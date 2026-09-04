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
                suggestedReply: String? = nil) {
        self.detail = detail
        self.needs = needs
        self.result = result
        self.suggestedReply = suggestedReply
    }

    /// Nothing worth carrying. The join yields `nil` rather than an empty
    /// reading, so a row's `job` is present only when it says something.
    public var isEmpty: Bool {
        detail == nil && needs == nil && result == nil && suggestedReply == nil
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
                           suggestedReply: string("suggestedReply"))
        return info.isEmpty ? nil : info
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
