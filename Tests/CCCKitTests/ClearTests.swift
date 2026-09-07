import Foundation
import Testing

@testable import CCCKit

/// `ccc clear` (item 27): the arm, its guards, and the two readings the
/// firing side depends on — is the row idle, and is the prompt box ours.
@Suite struct ClearTests {
    private func withTemp(_ body: (URL) async throws -> Void) async throws {
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "ccc-clear-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir)
    }

    private func withTempSync(_ body: (URL) throws -> Void) throws {
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "ccc-clear-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    /// A `claude` that answers with one background row in `cwd`.
    private func stub(_ dir: URL, cwd: String, state: String = "done") throws -> ClaudeCLI {
        let claude = dir.appending(path: "claude").path
        let roster = """
        [{"id":"a1b2","cwd":"\(cwd)","kind":"background","startedAt":1756800000000,\
        "state":"\(state)","status":"idle","sessionId":"a1b2c3d4-0000-0000-0000-000000000000"}]
        """
        try Data("#!/bin/sh\ncat <<'EOF'\n\(roster)\nEOF\n".utf8).write(to: URL(filePath: claude))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude)
        return ClaudeCLI(executable: claude, host: .local)
    }

    @Test func armingWritesTheOverlayWithItsPromptAndUuid() async throws {
        try await withTemp { dir in
            let overlay = dir.appending(path: "roster.json").path
            let cli = try stub(dir, cwd: dir.path)
            let outcome = try await cli.clear(id: "a1b2", then: "carry on", overlayPath: overlay)
            #expect(outcome.armed)
            #expect(outcome.then == "carry on")
            let mark = RosterOverlay.load(path: overlay).overlay.mark(for: "a1b2", sessionId: nil)
            #expect(mark?.clear?.then == "carry on")
            // The uuid guard comes from the row, so the clear cannot land
            // on whatever session follows this one.
            #expect(mark?.sessionId == "a1b2c3d4-0000-0000-0000-000000000000")
        }
    }

    /// The mark carries the uuid the row had when it was armed, and a
    /// clear mints a new one — so a pending clear never applies to the
    /// session on the other side of a clear.
    @Test func aPendingClearDoesNotApplyAcrossANewSessionUuid() throws {
        var overlay = RosterOverlay()
        overlay.arm(PendingClear(then: "go"), id: "a1b2", sessionId: "before")
        #expect(overlay.mark(for: "a1b2", sessionId: "before")?.clear != nil)
        #expect(overlay.mark(for: "a1b2", sessionId: "after") == nil)
    }

    @Test func cancelSaysWhetherItCancelledAnything() async throws {
        try await withTemp { dir in
            let overlay = dir.appending(path: "roster.json").path
            let cli = try stub(dir, cwd: dir.path)
            let nothing = try await cli.clear(id: "a1b2", cancel: true, overlayPath: overlay)
            #expect(!nothing.cancelled)
            #expect(nothing.said.contains("no clear was armed"))
            _ = try await cli.clear(id: "a1b2", overlayPath: overlay)
            let cancelled = try await cli.clear(id: "a1b2", cancel: true, overlayPath: overlay)
            #expect(cancelled.cancelled)
            #expect(RosterOverlay.load(path: overlay).overlay.armedClears.isEmpty)
        }
    }

    /// "A clear before the bank is committed is how state is lost": the
    /// verb refuses a dirty tree, and nothing is written.
    @Test func aDirtyWorktreeIsRefusedAndNothingIsArmed() async throws {
        try await withTemp { dir in
            let repo = dir.appending(path: "repo")
            try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
            _ = try? Git.run(WorktreeProbe.defaultGit, ["-C", repo.path, "init", "-q"])
            _ = try? Git.run(WorktreeProbe.defaultGit, ["-C", repo.path, "commit", "-q", "--allow-empty", "-m", "seed"])
            try Data("half a thought\n".utf8).write(to: repo.appending(path: "bank.md"))
            _ = try? Git.run(WorktreeProbe.defaultGit, ["-C", repo.path, "add", "bank.md"])
            #expect(ClearGuard.refusal(cwd: repo.path) != nil)

            let overlay = dir.appending(path: "roster.json").path
            let cli = try stub(dir, cwd: repo.path)
            var refused = false
            do { _ = try await cli.clear(id: "a1b2", overlayPath: overlay) }
            catch { refused = "\(error)".contains("uncommitted") }
            #expect(refused)
            #expect(RosterOverlay.load(path: overlay).overlay.armedClears.isEmpty)
        }
    }

