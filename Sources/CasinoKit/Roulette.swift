import Foundation
import Observation
import SwiftUI

public enum PocketColor: Hashable, Sendable {
    case red, black, green
}

/// A European single-zero wheel: 37 pockets, one green.
///
/// Single zero rather than double: it is the wheel the payouts below are honest against. Adding a
/// 00 pocket without changing anything else would quietly double the house edge.
public enum RouletteWheel {
    /// Pockets in *physical* order, clockwise from the zero — not sorted. The running order is the
    /// whole point of a wheel: it alternates colour between neighbours and spreads the low and high
    /// numbers evenly around the rim, so no arc of the wheel favours a bet.
    public static let order: [Int] = [
        0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23,
        10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26,
    ]

    public static let pockets = order.count

    /// The reds are not simply the odd numbers. Colour alternates around the *wheel*, and the
    /// numbers are not in wheel order, so the set has to be spelled out.
    private static let reds: Set<Int> = [
        1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36,
    ]

    public static func color(of number: Int) -> PocketColor {
        if number == 0 { return .green }
        return reds.contains(number) ? .red : .black
    }

    public static func colorName(of number: Int) -> String {
        switch color(of: number) {
        case .red: "RED"
        case .black: "BLACK"
        case .green: "GREEN"
        }
    }

    /// Where a pocket sits on the drawn wheel: clockwise degrees from the top, before rotation.
    public static func angle(ofPocketAt index: Int) -> Double {
        Double(index) * 360 / Double(pockets)
    }

    public static func index(of number: Int) -> Int? {
        order.firstIndex(of: number)
    }
}

/// What you can put a chip on: the whole felt.
///
/// Outside bets and dozens name themselves; everything inside the grid is a *set* of numbers, and
/// which sets are legal is `RouletteLayout`'s business. Modelling inside bets as a set rather than
/// as separate `split`/`street`/`corner` cases is what lets the payout be one rule — 36 over the
/// numbers covered — instead of a table that can disagree with itself.
public enum RouletteBet: Hashable, Sendable {
    case red, black, even, odd, low, high
    /// 1, 2 or 3 — the first, second or third dozen.
    case dozen(Int)
    /// 1, 2 or 3 — the "2:1" boxes down the right of the grid, numbered from the top.
    case column(Int)
    /// A chip on the grid: one number, or several that form a legal shape on it.
    case inside(Set<Int>)

    public static let outsideBets: [RouletteBet] = [.red, .black, .even, .odd, .low, .high]
    public static let dozens: [RouletteBet] = [.dozen(1), .dozen(2), .dozen(3)]
    public static let columns: [RouletteBet] = [.column(1), .column(2), .column(3)]

    /// A single number. Not a case of its own — it is the one-element inside bet — but spelled
    /// like one because that is how every caller thinks of it.
    public static func straight(_ number: Int) -> RouletteBet { .inside([number]) }

    /// Every pocket this chip is on.
    public var covers: Set<Int> {
        switch self {
        case .red: Set((1...36).filter { RouletteWheel.color(of: $0) == .red })
        case .black: Set((1...36).filter { RouletteWheel.color(of: $0) == .black })
        case .even: Set((1...36).filter { $0.isMultiple(of: 2) })
        case .odd: Set((1...36).filter { !$0.isMultiple(of: 2) })
        case .low: Set(1...18)
        case .high: Set(19...36)
        case .dozen(let which): RouletteLayout.dozen(which)
        case .column(let which): RouletteLayout.columnBet(which)
        case .inside(let numbers): numbers
        }
    }

    /// Total returned per credit staked, stake included. An even-money bet pays 2, which is a gain
    /// of 1 — the same convention the slot machine's multipliers use, so the credits arithmetic
    /// reads the same on both tables.
    ///
    /// One rule for every bet on the felt: 36 divided by how many of the 37 pockets it covers.
    /// That ratio *is* the single-zero house edge, and deriving it means no bet can be mispriced
    /// by a typo in a table.
    public var payout: Int {
        let covered = covers.count
        return covered > 0 ? 36 / covered : 0
    }

    /// Zero loses every bet here except one that names the zero itself. That single pocket *is*
    /// the house edge — 1/37, or 2.7%.
    public func wins(_ number: Int) -> Bool { covers.contains(number) }

