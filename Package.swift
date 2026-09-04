// swift-tools-version: 6.2
import PackageDescription

// ccc — one binary. No arguments → the AppKit app; a subcommand → headless
// CLI over the same code. CCCKit is everything that runs without a window
// and is what the tests link. SwiftTerm was the v0 pane stand-in (pinned to a
// release tag, never main — docs/TERMINAL.md) and stays as the
// `CCC_CORE=swiftterm` escape hatch behind the libghostty-vt pane
// (docs/CHECKS.md).
let package = Package(
    name: "ccc",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0"),
        // Earned 2026-09-02 (docs/DESIGN.md §6): self-update over the CDN
        // appcast, the fleet's mux/disk release flow. Air cannot be pushed
        // to (no Remote Login), so every update is a pull, and this is the
        // pull. Only the app target links it; CCCKit and the tests never do.
        //
        // Sparkle now arrives THROUGH ota (§6 amendment, 2026-09-02): the
        // release flow ccc hand-copied from disk, plus the app-side half
        // this repo wrote and ota extracted. Pinned to an exact tag, moved
        // deliberately (2026-09-02: 45f3a63 → v0.1.0, which adds "refuse
        // to release an installed app" — ccc releases from .build/dist, so
        // nothing changes) — the same policy vendor/ghostty is held to.
        .package(url: "https://github.com/ramonfabrega/ota", exact: "0.1.0"),
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
                // BuildInfo and CLIInstall, which ota extracted from this
                // repo. Zero dependencies by design — no Sparkle behind the
                // library every test links.
                .product(name: "OTA", package: "ota"),
            ]
        ),
        .executableTarget(
            name: "ccc",
            // OTAUpdater is the Sparkle half, and it stops here: the app
            // target is the only one that embeds Sparkle.framework and the
            // only one that carries the rpath below.
            dependencies: ["CCCKit", .product(name: "OTAUpdater", package: "ota")],
            linkerSettings: [
                // The bundle embeds Sparkle.framework in Contents/Frameworks;
                // the bare SwiftPM binary needs the matching rpath baked in.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "CCCKitTests",
            dependencies: ["CCCKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
