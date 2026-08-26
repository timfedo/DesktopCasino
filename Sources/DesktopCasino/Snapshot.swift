import AppKit
import CasinoKit
import SwiftUI

/// Debug affordance: `DesktopCasino --snapshot out.png` renders the UI offscreen and exits.
/// Useful for eyeballing layout without granting Screen Recording to capture a desktop-level
/// window. The card backdrop is opaque, so what this renders is what the panel looks like on a
/// desktop — it no longer reads darker here than it does over a wallpaper.
@MainActor
enum Snapshot {
    static func writeIfRequested() -> Bool {
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--snapshot"), flag + 1 < args.count {
            render(CasinoView(machine: SlotMachine(), alwaysHovered: true), to: args[flag + 1])
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
