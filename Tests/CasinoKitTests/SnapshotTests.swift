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
