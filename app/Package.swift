// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Omakase",
    platforms: [.macOS(.v13)],
    targets: [
        // Everything the CLI and the app share: themes, colours, integrations.
        .target(name: "OmakaseKit"),
        // `omakase` — the command line interface, no dependencies at runtime.
        .executableTarget(name: "omakase", dependencies: ["OmakaseKit"]),
        // Omakase.app — the window and the menu bar item.
        .executableTarget(name: "OmakaseApp", dependencies: ["OmakaseKit"]),
        // A plain executable, not a testTarget: XCTest ships with Xcode, not
        // with the Command Line Tools, and the whole point is building with
        // only the latter. Run it with `swift run OmakaseTests`.
        .executableTarget(name: "OmakaseTests", dependencies: ["OmakaseKit"]),
    ]
)
