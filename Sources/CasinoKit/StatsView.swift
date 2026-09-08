import SwiftUI

/// The stats window's content.
///
/// Takes plain values rather than the machine, so a snapshot test and the `--stats` render can
/// both pin an exact ledger *and* an exact "today" — half of what is on this screen is relative
/// to the current date, and none of it would be reproducible otherwise. `StatsScreen` is the
/// live wrapper that reads the machine.
public struct StatsView: View {
    public var ledger: Ledger
    public var session: Ledger.Day
    public var credits: Int
    /// Which table's record this is. The figures either side of the breakdown are the same for
    /// both; what a "win" and a "landing" mean is not.
    public var game: Casino.Game
    public var today: Date
    public var calendar: Calendar
    /// Absent in a render or a test, which is also what hides the reset button there.
    public var onReset: (@MainActor () -> Void)?
    /// Absent when there is only one record to look at, which hides the picker.
    public var onSelect: (@MainActor (Casino.Game) -> Void)?

    @State private var confirmingReset = false

    public init(
        ledger: Ledger,
        session: Ledger.Day = Ledger.Day(),
        credits: Int,
        game: Casino.Game = .slots,
        today: Date = Date(),
        calendar: Calendar = .current,
        onReset: (@MainActor () -> Void)? = nil,
        onSelect: (@MainActor (Casino.Game) -> Void)? = nil
    ) {
        self.ledger = ledger
        self.session = session
        self.credits = credits
        self.game = game
        self.today = today
        self.calendar = calendar
        self.onReset = onReset
        self.onSelect = onSelect
    }

    /// How many days the chart covers. Two weeks: long enough to see a shape, short enough that
    /// every bar stays wide enough to read at the window's natural width.
    public static let chartDays = 14

