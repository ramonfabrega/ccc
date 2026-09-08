import Foundation

/// What ccc says about a session that the harness does not (v4): archived,
/// pinned. The roster is the daemon's and stays read-only; this is the one
/// file of ours laid over it, `~/Library/Application Support/ccc/roster.json`,
/// hand-editable like `hosts.json`.
///
/// **It lives with the session's host** (docs/DESIGN.md §8). Each Mac's
/// file marks only that Mac's own sessions, and a remote row carries its
/// marks inside the far side's `ccc list --json` — the same road the model
/// column takes — so `ccc archive studio:a1b2` from air runs `ccc archive
/// a1b2` on studio, and both Macs agree on what is archived because there
/// is one answer, kept next to the session.
public struct SessionMark: Codable, Sendable, Equatable {
    /// When it was archived; `nil` when it is not.
    public var archived: Date?
    /// When it was pinned; `nil` when it is not.
    public var pinned: Date?
    /// A `/clear` waiting for the row to go idle (item 27); `nil` when
    /// none is armed. Unlike the two above this is an *instruction* with a
    /// lifetime of minutes rather than an opinion, and it is here for the
    /// three things the file already gives: it survives an app restart,
    /// it rides the same road to the session's own host, and the uuid
    /// guard above is exactly right for it — a clear mints a new session
    /// uuid, so a pending clear never applies to the session that follows
    /// the one it was armed on.
    public var clear: PendingClear?
    /// The full session uuid the mark was made against, when the row had
    /// one. The daemon mints short ids and nothing promises it never mints
    /// one twice, so a mark whose uuid disagrees with the row's is a mark
    /// on some earlier session and does not apply.
    public var sessionId: String?
    /// What became of the last clear armed here (v0.1.36). The arming
    /// side is normally a background session that will never see the
    /// window's notice or the headless log — and after a clear that
    /// worked it has no memory of arming at all — so the outcome is
    /// written back where a *reader* can find it: `ccc clear` with no
    /// ref. Without it "armed, then gone, and nothing said why" is a
    /// state the fleet can reach in silence, which is how the keying bug
    /// below lived through two probes.
    public var fired: ClearRecord?

    public init(archived: Date? = nil, pinned: Date? = nil, clear: PendingClear? = nil,
                sessionId: String? = nil, fired: ClearRecord? = nil) {
        self.archived = archived
        self.pinned = pinned
        self.clear = clear
        self.sessionId = sessionId
        self.fired = fired
    }

    public var isEmpty: Bool { archived == nil && pinned == nil && clear == nil && fired == nil }

    /// The newest thing that happened to this mark, for pruning.
    var madeAt: Date { [archived, pinned, clear?.armedAt, fired?.at].compactMap { $0 }.max() ?? .distantPast }
}

/// What one armed clear did, kept on the mark it was armed on. Three
/// shapes, all of them worth a sentence: it fired, it was refused (a
/// dirty tree at the moment it came due), or it was dropped (the session
/// it named is gone). `fired` is the one bit a caller checks; `said` is
/// the sentence the window drew.
public struct ClearRecord: Codable, Sendable, Equatable {
    public var at: Date
    public var said: String
    public var fired: Bool

    public init(at: Date = Date(), said: String, fired: Bool) {
        self.at = at
        self.said = said
        self.fired = fired
    }
}

/// A `/clear` armed on a session, waiting for it to stop working (item 27).
///
/// The caller is normally the session itself — a commander whose item has
/// landed and whose bank is committed — and a session cannot wait for its
/// own turn to end: while `ccc clear` runs, the row it is asking about is
/// busy *because of that call*. So the verb arms and returns, and whatever
/// owns a pane on this Mac fires it on a later poll. Measured 2026-09-06:
/// a `/clear` typed mid-turn takes effect at once and the running turn's
/// output is simply gone (docs/EVIDENCE.md "item 27"), which is what the
/// idle gate is for.
public struct PendingClear: Codable, Sendable, Equatable {
    public var armedAt: Date
    /// Typed after the clear lands. Nil clears and stops there.
    public var then: String?

    public init(armedAt: Date = Date(), then: String? = nil) {
        self.armedAt = armedAt
        self.then = then
    }

    /// What the verb prints and the notice repeats.
    public func said(_ id: String) -> String {
        let tail = then.map { ", then: \($0)" } ?? ""
        return "armed a clear on \(id); it fires when the row is idle\(tail)"
    }
}

public struct RosterOverlay: Codable, Sendable, Equatable {
    /// Keyed by the harness's short id: host-local by construction, since
    /// the file is.
    public var marks: [String: SessionMark]

    public init(marks: [String: SessionMark] = [:]) {
        self.marks = marks
    }