    public var isValid: Bool {
        switch self {
        case .dozen(let which), .column(let which): (1...3).contains(which)
        case .inside(let numbers): RouletteLayout.isLegalInside(numbers)
        default: true
        }
    }

    public var label: String {
        switch self {
        case .red: "RED"
        case .black: "BLACK"
        case .even: "EVEN"
        case .odd: "ODD"
        case .low: "1–18"
        case .high: "19–36"
        case .dozen(let which): ["1ST 12", "2ND 12", "3RD 12"][max(0, min(2, which - 1))]
        case .column(let which): "COL \(max(1, min(3, which)))"
        case .inside(let numbers):
            numbers.count == 1 ? "№ \(numbers.first ?? 0)" : RouletteLayout.insideName(numbers)
        }
    }

    /// The numbers an inside bet is on, as `1·2·3`. Empty for everything else, which names itself.
    public var spread: String {
        guard case .inside(let numbers) = self, numbers.count > 1 else { return "" }
        return numbers.sorted().map(String.init).joined(separator: "·")
    }

    /// What the current chip reads as above the felt: what it is, and what it returns.
    public var summary: String {
        let spread = spread
        return spread.isEmpty ? "\(label) · \(payout)×" : "\(label) \(spread) · \(payout)×"
    }

    public var help: String {
        switch self {
        case .inside(let numbers) where numbers.count == 1:
            "Straight up on \(numbers.first ?? 0) — pays \(payout)×"
        case .inside(let numbers):
            """
            \(RouletteLayout.insideName(numbers).capitalized) on \
            \(numbers.sorted().map(String.init).joined(separator: ", ")) — pays \(payout)×
            """
        default:
            "\(label) — pays \(payout)×"
        }
    }

    /// A stable string for `UserDefaults`. `RawRepresentable` cannot express the cases that carry
    /// a value, so the encoding is spelled out.
    public var storageKey: String {
        switch self {
        case .red: "red"
        case .black: "black"
        case .even: "even"
        case .odd: "odd"
        case .low: "low"
        case .high: "high"
        case .dozen(let which): "dozen:\(which)"
        case .column(let which): "column:\(which)"
        case .inside(let numbers):
            "inside:\(numbers.sorted().map(String.init).joined(separator: ","))"
        }
    }

    public init?(storageKey: String) {
        let parts = storageKey.split(separator: ":", maxSplits: 1)
        switch parts.first.map(String.init) {
        case "red": self = .red
        case "black": self = .black
        case "even": self = .even
        case "odd": self = .odd
        case "low": self = .low
        case "high": self = .high
        case "dozen":
            guard parts.count == 2, let which = Int(parts[1]) else { return nil }
            self = .dozen(which)
        case "column":
            guard parts.count == 2, let which = Int(parts[1]) else { return nil }
            self = .column(which)
        // `straight` is also read, so a bet saved by the build before the felt arrived comes back
        // as the straight up it was rather than silently resetting to red.
        case "inside", "straight":
            guard parts.count == 2 else { return nil }
            let fields = parts[1].split(separator: ",")
            let numbers = fields.compactMap { Int($0) }
            guard numbers.count == fields.count else { return nil }
            self = .inside(Set(numbers))
        default: return nil
        }
        guard isValid else { return nil }
    }
}

/// The roulette table.
///
/// Shape deliberately mirrors `SlotMachine`: the stake leaves the bank the moment the wheel is
/// pushed, resolution is scheduled for when the animation lands, and an unresolved round is
/// refundable so quitting mid-spin cannot bank the debit.
@MainActor
@Observable
public final class Roulette {
    public enum Outcome: Equatable {
        case idle
        case spinning
        case lost(Int)
        case won(Int)

        /// The number the ball landed in, once there is one.
        public var number: Int? {
            switch self {
            case .lost(let number), .won(let number): number
            case .idle, .spinning: nil
            }
        }
    }

    /// How long the wheel runs. Longer than the reels take, because the interest is in the last
    /// of it — the ball leaving the track, dropping into a pocket, and being carried round by the
    /// wheel to wherever it stops.
    public static let spinDuration: Double = 2.6

