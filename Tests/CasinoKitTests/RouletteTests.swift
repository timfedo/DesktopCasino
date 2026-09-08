import Foundation
import Testing

@testable import CasinoKit

/// The wheel itself: its layout, and what it pays. Arithmetic only — the drawing has its own
/// snapshots next door.
@Suite("Roulette wheel")
struct RouletteWheelTests {
    @Test("Thirty-seven pockets, 0 through 36, each exactly once")
    func layout() {
        #expect(RouletteWheel.pockets == 37)
        #expect(Set(RouletteWheel.order) == Set(0...36))
        #expect(RouletteWheel.order.count == Set(RouletteWheel.order).count)
    }

    @Test("Eighteen red, eighteen black, one green")
    func colours() {
        let counts = (0...36).reduce(into: [PocketColor: Int]()) {
            $0[RouletteWheel.color(of: $1), default: 0] += 1
        }
        #expect(counts[.red] == 18)
        #expect(counts[.black] == 18)
        #expect(counts[.green] == 1)
        #expect(RouletteWheel.color(of: 0) == .green)
    }

    @Test("No two neighbouring pockets share a colour, all the way round")
    func coloursAlternateAroundTheWheel() {
        // The property that makes it a wheel rather than a list: no arc of it favours red or
        // black. A transcription slip in the running order breaks this and nothing else — and it
        // has to hold across the wrap too, where the green zero sits between a black and a red.
        let order = RouletteWheel.order
        for index in order.indices {
            let here = RouletteWheel.color(of: order[index])
            let next = RouletteWheel.color(of: order[(index + 1) % order.count])
            #expect(here != next, "pockets \(order[index]) and \(order[(index + 1) % 37]) match")
        }
    }

    @Test("Pockets are evenly spaced, first at the top")
    func spacing() {
        #expect(RouletteWheel.angle(ofPocketAt: 0) == 0)
        let step = 360.0 / 37
        #expect(abs(RouletteWheel.angle(ofPocketAt: 1) - step) < 1e-9)
        #expect(abs(RouletteWheel.angle(ofPocketAt: 36) - 36 * step) < 1e-9)
    }
}

/// The felt: where the numbers sit, and which chips can be placed on them.
@Suite("Roulette layout")
struct RouletteLayoutTests {
    @Test("The grid holds 1 to 36, in columns of three")
    func gridCoversEveryNumber() {
        var seen: Set<Int> = []
        for column in 0..<RouletteLayout.columns {
            for row in 0..<RouletteLayout.rows {
                let number = RouletteLayout.number(column: column, row: row)
                #expect(number != nil)
                if let number { seen.insert(number) }
            }
        }
        #expect(seen == Set(1...36))
        // The top row is the multiples of three, which is what a real layout reads like.
        #expect(RouletteLayout.number(column: 0, row: 0) == 3)
        #expect(RouletteLayout.number(column: 0, row: 2) == 1)
        #expect(RouletteLayout.number(column: 11, row: 0) == 36)
    }

    @Test("Position round-trips: a number's column and row put it back where it was")
    func positionsRoundTrip() {
        for number in 1...36 {
            let column = RouletteLayout.column(of: number)
            let row = RouletteLayout.row(of: number)
            #expect(column != nil)
            #expect(row != nil)
            if let column, let row {
                #expect(RouletteLayout.number(column: column, row: row) == number)
            }
        }
        // The zero is beside the grid, not on it.
        #expect(RouletteLayout.column(of: 0) == nil)
        #expect(RouletteLayout.row(of: 0) == nil)
    }

    @Test("Columns and dozens each cover twelve numbers, and together cover the grid")
    func columnsAndDozens() {
        for which in 1...3 {
            #expect(RouletteLayout.columnBet(which).count == 12)
            #expect(RouletteLayout.dozen(which).count == 12)
        }
        let allColumns = (1...3).map(RouletteLayout.columnBet).reduce(Set<Int>()) { $0.union($1) }
        let allDozens = (1...3).map(RouletteLayout.dozen).reduce(Set<Int>()) { $0.union($1) }
        #expect(allColumns == Set(1...36))
        #expect(allDozens == Set(1...36))
    }

