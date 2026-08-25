import Testing

@testable import CasinoKit

/// Pins the payout table. The README quotes an RTP; without this a weight tweak would move the
/// house edge silently.
@Suite("Payout table")
struct PayoutTests {
    /// Exhaustive: 21^3 = 9261 combinations, so there is no need to sample.
    private static func enumerateOutcomes() -> (
        returned: Int, triples: Int, pairs: Int, nothing: Int, total: Int
    ) {
        let strip = Reel.strip
        var returned = 0, triples = 0, pairs = 0, nothing = 0

        for a in strip {
            for b in strip {
                for c in strip {
                    let spin = [a, b, c]
                    if a == b, b == c {
                        returned += a.tripleMultiplier
                        triples += 1
                    } else if let matched = spin.first(where: { s in
                        spin.filter { $0 == s }.count == 2
                    }) {
                        returned += matched.pairMultiplier
                        pairs += 1
                    } else {
                        nothing += 1
                    }
                }
            }
        }
        return (returned, triples, pairs, nothing, strip.count * strip.count * strip.count)
    }

    @Test("Strip has 21 stops")
    func stripLength() {
        #expect(Reel.strip.count == 21)
        #expect(Reel.symbols.reduce(0) { $0 + $1.weight } == 21)
    }

    @Test("Each symbol appears exactly `weight` times on the strip")
    func stripWeights() {
        for symbol in Reel.symbols {
            #expect(Reel.strip.filter { $0 == symbol }.count == symbol.weight)
        }
    }

    @Test("Return to player is exactly 48/49")
    func returnToPlayer() {
        let result = Self.enumerateOutcomes()
        // 9072/9261 reduces to 48/49; house edge is the remaining 1/49.
        #expect(result.returned == 9072)
        #expect(result.total == 9261)
        #expect(result.returned * 49 == result.total * 48)
    }

    @Test("Outcome rates: triple 1/21, pair and nothing 10/21 each")
    func outcomeRates() {
        let result = Self.enumerateOutcomes()
        #expect(result.triples * 21 == result.total)
        #expect(result.pairs * 21 == result.total * 10)
        #expect(result.nothing * 21 == result.total * 10)
        #expect(result.triples + result.pairs + result.nothing == result.total)
    }

    @Test("Diamond jackpot is 1 in 9261")
    func jackpotOdds() {
        let diamond = Reel.symbols.first { $0.name == "diamond" }!
        #expect(diamond.weight == 1)
        #expect(diamond.tripleMultiplier == 100)
        let stops = Reel.strip.count
        #expect(stops * stops * stops == 9261)
    }

    @Test("Low pairs are a push, high pairs a gain")
    func pairPayouts() {
        // Documented as deliberate: a 1x pair returns the stake and nothing more.
        for name in ["cherry", "lemon", "bell"] {
            #expect(Reel.symbols.first { $0.name == name }!.pairMultiplier == 1)
        }
        for name in ["star", "seven", "diamond"] {
            #expect(Reel.symbols.first { $0.name == name }!.pairMultiplier == 2)
        }
    }
}