    /// Whole turns of travel before the settle. The ball takes more, in the opposite direction,
    /// which is what makes the counter-rotation read at a glance.
    ///
    /// How far the wheel turns in a spin, nominally. The real figure is up to a turn more — a
    /// random extra, so it never comes to rest in the same place twice — and the duration is
    /// scaled to whatever it comes to, so the *speed* is the same every time.
    ///
    /// Not private, so `RouletteSpeedTests` can sample the easing at 60fps against it.
    static let nominalTravel = 2.5

    /// The spin's easing, as bezier control points: nearly linear, easing only at the end.
    ///
    /// Spelled out rather than named so the speed test can evaluate the same curve the animation
    /// runs; `Animation` does not expose its own. That matters because the curve is what decides
    /// whether the wheel strobes, and the curve is what was wrong to begin with — it inherited the
    /// reels' `timingCurve(0.1, 0.62, ...)`, which puts 62% of the travel into the first 10% of the
    /// time. About six times the average speed at the start, which on a 37-pocket wheel is more
    /// than two pockets between frames. The reels get away with it because they blur; the wheel
    /// does not, so it lost its numbers.
    ///
    /// What matters is the ratio of *peak* speed to average, because the peak is what aliases and
    /// the average is what makes a spin feel quick. The reels' curve peaks at about six times
    /// average and `easeOut` at about 1.7, which forced a long, slow spin to stay legible. This
    /// one is close to constant speed until it settles, peaking at about 1.2 — so the same peak
    /// buys a much shorter spin. It is also what a real wheel does: it turns steadily and then
    /// friction takes it.
    static let spinCurve = (x1: 0.0, y1: 0.0, x2: 0.8, y2: 1.0)

    private static let betsKey = "rouletteBets"
    private static let betKey = "rouletteBet"
    private static let stakeKey = "rouletteStake"
    private static let ledgerKey = "rouletteLedger"

    /// Every chip on the table, and how much is riding on each. A real player covers several spots
    /// at once — a number, its colour, and the dozen it sits in — and the whole point of a felt is
    /// that you can.
    public private(set) var bets: [RouletteBet: Int] = [:]
    /// The denomination the next chip is placed at. Not the total staked — see `totalStake`.
    public private(set) var stake: Int

    /// This table's play record. Kept apart from the slot machine's rather than pooled: the two
    /// games have different odds, different payouts and a different idea of what a win is, so one
    /// combined return rate would describe neither of them.
    public private(set) var ledger: Ledger
    /// Totals since launch, not persisted — "this session" means this run of the app.
    public private(set) var session = Ledger.Day()

    public private(set) var isSpinning = false
    public private(set) var outcome: Outcome = .idle
    public private(set) var lastWin = 0
    /// What the round in flight, or the last resolved round, actually cost.
    public private(set) var lastStake = 0
    /// Bumped on every resolved round so the view can retrigger an animation even when two
    /// identical results land back to back.
    public private(set) var spinCount = 0
    /// How many of the chips on the table the last result paid. With several down at once, "you
    /// won" is a count rather than a yes or no.
    public private(set) var winningBets = 0

    /// Wheel rotation in turns, monotonically increasing, animated by SwiftUI. Where it comes to
    /// rest is nobody's business but chance's — there is no marker to line anything up with, and
    /// the ball rides the winning pocket to wherever the wheel stops.
    public private(set) var wheelTurns: Double = 0
    /// Where this spin began and ends. Not animated — the view needs both ends to know how far
    /// through the spin the interpolated `wheelTurns` is, which is what every phase of the ball's
    /// flight is keyed off.
    public private(set) var wheelStart: Double = 0
    public private(set) var wheelTarget: Double = 0
    /// The pocket the ball ends up in, as an index into `RouletteWheel.order`.
    ///
    /// The ball has no animated position of its own any more. Once it is captured it simply *is*
    /// this pocket, and rides round with the wheel to wherever the wheel stops — which is what a
    /// ball does, and what makes the last second of a spin the wheel carrying it rather than the
    /// two arriving at the same place by arrangement.
    public private(set) var landingIndex = 0
    /// Where the ball sits as a spin begins, in degrees. It rests in the previous winning pocket,
    /// at whatever angle the wheel left it — so the next spin has to start its flight from there
    /// rather than from a fixed point.
    public private(set) var ballStart: Double = 0

    private let bank: Bank
    private let defaults: UserDefaults

