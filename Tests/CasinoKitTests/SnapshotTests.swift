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
    private static func statsBoard(_ ledger: Ledger) -> some View {
        StatsView(
            ledger: ledger,
            session: Ledger.Day(spins: 14, wagered: 90, won: 145),
            credits: 240,
            today: statsDay,
            calendar: utc,
            // Inert, but present: the footer's reset button only draws when a handler is, and it
            // is part of the screen the reference is here to pin.
            onReset: {}
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