    @Test("Every enumerated chip is one the legality rule also accepts")
    func enumeratedBetsAreLegal() {
        // The two are written independently — one builds the shapes, the other recognises them —
        // so agreeing is worth something. A chip that could be enumerated but not recognised would
        // be placeable and then rejected on the next click.
        for bet in RouletteLayout.allInsideBets {
            #expect(RouletteLayout.isLegalInside(bet), "\(bet.sorted()) was built but not accepted")
        }
        #expect(Set(RouletteLayout.allInsideBets).count == RouletteLayout.allInsideBets.count)
    }

    @Test("The chips are the ones a felt has: 37 straights, 60 splits, 12 streets, 22 corners")
    func theChipsAreTheRightOnes() {
        let bets = RouletteLayout.allInsideBets
        // 57 splits on the grid — 33 across, 24 down — plus the zero's three.
        #expect(bets.filter { $0.count == 1 }.count == 37)
        #expect(bets.filter { $0.count == 2 }.count == 60)
        // 12 streets and the zero's two trios.
        #expect(bets.filter { $0.count == 3 }.count == 14)
        // 22 corners and the zero's basket.
        #expect(bets.filter { $0.count == 4 }.count == 23)
        #expect(bets.filter { $0.count == 6 }.count == 11)
    }

    @Test("Shapes that are not chips are refused")
    func illegalShapesAreRefused() {
        #expect(!RouletteLayout.isLegalInside([]))
        #expect(!RouletteLayout.isLegalInside([1, 5]))          // diagonal
        #expect(!RouletteLayout.isLegalInside([1, 34]))         // opposite ends
        #expect(!RouletteLayout.isLegalInside([1, 2, 4]))       // three quarters of a corner
        #expect(!RouletteLayout.isLegalInside([1, 4, 7]))       // a row, which is not a street
        #expect(!RouletteLayout.isLegalInside([0, 1, 3]))       // not one of the zero's
        #expect(!RouletteLayout.isLegalInside([1, 2, 3, 4, 5])) // five of a line
        #expect(!RouletteLayout.isLegalInside([37]))
    }

    @Test("Clicked numbers resolve to the smallest chip that covers them")
    func resolutionPicksTheSmallestChip() {
        #expect(RouletteLayout.resolve([17]) == [17])
        #expect(RouletteLayout.resolve([1, 2]) == [1, 2])
        // Three quarters of a corner can only have meant the corner…
        #expect(RouletteLayout.resolve([1, 2, 4]) == [1, 2, 4, 5])
        // …and a street plus one more can only have meant the line, not any smaller chip.
        #expect(RouletteLayout.resolve([1, 2, 3, 4]) == [1, 2, 3, 4, 5, 6])
        #expect(RouletteLayout.resolve([1, 34]) == nil)
        #expect(RouletteLayout.resolve([]) == nil)
    }
}

@Suite("Roulette payouts")
struct RoulettePayoutTests {
    /// Every bet, over every pocket. 37 outcomes is small enough that there is no need to sample.
    private static func wins(for bet: RouletteBet) -> [Int] {
        (0...36).filter { bet.wins($0) }
    }

    @Test("Even-money bets cover eighteen pockets each and pay 2x")
    func evenMoney() {
        for bet in RouletteBet.outsideBets {
            #expect(Self.wins(for: bet).count == 18, "\(bet) covers the wrong number of pockets")
            #expect(bet.payout == 2)
        }
    }