    /// `bank` is injectable so the slot machine can share this table's purse; left out, the table
    /// opens its own against the same defaults.
    public init(bank: Bank? = nil, defaults: UserDefaults = .standard) {
        self.bank = bank ?? Bank(defaults: defaults)
        self.defaults = defaults

        // A ledger that will not decode is treated as no ledger, for the same reason the slot
        // machine's is: throwing here is indistinguishable from "no history" and would wipe a
        // record nobody can read anyway.
        ledger = (defaults.data(forKey: Self.ledgerKey)
            .flatMap { try? JSONDecoder().decode(Ledger.self, from: $0) }) ?? Ledger()

        if let stored = defaults.object(forKey: Self.stakeKey) as? Int,
           Bank.betSizes.contains(stored) {
            stake = stored
        } else {
            stake = Bank.betSizes[1]
        }

        bets = Self.decodeBets(defaults.data(forKey: Self.betsKey))
        if bets.isEmpty {
            // A single bet saved by the build before the felt held several. Read rather than
            // dropped, so upgrading does not clear somebody's table.
            if let single = defaults.string(forKey: Self.betKey)
                .flatMap(RouletteBet.init(storageKey:)) {
                bets = [single: stake]
            } else {
                // A fresh table opens with one chip down, so the gold button does something on the
                // first click rather than sitting disabled next to an empty felt.
                bets = [.red: stake]
            }
        }
    }

    // MARK: - The table

    /// What the round in front of you costs: every chip on the felt added up.
    public var totalStake: Int { bets.values.reduce(0, +) }

    /// Every pocket backed by anything currently on the table.
    public var covered: Set<Int> {
        bets.keys.reduce(into: Set<Int>()) { $0.formUnion($1.covers) }
    }

    /// The chips, in a stable order for display: biggest stake first, then by name.
    public var placedBets: [(bet: RouletteBet, stake: Int)] {
        bets.map { (bet: $0.key, stake: $0.value) }
            .sorted { ($0.stake, $1.bet.label) > ($1.stake, $0.bet.label) }
    }

    /// Adds a chip at the current denomination, stacking on whatever is already there — which is
    /// what clicking the same spot twice does at a real table.
    ///
    /// Refused when the bank could not cover the table afterwards. Stakes are only taken when the
    /// wheel is pushed, so without this you could lay out more than you hold and discover it as a
    /// spin that silently does nothing.
    public func place(_ bet: RouletteBet) {
        guard !isSpinning, bet.isValid, bank.credits >= totalStake + stake else { return }
        bets[bet, default: 0] += stake
        saveBets()
    }

    public func remove(_ bet: RouletteBet) {
        guard !isSpinning, bets[bet] != nil else { return }
        bets[bet] = nil
        saveBets()
    }

    public func clearBets() {
        guard !isSpinning, !bets.isEmpty else { return }
        bets = [:]
        saveBets()
    }

    // MARK: - Play

    public var canSpin: Bool {
        !isSpinning && totalStake > 0 && bank.canAfford(totalStake)
    }

    /// The number the ball last landed in, or `nil` before the first round of the session.
    public var result: Int? { outcome.number }

    /// Puts a chip on the numbers dragged across, resolved *upward* to the smallest chip on the
    /// felt that covers them.
    ///
    /// Resolving upward is not a nicety. Every three-number subset of a corner is an illegal shape,
    /// in every order, so a rule of "cover exactly what was touched" would make corners and lines
    /// unplaceable. It also matches the felt: a chip on a corner backs all four numbers, and you
    /// were never placing them one at a time.
    public func placeInside(covering numbers: Set<Int>) {
        guard !isSpinning, let resolved = RouletteLayout.resolve(numbers) else { return }
        place(.inside(resolved))
    }

    public func setStake(_ value: Int) {
        guard !isSpinning, Bank.betSizes.contains(value) else { return }
        stake = value
        defaults.set(stake, forKey: Self.stakeKey)
    }

