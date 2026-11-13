import Foundation

/// **The spawn ledger**: one JSON line per session ccc dispatched, appended
/// to a file ccc owns, so "job A spawned job B" is a record and not a
/// reading of A's transcript.
///
/// Asked for by lore, 2026-11-13, with the user's go-ahead, and the reason
/// is the whole design (`docs/EVIDENCE.md` "the spawn ledger"). The daemon
/// records no parent, so lore read the edge off the spawner's transcript: the `"ref"` in
/// a `ccc spawn --json` answer, or the harness's own `backgrounded · <id>`.
/// That held until a commander wrote the answer to a file and printed the
/// id through python — eighteen lanes with no parent, a loop that priced
/// zero of them. A wider regex fixes that spelling and breaks on the next.
/// **ccc is the one place that knows both ends at the moment of the
/// spawn**, so it says so itself, whether or not `--json` was passed and
/// wherever stdout went.
///
/// What a line claims is what ccc knew when it wrote it, and nothing else:
///
/// - `child` is the daemon's id out of the harness's answer — the `ref`
///   `--json` prints, the id that survives /clear.
/// - `parent` is the **calling process's environment**, verbatim, or
///   `null`. A Claude Code session hands every shell it runs three ids
///   (measured 2026-11-13, 2.1.321, in a job that had been /cleared):
///   `CLAUDE_JOB_DIR`, whose basename is the caller's daemon job id;
///   `CLAUDE_CODE_SESSION_ID`, the transcript that is live *now* (it
///   moves at /clear — the job file calls it `resumeSessionId`); and
///   `CLAUDE_CODE_BRIDGE_SESSION_ID`, the id in commit trailers. `null`
///   is a fact too: nothing in the environment says a session asked, so a
///   person typed it or clicked Start.
/// - `model` and `effort` are what was **asked**, never what served. The
///   served model is the transcript's to say (CLAUDE.md, fan-out rules).
/// - `branch` and `base` are set only when ccc cut the worktree. When the
///   harness cut it ccc never sees what it made, and `worktree` — the
///   word the caller passed — is all there is.
///
/// Remote spawns are written **here**, on the Mac that ran `ccc`, with the
/// far host in `host`: the far side ran a bare `claude --bg` and its ccc
/// was never asked.
///
/// **Append-only, and a reader depends on it.** lore keys a line on
/// (`child`, `ts`), inserts it once and keeps it, so the file may be
/// rotated or truncated and lose nothing over there — but a line is never
/// rewritten in place, and nothing here has a verb that would.
///
/// A `/clear` is not in this file, because it mints nothing: the daemon
/// id, the name and the bridge id all hold, and only the session uuid
/// moves (`Clear.swift`). `kind` is a string so that a later record can
/// join the file without breaking a reader that skips what it does not
/// know.
public struct SpawnLedger: Sendable {
    public var path: String

    public init(path: String = SpawnLedger.defaultPath) {
        self.path = path
    }

