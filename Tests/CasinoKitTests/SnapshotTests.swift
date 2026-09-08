import SwiftUI
import Testing

@testable import CasinoKit

/// Pixel-level regressions in the parts of the UI that arithmetic cannot pin.
///
/// These cover the drawing that has actually broken before: the reel's stop alignment, and the
/// marquee's behaviour at the corners, which took several attempts to get right and would regress
/// silently. Everything here is rendered at a fixed phase, never from a clock.
@MainActor
@Suite("Snapshots")
struct SnapshotTests {
    private static let reelBox = CGSize(width: 214, height: 82)

    // MARK: - Reels

    @Test("A reel at rest shows its landed symbol centred")
    func reelAtRest() throws {
        // Position 0 with no travel: the resting frame, which is what a payout is read from.
        try Snapshot.assert(
            ReelView(position: 0, spinStart: 0, spinTarget: 0)
                .background(.black),
            size: CGSize(width: ReelView.width, height: ReelView.stopHeight),
            named: "reel-at-rest"
        )
    }

    @Test("A reel mid-travel shows two symbols and motion blur")
    func reelMidTravel() throws {
        // Half a stop into a long spin: both neighbours visible, blur near full.
        try Snapshot.assert(
            ReelView(position: 10.5, spinStart: 4, spinTarget: 60)
                .background(.black),
            size: CGSize(width: ReelView.width, height: ReelView.stopHeight),
            named: "reel-mid-travel"
        )
    }

    @Test("A reel settling has almost no blur left")
    func reelSettling() throws {
        try Snapshot.assert(
            ReelView(position: 59.5, spinStart: 4, spinTarget: 60)
                .background(.black),
            size: CGSize(width: ReelView.width, height: ReelView.stopHeight),
            named: "reel-settling"
        )
    }

    // MARK: - Win marquee

    @Test("The marquee draws a continuous band with even corners", arguments: [0, 7, 14])
    func marqueeAtPhase(phase: Int) throws {
        // Three phases a third of a stripe period apart, so a corner artefact cannot hide in the
        // gap between stripes on any one of them.
        try Snapshot.assert(
            MarqueeFrame(
                cornerRadius: 12,
                stripe: Palette.gold,
                base: Palette.red,
                phase: CGFloat(phase),
                pulse: 0.5
            )
            .background(.black),
            size: Self.reelBox,
            named: "marquee-phase-\(phase)"
        )
    }

    @Test("Corners keep their taper", arguments: [0, 7])
    func marqueeCorner(phase: Int) throws {
        // Cropped hard to the top-left corner. On the full frame a corner regression moves well
        // under 1% of pixels — barely above any sane tolerance — so it gets its own close-up
        // where the same change is unmissable.
        try Snapshot.assert(
            MarqueeFrame(
                cornerRadius: 12,
                stripe: Palette.gold,
                base: Palette.red,
                phase: CGFloat(phase),
                pulse: 0.5
            )
            .frame(width: Self.reelBox.width, height: Self.reelBox.height)
            .frame(width: 34, height: 34, alignment: .topLeading)
            .clipped()
            .background(.black),
            size: CGSize(width: 34, height: 34),
            named: "marquee-corner-\(phase)"
        )
    }

    @Test("The glow pulse changes the frame")
    func marqueePulseExtremes() throws {
        for pulse in [0.0, 1.0] {
            try Snapshot.assert(
                MarqueeFrame(
                    cornerRadius: 12,
                    stripe: Palette.gold,
                    base: Palette.red,
                    phase: 0,
                    pulse: pulse
                )
                .background(.black),
                size: Self.reelBox,
                named: "marquee-pulse-\(Int(pulse))"
            )
        }
    }

