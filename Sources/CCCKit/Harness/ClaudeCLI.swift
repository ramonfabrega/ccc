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
    ///
    /// Under `~/Library/Caches`, not Application Support: `-o ControlPath=`
    /// is parsed like a config line, so a path with a space
    /// ("Application Support") fails with "extra arguments at end of line"
    /// — found 2026-09-02, the day the default path was first used without
    /// `CCC_SSH_CONTROL_DIR` set. Sockets are ephemeral, which is what
    /// Caches is for.
    public static var sshControlDirectory: String {
        if let override = ProcessInfo.processInfo.environment["CCC_SSH_CONTROL_DIR"], !override.isEmpty { return override }
        return FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
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

    /// Unlink this host's master socket, so the next ssh makes a fresh
    /// master instead of retrying a wedged one (docs/DESIGN.md §4b: ssh
    /// itself never evicts it). The orphaned master, if any, exits on its
    /// own once `ControlPersist` runs out. `false` when there was nothing
    /// to evict — a local host, or no socket.
    @discardableResult
    public func evictControlMaster() -> Bool {
        guard !host.isLocal else { return false }
        return unlink(sshControlPath) == 0
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
    ///
    /// `--host local` is not optional: `ccc list` spans every host it
    /// knows, and the far side may well list *us*. Without it, air asking
    /// studio would have studio ask air, which asks studio…
    public func rosterArgv() -> [String] {
        guard rosterSource == .ccc, let ccc = host.ccc else { return agentsArgv() }
        let words = [ccc, "list", "--json", "--host", Host.localName]
        guard let destination = host.ssh else { return words }
        return sshPrefix(tty: false, destination: destination) + words
    }

    /// The far side's home directory, by asking its login shell to expand
    /// `~` — the same expansion every remote path here relies on. This is
    /// what makes `~/code` mean the right thing on a host whose username
    /// differs (air is `rf-air`, studio is `rf-studio`). Local answers
    /// without a process.
    /// What one ssh can learn about a host before it is configured: its
    /// home, and where `claude` and `ccc` actually are. Asked rather than
    /// assumed, because two conventions collided on the first real host —
    /// `claude`'s installer uses `~/.local/bin`, ccc's own install script
    /// prefers Homebrew's bin — and a default that guesses one of them is
    /// wrong for the other. The candidate order is each installer's.
    public struct Probe: Sendable, Equatable {
        public var home: String
        public var claude: String?
        public var ccc: String?

        public static let claudeCandidates = ["~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        public static let cccCandidates = ["/opt/homebrew/bin/ccc", "/usr/local/bin/ccc", "~/.local/bin/ccc"]

        /// The remote words. Sent unquoted, one word per argv element, so
        /// the remote login shell expands every `~` (the same rule as every
        /// other remote path here).
        static var words: [String] {
            // `~` as its own word: a shell does not expand it after `=`
            // (`home=~` prints literally — measured), so the value arrives
            // with a leading space the parser trims.
            var out = ["echo", "home=", "~", ";"]
            for (label, candidates) in [("claude", claudeCandidates), ("ccc", cccCandidates)] {
                out += ["for", "p", "in"] + candidates + [";", "do", "test", "-x", "$p", "&&", "echo", "\(label)=$p", "&&", "break", ";", "done", ";"]
            }
            return out
        }

        /// `home=/Users/x`, `claude=/…`, `ccc=/…` lines, in any order; a
        /// binary that was not found simply has no line.
        public static func parse(_ text: String) -> Probe? {
            var home: String?, claude: String?, ccc: String?
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, parts[1].hasPrefix("/") else { continue }
                switch parts[0] {
                case "home": home = parts[1]
                case "claude": claude = parts[1]
                case "ccc": ccc = parts[1]
                default: break
                }
            }
            guard let home else { return nil }
            return Probe(home: home, claude: claude, ccc: ccc)
        }
    }

    /// Run the probe on this host. Local answers from the filesystem.
    public func probe() async throws -> Probe {
        guard let destination = host.ssh else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            func first(_ candidates: [String]) -> String? {
                candidates.map { $0.replacingOccurrences(of: "~", with: home) }
                    .first { FileManager.default.isExecutableFile(atPath: $0) }
            }
            return Probe(home: home, claude: first(Probe.claudeCandidates), ccc: first(Probe.cccCandidates))
        }
        try prepareControlDirectory()
        let out = try await run(sshPrefix(tty: false, destination: destination) + Probe.words)
        guard let probe = Probe.parse(String(decoding: out, as: UTF8.self)) else {
            throw RunError(status: 0, stderr: "the probe on \(host.name) answered nothing usable", host: host.name)
        }
        return probe
    }

    public func home() async throws -> String {
        guard let destination = host.ssh else {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        try prepareControlDirectory()
        let out = try await run(sshPrefix(tty: false, destination: destination) + ["echo", "~"])
        let path = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/") else {
            throw RunError(status: 0, stderr: "`echo ~` on \(host.name) answered '\(path)', not a path", host: host.name)
        }
        return path
    }

    /// The argv for attaching. The PTY execs this.
    public func attachArgv(id: String) -> [String] {
        argv(["attach", id], tty: true)
    }

    /// `claude rm <id>` on this host: delete the session and its worktree
    /// when the harness judges that safe. The guard is the harness's, not
    /// ours (docs/HARNESS.md): a dirty or unpushed worktree is kept and
    /// the session stays, exit 1 with the reason. ccc passes the words
    /// through — the agents view's Delete is this same check.
    public func rmArgv(id: String) -> [String] {
        argv(["rm", id], tty: false)
    }

    public struct RmResult: Sendable {
        public var removed: Bool
        /// What the harness said, stdout and stderr in the order they came.
        public var said: String
    }

    public func rm(id: String) async throws -> RmResult {
        try prepareControlDirectory()
        let result = try await run(rmArgv(id: id), accepting: [0, 1], program: "claude")
        let said = (String(decoding: result.stdout, as: UTF8.self) + result.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return RmResult(removed: result.status == 0, said: said)
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
        let result = try await run(rosterArgv(), accepting: accepted, program: rosterSource == .ccc ? "ccc" : "claude")
        guard result.status != 0 else { return RosterReading(data: result.stdout, warning: nil) }
        let said = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return RosterReading(data: result.stdout,
                             warning: said.isEmpty ? "\(host.name): the remote ccc reported a roster shape change" : said)
    }

    public struct RunError: Error, CustomStringConvertible {
        public var status: Int32
        public var stderr: String
        public var host: String
        /// What was run on the far side — `claude`, or `ccc` for the roster
        /// twin — so "exited 127" names the missing binary.
        public var program: String = "claude"
        /// ssh's own failures exit 255 and say nothing about `claude`; naming
        /// the hop is the difference between "the Mac is asleep" and "the
        /// harness is broken".
        public var description: String {
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if status == 255 { return "ssh to \(host) failed: \(detail.isEmpty ? "no route or auth refused" : detail)" }
            let where_ = host == Host.localName ? "" : " on \(host)"
            let hint = status == 127 && program == "ccc" ? " (`ccc hosts add \(host) --ccc <path>` fixes the path, `--no-ccc` reads the harness instead)" : ""
            return "\(program)\(where_) exited \(status): \(detail)\(hint)"
        }
    }

    /// The far side's `ccc version --json` — which build answers this
    /// host's roster. `nil` when the host reads through the harness (no
    /// `ccc` there). Rides the same master as the poll, so on a warm
    /// connection it costs one round trip and no handshake. An older ccc
    /// with no `version` verb exits 2, which the caller reports as "older
    /// than the first build that can say".
    public func cccVersion() async throws -> BuildInfo? {
        guard let ccc = host.ccc else { return nil }
        guard let destination = host.ssh else { return BuildInfo.current }
        try prepareControlDirectory()
        let out = try await run(sshPrefix(tty: false, destination: destination) + [ccc, "version", "--json"], program: "ccc")
        do {
            return try JSONDecoder().decode(BuildInfo.self, from: out)
        } catch {
            throw RunError(status: 0, stderr: "`ccc version --json` on \(host.name) answered something that is not a build", host: host.name, program: "ccc")
        }
    }

    private func run(_ argv: [String], program: String = "claude") async throws -> Data {
        try await run(argv, accepting: [0], program: program).stdout
    }

    private func run(_ argv: [String],
                     accepting accepted: Set<Int32>,
                     program: String) async throws -> (stdout: Data, stderr: String, status: Int32) {
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
            throw RunError(status: process.terminationStatus, stderr: text, host: host.name, program: program)
        }
        return (stdout, text, process.terminationStatus)
    }
}
