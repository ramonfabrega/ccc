import Foundation

/// Which ccc this is. Version and build come from the bundle's Info.plist
/// (`scripts/make-bundle`: `VERSION`, and the git commit count), so the
/// answer is the same one Sparkle compares — and skew between two Macs, or
/// between the command on PATH and the app holding the socket, is a number
/// rather than a "malformed request".
///
/// A bare `.build/debug/ccc` has no plist and says so: it is the dev lane,
/// never a release, and nothing should mistake it for one.
public struct BuildInfo: Codable, Sendable, Equatable {
    /// `CFBundleShortVersionString` — `0.1.4`. `nil` outside a bundle.
    public var version: String?
    /// `CFBundleVersion` — the commit count, monotonic. `nil` outside a bundle.
    public var build: Int?
    /// The `.app` this executable lives in, when it does.
    public var bundlePath: String?
    /// The executable itself, symlinks resolved — what `install-cli` links to.
    public var executablePath: String

    public init(version: String?, build: Int?, bundlePath: String?, executablePath: String) {
        self.version = version
        self.build = build
        self.bundlePath = bundlePath
        self.executablePath = executablePath
    }

    public var isBundled: Bool { bundlePath != nil && version != nil }

    /// `0.1.4 (53)`, or `dev` for a bare binary.
    public var short: String {
        guard let version else { return "dev" }
        return build.map { "\(version) (\($0))" } ?? version
    }

    /// The `ccc version` line.
    public var description: String {
        isBundled ? "ccc \(short)  \(bundlePath ?? "")" : "ccc dev build (not a bundle: \(executablePath))"
    }

    /// This process. The executable is resolved through its symlinks first
    /// — the command on PATH *is* a symlink into the bundle — and the
    /// bundle is the nearest `.app` above it, read directly rather than
    /// trusted to `Bundle.main`, which a symlinked CLI launch can confuse.
    public static let current: BuildInfo = {
        let executable = (Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0]))
            .resolvingSymlinksInPath()
        return BuildInfo(executable: executable)
    }()

    public init(executable: URL) {
        executablePath = executable.path
        var dir = executable.deletingLastPathComponent()
        while dir.path != "/" {
            if dir.pathExtension == "app",
               let bundle = Bundle(url: dir),
               let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                self.version = version
                self.build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap { Int($0) }
                self.bundlePath = dir.path
                return
            }
            dir = dir.deletingLastPathComponent()
        }
    }
}

/// `ccc` on PATH: a symlink into the installed bundle (VS Code's pattern,
/// the same one `scripts/install` makes), so the command and the app are
/// always the same build and a Sparkle update — which replaces the bundle
/// at the same path — carries the link along. Offered by the app on first
/// launch when no command is found; `ccc install-cli` is its twin.
public enum CLIInstall {
    /// Where the link goes, in preference order: the first that exists and
    /// is writable wins, and `~/.local/bin` is created if nothing else is —
    /// it is where `claude`'s own installer puts things, so it is on PATH
    /// already on any Mac that runs the harness. `ClaudeCLI.Probe` looks in
    /// the same three places on a remote host, which is what makes a fresh
    /// install there findable by `ccc hosts add`.
    public static let candidateDirectories = ["/opt/homebrew/bin", "/usr/local/bin", "~/.local/bin"]

    public enum Status: Equatable, Sendable {
        /// A `ccc` that resolves to this executable.
        case installed(path: String)
        /// A symlink named `ccc` whose target is gone — an app that moved
        /// or was deleted. Ours to relink.
        case dangling(path: String, target: String)
        /// A `ccc` that is something else: another bundle's link, a dev
        /// build, a real file. The user's; reported, never replaced quietly.
        case foreign(path: String, target: String?)
        case missing

        public var path: String? {
            switch self {
            case .installed(let p), .dangling(let p, _), .foreign(let p, _): return p
            case .missing: return nil
            }
        }
    }

    static func expand(_ dir: String, home: String) -> String {
        dir.hasPrefix("~/") ? home + dir.dropFirst(1) : dir
    }

    /// The first `ccc` found in `directories` (then every PATH entry, so a
    /// command somewhere unusual still counts), judged against `executable`.
    public static func status(executable: String = BuildInfo.current.executablePath,
                              directories: [String] = candidateDirectories,
                              path: String? = ProcessInfo.processInfo.environment["PATH"],
                              home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> Status {
        let fm = FileManager.default
        let dirs = directories + (path ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        for dir in dirs.map({ expand($0, home: home) }) where seen.insert(dir).inserted {
            let link = dir + "/ccc"
            guard fm.fileExists(atPath: link) || (try? fm.destinationOfSymbolicLink(atPath: link)) != nil else { continue }
            let target = try? fm.destinationOfSymbolicLink(atPath: link)
            let resolved = URL(filePath: link).resolvingSymlinksInPath().path
            if resolved == URL(filePath: executable).resolvingSymlinksInPath().path { return .installed(path: link) }
            if let target, !fm.fileExists(atPath: resolved) { return .dangling(path: link, target: target) }
            return .foreign(path: link, target: target)
        }
        return .missing
    }

    public struct Result: Equatable, Sendable {
        public var path: String
        public var replaced: String?
        /// `~/.local/bin` had to be created; it may not be on PATH yet.
        public var createdDirectory: Bool
        public var description: String {
            var out = "ccc → \(path)"
            if let replaced { out += " (was \(replaced))" }
            if createdDirectory { out += "; created \(URL(filePath: path).deletingLastPathComponent().path) — add it to PATH if it is not" }
            return out
        }
    }

    public struct InstallError: Error, CustomStringConvertible {
        public var description: String
    }

    /// Link `ccc` to `executable`. A symlink already there is relinked (its
    /// old target reported); a regular file is refused unless `force`. With
    /// no `directory`, the first writable candidate is used, and
    /// `~/.local/bin` is created when none is.
    @discardableResult
    public static func install(executable: String = BuildInfo.current.executablePath,
                               directory: String? = nil,
                               directories: [String] = candidateDirectories,
                               force: Bool = false,
                               home: String = FileManager.default.homeDirectoryForCurrentUser.path) throws -> Result {
        let fm = FileManager.default
        var created = false
        let dir: String
        if let directory {
            dir = expand(directory, home: home)
            guard fm.fileExists(atPath: dir) else { throw InstallError(description: "\(dir) does not exist") }
        } else {
            let expanded = directories.map { expand($0, home: home) }
            if let writable = expanded.first(where: { fm.isWritableFile(atPath: $0) && (try? fm.contentsOfDirectory(atPath: $0)) != nil }) {
                dir = writable
            } else if let last = expanded.last {
                try fm.createDirectory(atPath: last, withIntermediateDirectories: true)
                dir = last
                created = true
            } else {
                throw InstallError(description: "no directory to install into")
            }
        }
        let link = dir + "/ccc"
        var replaced: String?
        if let existing = try? fm.destinationOfSymbolicLink(atPath: link) {
            if existing == executable { return Result(path: link, replaced: nil, createdDirectory: created) }
            replaced = existing
            try fm.removeItem(atPath: link)
        } else if fm.fileExists(atPath: link) {
            guard force else {
                throw InstallError(description: "\(link) exists and is not a symlink; pass --force to replace it")
            }
            replaced = link
            try fm.removeItem(atPath: link)
        }
        do {
            try fm.createSymbolicLink(atPath: link, withDestinationPath: executable)
        } catch {
            throw InstallError(description: "could not link \(link): \(error.localizedDescription)")
        }
        return Result(path: link, replaced: replaced, createdDirectory: created)
    }
}
