import Foundation

/// The running record of play, persisted alongside the bank and read by the stats window.
///
/// Days are bucketed by the *local* calendar day the spin resolved on, which is what "today" and
/// "best day" have to mean for someone reading their own history. Storing instants and bucketing
/// at read time would re-bucket everything whenever the machine changed time zone.
public struct Ledger: Equatable, Sendable {
    /// One calendar day's play. Also reused for the current session, which has the same shape.
    public struct Day: Equatable, Sendable {
        public var spins = 0
        public var wagered = 0
        public var won = 0

        public init(spins: Int = 0, wagered: Int = 0, won: Int = 0) {
            self.spins = spins
            self.wagered = wagered
            self.won = won
        }

        /// Gain, not turnover: what the bank actually moved by.
        public var net: Int { won - wagered }
    }

    /// A day paired with the key it is filed under, so the chart can label a bar it was handed.
    public struct DatedDay: Equatable, Sendable {
        public let key: String
        public let day: Day

        public init(key: String, day: Day) {
            self.key = key
            self.day = day
        }
    }

    // MARK: - Stored

    /// Readable anywhere, writable only in here: the counters are cross-checked against each
    /// other — `blanks` is derived from `pairs` and `triples`, `net` from `wagered` and `won` —
    /// so anything that sets one without the others produces a screen that contradicts itself.
    /// `record(...)` is the only way in.
    ///
    /// Keyed `yyyy-MM-dd` in the local calendar. Keys sort lexicographically in date order, which
    /// is the only reason pruning and "most recent" can avoid parsing them back into dates.
    public internal(set) var days: [String: Day] = [:]

    public internal(set) var spins = 0
    public internal(set) var wagered = 0
    public internal(set) var won = 0
    /// Spins that paid *more* than the stake. A 1x pair is not one of these — see `pushes`.
    public internal(set) var gains = 0
    /// Spins that paid back exactly the stake. Counted apart from gains because 1x pairs are
    /// most of what a slot machine pays, and folding them into a "win rate" flatters it wildly.
    public internal(set) var pushes = 0
    public internal(set) var pairs = 0
    /// Three-of-a-kind counts, keyed by symbol name.
    public internal(set) var triples: [String: Int] = [:]

    public internal(set) var bestWin = 0
    public internal(set) var bestWinSymbol: String?
    public internal(set) var bestWinAt: Date?

    /// High-water mark of the bank, sampled after each spin resolves and after each refill.
    public internal(set) var peakBank = 0
    /// How many times the bank ran dry and had to be topped up.
    public internal(set) var refills = 0

    public internal(set) var winStreak = 0
    public internal(set) var longestWinStreak = 0
    /// Consecutive spins without a gain, pushes included.
    public internal(set) var drySpell = 0
    public internal(set) var longestDrySpell = 0

    public internal(set) var firstSpinAt: Date?
    public internal(set) var lastSpinAt: Date?

    public init() {}

    // MARK: - Recording

    /// Files one resolved spin.
    ///
    /// `bank` is the balance *after* the payout landed, so the high-water mark counts the spin
    /// that set it. `date` and `calendar` are injectable so tests can place a spin on a chosen
    /// day without waiting for one.
    public mutating func record(
        stake: Int,
        payout: Int,
        outcome: SlotMachine.Outcome,
        bank: Int,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) {
        spins += 1
        wagered += stake
        won += payout

        let key = Self.dayKey(for: date, calendar: calendar)
        var day = days[key] ?? Day()
        day.spins += 1
        day.wagered += stake
        day.won += payout
        days[key] = day
        prune()

        switch outcome {
        case .pair: pairs += 1
        case .triple(let symbol): triples[symbol.name, default: 0] += 1
        default: break
        }

        if payout > stake {
            gains += 1
            winStreak += 1
            drySpell = 0
            longestWinStreak = max(longestWinStreak, winStreak)
        } else {
            if payout == stake { pushes += 1 }
            drySpell += 1
            winStreak = 0
            longestDrySpell = max(longestDrySpell, drySpell)
        }

        if payout > bestWin {
            bestWin = payout
            bestWinSymbol = outcome.symbol?.name
            bestWinAt = date
        }

        peakBank = max(peakBank, bank)
        if firstSpinAt == nil { firstSpinAt = date }
        lastSpinAt = date
    }

