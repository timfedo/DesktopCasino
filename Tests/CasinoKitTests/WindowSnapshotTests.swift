import Foundation
import SwiftUI
import Testing

@testable import CasinoKit
@testable import DesktopCasino

/// Pixel-level regressions in the whole card — the window as `DesktopPanel` actually hosts it.
///
/// The component snapshots next door pin the pieces arithmetic cannot: a reel's stop alignment,
/// the marquee's corners. These pin the *assembly*, which is where the cheap breakages live —
/// a stack that grew and pushed the panel taller, a win drawn like a push, chrome that stopped
/// hiding itself. None of it is reachable from the unit tests, because none of it is a number.
///
/// Every state is staged rather than played for, so nothing here waits on a clock or a die roll.
@MainActor
@Suite("Window snapshots")
struct WindowSnapshotTests {

    // MARK: - Staging

    /// A scratch domain, so composing a machine for a picture never reads or writes real credits.
    private static func scratchDefaults() -> UserDefaults {
        let suite = "DesktopCasinoTests.window.\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    /// Strip stops carrying the named symbols, preferring a distinct stop per reel — which is
    /// what a spin usually lands, since most symbols occupy several stops.
    ///
    /// Named rather than hard-coded because the strip is a seeded shuffle: which index carries
    /// which symbol is an implementation detail, and "two sevens and a bell" is what the test
    /// actually means.
    private static func stops(_ names: [String]) -> [Int] {
        var used: Set<Int> = []
        return names.map { name in
            let carrying = Reel.strip.indices.filter { Reel.strip[$0].name == name }
            precondition(!carrying.isEmpty, "no strip stop carries \(name)")
            let stop = carrying.first { !used.contains($0) } ?? carrying[0]
            used.insert(stop)
            return stop
        }
    }

    /// A house staged at the slot machine.
    private static func slots(
        _ names: [String], credits: Int, bet: Int = 5, spinning: Bool = false
    ) -> Casino {
        let casino = Casino(defaults: scratchDefaults())
        casino.select(.slots)
        casino.slots.stage(landings: stops(names), credits: credits, bet: bet, spinning: spinning)
        return casino
    }

    /// A house staged at the roulette table. Credits are staged on the bank rather than the table,
    /// because the balance belongs to neither game — which is the whole reason the picker sits
    /// above the readout rather than below it.
    private static func roulette(
        _ number: Int,
        bets: [RouletteBet: Int],
        credits: Int,
        stake: Int = 5,
        spinning: Bool = false
    ) -> Casino {
        let casino = Casino(defaults: scratchDefaults())
        casino.select(.roulette)
        casino.bank.stage(credits: credits)
        casino.roulette.stage(number: number, bets: bets, stake: stake, spinning: spinning)
        return casino
    }

    /// A house nobody has played yet: 100 credits, the default 5 chip, and the seeded opening
    /// symbols a fresh install shows.
    private static func fresh(withTable table: Casino.Game = .slots) -> Casino {
        let casino = Casino(defaults: scratchDefaults())
        casino.select(table)
        return casino
    }

    /// The card exactly as the panel hosts it. No frame: its height comes from its content, and
    /// letting the render size itself is what makes a taller stack a test failure.
    private static func window(_ casino: Casino, hovered: Bool = false) -> some View {
        CasinoView(casino: casino, alwaysHovered: hovered, isStill: true)
    }

    // MARK: - States

    @Test("The window at rest, before the first spin")
    func idle() throws {
        try Snapshot.assert(Self.window(Self.fresh()), named: "window-idle")
    }

    @Test("Hovering reveals the close and placement controls")
    func hovered() throws {
        try Snapshot.assert(
            Self.window(Self.fresh(), hovered: true), named: "window-hovered"
        )
    }

    @Test("Mid-spin: drums blurred and staggered, stake already gone")
    func spinning() throws {
        // Staged partway through the travel, so the three reels sit at three different speeds —
        // the same left-to-right stagger a real spin shows, and the only state in which the
        // motion blur appears in the assembled card at all.
        try Snapshot.assert(
            Self.window(Self.slots(["seven", "seven", "diamond"], credits: 95, spinning: true)),
            named: "window-spinning"
        )
    }

    @Test("A losing spin gets no border, no glow and no figure")
    func noWin() throws {
        try Snapshot.assert(
            Self.window(Self.slots(["cherry", "lemon", "bell"], credits: 95)),
            named: "window-no-win"
        )
    }

    @Test("A 1x pair is a push, and is drawn as one")
    func push() throws {
        // Cherry, lemon and bell pairs pay the stake straight back, and between them that is 39%
        // of all spins. Dressing those up in the winner's gold is the textbook loss disguised as
        // a win, so the push has its own muted treatment and a ±0 — which only a picture pins.
        try Snapshot.assert(
            Self.window(Self.slots(["cherry", "cherry", "lemon"], credits: 100)),
            named: "window-push"
        )
    }

    @Test("A 2x pair earns the gold border, the glow and a net figure")
    func pairWin() throws {
        try Snapshot.assert(
            Self.window(Self.slots(["seven", "seven", "bell"], credits: 125, bet: 25)),
            named: "window-pair-win"
        )
    }

    @Test("Three of a kind keeps the gold treatment")
    func triple() throws {
        // No marquee here, deliberately: it animates off a clock, so a still could only pin an
        // arbitrary phase — the marquee has its own fixed-phase snapshots. That used to rest on
        // an offscreen render never running the `.task` that mounts it, which turned out to be
        // true on the CI runner and false on at least one Mac, so `isStill` now says it outright.
        // What this fixes is the frame underneath: gold, and not the jackpot's cyan.
        try Snapshot.assert(
            Self.window(Self.slots(["seven", "seven", "seven"], credits: 590, bet: 10)),
            named: "window-triple"
        )
    }

    @Test("The jackpot turns the frame cyan")
    func jackpot() throws {
        try Snapshot.assert(
            Self.window(Self.slots(["diamond", "diamond", "diamond"], credits: 1090, bet: 10)),
            named: "window-jackpot"
        )
    }

    @Test("An empty balance offers a refill instead of a spin")
    func broke() throws {
        try Snapshot.assert(
            Self.window(Self.slots(["cherry", "lemon", "bell"], credits: 0)),
            named: "window-broke"
        )
    }

    @Test("Stakes above the balance are dimmed out")
    func lowBalance() throws {
        // Seven credits: the 1 and 5 chips are still playable, the 10 and 25 are not.
        try Snapshot.assert(
            Self.window(Self.slots(["cherry", "lemon", "seven"], credits: 7)),
            named: "window-low-balance"
        )
    }

    // MARK: - The roulette table

    @Test("The roulette table, waiting for a bet")
    func rouletteIdle() throws {
        // Nothing spun yet: the wheel parked on the zero, an em dash in the hub, and RED — the
        // bet a fresh install opens on.
        try Snapshot.assert(Self.window(Self.fresh(withTable: .roulette)), named: "roulette-idle")
    }

    @Test("A straight-up win: gold hub, gold glow, and 35 net on a 36x payout")
    func rouletteStraightWin() throws {
        // The one that pays 36×, which is the whole reason the number stepper is on the felt. Also
        // the case where gross and net differ most: a 1 chip returns 36 and gains 35.
        try Snapshot.assert(
            Self.window(Self.roulette(17, bets: [.straight(17): 1], credits: 136, stake: 1)),
            named: "roulette-straight-win"
        )
    }

    @Test("Zero takes the even-money bets with it")
    func rouletteZero() throws {
        // The house edge, drawn: red loses to the green pocket like everything else outside a
        // straight-up on the zero itself.
        try Snapshot.assert(
            Self.window(Self.roulette(0, bets: [.red: 5], credits: 95)),
            named: "roulette-zero"
        )
    }

    @Test("Mid-spin: ball out on its track, felt dimmed, stake already gone")
    func rouletteSpinning() throws {
        // Frozen partway through: the ball is still on the outer track and has not yet spiralled
        // down onto the pockets, which is the only state that shows the two radii apart.
        try Snapshot.assert(
            Self.window(Self.roulette(26, bets: [.dozen(3): 10], credits: 90, stake: 10, spinning: true)),
            named: "roulette-spinning"
        )
    }

    @Test("A corner's chip sits on the intersection, inside an outline round its four numbers")
    func rouletteCorner() throws {
        // Where the chip is *is* the bet: a corner belongs to no one cell, so it is drawn on the
        // point the four meet, exactly as you would place it at a table, and the outline says
        // which four. Also catches the felt losing its cell borders, without which the black
        // numbers vanish into the card.
        try Snapshot.assert(
            Self.window(Self.roulette(5, bets: [.inside([1, 2, 4, 5]): 10], credits: 130, stake: 10)),
            named: "roulette-corner"
        )
    }

    @Test("Chips on overlapping shapes each sit on their own numbers")
    func rouletteOverlappingChips() throws {
        // A corner, a split inside it, and another split alongside — three chips of two different
        // widths, close enough that a misplaced one is obvious.
        //
        // This is the case that broke, and nothing else here covered it. Chips are positioned by
        // offset from the grid's corner, and handing the overlay a bare `ForEach` had SwiftUI wrap
        // them in a centre-aligned stack sized to the largest: the one-column splits came out
        // half a cell to the right of the numbers they were on. A single chip is the largest child
        // and has nothing to be centred against, so every existing snapshot passed.
        try Snapshot.assert(
            Self.window(
                Self.roulette(
                    17,
                    bets: [
                        .inside([13, 14, 16, 17]): 5,
                        .inside([16, 17]): 5,
                        .inside([20, 21]): 5,
                    ],
                    credits: 120,
                    stake: 5
                )
            ),
            named: "roulette-overlapping-chips"
        )
    }

    @Test("An outside bet lights every number it covers")
    func rouletteOutsideCoverage() throws {
        // Eighteen cells lit at once. The quickest way to learn what "2nd 12" actually covers is
        // to see it, which is why the felt lights an outside bet's numbers and not just its box.
        try Snapshot.assert(
            Self.window(Self.roulette(20, bets: [.dozen(2): 5], credits: 115, stake: 5)),
            named: "roulette-dozen"
        )
    }

    @Test("An empty balance at the wheel offers a refill too")
    func rouletteBroke() throws {
        // The felt stays live-looking but the line says why the gold button changed, which is the
        // same contract the slot machine's empty state has.
        try Snapshot.assert(
            Self.window(Self.roulette(0, bets: [.red: 5], credits: 0)),
            named: "roulette-broke"
        )
    }

    @Test("Switching tables changes the height of the window")
    func tablesAreDifferentHeights() throws {
        // The panel resizes to follow the card, and the card is a different size per table. If
        // these ever matched, `matchHeight` would be dead code and nobody would notice.
        let slots = try #require(Snapshot.render(Self.window(Self.fresh())))
        let roulette = try #require(Snapshot.render(Self.window(Self.fresh(withTable: .roulette))))

        #expect(slots.pixelsWide == roulette.pixelsWide)
        #expect(roulette.pixelsHigh > slots.pixelsHigh)
    }

    // MARK: - Window controls, close up

    private static let controlsCrop = CGSize(width: 84, height: 40)

    /// The top-left corner of the card, cropped hard. `fixedSize` first, so the card lays itself
    /// out at the height it would really have rather than squeezing into the crop.
    private static func controlsCorner(hovered: Bool) -> some View {
        window(fresh(), hovered: hovered)
            .fixedSize()
            .frame(width: controlsCrop.width, height: controlsCrop.height, alignment: .topLeading)
            .clipped()
    }

    @Test("The window controls, up close", arguments: [false, true])
    func controls(hovered: Bool) throws {
        // Both buttons are 13pt across. On the whole card, changing one moves about a tenth of a
        // percent of the pixels — under any tolerance worth having. Cropped to the corner they
        // own a twentieth of the frame and the same change is unmissable. Same trick as the
        // marquee corners.
        try Snapshot.assert(
            Self.controlsCorner(hovered: hovered),
            size: Self.controlsCrop,
            named: "window-controls-\(hovered ? "hovered" : "idle")"
        )
    }

    /// The opposite corner, where the stats button lives on its own.
    private static func statsCorner(hovered: Bool) -> some View {
        window(fresh(), hovered: hovered)
            .fixedSize()
            .frame(width: controlsCrop.width, height: controlsCrop.height, alignment: .topTrailing)
            .clipped()
    }

    @Test("The stats button, up close", arguments: [false, true])
    func statsControl(hovered: Bool) throws {
        // Same reasoning as the controls crop: one 13pt button is invisible against the whole
        // card. It gets its own close-up so that losing it, or lighting it at the wrong time,
        // fails loudly.
        try Snapshot.assert(
            Self.statsCorner(hovered: hovered),
            size: Self.controlsCrop,
            named: "window-stats-\(hovered ? "hovered" : "idle")"
        )
    }

    @Test("The chrome really is hidden until the pointer arrives")
    func chromeIsHiddenUntilHovered() throws {
        let bare = try #require(
            Snapshot.render(Self.controlsCorner(hovered: false), size: Self.controlsCrop)
        )
        let lit = try #require(
            Snapshot.render(Self.controlsCorner(hovered: true), size: Self.controlsCrop)
        )

        // Guards the pair of snapshots above as much as the view. If hover ever stopped doing
        // anything, both references would be re-recorded identical and both would keep passing
        // for ever — a snapshot suite's quietest failure mode.
        var differing = 0
        for y in stride(from: 0, to: bare.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bare.pixelsWide, by: 2) {
                guard let a = bare.colorAt(x: x, y: y), let b = lit.colorAt(x: x, y: y) else {
                    continue
                }
                if abs(a.redComponent - b.redComponent) > 0.05 { differing += 1 }
            }
        }
        #expect(differing > 0)
    }

    // MARK: - Fit

    @Test("The card renders at exactly the width the panel gives it")
    func cardFillsThePanelWidth() throws {
        let image = try #require(Snapshot.render(Self.window(Self.fresh())))
        // The panel takes its height from the card's fitting size, so height is the card's to
        // choose — and the reference images above pin whatever it chose. Width is not: the card
        // is handed `DesktopPanel.size.width` and a mismatch would clip or letterbox it.
        #expect(image.pixelsWide == Int(DesktopPanel.size.width) * 2)
        #expect(image.pixelsHigh > Int(ReelView.stopHeight) * 2)
    }
}