    /// No scroll view and no backdrop of its own: `StatsScreen` adds both for the window. Kept
    /// out of here because `ImageRenderer` does not lay out a `ScrollView`'s content — every
    /// offscreen render of this screen came back as an empty gradient until the scrolling moved
    /// up a level.
    public var body: some View {
        VStack(spacing: 13) {
            Text("STATISTICS")
                .font(.system(size: 10, weight: .heavy))
                .tracking(2.4)
                .foregroundStyle(Palette.gold.opacity(0.85))
                .padding(.bottom, 2)

            if onSelect != nil { tablePicker }

            if ledger.spins == 0 {
                emptyState
            } else {
                bestDay
                netTiles
                chartCard
                bankrollCard
                spinsCard
                streakCard
                breakdownCard
            }

            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sections

    /// Which table's record you are reading. Two records rather than one pooled total: the games
    /// have different odds and a different idea of what a win is, so a combined return rate would
    /// describe neither of them.
    private var tablePicker: some View {
        HStack(spacing: 5) {
            ForEach(Casino.Game.allCases, id: \.self) { table in
                let selected = game == table
                Button {
                    onSelect?(table)
                } label: {
                    Text(table.title)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.3)
                        .foregroundStyle(selected ? .black.opacity(0.85) : .white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .background(selected ? Palette.gold : .white.opacity(0.07),
                                    in: .rect(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.15), value: game)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(game == .slots ? "NO SPINS YET" : "NO COUPS YET")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(.white.opacity(0.6))
            Text(game == .slots
                 ? "Take a spin and this fills in."
                 : "Back a number and this fills in.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    /// The headline the whole screen is built around: the best net any single day has produced.
    private var bestDay: some View {
        let best = ledger.bestDay
        return VStack(spacing: 2) {
            Text("BEST DAY")
                .font(.system(size: 9, weight: .heavy))
                .tracking(2.4)
                .foregroundStyle(Palette.gold.opacity(0.75))

            Text(best.map { Format.signed($0.day.net) } ?? "—")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Self.tint(best?.day.net ?? 0))

            Text(best.map {
                "\(Ledger.longLabel(forDay: $0.key)) · \(Format.count($0.day.spins, game.roundNoun))"
            } ?? "nothing banked yet")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(
            LinearGradient(colors: [Palette.gold.opacity(0.12), Palette.gold.opacity(0.03)],
                           startPoint: .top, endPoint: .bottom),
            in: .rect(cornerRadius: 13)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(Palette.gold.opacity(0.22), lineWidth: 1)
        }
    }

    private var netTiles: some View {
        let day = ledger.day(today, calendar: calendar)
        return HStack(spacing: 8) {
            Tile(label: "TODAY", net: day.net, caption: Format.count(day.spins, game.roundNoun))
            Tile(label: "SESSION", net: session.net,
                 caption: Format.count(session.spins, game.roundNoun))
            Tile(label: "ALL TIME", net: ledger.net,
                 caption: Format.count(ledger.spins, game.roundNoun))
        }
    }

    private var chartCard: some View {
        let series = ledger.recentDays(Self.chartDays, endingOn: today, calendar: calendar)
        return Card(title: "LAST \(Self.chartDays) DAYS") {
            DailyNetChart(series: series)
            HStack {
                Text(series.first.map { Ledger.shortLabel(forDay: $0.key) } ?? "")
                Spacer()
                Text("today")
            }
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.35))
        }
    }

    private var bankrollCard: some View {
        Card(title: "BANKROLL") {
            Row(label: "Credits now", value: Format.grouped(credits))
            Row(label: "Best balance", value: Format.grouped(ledger.peakBank),
                help: "The most you have ever held at once.")
            Row(label: "Times busted", value: "\(ledger.refills)",
                tint: ledger.refills > 0 ? Palette.loss : .white,
                help: "How often the bank ran dry and needed a refill.")
            Row(label: "Biggest payout",
                value: Format.grouped(ledger.bestWin),
                caption: ledger.bestWinAt.map { Ledger.longLabel(for: $0, calendar: calendar) },
                tint: Palette.gold,
                symbol: ledger.bestWinSymbol.flatMap(Self.symbol(named:)),
                help: "The largest single payout, before its stake comes off.")
        }
    }

    private var spinsCard: some View {
        Card(title: game == .slots ? "SPINS" : "COUPS") {
            Row(label: game == .slots ? "Spins played" : "Coups played",
                value: Format.grouped(ledger.spins))
            Row(label: "Staked", value: Format.grouped(ledger.wagered))
            Row(label: "Paid out", value: Format.grouped(ledger.won))
            Row(label: "Return", value: Format.percent(ledger.returnRate),
                tint: Self.tint(ledger.net),
                help: "Credits paid back per credit staked. Over 100% means you are up.")
            Row(label: "Win rate", value: Format.percent(ledger.gainRate),
                help: "Share of rounds that paid more than they cost.")
            // Only the slot machine has pushes. A roulette bet either pays or it does not, so the
            // row would be a permanent 0.0% and read as a broken statistic rather than an absent
            // concept.
            if game == .slots {
                Row(label: "Push rate", value: Format.percent(ledger.pushRate),
                    help: "Share of spins that paid back exactly the stake — a 1x pair.")
            }
        }
    }

    private var streakCard: some View {
        Card(title: "STREAKS") {
            Row(label: "Current run",
                value: currentStreak.text,
                tint: currentStreak.tint,
                help: "Consecutive rounds since the run changed direction.")
            Row(label: "Best winning run",
                value: Format.count(ledger.longestWinStreak, game.roundNoun),
                tint: ledger.longestWinStreak > 0 ? Palette.gold : .white)
            Row(label: "Longest cold run",
                value: Format.count(ledger.longestDrySpell, game.roundNoun),
                help: "The most rounds in a row without a gain, pushes included.")
        }
    }

    private var currentStreak: (text: String, tint: Color) {
        if ledger.winStreak > 0 {
            return ("\(ledger.winStreak) winning", Palette.gold)
        }
        if ledger.drySpell > 0 {
            return ("\(ledger.drySpell) cold", Palette.loss)
        }
        return ("—", .white.opacity(0.6))
    }

    @ViewBuilder
    private var breakdownCard: some View {
        switch game {
        case .slots: landingsCard
        case .roulette: pocketsCard
        }
    }

    /// Where the ball has actually been, laid out on the felt so it is read the same way the bets
    /// are placed. Deliberately captioned rather than left to speak for itself: a wheel that looks
    /// lopsided over eighty coups is a wheel behaving normally, and a stats screen that implies
    /// otherwise is teaching the gambler's fallacy.
    private var pocketsCard: some View {
        let hottest = ledger.hottestPocket
        return Card(title: "POCKETS") {
            PocketHeatGrid(pockets: ledger.pockets)

            Text("where the ball landed — brighter is more often")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.3))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)

            HStack(spacing: 0) {
                colorTally("RED", Palette.pocketRed, ledger.pocketHits(.red))
                colorTally("BLACK", Palette.pocketBlack, ledger.pocketHits(.black))
                colorTally("ZERO", Palette.pocketGreen, ledger.pocketHits(.green))
            }
            .padding(.bottom, 3)

            Row(label: "Hottest number",
                value: hottest.map { "\($0.number) · \(Format.count($0.hits, "hit"))" } ?? "—",
                caption: hottest.map { _ in Format.percent(ledger.hottestShare) + " of coups" },
                tint: Palette.gold,
                help: "The number that has come up most. Over 1/37 means nothing on its own.")
            Row(label: "Bets won", value: "\(ledger.gains)")
            Row(label: "Bets lost", value: "\(max(0, ledger.spins - ledger.gains))")
        }
    }

    private func colorTally(_ label: String, _ swatch: Color, _ hits: Int) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Circle()
                    .fill(swatch)
                    .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5) }
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.45))
            }
            Text("\(hits)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(hits > 0 ? .white : .white.opacity(0.3))
            Text(ledger.coups > 0
                 ? Format.percent(Double(hits) / Double(ledger.coups))
                 : "—")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var landingsCard: some View {
        Card(title: "LANDINGS") {
            HStack(spacing: 0) {
                ForEach(Reel.symbols, id: \.name) { symbol in
                    let hits = ledger.triples[symbol.name] ?? 0
                    VStack(spacing: 3) {
                        SymbolFace(symbol: symbol, pointSize: 15)
                            .frame(height: 20)
                        Text("\(hits)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(hits > 0 ? Palette.gold : .white.opacity(0.3))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        symbol.name == "diamond" && hits > 0
                            ? Palette.gold.opacity(0.1) : .clear,
                        in: .rect(cornerRadius: 7)
                    )
                    .help("\(symbol.name.capitalized) ×3 — pays \(symbol.tripleMultiplier)x")
                }
            }

            Text("three of a kind, by symbol")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.3))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)

            Row(label: "Three of a kind", value: "\(ledger.tripleTotal)")
            Row(label: "Pairs", value: "\(ledger.pairs)")
            Row(label: "No win", value: "\(ledger.blanks)")
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(ledger.firstSpinAt.map {
                "Playing since \(Ledger.longLabel(for: $0, calendar: calendar))"
            } ?? "")
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.35))

            Spacer(minLength: 4)

            // Nothing to clear before the first spin, and offering it there reads as a control
            // that might take the credits with it.
            if onReset != nil, ledger.spins > 0 {
                Button("Reset") { confirmingReset = true }
                    .buttonStyle(QuietButton())
                    .help("Clears the play record. Your credits are not touched.")
            }
        }
        .padding(.top, 2)
        .confirmationDialog("Reset all statistics?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { onReset?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The play record is cleared for good. Your credits are left alone.")
        }
    }

    // MARK: - Pieces

    private struct Card<Content: View>: View {
        let title: String
        @ViewBuilder let content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(Palette.gold.opacity(0.7))
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(.white.opacity(0.05), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.07), lineWidth: 1)
            }
        }
    }

    private struct Tile: View {
        let label: String
        let net: Int
        let caption: String

        var body: some View {
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.4))
                Text(Format.signed(net))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(StatsView.tint(net))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(caption)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.white.opacity(0.05), in: .rect(cornerRadius: 10))
        }
    }

    private struct Row: View {
        let label: String
        let value: String
        var caption: String?
        var tint: Color = .white
        var symbol: Symbol?
        var help: String?

        @ViewBuilder var body: some View {
            // Applied conditionally rather than with `help(help ?? "")`: an empty tooltip string
            // still installs a tooltip, which shows up as a blank box on hover.
            if let help {
                row.help(help)
            } else {
                row
            }
        }

        private var row: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))

                Spacer(minLength: 6)

                if let symbol {
                    SymbolFace(symbol: symbol, pointSize: 11)
                }

                VStack(alignment: .trailing, spacing: 0) {
                    Text(value)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                    if let caption {
                        Text(caption)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            }
        }
    }

    /// Restrained enough to sit on the felt without becoming the loudest thing on the screen,
    /// which a stock destructive button next to a gold headline would be.
    private struct QuietButton: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            // The hover state lives in a nested `View` because `@State` only tracks inside one;
            // on the style itself it would be re-initialised on every render and never change.
            Face(configuration: configuration)
        }

        private struct Face: View {
            let configuration: ButtonStyleConfiguration
            @State private var hovered = false

            var body: some View {
                configuration.label
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hovered ? Palette.loss : .white.opacity(0.45))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        hovered ? Palette.loss.opacity(0.14) : Color.white.opacity(0.06),
                        in: .rect(cornerRadius: 6)
                    )
                    .opacity(configuration.isPressed ? 0.6 : 1)
                    .onHover { hovered = $0 }
                    .animation(.easeOut(duration: 0.12), value: hovered)
            }
        }
    }

    // MARK: - Derived

    static func tint(_ net: Int) -> Color {
        if net > 0 { return Palette.gold }
        if net < 0 { return Palette.loss }
        return .white.opacity(0.6)
    }

    private static func symbol(named name: String) -> Symbol? {
        Reel.symbols.first { $0.name == name }
    }
}

