import AppKit
import SwiftUI
import Foundation
import Testing

@testable import CasinoKit
@testable import DesktopCasino

/// That the window actually follows the card.
///
/// The card reports its height out of the layout and the panel resizes to match. Both halves are
/// straightforward; the join between them is not, because it depends on SwiftUI delivering a
/// preference change through an `NSHostingView` — and if it silently did not, the roulette table
/// would simply be drawn clipped inside a slot machine's window. Nothing else here would notice.
///
/// The panel is never ordered on screen. It is built, measured and closed.
@MainActor
@Suite("Panel resize")
struct PanelResizeTests {
    private static func scratchDefaults() -> UserDefaults {
        let suite = "DesktopCasinoTests.panel.\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    /// Drains the main run loop. Not `async`, because `run(until:)` is unavailable from an async
    /// context — which is the point: this is the synchronous pass SwiftUI's update is scheduled on.
    private static func pump() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

    /// Gives SwiftUI its update pass, then AppKit its layout pass, until the window has stopped
    /// moving.
    ///
    /// Waited for rather than counted out. A table change animates and the window follows it frame
    /// by frame, so "settled" is a state, not a duration — and pumping a fixed number of times
    /// measures the machine as much as the code. Counted out, this passed on an idle machine and
    /// failed on a busy one, reporting a window a single point short of where it ends up, which is
    /// exactly the tail of an animation caught before it finished.
    ///
    /// Still floored at the old count, because a window that has not started moving yet is also
    /// "not moving", and given a deadline, so a resize that genuinely never lands fails rather
    /// than hangs.
    private static func settle(_ panel: NSPanel) async {
        for _ in 0..<45 {
            await Task.yield()
            pump()
        }
        var still = 0
        var last = panel.frame
        let deadline = Date().addingTimeInterval(10)
        while still < 8, Date() < deadline {
            await Task.yield()
            pump()
            if panel.frame == last {
                still += 1
            } else {
                still = 0
                last = panel.frame
            }
        }
    }

    @Test("Changing tables opens the window downward, holding its top edge")
    func windowFollowsTheCard() async throws {
        let casino = Casino(defaults: Self.scratchDefaults())
        casino.select(.slots)

        let ref = PanelRef()
        let panel = DesktopPanel(content: CasinoView(casino: casino, panelRef: ref))
        ref.panel = panel
        defer { panel.close() }

        await Self.settle(panel)

        // Parked with its top at the top of the screen, so there is a whole screen height below
        // for the taller table to open into and the clamp never comes into it. Anywhere lower and
        // this would be testing `clampToScreen` instead of the anchor.
        let area = try #require(
            (panel.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
        )
        panel.setFrameOrigin(NSPoint(x: area.minX + 40, y: area.maxY - panel.frame.height))
        await Self.settle(panel)

        let atSlots = panel.frame
        #expect(atSlots.height > 0)

        // The picker changes table with animations off, so the card resizes in one step and the
        // window with it. Driven here *with* an animation anyway, which is the harder case: the
        // window then follows an interpolated height, and the last frame of a spring is a very
        // small difference — small enough for `matchHeight`, which ignores anything under half a
        // point, to leave the window short of where the card ended up. It must land exactly
        // either way.
        withAnimation(.smooth(duration: 0.32)) { casino.select(.roulette) }
        await Self.settle(panel)

        let atRoulette = panel.frame
        #expect(atRoulette.height > atSlots.height, "the window did not grow for the wheel")
        #expect(atRoulette.width == DesktopPanel.size.width)
        // Anchored at the top, so the card opens *downward*: the top edge is exactly where it was
        // and the bottom has moved down. That is what keeps the picker you just clicked, and the
        // credits above it, from leaping somewhere else.
        #expect(abs(atRoulette.maxY - atSlots.maxY) < 0.5, "the top edge moved")
        #expect(atRoulette.minY < atSlots.minY, "the card did not open downward")
        #expect(atRoulette.origin.x == atSlots.origin.x)

        // And back the way the picker really does it, in one step.
        casino.select(.slots)
        await Self.settle(panel)
        #expect(panel.frame.height == atSlots.height, "the window did not shrink back")
    }
}
