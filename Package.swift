// swift-tools-version: 6.2
import PackageDescription

// ccc — one binary. No arguments → the AppKit app; a subcommand → headless
// CLI over the same code. CCCKit is everything that runs without a window
// and is what the tests link. SwiftTerm is the v0 pane stand-in (pinned to a
// release tag, never main — docs/TERMINAL.md); it leaves with v1.
let package = Package(
    name: "ccc",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0"),
    ],
    targets: [
        .target(
            name: "CCCKit",
            dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")]
        ),
        .executableTarget(
            name: "ccc",
            dependencies: ["CCCKit"]
        ),
        .testTarget(
            name: "CCCKitTests",
            dependencies: ["CCCKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