/// Every pocket on the felt, tinted by how often the ball has landed in it.
///
/// Laid out exactly as `RouletteFelt` lays out the betting grid, so the shape you learn placing
/// chips is the shape you read the history on. Free of text, like `DailyNetChart` and for the same
/// reason: it is pure geometry, which renders identically on any machine.
public struct PocketHeatGrid: View {
    public var pockets: [Int: Int]
    public var cell: CGSize
    public var gap: CGFloat

    public init(
        pockets: [Int: Int],
        cell: CGSize = CGSize(width: 26, height: 17),
        gap: CGFloat = 2
    ) {
        self.pockets = pockets
        self.cell = cell
        self.gap = gap
    }

    public var body: some View {
        // Scaled to the busiest pocket rather than to a fixed ceiling, so the grid reads at eighty
        // coups and at eighty thousand.
        let peak = max(pockets.values.max() ?? 0, 1)

        HStack(spacing: gap) {
            pocket(0)
                .frame(width: cell.width * 0.8)
                .frame(maxHeight: .infinity)

            VStack(spacing: gap) {
                ForEach(0..<RouletteLayout.rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<RouletteLayout.columns, id: \.self) { column in
                            if let number = RouletteLayout.number(column: column, row: row) {
                                pocket(number, peak: peak)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: cell.height)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: cell.height * CGFloat(RouletteLayout.rows)
               + gap * CGFloat(RouletteLayout.rows - 1))
    }

    private func pocket(_ number: Int, peak: Int = 1) -> some View {
        let hits = pockets[number] ?? 0
        // Square-rooted, not linear: over a real run most pockets sit close together and one or
        // two run ahead, and a linear ramp renders that as a grid of near-black with a single
        // bright cell. The root spreads the crowded low end out where the differences are.
        let heat = peak > 0 ? pow(Double(hits) / Double(peak), 0.5) : 0
        return RoundedRectangle(cornerRadius: 3)
            // The felt's lifted black, not the wheel's. Ramping opacity on a near-black colour
            // has nowhere to go: a black pocket with the most hits in the record would come out
            // looking exactly like one with none.
            .fill(RouletteFelt.feltPocket(number)
                .opacity(hits == 0 ? 0.22 : 0.4 + 0.6 * heat))
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(.white.opacity(hits == 0 ? 0.04 : 0.10), lineWidth: 0.5)
            }
            .help("\(number): \(hits == 1 ? "1 hit" : "\(hits) hits")")
    }
}

/// Net per day as bars either side of a zero line: gold above, red below.
///
/// Split out and free of text so the snapshot test that guards it compares pure geometry, which
/// is the part that can silently break and the part that renders identically on any machine.
public struct DailyNetChart: View {
    public var series: [Ledger.DatedDay]
    public var height: CGFloat