    public func spin() {
        let staked = totalStake
        guard !isSpinning, staked > 0, bank.withdraw(staked) else { return }

        isSpinning = true
        outcome = .spinning
        lastWin = 0
        lastStake = staked

        // The pocket is drawn uniformly from the wheel, not from the numbers: they are the same
        // 37 either way here, but the wheel is the thing the ball actually lands in.
        let landing = Int.random(in: 0..<RouletteWheel.pockets)

        // Set before the animation block, and not animated: the view needs both ends of the travel
        // to know how far through the spin it is, which it cannot get from the interpolated value
        // on its own.
        // Read off the *outgoing* pocket, before it is replaced: this is where the ball is
        // sitting right now, and where its next flight has to begin.
        ballStart = Self.ballAngle(pocketAt: landingIndex, wheelTurns: wheelTurns)

        wheelStart = wheelTurns
        landingIndex = landing

        // Where it stops is chance's, not arithmetic's. There is no marker to park a pocket
        // against, so the only thing the travel has to be is consistent in *length*.
        let travel = Self.travel(extra: Double.random(in: 0..<1))
        wheelTarget = wheelTurns + travel

        // Scaled to the travel, which is what makes every spin the same *speed*. A fixed duration
        // over a variable distance is a wheel that visibly spins harder some times than others.
        let duration = Self.spinDuration * travel / Self.nominalTravel
        let curve = Animation.timingCurve(
            Self.spinCurve.x1, Self.spinCurve.y1, Self.spinCurve.x2, Self.spinCurve.y2,
            duration: duration
        )
        withAnimation(curve) {
            wheelTurns = wheelTarget
        }

        let number = RouletteWheel.order[landing]
        Task { [number] in
            // A cancelled sleep must abort the round. `try?` would swallow the cancellation and
            // resolve immediately instead, paying out a spin that never finished.
            do {
                try await Task.sleep(for: .seconds(duration + 0.1))
            } catch {
                return
            }
            self.resolve(number)
        }
    }

    /// How far the wheel turns on a spin: the nominal, plus up to a turn of `extra`.
    ///
    /// The extra is what makes the wheel stop somewhere different every time, the way a real one
    /// does. It used to be forced — the winning pocket had to finish under a marker at the top, so
    /// the fraction was whatever that took — and with the marker gone there is nothing to line up
    /// and the fraction can simply be random.
    ///
    /// The duration is scaled to whatever this comes to, which is what keeps the *speed* the same
    /// from spin to spin. Bounded to a single turn of variation so the length stays close too.
    static func travel(extra: Double) -> Double {
        nominalTravel + min(max(extra, 0), 1)
    }

    /// Where the ball sits when it is resting in `index`, given the wheel's rotation.
    ///
    /// Reduced to a single turn, because `wheelTurns` counts every turn since launch and anything
    /// built from it has to be reduced before it is used.
    static func ballAngle(pocketAt index: Int, wheelTurns: Double) -> Double {
        (RouletteWheel.angle(ofPocketAt: index) + wheelTurns * 360)
            .truncatingRemainder(dividingBy: 360)
    }

    private func resolve(_ number: Int) {
        let staked = lastStake

        // Every chip is settled independently, which is the whole point of a table full of them:
        // backing 17 and RED and the 2nd dozen means a black 20 still pays two of the three.
        var payout = 0
        var bestBet: RouletteBet?
        var bestReturn = 0
        for (bet, amount) in bets where bet.wins(number) {
            let returned = amount * bet.payout
            payout += returned
            if returned > bestReturn {
                bestReturn = returned
                bestBet = bet
            }
        }
        winningBets = bets.keys.filter { $0.wins(number) }.count

        if payout > 0 {
            bank.deposit(payout)
            lastWin = payout
            outcome = .won(number)
        } else {
            lastWin = 0
            outcome = .lost(number)
        }

        isSpinning = false
        spinCount += 1

        // Filed with the chip that returned the most, since that is what "biggest payout" on the
        // stats screen is asking about. The table cannot have changed since the wheel was pushed —
        // the felt is locked from `spin()` until here.
        ledger.record(stake: staked, payout: payout,
                      detail: .roulette(number: number, winningBet: bestBet),
                      bank: bank.credits)
        session.spins += 1
        session.wagered += staked
        session.won += payout

        // A losing round can leave the chip denomination unaffordable; drop to the largest that
        // still fits rather than leaving one nobody can place.
        if !bank.canAfford(stake), let affordable = bank.largestAffordableStake() {
            setStake(affordable)
        }
        // And the table itself can now be beyond the balance, which would make `SPIN` inert with
        // no explanation. Trimmed to what is affordable, biggest chip first.
        trimBetsToBalance()
        save()
    }

