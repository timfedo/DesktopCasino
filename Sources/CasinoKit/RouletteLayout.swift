import Foundation

/// The betting layout — the felt, not the wheel.
///
/// Two different arrangements of the same 37 numbers, and keeping them straight matters: the wheel
/// is in running order so no arc of it favours a bet, while the felt is in numerical order so the
/// grid can be read. Nothing here knows about pockets; `RouletteWheel` is the other one.
///
/// The grid is 12 columns of 3, filled downward — column 0 carries 3, 2, 1 from the top, which is
/// how a real layout reads, and is why the top row is the multiples of three.
public enum RouletteLayout {
    public static let columns = 12
    public static let rows = 3

    /// Column of `number`, 0...11 left to right. The zero is not on the grid; it sits alongside.
    public static func column(of number: Int) -> Int? {
        guard (1...36).contains(number) else { return nil }
        return (number - 1) / rows
    }

    /// Row of `number`, 0 at the *top*. The top row is 3, 6, 9 … 36.
    public static func row(of number: Int) -> Int? {
        guard (1...36).contains(number) else { return nil }
        return rows - 1 - (number - 1) % rows
    }

    public static func number(column: Int, row: Int) -> Int? {
        guard (0..<columns).contains(column), (0..<rows).contains(row) else { return nil }
        return column * rows + (rows - row)
    }

    /// Every number in a felt column bet — the "2:1" boxes down the right-hand side. Numbered
    /// from the top, so column 1 is the row carrying 3, 6, 9 …
    public static func columnBet(_ which: Int) -> Set<Int> {
        guard (1...rows).contains(which) else { return [] }
        return Set((0..<columns).compactMap { number(column: $0, row: which - 1) })
    }

    public static func dozen(_ which: Int) -> Set<Int> {
        guard (1...3).contains(which) else { return [] }
        return Set(((which - 1) * 12 + 1)...(which * 12))
    }

    // MARK: - Inside bets

    /// The zero's own combinations. A real felt lets you back the zero with the numbers it touches
    /// at the corner of the layout, and nothing else — {0,1,3} looks plausible and is not a bet.
    static let zeroCombinations: [Set<Int>] = [
        [0], [0, 1], [0, 2], [0, 3], [0, 1, 2], [0, 2, 3], [0, 1, 2, 3],
    ]

    /// Whether `numbers` is a chip you could actually place: a straight, split, street, corner,
    /// line, or one of the zero's combinations.
    ///
    /// This is what makes clicking cells a betting *layout* rather than a pick-any-numbers game.
    /// Any set of numbers has a defensible payout — 36 over however many it covers — but only
    /// these shapes are bets, and letting someone build "17 and 34" would quietly be a different
    /// game with a different variance.
    public static func isLegalInside(_ numbers: Set<Int>) -> Bool {
        guard !numbers.isEmpty, numbers.allSatisfy({ (0...36).contains($0) }) else { return false }
        if numbers.contains(0) { return zeroCombinations.contains(numbers) }

        let cells = numbers.compactMap { number -> (column: Int, row: Int)? in
            guard let onColumn = column(of: number), let onRow = row(of: number) else { return nil }
            return (onColumn, onRow)
        }
        guard cells.count == numbers.count else { return false }

        let columnsUsed = Set(cells.map(\.column))
        let rowsUsed = Set(cells.map(\.row))

        switch numbers.count {
        case 1:
            return true
        case 2:
            // Neighbours, sharing an edge: same column one row apart, or same row one column apart.
            let sortedColumns = columnsUsed.sorted()
            let sortedRows = rowsUsed.sorted()
            if columnsUsed.count == 1 { return sortedRows[1] - sortedRows[0] == 1 }
            if rowsUsed.count == 1 { return sortedColumns[1] - sortedColumns[0] == 1 }
            return false
        case 3:
            // A street: one whole column, top to bottom.
            return columnsUsed.count == 1 && rowsUsed.count == rows
        case 4:
            // A corner: a 2x2 block, so exactly two adjacent columns and two adjacent rows.
            return isBlock(columnsUsed, rowsUsed, width: 2, height: 2)
        case 6:
            // A line: two whole adjacent columns.
            return isBlock(columnsUsed, rowsUsed, width: 2, height: rows)
        default:
            return false
        }
    }

