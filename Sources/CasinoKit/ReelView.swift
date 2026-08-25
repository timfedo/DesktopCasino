import SwiftUI

/// One reel. `Animatable` gives us the interpolated scroll position on every frame, so the
/// body can pick which symbols are on screen — a plain `.offset` animation could only slide
/// a fixed set of views and would jump when the strip index changed.


/// The conformance is main-actor isolated: SwiftUI only ever drives `animatableData`
/// from the render loop on the main actor.
public struct ReelView: View, @MainActor Animatable {
    public var position: Double
    public var spinStart: Double
    public var spinTarget: Double

    public init(position: Double, spinStart: Double, spinTarget: Double) {
        self.position = position
        self.spinStart = spinStart
        self.spinTarget = spinTarget
    }

    public static let width: CGFloat = 62
    public static let stopHeight: CGFloat = 66

    public var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    public var body: some View {
        let stops = Reel.strip.count
        let base = Int(position.rounded(.down))

        ZStack {
            // Each symbol is placed by its absolute strip index, so its offset is a continuous
            // function of `position`: symbol `slot` sits at `(position - slot)` stop-heights,
            // and symbols travel downward as the reel turns.
            //
            // Deriving the offset from the *fractional* part instead looks equivalent but is
            // not: every time `position` crosses an integer the centre symbol jumps two stops
            // backwards. Motion blur hides that at speed, which is why it only showed up as the
            // final symbol popping into place in a single frame once the reel had settled.
            ForEach(-1...2, id: \.self) { k in
                let slot = base + k
                let index = ((slot % stops) + stops) % stops
                SymbolFace(symbol: Reel.strip[index])
                    .frame(width: Self.width, height: Self.stopHeight)
                    .offset(y: CGFloat(position - Double(slot)) * Self.stopHeight)
            }
        }
        .frame(width: Self.width, height: Self.stopHeight)
        .clipped()
        .blur(radius: 7 * pow(speedFraction, 0.7))
        .background(
            LinearGradient(colors: [.white.opacity(0.09), .white.opacity(0.03)],
                           startPoint: .top, endPoint: .bottom),
            in: .rect(cornerRadius: 8)
        )
        .overlay {
            // Glass shading so the strip reads as a physical drum.
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .clipShape(.rect(cornerRadius: 8))
    }

    /// 1 at the start of a spin, 0 once the reel has settled — a good stand-in for drum
    /// speed under an ease-out curve, and it drives the motion blur.
    private var speedFraction: Double {
        let span = spinTarget - spinStart
        guard span > 0.5 else { return 0 }
        return min(max(1 - (position - spinStart) / span, 0), 1)
    }
}
