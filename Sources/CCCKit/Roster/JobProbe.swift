import Foundation

/// What the daemon's own job file says a session is doing, saying, or has
/// produced (v10): `~/.claude/jobs/<id>/state.json`, the file `DraftProbe`
/// already opens for one boolean.
///
/// The roster is thin by design — `claude agents --json --all` carries a
/// name, a state and sometimes `waitingFor` — and that thinness is what
/// made ccc's notifications four lines of constants. Measured 2026-09-04
/// across the 20 jobs on studio: `detail` was present in **20 of 20**, and
/// the one session the roster showed as `blocked` carried **no
/// `waitingFor` at all** while its job file held both the question and a
/// proposed answer. The roster says *that* it is your turn; this file says
/// *what for*.
///
/// The reading shifts with the state, which is what makes one field worth
/// joining:
/// - `working` → the live activity. Watched on 2026-09-04, one session
///   read `"PR #50 ready to merge; awaiting go-ahead"`, then
///   `"Reading the MIME table"` ten minutes later.
/// - `blocked` → the question, mirrored into `needs`.
/// - `done` → the result, equal to `output.result` verbatim in 12 of the
///   15 finished jobs and 20–460 characters long.
///
/// Read-only and lenient, like every other boundary here: the file is
/// undocumented past "unknown fields are preserved" (docs/HARNESS.md), so
/// every field is optional, a field of the wrong type is dropped rather
/// than failing the reading, and a file that is missing or unparseable is
/// `nil` — the banner ccc had before. **Never written** (CLAUDE.md).
public struct JobInfo: Codable, Sendable, Equatable {
    /// The live one-liner, whatever the state. Always present in the
    /// sample; still optional, because the sample is not a promise.
    public var detail: String?
    /// What a blocked session is asking. `DraftProbe` reads this same
    /// field for the phrase the harness prints at an unprompted `--bg`.
    public var needs: String?
    /// The finished result — `output.result`, the summary the session
    /// closed with.
    public var result: String?
    /// A reply the daemon proposes to `needs`. Rare (2 of 20), and worth
    /// showing when it is there rather than building anything for.
    public var suggestedReply: String?
    /// Whether this session was dispatched with `--rc` — Remote Control,
    /// so it is on claude.ai/code and in the Claude app, where it can be
    /// **answered from a phone** (v13, item 17; docs/HARNESS.md "Remote
    /// Control"). Read from `respawnFlags`, which is this same file.
    ///
    /// Measured 2026-09-04 before it was built, because two nearer
    /// candidates are wrong: `claude agents --json --all` carries nine
    /// keys and **no flag signal at all**, and `bridgeSessionId` is on
    /// **every** job — it is the claude.ai session id every background
    /// session gets, not a mark of Remote Control. `bridgeOutboundOnly`
    /// and `bridgeSessionSeq` do not discriminate either. `respawnFlags`
    /// does, five of nine on the fleet it was measured on, and it costs
    /// nothing: this file was already open.
    ///
    /// What it means is narrow and worth stating: the session was
    /// *launched* answerable. It is not proof the phone is connected right
    /// now, and nothing here polls Anthropic to find out. The row is
    /// telling you which sessions you could answer from the couch and
    /// which are only answerable at this Mac — which is the question a
    /// person actually has.
    public var remoteControl: Bool
    /// The `--permission-mode` the job was **launched** with, from the same
    /// `respawnFlags` — `auto`, `default`, `plan`, …, or nil when none was
    /// passed (the harness's default, which prompts). As launched, and
    /// only that: a runtime `/model` or shift-tab never reaches the flags,
    /// and a respawn brings the job back with these. Read (2026-09-04, at
    /// the user's word relayed by lore) because the only way to learn
    /// which worker would block on its first prompt was to open seven
    /// state files; the row now says which ones ask.
    public var permissionMode: String?
    /// **When the daemon last wrote this job's file** (`updatedAt`), which
    /// is the only clock ccc has for a session that is *working* (item
    /// 21). The roster's `startedAt` says when it began and nothing says
    /// when it last moved; this does, and it moves on every turn — read
    /// live 2026-09-06 against a session eight seconds into a tool call.
    ///
    /// It exists for the transition the watcher did not have. cuanto's
    /// Lane B was contracted to report at each landing point, sent zero
    /// messages, and sat with two unpushed commits for two days: nothing
    /// fired, because `blocked`/`done`/`failed`/`stopped` are the only
    /// things that ever happen to a row and it was `working` throughout.
    /// A stall is a *non-event*, and a non-event can only be detected
    /// against a clock.
    public var updatedAt: Date?
    /// **Whether the model's turn is generating** — the job file's own
    /// word, and not the same question the roster's `status` answers.
    ///
    /// Measured 2026-09-06, the night `ccc clear` shipped, on two rows
    /// with Remote Control on and everything else alike:
    ///
    ///     attrition  roster status=busy   tempo=idle  inFlight={tasks:3, kinds:[monitor, local_bash]}
    ///     lore       roster status=idle   tempo=idle  inFlight={tasks:0, kinds:[]}
    ///
    /// The daemon's `status` means *something live is attached to this
    /// session*, background tasks included; `tempo` means *the turn is
    /// running*. A commander holding a persistent Monitor is `busy` for
    /// as long as it holds it, which is forever by design — so anything
    /// asking "may I type into this pane now" has to read this field and
    /// not that one. `ClearWindow` does; `blocked` still comes from the
    /// roster, which is the right source for "a question is up".
    ///
    /// Values seen: `idle`, `active`, `blocked`. Kept as the string the
    /// file carries rather than an enum — a word this build has not met
    /// must read as "not idle" and never as a decode failure.
    public var tempo: String?
    // `children` — the job's pull requests and published artifacts — is
    // **not read**. It was, for a day: v11 slice 3 dropped the PR half of
    // the banner's receipt line and slice 4 dropped the rest, because the
    // field is appended for the life of the *job* and never pruned, so
    // what it names is almost never what the run in front of you just
    // did. Measured across the three jobs the index can count sessions
    // for: 294 sessions, 18 artifacts between them — a receipt line was
    // fresh at most 6% of the time, and `attrition` is the pure case at
    // one artifact over 202 sessions.
    //
    // `docs/EVIDENCE.md` "Fresh at most 6%" carries those numbers and the
    // argument for the run-delta that would fix it — not built, because
    // its own measurement says it would draw an empty line nineteen
    // banners in twenty.
    //
    // It stays out of the type rather than decoded-and-unused: the file
    // is on disk and one `JSONSerialization` away whenever the delta
    // earns itself.

