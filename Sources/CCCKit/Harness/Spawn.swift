import Foundation

/// What to dispatch (v5): the arguments of `claude --bg`, as ccc exposes
/// them. One of these is built by the New Session sheet and by
/// `ccc spawn`, and it is the *same* words on the wire — the sheet has
/// no field the command lacks and the reverse.
///
/// No `--cwd` exists on the harness side: the cwd is the directory the
/// command runs in (docs/HARNESS.md). Locally that is the child's working
/// directory; remotely it is a `cd` in front of the command, on the far
/// side, so `~/code` means the far side's `~`.
public struct SpawnRequest: Codable, Sendable, Equatable {
    /// Where the session runs. `nil` is the invoking process's directory
    /// locally and the login shell's default (home) remotely.
    public var cwd: String?
    /// The first instruction. `nil` or empty is the draft: the session
    /// starts, registers, and sits idle awaiting a prompt.
    public var prompt: String?
    public var name: String?
    public var model: String?
    public var agent: String?
    public var permissionMode: String?
    public var effort: String?
    /// `--worktree`: `nil` for none, `""` to let the harness name it, else
    /// the name.
    public var worktree: String?
    /// Fork (slice 3): the session this one continues from, as
    /// `--resume <id> --fork-session` — a new session that opens with the
    /// source's transcript, the source untouched. Measured 2026-09-02
    /// (docs/HARNESS.md): this must be the **full session id** (the
    /// roster's `sessionId`); the eight-character job id opens the
    /// harness's "Resume session" picker instead, and a name resolves but
    /// the daemon records `restoresTranscript: false` for it. With no
    /// prompt it is a draft that already knows the conversation.
    public var from: String?

    public init(cwd: String? = nil, prompt: String? = nil, name: String? = nil, model: String? = nil,
                agent: String? = nil, permissionMode: String? = nil, effort: String? = nil,
                worktree: String? = nil, from: String? = nil) {
        self.cwd = cwd
        self.prompt = prompt
        self.name = name
        self.model = model
        self.agent = agent
        self.permissionMode = permissionMode
        self.effort = effort
        self.worktree = worktree
        self.from = from
    }

