import SwiftUI

public struct Symbol: Hashable, Sendable {
    public let name: String
    public let face: Face
    /// How many stops this symbol occupies on the physical reel strip.
    public let weight: Int
    public let tripleMultiplier: Int
    public let pairMultiplier: Int

    public init(
        name: String, face: Face, weight: Int, tripleMultiplier: Int, pairMultiplier: Int
    ) {
        self.name = name
        self.face = face
        self.weight = weight
        self.tripleMultiplier = tripleMultiplier
        self.pairMultiplier = pairMultiplier
    }

    /// How a symbol is drawn. Most are emoji, but the seven is a tinted numeral: the 7️⃣ emoji
    /// is a blue keycap, and every SF Symbol is a monochrome template, so neither can give the
    /// red seven a slot machine actually uses.
    public enum Face: Hashable, Sendable {
        case emoji(String)
        case numeral(String, Color)
    }
}

public enum Reel {
    public static let slotRed = Color(red: 0.93, green: 0.17, blue: 0.22)

    public static let symbols: [Symbol] = [
        Symbol(name: "cherry",  face: .emoji("🍒"), weight: 6, tripleMultiplier: 5,   pairMultiplier: 1),
        Symbol(name: "lemon",   face: .emoji("🍋"), weight: 5, tripleMultiplier: 8,   pairMultiplier: 1),
        Symbol(name: "bell",    face: .emoji("🔔"), weight: 4, tripleMultiplier: 12,  pairMultiplier: 1),
        Symbol(name: "star",    face: .emoji("⭐️"), weight: 3, tripleMultiplier: 20,  pairMultiplier: 2),
        Symbol(name: "seven",   face: .numeral("7", slotRed), weight: 2, tripleMultiplier: 50, pairMultiplier: 2),
        Symbol(name: "diamond", face: .emoji("💎"), weight: 1, tripleMultiplier: 100, pairMultiplier: 2),
    ]

    /// The physical strip: each symbol appears `weight` times, shuffled once with a fixed
    /// seed so the running order is stable across launches. Landing on a uniformly random
    /// strip stop therefore reproduces the intended odds — same as a real reel.
    public static let strip: [Symbol] = {
        var stops = symbols.flatMap { Array(repeating: $0, count: $0.weight) }
        var rng = SplitMix64(seed: 0x5CA1_AB1E_D15C_0DE5)
        stops.shuffle(using: &rng)
        return stops
    }()
}

public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