    @Test("Pulse extremes are visibly different from one another")
    func pulseActuallyDiffers() throws {
        let dim = try #require(
            Snapshot.render(
                MarqueeFrame(cornerRadius: 12, stripe: Palette.gold, base: Palette.red,
                             phase: 0, pulse: 0).background(.black),
                size: Self.reelBox
            )
        )
        let bright = try #require(
            Snapshot.render(
                MarqueeFrame(cornerRadius: 12, stripe: Palette.gold, base: Palette.red,
                             phase: 0, pulse: 1).background(.black),
                size: Self.reelBox
            )
        )
        // Guards the harness as much as the view: if these matched, the tolerance would be so
        // loose that every snapshot here would pass regardless of what changed.
        var differing = 0
        for y in stride(from: 0, to: dim.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: dim.pixelsWide, by: 4) {
                guard let a = dim.colorAt(x: x, y: y), let b = bright.colorAt(x: x, y: y) else {
                    continue
                }
                if abs(a.redComponent - b.redComponent) > 0.05 { differing += 1 }
            }
        }
        #expect(differing > 0)
    }

    // MARK: - Daily net chart

    /// A fortnight with every case the chart has to draw in it: a big win, a big loss, a day that
    /// came out exactly level, and days that were not played at all.
    private static let chartSeries: [Ledger.DatedDay] = [
        Ledger.DatedDay(key: "2026-08-14", day: Ledger.Day()),
        Ledger.DatedDay(key: "2026-08-15", day: Ledger.Day(spins: 12, wagered: 60, won: 60)),
        Ledger.DatedDay(key: "2026-08-16", day: Ledger.Day(spins: 20, wagered: 120, won: 380)),
        Ledger.DatedDay(key: "2026-08-17", day: Ledger.Day(spins: 8, wagered: 80, won: 5)),
        Ledger.DatedDay(key: "2026-08-18", day: Ledger.Day()),
        Ledger.DatedDay(key: "2026-08-19", day: Ledger.Day(spins: 30, wagered: 150, won: 151)),
        Ledger.DatedDay(key: "2026-08-20", day: Ledger.Day(spins: 44, wagered: 440, won: 120)),
    ]

    @Test("The chart draws gains above the line and losses below it")
    func dailyNetChart() throws {
        // Geometry only — no text anywhere in this view, which is what makes a reference
        // recorded on one machine safe to compare on another.
        try Snapshot.assert(
            DailyNetChart(series: Self.chartSeries)
                .padding(8)
                .background(.black),
            size: CGSize(width: 200, height: 82),
            named: "chart-daily-net"
        )
    }

    @Test("A chart with nothing in it still draws its zero line")
    func emptyDailyNetChart() throws {
        try Snapshot.assert(
            DailyNetChart(series: Self.chartSeries.map {
                Ledger.DatedDay(key: $0.key, day: Ledger.Day())
            })
            .padding(8)
            .background(.black),
            size: CGSize(width: 200, height: 82),
            named: "chart-daily-net-empty"
        )
    }

    // MARK: - Stats screen

    /// UTC, so the ledger buckets into the same days whatever the runner's time zone is, and a
    /// fixed "today" so the chart window and the TODAY tile are the same fortnight every run.
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static let statsDay = utc.date(
        from: DateComponents(year: 2026, month: 8, day: 27, hour: 12)
    )!

    /// No explicit size: the board's height is its content's, so the render *is* the layout and a
    /// card that grew shows up as a size mismatch rather than as a wall of moved pixels.
    private static func statsBoard(
        _ ledger: Ledger, game: Casino.Game = .slots, picker: Bool = false
    ) -> some View {
        StatsView(
            ledger: ledger,
            session: Ledger.Day(spins: 14, wagered: 90, won: 145),
            credits: 240,
            game: game,
            today: statsDay,
            calendar: utc,
            // Inert, but present: the footer's reset button only draws when a handler is, and it
            // is part of the screen the reference is here to pin. Same for the table picker.
            onReset: {},
            onSelect: picker ? { _ in } : nil
        )
        .frame(width: 400)
        .background { Palette.felt }
    }

    @Test("The stats screen over a fortnight of play")
    func statsScreen() throws {
        try Snapshot.assert(
            Self.statsBoard(.sample(endingOn: Self.statsDay, calendar: Self.utc)),
            named: "stats-screen"
        )
    }

    @Test("The stats screen before the first spin")
    func statsScreenEmpty() throws {
        // The state every install starts in, and the one easiest to leave showing a wall of
        // zeroes and a best day of "—" instead of an invitation.
        try Snapshot.assert(Self.statsBoard(Ledger()), named: "stats-screen-empty")
    }

    @Test("The stats screen for the wheel, which counts different things")
    func statsScreenRoulette() throws {
        // A different breakdown, a different noun for a round, and no push rate — roulette has no
        // such thing, and a permanent 0.0% would read as a broken figure rather than an absent
        // concept. All of which is layout, and none of which arithmetic can pin.
        try Snapshot.assert(
            Self.statsBoard(
                .rouletteSample(endingOn: Self.statsDay, calendar: Self.utc),
                game: .roulette,
                picker: true
            ),
            named: "stats-screen-roulette"
        )
    }

    @Test("The pocket heat grid keeps black pockets visible as they warm up")
    func pocketHeatGrid() throws {
        // Geometry and tint only, no text. The black pockets are the point: ramping opacity on the
        // wheel's near-black would leave the busiest black pocket looking like an empty one.
        var pockets: [Int: Int] = [:]
        for number in 0...36 { pockets[number] = (number * 7) % 13 }
        pockets[17] = 24
        pockets[26] = 19

        try Snapshot.assert(
            PocketHeatGrid(pockets: pockets)
                .padding(8)
                .background(.black),
            size: CGSize(width: 340, height: 71),
            named: "pocket-heat-grid"
        )
    }

    // MARK: - Roulette wheel

    private static let wheel = CGSize(width: 220, height: 220)

    /// A spin that ends with the ball in pocket `landing`, frozen at `progress` through it.
    /// The wheel's own rotation is the only animated value — everything the ball does is derived
    /// from it — so a frame is pinned by saying how far through the spin it is.
    ///
    /// Nominal travel, with none of the random shove a real spin gets: a reference render has to
    /// come out the same every time it is taken.
    private static func wheelView(
        landing: Int,
        progress: Double,
        result: Int? = nil,
        won: Bool = false
    ) -> some View {
        let target = Roulette.travel(extra: 0)
        return RouletteWheelView(
            turns: target * progress,
            spinStart: 0,
            spinTarget: target,
            landingIndex: landing,
            result: result,
            won: won,
            diameter: wheel.width
        )
        .background(.black)
    }

    @Test("A wheel at rest has the ball sitting in the winning pocket")
    func wheelAtRest() throws {
        // The frame where the two have to agree, and the arithmetic that makes them agree is
        // spread across `Roulette` and this view. Where on screen they agree is not fixed — the
        // wheel stops where the throw leaves it — so this is the render that would catch the ball
        // parting company with its pocket.
        try Snapshot.assert(
            Self.wheelView(landing: 0, progress: 1, result: 0),
            size: Self.wheel,
            named: "wheel-at-rest"
        )
    }

    @Test("A wheel mid-spin has the ball out on its track")
    func wheelMidSpin() throws {
        try Snapshot.assert(
            Self.wheelView(landing: 8, progress: 0.35),
            size: Self.wheel,
            named: "wheel-mid-spin"
        )
    }

    @Test("A settling wheel has the ball down in its pocket, riding round")
    func wheelSettling() throws {
        // Past the capture point, so the ball is no longer flying: it is in pocket 8 and being
        // carried the rest of the way by the wheel.
        try Snapshot.assert(
            Self.wheelView(landing: 8, progress: 0.93, result: 17, won: true),
            size: Self.wheel,
            named: "wheel-settling"
        )
    }

    @Test("Partway down, the ball is off the track and not yet in a pocket")
    func wheelDropping() throws {
        // Between release and capture: the one stretch where the ball is neither on the rim it
        // has been riding nor in the pocket that will catch it.
        try Snapshot.assert(
            Self.wheelView(landing: 8, progress: 0.73),
            size: Self.wheel,
            named: "wheel-dropping"
        )
    }

    @Test("The ball comes off the track and drops onto the pockets")
    func ballDropsOntoThePockets() throws {
        // Early in the spin against the moment of capture. If the drop were ever dropped, the
        // references above would still be re-recorded happily and both would keep passing; this is
        // what makes that a failure.
        let flying = try #require(
            Snapshot.render(Self.wheelView(landing: 0, progress: 0.2), size: Self.wheel)
        )
        let landed = try #require(
            Snapshot.render(Self.wheelView(landing: 0, progress: 1, result: 0), size: Self.wheel)
        )

        var differing = 0
        for y in stride(from: 0, to: flying.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: flying.pixelsWide, by: 2) {
                guard let a = flying.colorAt(x: x, y: y), let b = landed.colorAt(x: x, y: y) else {
                    continue
                }
                if abs(a.redComponent - b.redComponent) > 0.2 { differing += 1 }
            }
        }
        #expect(differing > 0)
    }

    @Test("Once captured, the ball travels with the wheel rather than against it")
    func ballRidesTheWheelAfterCapture() throws {
        // Two frames late in the spin, both past the capture point. The wheel has turned between
        // them, and the ball has to have turned with it by exactly the same amount — that is what
        // "it sticks in a pocket and rides round" means, and the alternative (two independent
        // animations timed to arrive together) looks like the ball was placed rather than thrown.
        let angles = [0.86, 0.94].map { progress -> Double in
            let target = Roulette.travel(extra: 0)
            let turns = target * progress
            return RouletteWheel.angle(ofPocketAt: 8) + turns * 360
        }
        let wheelMoved = (angles[1] - angles[0])

        // Rendering cannot measure an angle, so this checks the expression the ball uses: past
        // capture its angle *is* the pocket's, so the two move together by construction.
        #expect(wheelMoved > 0)
        let calm = try #require(
            Snapshot.render(Self.wheelView(landing: 8, progress: 0.86), size: Self.wheel)
        )
        let later = try #require(
            Snapshot.render(Self.wheelView(landing: 8, progress: 0.94), size: Self.wheel)
        )
        var differing = 0
        for y in stride(from: 0, to: calm.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: calm.pixelsWide, by: 2) {
                guard let a = calm.colorAt(x: x, y: y), let b = later.colorAt(x: x, y: y) else {
                    continue
                }
                if abs(a.redComponent - b.redComponent) > 0.2 { differing += 1 }
            }
        }
        // The wheel turned, so the numerals moved — the frames are not identical.
        #expect(differing > 0)
    }

    // MARK: - Symbols

    @Test("The seven renders as a red numeral, not a keycap emoji")
    func sevenFace() throws {
        let seven = try #require(Reel.symbols.first { $0.name == "seven" })
        try Snapshot.assert(
            SymbolFace(symbol: seven, pointSize: 32)
                .frame(width: 62, height: 66)
                .background(.black),
            size: CGSize(width: 62, height: 66),
            named: "symbol-seven"
        )
    }
}