    @Test("Dozens cover twelve pockets each and pay 3x")
    func dozens() {
        #expect(Self.wins(for: .dozen(1)) == Array(1...12))
        #expect(Self.wins(for: .dozen(2)) == Array(13...24))
        #expect(Self.wins(for: .dozen(3)) == Array(25...36))
        for bet in RouletteBet.dozens { #expect(bet.payout == 3) }
    }

    @Test("A straight up covers one pocket and pays 36x")
    func straightUp() {
        for number in 0...36 {
            #expect(Self.wins(for: .straight(number)) == [number])
            #expect(RouletteBet.straight(number).payout == 36)
        }
    }

    @Test("Zero loses everything except a straight up on the zero")
    func zeroIsTheHouseEdge() {
        for bet in RouletteBet.outsideBets + RouletteBet.dozens {
            #expect(!bet.wins(0), "\(bet) should not win on the zero")
        }
        #expect(RouletteBet.straight(0).wins(0))
    }

    @Test("Columns cover twelve pockets each and pay 3x")
    func columns() {
        for bet in RouletteBet.columns {
            #expect(Self.wins(for: bet).count == 12)
            #expect(bet.payout == 3)
        }
        let all = RouletteBet.columns.reduce(Set<Int>()) { $0.union($1.covers) }
        #expect(all == Set(1...36))
    }

    @Test("Splits, streets, corners and lines pay 18x, 12x, 9x and 6x")
    func insideBets() {
        for numbers in RouletteLayout.allInsideBets {
            let bet = RouletteBet.inside(numbers)
            #expect(Self.wins(for: bet).sorted() == numbers.sorted())
            #expect(bet.payout == 36 / numbers.count)
        }
    }

    /// Every chip on the felt, which is what the identity below has to hold across.
    private static var everyBet: [RouletteBet] {
        RouletteBet.outsideBets + RouletteBet.dozens + RouletteBet.columns
            + RouletteLayout.allInsideBets.map(RouletteBet.inside)
    }

    @Test("Every bet returns 36/37 — the single-zero edge, and the same one for all of them")
    func returnToPlayer() {
        // Stake 37 on any chip on the felt, one credit per pocket it covers, and 36 comes back.
        // That identity is what makes 2x/3x/6x/9x/12x/18x/36x the honest numbers for an
        // 18/12/6/4/3/2/1 pocket bet, and it is the reason `payout` is derived rather than
        // tabulated — a table can hold a typo, this cannot.
        for bet in Self.everyBet {
            let covered = Self.wins(for: bet).count
            #expect(covered * bet.payout == 36, "\(bet) does not return 36 per 37 staked")
        }
    }

    @Test("No bet on the felt covers the whole wheel, and none covers nothing")
    func everyBetIsABet() {
        for bet in Self.everyBet {
            #expect(bet.isValid, "\(bet) is not placeable")
            #expect((1...36).contains(bet.covers.count))
        }
    }

    @Test("Bets round-trip through their storage key")
    func storageKeys() {
        for bet in Self.everyBet {
            #expect(RouletteBet(storageKey: bet.storageKey) == bet)
        }
        // Junk on disk falls back rather than crashing, and shapes that are not chips are junk.
        #expect(RouletteBet(storageKey: "chartreuse") == nil)
        #expect(RouletteBet(storageKey: "dozen:4") == nil)
        #expect(RouletteBet(storageKey: "column:0") == nil)
        #expect(RouletteBet(storageKey: "inside:37") == nil)
        #expect(RouletteBet(storageKey: "inside:1,5") == nil)
        #expect(RouletteBet(storageKey: "inside:1,two") == nil)
        #expect(RouletteBet(storageKey: "dozen") == nil)
    }
}

/// Every case runs against a throwaway `UserDefaults` domain, so tests never touch the real one.
@MainActor
@Suite("Roulette table")
struct RouletteTableTests {
    private static func scratchDefaults(_ name: String) -> UserDefaults {
        let suite = "DesktopCasinoTests.roulette.\(name).\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    @Test("A spin debits the stake up front and leaves the wheel turning")
    func spinDebits() {
        let defaults = Self.scratchDefaults("spin")
        let bank = Bank(defaults: defaults)
        let table = Roulette(bank: bank, defaults: defaults)
        let opening = bank.credits
        let staked = table.totalStake

        let resting = table.wheelTurns
        table.spin()

        #expect(table.isSpinning)
        #expect(staked > 0, "a fresh table opens with a chip down")
        #expect(bank.credits == opening - staked)
        #expect(table.lastStake == staked)
        // Nominal, plus up to one turn of shove and no more. The shove is what makes the stopping
        // angle unpredictable now that no marker decides it; bounding it is what lets the duration
        // be scaled to the travel and every spin still come out the same speed and roughly the
        // same length.
        let travelled = table.wheelTurns - resting
        #expect(travelled >= Roulette.nominalTravel)
        #expect(travelled < Roulette.nominalTravel + 1)
        // Both ends of the travel are published, so the ball can tell how far through it is.
        #expect(table.wheelStart == resting)
        #expect(table.wheelTarget == table.wheelTurns)
    }

    @Test("The ball comes to rest in the pocket that was scored")
    func wheelSettlesOnTheResult() async throws {
        let defaults = Self.scratchDefaults("settle")
        let bank = Bank(defaults: defaults)
        let table = Roulette(bank: bank, defaults: defaults)
        table.spin()

        let deadline = Date().addingTimeInterval(120)
        while table.isSpinning, Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(!table.isSpinning)

        // The invariant the whole drawing rests on. It is no longer "the winner finishes at the
        // top" — the wheel stops wherever the throw leaves it, as a real one does — so what has to
        // hold is that the ball is in the *scored* pocket at whatever angle that pocket ended up.
        // Otherwise the number in the hub is not the one the ball is sitting in, and the game is
        // lying about what it paid.
        let number = try #require(table.result)
        let index = try #require(RouletteWheel.index(of: number))
        #expect(table.landingIndex == index)

        let resting = RouletteBall.angle(
            wheelTurns: table.wheelTurns,
            spinStart: table.wheelStart,
            spinTarget: table.wheelTarget,
            landingIndex: table.landingIndex,
            ballStart: table.ballStart
        )
        var offBy = (resting - Roulette.ballAngle(pocketAt: index, wheelTurns: table.wheelTurns))
            .truncatingRemainder(dividingBy: 360)
        if offBy < 0 { offBy += 360 }
        #expect(min(offBy, 360 - offBy) < 1e-6)
    }

    @Test("The next spin starts the ball where the last one left it")
    func theBallIsPickedUpWhereItLies() async throws {
        // With no marker the ball no longer rests at a known angle, so the model has to carry it:
        // the free path of the next spin starts from the pocket the last one stopped in. Assumed
        // zero instead, the ball would jump to the top of the wheel the instant a spin was pushed.
        let defaults = Self.scratchDefaults("carry")
        let bank = Bank(defaults: defaults)
        let table = Roulette(bank: bank, defaults: defaults)

        table.spin()
        try await Self.settle(table)
        let lastPocket = table.landingIndex
        let lastAngle = Roulette.ballAngle(pocketAt: lastPocket, wheelTurns: table.wheelTurns)

        table.spin()
        #expect(abs(table.ballStart - lastAngle) < 1e-6)
        try await Self.settle(table)
    }

    private static func settle(_ table: Roulette) async throws {
        let deadline = Date().addingTimeInterval(120)
        while table.isSpinning, Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(!table.isSpinning)
    }

    @Test("A resolved round reconciles: credits move by exactly net = payout - stake")
    func netReconciles() async throws {
        let defaults = Self.scratchDefaults("net")
        let bank = Bank(defaults: defaults)
        let table = Roulette(bank: bank, defaults: defaults)
        let opening = bank.credits
        table.spin()

        // Polled rather than slept for a fixed interval, for the same reason the slot machine's
        // equivalent is: resolution is scheduled seconds out on the main actor, which the snapshot
        // tests are busy rendering on.
        let deadline = Date().addingTimeInterval(120)
        while table.isSpinning, Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(!table.isSpinning)
        #expect(table.spinCount == 1)
        #expect(bank.credits == opening - table.lastStake + table.lastWin)

        let number = try #require(table.result)
        var expected = 0
        for (bet, amount) in table.bets where bet.wins(number) {
            expected += amount * bet.payout
        }
        #expect(table.lastWin == expected)
    }

    @Test("Quitting mid-spin refunds the stake instead of banking the debit")
    func refund() {
        let defaults = Self.scratchDefaults("refund")
        let bank = Bank(defaults: defaults)
        let table = Roulette(bank: bank, defaults: defaults)
        let opening = bank.credits

        table.spin()
        #expect(bank.credits < opening)
        table.refundUnresolvedSpin()

        #expect(bank.credits == opening)
        #expect(!table.isSpinning)

        // And it is a no-op when there is nothing in flight.
        table.refundUnresolvedSpin()
        #expect(bank.credits == opening)
    }

    @Test("You cannot stake more than you hold")
    func cannotOverspend() {
        let defaults = Self.scratchDefaults("broke")
        defaults.set(0, forKey: "credits")
        let bank = Bank(defaults: defaults)
        let table = Roulette(bank: bank, defaults: defaults)

        #expect(!table.canSpin)
        table.spin()
        #expect(!table.isSpinning)
        #expect(bank.credits == 0)
    }

    // MARK: - The table

    @Test("Several chips can be down at once, and they add up")
    func severalChips() {
        let defaults = Self.scratchDefaults("several")
        let table = Roulette(bank: Bank(defaults: defaults), defaults: defaults)
        table.clearBets()
        table.setStake(5)

        table.place(.straight(17))
        table.place(.black)
        table.place(.dozen(2))

        #expect(table.bets.count == 3)
        #expect(table.totalStake == 15)
        // 17 is black and in the second dozen, so all three cover it.
        #expect(table.covered.contains(17))
    }

    @Test("Clicking the same spot again stacks another chip on it")
    func chipsStack() {
        let defaults = Self.scratchDefaults("stack")
        let table = Roulette(bank: Bank(defaults: defaults), defaults: defaults)
        table.clearBets()
        table.setStake(5)

        table.place(.red)
        table.place(.red)
        #expect(table.bets[.red] == 10)
        #expect(table.bets.count == 1)

        table.setStake(25)
        table.place(.red)
        #expect(table.bets[.red] == 35)
    }

    @Test("A table you could not cover is refused rather than laid out")
    func cannotLayOutMoreThanYouHold() {
        let defaults = Self.scratchDefaults("overlay")
        defaults.set(12, forKey: "credits")
        let bank = Bank(defaults: defaults)
        let table = Roulette(bank: bank, defaults: defaults)
        table.clearBets()
        table.setStake(5)

        table.place(.red)
        table.place(.black)
        #expect(table.totalStake == 10)

        // The third would take it to 15 against a balance of 12. Stakes are only taken when the
        // wheel is pushed, so without this you could lay out more than you hold and find out as a
        // spin that silently does nothing.
        table.place(.even)
        #expect(table.totalStake == 10)
        #expect(bank.credits == 12)
    }

    @Test("Chips come off one at a time, or all at once")
    func removingChips() {
        let defaults = Self.scratchDefaults("remove")
        let table = Roulette(bank: Bank(defaults: defaults), defaults: defaults)
        table.clearBets()
        table.place(.red)
        table.place(.straight(7))

        table.remove(.red)
        #expect(table.bets.count == 1)
        #expect(table.bets[.straight(7)] != nil)

        table.clearBets()
        #expect(table.bets.isEmpty)
        #expect(table.totalStake == 0)
        // Nothing staked is not a spin.
        #expect(!table.canSpin)
    }

    @Test("Every winning chip is paid, and the losers are not")
    func everyWinningChipPays() async throws {
        let defaults = Self.scratchDefaults("payout")
        let bank = Bank(defaults: defaults)
        let table = Roulette(bank: bank, defaults: defaults)
        bank.stage(credits: 500)
        table.clearBets()
        table.setStake(5)

        // Every pocket is covered by exactly one of these, so whatever comes up, red or black
        // pays and the other does not — and the zero pays neither.
        table.place(.red)
        table.place(.black)
        let opening = bank.credits

        table.spin()
        let deadline = Date().addingTimeInterval(120)
        while table.isSpinning, Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        let number = try #require(table.result)
        let expected = RouletteWheel.color(of: number) == .green ? 0 : 10
        #expect(table.lastWin == expected)
        #expect(table.winningBets == (expected > 0 ? 1 : 0))
        #expect(bank.credits == opening - 10 + expected)
    }

    // MARK: - Making inside bets

    @Test("Dragging across numbers places the chip they add up to")
    func draggingPlacesInsideBets() {
        let defaults = Self.scratchDefaults("drag")
        let table = Roulette(bank: Bank(defaults: defaults), defaults: defaults)
        table.clearBets()
        table.setStake(5)

        table.placeInside(covering: [1, 2])
        #expect(table.bets[.inside([1, 2])] == 5)

        // Three quarters of a corner can only have meant the corner. Every three-number subset of
        // one is an illegal shape, so a rule of "cover exactly what was touched" would leave
        // corners and lines unplaceable however you dragged.
        table.placeInside(covering: [10, 11, 13])
        #expect(table.bets[.inside([10, 11, 13, 14])] == 5)
        #expect(RouletteLayout.insideName([10, 11, 13, 14]) == "CORNER")

        // A street and one more is the line.
        table.placeInside(covering: [1, 2, 3, 4])
        #expect(table.bets[.inside([1, 2, 3, 4, 5, 6])] == 5)
    }

    @Test("A drag no chip could cover places nothing at all")
    func impossibleDragPlacesNothing() {
        let defaults = Self.scratchDefaults("nodrag")
        let table = Roulette(bank: Bank(defaults: defaults), defaults: defaults)
        table.clearBets()

        table.placeInside(covering: [1, 34])
        #expect(table.bets.isEmpty)
    }

    @Test("The table and the stake round-trip through the injected defaults")
    func persistence() {
        let defaults = Self.scratchDefaults("persist")
        let table = Roulette(bank: Bank(defaults: defaults), defaults: defaults)
        table.clearBets()
        table.setStake(25)
        table.place(.inside([1, 2, 4, 5]))
        table.place(.red)
        table.save()

        let reloaded = Roulette(bank: Bank(defaults: defaults), defaults: defaults)
        #expect(reloaded.bets == [.inside([1, 2, 4, 5]): 25, .red: 25])
        #expect(reloaded.stake == 25)
        #expect(reloaded.totalStake == 50)
    }

    @Test("A single bet saved by an older build still loads")
    func readsTheOlderEncoding() {
        // Before the felt held several chips there was one bet, written as `rouletteBet`. Dropping
        // it would silently clear somebody's table on upgrade, which is the kind of thing nobody
        // reports.
        let defaults = Self.scratchDefaults("legacy")
        defaults.set("straight:17", forKey: "rouletteBet")
        defaults.set(10, forKey: "rouletteStake")

        let table = Roulette(bank: Bank(defaults: defaults), defaults: defaults)
        #expect(table.bets == [.straight(17): 10])
    }

    @Test("A fresh table opens with a chip down, so the button does something")
    func freshTableHasAChip() {
        let defaults = Self.scratchDefaults("fresh")
        let table = Roulette(bank: Bank(defaults: defaults), defaults: defaults)
        #expect(table.totalStake > 0)
        #expect(table.canSpin)
    }

    @Test("Nothing on the felt can be changed while the wheel is turning")
    func lockedMidSpin() {
        let defaults = Self.scratchDefaults("locked")
        let table = Roulette(bank: Bank(defaults: defaults), defaults: defaults)
        table.clearBets()
        table.setStake(5)
        table.place(.red)
        table.spin()

        let staked = table.totalStake
        table.place(.black)
        table.setStake(25)
        table.placeInside(covering: [8, 9])
        table.clearBets()
        table.remove(.red)

        #expect(table.bets == [.red: 5])
        #expect(table.totalStake == staked)
        #expect(table.stake == 5)
    }

    @Test("Every resolved coup is filed, and the ledger reconciles with the bank")
    func ledgerRecordsCoups() async throws {
        let defaults = Self.scratchDefaults("ledger")
        let bank = Bank(defaults: defaults)
        let table = Roulette(bank: bank, defaults: defaults)
        let opening = bank.credits

        table.spin()
        let deadline = Date().addingTimeInterval(120)
        while table.isSpinning, Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        let number = try #require(table.result)
        #expect(table.ledger.spins == 1)
        #expect(table.ledger.coups == 1)
        #expect(table.ledger.pockets[number] == 1)
        #expect(table.ledger.wagered == table.lastStake)
        #expect(table.ledger.won == table.lastWin)
        #expect(bank.credits == opening + table.ledger.net)
        // The slot machine's breakdown stays empty — these are two separate diaries.
        #expect(table.ledger.triples.isEmpty)
    }
}
