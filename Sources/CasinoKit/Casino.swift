import Foundation
import Observation

/// The house: one bank, two tables, and which one you are standing at.
///
/// The widget talks to this rather than to a game directly, so the stake chips and the big gold
/// button do not have to know which table is in front of them.
@MainActor
@Observable
public final class Casino {
    public enum Game: String, CaseIterable, Sendable {
        case slots
        case roulette

        public var title: String {
            switch self {
            case .slots: "SLOTS"
            case .roulette: "ROULETTE"
            }
        }

        public var help: String {
            switch self {
            case .slots: "Three-reel slot machine"
            case .roulette: "European single-zero roulette"
            }
        }

        /// What one round is called here. The stats screen counts the same thing at both tables
        /// and should not call a coup a spin while it does.
        public var roundNoun: String {
            switch self {
            case .slots: "spin"
            case .roulette: "coup"
            }
        }
    }

    private static let gameKey = "game"

    public let bank: Bank
    public let slots: SlotMachine
    public let roulette: Roulette
    public private(set) var game: Game

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let bank = Bank(defaults: defaults)
        self.bank = bank
        slots = SlotMachine(bank: bank, defaults: defaults)
        roulette = Roulette(bank: bank, defaults: defaults)
        game = Game(rawValue: defaults.string(forKey: Self.gameKey) ?? "") ?? .slots
    }

    // MARK: - Tables

    /// True while either table has a stake in flight.
    public var isBusy: Bool { slots.isSpinning || roulette.isSpinning }

    /// Changing tables mid-spin is refused rather than cancelled. The stake is already down and
    /// the result is scheduled, so the honest choices are to wait or to void the bet — and waiting
    /// is the one that cannot cost you the round.
    public func select(_ newGame: Game) {
        guard !isBusy, newGame != game else { return }
        game = newGame
        defaults.set(game.rawValue, forKey: Self.gameKey)
    }

    // MARK: - The table in front of you

    public var isSpinning: Bool {
        switch game {
        case .slots: slots.isSpinning
        case .roulette: roulette.isSpinning
        }
    }

    public var canSpin: Bool {
        switch game {
        case .slots: slots.canSpin
        case .roulette: roulette.canSpin
        }
    }

    /// The chip denomination the picker sets.
    public var stake: Int {
        switch game {
        case .slots: slots.bet
        case .roulette: roulette.stake
        }
    }

    /// What pressing the gold button will actually cost. The same as `stake` at the slot machine,
    /// where one chip is the whole bet; at the wheel it is every chip on the felt added up.
    public var wager: Int {
        switch game {
        case .slots: slots.bet
        case .roulette: roulette.totalStake
        }
    }

    public func setStake(_ value: Int) {
        switch game {
        case .slots: slots.setBet(value)
        case .roulette: roulette.setStake(value)
        }
    }

    public func spin() {
        switch game {
        case .slots: slots.spin()
        case .roulette: roulette.spin()
        }
    }

    // MARK: - Housekeeping

    /// Tops the bank up and clears both tables, whichever one you happen to be at: the balance is
    /// shared, so leaving the other table showing the round that emptied it would be a lie.
    ///
    /// The refill is *filed* at the table you were standing at and only there. It is one event —
    /// counting it on both records would report twice as many busts as happened.
    public func refill() {
        guard !isBusy else { return }
        switch game {
        case .slots:
            slots.refill()
            roulette.reset()
        case .roulette:
            roulette.refill()
            slots.reset()
        }
    }

    // MARK: - Records

    public func ledger(for game: Game) -> Ledger {
        switch game {
        case .slots: slots.ledger
        case .roulette: roulette.ledger
        }
    }

    public func session(for game: Game) -> Ledger.Day {
        switch game {
        case .slots: slots.session
        case .roulette: roulette.session
        }
    }

    /// Clears one table's record. Deliberately not both at once: they are separate diaries, and a
    /// reset button on a screen showing roulette should not quietly wipe the slot machine too.
    public func resetLedger(for game: Game) {
        switch game {
        case .slots: slots.resetLedger()
        case .roulette: roulette.resetLedger()
        }
    }

    public func save() {
        bank.save()
        slots.save()
        roulette.save()
        defaults.set(game.rawValue, forKey: Self.gameKey)
    }

    /// Returns the stake of any round that never resolved, on either table.
    public func refundUnresolvedSpin() {
        slots.refundUnresolvedSpin()
        roulette.refundUnresolvedSpin()
    }
}
