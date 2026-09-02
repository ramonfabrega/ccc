import Foundation

/// Where the harness is and how ccc invokes it. ccc reads the roster, spawns
/// (v5), and attaches — nothing else (CLAUDE.md hard constraints). Every
/// invocation is the documented `claude` command; no daemon files are read.
///
/// One of these per `Host`. A remote host is the *same* argv behind one
/// `ssh` prefix, built in `argv(_:tty:)` and nowhere else — so what the poll
/// runs, what the PTY execs, and what the roster's context menu offers to
/// copy are the same command by construction.
public struct ClaudeCLI: Sendable {
    /// Path of the `claude` executable — ours for `local`, the far side's
    /// for a remote host (never resolved here: it is the remote shell's `~`
    /// to expand).
    public var executable: String
    public var host: Host

    public init(executable: String, host: Host = .local) {
        self.executable = executable
        self.host = host
    }

    /// Resolve `claude` the way a shell would (PATH), then the launcher's
    /// default location. A GUI app launched by LaunchServices has a minimal
    /// PATH, so the fallback matters.
    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) -> ClaudeCLI? {
        if let override = environment["CCC_CLAUDE"], !override.isEmpty {
            return ClaudeCLI(executable: override)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates: [String] = []
        for dir in (environment["PATH"] ?? "").split(separator: ":") {
            candidates.append("\(dir)/claude")
        }
        candidates += ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return ClaudeCLI(executable: path)
        }
        return nil
    }

    /// The CLI for one host: this Mac's resolved `claude` for `local`, the
    /// host's configured path otherwise. `nil` when the local `claude` is
    /// missing, or the host is unusable (`Host.validate`).
    public static func of(_ host: Host,
                          environment: [String: String] = ProcessInfo.processInfo.environment) -> ClaudeCLI? {
        guard host.validate() == nil else { return nil }
        guard let ssh = host.ssh, !ssh.isEmpty else {
            guard var local = locate(environment: environment) else { return nil }
            local.host = host
            return local
        }
        guard let claude = host.claude else { return nil }
        return ClaudeCLI(executable: claude, host: host)
    }

    // MARK: the one prefix

    /// Absolute, for the same reason `locate` has fallbacks: a GUI app
    /// launched by LaunchServices cannot count on PATH, and the PTY execs
    /// argv[0] with `execvp`.
    static let sshExecutable = "/usr/bin/ssh"

    /// One multiplexed connection per host (CLAUDE.md). The master is set up
    /// by whichever invocation gets there first; the rest ride it, so only
    /// the first of a 2 s poll pays a TCP + auth handshake. `ControlPersist`
    /// keeps it warm across polls, and well past the interval so a run of
    /// failures does not re-handshake every tick.
    public static var sshControlDirectory: String {
        if let override = ProcessInfo.processInfo.environment["CCC_SSH_CONTROL_DIR"], !override.isEmpty { return override }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "ccc/ssh").path
    }

    /// A unix socket path is capped near 104 bytes (`sockaddr_un`), and ssh
    /// builds the master socket from this path — so it is the host *name*,
    /// which we control the length of, never the ssh destination.
    public var sshControlPath: String { "\(Self.sshControlDirectory)/\(host.name).sock" }

    public func prepareControlDirectory() throws {
        guard !host.isLocal else { return }
        try FileManager.default.createDirectory(atPath: Self.sshControlDirectory,
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    /// `arguments` as ccc would run them on `host`. Local: the executable
    /// and its arguments. Remote: `ssh [-t] <dest> <claude> <arguments>` —
    /// the remote words unquoted, so the remote login shell expands a
    /// leading `~` (`Host.validate` is what keeps that safe).
    ///
    /// `tty` asks ssh for a PTY (`-t`). Attach needs one; the roster poll
    /// must not have one, or `claude agents --json` would negotiate a
    /// terminal and its output would stop being a clean pipe.
    public func argv(_ arguments: [String], tty: Bool) -> [String] {
        guard let destination = host.ssh else { return [executable] + arguments }
        return sshPrefix(tty: tty, destination: destination) + [executable] + arguments
    }

    func sshPrefix(tty: Bool, destination: String) -> [String] {
        var out = [Self.sshExecutable]
        if tty { out.append("-t") }
        out += [
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(sshControlPath)",
            "-o", "ControlPersist=60",
            // The poll must fail fast and visibly rather than hang a tick.
            "-o", "ConnectTimeout=5",
            "-o", "BatchMode=yes",
            destination,
        ]
        return out
    }

    public func agentsArgv(all: Bool = true) -> [String] {
        argv(all ? ["agents", "--json", "--all"] : ["agents", "--json"], tty: false)
    }

    /// Which reader answers this host's roster.
    public enum RosterSource: String, Sendable {
        /// `claude agents --json --all` — the harness, decoded here. Always
        /// available; the model column stays blank on a remote host because
        /// the transcript it joins against is on the other machine.
        case claude
        /// `ccc list --json` on the far side — our own twin, which does the
        /// transcript join where the filesystem is and hands back finished
        /// rows. One round trip, models included.
        case ccc
    }

    public var rosterSource: RosterSource {
        // Local always reads the harness directly: shelling out to ourselves
        // would spawn a second process to do what this one already does.
        (!host.isLocal && host.ccc != nil) ? .ccc : .claude
    }

    /// The argv that produces this host's roster, whichever reader that is.
    public func rosterArgv() -> [String] {
        guard rosterSource == .ccc, let ccc = host.ccc else { return agentsArgv() }
        guard let destination = host.ssh else { return [ccc, "list", "--json"] }
        return sshPrefix(tty: false, destination: destination) + [ccc, "list", "--json"]
    }

    /// The argv for attaching. The PTY execs this.
    public func attachArgv(id: String) -> [String] {
        argv(["attach", id], tty: true)
    }

    /// The same command as a line a human can paste into a terminal — what
    /// the roster's "copy attach command" offers. One definition, two
    /// surfaces (CLAUDE.md's parity rule).
    public func attachCommandLine(id: String) -> String {
        attachArgv(id: id).map { $0.contains(where: \.isWhitespace) ? "'\($0)'" : $0 }.joined(separator: " ")
    }

    // MARK: running

    /// `claude agents --json --all` on this host, raw bytes. Throws on a
    /// non-zero exit with stderr in the error; decoding is the caller's job.
    public func agentsJSON(all: Bool = true) async throws -> Data {
        try prepareControlDirectory()
        return try await run(agentsArgv(all: all))
    }

    /// A roster read: the bytes, plus whatever the reader warned about
    /// without failing.
    public struct RosterReading: Sendable {
        public var data: Data
        /// The far side had rows AND something to say about their shape.
        public var warning: String?
    }

    /// This host's roster, from whichever reader `rosterSource` names. The
    /// bytes differ by source — harness sessions, or finished `SessionRow`s
    /// — so the caller decodes on the same enum.
    ///
    /// `ccc list` exits **3** when the roster decoded but its shape changed:
    /// the rows are good and a banner is owed. Treating that as a failure
    /// would throw away a whole host's sessions over a warning — the exact
    /// "never an empty list" rule this project holds — so 3 is a reading
    /// with a warning, not an error.
    public func rosterJSON() async throws -> RosterReading {
        try prepareControlDirectory()
        let accepted: Set<Int32> = rosterSource == .ccc ? [0, 3] : [0]
        let result = try await run(rosterArgv(), accepting: accepted)
        guard result.status != 0 else { return RosterReading(data: result.stdout, warning: nil) }
        let said = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return RosterReading(data: result.stdout,
                             warning: said.isEmpty ? "\(host.name): the remote ccc reported a roster shape change" : said)
    }

    public struct RunError: Error, CustomStringConvertible {
        public var status: Int32
        public var stderr: String
        public var host: String
        /// ssh's own failures exit 255 and say nothing about `claude`; naming
        /// the hop is the difference between "the Mac is asleep" and "the
        /// harness is broken".
        public var description: String {
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if status == 255 { return "ssh to \(host) failed: \(detail.isEmpty ? "no route or auth refused" : detail)" }
            let where_ = host == Host.localName ? "" : " on \(host)"
            return "claude\(where_) exited \(status): \(detail)"
        }
    }

    private func run(_ argv: [String]) async throws -> Data {
        try await run(argv, accepting: [0]).stdout
    }

    private func run(_ argv: [String],
                     accepting accepted: Set<Int32>) async throws -> (stdout: Data, stderr: String, status: Int32) {
        let process = Process()
        process.executableURL = URL(filePath: argv[0])
        process.arguments = Array(argv.dropFirst())
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()
        // Read both pipes to EOF before waiting, or a full pipe deadlocks.
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: stderr, as: UTF8.self)
        guard accepted.contains(process.terminationStatus) else {
            throw RunError(status: process.terminationStatus, stderr: text, host: host.name)
        }
        return (stdout, text, process.terminationStatus)
    }
}
