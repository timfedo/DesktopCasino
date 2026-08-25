import CasinoKit
import SwiftUI


struct CasinoView: View {
    let machine: SlotMachine
    /// Injected rather than looked up: scanning `NSApp.windows` per access ran once per drag
    /// frame, and it left `mode` with two sources of truth synced only on appear. Held weakly
    /// through a box, since the panel hosts this very view and would otherwise retain itself.
    var panelRef = PanelRef()
    /// Forces the hover state on for offscreen renders, where there is no pointer to hover with.
    var alwaysHovered = false

    @State private var hovering = false
    @State private var modeRevision = 0

    private var panel: DesktopPanel? { panelRef.panel }
    /// Drops back to false a minute after a win. `TimelineView(.animation)` asks for a frame at
    /// display refresh for as long as the marquee is mounted, so leaving it up until the next
    /// spin means an idle desktop widget animating forever.
    @State private var celebrating = false

    /// Window origin minus pointer position, in screen coordinates, captured when the drag
    /// starts. Constant for the whole drag.
    @State private var grabOffset: CGSize?

    private let gold = Palette.gold

    /// Pins the window to the pointer using an absolute anchor: the grab offset is measured
    /// once, then every update sets `origin = pointer + offset`.
    ///
    /// Two things it deliberately avoids. The gesture's own `translation` is reported relative
    /// to the window, and dragging moves that window, so feeding it back runs away. Summing
    /// per-frame `NSEvent.mouseLocation` deltas runs away more slowly for the same reason —
    /// each sample is taken when the callback happens rather than when the event occurred, and
    /// integrating never corrects the accumulated error. An absolute anchor is self-correcting:
    /// a late sample simply lands in the right place on the next update.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { _ in
                guard let panel else { return }
                let mouse = NSEvent.mouseLocation

                let offset = grabOffset ?? CGSize(
                    width: panel.frame.origin.x - mouse.x,
                    height: panel.frame.origin.y - mouse.y
                )
                if grabOffset == nil { grabOffset = offset }

