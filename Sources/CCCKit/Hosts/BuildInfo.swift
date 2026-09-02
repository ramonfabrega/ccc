import Foundation
import OTA

// Which ccc this is, and `ccc` on PATH — both now live in `ota`'s `OTA`
// product, which was extracted from THIS file on 2026-09-02 (docs/DESIGN.md
// §6). What stays here is the only ccc-specific part: the name, said once.
//
// `OTA` has no dependencies, deliberately, so CCCKit can import it without
// Sparkle coming along. The updater — the half that does need Sparkle — is
// `OTAUpdater`, and only the `ccc` executable target links it. CCCKit is
// what every test links, and `swift test` still resolves no Sparkle.

// The dependency's surface in ccc, written down rather than re-exported
// wholesale: these two names are all of `OTA` that ccc uses. Aliasing them
// here is what keeps every existing `BuildInfo` reference compiling, and the
// `ccc` target reaches both through CCCKit.
public typealias BuildInfo = OTA.BuildInfo
public typealias CLIInstall = OTA.CLIInstall

/// The one place ccc names itself to `ota`. Everything user-facing
/// (`ccc version`, the status item, the window title) derives from it.
public let cccName = "ccc"

/// Cached: the bundle walk runs once per process, as it did when this
/// struct lived here.
private let currentBuild = BuildInfo.current(name: cccName)

extension BuildInfo {
    /// This process. The executable is resolved through its symlinks — the
    /// command on PATH IS a symlink into the bundle — and the bundle is the
    /// nearest `.app` above it, so the command answers for the app.
    public static var current: BuildInfo { currentBuild }
}

extension CLIInstall {
    /// `ccc` on PATH, a symlink into the installed bundle.
    public static let ccc = CLIInstall(command: cccName)
}

extension JSONDecoder {
    /// For any payload carrying a `BuildInfo`: a peer older than ccc v0.1.6
    /// sends no `name`, and the reader is what knows which command it ran.
    /// Use this, never a bare `JSONDecoder()`, or a remote row renders an
    /// empty name with nothing to say why.
    public static var ccc: JSONDecoder { .naming(cccName) }
}
