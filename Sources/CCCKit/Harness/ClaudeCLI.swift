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
        /// What the harness said, stdout and stderr in the order they came,
        /// with the cleanup's own sentence appended when there was one.
        public var said: String
        /// Item 24: what became of the worktree **ccc** cut for this
        /// session, if it cut one. Nil is the ordinary answer — a plain
        /// cwd, or a worktree the harness made and therefore removed.
        public var worktree: WorktreeProbe.Cleanup?

        public init(removed: Bool, said: String, worktree: WorktreeProbe.Cleanup? = nil) {
            self.removed = removed
            self.said = said
            self.worktree = worktree
        }
    }

    /// `claude stop <id>` on this host: end a running background session
    /// and keep everything — "Its conversation is kept; resume it later
    /// with `claude attach <id>`", and the worktree is untouched, which is
    /// what separates it from `rm`. It works only on a live session (`rm`
    /// is the one that works on an exited one).
    ///
    /// ccc had no verb for this until 2026-09-06 even though `stopped` has
    /// been a state on every row since v1 — the twin rule biting from the
    /// read side (a state ccc could show and never produce). `ccc spawn
    /// --replace` needs it, and a stop that existed only inside `--replace`
    /// would be the same gap one level down.
    public func stopArgv(id: String) -> [String] {
        argv(["stop", id], tty: false)
    }

    public struct StopResult: Sendable {
        public var stopped: Bool
        /// What the harness said, stdout and stderr in the order they came.
        public var said: String
    }

    public func stop(id: String) async throws -> StopResult {
        try prepareControlDirectory()
        let result = try await run(stopArgv(id: id), accepting: [0, 1], program: "claude")
        let said = (String(decoding: result.stdout, as: UTF8.self) + result.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return StopResult(stopped: result.status == 0, said: said)
    }

    /// Delete a session, and the worktree **ccc** cut for it (item 24).
    ///
    /// `claude rm` deletes the session and the worktree *the harness*
    /// made. When ccc cut the tree itself (`--base`, or `--worktree` from
    /// a folder off the default branch) it handed the harness a plain
    /// cwd, so the daemon never learned there was a worktree at all:
    /// measured 2026-09-06, `ccc rm 0f7b8c26` answered `removed`, exit 0,
    /// and left the tree, the branch and the `ccc-base` record on disk,
    /// with nobody but the user to finish it. Every ccc-cut worktree on
    /// the fleet was in that state.
    ///
    /// So the cwd is read from the roster **before** the session goes —
    /// afterwards there is no row to ask — and the cleanup runs only when
    /// the harness actually removed the session, only on a tree carrying
    /// ccc's own `ccc-cut` record, and only as far as git will go.
    /// Nothing is asked first: `rm` is already the destructive verb, and
    /// leaving half of it undone is the surprise.
    public func rm(id: String, probe: WorktreeProbe = WorktreeProbe()) async throws -> RmResult {
        guard host.isLocal else { return try await remoteRm(id: id) }
        try prepareControlDirectory()
        // Before the session leaves the roster, while its cwd is still
        // something we can ask for.
        let cut = (await localCwd(id: id)).flatMap { WorktreeProbe.cut(at: $0) }
        let result = try await run(rmArgv(id: id), accepting: [0, 1], program: "claude")
        var said = (String(decoding: result.stdout, as: UTF8.self) + result.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0, let cut else {
            return RmResult(removed: result.status == 0, said: said)
        }
        let git = probe.git
        let cleanup = await Task.detached(priority: .userInitiated) {
            WorktreeProbe.removeCut(cut, git: git)
        }.value
        said = said.isEmpty ? cleanup.said : said + "; " + cleanup.said
        return RmResult(removed: true, said: said, worktree: cleanup)
    }

    /// The row's cwd for a local id, or nil when the roster has no such
    /// row. Never fatal: a session ccc cannot find a row for is still a
    /// session `claude rm` may know how to delete.
    private func localCwd(id: String) async -> String? {
        guard let data = try? await agentsJSON() else { return nil }
        return RosterDecoder.decode(data).sessions.first { $0.id == id }?.cwd
    }

    /// A remote `rm` goes through the far side's own `ccc` when it has
    /// one — a ccc-cut worktree only ever exists on the host that cut it
    /// (`prepareWorktree` refuses `--base` for a remote spawn), so its
    /// records, its repository and its git are all over there. The same
    /// shape as `fetch` and `pull`. With no ccc on the far side this is
    /// the passthrough it has always been, and the tree is left as before.
    private func remoteRm(id: String) async throws -> RmResult {
        try prepareControlDirectory()
        guard let ccc = host.ccc, let destination = host.ssh else {
            let result = try await run(rmArgv(id: id), accepting: [0, 1], program: "claude")
            let said = (String(decoding: result.stdout, as: UTF8.self) + result.stderr)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return RmResult(removed: result.status == 0, said: said)
        }
        let argv = sshPrefix(tty: false, destination: destination) + [ccc, "rm", id, "--json"]
        let result = try await run(argv, accepting: [0, 1], program: "ccc")
        let text = String(decoding: result.stdout, as: UTF8.self)
        // The far side's own answer, when it is a ccc new enough to speak
        // it; its plain text otherwise.
        if let data = text.data(using: .utf8),
           let answer = try? JSONDecoder().decode(RemoteRmAnswer.self, from: data) {
            return RmResult(removed: result.status == 0, said: answer.said, worktree: answer.worktree)
        }
        return RmResult(removed: result.status == 0,
                        said: (text + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// `ccc rm --json` as the far side prints it. Lenient like every shape
    /// that crosses the hop: an older ccc sends no `worktree`.
    struct RemoteRmAnswer: Decodable {
        var said: String
        var worktree: WorktreeProbe.Cleanup?
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
            return try BuildInfo.decode(out, naming: cccName)
        } catch {
            throw RunError(status: 0, stderr: "`ccc version --json` on \(host.name) answered something that is not a build", host: host.name, program: "ccc")
        }
    }

    func run(_ argv: [String], program: String = "claude") async throws -> Data {
        try await run(argv, accepting: [0], program: program).stdout
    }

    func run(_ argv: [String],
             accepting accepted: Set<Int32>,
             program: String,
             cwd: String? = nil,
             environment: [String: String]? = nil) async throws -> (stdout: Data, stderr: String, status: Int32) {
        // Nonblocking since item 4: the pipes drain as bytes arrive and the
        // exit is awaited, so a 5 s `ConnectTimeout` against a sleeping Mac
        // suspends this task instead of parking a pool thread.
        let output = try await Subprocess.run(argv, cwd: cwd, environment: environment)
        let text = String(decoding: output.stderr, as: UTF8.self)
        guard accepted.contains(output.status) else {
            throw RunError(status: output.status, stderr: text, host: host.name, program: program)
        }
        return (output.stdout, text, output.status)
    }
}
