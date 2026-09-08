import AppKit
import CasinoKit
import SwiftUI

/// Debug affordance: `DesktopCasino --snapshot out.png` renders the UI offscreen and exits.
/// Useful for eyeballing layout without granting Screen Recording to capture a desktop-level
/// window. The card backdrop is opaque, so what this renders is what the panel looks like on a
/// desktop — it no longer reads darker here than it does over a wallpaper.
///
/// Not to be confused with the test suite's `Snapshot`, which compares renders against
/// committed references. This one only writes a PNG for a human to look at.
@MainActor
enum OffscreenRender {
    static func writeIfRequested() -> Bool {
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--snapshot"), flag + 1 < args.count {
            render(
                CasinoView(casino: Casino(), alwaysHovered: true, isStill: true),
                to: args[flag + 1]
            )
            return true
        }
        // `--roulette` renders the other table, which `--snapshot` only shows if that is the one
        // you happened to leave the widget on.
        //
        // Staged against a scratch domain, not the real one. `select` and the bet setters write
        // through as they are called, so composing a picture here would otherwise move the widget
        // to the roulette table behind the player's back — which is exactly what it did.
        if let flag = args.firstIndex(of: "--roulette"), flag + 1 < args.count {
            let casino = Casino(defaults: scratchDefaults())
            casino.select(.roulette)
            // A table with several chips on it, which is what the felt is for.
            casino.roulette.stage(
                number: 17,
                bets: [.straight(17): 5, .black: 10, .dozen(2): 5, .inside([1, 2, 4, 5]): 5],
                stake: 5
            )
            render(
                CasinoView(casino: casino, alwaysHovered: true, isStill: true),
                to: args[flag + 1]
            )
            return true
        }
        // `--faces` shows every symbol at once, which a single spin cannot do.
        if let flag = args.firstIndex(of: "--faces"), flag + 1 < args.count {
            render(FaceSheet(), to: args[flag + 1])
            return true
        }
        // `--win` forces the three-of-a-kind marquee, which otherwise needs a 1-in-21 spin.
        if let flag = args.firstIndex(of: "--win"), flag + 1 < args.count {
            render(WinSheet(), to: args[flag + 1])
            return true
        }
        // `--stats` renders the stats window over a fixed fortnight of play, which a real ledger
        // only reaches after a fortnight of playing.
        if let flag = args.firstIndex(of: "--stats"), flag + 1 < args.count {
            let today = Date()
            render(
                StatsView(ledger: .sample(endingOn: today), credits: 240, today: today,
                          onReset: {})
                    .frame(width: 400)
                    .background { Palette.felt },
                to: args[flag + 1]
            )
            return true
        }
        // The same screen for the other table, which shows a different breakdown entirely.
        if let flag = args.firstIndex(of: "--stats-roulette"), flag + 1 < args.count {
            let today = Date()
            render(
                StatsView(ledger: .rouletteSample(endingOn: today), credits: 240,
                          game: .roulette, today: today, onReset: {}, onSelect: { _ in })
                    .frame(width: 400)
                    .background { Palette.felt },
                to: args[flag + 1]
            )
            return true
        }
        return false
    }

    private struct WinSheet: View {
        var body: some View {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    SymbolFace(symbol: Reel.symbols.first { $0.name == "seven" }!)
                        .frame(width: ReelView.width, height: ReelView.stopHeight)
                        .background(
                            LinearGradient(colors: [.white.opacity(0.09), .white.opacity(0.03)],
                                           startPoint: .top, endPoint: .bottom),
                            in: .rect(cornerRadius: 8)
                        )
                }
            }
            .padding(8)
            .background(.black.opacity(0.45), in: .rect(cornerRadius: 12))
            .overlay { WinMarquee(cornerRadius: 12, stripe: Palette.gold, base: Palette.red) }
            .padding(28)
            .background(Color(red: 0.03, green: 0.08, blue: 0.06))
        }
    }

    private struct FaceSheet: View {
        var body: some View {
            HStack(spacing: 6) {
                ForEach(Reel.symbols, id: \.name) { symbol in
                    SymbolFace(symbol: symbol)
                        .frame(width: ReelView.width, height: ReelView.stopHeight)
                        .background(
                            LinearGradient(colors: [.white.opacity(0.09), .white.opacity(0.03)],
                                           startPoint: .top, endPoint: .bottom),
                            in: .rect(cornerRadius: 8)
                        )
                }
            }
            .padding(10)
            .background(.black.opacity(0.9))
        }
    }

    /// A throwaway domain for renders that have to compose a state to photograph it.
    private static func scratchDefaults() -> UserDefaults {
        let suite = "DesktopCasino.offscreen.\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite) ?? .standard
    }

    private static func render(_ content: some View, to path: String) {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("snapshot: render failed\n".utf8))
            exit(1)
        }

        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("snapshot written to \(path)")
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
            exit(1)
        }
    }
}
