import SwiftUI

/// The wheel and its ball.
///
/// Three layers, and the split matters. The **disc** is static drawing under a `rotationEffect`,
/// so SwiftUI renders the 37 wedges and their numerals once and then only re-transforms them —
/// putting the Canvas inside an `Animatable` view instead would redraw all of it every frame.
/// The **ball** is animatable, because it is the one thing that needs the interpolated value: it
/// falls off the track, bounces, and is then carried round by the wheel, none of which can be read
/// off a transform. The **hub** does not turn at all.
public struct RouletteWheelView: View {
    /// Wheel rotation in turns, interpolated. Whole turns are invisible; the fraction is where it
    /// happens to have come to rest.
    public var turns: Double
    /// Both ends of the spin, so the ball can tell how far through it is. Equal when nothing is
    /// spinning, which the ball reads as "settled".
    public var spinStart: Double
    public var spinTarget: Double
    /// The pocket the ball ends up in, as an index into `RouletteWheel.order`.
    public var landingIndex: Int
    /// Where the ball is sitting as the spin begins, in clockwise degrees from the top. It rests
    /// in the *last* winning pocket, wherever the wheel left that — there is no marker to park it
    /// against any more, so its starting angle has to be carried rather than assumed to be zero.
    public var ballStart: Double
    /// The number in the hub, or `nil` before the first result of the session.
    public var result: Int?
    /// Lights the hub gold. Set when the last result paid.
    public var won: Bool
    public var diameter: CGFloat

    public init(
        turns: Double,
        spinStart: Double = 0,
        spinTarget: Double = 0,
        landingIndex: Int = 0,
        ballStart: Double = 0,
        result: Int?,
        won: Bool = false,
        diameter: CGFloat
    ) {
        self.turns = turns
        self.spinStart = spinStart
        self.spinTarget = spinTarget
        self.landingIndex = landingIndex
        self.ballStart = ballStart
        self.result = result
        self.won = won
        self.diameter = diameter
    }

    /// Every radius on the wheel, as a fraction of its radius. Kept in one place because they have
    /// to stay in order — the ball's resting orbit sits inside the pocket ring, which sits inside
    /// the track it spins in, which sits inside the rim.
    enum Ring {
        static let rimOuter: CGFloat = 1.0
        static let rimInner: CGFloat = 0.90
        /// Where the ball runs while it is still travelling.
        static let ballTrack: CGFloat = 0.845
        static let pocketOuter: CGFloat = 0.80
        /// The numerals sit near the outer edge of the pockets, where there is the most arc to
        /// write across: 37 of them around a 172pt wheel leaves about 10pt each, and any further
        /// in they start to collide.
        static let numerals: CGFloat = 0.705
        /// Where the ball comes to rest: inboard of the numerals, on the floor of the pocket,
        /// which is where it ends up on a real wheel too.
        static let ballRest: CGFloat = 0.58
        static let pocketInner: CGFloat = 0.44
        static let hub: CGFloat = 0.30
    }

    public var body: some View {
        ZStack {
            disc
                .rotationEffect(.degrees(turns * 360))
            hub
            RouletteBall(
                wheelTurns: turns,
                spinStart: spinStart,
                spinTarget: spinTarget,
                landingIndex: landingIndex,
                ballStart: ballStart,
                wheelRadius: diameter / 2
            )
        }
        .frame(width: diameter, height: diameter)
    }

    // MARK: - Layers