    public mutating func recordRefill(bank: Int) {
        refills += 1
        peakBank = max(peakBank, bank)
    }

    /// Days kept before the oldest are dropped. Roughly half a year, which keeps the stored blob
    /// a few kilobytes however long someone plays.
    public static let historyLimit = 180

    private mutating func prune() {
        guard days.count > Self.historyLimit else { return }
        let keep = Set(days.keys.sorted().suffix(Self.historyLimit))
        days = days.filter { keep.contains($0.key) }
    }

    // MARK: - Derived

    public var net: Int { won - wagered }

    /// The day with the highest net. Ties go to the more recent day, and a ledger of nothing but
    /// losing days still reports one — "best" is the highest net, not necessarily a profit.
    public var bestDay: DatedDay? {
        days.map { DatedDay(key: $0.key, day: $0.value) }
            .max { (($0.day.net, $0.key)) < (($1.day.net, $1.key)) }
    }

    public func day(_ date: Date, calendar: Calendar = .current) -> Day {
        days[Self.dayKey(for: date, calendar: calendar)] ?? Day()
    }

    /// The `count` calendar days ending on `date`, oldest first. Days with no play come back as
    /// an empty `Day`, so a gap in the history draws as a gap rather than closing up.
    public func recentDays(
        _ count: Int, endingOn date: Date, calendar: Calendar = .current
    ) -> [DatedDay] {
        (0..<count).reversed().compactMap { back in
            guard let then = calendar.date(byAdding: .day, value: -back, to: date) else {
                return nil
            }
            let key = Self.dayKey(for: then, calendar: calendar)
            return DatedDay(key: key, day: days[key] ?? Day())
        }
    }

    /// Credits returned per credit staked, across all time. The house edge, from the other side.
    public var returnRate: Double { wagered > 0 ? Double(won) / Double(wagered) : 0 }

    /// Share of spins that gained. Excludes pushes on purpose — see `pushes`.
    public var gainRate: Double { spins > 0 ? Double(gains) / Double(spins) : 0 }

    public var pushRate: Double { spins > 0 ? Double(pushes) / Double(spins) : 0 }

    public var jackpots: Int { triples["diamond"] ?? 0 }

    /// Three-of-a-kind spins, across every symbol.
    public var tripleTotal: Int { triples.values.reduce(0, +) }

    /// Spins that paid nothing at all. Counted off the landings rather than off `gains` and
    /// `pushes`, which split pairs across both — 1x pairs push, 2x pairs gain.
    public var blanks: Int { max(0, spins - pairs - tripleTotal) }

    // MARK: - Day keys

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static let months = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    /// `"12 Aug"`. Formatted by hand rather than through `DateFormatter`: every other string in
    /// the app is fixed English, and a locale-dependent one would make the snapshot test depend
    /// on whatever region the runner is set to.
    public static func shortLabel(forDay key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]) else { return key }
        return "\(parts[2]) \(months[parts[1] - 1])"
    }

    /// `"12 Aug 2026"`.
    public static func longLabel(forDay key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]) else { return key }
        return "\(parts[2]) \(months[parts[1] - 1]) \(parts[0])"
    }

    public static func longLabel(for date: Date, calendar: Calendar = .current) -> String {
        longLabel(forDay: dayKey(for: date, calendar: calendar))
    }
}

// MARK: - Persistence

