import Foundation
import Observation

/// The balance both tables play against.
///
/// Split out of `SlotMachine` when the roulette table arrived. Two purses would let you walk away
/// from a bad run by switching tables, and the credits readout sits *above* the table picker in the
/// widget precisely because it belongs to neither game.
@MainActor
@Observable
public final class Bank {
    /// `nonisolated` because they are constants, not state: the house rules, readable from
    /// anywhere. Left main-actor isolated they would drag every sample generator and payout table
    /// that mentions a stake onto the main actor for no reason.
    public nonisolated static let startingBank = 100
    public nonisolated static let betSizes = [1, 5, 10, 25]

    /// The smallest stake anyone can put down. Below this you are out of credits.
    public nonisolated static var minimumStake: Int { betSizes[0] }

    private static let creditsKey = "credits"

    public private(set) var credits: Int

    private let defaults: UserDefaults

    /// `defaults` is injectable so tests can run against a scratch domain instead of polluting
    /// the real one.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        credits = defaults.object(forKey: Self.creditsKey) as? Int ?? Self.startingBank
    }

    public var isBroke: Bool { credits < Self.minimumStake }

    public func canAfford(_ amount: Int) -> Bool { amount > 0 && credits >= amount }

    /// The largest listed stake the balance covers, or `nil` when it covers none of them. Used to
    /// downshift a bet that a losing round has just made unaffordable.
    public func largestAffordableStake() -> Int? {
        Self.betSizes.last { canAfford($0) }
    }

    /// Takes the stake, or refuses and leaves the balance untouched. The result is
    /// deliberately not discardable: a caller that ignores it has started a round nobody paid for.
    public func withdraw(_ amount: Int) -> Bool {
        guard canAfford(amount) else { return false }
        credits -= amount
        return true
    }

    public func deposit(_ amount: Int) {
        guard amount > 0 else { return }
        credits += amount
    }

    public func refill() {
        credits += Self.startingBank
        save()
    }

    public func save() {
        defaults.set(credits, forKey: Self.creditsKey)
    }

    /// Sets the balance for a render without persisting it.
    ///
    /// Staging is a rendering concern — the snapshot suite needs an empty purse and a jackpot
    /// balance without playing for either. Writing a fabricated figure into `UserDefaults` would
    /// hand the player free credits, so this deliberately does not `save()`.
    public func stage(credits: Int) {
        self.credits = max(0, credits)
    }
}
