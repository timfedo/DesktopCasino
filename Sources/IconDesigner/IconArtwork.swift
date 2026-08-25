import CasinoKit
import SwiftUI

/// Every knob the designer exposes. All lengths are fractions of the icon's side, so one config
/// renders identically at 16pt and 1024pt.
struct IconConfig: Equatable {
    // Rings
    var ringCount = 3.0
    var perRing = 9.0
    /// How far from the centre the outermost ring sits.
    var spread = 0.62
    /// Radius of the innermost ring — keeps satellites clear of the diamond.
    var innerGap = 0.2
    /// Shapes how ring radii are spaced. Above 1 bunches rings inward, so the outer ones spread
    /// apart and the scatter thins with distance.
    var ringSpacingBias = 1.35
    /// Rotates each successive ring by this fraction of one angular step, so spokes interleave
    /// instead of stacking into visible radial lines.
    var ringTwist = 0.5

    // Controlled irregularity: 0 gives a perfectly regular lattice.
    var angleJitter = 0.35
    var radiusJitter = 0.3

    // Satellites
    var satelliteSize = 0.13
    /// How much smaller a satellite gets with distance. 0 keeps them all one size.
    var sizeFalloff = 0.55
    /// How much a satellite fades with distance.
    var fadeFalloff = 0.45
    var maxRotation = 55.0

    // Centre and frame
    var diamondSize = 0.4
    var glowRadius = 0.24
    var glowStrength = 0.6
    var cornerRadius = 0.22
    var seed = 7.0
}

/// One satellite's placement. Derived purely from the config, so a given seed always lays out the
/// same icon.
private struct Satellite {
    let symbol: Symbol
    let offset: CGSize
    let scale: Double
    let rotation: Double
    let opacity: Double
}

/// The icon: a diamond over the widget's own backdrop, with the other reel symbols arranged in
/// rings behind it — smaller, fainter and sparser the further out they sit.
struct IconArtwork: View {
    let config: IconConfig

    /// Computed once per config rather than per `body` pass. The designer mounts five previews,
    /// so without this every slider drag redid the whole layout five times a frame.
    private let layout: [Satellite]

    init(config: IconConfig) {
        self.config = config
        self.layout = Self.placements(config: config)
    }

    private static let satellites = Reel.symbols.filter { $0.name != "diamond" }
    private static let diamond = Reel.symbols.first { $0.name == "diamond" }!

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)

            ZStack {
                Palette.cardBottom
                Palette.card()

                // Sits behind everything, so the diamond reads as lit from within.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Palette.gold.opacity(config.glowStrength),
                                Palette.gold.opacity(config.glowStrength * 0.3),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: side * config.glowRadius * 1.5
                        )
                    )
                    .frame(width: side * config.glowRadius * 3, height: side * config.glowRadius * 3)
                    .blur(radius: side * 0.02)

                ForEach(Array(layout.enumerated()), id: \.offset) { _, item in
                    SymbolFace(symbol: item.symbol, pointSize: side * config.satelliteSize)
                        .scaleEffect(item.scale)
                        .rotationEffect(.degrees(item.rotation))
                        .opacity(item.opacity)
                        .offset(x: item.offset.width * side, y: item.offset.height * side)
                }

                SymbolFace(symbol: Self.diamond, pointSize: side * config.diamondSize)
                    .shadow(color: .cyan.opacity(config.glowStrength * 0.7),
                            radius: side * config.glowRadius * 0.4)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(.rect(cornerRadius: side * config.cornerRadius))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// How many of each symbol the current config lays out. Exposed so a render can show that
    /// the deck draw really does keep the types balanced.
    func symbolTally() -> [(name: String, count: Int)] {
        Dictionary(grouping: layout, by: \.symbol.name)
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.name < $1.name }
    }

    /// Offsets come back as fractions of the side, so one layout serves every render size.
    private static func placements(config: IconConfig) -> [Satellite] {
        var rng = SplitMix64(seed: UInt64(max(config.seed, 0)) &+ 0xA11CE)
        let rings = max(Int(config.ringCount.rounded()), 1)
        let perRing = max(Int(config.perRing.rounded()), 1)

        // Drawing from a reshuffled deck rather than picking at random keeps every symbol's count
        // within one of every other's, however many satellites there are. Independent random
        // picks would leave one symbol noticeably over-represented at these small counts.
        var deck: [Symbol] = []
        func nextSymbol() -> Symbol {
            if deck.isEmpty { deck = Self.satellites.shuffled(using: &rng) }
            return deck.removeFirst()
        }

        func jitter(_ amount: Double) -> Double {
            amount == 0 ? 0 : Double.random(in: -0.5...0.5, using: &rng) * amount
        }

        let span = max(config.spread - config.innerGap, 0.0001)
        let ringGap = span / Double(max(rings - 1, 1))
        let step = 2 * .pi / Double(perRing)
        var result: [Satellite] = []

        for ring in 0..<rings {
            let t = rings == 1 ? 0 : Double(ring) / Double(rings - 1)
            let ringRadius = config.innerGap + span * pow(t, config.ringSpacingBias)

            for index in 0..<perRing {
                let angle = Double(index) * step
                    + Double(ring) * step * config.ringTwist
                    + jitter(config.angleJitter) * step
                let radius = max(ringRadius + jitter(config.radiusJitter) * ringGap, 0)
                let reach = min(max((radius - config.innerGap) / span, 0), 1)

                result.append(
                    Satellite(
                        symbol: nextSymbol(),
                        offset: CGSize(width: cos(angle) * radius, height: sin(angle) * radius),
                        scale: max(1 - config.sizeFalloff * reach, 0.05),
                        rotation: Double.random(
                            in: -config.maxRotation...config.maxRotation, using: &rng
                        ),
                        opacity: max(1 - config.fadeFalloff * reach, 0.05)
                    )
                )
            }
        }
        return result
    }
}
