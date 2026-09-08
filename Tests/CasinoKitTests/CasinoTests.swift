import Foundation
import Testing

@testable import CasinoKit

/// The house: one balance across two tables, and the rules about moving between them.
///
/// Worth its own suite because the sharing is the part a second game could quietly break. Two
/// purses would let you walk a losing run off by switching tables, which is not a game.
@MainActor
@Suite("Casino")
struct CasinoTests {
    private static func scratchDefaults(_ name: String) -> UserDefaults {
        let suite = "DesktopCasinoTests.casino.\(name).\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    @Test("Both tables spend the same credits")
    func oneBalance() {
        let casino = Casino(defaults: Self.scratchDefaults("shared"))
        let opening = casino.bank.credits

        // Two chips down, so the debit is the table rather than the chip denomination — which is
        // the distinction `wager` exists for.
        casino.roulette.clearBets()
        casino.roulette.setStake(10)
        casino.roulette.place(.red)
        casino.roulette.place(.straight(7))
        #expect(casino.roulette.totalStake == 20)

        casino.roulette.spin()
        #expect(casino.bank.credits == opening - 20)
        // The slot machine reads the balance the roulette table just spent from, not a copy.
        #expect(casino.slots.credits == opening - 20)
    }

    @Test("The stake chips address whichever table you are at")
    func stakeFollowsTheTable() {
        let casino = Casino(defaults: Self.scratchDefaults("stake"))

        casino.select(.slots)
        casino.setStake(25)
        #expect(casino.slots.bet == 25)

        casino.select(.roulette)
        casino.setStake(1)
        #expect(casino.roulette.stake == 1)
        // Each table keeps its own chip; changing one is not changing the other.
        #expect(casino.slots.bet == 25)
        #expect(casino.stake == 1)

        // And what the button costs is the chip at the slot machine but the whole table at the
        // wheel, where several chips can be down at once.
        casino.roulette.clearBets()
        casino.roulette.place(.red)
        casino.roulette.place(.black)
        #expect(casino.wager == 2)
        casino.select(.slots)
        #expect(casino.wager == 25)
    }

    @Test("Changing tables is refused while a stake is in flight")
    func lockedMidSpin() {
        let casino = Casino(defaults: Self.scratchDefaults("locked"))
        casino.select(.slots)
        casino.spin()

        #expect(casino.isBusy)
        casino.select(.roulette)
        #expect(casino.game == .slots)
    }

    @Test("The table you were at is remembered")
    func tablePersists() {
        let defaults = Self.scratchDefaults("persist")
        let casino = Casino(defaults: defaults)
        casino.select(.roulette)
        casino.save()

        #expect(Casino(defaults: defaults).game == .roulette)
    }

    @Test("Being out of credits at one table is being out of credits at the other")
    func brokeIsShared() {
        let defaults = Self.scratchDefaults("broke")
        defaults.set(0, forKey: "credits")
        let casino = Casino(defaults: defaults)

        #expect(casino.bank.isBroke)
        #expect(casino.slots.outcome == .broke)
        #expect(!casino.slots.canSpin)
        #expect(!casino.roulette.canSpin)
    }

    @Test("A refill from the roulette table clears the slot machine's empty banner too")
    func refillClearsBothTables() {
        // `.broke` used to be stored on the slot machine, set when a spin resolved. With a shared
        // bank that flag can go stale in a way it never could before: top the balance up while
        // standing at the other table and the machine would still be saying OUT OF CREDITS.
        let defaults = Self.scratchDefaults("refill")
        defaults.set(0, forKey: "credits")
        let casino = Casino(defaults: defaults)
        casino.select(.roulette)

        casino.refill()

        #expect(casino.bank.credits == Bank.startingBank)
        #expect(casino.slots.outcome == .idle)
        #expect(casino.slots.canSpin)
    }

    @Test("Quitting mid-spin refunds whichever table had the stake down")
    func refundsEitherTable() {
        for table in Casino.Game.allCases {
            let casino = Casino(defaults: Self.scratchDefaults("refund-\(table.rawValue)"))
            casino.select(table)
            let opening = casino.bank.credits

            casino.spin()
            #expect(casino.bank.credits < opening)
            casino.refundUnresolvedSpin()

            #expect(casino.bank.credits == opening, "\(table) did not give the stake back")
            #expect(!casino.isBusy)
        }
    }

    @Test("Credits survive a round trip through the defaults, whichever table wrote them")
    func creditsPersist() {
        let defaults = Self.scratchDefaults("credits")
        let casino = Casino(defaults: defaults)
        casino.roulette.setStake(10)
        casino.roulette.spin()
        casino.save()

        #expect(Casino(defaults: defaults).bank.credits == casino.bank.credits)
    }
}
