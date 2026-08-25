import AppKit
import CasinoKit
import SwiftUI

struct DesignerView: View {
    @State private var config = IconConfig()
    @State private var status = ""
    @State private var busy = false

    /// Written next to the package so `make_app.sh` can pick the icon up.
    private let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Icon")

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            preview
            controls
        }
        .padding(20)
        .frame(minWidth: 780, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var preview: some View {
        VStack(spacing: 14) {
            IconArtwork(config: config)
                .frame(width: 320, height: 320)
                .shadow(color: .black.opacity(0.4), radius: 14, y: 6)

            // The small sizes are where a busy icon falls apart, so show them honestly.
            HStack(alignment: .bottom, spacing: 14) {
                ForEach([128, 64, 32, 16], id: \.self) { size in
                    VStack(spacing: 4) {
                        IconArtwork(config: config)
                            .frame(width: CGFloat(size), height: CGFloat(size))
                        Text("\(size)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .frame(width: 340)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    group("Rings") {
                        slider("Rings", $config.ringCount, 1...8, format: "%.0f")
                        slider("Per ring", $config.perRing, 1...24, format: "%.0f")
                        slider("Spread", $config.spread, 0.2...1.0)
                        slider("Inner gap", $config.innerGap, 0...0.5)
                        slider("Spacing bias", $config.ringSpacingBias, 0.4...3)
                        slider("Ring twist", $config.ringTwist, 0...1)
                    }
                    group("Irregularity") {
                        slider("Angle jitter", $config.angleJitter, 0...1)
                        slider("Radius jitter", $config.radiusJitter, 0...1)
                        slider("Max rotation", $config.maxRotation, 0...180, format: "%.0f°")
                    }
                    group("Satellites") {
                        slider("Size", $config.satelliteSize, 0.02...0.3)
                        slider("Size falloff", $config.sizeFalloff, 0...1)
                        slider("Fade falloff", $config.fadeFalloff, 0...1)
                    }
                    group("Centre") {
                        slider("Diamond size", $config.diamondSize, 0.1...0.7)
                        slider("Glow radius", $config.glowRadius, 0...0.6)
                        slider("Glow strength", $config.glowStrength, 0...1)
                    }
                    group("Frame") {
                        slider("Corner radius", $config.cornerRadius, 0...0.5)
                        slider("Seed", $config.seed, 0...200, format: "%.0f")
                    }
                }
                .padding(.trailing, 6)
            }

            Divider().padding(.vertical, 12)

            HStack(spacing: 10) {
                Button("Reset") { config = IconConfig() }
                Button("Shuffle") { config.seed = (config.seed + 1).truncatingRemainder(dividingBy: 200) }
                Spacer()
                Button(busy ? "Rendering…" : "Render icon") { render() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy)
            }

            if !status.isEmpty {
                Text(status)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 8)
            }
        }
        .frame(minWidth: 360)
    }

    private func group(
        _ title: String, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(.bottom, 6)
    }

    private func slider(
        _ label: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        format: String = "%.2f"
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .frame(width: 96, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
        }
    }

    private func render() {
        busy = true
        status = ""
        Task {
            do {
                status = try await IconExport.write(config, to: outputDirectory)
            } catch {
                status = "Failed: \(error)"
            }
            busy = false
        }
    }
}