    /// `~/Library/Application Support/ccc/spawns.jsonl`, beside the roster
    /// overlay and the host list, or `CCC_SPAWN_LEDGER`.
    public static var defaultPath: String {
        if let override = ProcessInfo.processInfo.environment["CCC_SPAWN_LEDGER"], !override.isEmpty { return override }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "ccc/spawns.jsonl").path
    }

    /// The line's shape version. Bumped when a field changes meaning,
    /// never when one is added.
    public static let version = 1

    /// What kind of dispatch a line records. `fork` is a spawn that opened
    /// with another session's transcript (`--from`).
    public enum Kind: String, Sendable, CaseIterable {
        case spawn, fork
    }

    /// Which face of ccc dispatched: the command, or the New Session sheet.
    public enum Surface: String, Sendable, CaseIterable {
        case cli, app
    }

    /// Who asked, as far as the environment says.
    public struct Caller: Codable, Sendable, Equatable {
        /// The caller's daemon job id: `CLAUDE_JOB_DIR`'s last component.
        /// Survives /clear. Absent for an interactive session.
        public var job: String?
        /// `CLAUDE_CODE_SESSION_ID`: the caller's live transcript.
        public var session: String?
        /// `CLAUDE_CODE_BRIDGE_SESSION_ID`, as the environment spells it
        /// (`session_…`; the job file spells the same id `cse_…`).
        public var bridge: String?

        public init(job: String? = nil, session: String? = nil, bridge: String? = nil) {
            self.job = job
            self.session = session
            self.bridge = bridge
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(job, forKey: .job)
            try c.encode(session, forKey: .session)
            try c.encode(bridge, forKey: .bridge)
        }

        /// The three variables this reads, in the order a reader should
        /// trust them as a key.
        public static let variables = ["CLAUDE_JOB_DIR", "CLAUDE_CODE_BRIDGE_SESSION_ID", "CLAUDE_CODE_SESSION_ID"]

        /// `nil` when the environment names no session at all.
        public static func of(environment: [String: String]) -> Caller? {
            func value(_ key: String) -> String? {
                environment[key].flatMap { $0.isEmpty ? nil : $0 }
            }
            let job = value("CLAUDE_JOB_DIR").map { ($0 as NSString).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
            let caller = Caller(job: job, session: value("CLAUDE_CODE_SESSION_ID"),
                                bridge: value("CLAUDE_CODE_BRIDGE_SESSION_ID"))
            return caller == Caller() ? nil : caller
        }

        /// This process's caller.
        public static var current: Caller? { of(environment: ProcessInfo.processInfo.environment) }

        /// Whether `word` names this caller: any of its ids, whole or as a
        /// prefix of at least six characters (a daemon id is eight).
        public func answers(to word: String) -> Bool {
            guard !word.isEmpty else { return false }
            return [job, session, bridge].compactMap { $0 }.contains { id in
                id == word || (word.count >= 6 && id.hasPrefix(word))
            }
        }

        /// The shortest thing that names it, for a line of text.
        public var short: String {
            job ?? session.map { String($0.prefix(8)) } ?? bridge ?? "?"
        }
    }

    public struct Entry: Codable, Sendable, Equatable {
        public var v: Int
        /// When the harness answered, ISO 8601, UTC.
        public var ts: String
        public var kind: String
        public var via: String
        /// The host the session runs on, by ccc's name for it.
        public var host: String
        /// The new session's daemon id.
        public var child: String
        public var name: String?
        public var model: String?
        public var effort: String?
        public var agent: String?
        /// Where the session runs: the worktree's path when ccc cut one.
        public var cwd: String?
        /// The `--worktree` word as asked: absent for none, `""` for a
        /// bare flag (the harness names it), else the name.
        public var worktree: String?
        /// The worktree's branch and the base it was cut from — only when
        /// ccc cut it.
        public var branch: String?
        public var base: String?
        /// The session id a fork opened from.
        public var from: String?
        /// The daemon id `--replace` stopped to make room for this one.
        public var replaced: String?
        public var draft: Bool
        public var parent: Caller?

        enum CodingKeys: String, CodingKey {
            case v, ts, kind, via, host, child, name, model, effort, agent, cwd, worktree, branch, base, from,
                 replaced, draft, parent
        }

        public init(v: Int = SpawnLedger.version, ts: String, kind: Kind, via: Surface, host: String, child: String,
                    name: String? = nil, model: String? = nil, effort: String? = nil, agent: String? = nil,
                    cwd: String? = nil, worktree: String? = nil, branch: String? = nil, base: String? = nil,
                    from: String? = nil, replaced: String? = nil, draft: Bool = false, parent: Caller? = nil) {
            self.v = v
            self.ts = ts
            self.kind = kind.rawValue
            self.via = via.rawValue
            self.host = host
            self.child = child
            self.name = name
            self.model = model
            self.effort = effort
            self.agent = agent
            self.cwd = cwd
            self.worktree = worktree
            self.branch = branch
            self.base = base
            self.from = from
            self.replaced = replaced
            self.draft = draft
            self.parent = parent
        }

        /// The line for a spawn that just succeeded. `asked` is the
        /// request as the caller made it; `result` is what came of it —
        /// the two differ exactly when ccc cut the worktree, which moves
        /// the cwd and takes `--worktree` off the harness's argv.
        public static func of(asked: SpawnRequest, result: SpawnResult, via: Surface, caller: Caller?,
                              replaced: String? = nil, now: Date = Date()) -> Entry {
            func word(_ text: String?) -> String? { text.flatMap { $0.isEmpty ? nil : $0 } }
            return Entry(ts: ISO8601DateFormatter().string(from: now),
                         kind: asked.isFork ? .fork : .spawn, via: via,
                         host: result.ref.host, child: result.ref.id,
                         name: word(asked.name), model: word(asked.model), effort: word(asked.effort),
                         agent: word(asked.agent), cwd: result.cwd, worktree: asked.worktree,
                         branch: result.worktree?.branch, base: result.worktree?.base,
                         from: asked.isFork ? asked.from : nil, replaced: word(replaced),
                         draft: result.draft, parent: caller)
        }

        /// Lenient, like every file ccc re-reads: only the child is
        /// required, and a kind this build has not met is kept as its
        /// word.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            child = try c.decode(String.self, forKey: .child)
            v = (try? c.decodeIfPresent(Int.self, forKey: .v)) ?? 0
            ts = (try? c.decodeIfPresent(String.self, forKey: .ts)) ?? ""
            kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? Kind.spawn.rawValue
            via = (try? c.decodeIfPresent(String.self, forKey: .via)) ?? ""
            host = (try? c.decodeIfPresent(String.self, forKey: .host)) ?? Host.localName
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            model = try? c.decodeIfPresent(String.self, forKey: .model)
            effort = try? c.decodeIfPresent(String.self, forKey: .effort)
            agent = try? c.decodeIfPresent(String.self, forKey: .agent)
            cwd = try? c.decodeIfPresent(String.self, forKey: .cwd)
            worktree = try? c.decodeIfPresent(String.self, forKey: .worktree)
            branch = try? c.decodeIfPresent(String.self, forKey: .branch)
            base = try? c.decodeIfPresent(String.self, forKey: .base)
            from = try? c.decodeIfPresent(String.self, forKey: .from)
            replaced = try? c.decodeIfPresent(String.self, forKey: .replaced)
            draft = (try? c.decodeIfPresent(Bool.self, forKey: .draft)) ?? false
            parent = try? c.decodeIfPresent(Caller.self, forKey: .parent)
        }

        /// Every key on every line, `null` where ccc had nothing to say —
        /// above all `parent`, where the null is the answer.
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(v, forKey: .v)
            try c.encode(ts, forKey: .ts)
            try c.encode(kind, forKey: .kind)
            try c.encode(via, forKey: .via)
            try c.encode(host, forKey: .host)
            try c.encode(child, forKey: .child)
            try c.encode(name, forKey: .name)
            try c.encode(model, forKey: .model)
            try c.encode(effort, forKey: .effort)
            try c.encode(agent, forKey: .agent)
            try c.encode(cwd, forKey: .cwd)
            try c.encode(worktree, forKey: .worktree)
            try c.encode(branch, forKey: .branch)
            try c.encode(base, forKey: .base)
            try c.encode(from, forKey: .from)
            try c.encode(replaced, forKey: .replaced)
            try c.encode(draft, forKey: .draft)
            try c.encode(parent, forKey: .parent)
        }

        /// One row of `ccc spawns`.
        public var description: String {
            var words = [ts, child]
            if host != Host.localName { words[1] = "\(host):\(child)" }
            words.append(name ?? "-")
            words.append(model ?? "-")
            words.append("← " + (parent?.short ?? (via == Surface.app.rawValue ? "(the sheet)" : "(typed)")))
            if let branch, let base { words.append("\(branch) off \(base)") }
            if kind != Kind.spawn.rawValue { words.append(kind) }
            if let replaced { words.append("replaced \(replaced)") }
            if draft { words.append("draft") }
            return words.joined(separator: "  ")
        }
    }

    public struct Failure: Error, CustomStringConvertible, Sendable {
        public var description: String
    }

    /// The line as it is written: one object, sorted keys, no newline.
    public static func line(_ entry: Entry) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(entry)
    }

    /// Append one line. `O_APPEND` and a single `write(2)`, so two spawns
    /// landing in the same instant — a commander fanning four lanes out
    /// in parallel is the ordinary case — each get a whole line.
    public func append(_ entry: Entry) throws {
        var line = try Self.line(entry)
        line.append(0x0A)
        let url = URL(filePath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { throw Failure(description: "\(path): \(String(cString: strerror(errno)))") }
        defer { close(fd) }
        let wrote = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard wrote == line.count else {
            let why = wrote < 0 ? String(cString: strerror(errno)) : "wrote \(wrote) of \(line.count) bytes"
            throw Failure(description: "\(path): \(why)")
        }
    }

    public struct Reading: Sendable, Equatable {
        /// Oldest first, as written.
        public var entries: [Entry]
        /// Lines that did not decode — a torn write, a hand edit.
        public var skipped: Int
    }

    /// Every line that reads. A missing file is an empty ledger, and a
    /// line that does not decode costs itself and nothing else.
    public func read() -> Reading {
        guard let data = FileManager.default.contents(atPath: path) else { return Reading(entries: [], skipped: 0) }
        let decoder = JSONDecoder()
        var entries: [Entry] = []
        var skipped = 0
        for line in data.split(separator: 0x0A) where !line.allSatisfy({ $0 == 0x20 || $0 == 0x0D }) {
            if let entry = try? decoder.decode(Entry.self, from: Data(line)) {
                entries.append(entry)
            } else {
                skipped += 1
            }
        }
        return Reading(entries: entries, skipped: skipped)
    }
}