    public init(series: [Ledger.DatedDay], height: CGFloat = 66) {
        self.series = series
        self.height = height
    }

    public var body: some View {
        // Scaled to the biggest swing in view rather than to a fixed ceiling: a session of 1
        // credit bets and a session of 25s should both fill the frame.
        let peak = max(series.map { abs($0.day.net) }.max() ?? 0, 1)
        let half = (height - 1) / 2

        HStack(alignment: .center, spacing: 3) {
            ForEach(series, id: \.key) { point in
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        Color.clear
                        if point.day.net > 0 {
                            bar(Palette.gold, length: length(point.day.net, peak, half))
                        } else if point.day.net == 0 && point.day.spins > 0 {
                            // Played and came out level. Brighter than the zero line it sits on,
                            // or a day spent breaking even would read as a day off.
                            bar(.white.opacity(0.55), length: 2)
                        }
                    }
                    .frame(height: half)

                    Rectangle()
                        .fill(.white.opacity(0.14))
                        .frame(height: 1)

                    ZStack(alignment: .top) {
                        Color.clear
                        if point.day.net < 0 {
                            bar(Palette.loss, length: length(point.day.net, peak, half))
                        }
                    }
                    .frame(height: half)
                }
                .frame(maxWidth: .infinity)
                .help("\(Ledger.shortLabel(forDay: point.key)): \(Format.signed(point.day.net))")
            }
        }
        .frame(height: height)
    }

    /// Floored at 2pt: a day that netted 1 credit against a 900 credit peak still has to be
    /// visible as a day that was played.
    private func length(_ net: Int, _ peak: Int, _ half: CGFloat) -> CGFloat {
        max(2, half * CGFloat(abs(net)) / CGFloat(peak))
    }

    private func bar(_ color: Color, length: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(LinearGradient(colors: [color, color.opacity(0.55)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(height: length)
    }
}

/// The live stats screen. Reads the machine inside `body`, which is what registers it for
/// observation — the window is long-lived, and pulling the ledger out at construction time would
/// freeze the numbers at whatever they were when it opened.
public struct StatsScreen: View {
    private let casino: Casino
    /// Bumped by the window controller each time the window is shown. Used as a `task` identity,
    /// which is what re-syncs the tab — the view is built once and reused, so an initial value
    /// would only ever reflect the table you were at the *first* time you opened it.
    private let opening: Int

    /// Which table's record is being read. Its own state rather than the casino's `game`, so you
    /// can look over your roulette history while the widget sits at the slot machine; picking a
    /// table to *read* is not picking one to play.
    @State private var showing: Casino.Game = .slots

    public init(casino: Casino, opening: Int = 0) {
        self.casino = casino
        self.opening = opening
    }

    public var body: some View {
        ScrollView {
            // "Today" is resolved per update rather than on a clock. Every figure here changes on
            // a spin anyway, and a window left open across midnight rolls over on the next one.
            StatsView(
                ledger: casino.ledger(for: showing),
                session: casino.session(for: showing),
                credits: casino.bank.credits,
                game: showing,
                today: Date(),
                onReset: { casino.resetLedger(for: showing) },
                onSelect: { showing = $0 }
            )
        }
        .background { Palette.felt }
        // Every open lands on the table the widget is showing — that is the one you were
        // wondering about when you clicked the button. Switching tabs in here afterwards sticks
        // until the next open.
        .task(id: opening) { showing = casino.game }
    }
}

/// Grouping and signs, done by hand.
///
/// `Int.formatted()` reads `Locale.current`, not the SwiftUI environment — so it would ignore the
/// locale the snapshot harness pins and put a reference recorded here out of reach of a runner in
/// another region. The trade is that this screen groups with commas wherever it is opened, unlike
/// the widget's credits counter. Acceptable for a screen whose every other word is fixed English.
enum Format {
    static func grouped(_ value: Int) -> String {
        let digits = String(abs(value))
        var out = value < 0 ? "−" : ""
        for (offset, digit) in digits.enumerated() {
            if offset > 0, (digits.count - offset).isMultiple(of: 3) { out.append(",") }
            out.append(digit)
        }
        return out
    }

    /// `+1,240`, `−85`, `0`. Uses a real minus sign, matching the SPIN button.
    static func signed(_ value: Int) -> String {
        value > 0 ? "+\(grouped(value))" : grouped(value)
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.1f%%", fraction * 100)
    }

    static func count(_ value: Int, _ noun: String) -> String {
        "\(grouped(value)) \(noun)\(value == 1 ? "" : "s")"
    }
}
