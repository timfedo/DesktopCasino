import SwiftUI

public enum Palette {
    public static let gold = Color(red: 0.98, green: 0.79, blue: 0.35)
    public static let red = Reel.slotRed
    public static let cardTop = Color(red: 0.05, green: 0.16, blue: 0.11)
    public static let cardBottom = Color(red: 0.02, green: 0.05, blue: 0.08)

    /// The widget's own backdrop, shared so the app icon matches it exactly.
    public static func card(opacity: Double = 1) -> LinearGradient {
        LinearGradient(
            colors: [cardTop.opacity(0.85 * opacity), cardBottom.opacity(0.92 * opacity)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Draws a single reel symbol. The seven is a tinted numeral with a matching glow so it reads
/// like a slot machine seven rather than the blue 7️⃣ keycap emoji.
public struct SymbolFace: View {
    public let symbol: Symbol
    public var pointSize: CGFloat

    public init(symbol: Symbol, pointSize: CGFloat = 32) {
        self.symbol = symbol
        self.pointSize = pointSize
    }

    public var body: some View {
        switch symbol.face {
        case .emoji(let glyph):
            Text(glyph)
                .font(.system(size: pointSize))
        case .numeral(let text, let color):
            Text(text)
                .font(.system(size: pointSize * 1.19, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [color, color.opacity(0.72)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: color.opacity(0.7), radius: pointSize * 0.22)
        }
    }
}