                panel.setFrameOrigin(NSPoint(
                    x: mouse.x + offset.width,
                    y: mouse.y + offset.height
                ))
            }
            .onEnded { _ in
                grabOffset = nil
                panel?.savePosition()
            }
    }

    var body: some View {
        VStack(spacing: 11) {
            header
            credits
            reelBox
            outcomeLine
            betPicker
            actionButton
        }
        // Height comes from the content, so this padding is the margin on every side. A fixed
        // frame height would centre the stack and leave a wider gap under the SPIN button.
        .padding(16)
        .frame(width: DesktopPanel.size.width)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Palette.card()
            }
            // Attached to the background rather than the card so that buttons, which sit in
            // the foreground, win hit-testing and stay clickable.
            .contentShape(Rectangle())
            .gesture(dragGesture)
        }
        .clipShape(.rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(
                    LinearGradient(colors: [gold.opacity(0.55), gold.opacity(0.12)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .task(id: machine.spinCount) {
            celebrating = isTriple && !reduceMotion
            guard celebrating else { return }
            // Re-triggered by `spinCount`, so a new spin cancels the previous countdown.
            try? await Task.sleep(for: .seconds(Self.celebrationDuration))
            celebrating = false
        }
    }

    /// How long the win marquee runs before it stops asking for frames.
    private static let celebrationDuration: Double = 60

    /// Honour the system setting rather than animating a desktop widget at someone who asked for
    /// less of it.
    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: - Sections

    /// A traffic-light-sized round button, muted until the pointer is over it — the same
    /// restraint as the native window controls, which stay grey until you approach them.
    private struct ControlButton: View {
        let symbol: String
        let tint: Color
        /// Keeps the button lit while not hovered, for a mode that is currently engaged.
        var active = false
        let help: String
        let action: () -> Void

        @State private var hovered = false

        private var lit: Bool { hovered || active }

        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(lit ? .black.opacity(0.75) : .white.opacity(0.5))
                    .frame(width: 13, height: 13)
                    .background(lit ? tint : Color.white.opacity(0.15), in: .circle)
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: lit)
            .help(help)
        }
    }

    /// Controls sit top-left with close outermost, mirroring the native traffic lights, and the
    /// title is centred in the remaining width like a real titlebar.
    private var header: some View {
        ZStack {
            Text("DESKTOP CASINO")
                .font(.system(size: 10, weight: .heavy))
                .tracking(2.4)
                .foregroundStyle(gold.opacity(0.85))

            HStack(spacing: 8) {
                ControlButton(
                    symbol: "xmark",
                    tint: Color(red: 0.99, green: 0.35, blue: 0.33),
                    help: "Quit DesktopCasino"
                ) {
                    NSApp.terminate(nil)
                }
                .opacity(hovering ? 1 : 0)

                // Cycles window placement: normal → floating → widget → normal. Stays visible
                // outside `normal` so there is always a way back out of a placement where the
                // window may be hard to reach.
                ControlButton(
                    symbol: mode.symbolName,
                    tint: gold,
                    active: mode != .normal,
                    help: mode.help
                ) {
                    panel?.setMode(mode.next)
                    modeRevision += 1
                }
                .opacity(hovering || mode != .normal ? 1 : 0)

                Spacer()
            }
        }
        .onAppear {
            if alwaysHovered { hovering = true }
        }
    }

    private var credits: some View {
        VStack(spacing: 1) {
            Text("\(machine.credits)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.35), value: machine.credits)

            Text("CREDITS")
                .font(.system(size: 8, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var reelBox: some View {
        HStack(spacing: 6) {
            ForEach(machine.reels.indices, id: \.self) { i in
                ReelView(
                    position: machine.reels[i].position,
                    spinStart: machine.reels[i].spinStart,
                    spinTarget: machine.reels[i].spinTarget
                )
            }
        }
        .padding(8)
        .background(.black.opacity(0.45), in: .rect(cornerRadius: 12))
        .overlay {
            if isTriple && celebrating {
                WinMarquee(cornerRadius: 12, stripe: Palette.gold, base: Palette.red)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(winHighlight, lineWidth: isWin ? 2 : 1)
            }
        }
        // A triple carries its own breathing glow inside the marquee.
        .shadow(color: isWin && !isTriple ? gold.opacity(0.55) : .clear, radius: 12)
        .scaleEffect(isWin ? 1.03 : 1)
        .animation(.spring(duration: 0.45, bounce: 0.45), value: machine.spinCount)
    }

    private var outcomeLine: some View {
        VStack(spacing: 2) {
            Text(outcomeText)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(isWin ? gold : .white.opacity(isPush ? 0.7 : 0.55))

            // Net, not gross: the stake left the balance when the spin started, so a 2x pair on
            // a 25 bet gains 25, not 50. Showing gross here while a push shows ±0 would put two
            // different units on the same line.
            Text(machine.lastWin > 0 ? (isPush ? "±0" : "+\(machine.lastWin - machine.lastStake)") : " ")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(gold)
        }
        .frame(height: 32)
        .animation(.easeOut(duration: 0.2), value: machine.spinCount)
    }

    private var betPicker: some View {
        HStack(spacing: 5) {
            ForEach(SlotMachine.betSizes, id: \.self) { size in
                let selected = machine.bet == size
                Button {
                    machine.setBet(size)
                } label: {
                    Text("\(size)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(selected ? .black : .white.opacity(0.65))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(selected ? gold : .white.opacity(0.09),
                                    in: .rect(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(machine.isSpinning || size > machine.credits)
                .opacity(size > machine.credits ? 0.35 : 1)
            }
        }
        .animation(.easeOut(duration: 0.15), value: machine.bet)
    }

    private var actionButton: some View {
        let broke = machine.credits < SlotMachine.betSizes[0]
        return Button {
            if broke { machine.refill() } else { machine.spin() }
        } label: {
            Text(broke ? "REFILL +\(SlotMachine.startingBank)"
                       : (machine.isSpinning ? "SPINNING…" : "SPIN  −\(machine.bet)"))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.black.opacity(0.85))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    LinearGradient(colors: [gold, gold.opacity(0.7)],
                                   startPoint: .top, endPoint: .bottom),
                    in: .rect(cornerRadius: 11)
                )
        }
        .buttonStyle(.plain)
        .disabled(machine.isSpinning)
        .opacity(machine.isSpinning ? 0.45 : 1)
        .animation(.easeOut(duration: 0.2), value: machine.isSpinning)
    }

    // MARK: - Derived

    /// Strictly a *gain*. Cherry, lemon and bell pairs pay 1x — your stake back, net zero — and
    /// that is 39% of all spins. Celebrating those is the textbook "loss disguised as a win", so
    /// a push gets its own muted treatment instead of the gold border and glow.
    /// Reads through to the panel; `modeRevision` exists only to invalidate the body when it
    /// changes, since `DesktopPanel` is not observable.
    private var mode: DesktopPanel.Mode {
        _ = modeRevision
        return panel?.mode ?? .normal
    }

    private var isWin: Bool { machine.lastWin > machine.lastStake && !machine.isSpinning }

    private var isPush: Bool {
        machine.lastWin > 0 && machine.lastWin == machine.lastStake && !machine.isSpinning
    }

    private var isTriple: Bool {
        guard case .triple = machine.outcome, !machine.isSpinning else { return false }
        return true
    }

    private var winHighlight: Color {
        guard isWin else { return .white.opacity(0.12) }
        return machine.outcome.isJackpot ? .cyan : gold
    }

    private var outcomeText: String {
        switch machine.outcome {
        case .idle: "PLACE YOUR BET"
        case .spinning: "GOOD LUCK"
        case .nothing: "NO WIN"
        case .pair(let symbol): "\(symbol.name.uppercased()) ×2"
        case .triple(let symbol):
            symbol.name == "diamond" ? "★ JACKPOT ★" : "\(symbol.name.uppercased()) ×3"
        case .broke: "OUT OF CREDITS"
        }
    }
}

/// One reel. `Animatable` gives us the interpolated scroll position on every frame, so the
/// body can pick which symbols are on screen — a plain `.offset` animation could only slide
/// a fixed set of views and would jump when the strip index changed.
/// Breaks the retain cycle between a panel and the SwiftUI view it hosts.
@MainActor
final class PanelRef {
    weak var panel: DesktopPanel?
    init(_ panel: DesktopPanel? = nil) { self.panel = panel }
}

/// The three-of-a-kind celebration: a barber-pole of slanted stripes travelling around the reel
/// frame, with the glow breathing in time.
///
/// Driven by `TimelineView(.animation)` rather than a `repeatForever` animation, so the stripe
/// travel and the pulse share one clock and cannot drift apart. It is only mounted while a triple
/// is on screen, so nothing redraws the rest of the time.
struct WinMarquee: View {
    let cornerRadius: CGFloat
    let stripe: Color
    let base: Color

    /// Points of stripe travel per second.
    private let speed: Double = 46
    /// Bounded by the corners, not the straights. A corner arc is only `pi * radius / 2` long —
    /// 18.9pt at a 12pt radius — so a coarse pitch fits barely one stripe into the whole turn and
    /// each corner becomes a solid block of red plus a solid block of gold, reading as a heavy
    /// corner beside the finely striped straight runs. This pitch puts a little over two stripes
    /// on each corner, which still resolves as distinct bars.
    private let stripeWidth: CGFloat = 4.2
    private let lineWidth: CGFloat = 3
    /// Fraction the band narrows at the middle of each corner arc.
    ///
    /// Measured, the band is already the same 3pt through the corners — but a curve crosses your
    /// line of sight obliquely, so at 45° it spans about 1.4x its true width along the horizontal
    /// and vertical, and reads that much heavier. This cancels the illusion rather than fixing a
    /// geometry error; 0.18 was tried first and was far too weak to be visible.
    private let cornerTaper: CGFloat = 0.45

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 0.5 + 0.5 * sin(time * 3.1)

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

                marquee(phase: CGFloat(time * speed))
            }
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



/// The conformance is main-actor isolated: SwiftUI only ever drives `animatableData`
/// from the render loop on the main actor.
struct ReelView: View, @MainActor Animatable {
    var position: Double
    var spinStart: Double
    var spinTarget: Double

    static let width: CGFloat = 62
    static let stopHeight: CGFloat = 66

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
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
