import Foundation
import Testing

@testable import CasinoKit

/// Everything here runs against a fixed calendar in UTC and explicit dates. The ledger buckets by
/// local calendar day, so a test that used `Date()` and the runner's time zone would pass or fail
/// depending on what time of day CI happened to run.
@MainActor
@Suite("Ledger")
struct LedgerTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static let cherry = Reel.symbols.first { $0.name == "cherry" }!
    private static let diamond = Reel.symbols.first { $0.name == "diamond" }!

    /// Files one spin on a chosen day, so a case can describe a run of play in a few lines.
    private static func play(
        _ ledger: inout Ledger,
        stake: Int,
        payout: Int,
        outcome: SlotMachine.Outcome = .nothing,
        bank: Int = 100,
        on day: Date
    ) {
        ledger.record(stake: stake, payout: payout, outcome: outcome, bank: bank,
                      at: day, calendar: calendar)
    }

    // MARK: - Days

    @Test("Spins land in the calendar day they resolved on")
    func spinsBucketByDay() {
        var ledger = Ledger()
        let monday = Self.date(2026, 8, 24)
        let tuesday = Self.date(2026, 8, 25)

        Self.play(&ledger, stake: 10, payout: 0, on: monday)
        Self.play(&ledger, stake: 10, payout: 50, outcome: .triple(Self.cherry), on: tuesday)

        #expect(ledger.days.count == 2)
        #expect(ledger.day(monday, calendar: Self.calendar).net == -10)
        #expect(ledger.day(tuesday, calendar: Self.calendar).net == 40)
        #expect(ledger.net == 30)
    }

    @Test("Two spins on the same day accumulate into one bucket")
    func sameDayAccumulates() {
        var ledger = Ledger()
        let day = Self.date(2026, 8, 24)
        Self.play(&ledger, stake: 5, payout: 0, on: day)
        Self.play(&ledger, stake: 5, payout: 25, outcome: .triple(Self.cherry), on: day)

        let record = ledger.day(day, calendar: Self.calendar)
        #expect(record.spins == 2)
        #expect(record.wagered == 10)
        #expect(record.won == 25)
        #expect(record.net == 15)
        #expect(ledger.days.count == 1)
    }

    @Test("The best day is the highest net, not the busiest or the most recent")
    func bestDayIsHighestNet() {
        var ledger = Ledger()
        let quiet = Self.date(2026, 8, 20)
        let busy = Self.date(2026, 8, 21)
        let latest = Self.date(2026, 8, 22)

        // One big win on a quiet day.
        Self.play(&ledger, stake: 25, payout: 2500, outcome: .triple(Self.diamond), on: quiet)
        // A lot of play that went nowhere.
        for _ in 0..<40 { Self.play(&ledger, stake: 10, payout: 10, outcome: .pair(Self.cherry), on: busy) }
        // A more recent, smaller win.
        Self.play(&ledger, stake: 25, payout: 500, on: latest)

        let best = ledger.bestDay
        #expect(best?.key == Ledger.dayKey(for: quiet, calendar: Self.calendar))
        #expect(best?.day.net == 2475)
    }

    @Test("A ledger of nothing but losing days still reports its least bad one")
    func bestDayOfLosingDays() {
        var ledger = Ledger()
        Self.play(&ledger, stake: 25, payout: 0, on: Self.date(2026, 8, 20))
        Self.play(&ledger, stake: 5, payout: 0, on: Self.date(2026, 8, 21))

        #expect(ledger.bestDay?.day.net == -5)
    }

    @Test("Ties on net go to the more recent day")
    func bestDayTieBreaksLater() {
        var ledger = Ledger()
        Self.play(&ledger, stake: 10, payout: 60, on: Self.date(2026, 8, 20))
        Self.play(&ledger, stake: 10, payout: 60, on: Self.date(2026, 8, 21))

        #expect(ledger.bestDay?.key == "2026-08-21")
    }

    @Test("There is no best day before anything has been played")
    func bestDayIsAbsentWhenEmpty() {
        #expect(Ledger().bestDay == nil)
    }

    @Test("The recent window is contiguous, with unplayed days present and empty")
    func recentDaysFillsGaps() {
        var ledger = Ledger()
        Self.play(&ledger, stake: 10, payout: 0, on: Self.date(2026, 8, 20))
        Self.play(&ledger, stake: 10, payout: 0, on: Self.date(2026, 8, 24))

        let series = ledger.recentDays(7, endingOn: Self.date(2026, 8, 24),
                                       calendar: Self.calendar)

        #expect(series.count == 7)
        #expect(series.map(\.key) == [
            "2026-08-18", "2026-08-19", "2026-08-20", "2026-08-21",
            "2026-08-22", "2026-08-23", "2026-08-24",
        ])
        // The two played days carry spins; the five between and around them are blank rather
        // than missing, which is what keeps the chart's x axis a real timeline.
        #expect(series.filter { $0.day.spins > 0 }.count == 2)
        #expect(series.last?.day.spins == 1)
    }

    @Test("History is capped, oldest first")
    func historyIsPruned() {
        var ledger = Ledger()
        let start = Self.date(2025, 1, 1)
        for offset in 0..<(Ledger.historyLimit + 30) {
            let day = Self.calendar.date(byAdding: .day, value: offset, to: start)!
            Self.play(&ledger, stake: 1, payout: 0, on: day)
        }

        #expect(ledger.days.count == Ledger.historyLimit)
        // Lifetime totals survive the pruning — only the day-by-day breakdown is bounded.
        #expect(ledger.spins == Ledger.historyLimit + 30)
        #expect(ledger.days[Ledger.dayKey(for: start, calendar: Self.calendar)] == nil)
        let newest = Self.calendar.date(byAdding: .day, value: Ledger.historyLimit + 29,
                                        to: start)!
        #expect(ledger.days[Ledger.dayKey(for: newest, calendar: Self.calendar)] != nil)
    }

    // MARK: - Wins, pushes and streaks

    @Test("A 1x pair is a push, not a win")
    func pushIsNotAWin() {
        var ledger = Ledger()
        let day = Self.date(2026, 8, 24)
        // Cherry pairs pay 1x: the stake back, net zero.
        Self.play(&ledger, stake: 10, payout: 10, outcome: .pair(Self.cherry), on: day)

        #expect(ledger.pushes == 1)
        #expect(ledger.gains == 0)
        #expect(ledger.gainRate == 0)
        #expect(ledger.pushRate == 1)
        #expect(ledger.net == 0)
    }

    @Test("Streaks run and reset, and the longest of each is kept")
    func streaks() {
        var ledger = Ledger()
        let day = Self.date(2026, 8, 24)

        for _ in 0..<3 { Self.play(&ledger, stake: 5, payout: 40, on: day) }
        #expect(ledger.winStreak == 3)
        #expect(ledger.longestWinStreak == 3)

        for _ in 0..<5 { Self.play(&ledger, stake: 5, payout: 0, on: day) }
        #expect(ledger.winStreak == 0)
        #expect(ledger.drySpell == 5)
        #expect(ledger.longestDrySpell == 5)

        for _ in 0..<2 { Self.play(&ledger, stake: 5, payout: 40, on: day) }
        #expect(ledger.drySpell == 0)
        #expect(ledger.winStreak == 2)
        // The earlier, longer run is not forgotten when a shorter one replaces it.
        #expect(ledger.longestWinStreak == 3)
        #expect(ledger.longestDrySpell == 5)
    }

    @Test("A push breaks a winning streak and extends the cold one")
    func pushBreaksAStreak() {
        var ledger = Ledger()
        let day = Self.date(2026, 8, 24)
        Self.play(&ledger, stake: 5, payout: 40, on: day)
        Self.play(&ledger, stake: 5, payout: 5, outcome: .pair(Self.cherry), on: day)

        #expect(ledger.winStreak == 0)
        #expect(ledger.drySpell == 1)
    }

    @Test("Landings are tallied by kind and by symbol, and account for every spin")
    func landingTallies() {
        var ledger = Ledger()
        let day = Self.date(2026, 8, 24)
        Self.play(&ledger, stake: 5, payout: 500, outcome: .triple(Self.diamond), on: day)
        Self.play(&ledger, stake: 5, payout: 25, outcome: .triple(Self.cherry), on: day)
        Self.play(&ledger, stake: 5, payout: 5, outcome: .pair(Self.cherry), on: day)
        Self.play(&ledger, stake: 5, payout: 0, on: day)

        #expect(ledger.jackpots == 1)
        #expect(ledger.triples["cherry"] == 1)
        #expect(ledger.tripleTotal == 2)
        #expect(ledger.pairs == 1)
        #expect(ledger.blanks == 1)
        #expect(ledger.tripleTotal + ledger.pairs + ledger.blanks == ledger.spins)
    }

    @Test("The biggest payout keeps its symbol and its date")
    func biggestPayout() {
        var ledger = Ledger()
        let early = Self.date(2026, 8, 20)
        let late = Self.date(2026, 8, 24)
        Self.play(&ledger, stake: 25, payout: 2500, outcome: .triple(Self.diamond), on: early)
        Self.play(&ledger, stake: 25, payout: 125, outcome: .triple(Self.cherry), on: late)

        #expect(ledger.bestWin == 2500)
        #expect(ledger.bestWinSymbol == "diamond")
        #expect(ledger.bestWinAt == early)
    }

    @Test("The high-water mark tracks the peak, not the latest balance")
    func peakBank() {
        var ledger = Ledger()
        let day = Self.date(2026, 8, 24)
        Self.play(&ledger, stake: 25, payout: 500, bank: 575, on: day)
        Self.play(&ledger, stake: 25, payout: 0, bank: 550, on: day)

        #expect(ledger.peakBank == 575)
    }

    @Test("Return rate is payouts over stakes")
    func returnRate() {
        var ledger = Ledger()
        let day = Self.date(2026, 8, 24)
        Self.play(&ledger, stake: 100, payout: 90, on: day)

        #expect(abs(ledger.returnRate - 0.9) < 0.0001)
        #expect(Ledger().returnRate == 0)
    }

    // MARK: - Persistence

    @Test("A ledger round-trips through JSON intact")
    func codableRoundTrip() throws {
        var ledger = Ledger()
        Self.play(&ledger, stake: 25, payout: 2500, outcome: .triple(Self.diamond), bank: 900,
                  on: Self.date(2026, 8, 20))
        Self.play(&ledger, stake: 5, payout: 0, on: Self.date(2026, 8, 21))
        ledger.recordRefill(bank: 100)

        let data = try JSONEncoder().encode(ledger)
        let restored = try JSONDecoder().decode(Ledger.self, from: data)

        #expect(restored == ledger)
    }

    @Test("A ledger written by an older build loads with defaults instead of throwing")
    func decodingToleratesMissingKeys() throws {
        // Everything but `spins` and one day is absent, which is what a field added later looks
        // like from the other side. Throwing here would wipe a real history on upgrade.
        let json = Data("""
        {"spins": 12, "days": {"2026-08-20": {"spins": 12, "wagered": 60}}}
        """.utf8)

        let ledger = try JSONDecoder().decode(Ledger.self, from: json)

        #expect(ledger.spins == 12)
        #expect(ledger.days["2026-08-20"]?.wagered == 60)
        #expect(ledger.days["2026-08-20"]?.won == 0)
        #expect(ledger.peakBank == 0)
        #expect(ledger.bestWinSymbol == nil)
    }

    @Test("An empty object decodes to an empty ledger")
    func decodingAnEmptyObject() throws {
        let ledger = try JSONDecoder().decode(Ledger.self, from: Data("{}".utf8))
        #expect(ledger == Ledger())
    }

    // MARK: - Labels

    @Test("Day keys sort in date order, which is what pruning and `bestDay` rely on")
    func dayKeysSortChronologically() {
        let keys = [
            Ledger.dayKey(for: Self.date(2026, 1, 5), calendar: Self.calendar),
            Ledger.dayKey(for: Self.date(2025, 12, 31), calendar: Self.calendar),
            Ledger.dayKey(for: Self.date(2026, 1, 12), calendar: Self.calendar),
        ]
        #expect(keys.sorted() == ["2025-12-31", "2026-01-05", "2026-01-12"])
    }

    @Test("Labels are fixed English, whatever the runner's region is")
    func labels() {
        #expect(Ledger.shortLabel(forDay: "2026-08-05") == "5 Aug")
        #expect(Ledger.longLabel(forDay: "2026-12-31") == "31 Dec 2026")
        // Garbage in, garbage out — but not a crash, and not a wrong month.
        #expect(Ledger.shortLabel(forDay: "nonsense") == "nonsense")
    }

    @Test("Figures are grouped and signed the same way in any locale")
    func numberFormatting() {
        #expect(Format.grouped(0) == "0")
        #expect(Format.grouped(999) == "999")
        #expect(Format.grouped(1234) == "1,234")
        #expect(Format.grouped(1_234_567) == "1,234,567")
        #expect(Format.signed(1234) == "+1,234")
        #expect(Format.signed(-85) == "−85")
        #expect(Format.signed(0) == "0")
        #expect(Format.count(1, "spin") == "1 spin")
        #expect(Format.count(0, "spin") == "0 spins")
        #expect(Format.percent(0.9123) == "91.2%")
    }

    // MARK: - Sample data

    @Test("The sample ledger is deterministic and covers the chart window")
    func sampleIsStable() {
        let today = Self.date(2026, 8, 27)
        let first = Ledger.sample(endingOn: today, calendar: Self.calendar)
        let second = Ledger.sample(endingOn: today, calendar: Self.calendar)

        #expect(first == second)
        #expect(first.spins > 0)
        // Twelve days of play with one deliberately skipped.
        #expect(first.days.count == 11)
        #expect(first.days["2026-08-20"] == nil)
    }
}
