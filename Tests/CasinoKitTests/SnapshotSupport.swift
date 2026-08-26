import AppKit
import SwiftUI
import Testing

/// Renders a view offscreen and compares it against a committed reference PNG.
///
/// Comparison is **tolerance based, not exact**. Text and especially emoji rasterise slightly
/// differently across macOS versions and GPUs, so byte equality would make these tests fail on any
/// runner that is not the machine that recorded them — which is the usual reason snapshot suites
/// get deleted. A small mean difference passes; a real layout change moves it far past the bound.
///
/// Record or re-record with:
///
///     SNAPSHOT_RECORD=1 swift test
///
@MainActor
enum Snapshot {
    /// Where reference images live, resolved from this file so it works whatever the cwd is.
    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__")
    }

    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] != nil
    }

    /// A pixel counts as changed when any channel moves by more than this. Set above the
    /// antialiasing wobble you get between machines, below any deliberate visual change.
    static let channelThreshold = 0.1

    /// Fraction of pixels allowed to differ before the snapshot fails.
    ///
    /// Deliberately small. A *mean* difference was tried first and was useless: the corner taper
    /// touches a few hundred pixels out of seventy thousand, so halving it moved the mean far
    /// less than the tolerance and every test still passed. Counting changed pixels instead is
    /// sensitive to a localised change while staying blind to uniform rasterisation noise.
    static let tolerance = 0.002

    /// Renders at `size`, or at the view's own ideal size when that is nil.
    ///
    /// Nil is how the whole window is taken: the card's height comes from its content, so
    /// pinning it to a number here would hide exactly the regression worth catching — a control
    /// that grew and pushed the stack taller. Left free, the recorded image *is* the layout, and
    /// a height change surfaces as the size mismatch below rather than as pixels.
    static func render(
        _ view: some View, size: CGSize? = nil, scale: CGFloat = 2
    ) -> NSBitmapImageRep? {
        let content = size.map { AnyView(view.frame(width: $0.width, height: $0.height)) }
            ?? AnyView(view)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }

    static func assert(
        _ view: some View,
        size: CGSize? = nil,
        named name: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        guard let rendered = render(view, size: size) else {
            Issue.record("\(name): the renderer produced no image", sourceLocation: sourceLocation)
            return
        }
        guard let png = rendered.representation(using: .png, properties: [:]) else {
            Issue.record("\(name): could not encode PNG", sourceLocation: sourceLocation)
            return
        }

        let reference = directory.appendingPathComponent("\(name).png")

        if isRecording || !FileManager.default.fileExists(atPath: reference.path) {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            try png.write(to: reference)
            if !isRecording {
                Issue.record(
                    "\(name): no reference existed, so one was recorded. Re-run to compare.",
                    sourceLocation: sourceLocation
                )
            }
            return
        }

        guard let referenceImage = NSImage(contentsOf: reference),
              let referenceTiff = referenceImage.tiffRepresentation,
              let expected = NSBitmapImageRep(data: referenceTiff)
        else {
            Issue.record("\(name): reference could not be read", sourceLocation: sourceLocation)
            return
        }

        guard expected.pixelsWide == rendered.pixelsWide,
              expected.pixelsHigh == rendered.pixelsHigh
        else {
            // For a self-sizing view this is the layout assertion, not a housekeeping check:
            // the window got taller or narrower than the reference says it should be.
            Issue.record(
                """
                \(name): size changed — \
                expected \(expected.pixelsWide)x\(expected.pixelsHigh), \
                got \(rendered.pixelsWide)x\(rendered.pixelsHigh)
                """,
                sourceLocation: sourceLocation
            )
            return
        }

        let difference = differingFraction(expected, rendered)
        if difference > tolerance {
            let failure = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(name).failed.png")
            try? png.write(to: failure)
            Issue.record(
                """
                \(name): \(String(format: "%.2f%%", difference * 100)) of pixels changed \
                (tolerance \(String(format: "%.2f%%", tolerance * 100))).
                Reference: \(reference.path)
                Actual:    \(failure.path)
                """,
                sourceLocation: sourceLocation
            )
        }
    }

    /// Fraction of pixels where any channel moved by more than `channelThreshold`.
    private static func differingFraction(
        _ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep
    ) -> Double {
        guard let a = canonical(lhs), let b = canonical(rhs),
              let left = a.bitmapData, let right = b.bitmapData
        else {
            return slowDifferingFraction(lhs, rhs)
        }

        let cutoff = UInt8(channelThreshold * 255)
        let width = a.pixelsWide
        let rowBytes = a.bytesPerRow
        var changed = 0

        for y in 0..<a.pixelsHigh {
            var l = left + y * rowBytes
            var r = right + y * rowBytes
            for _ in 0..<width {
                var moved = false
                for channel in 0..<4 where !moved {
                    let delta = l[channel] > r[channel]
                        ? l[channel] - r[channel]
                        : r[channel] - l[channel]
                    if delta > cutoff { moved = true }
                }
                if moved { changed += 1 }
                l += 4
                r += 4
            }
        }
        return Double(changed) / Double(a.pixelsWide * a.pixelsHigh)
    }

    /// Redraws into one known layout — 8-bit RGBA, non-planar, device RGB — so the comparison can
    /// walk bytes instead of allocating two colour-converted `NSColor`s per pixel.
    ///
    /// Worth the twenty lines: the window snapshots are 528x744, five times the area of the
    /// component ones and a dozen of them, and the per-pixel `NSColor` path turned the suite from
    /// seconds into a wait. It also stops the comparison assuming anything about the layout
    /// `ImageRenderer` happens to hand back.
    private static func canonical(_ rep: NSBitmapImageRep) -> NSBitmapImageRep? {
        guard let canvas = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: rep.pixelsWide,
            pixelsHigh: rep.pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: rep.pixelsWide * 4,
            bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: canvas) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // The bitmap context is one point per pixel, so this is a straight copy, not a resample.
        _ = rep.draw(in: NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return canvas
    }

    /// Fallback for the day `canonical` cannot allocate its canvas. Same answer, slowly.
    private static func slowDifferingFraction(
        _ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep
    ) -> Double {
        var changed = 0
        var counted = 0

        for y in 0..<lhs.pixelsHigh {
            for x in 0..<lhs.pixelsWide {
                guard let a = lhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let b = rhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                else { continue }
                counted += 1
                let delta = max(
                    abs(a.redComponent - b.redComponent),
                    abs(a.greenComponent - b.greenComponent),
                    abs(a.blueComponent - b.blueComponent),
                    abs(a.alphaComponent - b.alphaComponent)
                )
                if delta > channelThreshold { changed += 1 }
            }
        }
        return counted == 0 ? 0 : Double(changed) / Double(counted)
    }
}
