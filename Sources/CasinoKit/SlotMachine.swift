import Observation
import SwiftUI

@MainActor
@Observable
public final class SlotMachine {
    public struct ReelState {
        /// How far the strip has scrolled, in symbol units. Monotonically increasing.
        public var position: Double = 0
        public var spinStart: Double = 0
        public var spinTarget: Double = 0
    }

    public enum Outcome: Equatable {
        case idle
        case spinning
        case nothing
        case pair(Symbol)
        case triple(Symbol)
        case broke

        public var isJackpot: Bool {
            if case .triple(let s) = self { return s.name == "diamond" }
            return false
        }
    }

    public static let betSizes = [1, 5, 10, 25]
    public static let startingBank = 100

    private static let creditsKey = "credits"
    private static let betKey = "bet"

    public private(set) var credits: Int
    public private(set) var reels = [ReelState](repeating: ReelState(), count: 3)
    public private(set) var outcome: Outcome = .idle
    public private(set) var lastWin = 0
    /// What the resolved spin actually cost. `bet` can be downshifted after a spin resolves, so
    /// comparing a payout against it would misjudge whether the spin gained anything.
    public private(set) var lastStake = 0
    public private(set) var isSpinning = false
    public private(set) var bet: Int

    private let defaults: UserDefaults

    /// Bumped on every resolved spin so the view can retrigger its win animation
    /// even when two identical outcomes land back to back.
    public private(set) var spinCount = 0

    /// `defaults` is injectable so tests can run against a scratch domain instead of polluting
    /// the real one.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Self.creditsKey) as? Int
        credits = stored ?? Self.startingBank
        bet = defaults.object(forKey: Self.betKey) as? Int ?? Self.betSizes[1]
        if !Self.betSizes.contains(bet) { bet = Self.betSizes[1] }

