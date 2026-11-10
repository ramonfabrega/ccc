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

    /// A `claude` that answers with one background row in `cwd`, named
    /// `probe` — every ref in this suite therefore has two spellings, and
    /// the verb owes the same answer to both.
    private func stub(_ dir: URL, cwd: String, state: String = "done") throws -> ClaudeCLI {
        let claude = dir.appending(path: "claude").path
        let roster = """
        [{"id":"a1b2","cwd":"\(cwd)","kind":"background","startedAt":1756800000000,"name":"probe",\
        "state":"\(state)","status":"idle","sessionId":"a1b2c3d4-0000-0000-0000-000000000000"}]
        """
        try Data("#!/bin/sh\ncat <<'EOF'\n\(roster)\nEOF\n".utf8).write(to: URL(filePath: claude))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude)
        return ClaudeCLI(executable: claude, host: .local)
    }

    /// Whether a ccc is serving the control socket is a property of the
    /// Mac the suite happens to run on, so every arm below states it.
    private let serving: @Sendable () -> Bool = { true }

    @Test func armingWritesTheOverlayWithItsPromptAndUuid() async throws {
        try await withTemp { dir in
            let overlay = dir.appending(path: "roster.json").path
            let cli = try stub(dir, cwd: dir.path)
            let outcome = try await cli.clear(id: "a1b2", then: "carry on", overlayPath: overlay, serving: serving)
            #expect(outcome.armed)
            #expect(outcome.then == "carry on")
            let mark = RosterOverlay.load(path: overlay).overlay.mark(for: "a1b2", sessionId: nil)
            #expect(mark?.clear?.then == "carry on")
            // The uuid guard comes from the row, so the clear cannot land
            // on whatever session follows this one.
            #expect(mark?.sessionId == "a1b2c3d4-0000-0000-0000-000000000000")
        }
    }

    /// **The bug hail reported twice, both times as "the arm succeeds and
    /// nothing ever happens."** A `<ref>` has resolved by name since
    /// v0.1.31 — but only for the *reads*. The mark went into the overlay
    /// under the caller's word, and the poller joins marks on
    /// `session.id` alone, so a clear armed as `ccc clear desk` was filed
    /// where no row could see it: the pane found no row for "desk",
    /// called it gone, and dropped it on the next tick. The arm said
    /// `armed: true`, the list went empty within one poll, and the
    /// session was never cleared.
    ///
    /// The key is the ROW's id, and so is the `ref` in the answer — the
    /// caller gets back the spelling everything else on this Mac uses.
    @Test func armingByNameKeysTheMarkOnTheRowsId() async throws {
        try await withTemp { dir in
            let overlay = dir.appending(path: "roster.json").path
            let cli = try stub(dir, cwd: dir.path)
            let outcome = try await cli.clear(id: "probe", then: "carry on", overlayPath: overlay, serving: serving)
            #expect(outcome.armed)
            #expect(outcome.ref == "a1b2")
            #expect(outcome.said.contains("armed a clear on a1b2"))
            let loaded = RosterOverlay.load(path: overlay).overlay
            // The one reading that matters: the poller looks the mark up
            // by the row's id, and this is the lookup that answered nil.
            #expect(loaded.mark(for: "a1b2", sessionId: "a1b2c3d4-0000-0000-0000-000000000000")?.clear?.then == "carry on")
            #expect(loaded.marks["probe"] == nil)
        }
    }

    /// Cancel takes the name too, and still works on a row the roster has
    /// forgotten — which is the case it exists for, so the roster read is
    /// its fallback and not its road.
    @Test func cancelResolvesANameAndStillWorksWithoutARow() async throws {
        try await withTemp { dir in
            let overlay = dir.appending(path: "roster.json").path
            let cli = try stub(dir, cwd: dir.path)
            _ = try await cli.clear(id: "probe", overlayPath: overlay, serving: serving)
            let cancelled = try await cli.clear(id: "probe", cancel: true, overlayPath: overlay, serving: serving)
            #expect(cancelled.cancelled)
            #expect(cancelled.ref == "a1b2")
            #expect(RosterOverlay.load(path: overlay).overlay.armedClears.isEmpty)

            // A word that is already a key never asks the roster: arm by
            // id, then cancel it with a `claude` that could not answer.
            _ = try await cli.clear(id: "a1b2", overlayPath: overlay, serving: serving)
            let deaf = ClaudeCLI(executable: dir.appending(path: "no-such-claude").path, host: .local)
            let byId = try await deaf.clear(id: "a1b2", cancel: true, overlayPath: overlay, serving: serving)
            #expect(byId.cancelled)
        }
    }

    /// `--status`: "am I still armed?" with an answer that consumes
    /// nothing. Before it the only per-row question was `--cancel`, and
    /// attrition's commander asked that one four times across two tranches
    /// — no clear fired in either. Read twice, by name and by id, and the
    /// arm is still there for the firing side.
    @Test func statusReadsTheArmAndLeavesIt() async throws {
        try await withTemp { dir in
            let overlay = dir.appending(path: "roster.json").path
            let cli = try stub(dir, cwd: dir.path)
            let before = try await cli.clear(id: "probe", action: .status, overlayPath: overlay, serving: { false })
            #expect(!before.armed && before.ref == "a1b2" && before.said == "no clear is armed on a1b2", "\(before.said)")

            _ = try await cli.clear(id: "a1b2", then: "carry on", overlayPath: overlay, serving: serving)
            for word in ["probe", "a1b2"] {
                let status = try await cli.clear(id: word, action: .status, overlayPath: overlay, serving: { false })
                #expect(status.armed && status.ref == "a1b2" && status.then == "carry on" && !status.cancelled)
                #expect(status.armedAt != nil)
                #expect(status.said.hasPrefix("a clear is armed on a1b2 ("), "\(status.said)")
                // The row is idle and nothing is serving: the read says
                // that, where it used to say the constant "it fires when
                // the row is idle" whatever the row was doing.
                #expect(status.said.contains("); the row is idle, but no ccc is serving "), "\(status.said)")
                #expect(status.said.hasSuffix(", then: carry on"), "\(status.said)")
                #expect(status.waiting?.hasPrefix("no ccc is serving ") == true)
            }
            let served = try await cli.clear(id: "a1b2", action: .status, overlayPath: overlay, serving: serving, job: { _ in nil })
            #expect(served.said.hasSuffix("); the row is idle; it fires on the next tick, then: carry on"), "\(served.said)")
            #expect(served.waiting == nil)
            #expect(RosterOverlay.load(path: overlay).overlay.armedClears.map(\.id) == ["a1b2"])

            // What became of the last one rides along, so a fresh context
            // asking after a fire learns it fired.
            var loaded = RosterOverlay.load(path: overlay).overlay
            let uuid = "a1b2c3d4-0000-0000-0000-000000000000"
            loaded.record(ClearRecord(said: "cleared a1b2 and typed: carry on", fired: true), id: "a1b2", sessionId: uuid)
            loaded.arm(nil, id: "a1b2", sessionId: uuid)
            try loaded.save(path: overlay)
            let after = try await cli.clear(id: "a1b2", action: .status, overlayPath: overlay, serving: { false })
            #expect(!after.armed && after.last?.hasSuffix("cleared a1b2 and typed: carry on") == true, "\(after.said)")
        }
    }

    /// An arm is a promise that something types minutes from now, and the
    /// only things that can are the app and a headless attach — both of
    /// which serve the control socket. With neither up the mark would sit
    /// in the file unread until it was pruned, and the caller would never
    /// learn that: `armed: true` has to mean it can fire.
    @Test func armingIsRefusedWhenNothingWouldFireIt() async throws {
        try await withTemp { dir in
            let overlay = dir.appending(path: "roster.json").path
            let cli = try stub(dir, cwd: dir.path)
            var said = ""
            do { _ = try await cli.clear(id: "probe", overlayPath: overlay, serving: { false }) }
            catch { said = "\(error)" }
            #expect(said.contains("nothing would fire it"))
            #expect(said.contains("--headless"))
            #expect(RosterOverlay.load(path: overlay).overlay.armedClears.isEmpty)
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
            let nothing = try await cli.clear(id: "a1b2", cancel: true, overlayPath: overlay, serving: serving)
            #expect(!nothing.cancelled)
            #expect(nothing.said.contains("no clear was armed"))
            _ = try await cli.clear(id: "a1b2", overlayPath: overlay, serving: serving)
            let cancelled = try await cli.clear(id: "a1b2", cancel: true, overlayPath: overlay, serving: serving)
            #expect(cancelled.cancelled)
            #expect(RosterOverlay.load(path: overlay).overlay.armedClears.isEmpty)
        }
    }

    /// "A clear before the bank is committed is how state is lost": the
    /// verb refuses a dirty tree, and nothing is written.
    ///
    /// The git runs go through `Task.detached`, and that is not taste.
    /// `Git.run` blocks its thread on a semaphore until the pipe drains,
    /// and this is the suite's only *async* test that touches git — run
    /// inline it parks a thread of the cooperative pool, which wedged the
    /// whole suite intermittently the night this file was written
    /// (`docs/EVIDENCE.md` "the suite's own deadlock"). The same rule the
    /// production callers follow (`merge`, `push`, `update`, `fetch`).
    @Test func aDirtyWorktreeIsRefusedAndNothingIsArmed() async throws {
        try await withTemp { dir in
            let repo = dir.appending(path: "repo")
            try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
            let path = repo.path
            await Task.detached {
                _ = try? Git.run(WorktreeProbe.defaultGit, ["-C", path, "init", "-q"])
                _ = try? Git.run(WorktreeProbe.defaultGit, ["-C", path, "commit", "-q", "--allow-empty", "-m", "seed"])
            }.value
            try Data("half a thought\n".utf8).write(to: repo.appending(path: "bank.md"))
            await Task.detached { _ = try? Git.run(WorktreeProbe.defaultGit, ["-C", path, "add", "bank.md"]) }.value
            #expect(await Task.detached { ClearGuard.refusal(cwd: path) }.value != nil)

            let overlay = dir.appending(path: "roster.json").path
            let cli = try stub(dir, cwd: repo.path)
            var refused = false
            do { _ = try await cli.clear(id: "a1b2", overlayPath: overlay, serving: serving) }
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

    /// **The seven hours** (2026-11-10): steer armed a clear as its banking
    /// turn's last act, the turn closed with two asks, the daemon read the
    /// close as `blocked`, and the arm sat 7h35m printing "it fires when
    /// the row is idle". The row then was exactly the first shape below.
    /// Measured the same day on five owned fixtures, haiku and sonnet: an
    /// ask-ended turn and an open dialog are both `blocked` with `tempo:
    /// blocked`, and the roster's `status` / `waitingFor` is what tells
    /// them apart. The first fires; a dialog is never typed into.
    @Test func aTurnThatEndedOnAnAskFiresAndADialogWaits() {
        func row(_ status: Session.Status?, waitingFor: String? = nil) -> Session {
            Session(id: "a1b2", cwd: "/x", kind: .background, startedAt: Date(), state: .blocked,
                    status: status, waitingFor: waitingFor)
        }
        let asked = JobInfo(needs: "Which do you want me to do next, option A or option B?", tempo: "blocked")
        #expect(ClearWindow.read(row(.idle), job: asked) == .init(.now, "its turn ended on an ask"))
        // A parked worker carries no `status` at all, and is the same row.
        #expect(ClearWindow.of(row(nil), job: asked) == .now)

        // The two dialogs, as the roster spelled them.
        let question = ClearWindow.read(row(.waiting, waitingFor: "input needed"), job: JobInfo(tempo: "blocked"))
        #expect(question == .init(.wait, "a dialog is up (input needed)"))
        let permission = ClearWindow.read(row(.waiting, waitingFor: "permission prompt"), job: JobInfo(tempo: "blocked"))
        #expect(permission == .init(.wait, "a dialog is up (permission prompt)"))
        // Either field alone is a dialog: the two were not always sent
        // together, and a missing one must not read as "no dialog".
        #expect(ClearWindow.of(row(.waiting), job: asked) == .wait)
        #expect(ClearWindow.of(row(.idle, waitingFor: "dialog open"), job: asked) == .wait)

        // A stale `blocked` over a turn that is generating again
        // (docs/EVIDENCE.md "A mid-turn /clear discards the running turn").
        #expect(ClearWindow.read(row(.idle), job: JobInfo(tempo: "active")) == .init(.wait, "its turn is running"))
        // No job file: a blocked row is not ours to judge.
        #expect(ClearWindow.of(row(.idle), job: nil) == .wait)
        #expect(ClearWindow.of(row(.idle), job: JobInfo(tempo: "whatever-comes-next")) == .wait)
    }

    /// The gate otherwise. Without a job file a `blocked` row waits: the
    /// roster alone cannot say the turn is over.
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
        // A job file that says a question is up under a roster that has
        // not said which kind: wait for the roster.
        #expect(ClearWindow.of(busy, job: JobInfo(tempo: "blocked")) == .wait)
    }

    /// What `--status` and the bare listing say about an armed clear: the
    /// gate's reason, plus the three things the gate does not look at.
    @Test func theOutlookNamesWhatAnArmIsWaitingOn() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let mark = SessionMark(clear: PendingClear(armedAt: now.addingTimeInterval(-3 * 3600)), sessionId: "uuid-a")
        func row(_ state: Session.State, _ status: Session.Status?, waitingFor: String? = nil, uuid: String = "uuid-a") -> Session {
            Session(id: "a1b2", cwd: "/x", kind: .background, startedAt: Date(), state: state, status: status,
                    waitingFor: waitingFor, sessionId: uuid)
        }
        func outlook(_ row: Session?, job: JobInfo? = nil, read: Bool = true, serving: Bool = true) -> ClearOutlook {
            ClearOutlook.of(mark: mark, row: row, rosterRead: read, job: job, serving: serving, socket: "/s", now: now)
        }
        // The line steer needed at 08:24Z, with the one clock there is.
        let dialog = outlook(row(.blocked, .waiting, waitingFor: "permission prompt"),
                             job: JobInfo(updatedAt: now.addingTimeInterval(-2 * 3600), tempo: "blocked"))
        #expect(dialog.said == "waiting: a dialog is up (permission prompt), row last moved 2h ago")
        #expect(dialog.waiting == "a dialog is up (permission prompt), row last moved 2h ago")
        #expect(outlook(row(.working, .busy), job: JobInfo(tempo: "active")).said == "waiting: its turn is running")

        let free = outlook(row(.done, .idle), job: JobInfo(tempo: "idle"))
        #expect(free == ClearOutlook(said: "the row is idle; it fires on the next tick", waiting: nil))
        // Free, and nothing up to type: the other way an arm sits forever.
        let unserved = outlook(row(.done, .idle), job: JobInfo(tempo: "idle"), serving: false)
        #expect(unserved.said.hasPrefix("the row is idle, but no ccc is serving /s to fire it"))
        #expect(unserved.waiting != nil)

        #expect(outlook(nil).said == "it will be dropped: its session is off the roster")
        #expect(outlook(row(.done, .idle, uuid: "uuid-b")).said == "it will be dropped: another session answers to that id now")
        #expect(outlook(row(.stopped, nil)).said == "it will be dropped: its session was stopped")
        // A roster that could not be read: the old sentence, and no claim.
        #expect(outlook(nil, read: false) == ClearOutlook(said: "it fires when its turn ends", waiting: nil))
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

    // MARK: what the clear did

    /// The outcome is written back onto the mark, because the one who
    /// armed it cannot see the window's notice or the headless log — and
    /// after a clear that worked, does not remember arming. Three shapes,
    /// newest first, and `fired` is the bit a caller checks.
    @Test func everyOutcomeIsWrittenWhereAReaderCanFindIt() {
        var overlay = RosterOverlay()
        overlay.record(ClearRecord(at: Date(timeIntervalSince1970: 100), said: "cleared a1b2", fired: true),
                       id: "a1b2", sessionId: "uuid-a")
        overlay.record(ClearRecord(at: Date(timeIntervalSince1970: 200), said: "dropped the clear armed on c3d4: its session is gone", fired: false),
                       id: "c3d4", sessionId: nil)
        let recent = overlay.firedClears
        #expect(recent.map(\.id) == ["c3d4", "a1b2"])
        #expect(recent.first?.record.fired == false)
        // A record is not an empty mark: it survives the load that drops
        // marks with nothing on them, which is what makes it readable at
        // all — and it survives arming and disarming beside it.
        #expect(overlay.marks["a1b2"]?.isEmpty == false)
        overlay.arm(PendingClear(then: "again"), id: "a1b2", sessionId: "uuid-a")
        #expect(overlay.marks["a1b2"]?.fired?.said == "cleared a1b2")
        overlay.arm(nil, id: "a1b2", sessionId: "uuid-a")
        #expect(overlay.marks["a1b2"]?.fired?.fired == true)
    }

    /// One record per row meant the newest overwrote the rest — on steer's
    /// row a drop erased the three fires before it, on the day the
    /// question was what those three had in common. A row keeps its last
    /// eight, `fired` stays the newest, and **an arm on the session that
    /// follows a clear does not erase them**: a clear changes the uuid by
    /// design, so the uuid guard used to start every arm from nothing.
    @Test func aRowKeepsItsLastFewRecordsAcrossClears() {
        var overlay = RosterOverlay()
        for n in 1...3 {
            let uuid = "uuid-\(n)"
            overlay.arm(PendingClear(armedAt: Date(timeIntervalSince1970: Double(n) * 100)), id: "a1b2", sessionId: uuid)
            overlay.arm(nil, id: "a1b2", sessionId: uuid)
            overlay.record(ClearRecord(at: Date(timeIntervalSince1970: Double(n) * 100 + 4), said: "cleared a1b2 (\(n))", fired: true),
                           id: "a1b2", sessionId: uuid)
        }
        overlay.record(ClearRecord(at: Date(timeIntervalSince1970: 900), said: "dropped the clear armed on a1b2: another session answers to that id now", fired: false),
                       id: "a1b2", sessionId: "uuid-3")
        #expect(overlay.firedClears.map(\.record.said) == [
            "dropped the clear armed on a1b2: another session answers to that id now",
            "cleared a1b2 (3)", "cleared a1b2 (2)", "cleared a1b2 (1)",
        ])
        #expect(overlay.marks["a1b2"]?.fired?.fired == false)
        // An opinion about a session still does not follow the id.
        overlay.set(.pin, id: "a1b2", sessionId: "uuid-3")
        overlay.arm(PendingClear(), id: "a1b2", sessionId: "uuid-4")
        #expect(overlay.marks["a1b2"]?.pinned == nil)
        #expect(overlay.marks["a1b2"]?.records.count == 4)

        // Bounded: the ninth pushes the first out.
        for n in 5...12 {
            overlay.record(ClearRecord(at: Date(timeIntervalSince1970: Double(n) * 1000), said: "cleared a1b2 (\(n))", fired: true),
                           id: "a1b2", sessionId: "uuid-4")
        }
        let kept = overlay.marks["a1b2"]?.records.map(\.said) ?? []
        #expect(kept.count == SessionMark.recordsKept)
        #expect(kept.first == "cleared a1b2 (12)" && kept.last == "cleared a1b2 (5)")
    }

    /// An arm that waits past the bound says so once, with the reason,
    /// where the next reader finds it as `last:`. Not before the bound,
    /// not twice for one arm, and again for the arm after.
    @Test func aLongWaitIsWrittenDownOnce() {
        var overlay = RosterOverlay()
        let armedAt = Date(timeIntervalSince1970: 1_000)
        overlay.arm(PendingClear(armedAt: armedAt), id: "a1b2", sessionId: "uuid-a")
        #expect(overlay.noteWaiting(id: "a1b2", why: "its turn is running", now: armedAt.addingTimeInterval(599)) == nil)
        let note = overlay.noteWaiting(id: "a1b2", why: "a dialog is up (permission prompt)", now: armedAt.addingTimeInterval(601))
        #expect(note?.said == "the clear armed on a1b2 has waited 10m: a dialog is up (permission prompt)")
        #expect(note?.fired == false)
        #expect(overlay.marks["a1b2"]?.clear != nil)
        #expect(overlay.noteWaiting(id: "a1b2", why: "its turn is running", now: armedAt.addingTimeInterval(7 * 3600)) == nil)
        #expect(overlay.marks["a1b2"]?.records.count == 1)
        // Nothing armed, nothing to note.
        #expect(overlay.noteWaiting(id: "c3d4", why: "x", now: armedAt.addingTimeInterval(9_999)) == nil)

        let again = armedAt.addingTimeInterval(8 * 3600)
        overlay.arm(PendingClear(armedAt: again), id: "a1b2", sessionId: "uuid-a")
        #expect(overlay.noteWaiting(id: "a1b2", why: "its turn is running", now: again.addingTimeInterval(700)) != nil)
        #expect(overlay.marks["a1b2"]?.records.count == 2)
    }

    /// A clear that went over an ask quotes it, one line and bounded:
    /// the pane no longer shows the question, and the banner is gone.
    @Test func aClearOverAnAskQuotesIt() {
        #expect(ClearRecord.cleared("a1b2", then: nil) == "cleared a1b2")
        #expect(ClearRecord.cleared("a1b2", then: "carry on") == "cleared a1b2, then: carry on")
        #expect(ClearRecord.cleared("a1b2", then: "carry on", over: "Reap run 1560?\nAnd the kill rule?")
                == "cleared a1b2 over its ask (“Reap run 1560?”), then: carry on")
        #expect(ClearRecord.cleared("a1b2", then: nil, over: "  \n") == "cleared a1b2")
        let long = ClearRecord.cleared("a1b2", then: nil, over: String(repeating: "x", count: 300))
        #expect(long.count == "cleared a1b2 over its ask (“”)".count + 121)
    }

    /// It rides the file like every other mark, and an older ccc's
    /// overlay — one with no `fired` anywhere — still decodes.
    @Test func aRecordSurvivesTheFileAndItsAbsenceDoesToo() throws {
        try withTempSync { dir in
            let path = dir.appending(path: "roster.json").path
            var overlay = RosterOverlay()
            overlay.record(ClearRecord(said: "cleared a1b2, then: carry on", fired: true), id: "a1b2", sessionId: nil)
            try overlay.save(path: path)
            #expect(RosterOverlay.load(path: path).overlay.firedClears.first?.record.said
                    == "cleared a1b2, then: carry on")

            let old = #"{"marks":{"a1b2":{"archived":"2026-09-06T10:00:00Z"}}}"#
            try Data(old.utf8).write(to: URL(filePath: path))
            let loaded = RosterOverlay.load(path: path)
            #expect(loaded.issue == nil)
            #expect(loaded.overlay.marks["a1b2"]?.archived != nil)
            #expect(loaded.overlay.firedClears.isEmpty)
        }
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

    /// **A question dialog is not a hint.** Captured 2026-11-10 off a live
    /// AskUserQuestion (harness 2.1.321): the selected option is drawn
    /// `❯ 1. A` from column 0 with the cursor visible on column 0. Glyph,
    /// gap, text past the cursor — every mark of a hint, and `type` would
    /// have sent `/clear` and Enter into it, which picks option 1. The
    /// permission dialog indents its `❯` and never read as a box.
    @Test func aQuestionDialogsSelectedOptionIsNotAPromptBox() {
        let asking = grid("❯ 1. A", cursorCol: 0)
        #expect(PromptBox.read(asking) == .unreadable)
        #expect(PromptBox.read(asking).isOurs == false)
        #expect(PromptBox.whyUnreadable(asking) == "the cursor was at col 0, row 1 of 40x4, on \"❯ 1. A\"")
        #expect(PromptBox.read(grid("❯ 2. B", cursorCol: 1)) == .unreadable)
        #expect(PromptBox.read(grid(" ❯ 1. Yes", cursorCol: 1)) == .unreadable)
        // The same words in a real box, cursor on the prompt column.
        #expect(PromptBox.read(grid("❯ 1. A", cursorCol: 2)) == .hint("1. A"))
    }

    /// The refusal names which unreadable it was. attrition's two lost
    /// clears left only "cannot be read", which no fixture reproduced; the
    /// next one carries the cursor and the row it sat on.
    @Test func anUnreadableBoxSaysWhatItSaw() {
        #expect(PromptBox.whyUnreadable(grid("  some transcript line", cursorCol: 2))
                == "the cursor was at col 2, row 1 of 40x4, on \"some transcript line\"")
        var hidden = grid("❯\u{00A0}", cursorCol: 2)
        hidden.cursor.visible = false
        #expect(PromptBox.whyUnreadable(hidden).hasPrefix("the cursor was hidden (col 2, row 1 of 40x4"))
        let blank = Grid(cols: 10, rows: 4, lines: Array(repeating: "          ", count: 4),
                         cursor: Grid.Cursor(col: 0, row: 0, visible: true))
        #expect(PromptBox.whyUnreadable(blank) == "the pane had not drawn (0 painted rows)")
        let long = String(repeating: "x", count: 80)
        var wide = grid("", cursorCol: 0)
        wide.lines[1] = long
        #expect(PromptBox.whyUnreadable(wide).hasSuffix(String(repeating: "x", count: 60) + "…\""))
    }

    /// `>` and `!` are prompts too (the plain-ASCII terminal, bash mode),
    /// the way `LeaveGesture` reads them.
    @Test func everyPromptGlyphReads() {
        for glyph in LeaveGesture.prompts {
            #expect(PromptBox.read(grid("\(glyph) go", cursorCol: 5)) == .draft("go"))
        }
    }

}
