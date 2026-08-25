// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesktopCasino",
    platforms: [.macOS(.v14)],
    targets: [
        // Shared by the widget and the icon designer: reel symbols, palette, symbol rendering.
        .target(
            name: "CasinoKit",
            path: "Sources/CasinoKit"
        ),
        .executableTarget(
            name: "DesktopCasino",
            dependencies: ["CasinoKit"],
            path: "Sources/DesktopCasino"
        ),
        .executableTarget(
            name: "IconDesigner",
            dependencies: ["CasinoKit"],
            path: "Sources/IconDesigner"
        ),
        .testTarget(
            name: "CasinoKitTests",
            dependencies: ["CasinoKit"],
            path: "Tests/CasinoKitTests"
        ),
    ]
)
