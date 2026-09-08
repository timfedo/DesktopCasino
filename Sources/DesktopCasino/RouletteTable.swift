import CasinoKit
import SwiftUI

/// The middle of the card when the roulette table is in front of you: the wheel, what it last
/// paid, and the felt you put chips on.
///
/// The credits readout, the stake chips and the gold button are not here — they belong to the
/// card, which shares them with the slot machine.
struct RouletteTable: View {
    let roulette: Roulette
    /// Passed in rather than derived: the balance belongs to the house, not to this table.
    var broke = false

    static let wheelDiameter: CGFloat = 220

    var body: some View {
        VStack(spacing: 9) {
            wheel
            outcomeLine
            tableLine
            RouletteFelt(
                bets: roulette.bets,
                result: roulette.result,
                disabled: roulette.isSpinning,
                place: { roulette.place($0) },
                placeCovering: { roulette.placeInside(covering: $0) },
                remove: { roulette.remove($0) }
            )
        }
    }

    // MARK: - Sections

    private var wheel: some View {
        RouletteWheelView(
            turns: roulette.wheelTurns,
            spinStart: roulette.wheelStart,
            spinTarget: roulette.wheelTarget,
            landingIndex: roulette.landingIndex,
            ballStart: roulette.ballStart,
            result: roulette.result,
            won: isWin,
            diameter: Self.wheelDiameter
        )
        .shadow(color: isWin ? Palette.gold.opacity(0.5) : .clear, radius: 16)
        .scaleEffect(isWin ? 1.02 : 1)
        .animation(.spring(duration: 0.45, bounce: 0.4), value: roulette.spinCount)
    }

    private var outcomeLine: some View {
        VStack(spacing: 2) {
            Text(outcomeText)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(isWin ? Palette.gold : .white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            // Net, not gross: the stakes left the balance the moment the wheel was pushed, so a
            // table returning 90 on 45 staked gained 45, not 90. Same convention as the slot
            // machine's line, because it is the same balance underneath.
            Text(isWin ? "+\(roulette.lastWin - roulette.lastStake)" : " ")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.gold)
        }
        .frame(height: 32)
        .animation(.easeOut(duration: 0.2), value: roulette.spinCount)
    }

    /// What is on the table, and the way off it. Sits between the result and the felt because it
    /// describes the felt rather than the spin.
    private var tableLine: some View {
        HStack(spacing: 6) {
            Text(tableSummary)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.1)
                .foregroundStyle(roulette.bets.isEmpty
                                 ? .white.opacity(0.4) : Palette.gold.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)

            if !roulette.bets.isEmpty && !roulette.isSpinning {
                Button("CLEAR") { roulette.clearBets() }
                    .buttonStyle(.plain)
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 6)
                    .frame(height: 14)
                    .background(.white.opacity(0.09), in: .rect(cornerRadius: 4))
                    .help("Take every chip off the table")
            }
        }
        .frame(height: 14)
        .animation(.easeOut(duration: 0.15), value: roulette.bets)
    }

    // MARK: - Derived

    private var isWin: Bool {
        if case .won = roulette.outcome, !roulette.isSpinning { return true }
        return false
    }

    private var tableSummary: String {
        let chips = roulette.bets.count
        guard chips > 0 else { return "NO CHIPS DOWN — CLICK THE FELT" }
        if chips == 1, let only = roulette.placedBets.first {
            let spread = only.bet.spread
            let name = spread.isEmpty ? only.bet.label : "\(only.bet.label) \(spread)"
            return "\(name) · \(only.stake) · \(only.bet.payout)×"
        }
        return "\(chips) CHIPS · \(roulette.totalStake) DOWN"
    }

    private var outcomeText: String {
        // Says why the gold button now offers a refill instead of a spin, the same way the slot
        // machine's line does — and for the same reason it takes precedence over the last result.
        if broke, !roulette.isSpinning { return "OUT OF CREDITS" }
        return switch roulette.outcome {
        case .idle: "PLACE YOUR BETS"
        case .spinning: "NO MORE BETS"
        case .won(let number):
            // With several chips down, "you won" is a count rather than a yes or no.
            "\(number) \(RouletteWheel.colorName(of: number)) — \(wonSummary)"
        case .lost(let number):
            "\(number) \(RouletteWheel.colorName(of: number)) — NO WIN"
        }
    }

    private var wonSummary: String {
        let won = roulette.winningBets
        return won <= 1 ? "PAID" : "\(won) BETS PAID"
    }
}
