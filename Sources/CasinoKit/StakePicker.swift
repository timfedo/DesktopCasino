import SwiftUI

/// The row of chips that sets the stake.
///
/// Shared by both tables. It was the slot machine's, inline in `CasinoView`; roulette wanted the
/// identical control, and two copies of a styling this fiddly drift the first time either is
/// touched.
public struct StakePicker: View {
    public let stake: Int
    public let credits: Int
    /// Set while a round is in flight — the stake is already down and cannot be changed.
    public let locked: Bool
    public let select: (Int) -> Void

    public init(stake: Int, credits: Int, locked: Bool, select: @escaping (Int) -> Void) {
        self.stake = stake
        self.credits = credits
        self.locked = locked
        self.select = select
    }

    public static let height: CGFloat = 24

    public var body: some View {
        HStack(spacing: 5) {
            ForEach(Bank.betSizes, id: \.self) { size in
                let selected = stake == size
                Button {
                    select(size)
                } label: {
                    Text("\(size)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(selected ? .black : .white.opacity(0.65))
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.height)
                        .background(selected ? Palette.gold : .white.opacity(0.09),
                                    in: .rect(cornerRadius: 7))
                        // Scoped to the chip rather than the row. On the row it also animated the
                        // row's *own* frame, so switching table — which changes both the stake and
                        // the height of everything above this — slid the whole picker down the
                        // card instead of it simply being in its new place. A chip's frame never
                        // moves within the row, so here it can only animate the fill.
                        .animation(.easeOut(duration: 0.15), value: selected)
                }
                .buttonStyle(.plain)
                .disabled(locked || size > credits)
                .opacity(size > credits ? 0.35 : 1)
            }
        }
    }
}
