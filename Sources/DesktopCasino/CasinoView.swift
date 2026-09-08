import CasinoKit
import SwiftUI


struct CasinoView: View {
    let casino: Casino
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

    /// Fades the table in after a change. Its own state rather than a `transition`, because a
    /// transition runs under the transaction that caused it, and the change itself is committed
    /// without one. See `selectTable`.
    @State private var tableFade: Double = 1
    /// The height of the box the table sits in, animated to whatever the table inside needs.
    /// `nil` until the first one has been measured.
    @State private var tableHeight: CGFloat?

    /// Whether the window controls are showing: the pointer is over the card, or a render has
    /// asked for them. Derived rather than seeded into `hovering` from `onAppear`, because
    /// `ImageRenderer` never calls `onAppear` — the chrome was silently missing from every
    /// offscreen render.
    private var showsChrome: Bool { hovering || alwaysHovered }

    /// The slot machine, which most of this file predates the roulette table in caring about.
    private var machine: SlotMachine { casino.slots }

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
            tablePicker
            credits
            table
            stakePicker
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
        // The two tables are different heights, so the window has to follow the card rather than
        // the other way round. Measured here rather than read back off the hosting view: changing
        // table is an `@Observable` mutation, and SwiftUI has not re-laid anything out by the time
        // the button's action returns, so `fittingSize` would be a frame stale — for one frame the
        // roulette table would be drawn into a slot machine's window and clipped.
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: CardHeightKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(CardHeightKey.self) { [panelRef] height in
            // SwiftUI delivers preference changes on the main actor as part of its update pass.
            MainActor.assumeIsolated { panelRef.panel?.matchHeight(to: height) }
        }
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
        /// Per button, because SF Symbols do not share a bounding box. `xmark` and `pin` are
        /// sparse marks that need 8pt to read at all; `chart.bar.fill` is a solid block that at
        /// the same size runs to the edge of the 13pt circle and looks cropped.
        var glyphSize: CGFloat = 8
        /// Keeps the button lit while not hovered, for a mode that is currently engaged.
        var active = false
        let help: String
        let action: () -> Void

        @State private var hovered = false

