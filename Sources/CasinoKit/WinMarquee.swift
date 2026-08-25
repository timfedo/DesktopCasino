import SwiftUI

/// The three-of-a-kind celebration: a barber-pole of slanted stripes travelling around the reel
/// frame, with the glow breathing in time.
///
/// Driven by `TimelineView(.animation)` rather than a `repeatForever` animation, so the stripe
/// travel and the pulse share one clock and cannot drift apart. It is only mounted while a triple
/// is on screen, so nothing redraws the rest of the time.
public struct WinMarquee: View {
    public let cornerRadius: CGFloat
    public let stripe: Color
    public let base: Color

    public init(cornerRadius: CGFloat, stripe: Color, base: Color) {
        self.cornerRadius = cornerRadius
        self.stripe = stripe
        self.base = base
    }

    /// Points of stripe travel per second.
    static let speed: Double = 46
    public var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            MarqueeFrame(
                cornerRadius: cornerRadius,
                stripe: stripe,
                base: base,
                phase: CGFloat(time * Self.speed),
                pulse: 0.5 + 0.5 * sin(time * 3.1)
            )
        }
    }
}

/// One frame of the marquee at an explicit `phase` and `pulse`.
///
/// Split out from `WinMarquee` so the drawing can be exercised without a clock: a snapshot of
/// something driven by `TimelineView(.animation)` would differ on every run.
public struct MarqueeFrame: View {
    public let cornerRadius: CGFloat
    public let stripe: Color
    public let base: Color
    /// Stripe travel along the outline, in points.
    public let phase: CGFloat
    /// Glow breathing, 0...1.
    public let pulse: Double

    public init(
        cornerRadius: CGFloat, stripe: Color, base: Color, phase: CGFloat, pulse: Double
    ) {
        self.cornerRadius = cornerRadius
        self.stripe = stripe
        self.base = base
        self.phase = phase
        self.pulse = pulse
    }

    private let stripeWidth: CGFloat = 4.2
    private let lineWidth: CGFloat = 3
    private let cornerTaper: CGFloat = 0.45

    public var body: some View {
            ZStack {
                // The halo is drawn as real blurred geometry rather than a `.shadow` on the
                // Canvas below. A shadow of canvas content barely registers against a dark card,
                // which made the pulse invisible; a blurred stroke is unambiguous and lets the
                // glow spread outside the frame as well as in.
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(stripe, lineWidth: lineWidth * 2.4)
                    .blur(radius: 4 + 8 * pulse)
                    .opacity(0.45 + 0.4 * pulse)

                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(base, lineWidth: lineWidth * 1.6)
                    .blur(radius: 7 + 9 * pulse)
                    .opacity(0.35 + 0.35 * pulse)

                marquee(phase: phase)
            }
    }

    private func marquee(phase: CGFloat) -> some View {
        Canvas { context, size in
            // Every stripe is placed by distance *along the outline*, so the pattern flows
            // continuously through the corners. Drawing each side as its own rotated band —
            // the obvious approach — leaves the stripes meeting at an angle in the corners
            // instead of curving round them.
            let outline = RoundedRectOutline(size: size, radius: cornerRadius)
            let length = outline.length
            guard length > 0 else { return }

            // The band is built as a tapered ribbon rather than a uniform stroke. Measured, a
            // constant-width band *is* the same 3pt through the corners — but a corner packs the
            // same length of band into far less visual area, so the ink concentrates and the
            // corner reads as heavier. Thinning the arcs slightly is the usual sign-painter's
            // correction; the taper follows sin(pi * progress) so it vanishes at the tangent
            // points and never steps.
            func halfWidth(at distance: CGFloat) -> CGFloat {
                let sample = outline.sample(at: distance)
                guard let progress = sample.arcProgress else { return lineWidth / 2 }
                return lineWidth / 2 * (1 - cornerTaper * sin(.pi * progress))
            }

            func edge(_ distance: CGFloat, outward: Bool) -> CGPoint {
                let sample = outline.sample(at: distance)
                let offset = halfWidth(at: distance)
                return sample.point.offset(by: sample.normal, times: outward ? offset : -offset)
            }

            let bandSteps = max(Int(length / 1.5), 64)
            var band = Path()
            for step in 0...bandSteps {
                let point = edge(length * CGFloat(step) / CGFloat(bandSteps), outward: true)
                if step == 0 { band.move(to: point) } else { band.addLine(to: point) }
            }
            for step in stride(from: bandSteps, through: 0, by: -1) {
                band.addLine(to: edge(length * CGFloat(step) / CGFloat(bandSteps), outward: false))
            }
            band.closeSubpath()

            context.clip(to: band)
            context.fill(band, with: .color(base))

            // Fitting a whole number of stripes to the perimeter keeps the pattern seamless
            // where it wraps; an arbitrary period leaves a visible join.
            let count = max(Int((length / (stripeWidth * 2)).rounded()), 8)
            let period = length / CGFloat(count)
            let width = period / 2
            // Generous: the band clip above decides the real extent.
            let half = lineWidth * 0.8

            // `slant` offsets the outer edge of a stripe along the *arc*, which on a corner is
            // also an angle. At a 12pt corner radius a 6.6pt slant rotates the stripe 31° between
            // its inner and outer edge, turning a thin bar into a broad wedge — the corners then
            // look far heavier than the straight runs. Keeping the slant near the band thickness
            // holds that rotation to a few degrees while still reading as a clear lean.
            let slant = lineWidth * 1.3

            // Stripes are subdivided ribbons rather than four-point quads, so their long edges
            // follow the corner arcs instead of cutting chords across them.
            let steps = max(Int(width / 1.2), 3)

            for index in 0..<count {
                let start = CGFloat(index) * period + phase
                var path = Path()

                for step in 0...steps {                     // outer edge, forwards
                    let sample = outline.sample(
                        at: start + slant + width * CGFloat(step) / CGFloat(steps)
                    )
                    let point = sample.point.offset(by: sample.normal, times: half)
                    if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                for step in stride(from: steps, through: 0, by: -1) {   // inner edge, back
                    let sample = outline.sample(
                        at: start + width * CGFloat(step) / CGFloat(steps)
                    )
                    path.addLine(to: sample.point.offset(by: sample.normal, times: -half))
                }

                path.closeSubpath()
                context.fill(path, with: .color(stripe))
            }
        }
    }
}