    @Test func aCleanTreeAndNoGitAtAllBothPass() throws {
        try withTempSync { dir in
            #expect(ClearGuard.refusal(cwd: dir.path) == nil)   // not a repo
            let repo = dir.appending(path: "clean")
            try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
            _ = try? Git.run(WorktreeProbe.defaultGit, ["-C", repo.path, "init", "-q"])
            _ = try? Git.run(WorktreeProbe.defaultGit, ["-C", repo.path, "commit", "-q", "--allow-empty", "-m", "seed"])
            #expect(ClearGuard.refusal(cwd: repo.path) == nil)
        }
    }

    /// The gate. `blocked` is a session holding a question up, and the box
    /// under that question answers it — never our seat.
    @Test func onlyAnIdleBackgroundRowIsOurSeat() {
        func session(_ state: Session.State?, _ status: Session.Status?, kind: Session.Kind = .background) -> Session {
            Session(id: "a1b2", cwd: "/x", kind: kind, startedAt: Date(), state: state, status: status)
        }
        #expect(ClearWindow.of(session(.done, .idle)) == .now)
        #expect(ClearWindow.of(session(.working, .idle)) == .now)
        #expect(ClearWindow.of(session(.working, .busy)) == .wait)
        #expect(ClearWindow.of(session(.blocked, .idle)) == .wait)
        #expect(ClearWindow.of(session(.blocked, .waiting)) == .wait)
        #expect(ClearWindow.of(session(.done, nil)) == .wait)
        #expect(ClearWindow.of(session(.failed, .idle)) == .gone)
        #expect(ClearWindow.of(session(.stopped, .idle)) == .gone)
        #expect(ClearWindow.of(session(.done, .idle, kind: .interactive)) == .gone)
    }

    /// The regression that made the verb useless to its first real user
    /// within an hour of shipping. A commander holding a persistent
    /// Monitor reads `status: busy` for as long as it holds it, and the
    /// question the gate is asking — is the TURN over — is `tempo`.
    /// Measured on the two live rows (docs/EVIDENCE.md "item 27 — the gate
    /// read the wrong field"): attrition `status=busy tempo=idle` with
    /// three tasks in flight, lore `status=idle tempo=idle` with none.
    @Test func aBusyRowWhoseTurnIsOverIsStillOurSeat() {
        let busy = Session(id: "a1b2", cwd: "/x", kind: .background, startedAt: Date(),
                           state: .done, status: .busy)
        #expect(ClearWindow.of(busy, job: JobInfo(tempo: "idle")) == .now)
        #expect(ClearWindow.of(busy, job: JobInfo(tempo: "active")) == .wait)
        // A word this build has not met is "not idle", never a fire.
        #expect(ClearWindow.of(busy, job: JobInfo(tempo: "whatever-comes-next")) == .wait)
        // `blocked` still comes from the roster and outranks any tempo.
        let blocked = Session(id: "a1b2", cwd: "/x", kind: .background, startedAt: Date(),
                              state: .blocked, status: .idle)
        #expect(ClearWindow.of(blocked, job: JobInfo(tempo: "idle")) == .wait)
    }

