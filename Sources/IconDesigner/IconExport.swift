import AppKit
import SwiftUI

/// Writes the artwork to disk: a 1024px PNG, plus a full `.icns` built through `iconutil`.
@MainActor
enum IconExport {
    /// The sizes an `.iconset` must contain, as (pixels, filename).
    private static let iconsetSizes: [(Int, String)] = [
        (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
    ]

    static func png(for config: IconConfig, side: Int) -> Data? {
        let renderer = ImageRenderer(
            content: IconArtwork(config: config)
                .frame(width: CGFloat(side), height: CGFloat(side))
        )
        renderer.scale = 1

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }

        return bitmap.representation(using: .png, properties: [:])
    }

    /// Returns a short human-readable summary of what was written.
    static func write(_ config: IconConfig, to directory: URL) async throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let pngURL = directory.appendingPathComponent("AppIcon.png")
        guard let master = png(for: config, side: 1024) else {
            throw Failure.renderFailed
        }
        try master.write(to: pngURL)

        // Each size is rendered from scratch rather than downscaled from the 1024, so the small
        // ones keep their contrast instead of turning to mush.
        let iconset = directory.appendingPathComponent("AppIcon.iconset")
        try? FileManager.default.removeItem(at: iconset)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

        for (side, name) in iconsetSizes {
            guard let data = png(for: config, side: side) else { throw Failure.renderFailed }
            try data.write(to: iconset.appendingPathComponent(name))
            // `ImageRenderer` is main-actor bound, so ten sizes back to back freeze the window.
            // Yielding between them lets the UI keep painting.
            await Task.yield()
        }

        let icns = directory.appendingPathComponent("AppIcon.icns")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw Failure.iconutilFailed(status: process.terminationStatus)
        }
        try? FileManager.default.removeItem(at: iconset)
        return "Wrote AppIcon.png and AppIcon.icns to \(directory.path)"
    }

    enum Failure: Error, CustomStringConvertible {
        case renderFailed
        case iconutilFailed(status: Int32)

        var description: String {
            switch self {
            case .renderFailed: "render failed"
            case .iconutilFailed(let status): "iconutil exited \(status)"
            }
        }
    }
}
