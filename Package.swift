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
        // libghostty-vt, built from vendor/ghostty by scripts/build-vt (Zig is
        // the build step and nothing else). Run that once after clone; the
        // xcframework is gitignored build output.
        .binaryTarget(
            name: "GhosttyVt",
            path: "vendor/ghostty/zig-out/lib/ghostty-vt.xcframework"
        ),
        .target(
            name: "CCCKit",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                "GhosttyVt",
            ]
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
