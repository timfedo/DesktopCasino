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

    private static func machine(
        _ names: [String], credits: Int, bet: Int = 5, spinning: Bool = false
    ) -> SlotMachine {
        let machine = SlotMachine(defaults: scratchDefaults())
        machine.stage(landings: stops(names), credits: credits, bet: bet, spinning: spinning)
        return machine
    }

    /// A machine nobody has played yet: 100 credits, the default 5 chip, and the seeded opening
    /// symbols a fresh install shows.
    private static func freshMachine() -> SlotMachine {
        SlotMachine(defaults: scratchDefaults())
    }

    /// The card exactly as the panel hosts it. No frame: its height comes from its content, and
    /// letting the render size itself is what makes a taller stack a test failure.
    private static func window(_ machine: SlotMachine, hovered: Bool = false) -> some View {
        CasinoView(machine: machine, alwaysHovered: hovered)
    }

    // MARK: - States

    @Test("The window at rest, before the first spin")
    func idle() throws {
        try Snapshot.assert(Self.window(Self.freshMachine()), named: "window-idle")
    }

    @Test("Hovering reveals the close and placement controls")
    func hovered() throws {
        try Snapshot.assert(
            Self.window(Self.freshMachine(), hovered: true), named: "window-hovered"
        )
    }

    @Test("Mid-spin: drums blurred and staggered, stake already gone")
    func spinning() throws {
        // Staged partway through the travel, so the three reels sit at three different speeds —
        // the same left-to-right stagger a real spin shows, and the only state in which the
        // motion blur appears in the assembled card at all.
        try Snapshot.assert(
            Self.window(Self.machine(["seven", "seven", "diamond"], credits: 95, spinning: true)),
            named: "window-spinning"
        )
    }

    @Test("A losing spin gets no border, no glow and no figure")
    func noWin() throws {
        try Snapshot.assert(
            Self.window(Self.machine(["cherry", "lemon", "bell"], credits: 95)),
            named: "window-no-win"
        )
    }

    @Test("A 1x pair is a push, and is drawn as one")
    func push() throws {
        // Cherry, lemon and bell pairs pay the stake straight back, and between them that is 39%
        // of all spins. Dressing those up in the winner's gold is the textbook loss disguised as
        // a win, so the push has its own muted treatment and a ±0 — which only a picture pins.
        try Snapshot.assert(
            Self.window(Self.machine(["cherry", "cherry", "lemon"], credits: 100)),
            named: "window-push"
        )
    }

    @Test("A 2x pair earns the gold border, the glow and a net figure")
    func pairWin() throws {
        try Snapshot.assert(
            Self.window(Self.machine(["seven", "seven", "bell"], credits: 125, bet: 25)),
            named: "window-pair-win"
        )
    }

    @Test("Three of a kind keeps the gold treatment")
    func triple() throws {
        // No marquee here, deliberately. It is mounted from `.task`, which an offscreen render
        // never runs, and it animates off a clock, which a still could not pin anyway — the
        // marquee has its own fixed-phase snapshots. What this fixes is the frame underneath:
        // gold, and not the jackpot's cyan.
        try Snapshot.assert(
            Self.window(Self.machine(["seven", "seven", "seven"], credits: 590, bet: 10)),
            named: "window-triple"
        )
    }

    @Test("The jackpot turns the frame cyan")
    func jackpot() throws {
        try Snapshot.assert(
            Self.window(Self.machine(["diamond", "diamond", "diamond"], credits: 1090, bet: 10)),
            named: "window-jackpot"
        )
    }

    @Test("An empty balance offers a refill instead of a spin")
    func broke() throws {
        try Snapshot.assert(
            Self.window(Self.machine(["cherry", "lemon", "bell"], credits: 0)),
            named: "window-broke"
        )
    }

    @Test("Stakes above the balance are dimmed out")
    func lowBalance() throws {
        // Seven credits: the 1 and 5 chips are still playable, the 10 and 25 are not.
        try Snapshot.assert(
            Self.window(Self.machine(["cherry", "lemon", "seven"], credits: 7)),
            named: "window-low-balance"
        )
    }

    // MARK: - Window controls, close up

    private static let controlsCrop = CGSize(width: 84, height: 40)

    /// The top-left corner of the card, cropped hard. `fixedSize` first, so the card lays itself
    /// out at the height it would really have rather than squeezing into the crop.
    private static func controlsCorner(hovered: Bool) -> some View {
        window(freshMachine(), hovered: hovered)
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
        let image = try #require(Snapshot.render(Self.window(Self.freshMachine())))
        // The panel takes its height from the card's fitting size, so height is the card's to
        // choose — and the reference images above pin whatever it chose. Width is not: the card
        // is handed `DesktopPanel.size.width` and a mismatch would clip or letterbox it.
        #expect(image.pixelsWide == Int(DesktopPanel.size.width) * 2)
        #expect(image.pixelsHigh > Int(ReelView.stopHeight) * 2)
    }
}
