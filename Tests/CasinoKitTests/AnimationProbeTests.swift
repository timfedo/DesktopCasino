import AppKit
import Foundation
import SwiftUI
import Testing

/// Records that this test process **cannot** observe a SwiftUI animation, which is why nothing
/// here tests one.
///
/// Worth an executable test rather than a comment, because the negative result is a trap. An
/// animation assertion that fails here looks exactly like a bug in the thing being animated —
/// "the height jumped from 376 to 643 with nothing in between" reads as a finding, and it is not
/// one. It was very nearly acted on.
///
/// The subject is a view with an explicitly animated frame height, which is the simplest thing
/// SwiftUI is guaranteed to interpolate. It is hosted the way the panel hosts the card, in a
/// window that is never ordered on screen — and with no display link, nothing ticks.
///
/// If this ever starts failing, that is good news: animations became observable, and the resize
/// and fade could then be tested properly instead of reasoned about.
@MainActor
@Suite("Animation probe")
struct AnimationProbeTests {
    private struct Subject: View {
        @State var tall = false

        var body: some View {
            Color.clear
                .frame(width: 50, height: tall ? 400 : 100)
                .onAppear {
                    // A turn's grace so the first layout is committed at the short height before
                    // anything starts moving away from it.
                    Task { @MainActor in
                        withAnimation(.linear(duration: 1.0)) { tall = true }
                    }
                }
        }
    }

    private static func pump() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

    @Test("Nothing here can see an animation mid-flight, so nothing here tests one")
    func animationsAreNotObservable() async throws {
        let host = NSHostingView(rootView: Subject())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 50, height: 400),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        // `NSWindow` defaults to releasing itself when closed, which a window held by a local
        // `let` must not do: closing it frees storage ARC is still holding, and the process took
        // a signal 11 after this test had already reported passing. `DesktopPanel` clears the
        // same flag for the same reason.
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }

        var heights: Set<CGFloat> = []
        for _ in 0..<40 {
            await Task.yield()
            Self.pump()
            heights.insert(host.fittingSize.height)
        }

        // Both ends, and nothing in between: the animation is only ever seen having finished.
        #expect(heights.contains(100))
        #expect(heights.contains(400))

        let between = heights.filter { $0 > 101 && $0 < 399 }
        #expect(
            between.isEmpty,
            """
            SwiftUI animations are now observable in this process — saw \(heights.sorted()). \
            The card's resize and fade can be tested directly rather than reasoned about, and \
            this test has done its job and can go.
            """
        )
    }
}
