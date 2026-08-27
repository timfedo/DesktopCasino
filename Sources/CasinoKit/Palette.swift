import SwiftUI

public enum Palette {
    public static let gold = Color(red: 0.98, green: 0.79, blue: 0.35)
    public static let red = Reel.slotRed
    /// Losses in the stats window. `red` is the reel's saturated signage red, which is right for
    /// a marquee and unreadable as small text on dark felt; this is the same hue lifted.
    public static let loss = Color(red: 0.96, green: 0.46, blue: 0.43)
    // Green has to lead in *both* stops. `cardBottom` used to be blue-dominant
    // (0.02, 0.05, 0.08), so the card faded from felt green into navy and read colder than the
    // top suggested — most of the "not very green" was down there rather than in `cardTop`.
    public static let cardTop = Color(red: 0.04, green: 0.20, blue: 0.12)
    public static let cardBottom = Color(red: 0.02, green: 0.07, blue: 0.06)

    /// The card over an opaque black backing. What the stats window sits on, where there is no
    /// wallpaper underneath to show through the way there is behind the panel.
    public static var felt: some View {
        ZStack {
            Color.black
            card()
        }
    }

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