    /// No job file, or one from a ccc across the hop that predates
    /// `tempo`: the daemon's coarser word stands. It never fires early —
    /// it only ever waits too long.
    @Test func withoutATempoTheDaemonsWordStands() {
        func row(_ status: Session.Status) -> Session {
            Session(id: "a1b2", cwd: "/x", kind: .background, startedAt: Date(), state: .done, status: status)
        }
        #expect(ClearWindow.of(row(.idle), job: nil) == .now)
        #expect(ClearWindow.of(row(.busy), job: nil) == .wait)
        #expect(ClearWindow.of(row(.idle), job: JobInfo(detail: "no tempo in this reading")) == .now)
        #expect(ClearWindow.of(row(.busy), job: JobInfo(detail: "no tempo in this reading")) == .wait)
    }

    /// `tempo` survives the wire between two builds of ccc, which is what
    /// a remote row rides home on.
    @Test func tempoCrossesTheHop() throws {
        let info = JobInfo(detail: "d", tempo: "idle")
        let wire = try JSONEncoder().encode(info)
        #expect(try JSONDecoder().decode(JobInfo.self, from: wire).tempo == "idle")
        // And out of the harness's own file, which is where it starts.
        let file = Data(#"{"detail":"d","tempo":"idle","inFlight":{"tasks":3}}"#.utf8)
        #expect(JobInfo.decode(file)?.tempo == "idle")
        // A file with no tempo says nothing rather than "idle".
        #expect(JobInfo.decode(Data(#"{"detail":"d"}"#.utf8))?.tempo == nil)
    }

    // MARK: the prompt box

    private func grid(_ line: String, cursorCol: Int, rows: Int = 4) -> Grid {
        var lines = Array(repeating: String(repeating: " ", count: 40), count: rows)
        lines[1] = line.padding(toLength: 40, withPad: " ", startingAt: 0)
        lines[2] = "status line".padding(toLength: 40, withPad: " ", startingAt: 0)
        return Grid(cols: 40, rows: rows, lines: lines,
                    cursor: Grid.Cursor(col: cursorCol, row: 1, visible: true))
    }

    /// Measured 2026-09-06 on a live background session: the harness drew
    /// `cat marker.txt` in the box and left the cursor on the prompt
    /// column through `end` and `ctrl-u`; the next character typed
    /// replaced the whole thing. That is a hint, and it is ours.
    @Test func aHintIsOursAndADraftIsNot() {
        #expect(PromptBox.read(grid("❯\u{00A0}", cursorCol: 2)) == .empty)
        #expect(PromptBox.read(grid("❯\u{00A0}cat marker.txt", cursorCol: 2)) == .hint("cat marker.txt"))
        #expect(PromptBox.read(grid("❯\u{00A0}ZZ", cursorCol: 4)) == .draft("ZZ"))
        #expect(PromptBox.read(grid("❯\u{00A0}ZZ", cursorCol: 4)).isOurs == false)
        #expect(PromptBox.read(grid("❯\u{00A0}cat marker.txt", cursorCol: 2)).isOurs)
    }

    /// Fails closed: a row that is not an input box, an invisible cursor
    /// (a dialog), and a pane that has not painted are all "not ours".
    @Test func anythingUnreadableIsNotOurs() {
        #expect(PromptBox.read(grid("  some transcript line", cursorCol: 2)) == .unreadable)
        var hidden = grid("❯\u{00A0}", cursorCol: 2)
        hidden.cursor.visible = false
        #expect(PromptBox.read(hidden) == .unreadable)
        let blank = Grid(cols: 10, rows: 4, lines: Array(repeating: "          ", count: 4),
                         cursor: Grid.Cursor(col: 0, row: 0, visible: true))
        #expect(PromptBox.read(blank) == .unreadable)
        #expect(PromptBox.read(blank).isOurs == false)
    }

    /// `>` and `!` are prompts too (the plain-ASCII terminal, bash mode),
    /// the way `LeaveGesture` reads them.
    @Test func everyPromptGlyphReads() {
        for glyph in LeaveGesture.prompts {
            #expect(PromptBox.read(grid("\(glyph) go", cursorCol: 5)) == .draft("go"))
        }
    }

}
