import Foundation
import Testing

@testable import CasinoKit

/// Every case runs against a throwaway `UserDefaults` domain, so tests never touch the real one.
@MainActor
@Suite("Slot machine")
struct SlotMachineTests {
    private static func scratchDefaults(_ name: String) -> UserDefaults {
        let suite = "DesktopCasinoTests.\(name).\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    @Test("A fresh machine opens on three different symbols")
    func freshOpeningIsNotATriple() {
        let machine = SlotMachine(defaults: Self.scratchDefaults("fresh"))
        let symbols = machine.reels.map { Reel.strip[Int($0.position) % Reel.strip.count].name }
        #expect(Set(symbols).count == 3)
    }

    @Test("Reels rest exactly on a stop, so the visual matches what was scored")
    func reelsRestOnAStop() {
        let machine = SlotMachine(defaults: Self.scratchDefaults("rest"))
        for reel in machine.reels {
            #expect(reel.position == reel.position.rounded())
            #expect(reel.position == reel.spinTarget)
        }
    }

    @Test("A spin debits the stake up front and targets a whole stop")
    func spinDebitsAndTargets() {
        let machine = SlotMachine(defaults: Self.scratchDefaults("spin"))
        let opening = machine.credits
        let stake = machine.bet

        machine.spin()

        #expect(machine.isSpinning)
        #expect(machine.credits == opening - stake)
        for reel in machine.reels {
            // The invariant the reel rendering depends on: a target is a whole number of stops,
            // so `strip[position mod stops]` is the symbol that was actually scored.
            #expect(reel.spinTarget == reel.spinTarget.rounded())
            #expect(reel.spinTarget > reel.spinStart)
        }
    }

    @Test("Quitting mid-spin refunds the stake instead of banking the debit")
    func refundReturnsTheStake() {
        let machine = SlotMachine(defaults: Self.scratchDefaults("refund"))
        let opening = machine.credits
        machine.spin()
        #expect(machine.credits < opening)

        machine.refundUnresolvedSpin()

        #expect(machine.credits == opening)
        #expect(!machine.isSpinning)
    }

    @Test("A resolved spin reconciles: credits move by exactly net = payout - stake")
    func netReconciles() async throws {
        let machine = SlotMachine(defaults: Self.scratchDefaults("net"))
        let opening = machine.credits
        machine.spin()

        // Poll rather than sleeping a fixed interval. Resolution is scheduled ~2.3s out on the
        // main actor, and the snapshot tests run in parallel doing heavy main-actor rendering —
        // a fixed 3s wait raced that contention and failed intermittently.
        let deadline = Date().addingTimeInterval(30)
        while machine.isSpinning, Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(!machine.isSpinning)
        #expect(machine.spinCount == 1)
        // `lastStake` is what was actually debited, so the figure the UI shows —
        // `lastWin - lastStake` — is a true net and never mixes units with a push's ±0.
        #expect(machine.lastStake > 0)
        #expect(machine.credits == opening - machine.lastStake + machine.lastWin)
    }

    @Test("Refunding is a no-op when no spin is in flight")
    func refundIsIdempotent() {
        let machine = SlotMachine(defaults: Self.scratchDefaults("noop"))
        let opening = machine.credits
        machine.refundUnresolvedSpin()
        machine.refundUnresolvedSpin()
        #expect(machine.credits == opening)
    }

    @Test("Credits and bet round-trip through the injected defaults")
    func persistence() {
        let defaults = Self.scratchDefaults("persist")
        let machine = SlotMachine(defaults: defaults)
        machine.setBet(25)
        machine.save()

        let reloaded = SlotMachine(defaults: defaults)
        #expect(reloaded.bet == 25)
        #expect(reloaded.credits == machine.credits)
    }

    @Test("You cannot stake more than you hold")
    func cannotOverspend() {
        let defaults = Self.scratchDefaults("broke")
        defaults.set(0, forKey: "credits")
        let machine = SlotMachine(defaults: defaults)

        #expect(!machine.canSpin)
        machine.spin()
        #expect(!machine.isSpinning)
        #expect(machine.credits == 0)
    }

    @Test("Refill tops the bank back up")
    func refill() {
        let defaults = Self.scratchDefaults("refill")
        defaults.set(0, forKey: "credits")
        let machine = SlotMachine(defaults: defaults)
        machine.refill()
        #expect(machine.credits == SlotMachine.startingBank)
        #expect(machine.canSpin)
    }

    // MARK: - Ledger

    @Test("A resolved spin is filed in the ledger and in the session")
    func spinIsRecorded() async throws {
        let machine = SlotMachine(defaults: Self.scratchDefaults("ledger"))
        #expect(machine.ledger.spins == 0)

        machine.spin()
        try await Self.settle(machine)

        #expect(machine.ledger.spins == 1)
        #expect(machine.ledger.wagered == machine.lastStake)
        #expect(machine.ledger.won == machine.lastWin)
        // The ledger's arithmetic has to agree with the bank's, or the stats window is telling a
        // different story from the credits counter above it.
        #expect(machine.ledger.net == machine.lastWin - machine.lastStake)
        #expect(machine.session.spins == 1)
        #expect(machine.session.net == machine.ledger.net)
        #expect(machine.ledger.day(Date()).spins == 1)
        #expect(machine.ledger.peakBank >= machine.credits)
    }

    @Test("Staging a result for a render does not touch the ledger")
    func stagingIsNotRecorded() {
        let machine = SlotMachine(defaults: Self.scratchDefaults("staged"))
        machine.stage(landings: [0, 0, 0], credits: 500, bet: 25)

        #expect(machine.spinCount == 1)
        #expect(machine.ledger.spins == 0)
        #expect(machine.session.spins == 0)
    }

    @Test("Going bust and refilling is counted")
    func refillIsCounted() {
        let defaults = Self.scratchDefaults("busts")
        defaults.set(0, forKey: "credits")
        let machine = SlotMachine(defaults: defaults)

        machine.refill()
        machine.refill()

        #expect(machine.ledger.refills == 2)
        #expect(machine.ledger.peakBank == machine.credits)
    }

    @Test("The ledger round-trips through the injected defaults")
    func ledgerPersistence() async throws {
        let defaults = Self.scratchDefaults("ledger-persist")
        let machine = SlotMachine(defaults: defaults)
        machine.spin()
        try await Self.settle(machine)

        let reloaded = SlotMachine(defaults: defaults)
        #expect(reloaded.ledger == machine.ledger)
        // The session is per launch, so it does not come back with the rest.
        #expect(reloaded.session.spins == 0)
    }

    @Test("A corrupt stored ledger loads as an empty one rather than failing to launch")
    func corruptLedgerIsDiscarded() {
        let defaults = Self.scratchDefaults("corrupt")
        defaults.set(Data("not json".utf8), forKey: "ledger")

        let machine = SlotMachine(defaults: defaults)

        #expect(machine.ledger == Ledger())
        #expect(machine.credits == SlotMachine.startingBank)
    }

    @Test("Resetting the ledger clears the record and leaves the bank alone")
    func resetKeepsCredits() async throws {
        let machine = SlotMachine(defaults: Self.scratchDefaults("reset"))
        machine.spin()
        try await Self.settle(machine)
        let banked = machine.credits

        machine.resetLedger()

        #expect(machine.credits == banked)
        #expect(machine.ledger.spins == 0)
        #expect(machine.ledger.days.isEmpty)
        #expect(machine.session.spins == 0)
        // Restarted at what is held, so the stats window never claims a peak below the balance
        // printed on the machine.
        #expect(machine.ledger.peakBank == banked)
    }

    /// Waits for a spin to resolve. See `netReconciles` for why this polls.
    private static func settle(_ machine: SlotMachine) async throws {
        let deadline = Date().addingTimeInterval(30)
        while machine.isSpinning, Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(!machine.isSpinning)
    }
}