    public init(detail: String? = nil, needs: String? = nil, result: String? = nil,
                suggestedReply: String? = nil, remoteControl: Bool = false, permissionMode: String? = nil,
                updatedAt: Date? = nil, tempo: String? = nil) {
        self.detail = detail
        self.needs = needs
        self.result = result
        self.suggestedReply = suggestedReply
        self.remoteControl = remoteControl
        self.permissionMode = permissionMode
        self.updatedAt = updatedAt
        self.tempo = tempo
    }

    /// Nothing worth carrying. The join yields `nil` rather than an empty
    /// reading, so a row's `job` is present only when it says something.
    ///
    /// `remoteControl` counts only when **true**: a session that is merely
    /// not remote-controlled has said nothing, and a reading of "no" for
    /// every field is the empty reading this guards against.
    public var isEmpty: Bool {
        detail == nil && needs == nil && result == nil && suggestedReply == nil && !remoteControl
            && permissionMode == nil && updatedAt == nil && tempo == nil
    }

    /// Hand-written and lenient, for the same reason `SessionRow`'s is:
    /// these readings arrive over ssh from *another build of ccc*, which
    /// may predate any field here. Synthesised decoding would throw on a
    /// missing non-optional `remoteControl`, and `SessionRow` decodes the
    /// whole reading with `try?` — so one absent key would drop `detail`,
    /// `needs` and `result` with it, and the far side's row would go
    /// silent rather than merely lose its newest field. Every field falls
    /// back instead.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        detail = try? container.decodeIfPresent(String.self, forKey: .detail)
        needs = try? container.decodeIfPresent(String.self, forKey: .needs)
        result = try? container.decodeIfPresent(String.self, forKey: .result)
        suggestedReply = try? container.decodeIfPresent(String.self, forKey: .suggestedReply)
        remoteControl = (try? container.decodeIfPresent(Bool.self, forKey: .remoteControl)) ?? false
        permissionMode = try? container.decodeIfPresent(String.self, forKey: .permissionMode)
        updatedAt = try? container.decodeIfPresent(Date.self, forKey: .updatedAt)
        tempo = try? container.decodeIfPresent(String.self, forKey: .tempo)
    }

    /// Whether a permission prompt will stop this job: launched without a
    /// mode (the harness prompts by default) or with one that asks.
    /// `auto` and `bypassPermissions` answer for themselves; everything
    /// else — `default`, `plan`, `acceptEdits` — still asks for something.
    public var asksForPermission: Bool {
        switch permissionMode {
        case "auto", "bypassPermissions": return false
        default: return true
        }
    }

    /// What this session has to say for itself, given what the roster says
    /// it is doing. One definition, because the banner, `ccc watch` and
    /// the roster row must not disagree about the sentence (CLAUDE.md's
    /// one-definition-many-surfaces rule).
    ///
    /// `needs` and `result` are the state's own field and win where they
    /// exist; `detail` is the fallback and the only answer while working.
    public func say(for state: Session.State?) -> String? {
        let pick: String?
        switch state {
        case .blocked: pick = needs ?? detail
        case .done: pick = result ?? detail
        default: pick = detail
        }
        guard let pick else { return nil }
        let trimmed = pick.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Lenient by hand: this is the harness's boundary, so a wrong type is
    /// a dropped field and never a thrown error.
    public static func decode(_ data: Data) -> JobInfo? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func string(_ key: String, in source: [String: Any] = object) -> String? {
            guard let value = source[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let info = JobInfo(detail: string("detail"), needs: string("needs"),
                           result: string("result", in: (object["output"] as? [String: Any]) ?? [:]),
                           suggestedReply: string("suggestedReply"),
                           remoteControl: remoteControl(in: object),
                           permissionMode: permissionMode(in: object),
                           updatedAt: string("updatedAt").flatMap(Self.instant),
                           tempo: string("tempo"))
        return info.isEmpty ? nil : info
    }

    /// The daemon writes `updatedAt` with fractional seconds
    /// (`2026-09-07T00:58:17.563Z`), which `.iso8601` alone does not
    /// parse; both shapes are tried, and an unparseable one is simply no
    /// clock — the stall detector then says nothing about that session
    /// rather than calling it stalled. Statically-let format styles, so
    /// no shared mutable formatter (ModelProbe's rule).
    private static let fractionalInstant = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plainInstant = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    static func instant(_ text: String) -> Date? {
        (try? fractionalInstant.parse(text)) ?? (try? plainInstant.parse(text))
    }

    /// The value after `--permission-mode` in `respawnFlags`, if any.
    /// Lenient the same way `remoteControl` is: no array, no flag, or a
    /// flag with nothing after it all read as "none was passed".
    static func permissionMode(in object: [String: Any]) -> String? {
        guard let flags = (object["respawnFlags"] as? [Any])?.compactMap({ $0 as? String }) else { return nil }
        guard let i = flags.firstIndex(of: "--permission-mode"), i + 1 < flags.count else { return nil }
        let mode = flags[i + 1].trimmingCharacters(in: .whitespaces)
        return mode.isEmpty || mode.hasPrefix("--") ? nil : mode
    }

    /// `--rc` (or its long spelling) among `respawnFlags`. Lenient in the
    /// house way: a missing array, an array of the wrong element type, or
    /// a whole file without the key all read as "not remote-controlled",
    /// which is the safe answer — the row simply says nothing about the
    /// phone rather than claiming a session is reachable there.
    ///
    /// Both spellings are matched because the harness accepts both and
    /// records what was typed; the fleet writes `--rc`, and a session
    /// launched with `--remote-control` would otherwise read as a session
    /// that cannot be answered from the couch when it can.
    static func remoteControl(in object: [String: Any]) -> Bool {
        guard let flags = object["respawnFlags"] as? [Any] else { return false }
        return flags.contains { ($0 as? String).map { $0 == "--rc" || $0 == "--remote-control" } ?? false }
    }
}

/// The join, cached the way the model join is: keyed on the file's (size,
/// mtime), so a tick that sees an unchanged job file costs one `stat` and
/// no read.
///
/// Unlike the transcript this is a *small* file — 1–2 KB against hundreds
/// of megabytes — so a miss is cheap and the cache is about cadence, not
/// about avoiding a catastrophe. It still earns its place: most of the
/// roster is terminal at any moment (15 of 20 jobs were `done` when this
/// was measured), and a terminal job's file never changes again.
public final class JobProbe: @unchecked Sendable {
    /// What the cache saved, cumulative — the same three cases
    /// `ModelProbe.Counters` reports, so `ccc stats` can say what the
    /// cadence actually costs instead of it being an argument.
    public struct Counters: Sendable, Codable, Equatable {
        /// Job files opened and parsed (the file had changed).
        public var reads = 0
        /// Rows answered from the cache after one `stat`.
        public var hits = 0
        /// `stat` failed — no job file, which is every interactive session.
        public var misses = 0
        public init(reads: Int = 0, hits: Int = 0, misses: Int = 0) {
            self.reads = reads
            self.hits = hits
            self.misses = misses
        }
    }

    private struct Stamp: Equatable {
        var size: UInt64
        var mtime: Date
    }

    private struct Entry {
        var stamp: Stamp
        var info: JobInfo?
    }

    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    private var counters = Counters()
    private let jobs: URL

    public init(jobsDirectory: URL = DraftProbe.defaultJobsDirectory) {
        self.jobs = jobsDirectory
    }

    public var stats: Counters {
        lock.lock()
        defer { lock.unlock() }
        return counters
    }

    /// The reading for one background session, by its short id. Interactive
    /// sessions have no job directory and answer `nil` after one `stat`.
    public func info(forJob id: String) -> JobInfo? {
        let url = jobs.appending(path: id).appending(path: "state.json")
        guard let stamp = Self.stamp(of: url) else {
            lock.lock(); counters.misses += 1; lock.unlock()
            return nil
        }
        let key = url.path(percentEncoded: false)

        lock.lock()
        if let cached = cache[key], cached.stamp == stamp {
            counters.hits += 1
            lock.unlock()
            return cached.info
        }
        lock.unlock()

        let info = (try? Data(contentsOf: url)).flatMap(JobInfo.decode)
        lock.lock()
        cache[key] = Entry(stamp: stamp, info: info)
        counters.reads += 1
        lock.unlock()
        return info
    }

    private static func stamp(of url: URL) -> Stamp? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize, let mtime = values.contentModificationDate else { return nil }
        return Stamp(size: UInt64(size), mtime: mtime)
    }
}