/// Decoded key by key with `decodeIfPresent`, so a ledger written by an older build — missing
/// whatever has been added since — loads with defaults instead of throwing. Throwing here would
/// be indistinguishable from "no history", and would quietly wipe somebody's record on upgrade.
extension Ledger: Codable {
    private enum CodingKeys: String, CodingKey {
        case days, spins, wagered, won, gains, pushes, pairs, triples
        case bestWin, bestWinSymbol, bestWinAt
        case peakBank, refills
        case winStreak, longestWinStreak, drySpell, longestDrySpell
        case firstSpinAt, lastSpinAt
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        days = try box.decodeIfPresent([String: Day].self, forKey: .days) ?? [:]
        spins = try box.decodeIfPresent(Int.self, forKey: .spins) ?? 0
        wagered = try box.decodeIfPresent(Int.self, forKey: .wagered) ?? 0
        won = try box.decodeIfPresent(Int.self, forKey: .won) ?? 0
        gains = try box.decodeIfPresent(Int.self, forKey: .gains) ?? 0
        pushes = try box.decodeIfPresent(Int.self, forKey: .pushes) ?? 0
        pairs = try box.decodeIfPresent(Int.self, forKey: .pairs) ?? 0
        triples = try box.decodeIfPresent([String: Int].self, forKey: .triples) ?? [:]
        bestWin = try box.decodeIfPresent(Int.self, forKey: .bestWin) ?? 0
        bestWinSymbol = try box.decodeIfPresent(String.self, forKey: .bestWinSymbol)
        bestWinAt = try box.decodeIfPresent(Date.self, forKey: .bestWinAt)
        peakBank = try box.decodeIfPresent(Int.self, forKey: .peakBank) ?? 0
        refills = try box.decodeIfPresent(Int.self, forKey: .refills) ?? 0
        winStreak = try box.decodeIfPresent(Int.self, forKey: .winStreak) ?? 0
        longestWinStreak = try box.decodeIfPresent(Int.self, forKey: .longestWinStreak) ?? 0
        drySpell = try box.decodeIfPresent(Int.self, forKey: .drySpell) ?? 0
        longestDrySpell = try box.decodeIfPresent(Int.self, forKey: .longestDrySpell) ?? 0
        firstSpinAt = try box.decodeIfPresent(Date.self, forKey: .firstSpinAt)
        lastSpinAt = try box.decodeIfPresent(Date.self, forKey: .lastSpinAt)
    }
}

extension Ledger.Day: Codable {
    private enum CodingKeys: String, CodingKey {
        case spins, wagered, won
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            spins: try box.decodeIfPresent(Int.self, forKey: .spins) ?? 0,
            wagered: try box.decodeIfPresent(Int.self, forKey: .wagered) ?? 0,
            won: try box.decodeIfPresent(Int.self, forKey: .won) ?? 0
        )
    }
}

// MARK: - Sample data

extension Ledger {
    /// A deterministic ledger, played out through the real strip and the real paytable, for the
    /// `--stats` render and the chart snapshot. Shared by both so that eyeballing the screen and
    /// testing it can never drift apart.
    ///
    /// Main-actor only because it scores through `SlotMachine`, which is where the paytable
    /// lives. Every caller — renders and tests — is on the main actor already.
    @MainActor
    public static func sample(
        endingOn today: Date, calendar: Calendar = .current, seed: UInt64 = 0x51A7_5EED
    ) -> Ledger {
        var rng = SplitMix64(seed: seed)
        var ledger = Ledger()
        var bank = SlotMachine.startingBank

        for back in (0..<12).reversed() {
            // An idle day partway back, so the chart is exercised with a real gap in it.
            guard back != 7,
                  let day = calendar.date(byAdding: .day, value: -back, to: today)
            else { continue }

            for _ in 0..<Int.random(in: 18...52, using: &rng) {
                let stake = SlotMachine.betSizes.randomElement(using: &rng) ?? 5
                if bank < stake {
                    bank += SlotMachine.startingBank
                    ledger.recordRefill(bank: bank)
                }
                let landings = (0..<3).map { _ in
                    Int.random(in: 0..<Reel.strip.count, using: &rng)
                }
                let (outcome, payout) = SlotMachine.score(landings, stake: stake)
                bank += payout - stake
                ledger.record(stake: stake, payout: payout, outcome: outcome, bank: bank,
                              at: day, calendar: calendar)
            }
        }
        return ledger
    }
}
