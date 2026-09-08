import SwiftUI

/// The betting layout, drawn as a real one: the zero alongside a 12x3 grid, the "2:1" column boxes
/// down the right, then the dozens and the even-money bets underneath.
///
/// Several chips can be down at once, each with its own stake, which is what a felt is *for* —
/// backing 17, and red, and the second dozen, and having a black 20 still pay two of the three.
///
/// **Click** a spot to put a chip on it, again to stack another. **Press and hold** to take the
/// chips off it. **Drag a rectangle** over the numbers, the way you select files in the Finder, to
/// place one chip on the split, street, corner or line it covers — that is how the compound bets
/// get made, because at this cell size aiming at the line *between* two numbers, the way you would
/// at a table, is a test of mouse control rather than a bet.
public struct RouletteFelt: View {
    /// Every chip on the table.
    public var bets: [RouletteBet: Int]
    /// The last winning number, ringed on the grid so you can see where it went.
    public var result: Int?
    public var disabled: Bool
    public var place: (RouletteBet) -> Void
    /// Called with the numbers a drag covered; the table resolves them to a real chip.
    public var placeCovering: (Set<Int>) -> Void
    public var remove: (RouletteBet) -> Void

    public init(
        bets: [RouletteBet: Int],
        result: Int? = nil,
        disabled: Bool = false,
        place: @escaping (RouletteBet) -> Void,
        placeCovering: @escaping (Set<Int>) -> Void,
        remove: @escaping (RouletteBet) -> Void
    ) {
        self.bets = bets
        self.result = result
        self.disabled = disabled
        self.place = place
        self.placeCovering = placeCovering
        self.remove = remove
    }

    /// The rubber band, in the grid's coordinate space. Held here rather than in the table: an
    /// unfinished selection is not a bet, and nothing outside this view should be able to see one.
    @State private var bandOrigin: CGPoint?
    @State private var bandCorner: CGPoint?

    // Sized to the card's 288pt of content:
    // 20 + 2 + 12x(18 + 2) + 24 = 286.
    static let cell = CGSize(width: 18, height: 21)
    static let gap: CGFloat = 2
    static let zeroWidth: CGFloat = 20
    static let columnWidth: CGFloat = 24
    static let outsideHeight: CGFloat = 20

    /// Every number backed by a chip already on the table.
    private var covered: Set<Int> {
        bets.keys.reduce(into: Set<Int>()) { $0.formUnion($1.covers) }
    }

    public var body: some View {
        VStack(spacing: Self.gap) {
            grid
            dozensRow
            outsideRow
        }
        .opacity(disabled ? 0.45 : 1)
        .animation(.easeOut(duration: 0.15), value: disabled)
    }

    // MARK: - The grid

    /// The whole grid is one coordinate space, so the rubber band can be intersected with cells by
    /// arithmetic rather than by 37 overlapping gesture recognisers.
    private var grid: some View {
        HStack(spacing: Self.gap) {
            zeroCell
            VStack(spacing: Self.gap) {
                ForEach(0..<RouletteLayout.rows, id: \.self) { row in
                    HStack(spacing: Self.gap) {
                        ForEach(0..<RouletteLayout.columns, id: \.self) { column in
                            if let number = RouletteLayout.number(column: column, row: row) {
                                numberCell(number)
                            }
                        }
                        columnCell(row + 1)
                    }
                }
            }
        }
        .coordinateSpace(name: Self.gridSpace)
        // Simultaneous, so it runs alongside the cells' own tap and long press rather than
        // instead of them. Those fail the moment the pointer moves, which is exactly when this
        // one starts.
        .simultaneousGesture(rubberBand)
        .overlay(alignment: .topLeading) { compoundChips }
        .overlay(alignment: .topLeading) { bandOverlay }
    }

    private static let gridSpace = "roulette.grid"

