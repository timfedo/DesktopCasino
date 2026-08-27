import CasinoKit
import SwiftUI


struct CasinoView: View {
    let machine: SlotMachine
    /// Injected rather than looked up: scanning `NSApp.windows` per access ran once per drag
    /// frame, and it left `mode` with two sources of truth synced only on appear. Held weakly
    /// through a box, since the panel hosts this very view and would otherwise retain itself.
    var panelRef = PanelRef()
    /// Owns the stats window. Absent in renders and tests, where the button still draws — it is
    /// part of the chrome the window snapshots are there to guard — and simply does nothing.
    var stats: StatsWindowController?
    /// Forces the hover state on for offscreen renders, where there is no pointer to hover with.
    var alwaysHovered = false
    /// Marks a render as a still, which suppresses the win celebration.
    ///
    /// The marquee travels off a clock, so a still can only ever pin an arbitrary phase. It was
    /// already *meant* to be absent from offscreen renders — `celebrating` is set from `.task`,
    /// and the reasoning was that a render never runs one. That holds on some machines and not
    /// others: `window-triple` and `window-jackpot` matched on the CI runner and failed locally,
    /// where the task does get a turn before `ImageRenderer` captures. Saying so outright is what
    /// makes the reference reproducible rather than a property of the machine that recorded it.
    var isStill = false

    @State private var hovering = false
    @State private var modeRevision = 0

    /// Whether the window controls are showing: the pointer is over the card, or a render has
    /// asked for them. Derived rather than seeded into `hovering` from `onAppear`, because
    /// `ImageRenderer` never calls `onAppear` — the chrome was silently missing from every
    /// offscreen render.
    private var showsChrome: Bool { hovering || alwaysHovered }

    private var panel: DesktopPanel? { panelRef.panel }

    private var statsOpen: Bool { stats?.isOpen == true }
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
            // Opaque, and deliberately not `.ultraThinMaterial`. A behind-window material samples
            // whatever is behind the window, and in widget mode the panel floats above a Space
            // transition — so the outgoing and incoming Spaces' windows slide *behind* it, and a
            // bright one showing through the card lifted the whole thing for the length of the
            // slide. Settled on the desktop the panel only ever sees the wallpaper, because it
            // sits below every window, so the frost cost a visible flicker on every Space switch
            // to buy a tint you could only see when nothing was moving.
            //
            // `cardBottom` under `card()` is exactly how the icon is composited, so the widget and
            // its icon now resolve to the same colour rather than merely sharing a gradient.
            ZStack {
                Palette.cardBottom
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
            celebrating = isTriple && !reduceMotion && !isStill
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
    /// title is centred in the remaining width like a real titlebar. Stats sits alone on the
    /// right, away from anything that closes or moves the window.
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
                .opacity(showsChrome ? 1 : 0)

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
                .opacity(showsChrome || mode != .normal ? 1 : 0)

                Spacer()

                ControlButton(
                    symbol: "chart.bar.fill",
                    tint: gold,
                    // Stays lit while the stats window is up, so the button reads as the thing
                    // that opened it rather than a control that did nothing.
                    active: statsOpen,
                    help: statsOpen ? "Close the statistics window" : "Statistics"
                ) {
                    stats?.toggle()
                }
                .opacity(showsChrome || statsOpen ? 1 : 0)
            }
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

/// Breaks the retain cycle between a panel and the SwiftUI view it hosts.
@MainActor
final class PanelRef {
    weak var panel: DesktopPanel?
    init(_ panel: DesktopPanel? = nil) { self.panel = panel }
}
