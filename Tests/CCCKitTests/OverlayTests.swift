import Foundation
import Testing

@testable import CCCKit

/// The overlay (v4): the one file of ours laid over the daemon's roster.
/// Hand-editable like `hosts.json`, so the lenient rule applies — a broken
/// file is no marks and a note, never no rows — and keyed by the short id
/// with the session's uuid as the guard against a reused one.
@Suite struct OverlayTests {
    private func withTempPath(_ body: (String) throws -> Void) throws {
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "ccc-overlay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir.appending(path: "roster.json").path)
    }

    @Test func noFileIsNoMarks() throws {
        try withTempPath { path in
            let loaded = RosterOverlay.load(path: path)
            #expect(loaded.overlay.marks.isEmpty)
            #expect(loaded.issue == nil)
        }
    }

    @Test func marksSurviveTheFile() throws {
        try withTempPath { path in
            var overlay = RosterOverlay()
            let when = Date(timeIntervalSince1970: 1_756_800_000)
            overlay.set(.archive, id: "a1b2", sessionId: "uuid-a", at: when)
            overlay.set(.pin, id: "c3d4", sessionId: nil, at: when)
            try overlay.save(path: path)
            let loaded = RosterOverlay.load(path: path)
            #expect(loaded.issue == nil)
            #expect(loaded.overlay == overlay)
            #expect(loaded.overlay.mark(for: "a1b2", sessionId: "uuid-a")?.archived == when)
            #expect(loaded.overlay.mark(for: "c3d4", sessionId: "anything")?.pinned == when)
            #expect(loaded.modifiedAt != nil)
        }
    }

    /// The file is ours to break by hand. The roster must not notice
    /// beyond one sentence.
    @Test func aBrokenFileIsANoteAndNoMarks() throws {
        try withTempPath { path in
            try Data("{ not json".utf8).write(to: URL(filePath: path))
            let loaded = RosterOverlay.load(path: path)
            #expect(loaded.overlay.marks.isEmpty)
            #expect(loaded.issue?.contains("ignoring the overlay") == true)
        }
    }

    /// A short id the daemon minted twice: the old session's mark must not
    /// land on the new one.
    @Test func aMarkOnAnEarlierSessionDoesNotApply() {
        var overlay = RosterOverlay()
        overlay.set(.archive, id: "a1b2", sessionId: "old-uuid")
        #expect(overlay.mark(for: "a1b2", sessionId: "new-uuid") == nil)
        #expect(overlay.mark(for: "a1b2", sessionId: "old-uuid") != nil)
        // A row with no uuid of its own cannot disagree.
        #expect(overlay.mark(for: "a1b2", sessionId: nil) != nil)
        // Marking the new session replaces the old mark rather than merging.
        overlay.set(.pin, id: "a1b2", sessionId: "new-uuid")
        let mark = overlay.mark(for: "a1b2", sessionId: "new-uuid")
        #expect(mark?.pinned != nil)
        #expect(mark?.archived == nil)
        #expect(mark?.sessionId == "new-uuid")
    }

    @Test func undoingTheLastMarkDropsTheEntry() {
        var overlay = RosterOverlay()
        overlay.set(.archive, id: "a1b2", sessionId: nil)
        overlay.set(.pin, id: "a1b2", sessionId: nil)
        overlay.set(.unarchive, id: "a1b2", sessionId: nil)
        #expect(overlay.marks["a1b2"]?.pinned != nil)
        #expect(overlay.marks["a1b2"]?.archived == nil)
        overlay.set(.unpin, id: "a1b2", sessionId: nil)
        #expect(overlay.marks["a1b2"] == nil)
    }

    /// Done rows leave the roster when the daemon recycles their worker;
    /// a week after that, the mark goes too. A host that is merely asleep
    /// never reaches this: pruning happens on a good poll of the host that
    /// owns the file.
    @Test func pruningForgetsOldMarksOnSessionsTheRosterLost() {
        let now = Date()
        var overlay = RosterOverlay()
        overlay.set(.archive, id: "gone-old", sessionId: nil, at: now.addingTimeInterval(-8 * 86_400))
        overlay.set(.archive, id: "gone-new", sessionId: nil, at: now.addingTimeInterval(-3600))
        overlay.set(.pin, id: "here-old", sessionId: nil, at: now.addingTimeInterval(-30 * 86_400))
        let dropped = overlay.prune(keeping: ["here-old"], now: now)
        #expect(dropped)
        #expect(Set(overlay.marks.keys) == ["gone-new", "here-old"])
        let droppedAgain = overlay.prune(keeping: ["here-old"], now: now)
        #expect(!droppedAgain)
    }

    @Test func aRemoteMarkIsTheSameVerbOnTheFarSidesCCC() {
        let host = Host(name: "studio", ssh: "studio", claude: "~/.local/bin/claude", ccc: "/opt/homebrew/bin/ccc")
        let cli = ClaudeCLI(executable: "~/.local/bin/claude", host: host)
        #expect(cli.markArgv(.archive, id: "a1b2")?.suffix(3) == ["/opt/homebrew/bin/ccc", "archive", "a1b2"])
        #expect(cli.markArgv(.unpin, id: "a1b2")?.contains("ControlPath=\(cli.sshControlPath)") == true)
        // No ccc there: nowhere to keep a mark, and the verb says so.
        let bare = ClaudeCLI(executable: "~/.local/bin/claude", host: Host(name: "air", ssh: "air", claude: "~/.local/bin/claude"))
        #expect(bare.markArgv(.archive, id: "a1b2") == nil)
    }

    /// Rows keep their marks across the wire, and an older ccc's rows —
    /// which carry no such keys — still decode as unmarked.
    @Test func marksCrossTheHopAndDefaultOff() throws {
        let session = Session(id: "a1b2", cwd: "/x", kind: .background, startedAt: Date(timeIntervalSince1970: 1_756_800_000),
                              state: .done)
        let row = SessionRow(session: session, model: nil, attached: false, archived: true, pinned: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let back = try JSONDecoder.roster.decode([SessionRow].self, from: encoder.encode([row]))
        #expect(back[0].archived && back[0].pinned)
        let older = Data(#"[{"session":{"id":"a1b2","cwd":"/x","kind":"background","startedAt":"2026-09-02T07:20:04.000Z","state":"done","extra":{}}}]"#.utf8)
        let decoded = try JSONDecoder.roster.decode([SessionRow].self, from: older)
        #expect(!decoded[0].archived && !decoded[0].pinned)
    }

    /// The v4 rule: archived is out of the default list, unless it is
    /// asking for input.
    @Test func blockedIsNeverHidden() {
        func row(_ state: Session.State, archived: Bool) -> SessionRow {
            SessionRow(session: Session(id: "x", cwd: "/", kind: .background, startedAt: Date(), state: state),
                       model: nil, attached: false, archived: archived)
        }
        #expect(row(.done, archived: true).isHidden)
        #expect(!row(.blocked, archived: true).isHidden)
        #expect(!row(.done, archived: false).isHidden)
    }
}