    public var isDraft: Bool { (prompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var isFork: Bool { !(from ?? "").isEmpty }

    /// The harness's words after `claude`. The prompt is one argument, last.
    public var claudeArguments: [String] {
        var out = ["--bg"]
        if let from, !from.isEmpty { out += ["--resume", from, "--fork-session"] }
        if let name, !name.isEmpty { out += ["--name", name] }
        if let model, !model.isEmpty { out += ["--model", model] }
        if let agent, !agent.isEmpty { out += ["--agent", agent] }
        if let permissionMode, !permissionMode.isEmpty { out += ["--permission-mode", permissionMode] }
        if let effort, !effort.isEmpty { out += ["--effort", effort] }
        if let worktree { out += worktree.isEmpty ? ["--worktree"] : ["--worktree", worktree] }
        if !isDraft, let prompt { out.append(prompt) }
        return out
    }
}

/// What the harness answered. Measured 2026-09-02 (2.1.259,
/// `scripts/spawn-probe`): one line, `backgrounded · <id>[ · <name>]`,
/// the id wrapped in ANSI colour, and for a draft a dim
/// `(idle — send a prompt to start)` after it; then four hint lines.
public struct SpawnResult: Codable, Sendable, Equatable {
    public var ref: SessionRef
    /// The harness said the session is idle awaiting its first prompt.
    public var draft: Bool
    /// What was actually asked of the harness — the cwd the command ran
    /// in, so the answer names it even when the request left it implicit.
    public var cwd: String?
    /// The harness's text, ANSI stripped.
    public var said: String
    /// The session this one was forked from, when it was — the request's
    /// `from` as given (a full session id), so the answer names its
    /// lineage. Absent off an older ccc.
    public var from: String?

    public init(ref: SessionRef, draft: Bool, cwd: String?, said: String, from: String? = nil) {
        self.ref = ref
        self.draft = draft
        self.cwd = cwd
        self.said = said
        self.from = from
    }

    public var description: String {
        let lineage = from.map { " from \($0.prefix(8))" } ?? ""
        return draft ? "drafted \(ref)\(lineage) (idle — attach and send a prompt)" : "spawned \(ref)\(lineage)"
    }
}

public struct SpawnError: Error, CustomStringConvertible, Sendable {
    public var description: String
}

extension ClaudeCLI {
    /// The argv for a spawn on this host.
    ///
    /// Local: `claude --bg …` — the cwd is the process's, set by the caller
    /// (`spawnCwd`), never a word. Remote: `ssh <dest> cd <cwd> && claude
    /// --bg …`, no tty (the harness prints and exits; a tty would make it
    /// negotiate a terminal). ssh joins the remote words with spaces and
    /// the far side's login shell re-splits them, so every word that could
    /// split or glob is single-quoted there — the prompt above all — while
    /// a bare `~/code` stays bare so that shell expands it (the same rule
    /// as every other remote path here).
    public func spawnArgv(_ request: SpawnRequest) -> [String] {
        guard let destination = host.ssh else { return [executable] + request.claudeArguments }
        var words: [String] = []
        if let cwd = request.cwd, !cwd.isEmpty {
            words += ["cd", Self.remoteWord(cwd), "&&"]
        }
        words.append(executable)
        words += request.claudeArguments.map(Self.remoteWord)
        return sshPrefix(tty: false, destination: destination) + words
    }

    /// The directory the *local* child runs in — `nil` remotely, where the
    /// cwd is a word in the argv instead.
    public func spawnCwd(_ request: SpawnRequest) -> String? {
        guard host.isLocal else { return nil }
        return request.cwd.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The same words as a pasteable line — the sheet's "what will run".
    public func spawnCommandLine(_ request: SpawnRequest) -> String {
        let argv = spawnArgv(request)
        let line = argv.map { $0.contains(where: \.isWhitespace) && !$0.hasPrefix("'") ? "'\($0)'" : $0 }
            .joined(separator: " ")
        if let cwd = spawnCwd(request) { return "cd \(cwd) && \(line)" }
        return line
    }

    /// Dispatch. The child's environment loses every `CLAUDE*` marker
    /// (docs/HARNESS.md experiment 1): `ccc spawn` typed inside a Claude
    /// Code session — which is exactly how an agent spawns — would
    /// otherwise hand the new session `CLAUDE_CODE_CHILD_SESSION`, and a
    /// child session keeps no transcript, which is the model column gone.
    public func spawn(_ request: SpawnRequest) async throws -> SpawnResult {
        try prepareControlDirectory()
        if let cwd = spawnCwd(request) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw SpawnError(description: "no such directory '\(cwd)'")
            }
        }
        var environment = ProcessInfo.processInfo.environment
        for key in environment.keys where key.hasPrefix("CLAUDE") { environment.removeValue(forKey: key) }
        let result = try await run(spawnArgv(request), accepting: [0], program: "claude",
                                   cwd: spawnCwd(request), environment: environment)
        let said = Self.stripANSI(String(decoding: result.stdout, as: UTF8.self) + result.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Self.parseSpawnAnswer(said) else {
            throw SpawnError(description: "claude --bg on \(host.name) answered without a session id: \(said.split(separator: "\n").first ?? "(nothing)")")
        }
        let cwd = request.cwd.flatMap { $0.isEmpty ? nil : $0 }
            ?? (host.isLocal ? FileManager.default.currentDirectoryPath : host.home)
        return SpawnResult(ref: SessionRef(host: host.name, id: parsed.id), draft: parsed.draft, cwd: cwd, said: said,
                           from: request.isFork ? request.from : nil)
    }

    /// The id and the draft mark out of the harness's answer, ANSI
    /// already gone. `nil` when there is no `backgrounded · <id>`.
    public static func parseSpawnAnswer(_ text: String) -> (id: String, draft: Bool)? {
        let plain = stripANSI(text)
        guard let range = plain.range(of: "backgrounded") else { return nil }
        var rest = plain[range.upperBound...]
        // "backgrounded · 2f4c7814 · ccc-v5-probe" — skip the separator.
        rest = rest.drop { $0.isWhitespace || $0 == "·" }
        let id = rest.prefix { $0.isHexDigit }
        guard id.count >= 6 else { return nil }
        let line = plain[range.lowerBound...].prefix { $0 != "\n" }
        return (String(id), line.contains("send a prompt to start"))
    }

    /// CSI sequences ending in a letter (`\e[36m`, `\e[2K`) removed.
    public static func stripANSI(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        var iterator = text.makeIterator()
        while let ch = iterator.next() {
            guard ch == "\u{1B}" else { out.append(ch); continue }
            guard let next = iterator.next() else { break }
            guard next == "[" else { continue }
            while let c = iterator.next(), !c.isLetter {}
        }
        return out
    }

    /// One remote word, safe across ssh's join and the far side's split.
    /// Left bare when every character is one a shell passes through
    /// unchanged (so `~` still expands); single-quoted otherwise, with a
    /// leading `~/` kept outside the quotes for the same reason.
    static func remoteWord(_ word: String) -> String {
        let safe = word.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", "-", "_", ".", "/", "~", ":", "=", "@", ",", "+", "%":
                return true
            default:
                return false
            }
        }
        if safe, !word.isEmpty { return word }
        let quoted = "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
        if word.hasPrefix("~/") { return "~/" + "'" + String(word.dropFirst(2)).replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return quoted
    }
}