    /// Selects numbers by dragging a rectangle over them, the way you select files in the Finder.
    ///
    /// Rectangle intersection rather than "cells the pointer passed over", and the difference is
    /// the whole point: dragging a box over a 2x2 block gives you exactly the corner, and over two
    /// columns exactly the line, without having to trace a path through them.
    ///
    /// `minimumDistance: 5` so an ordinary click still reaches the cell underneath — a drag gesture
    /// with no threshold swallows every tap on the grid.
    private var rubberBand: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named(Self.gridSpace))
            .onChanged { value in
                guard !disabled else { return }
                bandOrigin = value.startLocation
                bandCorner = value.location
            }
            .onEnded { _ in
                let selected = banded
                bandOrigin = nil
                bandCorner = nil
                guard !disabled, selected.count > 1 else { return }
                placeCovering(selected)
            }
    }

    /// The band as a rectangle, or nil when nothing is being dragged.
    private var band: CGRect? {
        guard let origin = bandOrigin, let corner = bandCorner else { return nil }
        return CGRect(
            x: min(origin.x, corner.x),
            y: min(origin.y, corner.y),
            width: abs(corner.x - origin.x),
            height: abs(corner.y - origin.y)
        )
    }

    /// Every number the band is touching.
    private var banded: Set<Int> {
        guard let band else { return [] }
        return Set((0...36).filter { Self.frame(of: $0).intersects(band) })
    }

    @ViewBuilder
    private var bandOverlay: some View {
        if let band {
            RoundedRectangle(cornerRadius: 2)
                .fill(Palette.gold.opacity(0.18))
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Palette.gold.opacity(0.8), lineWidth: 1)
                }
                .frame(width: band.width, height: band.height)
                .offset(x: band.minX, y: band.minY)
                .allowsHitTesting(false)
        }
    }

    /// Where a number sits in the grid's coordinate space. The zero stands alongside at full
    /// height, so it has a frame of its own rather than a place in the twelve columns.
    static func frame(of number: Int) -> CGRect {
        let fullHeight = CGFloat(RouletteLayout.rows) * cell.height
            + CGFloat(RouletteLayout.rows - 1) * gap
        guard number != 0 else {
            return CGRect(x: 0, y: 0, width: zeroWidth, height: fullHeight)
        }
        guard let column = RouletteLayout.column(of: number),
              let row = RouletteLayout.row(of: number)
        else { return .zero }
        return CGRect(
            x: zeroWidth + gap + CGFloat(column) * (cell.width + gap),
            y: CGFloat(row) * (cell.height + gap),
            width: cell.width,
            height: cell.height
        )
    }

    /// The zero, standing alongside the grid at full height, exactly as it does on a felt.
    private var zeroCell: some View {
        spot(
            0,
            label: "0",
            fill: Palette.pocketGreen,
            width: Self.zeroWidth,
            height: nil,
            fontSize: 10,
            lit: covered.contains(0) || banded.contains(0),
            ringed: result == 0
        )
    }

    private func numberCell(_ number: Int) -> some View {
        spot(
            number,
            label: "\(number)",
            fill: Self.feltPocket(number),
            width: Self.cell.width,
            height: Self.cell.height,
            fontSize: 9.5,
            lit: covered.contains(number) || banded.contains(number),
            ringed: result == number
        )
    }

    private func columnCell(_ which: Int) -> some View {
        namedBox(.column(which), title: "2:1", width: Self.columnWidth, height: Self.cell.height)
    }

    // MARK: - Outside

    private var dozensRow: some View {
        HStack(spacing: Self.gap) {
            // Indented past the zero so the dozens sit under the twelve columns they cover, the
            // way they do on a felt.
            Spacer().frame(width: Self.zeroWidth)
            ForEach(RouletteBet.dozens, id: \.self) { bet in
                namedBox(bet, title: bet.label, width: nil, height: Self.outsideHeight)
            }
            Spacer().frame(width: Self.columnWidth)
        }
    }

    private var outsideRow: some View {
        HStack(spacing: Self.gap) {
            Spacer().frame(width: Self.zeroWidth)
            ForEach(RouletteBet.outsideBets, id: \.self) { bet in
                namedBox(bet, title: bet.label, width: nil, height: Self.outsideHeight,
                         swatch: Self.swatch(for: bet))
            }
            Spacer().frame(width: Self.columnWidth)
        }
    }

    private static func swatch(for bet: RouletteBet) -> Color? {
        switch bet {
        case .red: Palette.pocketRed
        // The lifted black, so the swatch matches the cells the bet actually covers.
        case .black: feltPocket(2)
        default: nil
        }
    }

    /// The wheel's black is nearly the card's own colour, and on the felt that reads as a hole in
    /// the grid rather than a black number. Lifted here only — against the wheel's gold rim the
    /// darker one is right, and this one would look grey.
    static func feltPocket(_ number: Int) -> Color {
        RouletteWheel.color(of: number) == .black
            ? Color(red: 0.15, green: 0.16, blue: 0.19)
            : Palette.pocket(RouletteWheel.color(of: number))
    }

    // MARK: - Spots

    /// A number on the grid, or the zero: a coloured pocket you can put a chip on.
    private func spot(
        _ anchor: Int,
        label: String,
        fill: Color,
        width: CGFloat,
        height: CGFloat?,
        fontSize: CGFloat,
        lit: Bool,
        ringed: Bool
    ) -> some View {
        Text(label)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(lit ? 1 : 0.85))
            .frame(width: width)
            .frame(height: height)
            .frame(maxHeight: height == nil ? .infinity : nil)
            // Barely dimmed when unlit, so the felt still reads as red and black at a
            // glance — which is what the outside bets underneath are about.
            .background(fill.opacity(lit ? 1 : 0.85), in: pocketShape)
            .overlay { cellEdge }
            .overlay { rings(lit: lit, ringed: ringed) }
            .overlay(alignment: .topTrailing) { perchedChip(amount: anchoredStake(at: anchor)) }
            .modifier(SpotGestures(
                disabled: disabled,
                place: { place(.straight(anchor)) },
                clear: { insideBets(covering: anchor).forEach { remove($0.bet) } }
            ))
            .help(cellHelp(at: anchor))
            .contextMenu {
                ForEach(insideBets(covering: anchor), id: \.bet) { entry in
                    Button("Take \(entry.stake) off \(entry.bet.label) \(entry.bet.spread)") {
                        remove(entry.bet)
                    }
                }
            }
    }

    /// Every chip on the grid riding on this number, whether it sits on the number itself or
    /// straddles it as part of a split, street, corner or line.
    ///
    /// What holding a cell clears. A corner's chip is drawn between four numbers and belongs to
    /// none of them, so "hold the thing it is on" has to mean any of the four — otherwise the only
    /// way to take one off would be the context menu.
    private func insideBets(covering number: Int) -> [(bet: RouletteBet, stake: Int)] {
        bets.compactMap { entry in
            guard case .inside(let numbers) = entry.key, numbers.contains(number) else { return nil }
            return (bet: entry.key, stake: entry.value)
        }
        .sorted { $0.bet.covers.count < $1.bet.covers.count }
    }

    /// Tap to place, press and hold to clear.
    ///
    /// One gesture that times its own press and decides on release, rather than a tap and a long
    /// press composed together. Both compositions were tried and both are wrong:
    ///
    /// - `Button` plus `onLongPressGesture` fires **both**. A button's action runs on release
    ///   however long you held it, so a long press took the chip off and immediately put one back.
    /// - `LongPressGesture.exclusively(before: TapGesture())` fires **neither** usefully: the long
    ///   press engages the moment the mouse goes down, which is enough for the exclusive to hand it
    ///   the sequence, and the tap it was supposed to fall back to never runs. That shipped, and
    ///   the result was a felt where clicking did nothing at all.
    ///
    /// Timing the press directly has no such subtlety: down, up, and a subtraction.
    private struct SpotGestures: ViewModifier {
        let disabled: Bool
        let place: () -> Void
        let clear: () -> Void

        /// Held long enough to be deliberate, short enough not to feel stuck.
        static let holdToClear: Double = 0.4
        /// How far the pointer may wander and still count as a press rather than a rubber band.
        private static let slop: CGFloat = 6

        @State private var pressing = false
        /// The countdown to clearing, running while the button is down.
        @State private var countdown: Task<Void, Never>?
        /// Set once this press has been spent — by clearing, or by turning into a drag — so the
        /// release that follows does not also place a chip.
        @State private var spent = false

        func body(content: Content) -> some View {
            content
                .contentShape(Rectangle())
                // Dips over exactly the hold duration, so the press reads as doing something and
                // reaching the bottom is what "now" looks like.
                .scaleEffect(pressing ? 0.88 : 1)
                .animation(.easeOut(duration: pressing ? Self.holdToClear : 0.12), value: pressing)
                .gesture(disabled ? nil : press)
                .onDisappear { countdown?.cancel() }
        }

        /// The chip comes off **when the hold is recognised**, not when the button comes back up:
        /// a countdown starts on the way down and fires on its own. Deciding on release was the
        /// first version and felt broken — you hold, nothing happens, and the thing you asked for
        /// only arrives once you have given up and let go.
        private var press: some Gesture {
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let travelled = abs(value.translation.width) >= Self.slop
                        || abs(value.translation.height) >= Self.slop

                    // A press that travels is a rubber band being drawn over the top of this
                    // cell. It belongs to the grid, so this one gives up on it.
                    if travelled {
                        stop()
                        spent = true
                        return
                    }

                    guard countdown == nil, !spent else { return }
                    pressing = true
                    countdown = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(Self.holdToClear))
                        guard !Task.isCancelled else { return }
                        spent = true
                        pressing = false
                        clear()
                    }
                }
                .onEnded { _ in
                    let alreadySpent = spent
                    stop()
                    spent = false
                    if !alreadySpent { place() }
                }
        }

        private func stop() {
            countdown?.cancel()
            countdown = nil
            pressing = false
        }
    }

    // MARK: - Chips on the grid

    /// The chips sitting on exactly one number, which are the ones a cell draws itself.
    private func anchoredBets(at number: Int) -> [(bet: RouletteBet, stake: Int)] {
        bets.compactMap { entry in
            guard case .inside(let numbers) = entry.key, numbers == [number] else { return nil }
            return (bet: entry.key, stake: entry.value)
        }
    }

    private func anchoredStake(at number: Int) -> Int {
        anchoredBets(at: number).reduce(0) { $0 + $1.stake }
    }

    /// The chips covering more than one number: a split, street, corner or line.
    private var compoundBets: [(bet: RouletteBet, stake: Int, area: CGRect)] {
        bets.compactMap { entry in
            guard case .inside(let numbers) = entry.key, numbers.count > 1,
                  let area = Self.area(covering: numbers)
            else { return nil }
            return (bet: entry.key, stake: entry.value, area: area)
        }
        // Drawn largest first, so a corner's outline does not hide inside a line's.
        .sorted { $0.area.width * $0.area.height > $1.area.width * $1.area.height }
    }

    /// The rectangle a set of numbers occupies on the grid. Legal inside bets are always solid
    /// rectangles of cells — a street is one column, a corner a 2x2 block — so the bounding box of
    /// their frames *is* the shape, not an approximation of it.
    static func area(covering numbers: Set<Int>) -> CGRect? {
        let frames = numbers.map { frame(of: $0) }.filter { $0 != .zero }
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    /// Chips that straddle numbers, drawn where you would physically put them: on the line between
    /// a split, on the intersection of a corner. The outline says which numbers they are riding on,
    /// which a chip sitting on a boundary cannot say by itself.
    @ViewBuilder
    private var compoundChips: some View {
        // The `ZStack(alignment: .topLeading)` is load-bearing, and its absence was a real bug.
        //
        // Every chip here is placed by `offset` from the grid's top-left corner, so they all have
        // to *start* from that corner. Handed a bare `ForEach`, the overlay wraps the children in
        // an implicit stack of its own with **centre** alignment, sizes it to the largest of them,
        // and centres each of the others inside it — so a one-column split next to a two-column
        // corner came out shifted half a cell to the right, and a short outline next to a tall one
        // shifted down.
        //
        // Which is why it only showed up with two chips near each other: on its own, a chip is the
        // largest child and has nothing to be centred against.
        ZStack(alignment: .topLeading) {
            ForEach(compoundBets, id: \.bet) { entry in
                let inset = entry.area.insetBy(dx: -1, dy: -1)
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Palette.gold, lineWidth: 1.5)
                    .frame(width: inset.width, height: inset.height)
                    .offset(x: inset.minX, y: inset.minY)

                // Centred on the shape by laying the chip out in a box the size of it, rather than
                // by offsetting half a guessed width — a three-figure stake is wider than a one.
                chip(amount: entry.stake)
                    .frame(width: entry.area.width, height: entry.area.height)
                    .offset(x: entry.area.minX, y: entry.area.minY)
            }
        }
        .allowsHitTesting(false)
    }

    /// Spells out every chip anchored here, because one badge can be the sum of more than one —
    /// a straight up on 1 and a corner starting at 1 both live on the same cell.
    private func cellHelp(at number: Int) -> String {
        let riding = insideBets(covering: number)
        guard !riding.isEmpty else { return RouletteBet.straight(number).help }
        return riding
            .map { "\($0.bet.label) \($0.bet.spread) — \($0.stake) at \($0.bet.payout)×" }
            .joined(separator: "\n")
    }

    /// One of the named boxes: a dozen, a column, or an even-money bet. Gold when a chip is on it,
    /// matching the stake picker and the slot machine's chips — the card only means one thing by
    /// gold.
    private func namedBox(
        _ boxBet: RouletteBet, title: String, width: CGFloat?, height: CGFloat,
        swatch: Color? = nil
    ) -> some View {
        let staked = bets[boxBet] ?? 0
        return HStack(spacing: 3) {
            if let swatch {
                Circle()
                    .fill(swatch)
                    .overlay { Circle().strokeBorder(.white.opacity(0.4), lineWidth: 0.5) }
                    .frame(width: 6, height: 6)
            }
            Text(title)
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(staked > 0 ? .black.opacity(0.85) : .white.opacity(0.62))
        .frame(maxWidth: width == nil ? .infinity : nil)
        .frame(width: width, height: height)
        .background(staked > 0 ? Palette.gold : .white.opacity(0.09), in: pocketShape)
        .overlay(alignment: .topTrailing) { perchedChip(amount: staked) }
        .modifier(SpotGestures(
            disabled: disabled,
            place: { place(boxBet) },
            clear: { remove(boxBet) }
        ))
        .help(helpText(for: boxBet))
        .contextMenu { removeButton(for: boxBet) }
    }

    @ViewBuilder
    private func removeButton(for bet: RouletteBet) -> some View {
        if bets[bet] != nil {
            Button("Take this chip off") { remove(bet) }
        }
    }

    private func helpText(for bet: RouletteBet) -> String {
        guard let staked = bets[bet] else { return bet.help }
        return "\(bet.help) — \(staked) down"
    }

    /// What is riding on a spot. Only ever drawn where a chip actually is, so an empty felt has no
    /// badges on it at all.
    ///
    /// No offset of its own: a chip on a single spot is nudged out over the corner of its box by
    /// the caller, and one straddling several is centred on them. Baking the nudge in here put
    /// compound chips off the intersection they are supposed to be sitting on.
    @ViewBuilder
    private func chip(amount: Int) -> some View {
        if amount > 0 {
            Text("\(amount)")
                .font(.system(size: 7, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 2.5)
                .frame(height: 9)
                .background(Palette.gold, in: Capsule())
                .overlay { Capsule().strokeBorder(.black.opacity(0.35), lineWidth: 0.5) }
        }
    }

    /// A chip perched on the top-right corner of the box it belongs to, clear of the number.
    @ViewBuilder
    private func perchedChip(amount: Int) -> some View {
        chip(amount: amount).offset(x: 3, y: -4)
    }

    // MARK: - Pieces

    private var pocketShape: RoundedRectangle { RoundedRectangle(cornerRadius: 3) }

    /// Every box on a real layout is outlined. Here it is doing structural work as well as
    /// looking right: it is what separates one 18pt cell from the next.
    private var cellEdge: some View {
        pocketShape.strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
    }

    /// The chip and the last result, drawn as two different rings so they can appear at once —
    /// gold for what you are backing, white for where the ball actually went.
    @ViewBuilder
    private func rings(lit: Bool, ringed: Bool) -> some View {
        ZStack {
            if lit {
                // Softer than it was. With several chips down this ring can be on thirty of the
                // thirty-seven numbers at once, and at full strength that read as noise rather
                // than as "these are the ones you are covered on".
                pocketShape.strokeBorder(Palette.gold.opacity(0.8), lineWidth: 1)
            }
            if ringed {
                pocketShape
                    .strokeBorder(.white.opacity(0.95), lineWidth: 1)
                    .padding(lit ? 2 : 0)
            }
        }
    }
}