    /// Everything painted on the wheel itself, and so everything that turns with it.
    private var disc: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)

            func circle(_ fraction: CGFloat) -> Path {
                let r = radius * fraction
                return Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r,
                                              width: r * 2, height: r * 2))
            }

            context.fill(
                circle(Ring.rimOuter),
                with: .linearGradient(
                    Gradient(colors: [Palette.gold, Palette.gold.opacity(0.45)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )
            // The groove the ball runs in, dark so the ball reads against it.
            context.fill(circle(Ring.rimInner), with: .color(Color(white: 0.07)))

            drawPockets(in: &context, centre: centre, radius: radius)
            drawFrets(in: &context, centre: centre, radius: radius)

            // The cone in the middle, which on a real wheel is what deflects the ball outward.
            context.fill(
                circle(Ring.pocketInner),
                with: .radialGradient(
                    Gradient(colors: [Color(white: 0.26), Color(white: 0.09)]),
                    center: centre,
                    startRadius: 0,
                    endRadius: radius * Ring.pocketInner
                )
            )

            drawNumerals(in: &context, centre: centre, radius: radius)
        }
    }

    private func drawPockets(in context: inout GraphicsContext, centre: CGPoint, radius: CGFloat) {
        let step = 360.0 / Double(RouletteWheel.pockets)
        for (index, number) in RouletteWheel.order.enumerated() {
            let middle = RouletteWheel.angle(ofPocketAt: index)
            var wedge = Path()
            wedge.move(to: centre)
            // Arc angles run from the positive x-axis, so "clockwise from the top" is 90° less.
            wedge.addArc(
                center: centre,
                radius: radius * Ring.pocketOuter,
                startAngle: .degrees(middle - step / 2 - 90),
                endAngle: .degrees(middle + step / 2 - 90),
                clockwise: false
            )
            wedge.closeSubpath()
            context.fill(wedge, with: .color(Palette.pocket(RouletteWheel.color(of: number))))
        }
    }

    /// The frets: the metal dividers standing between one pocket and the next.
    private func drawFrets(in context: inout GraphicsContext, centre: CGPoint, radius: CGFloat) {
        let step = 360.0 / Double(RouletteWheel.pockets)
        var frets = Path()
        for index in 0..<RouletteWheel.pockets {
            let edge = Angle.degrees(RouletteWheel.angle(ofPocketAt: index) - step / 2 - 90)
            let direction = CGPoint(x: cos(edge.radians), y: sin(edge.radians))
            frets.move(to: CGPoint(x: centre.x + direction.x * radius * Ring.pocketInner,
                                   y: centre.y + direction.y * radius * Ring.pocketInner))
            frets.addLine(to: CGPoint(x: centre.x + direction.x * radius * Ring.pocketOuter,
                                      y: centre.y + direction.y * radius * Ring.pocketOuter))
        }
        context.stroke(frets, with: .color(Palette.gold.opacity(0.35)),
                       lineWidth: max(0.5, radius * 0.008))
    }

    /// Numerals stand on the wheel, so they turn with it and the ones at the bottom come round
    /// upside down — which is what a wheel actually looks like, and what makes the rotation
    /// legible at a glance instead of a blur of colour.
    private func drawNumerals(
        in context: inout GraphicsContext, centre: CGPoint, radius: CGFloat
    ) {
        for (index, number) in RouletteWheel.order.enumerated() {
            var stamped = context
            stamped.translateBy(x: centre.x, y: centre.y)
            stamped.rotate(by: .degrees(RouletteWheel.angle(ofPocketAt: index)))
            stamped.draw(
                Text("\(number)")
                    .font(.system(size: radius * 0.079, weight: .bold, design: .rounded))
                    .foregroundStyle(.white),
                at: CGPoint(x: 0, y: -radius * Ring.numerals),
                anchor: .center
            )
        }
    }

    /// The turret in the middle, reused as the readout for the last number. It does not turn:
    /// it is the one part of the wheel that has to stay readable while everything else is moving.
    private var hub: some View {
        let radius = diameter / 2
        let size = radius * Ring.hub * 2
        let pocket = result.map(RouletteWheel.color(of:))

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.16), Color(white: 0.04)],
                        center: .center, startRadius: 0, endRadius: size / 2
                    )
                )
            Circle()
                .strokeBorder(
                    pocket.map(Self.hubRing) ?? Palette.gold.opacity(0.4),
                    lineWidth: max(1, radius * 0.028)
                )
            Text(result.map(String.init) ?? "—")
                .font(.system(size: radius * 0.30, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(won ? Palette.gold : .white.opacity(0.88))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.5), radius: radius * 0.06)
    }

    /// The ring around the hub says which colour the number was. `pocketBlack` is darker than the
    /// hub it would be drawn on, so a black result would simply have no ring — lightened to the
    /// point where it reads as "the black one" rather than as nothing.
    private static func hubRing(_ color: PocketColor) -> Color {
        color == .black ? Color(white: 0.42) : Palette.pocket(color)
    }

}

/// The ball, on its own animatable layer.
///
/// It has no position of its own. Everything below is a function of the *wheel's* interpolated
/// rotation, which is the only thing SwiftUI is animating — and that is what lets the ball be
/// captured by a pocket partway through and then simply ride the wheel to wherever it stops.
/// Given its own animated angle the two would have to be arranged to arrive together, which is
/// what the previous version did and why it looked like the ball had been placed rather than
/// thrown.
///
/// The conformance is main-actor isolated for the same reason `ReelView`'s is: SwiftUI only ever
/// drives `animatableData` from the render loop on the main actor.
struct RouletteBall: View, @MainActor Animatable {
    var wheelTurns: Double
    var spinStart: Double
    var spinTarget: Double
    var landingIndex: Int
    var ballStart: Double = 0
    var wheelRadius: CGFloat

    var animatableData: Double {
        get { wheelTurns }
        set { wheelTurns = newValue }
    }

    /// Where the ball leaves the banked track, and where a pocket catches it, as fractions of the
    /// spin. It holds the rim for well over half the spin, drops across the next stretch, and
    /// spends the last of it riding round in a pocket — the stick before the stop, which is the
    /// part that makes the result feel dealt rather than announced.
    /// Not private, so the speed test can work out how much of the spin the ball's own travel is
    /// packed into.
    static let release = 0.58
    static let capture = 0.88

    /// How many turns the ball makes against the wheel, per turn of the wheel's own travel.
    ///
    /// A ratio rather than a count, so the ball keeps one speed too. The wheel's travel varies a
    /// little from spin to spin — the pocket decides the fraction — and the duration is scaled to
    /// match, so a fixed number of ball turns would have the ball running faster on the shorter
    /// spins. Above 1, so the ball always outruns the wheel it is running against.
    static let turnsPerWheelTurn = 1.2

