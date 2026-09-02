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
    /// The full session uuid the mark was made against, when the row had
    /// one. The daemon mints short ids and nothing promises it never mints
    /// one twice, so a mark whose uuid disagrees with the row's is a mark
    /// on some earlier session and does not apply.
    public var sessionId: String?

    public init(archived: Date? = nil, pinned: Date? = nil, sessionId: String? = nil) {
        self.archived = archived
        self.pinned = pinned
        self.sessionId = sessionId
    }

    public var isEmpty: Bool { archived == nil && pinned == nil }

    /// The newest thing that happened to this mark, for pruning.
    var madeAt: Date { [archived, pinned].compactMap { $0 }.max() ?? .distantPast }
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
    public func mark(_ change: MarkChange, id: String, overlayPath: String = RosterOverlay.defaultPath) async throws -> String {
        if host.isLocal {
            var overlay = RosterOverlay.load(path: overlayPath).overlay
            var sessionId: String?
            switch change {
            case .archive, .pin:
                let roster = RosterDecoder.decode(try await agentsJSON())
                guard let row = roster.sessions.first(where: { $0.id == id }) else {
                    throw MarkError.noSuchSession(id)
                }
                sessionId = row.sessionId
            case .unarchive, .unpin:
                guard overlay.marks[id] != nil else { return "\(id) was not \(change == .unarchive ? "archived" : "pinned")" }
            }
            overlay.set(change, id: id, sessionId: sessionId)
            try overlay.save(path: overlayPath)
            return "\(change.pastTense) \(id)"
        }
        guard let argv = markArgv(change, id: id) else { throw MarkError.noRemoteCCC(host.name) }
        try prepareControlDirectory()
        let out = try await run(argv, program: "ccc")
        return String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public enum MarkError: Error, CustomStringConvertible {
        case noSuchSession(String)
        case noRemoteCCC(String)
        public var description: String {
            switch self {
            case .noSuchSession(let id): return "no session '\(id)' in the roster"
            case .noRemoteCCC(let host): return "marks live with the session's host, and \(host) has no ccc for them (`ccc hosts add \(host)` finds one)"
            }
        }
    }
}