        // Distinct symbols, so a fresh install never opens on a three-of-a-kind. Distinct stops
        // are not enough: several stops carry the same symbol.
        var rng = SplitMix64(seed: 0xC0FF_EE00_1234_5678)
        var used: Set<String> = []
        for i in reels.indices {
            var stop = Int.random(in: 0..<Reel.strip.count, using: &rng)
            while used.contains(Reel.strip[stop].name) {
                stop = (stop + 1) % Reel.strip.count
            }
            used.insert(Reel.strip[stop].name)
            reels[i] = ReelState(position: Double(stop),
                                 spinStart: Double(stop),
                                 spinTarget: Double(stop))
        }
        if credits < Self.betSizes[0] { outcome = .broke }
    }

    // MARK: - Play

    public var canSpin: Bool { !isSpinning && credits >= bet }

    public func setBet(_ value: Int) {
        guard !isSpinning, Self.betSizes.contains(value) else { return }
        bet = value
        defaults.set(bet, forKey: Self.betKey)
    }

    public func refill() {
        guard !isSpinning else { return }
        credits += Self.startingBank
        lastWin = 0
        outcome = .idle
        save()
    }

    public func spin() {
        guard canSpin else { return }

        isSpinning = true
        outcome = .spinning
        lastWin = 0
        credits -= bet

        let stops = Reel.strip.count
        var landings: [Int] = []

        for i in reels.indices {
            let landing = Int.random(in: 0..<stops)
            landings.append(landing)

            let start = reels[i].position
            let base = start.rounded(.down)
            let currentStop = Int(base) % stops
            var delta = landing - currentStop
            if delta < 0 { delta += stops }

            // Later reels spin longer, so they stop left to right.
            let fullRevolutions = 4 + i * 2
            let target = base + Double(fullRevolutions * stops + delta)

            reels[i].spinStart = start
            reels[i].spinTarget = target
            withAnimation(.timingCurve(0.12, 0.72, 0.2, 1.0, duration: Self.duration(forReel: i))) {
                reels[i].position = target
            }
        }

        let settle = Self.duration(forReel: reels.count - 1) + 0.1
        Task { [landings] in
            // A cancelled sleep must abort the spin. `try?` would swallow the cancellation and
            // resolve immediately instead, paying out a spin that never finished.
            do { try await Task.sleep(for: .seconds(settle)) } catch { return }
            self.resolve(landings)
        }
    }

    private static func duration(forReel index: Int) -> Double {
        1.35 + Double(index) * 0.42
    }

    private func resolve(_ landings: [Int]) {
        let (result, payout) = Self.score(landings, stake: bet)
        outcome = result

        credits += payout
        lastWin = payout
        lastStake = bet
        isSpinning = false
        spinCount += 1
        if credits < Self.betSizes[0] { outcome = .broke }
        if bet > credits, let affordable = Self.betSizes.last(where: { $0 <= credits }) {
            bet = affordable
        }
        save()
    }

    /// What a set of strip landings pays at a given stake.
    ///
    /// Pure and static so that a spin resolving for real and a machine staged for a render go
    /// through the same table — a second copy of this arithmetic would let the symbols on the
    /// reels drift out of step with the line printed underneath them.
    static func score(_ landings: [Int], stake: Int) -> (outcome: Outcome, payout: Int) {
        let result = landings.map { Reel.strip[wrap($0)] }

        if result[0] == result[1], result[1] == result[2] {
            return (.triple(result[0]), stake * result[0].tripleMultiplier)
        }
        if let matched = result.first(where: { symbol in
            result.filter { $0 == symbol }.count == 2
        }) {
            return (.pair(matched), stake * matched.pairMultiplier)
        }
        return (.nothing, 0)
    }

    /// Strip indices are modular: reels turn past the end of the strip and back onto it.
    private static func wrap(_ stop: Int) -> Int {
        let stops = Reel.strip.count
        return ((stop % stops) + stops) % stops
    }

    /// Returns the stake of a spin that never resolved. Credits are debited when a spin starts,
    /// so quitting mid-spin would otherwise persist the debit with no payout.
    public func refundUnresolvedSpin() {
        guard isSpinning else { return }
        credits += bet
        isSpinning = false
        outcome = .idle
    }

    public func save() {
        defaults.set(credits, forKey: Self.creditsKey)
        defaults.set(bet, forKey: Self.betKey)
    }

    // MARK: - Staging

    /// Parks the machine on an exact result without playing for it.
    ///
    /// Offscreen renders and the window snapshot tests need particular states — a jackpot, a
    /// push, an empty balance, a spin frozen halfway — and a live machine only reaches those by
    /// chance, several seconds of animation later. Landings run through `score`, the same table
    /// a real spin resolves against, so a staged card is a card the game could actually deal.
    ///
    /// Nothing is persisted. Staging is a rendering concern, and writing a fabricated balance
    /// into `UserDefaults` would hand the player free credits.
    public func stage(landings: [Int], credits: Int, bet: Int, spinning: Bool = false) {
        precondition(landings.count == reels.count, "stage wants one landing per reel")

        self.credits = credits
        self.bet = Self.betSizes.contains(bet) ? bet : Self.betSizes[1]

        for i in reels.indices {
            let landing = Self.wrap(landings[i])
            guard spinning else {
                reels[i] = ReelState(position: Double(landing),
                                     spinStart: Double(landing),
                                     spinTarget: Double(landing))
                continue
            }
            // Mirrors `spin()`: later reels travel further, so they settle left to right. Frozen
            // partway along that travel, which is where the motion blur lives — and at a
            // different fraction per reel, so a still shows the same stagger a spin does.
            let target = Double(landing + (4 + i * 2) * Reel.strip.count)
            reels[i] = ReelState(position: Self.stagedSpinProgress[i] * target,
                                 spinStart: 0,
                                 spinTarget: target)
        }

        guard !spinning else {
            outcome = .spinning
            lastWin = 0
            lastStake = 0
            isSpinning = true
            return
        }

        let (result, payout) = Self.score(landings, stake: self.bet)
        lastWin = payout
        lastStake = self.bet
        isSpinning = false
        spinCount += 1
        outcome = credits < Self.betSizes[0] ? .broke : result
    }

    /// How far through its travel each reel is in a staged spin: left nearly home, right barely
    /// started. `ReelView` reads its blur off exactly this fraction.
    private static let stagedSpinProgress = [0.94, 0.72, 0.45]
}