    /// Drops chips, smallest first, until the table is something the bank can cover.
    private func trimBetsToBalance() {
        while totalStake > bank.credits, !bets.isEmpty {
            guard let smallest = bets.min(by: { ($0.value, $0.key.label) < ($1.value, $1.key.label) })
            else { break }
            bets[smallest.key] = nil
        }
        saveBets()
    }

    /// Returns the stake of a round that never resolved. Credits are debited when the wheel is
    /// pushed, so quitting mid-spin would otherwise persist the debit with no payout.
    public func refundUnresolvedSpin() {
        guard isSpinning else { return }
        bank.deposit(lastStake)
        isSpinning = false
        outcome = .idle
    }

    /// Clears the last result without touching the balance or the wheel's resting position.
    public func reset() {
        guard !isSpinning else { return }
        lastWin = 0
        lastStake = 0
        outcome = .idle
    }

    /// Tops the shared bank up and files the refill here. See `SlotMachine.refill` for why it is
    /// filed at one table rather than both.
    public func refill() {
        guard !isSpinning else { return }
        bank.refill()
        ledger.recordRefill(bank: bank.credits)
        reset()
        save()
    }

    /// Clears this table's play record without touching the bank. The slot machine's record is
    /// left alone — they are separate diaries and are reset separately.
    public func resetLedger() {
        ledger = Ledger()
        ledger.peakBank = bank.credits
        session = Ledger.Day()
        save()
    }

    /// Bets are written through as they are placed; this is for the quit path, which saves
    /// everything at once and should not have to know that.
    public func save() {
        bank.save()
        saveBets()
        defaults.set(stake, forKey: Self.stakeKey)
        if let encoded = try? JSONEncoder().encode(ledger) {
            defaults.set(encoded, forKey: Self.ledgerKey)
        }
    }

    /// Stored as `storageKey: amount`, which is legible in `defaults read` and survives a bet
    /// shape being added later — an entry that no longer parses is simply dropped on load.
    private func saveBets() {
        let encodable = Dictionary(uniqueKeysWithValues: bets.map { ($0.key.storageKey, $0.value) })
        if let data = try? JSONEncoder().encode(encodable) {
            defaults.set(data, forKey: Self.betsKey)
        }
    }

    private static func decodeBets(_ data: Data?) -> [RouletteBet: Int] {
        guard let data,
              let stored = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }

        var bets: [RouletteBet: Int] = [:]
        for (key, amount) in stored {
            guard amount > 0, let bet = RouletteBet(storageKey: key) else { continue }
            bets[bet] = amount
        }
        return bets
    }

    // MARK: - Staging

    /// Parks the wheel on an exact result without playing for it, for offscreen renders and the
    /// window snapshots. Nothing is persisted, for the same reason `SlotMachine.stage` persists
    /// nothing: a fabricated balance written to disk is free credits.
    public func stage(
        number: Int,
        bets: [RouletteBet: Int],
        stake: Int = Bank.betSizes[1],
        spinning: Bool = false,
        progress: Double = Roulette.stagedSpinProgress
    ) {
        precondition((0...36).contains(number), "no such pocket")
        guard let landing = RouletteWheel.index(of: number) else { return }

        self.bets = bets.filter { $0.key.isValid && $0.value > 0 }
        self.stake = Bank.betSizes.contains(stake) ? stake : Bank.betSizes[1]
        landingIndex = landing
        lastStake = totalStake

        // No extra: a staged render has to come out the same every time it is taken.
        wheelStart = 0
        wheelTarget = Self.travel(extra: 0)
        ballStart = 0

        guard !spinning else {
            // Frozen partway through the travel. `progress` is the caller's, so a snapshot can pin
            // the ball out on its track, mid-bounce, or already riding the wheel round.
            wheelTurns = wheelTarget * progress
            isSpinning = true
            outcome = .spinning
            lastWin = 0
            winningBets = 0
            return
        }

        wheelTurns = wheelTarget
        isSpinning = false
        spinCount += 1

        var payout = 0
        for (bet, amount) in self.bets where bet.wins(number) {
            payout += amount * bet.payout
        }
        winningBets = self.bets.keys.filter { $0.wins(number) }.count
        lastWin = payout
        outcome = payout > 0 ? .won(number) : .lost(number)
    }

    /// How far through its travel a staged spin is frozen by default. Late enough that the wheel
    /// has visibly turned, early enough that the ball is still out on its track.
    public static let stagedSpinProgress = 0.42
}