    /// A full rectangle of the given size, with both spans contiguous. The cell count is checked
    /// by the caller, so contiguous spans of the right size can only be the filled block.
    private static func isBlock(
        _ columnsUsed: Set<Int>, _ rowsUsed: Set<Int>, width: Int, height: Int
    ) -> Bool {
        guard columnsUsed.count == width, rowsUsed.count == height else { return false }
        return isRun(columnsUsed) && isRun(rowsUsed)
    }

    private static func isRun(_ values: Set<Int>) -> Bool {
        guard let low = values.min(), let high = values.max() else { return false }
        return high - low == values.count - 1
    }

    /// Every chip that can be placed inside the grid: each straight, split, street, corner and
    /// line, plus the zero's combinations.
    ///
    /// Enumerated rather than derived on demand. There are only 145 of them, and having the list
    /// is what lets `resolve(_:)` answer "what did they mean" by looking rather than by reasoning
    /// about shapes — which is the part that would be subtly wrong.
    public static let allInsideBets: [Set<Int>] = {
        var bets: [Set<Int>] = zeroCombinations
        for column in 0..<columns {
            let street = Set((0..<rows).compactMap { number(column: column, row: $0) })

            for row in 0..<rows {
                guard let here = number(column: column, row: row) else { continue }
                bets.append([here])
                if let below = number(column: column, row: row + 1) {
                    bets.append([here, below])
                }
                if let right = number(column: column + 1, row: row) {
                    bets.append([here, right])
                }
                // Corners are named by their top-left cell, so each one is found exactly once.
                if let right = number(column: column + 1, row: row),
                   let below = number(column: column, row: row + 1),
                   let diagonal = number(column: column + 1, row: row + 1) {
                    bets.append([here, right, below, diagonal])
                }
            }

            bets.append(street)
            let next = Set((0..<rows).compactMap { number(column: column + 1, row: $0) })
            if next.count == rows { bets.append(street.union(next)) }
        }
        return bets
    }()

    /// What a set of clicked numbers means as a bet: the smallest chip on the felt that covers all
    /// of them, or `nil` if no single chip does.
    ///
    /// Needed because the obvious rule — every click must leave a legal bet — makes corners and
    /// lines *unreachable*. Every three-number subset of a corner is an illegal shape, in every
    /// order, so there is no click sequence that arrives at one. Resolving upward instead matches
    /// what a real felt does anyway: a chip on the corner backs all four numbers, and you were
    /// never placing them one at a time.
    public static func resolve(_ numbers: Set<Int>) -> Set<Int>? {
        guard !numbers.isEmpty else { return nil }
        if isLegalInside(numbers) { return numbers }
        return allInsideBets
            .filter { numbers.isSubset(of: $0) }
            // Smallest first, so three numbers in a square become the corner and not the line that
            // also contains them. Ties break on the lowest number for a stable answer.
            .min { ($0.count, $0.min() ?? 0) < ($1.count, $1.min() ?? 0) }
    }

    /// What a legal inside bet is called, by how many numbers it covers.
    public static func insideName(_ numbers: Set<Int>) -> String {
        if numbers.contains(0), numbers.count > 1 {
            return numbers.count == 4 ? "BASKET" : (numbers.count == 3 ? "TRIO" : "SPLIT")
        }
        switch numbers.count {
        case 1: return "STRAIGHT"
        case 2: return "SPLIT"
        case 3: return "STREET"
        case 4: return "CORNER"
        case 6: return "LINE"
        default: return "INSIDE"
        }
    }
}
