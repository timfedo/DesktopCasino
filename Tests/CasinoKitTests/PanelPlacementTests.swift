import AppKit
import Testing

@testable import DesktopCasino

/// Where the window lands when the card changes size under it.
///
/// The roulette table is the best part of two hundred points taller than three reels, so changing
/// tables resizes the window — and a resize is the one moment a widget that lives in the corner of
/// the screen can walk off the edge of it.
@MainActor
@Suite("Panel placement")
struct PanelPlacementTests {
    /// A screen with a menu bar's worth of chrome taken off the top, in AppKit's bottom-left
    /// coordinates.
    private static let screen = NSRect(x: 0, y: 0, width: 1440, height: 875)

    private static func clamp(_ origin: NSPoint, _ size: NSSize) -> NSPoint {
        DesktopPanel.clamped(origin: origin, size: size, in: screen)
    }

    private static let slots = NSSize(width: 264, height: 405)
    private static let roulette = NSSize(width: 264, height: 568)

    @Test("A window already inside the screen is left exactly where it is")
    func insideIsUntouched() {
        let origin = NSPoint(x: 1144, y: 32)
        #expect(Self.clamp(origin, Self.slots) == origin)
        #expect(Self.clamp(origin, Self.roulette) == origin)
    }

    @Test("Growing upward near the top of the screen slides the window back down")
    func growingAtTheTopComesBackDown() {
        // High enough that the slot machine still fits and the wheel does not: anchored at the
        // bottom-left, switching tables would poke the taller card out over the menu bar.
        let origin = NSPoint(x: 40, y: 400)
        #expect(Self.clamp(origin, Self.slots) == origin)

        let corrected = Self.clamp(origin, Self.roulette)
        #expect(corrected.x == origin.x)
        #expect(corrected.y == Self.screen.maxY - Self.roulette.height)
        #expect(corrected.y + Self.roulette.height <= Self.screen.maxY)
    }

    @Test("A window off the right or bottom edge is pulled back on")
    func overhangingEdgesArePulledIn() {
        let corner = Self.clamp(NSPoint(x: 1400, y: -60), Self.slots)
        #expect(corner.x == Self.screen.maxX - Self.slots.width)
        #expect(corner.y == Self.screen.minY)
    }

    @Test("A card taller than the screen keeps its top-left corner on, not crashed on")
    func oversizedIsPinnedRatherThanCrashed() {
        // The bounds cross over here — `maxY - height` is below `minY` — and clamping into a
        // reversed range traps rather than misplaces. Whichever half has to go, it is not the one
        // with the close button on it.
        let huge = NSSize(width: 2000, height: 1200)
        let pinned = Self.clamp(NSPoint(x: 300, y: 300), huge)
        #expect(pinned.x == Self.screen.minX)
        #expect(pinned.y == Self.screen.maxY - huge.height)
        // Which is to say: the top edge is exactly the top of the screen.
        #expect(pinned.y + huge.height == Self.screen.maxY)
    }
}