    public static var defaultPath: String {
        if let override = ProcessInfo.processInfo.environment["CCC_ROSTER_OVERLAY"], !override.isEmpty { return override }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "ccc/roster.json").path
    }

    /// What a load produced. A broken file is an empty overlay with the
    /// reason — the roster must never disappear because our sidecar did.
    public struct Loaded: Sendable, Equatable {
        public var overlay: RosterOverlay
        public var issue: String?
        /// The file's mtime, so a poller can skip re-reading an unchanged file.
        public var modifiedAt: Date?
        public init(overlay: RosterOverlay, issue: String? = nil, modifiedAt: Date? = nil) {
            self.overlay = overlay
            self.issue = issue
            self.modifiedAt = modifiedAt
        }
    }

    public static func modificationDate(path: String = defaultPath) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    public static func load(path: String = defaultPath) -> Loaded {
        guard let data = FileManager.default.contents(atPath: path) else { return Loaded(overlay: RosterOverlay()) }
        let modified = modificationDate(path: path)
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var overlay = try decoder.decode(RosterOverlay.self, from: data)
            overlay.marks = overlay.marks.filter { !$0.value.isEmpty }
            return Loaded(overlay: overlay, modifiedAt: modified)
        } catch {
            return Loaded(overlay: RosterOverlay(),
                          issue: "\(path): \(error.localizedDescription); ignoring the overlay", modifiedAt: modified)
        }
    }

    public func save(path: String = defaultPath) throws {
        let url = URL(filePath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Run `body` holding an exclusive lock on the file's `.lock` sibling,
    /// so a load → change → save is one act against every other writer:
    /// the app's poller pruning, a `ccc archive` from a shell, two marks
    /// from the keyboard. `save` is atomic and always was; what the lock
    /// adds is that nobody saves over a load they did not make. Hold it
    /// around synchronous work only — never across an `await`.
    public static func locked<T>(path: String = defaultPath, _ body: () throws -> T) throws -> T {
        let url = URL(filePath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(path + ".lock", O_RDWR | O_CREAT, 0o600)
        guard fd >= 0 else { throw LockError(errno: errno) }
        defer { close(fd) }
        while flock(fd, LOCK_EX) != 0 {
            guard errno == EINTR else { throw LockError(errno: errno) }
        }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    public struct LockError: Error, CustomStringConvertible {
        public var errno: Int32
        public var description: String { "could not lock the overlay: \(String(cString: strerror(errno)))" }
    }

    /// The mark for a row, if one applies: same short id, and the uuid
    /// agrees when both sides have one.
    public func mark(for id: String, sessionId: String?) -> SessionMark? {
        guard let mark = marks[id] else { return nil }
        if let theirs = mark.sessionId, let ours = sessionId, theirs != ours { return nil }
        return mark
    }

    public mutating func set(_ change: MarkChange, id: String, sessionId: String?, at now: Date = Date()) {
        var mark = mark(for: id, sessionId: sessionId) ?? SessionMark()
        switch change {
        case .archive: mark.archived = now
        case .unarchive: mark.archived = nil
        case .pin: mark.pinned = now
        case .unpin: mark.pinned = nil
        }
        if mark.sessionId == nil { mark.sessionId = sessionId }
        marks[id] = mark.isEmpty ? nil : mark
    }

    /// Arm a clear on a row, or disarm one (`nil`). Returns what was
    /// there, so a cancel can say whether it cancelled anything.
    @discardableResult
    public mutating func arm(_ clear: PendingClear?, id: String, sessionId: String?) -> PendingClear? {
        var mark = mark(for: id, sessionId: sessionId) ?? SessionMark()
        let previous = mark.clear
        mark.clear = clear
        if mark.sessionId == nil { mark.sessionId = sessionId }
        marks[id] = mark.isEmpty ? nil : mark
        return previous
    }

    /// Write down what a clear did, on the mark it was armed on. Called
    /// by whichever pane took the mark, right after it took it.
    public mutating func record(_ outcome: ClearRecord, id: String, sessionId: String?) {
        var mark = mark(for: id, sessionId: sessionId) ?? SessionMark()
        mark.fired = outcome
        if mark.sessionId == nil { mark.sessionId = sessionId }
        marks[id] = mark.isEmpty ? nil : mark
    }

    /// Every row with a clear waiting, newest first. The read half of
    /// `ccc clear` — a write with no way to look at it is a finding.
    public var armedClears: [(id: String, mark: SessionMark)] {
        marks.filter { $0.value.clear != nil }
            .sorted { ($0.value.clear?.armedAt ?? .distantPast) > ($1.value.clear?.armedAt ?? .distantPast) }
            .map { (id: $0.key, mark: $0.value) }
    }

    /// Every clear that already happened, newest first — the other half
    /// of the same read. An arm that vanished from `armedClears` is here,
    /// with the sentence that says whether it typed or was dropped.
    public var firedClears: [(id: String, record: ClearRecord)] {
        marks.compactMap { entry in entry.value.fired.map { (id: entry.key, record: $0) } }
            .sorted { $0.record.at > $1.record.at }
    }

    /// Drop marks on sessions the roster no longer has, once they are old
    /// enough that "gone" is not "this host is asleep" — done rows leave the
    /// roster when the daemon recycles their worker (docs/HARNESS.md), and
    /// a mark on a row that will never return is dead weight. Returns
    /// whether anything was dropped, so the caller knows to save.
    @discardableResult
    public mutating func prune(keeping live: Set<String>, olderThan age: TimeInterval = 7 * 86_400, now: Date = Date()) -> Bool {
        let before = marks.count
        marks = marks.filter { live.contains($0.key) || now.timeIntervalSince($0.value.madeAt) < age }
        return marks.count != before
    }
}

/// The four gestures on a mark. One verb each (`ccc archive <ref>`), one
/// context-menu item each; the same `RosterOverlay.set` behind both.
public enum MarkChange: String, Codable, Sendable, CaseIterable {
    case archive, unarchive, pin, unpin

    /// "archived", "unpinned" — what the verb and the notice say.
    public var pastTense: String {
        switch self {
        case .archive: return "archived"
        case .unarchive: return "unarchived"
        case .pin: return "pinned"
        case .unpin: return "unpinned"
        }
    }
}

extension ClaudeCLI {
    /// `ccc <change> <id>` on a remote host: the mark is made where the
    /// session lives, by the far side's own ccc, and comes back in its
    /// roster rows. Needs `ccc` there — a host read through the harness
    /// fallback has nowhere to keep a mark.
    public func markArgv(_ change: MarkChange, id: String) -> [String]? {
        guard let ccc = host.ccc, let destination = host.ssh else { return nil }
        return sshPrefix(tty: false, destination: destination) + [ccc, change.rawValue, id]
    }

    /// Apply a mark on this host and say what happened, in the words the
    /// verb prints. Local: the overlay file, after checking the roster —
    /// `archive` and `pin` need the row (so every mark starts with the
    /// session's uuid as its guard); `unarchive` and `unpin` only drop a
    /// mark and need nothing, since the row may be gone. Remote: the same
    /// verb on the far side, its answer passed through.
    ///
    /// **The key is the row's id, never the caller's word.** A `<ref>`
    /// resolves by name as well as by id (v0.1.31), and the poller joins
    /// marks on `session.id` alone — so a mark filed under a name is a
    /// mark no row will ever read (`docs/EVIDENCE.md`, "the name that
    /// resolved for the read and not for the write").
    public func mark(_ change: MarkChange, id: String, overlayPath: String = RosterOverlay.defaultPath) async throws -> String {
        if host.isLocal {
            var key = id
            var sessionId: String?
            switch change {
            case .archive, .pin:
                let roster = RosterDecoder.decode(try await agentsJSON())
                let row = try roster.sessions.session(matching: id)
                key = row.id
                sessionId = row.sessionId
            case .unarchive, .unpin:
                // No roster read when the word is already a key — the
                // undo half works on a row the roster has forgotten, and
                // that is the case it exists for. Only a word that is not
                // a key can be a name, and only then is it worth a
                // `claude agents` to find out (leniently: no row means
                // the sentence below, not an error).
                if RosterOverlay.load(path: overlayPath).overlay.marks[id] == nil,
                   let row = RosterDecoder.decode(try await agentsJSON()).sessions.sessionIfAny(matching: id) {
                    key = row.id
                }
            }
            // Load, change and save as one stretch under the file's lock,
            // and only after the roster read above. Until 2026-09-04 the
            // load came first, so two marks a few hundred ms apart — `a`
            // then `p` down the list, or two `ccc archive`s from a shell —
            // each loaded the same file, waited on `claude agents`, and
            // the second save silently dropped the first mark (reproduced
            // with a 400 ms stub: one of two archives gone, both exit 0).
            return try RosterOverlay.locked(path: overlayPath) {
                var overlay = RosterOverlay.load(path: overlayPath).overlay
                if change == .unarchive || change == .unpin, overlay.marks[key] == nil {
                    return "\(key) was not \(change == .unarchive ? "archived" : "pinned")"
                }
                overlay.set(change, id: key, sessionId: sessionId)
                try overlay.save(path: overlayPath)
                return "\(change.pastTense) \(key)"
            }
        }
        guard let argv = markArgv(change, id: id) else { throw MarkError.noRemoteCCC(host.name) }
        try prepareControlDirectory()
        let out = try await run(argv, program: "ccc")
        return String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public enum MarkError: Error, CustomStringConvertible {
        case noRemoteCCC(String)
        public var description: String {
            switch self {
            case .noRemoteCCC(let host): return "marks live with the session's host, and \(host) has no ccc for them (`ccc hosts add \(host)` finds one)"
            }
        }
    }
}
