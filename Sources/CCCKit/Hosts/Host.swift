import Foundation

/// A machine ccc can reach. `local` is this Mac and is always present; every
/// other host is the same commands behind one `ssh` prefix (CLAUDE.md: "PTY
/// is always local; remote is the same command behind `ssh -t`"). No daemon
/// of ours runs on the far side — `claude` there is the harness, unmodified.
public struct Host: Codable, Sendable, Equatable, Identifiable {
    /// The address half of a `SessionRef`: what the user types in
    /// `ccc attach studio:a1b2`. Unique, and never contains `:`.
    public var name: String
    /// The ssh destination (`studio`, `ramon@air.tailnet.ts.net`, an
    /// `~/.ssh/config` alias). `nil` means this host is us.
    public var ssh: String?
    /// Absolute path of `claude` on the far side. Required for a remote host
    /// and measured, not assumed: experiment 3 (docs/HARNESS.md) found that a
    /// non-interactive ssh has no `claude` on PATH, so the bare name fails
    /// with `command not found` and the roster looks like an outage. Left
    /// unexpanded — `~/.local/bin/claude` is expanded by the *remote* login
    /// shell, which is why `validate` rejects anything that would need quotes.
    public var claude: String?

    public var id: String { name }
    public var isLocal: Bool { ssh == nil }

    public init(name: String, ssh: String? = nil, claude: String? = nil) {
        self.name = name
        self.ssh = ssh
        self.claude = claude
    }

    public static let localName = "local"
    public static let local = Host(name: localName)

    /// Why a host cannot be used, as the sentence to show. Checked when a
    /// host is added and again when the config is loaded, so a hand-edited
    /// file fails with the same words as `ccc hosts add`.
    public func validate() -> String? {
        if name.isEmpty { return "a host needs a name" }
        if name.contains(":") { return "host name '\(name)' contains ':', which separates host from id in `host:id`" }
        if name.contains(where: \.isWhitespace) { return "host name '\(name)' contains whitespace" }
        if isLocal { return nil }
        guard let claude, !claude.isEmpty else {
            return "host '\(name)' has no claude path; a non-interactive ssh has no claude on PATH (experiment 3)"
        }
        // The remote command words are handed to ssh unquoted so the remote
        // shell expands a leading `~`. That only holds while they cannot be
        // reinterpreted as shell syntax.
        if claude.contains(where: { $0.isWhitespace || "\"'$`;&|<>()".contains($0) }) {
            return "claude path '\(claude)' has whitespace or shell characters; ccc passes it to the remote shell unquoted so `~` expands"
        }
        return nil
    }
}

/// The host list: `~/Library/Application Support/ccc/hosts.json`, or
/// `CCC_HOSTS`. Hand-editable on purpose — the JSON file is the twin of the
/// picker, and one line adds a Mac.
public struct HostConfig: Codable, Sendable, Equatable {
    public var hosts: [Host]

    public init(hosts: [Host] = []) {
        self.hosts = hosts
    }

    public static var defaultPath: String {
        if let override = ProcessInfo.processInfo.environment["CCC_HOSTS"], !override.isEmpty { return override }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "ccc/hosts.json").path
    }

    /// What a load produced: the usable hosts, and every reason a host was
    /// dropped. A broken config degrades to "local only" with the reason
    /// shown — never an empty host list and never a crash (the roster's
    /// lenient-decode rule, applied to our own file).
    public struct Loaded: Sendable, Equatable {
        public var config: HostConfig
        public var issues: [String]
        public init(config: HostConfig, issues: [String] = []) {
            self.config = config
            self.issues = issues
        }
    }

    public static func load(path: String = defaultPath) -> Loaded {
        guard let data = FileManager.default.contents(atPath: path) else {
            return Loaded(config: HostConfig(hosts: [.local]))
        }
        let decoded: [Host]
        do {
            decoded = try JSONDecoder().decode(HostConfig.self, from: data).hosts
        } catch {
            return Loaded(config: HostConfig(hosts: [.local]),
                          issues: ["\(path): \(error.localizedDescription); using local only"])
        }
        var issues: [String] = []
        var seen = Set<String>()
        var kept: [Host] = []
        for host in decoded {
            if let problem = host.validate() { issues.append(problem); continue }
            guard seen.insert(host.name).inserted else {
                issues.append("duplicate host '\(host.name)'; keeping the first")
                continue
            }
            kept.append(host)
        }
        // `local` is not optional: it is this Mac, and dropping it would hide
        // every session the app can actually attach to.
        if !seen.contains(Host.localName) { kept.insert(.local, at: 0) }
        return Loaded(config: HostConfig(hosts: kept), issues: issues)
    }

    public func save(path: String = defaultPath) throws {
        let url = URL(filePath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public func host(named name: String) -> Host? {
        hosts.first { $0.name == name }
    }
}
