import Foundation
import Testing

@testable import CasinoKit

/// How fast the wheel and the ball are allowed to move between two frames.
///
/// Neither is motion-blurred. The disc is a static drawing under a `rotationEffect`, which is what
/// makes it cheap to animate, and the ball is a plain circle — so anything that moves further than
/// its own feature size in one frame aliases. The wheel loses its numbers to a strobe; the ball
/// becomes a dotted trail.
///
/// This is arithmetic, not drawing, so it can be checked exactly: sample the easing curve at 60fps
/// and measure the widest step. It reads the curve the animation actually runs — which is why
/// `Roulette.spinCurve` is control points rather than `.easeOut` — so restoring the reels' curve,
/// which is what caused this in the first place, fails here rather than on screen.
@MainActor
@Suite("Roulette speed")
struct RouletteSpeedTests {
    private static var curve: (x1: Double, y1: Double, x2: Double, y2: Double) {
        Roulette.spinCurve
    }

    private static func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }

    /// The eased fraction of the travel completed at `time`, 0...1.
    ///
    /// A timing curve is parameterised by its own `t`, not by time, so the time has to be solved
    /// for first. Bisection: the x curve is monotonic, so fifty halvings is exact to well past
    /// what a frame can show.
    private static func progress(atTime time: Double) -> Double {
        var low = 0.0
        var high = 1.0
        for _ in 0..<50 {
            let mid = (low + high) / 2
            if bezier(mid, curve.x1, curve.x2) < time { low = mid } else { high = mid }
        }
        return bezier((low + high) / 2, curve.y1, curve.y2)
    }

    /// The widest single-frame step, in degrees, for a spin covering `turns` over `duration` at
    /// 60fps.
    private static func widestStep(turns: Double, duration: Double = Roulette.spinDuration)
        -> Double
    {
        let frames = Int((duration * 60).rounded())
        var widest = 0.0
        var previous = 0.0
        for frame in 1...frames {
            let time = Double(frame) / Double(frames)
            let travelled = progress(atTime: time) * turns * 360
            widest = max(widest, travelled - previous)
            previous = travelled
        }
        return widest
    }

    private static let pocket = 360.0 / Double(RouletteWheel.pockets)

    /// The extra travel a spin can draw, sampled finely. The wheel stops wherever it stops, so this
    /// is the whole space of spins the model can produce.
    private static let extras = stride(from: 0.0, to: 1.0, by: 0.02)

    private static func duration(forTravel travel: Double) -> Double {
        Roulette.spinDuration * travel / Roulette.nominalTravel
    }

    @Test("The wheel never turns more than a pocket between frames")
    func wheelStaysUnderAPocketPerFrame() {
        let step = Self.widestStep(turns: Roulette.nominalTravel)

        #expect(
            step < Self.pocket,
            """
            The wheel opens at \(String(format: "%.1f", step))° a frame against a \
            \(String(format: "%.1f", Self.pocket))° pocket — the numbers will strobe rather \
            than turn. Slow the spin, take a turn off it, or flatten the curve.
            """
        )
    }

    @Test("The ball never leaves more than its own width between frames")
    func ballStaysUnderItsOwnWidth() {
        // Swept rather than measured at nominal, because the ball is the one part whose speed is
        // *not* flat across spins: its turns are rounded to a whole number so the join at capture
        // lands cleanly, and rounding up is a step change in distance over a duration that only
        // grew smoothly. The fastest spin is therefore the one just past a rounding boundary —
        // about 14% quicker than the nominal one, which measuring only nominal would miss.
        //
        // The ball also finishes its own travel by the time a pocket catches it, so it covers those
        // turns in that fraction of the spin rather than all of it.
        var step = 0.0
        for extra in Self.extras {
            let travel = Roulette.travel(extra: extra)
            step = max(step, Self.widestStep(
                turns: RouletteBall.turns(forTravel: travel) / RouletteBall.capture,
                duration: Self.duration(forTravel: travel)
            ))
        }

        // Its width as an angle at the track it runs on.
        let radius = RouletteWheelView.Ring.ballTrack
        let widthInDegrees = (0.115 / radius) * 180 / .pi

        // Twice its width, not once. Requiring successive frames to actually overlap is stricter
        // than motion needs to be — a small bright object leaving a gap of up to its own width
        // reads as something moving fast, which it is. Past that the gaps win and it reads as a
        // dotted line, which is the thing being guarded against.
        let budget = widthInDegrees * 2

        #expect(
            step < budget,
            """
            The ball opens at \(String(format: "%.1f", step))° a frame, which is \
            \(String(format: "%.1f", step / widthInDegrees)) times its own \
            \(String(format: "%.1f", widthInDegrees))° width — far enough apart between frames \
            to read as a dotted trail rather than a ball.
            """
        )
    }

    @Test("The ball still outruns the wheel, and the other way round")
    func theBallIsTheFastPart() {
        // A real wheel turns slowly and the ball does not. Losing that would make the whole thing
        // read as one rigid disc.
        #expect(RouletteBall.turnsPerWheelTurn > 1)
    }

    // MARK: - Speeding up

    @Test("The wheel only ever slows down, never speeds up mid-spin")
    func theWheelNeverAccelerates() {
        // What a spun wheel does is decelerate. A curve whose slope rises before it falls reads as
        // the wheel being *pushed* partway through, and the one that was here — a near-linear ease
        // with the second control point out at 0.7 — accelerated for the first fifth of every
        // spin. It is not obvious by eye which curves do this, so it is measured.
        let frames = 192
        let steps = (0..<frames).map { frame -> Double in
            let from = Self.progress(atTime: Double(frame) / Double(frames))
            let to = Self.progress(atTime: Double(frame + 1) / Double(frames))
            return to - from
        }

        let rising = steps.indices.dropLast().filter { steps[$0 + 1] > steps[$0] + 1e-9 }
        #expect(
            rising.isEmpty,
            """
            The wheel speeds up over \(rising.count) of \(frames) frames before it slows — \
            first at \(String(format: "%.0f%%", Double(rising.first ?? 0) / Double(frames) * 100)) \
            through the spin.
            """
        )
    }

    @Test("Every spin turns at the same speed, however far it happens to run")
    func everySpinIsTheSameSpeed() {
        // The travel now carries up to a whole extra turn of shove, so it is never the same twice;
        // the duration is scaled to it so the speed is. Without that the wheel visibly spun harder
        // on the longer spins, which is what "it speeds up each time" first looked like.
        var speeds: [Double] = []
        for extra in Self.extras {
            let travel = Roulette.travel(extra: extra)
            speeds.append(travel / Self.duration(forTravel: travel))
        }

        let fastest = speeds.max() ?? 0
        let slowest = speeds.min() ?? 0
        #expect(
            fastest - slowest < 1e-9,
            "spins range from \(slowest) to \(fastest) turns a second — they should all match"
        )
    }

    // MARK: - The join

    @Test("The ball does not jump when a pocket catches it")
    func theBallIsContinuousAtCapture() {
        // The ball flies free until `capture` and *is* the pocket after it. The two expressions
        // meet only if the free path made a whole number of turns getting there — a fraction of a
        // turn puts them that fraction of a circle apart, and the ball teleports at the join, 88%
        // of the way through the spin where it is most visible.
        //
        // Scaling the ball's turns with the wheel's travel without rounding did exactly that: up
        // to 144° on every travel except the one that came out whole by luck.
        for extra in Self.extras {
            for landing in stride(from: 0, to: RouletteWheel.pockets, by: 4) {
                let travel = Roulette.travel(extra: extra)
                let start = extra * 7  // an arbitrary parked position, not a round number
                let target = start + travel
                let atCapture = start + travel * RouletteBall.capture
                // Where the ball was left by the spin before, which is now any angle at all.
                let ballStart = Roulette.ballAngle(pocketAt: landing / 2, wheelTurns: start)

                let before = RouletteBall.angle(
                    wheelTurns: atCapture - travel * 1e-6,
                    spinStart: start, spinTarget: target, landingIndex: landing,
                    ballStart: ballStart
                )
                let after = RouletteBall.angle(
                    wheelTurns: atCapture + travel * 1e-6,
                    spinStart: start, spinTarget: target, landingIndex: landing,
                    ballStart: ballStart
                )

                var gap = (after - before).truncatingRemainder(dividingBy: 360)
                if gap < 0 { gap += 360 }
                let jump = min(gap, 360 - gap)

                #expect(
                    jump < 0.5,
                    """
                    The ball jumps \(String(format: "%.0f", jump))° at capture on a \
                    \(String(format: "%.2f", travel))-turn spin — it makes \
                    \(RouletteBall.turns(forTravel: travel)) turns, which has to be whole.
                    """
                )
            }
        }
    }

    @Test("The ball spins the same distance on the hundredth spin as on the first")
    func theBallDoesNotSpeedUpOverASession() {
        // `wheelTurns` counts every turn the wheel has made since launch and is never reduced — it
        // cannot be, because the wheel only ever turns forwards. The ball's free path is built from
        // the pocket's angle at the moment of capture, and taking that angle *raw* meant the path
        // inherited the whole session's rotation with it: measured, a third of a turn on the first
        // spin of a session and seventeen turns by the eighth, growing for as long as you played.
        //
        // That is what "it speeds up every time" turned out to be, and it survived four other
        // fixes because none of them touched it. Every one of those examined a single spin, and a
        // single spin looks perfectly correct.
        for parked in [0.0, 2.5, 25.0, 250.0, 2500.0] {
            for landing in stride(from: 0, to: RouletteWheel.pockets, by: 6) {
                let travel = Roulette.travel(extra: Double(landing) / 40)
                let target = parked + travel
                let ballStart = Roulette.ballAngle(pocketAt: landing / 2, wheelTurns: parked)

                let atRest = RouletteBall.angle(
                    wheelTurns: parked, spinStart: parked, spinTarget: target,
                    landingIndex: landing, ballStart: ballStart
                )
                let justBeforeCapture = RouletteBall.angle(
                    wheelTurns: parked + travel * (RouletteBall.capture - 1e-6),
                    spinStart: parked, spinTarget: target, landingIndex: landing,
                    ballStart: ballStart
                )
                let sweptTurns = abs(justBeforeCapture - atRest) / 360

                // Its own turns plus at most one, because both ends of the sweep are angles that
                // can sit anywhere in a circle. Anything beyond that is rotation it did not ask for.
                let owed = RouletteBall.turns(forTravel: travel)
                #expect(
                    sweptTurns < owed + 1,
                    """
                    After \(parked) turns of play the ball sweeps \
                    \(String(format: "%.1f", sweptTurns)) turns to reach the pocket, against the \
                    \(owed) it should. The session's rotation is leaking into the ball's path.
                    """
                )
            }
        }
    }

    @Test("Twenty spins in a row, and the twentieth is no longer than the first")
    func aWholeSessionStaysTheSameLength() {
        // The regression this whole file exists for, driven the way it actually happens: one spin
        // after another, each starting from where the last one left the wheel *and* the ball. The
        // ball's start is new carried state, and carried state is precisely what leaked the
        // session's rotation into the ball's path last time — measured then at a third of a turn on
        // the first spin and seventeen by the eighth.
        //
        // Chained arithmetic rather than twenty real spins, which would take a minute of wall clock
        // and tell you the same thing. Reasoning about a single spin is what missed it before; this
        // is the sequence.
        var wheelTurns = 0.0
        var pocket = 0
        var ballStart = 0.0
        var sweeps: [Double] = []

        for spin in 0..<20 {
            // Stands in for `Double.random`, which a test cannot have: an irrational stride, so the
            // extras never repeat and never line up with a whole turn.
            let extra = (Double(spin) * 0.618_033_988_75).truncatingRemainder(dividingBy: 1)
            let landing = (spin * 11 + 3) % RouletteWheel.pockets

            ballStart = Roulette.ballAngle(pocketAt: pocket, wheelTurns: wheelTurns)
            let travel = Roulette.travel(extra: extra)
            let start = wheelTurns
            let target = start + travel

            let atRest = RouletteBall.angle(
                wheelTurns: start, spinStart: start, spinTarget: target,
                landingIndex: landing, ballStart: ballStart
            )
            let justBeforeCapture = RouletteBall.angle(
                wheelTurns: start + travel * (RouletteBall.capture - 1e-9),
                spinStart: start, spinTarget: target, landingIndex: landing, ballStart: ballStart
            )
            sweeps.append(abs(justBeforeCapture - atRest) / 360)

            wheelTurns = target
            pocket = landing
        }

        let first = sweeps.first ?? 0
        let last = sweeps.last ?? 0
        let widest = sweeps.max() ?? 0
        #expect(
            widest < 6,
            """
            By spin \(sweeps.firstIndex(of: widest) ?? 0) the ball sweeps \
            \(String(format: "%.1f", widest)) turns — it started at \
            \(String(format: "%.1f", first)) and finished at \(String(format: "%.1f", last)). \
            The session's rotation is leaking into the ball again.
            """
        )
    }

    @Test("The ball comes to rest in the winning pocket, wherever that pocket stops")
    func theBallLandsOnTheWinner() {
        // The other end of the same arithmetic. It is *not* "the ball finishes at the top" any
        // more: there is no marker, so the wheel stops wherever the throw leaves it and the ball
        // has to be in the winning pocket at that angle rather than at a fixed one on screen.
        for extra in Self.extras {
            for landing in stride(from: 0, to: RouletteWheel.pockets, by: 4) {
                let travel = Roulette.travel(extra: extra)
                let parked = extra * 7
                let target = parked + travel
                let resting = RouletteBall.angle(
                    wheelTurns: target, spinStart: parked, spinTarget: target,
                    landingIndex: landing,
                    ballStart: Roulette.ballAngle(pocketAt: landing / 2, wheelTurns: parked)
                )

                var offBy = (resting - Roulette.ballAngle(pocketAt: landing, wheelTurns: target))
                    .truncatingRemainder(dividingBy: 360)
                if offBy < 0 { offBy += 360 }
                #expect(min(offBy, 360 - offBy) < 1e-6)
            }
        }
    }

    @Test("The wheel stops somewhere different every time")
    func theWheelStopsAtARandomAngle() {
        // What the marker used to hide. With one, the travel was solved for so the winner arrived
        // at the top, and the wheel therefore finished in one of 37 positions. Without one the
        // throw decides, and the resting angle has to be spread over the whole circle — otherwise
        // removing the marker just means the wheel stops in the same place with nothing drawn on it.
        let angles = Self.extras.map {
            Roulette.travel(extra: $0).truncatingRemainder(dividingBy: 1) * 360
        }

        // Every twelfth of the circle gets used, which a fixed or near-fixed stop cannot manage.
        let twelfths = Set(angles.map { Int($0 / 30) })
        #expect(twelfths.count == 12, "the wheel only ever stops in \(twelfths.count) of 12 sectors")
    }

    @Test("Spins stay about the same length, so the speed is not bought with a wild clock")
    func spinLengthsStayClose() {
        // Constant speed over a variable distance means a variable duration, and the distance now
        // varies by a whole turn because that is what makes the stopping angle unpredictable. One
        // turn on top of two and a half is as much as that can be spent without spins visibly
        // running to different lengths.
        var durations: [Double] = []
        for extra in Self.extras {
            durations.append(Self.duration(forTravel: Roulette.travel(extra: extra)))
        }

        let longest = durations.max() ?? 0
        let shortest = durations.min() ?? 0
        #expect(longest / shortest < 1.5, "spins run from \(shortest)s to \(longest)s")
        #expect(shortest > 1.5, "a \(shortest)s spin is over before it reads as one")
    }
}
