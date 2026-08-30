// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Artheme",
    platforms: [.macOS(.v13)],
    targets: [
        // Everything the CLI and the app share: themes, colours, integrations.
        .target(name: "ArthemeKit"),
        // `artheme` — the command line interface, no dependencies at runtime.
        .executableTarget(name: "artheme", dependencies: ["ArthemeKit"]),
        // Artheme.app — the window and the menu bar item.
        .executableTarget(name: "ArthemeApp", dependencies: ["ArthemeKit"]),
        // A plain executable, not a testTarget: XCTest ships with Xcode, not
        // with the Command Line Tools, and the whole point is building with
        // only the latter. Run it with `swift run ArthemeTests`.
        .executableTarget(name: "ArthemeTests", dependencies: ["ArthemeKit"]),
    ]
)
