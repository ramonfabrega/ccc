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
    /// What the session produced: pull requests, published artifacts.
    /// Present in 14 of 20 jobs, and the reason a finished banner can say
    /// "there are two PRs waiting" instead of only "done".
    public var children: [Link]

    public struct Link: Codable, Sendable, Equatable {
        public var id: String
        /// `pr`, `frame`, … Unknown kinds pass through untouched.
        public var kind: String?
        public var title: String?

        public init(id: String, kind: String? = nil, title: String? = nil) {
            self.id = id
            self.kind = kind
            self.title = title
        }

        /// The link as one token in a receipt line: `#4916` for a pull
        /// request, its title for anything that has one, else the id.
        public var token: String {
            if kind == "pr" { return "#\(id)" }
            if let title, !title.isEmpty { return title }
            return id
        }
    }

    public init(detail: String? = nil, needs: String? = nil, result: String? = nil,
                suggestedReply: String? = nil, children: [Link] = []) {
        self.detail = detail
        self.needs = needs
        self.result = result
        self.suggestedReply = suggestedReply
        self.children = children
    }

    /// Nothing worth carrying. The join yields `nil` rather than an empty
    /// reading, so a row's `job` is present only when it says something.
    public var isEmpty: Bool {
        detail == nil && needs == nil && result == nil && suggestedReply == nil && children.isEmpty
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

    /// The receipt: what came out, as one line. `nil` when the session
    /// produced nothing. Capped at four tokens — a banner has one line for
    /// this and a session with eleven PRs would spend the whole width on
    /// a list nobody reads to the end.
    public var receipt: String? {
        guard !children.isEmpty else { return nil }
        let tokens = children.prefix(4).map(\.token)
        let more = children.count - tokens.count
        return tokens.joined(separator: " · ") + (more > 0 ? " +\(more)" : "")
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
        var links: [Link] = []
        for case let child as [String: Any] in (object["children"] as? [Any]) ?? [] {
            // An id can arrive as a PR number; accept both spellings.
            let id = (child["id"] as? String) ?? (child["id"] as? Int).map(String.init)
            guard let id, !id.isEmpty else { continue }
            links.append(Link(id: id, kind: string("kind", in: child), title: string("title", in: child)))
        }
        let info = JobInfo(detail: string("detail"), needs: string("needs"),
                           result: string("result", in: (object["output"] as? [String: Any]) ?? [:]),
                           suggestedReply: string("suggestedReply"), children: links)
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