    /// This spin's ball travel, in turns.
    var revolutions: Double {
        Self.turns(forTravel: max(spinTarget - spinStart, 0))
    }

    var body: some View {
        let angle = Angle.degrees(ballAngle).radians
        let orbit = wheelRadius * orbitFraction
        let size = wheelRadius * 0.115

        return Circle()
            .fill(
                RadialGradient(
                    colors: [.white, Color(white: 0.72)],
                    center: UnitPoint(x: 0.35, y: 0.3),
                    startRadius: 0,
                    endRadius: size
                )
            )
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.55), radius: size * 0.35, y: size * 0.15)
            .offset(x: orbit * sin(angle), y: -orbit * cos(angle))
    }

    // MARK: - Where it is

    /// How far through the spin the wheel is, 0...1. A wheel that is not spinning reads as 1,
    /// which puts the ball in its pocket at rest.
    private var progress: Double {
        let span = spinTarget - spinStart
        guard span > 0.001 else { return 1 }
        return min(max((wheelTurns - spinStart) / span, 0), 1)
    }

    private var ballAngle: Double {
        Self.angle(
            wheelTurns: wheelTurns,
            spinStart: spinStart,
            spinTarget: spinTarget,
            landingIndex: landingIndex,
            ballStart: ballStart
        )
    }

    /// Clockwise degrees from the top, matching how the disc places its pockets.
    ///
    /// Two regimes, meeting at `capture`. Before it the ball is flying free against the wheel;
    /// after it the ball *is* the pocket, and the expression is the pocket's own screen position.
    /// The free path is defined to arrive at where the pocket will be at the moment of capture, so
    /// there is no seam — but only because it makes a **whole** number of turns getting there. A
    /// fraction of a turn in `revolutions` puts the two regimes that fraction of a circle apart,
    /// and the ball teleports at the join. Static, and separate, so that can be measured.
    static func angle(
        wheelTurns: Double, spinStart: Double, spinTarget: Double, landingIndex: Int,
        ballStart: Double = 0
    ) -> Double {
        let pocket = RouletteWheel.angle(ofPocketAt: landingIndex)
        func pocketAngle(at turns: Double) -> Double { pocket + turns * 360 }

        let travel = spinTarget - spinStart
        guard travel > 0.001 else { return pocketAngle(at: wheelTurns) }

        let progress = min(max((wheelTurns - spinStart) / travel, 0), 1)
        guard progress < capture else { return pocketAngle(at: wheelTurns) }

        // Runs from wherever the ball was sitting — the last winning pocket, which the wheel
        // left at no particular angle — down through a whole number of counter-turns to this
        // spin's pocket, arriving as that pocket reaches it.
        //
        // The pocket's angle is reduced to a single turn *before* the counter-turns come off, and
        // that is not tidiness. `wheelTurns` counts every turn the wheel has made since launch, so
        // the raw angle grows without bound; leaving it raw made the ball's sweep grow with it —
        // a third of a turn on the first spin of a session, seventeen turns by the eighth, which
        // is a ball that visibly spins faster every time you play it.
        let atCapture = spinStart + travel * capture
        let landed = pocketAngle(at: atCapture).truncatingRemainder(dividingBy: 360)
        let caught = landed - 360 * turns(forTravel: travel)
        return ballStart + (caught - ballStart) * (progress / capture)
    }

    /// How many turns the ball makes against the wheel on a spin of this travel.
    ///
    /// **Whole turns.** It scales with the wheel's travel so the ball keeps roughly one speed —
    /// the duration is scaled to the travel too — but it is rounded, because a fraction of a turn
    /// here is a fraction of a circle between the free path and the pocket that catches it. Left
    /// unrounded it jumped by up to 144° at the moment of capture, near the end of the spin, on
    /// every travel except the one that happened to come out whole.
    static func turns(forTravel travel: Double) -> Double {
        max(1, (travel * turnsPerWheelTurn).rounded())
    }

    // MARK: - The drop

    /// Where in the drop the ball is: 0 the instant it leaves the track, 1 the instant a pocket
    /// catches it. Zero for the whole time it is still riding the rim.
    private var dropped: Double {
        guard progress > Self.release else { return 0 }
        return min((progress - Self.release) / (Self.capture - Self.release), 1)
    }

    /// How far out the ball is, as a fraction of the wheel's radius.
    ///
    /// It holds the track until it is slow enough to fall off it, and only then drops onto the
    /// pockets. Interpolating straight from track to rest across the whole spin was the first
    /// attempt and looked wrong for a reason: a ball on a banked rim does not drift inward the
    /// moment it starts slowing, it stays pinned and then leaves all at once.
    private var orbitFraction: CGFloat {
        guard dropped > 0 else { return RouletteWheelView.Ring.ballTrack }
        // Smoothstepped, so the ball does not visibly kink at either end of the drop.
        let eased = dropped * dropped * (3 - 2 * dropped)
        return RouletteWheelView.Ring.ballTrack
            + (RouletteWheelView.Ring.ballRest - RouletteWheelView.Ring.ballTrack) * eased
    }
}
