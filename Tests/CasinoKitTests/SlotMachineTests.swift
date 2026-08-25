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
}