        private var lit: Bool { hovered || active }

        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: glyphSize, weight: .black))
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
                    glyphSize: 6.5,
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

    /// Which table you are standing at. Directly above the credits, because the balance is the one
    /// thing the two tables share — the picker changes the game underneath the number, not the
    /// number.
    ///
    /// Locked mid-round: the stake is already down and the result is already scheduled, and
    /// walking away from a bet you have paid for is not something a control should let you do by
    /// accident.
    private var tablePicker: some View {
        HStack(spacing: 5) {
            ForEach(Casino.Game.allCases, id: \.self) { game in
                let selected = casino.game == game
                Button {
                    selectTable(game)
                } label: {
                    Text(game.title)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.3)
                        .foregroundStyle(selected ? .black.opacity(0.85) : .white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .background(selected ? gold : .white.opacity(0.09),
                                    in: .rect(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(casino.isBusy)
                .help(game.help)
            }
        }
        .opacity(casino.isBusy ? 0.45 : 1)
        .animation(.easeOut(duration: 0.2), value: casino.isBusy)
    }

    /// Changes table in two parts: the layout instantly, and the new table fading in over it.
    ///
    /// Only the middle of the card animates. The chrome around it — the picker and credits above,
    /// the stake chips and the gold button below — is left alone, and that is the whole point:
    /// with the window anchored at its bottom edge, the chips and the button are already at a
    /// fixed place on screen, so *not animating them* is what makes them genuinely static rather
    /// than merely arriving somewhere on a curve.
    ///
    /// Animating the height instead was the obvious thing and is subtly worse. Everything above
    /// the table has to travel with it, so a quarter of a second of the picker you just clicked
    /// sliding out from under the pointer — smooth, coherent, and still the card moving when
    /// nothing about changing table needs the card to move.
    ///
    /// Two transactions, in this order, both synchronous:
    ///
    /// 1. The model change and the fade reset, with animations off. The card resizes, the window
    ///    follows in the same pass, and the new table is laid out but invisible.
    /// 2. The fade back in. `tableFade` feeds an `opacity` and nothing else, so this animation has
    ///    no geometry to reach: it cannot move anything, however long it runs.
    private func selectTable(_ game: Casino.Game) {
        guard game != casino.game, !casino.isBusy else { return }

        // Both committed without an animation: the swap itself is instant, and the box the table
        // sits in animates to the new table's height once it has been measured — see `table`.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            tableFade = 0
            casino.select(game)
        }

        // Deferred a turn so the blank above is committed first. Run in the same pass, the two
        // assignments would cancel and nothing would fade.
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.28)) { tableFade = 1 }
        }
    }

    /// A spring with no bounce. A card resizing should not overshoot and come back, and the settle
    /// of a bouncy one would have the window chasing it for longer than the movement is worth.
    private static let tableChange: Animation = .smooth(duration: 0.34)

    /// How far outside its box the table is allowed to draw: wider than the wheel's 16pt win glow
    /// and the reels' 12pt one, both of which fall outside the frame they belong to.
    private static let glowSlack: CGFloat = 26

    /// The table, in a box whose height is animated to whatever the table inside it needs.
    ///
    /// The height is driven explicitly rather than left to layout, and it is driven through an
    /// `Animatable` box rather than a plain `frame(height:)` fed an animated value. The difference
    /// is the whole fix — see `TableBox`.
    private var table: some View {
        let measured = tableContent
            // A new view per table, so the outgoing one is gone rather than fading out underneath.
            // A true cross-fade would need both laid out at once, and they are 250pt apart in
            // height — the card would have to be big enough for the taller of them throughout.
            .id(casino.game)
            // Ignores the height the box proposes, so what gets measured below is what the table
            // actually wants rather than what it is currently being given.
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: TableHeightKey.self, value: proxy.size.height)
                }
            }
            .opacity(tableFade)

        return Group {
            // Unconstrained until the first table has been measured, which happens once at launch.
            if let tableHeight {
                TableBox(height: tableHeight, slack: Self.glowSlack) { measured }
            } else {
                measured
            }
        }
        .onPreferenceChange(TableHeightKey.self) { height in
            MainActor.assumeIsolated { adopt(tableHeight: height) }
        }
    }

    /// Takes the natural height of whichever table is now in the box, animating the box to it.
    ///
    /// The first one is adopted outright: there is nothing to animate from, and a card that grew
    /// into place on launch would be a strange thing to watch.
    private func adopt(tableHeight height: CGFloat) {
        guard height > 0, height != tableHeight else { return }
        guard tableHeight != nil else {
            tableHeight = height
            return
        }
        withAnimation(Self.tableChange) { tableHeight = height }
    }

    @ViewBuilder
    private var tableContent: some View {
        switch casino.game {
        case .slots:
            VStack(spacing: 11) {
                reelBox
                outcomeLine
            }
        case .roulette:
            RouletteTable(roulette: casino.roulette, broke: casino.bank.isBroke)
        }
    }

    private var stakePicker: some View {
        StakePicker(
            stake: casino.stake,
            credits: casino.bank.credits,
            locked: casino.isSpinning
        ) {
            casino.setStake($0)
        }
    }

    private var credits: some View {
        VStack(spacing: 1) {
            Text("\(casino.bank.credits)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.35), value: casino.bank.credits)

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

    private var actionButton: some View {
        let broke = casino.bank.isBroke
        // Nothing staked is only reachable at the wheel, where clearing the felt is a thing you
        // can do. Saying so beats a gold button that looks live and does nothing.
        let unstaked = !broke && casino.wager == 0
        let inert = casino.isSpinning || unstaked

        return Button {
            if broke { casino.refill() } else { casino.spin() }
        } label: {
            Text(label(broke: broke, unstaked: unstaked))
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
                // Scoped to the label, for the same reason as the stake chips: on the button it
                // also animated the button's own frame, and the button moves the height of a
                // roulette felt when you change table.
                .opacity(inert ? 0.45 : 1)
                .animation(.easeOut(duration: 0.2), value: inert)
        }
        .buttonStyle(.plain)
        .disabled(inert)
    }

    private func label(broke: Bool, unstaked: Bool) -> String {
        if broke { return "REFILL +\(Bank.startingBank)" }
        if casino.isSpinning { return "SPINNING…" }
        if unstaked { return "PLACE A BET" }
        return "SPIN  −\(casino.wager)"
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

/// The box the table sits in, re-laid out at the interpolated height on every frame.
///
/// A plain `frame(height:)` fed an animated value is not enough, and the difference is the whole
/// reason this type exists. That interpolates what is *drawn*, but the height the surrounding
/// layout resolves — and therefore the height the card reports and the window matches — goes
/// straight to the target. The result was a window that resized in one step while the table
/// animated inside it: growing, it sprang to full size and the table filled in afterwards;
/// shrinking, it cropped to the final size immediately and the table animated inside the crop.
///
/// Driving the height through `animatableData` re-runs this body every frame, so each frame is a
/// real layout at the interpolated height. The card then measures what is actually on screen and
/// the window follows it the whole way. Same technique as `ReelView`, and for the same reason:
/// SwiftUI hands an `Animatable` view the in-between values, and nothing else does.
///
/// The conformance is main-actor isolated because SwiftUI only ever drives `animatableData` from
/// the render loop on the main actor.
private struct TableBox<Content: View>: View, @MainActor Animatable {
    var height: CGFloat
    var slack: CGFloat
    @ViewBuilder var content: Content

    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    var body: some View {
        content
            .frame(height: max(height, 0), alignment: .top)
            // Clipped with slack rather than to the bounds. Growing, the table is at its full
            // height inside a box that is still short, and without a clip it would spill over the
            // stake chips; clipped exactly, the win glow around the wheel and the reels — which
            // are drawn outside their own frames — would be sliced off at rest.
            .clipShape(Rectangle().inset(by: -slack))
    }
}

/// The natural height of whichever table is on the card, reported out of the layout so the box
/// around it can be animated to match.
private struct TableHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The card's laid-out height, reported out of the layout so the window can match it.
private struct CardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
