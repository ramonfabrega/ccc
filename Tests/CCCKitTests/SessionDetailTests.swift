import Foundation
import Testing

@testable import CCCKit

/// `ccc show`'s content (`SessionDetail`): the row with the cuts taken
/// out.
@Suite struct SessionDetailTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func row(state: Session.State? = .working, status: Session.Status? = nil, pid: Int32? = 1,
                     kind: Session.Kind = .background, waitingFor: String? = nil, host: String = Host.localName,
                     draft: Bool = false, worktree: WorktreeInfo? = nil, job: JobInfo? = nil) -> SessionRow {
        SessionRow(session: Session(id: "a1b2c3d4", cwd: "/Users/x/code/a", kind: kind,
                                    startedAt: now.addingTimeInterval(-7200), state: state, status: status, pid: pid,
                                    waitingFor: waitingFor, sessionId: "0000-full", name: "lane"),
                   host: host, model: "claude-opus-5-5", attached: false, draft: draft, worktree: worktree, job: job)
    }

    private func detail(_ row: SessionRow, showsHost: Bool = false) -> SessionDetail {
        SessionDetail(row: row, showsHost: showsHost, now: now, calendar: utc) { $0.replacingOccurrences(of: "/Users/x", with: "~") }
    }

    /// The whole reason the pane exists: the row cuts this at about sixty
    /// characters, and a result runs to 460.
    @Test func aFinishedRowCarriesItsResultWhole() {
        let long = String(repeating: "Tree tint now matches the photograph. ", count: 12)
        let d = detail(row(state: .done, pid: nil, job: JobInfo(detail: "tint matches", result: long)))
        #expect(d.passages.map(\.title) == ["result"])
        #expect(d.passages[0].text == long.trimmingCharacters(in: .whitespaces))
        #expect(d.state == "done")
        #expect(d.tone == .gone)
    }

    /// `suggestedReply` was read from the job file for two months and
    /// drawn nowhere (docs/QUEUE.md's open question). It is drawn here,
    /// and only under a question.
    @Test func aBlockedRowAsksAndOffersTheSuggestedReply() {
        let job = JobInfo(detail: "waiting on a go-ahead", needs: "Merge PR #50?", suggestedReply: "yes, merge it")
        let d = detail(row(state: .blocked, status: .waiting, job: job))
        #expect(d.passages.map(\.kind) == [.say, .reply])
        #expect(d.passages.map(\.title) == ["asking", "suggested reply"])
        #expect(d.passages[1].text == "yes, merge it")
        #expect(d.tone == .waiting)
        // Not under a result: a reply to a question nobody is asking.
        let done = detail(row(state: .done, job: JobInfo(result: "merged", suggestedReply: "yes, merge it")))
        #expect(done.passages.map(\.kind) == [.say])
    }

    /// A paraphrase is not a second fact. The first build printed `detail`
    /// under every `result` and it said the same thing twice.
    @Test func theLiveLineIsNotRepeatedUnderTheFieldTheStateOwns() {
        let d = detail(row(state: .done, job: JobInfo(detail: "branch ready, 3 parked", result: "The branch is ready.")))
        #expect(d.passages.count == 1)
        #expect(d.passages[0].text == "The branch is ready.")
    }

    /// The roster's `waitingFor` is the fallback, not a second line: a
    /// blocked row whose job file is silent still says what it waits on.
    @Test func aBlockedRowWithNoJobFileStillSaysWhatTheRosterSaid() {
        let d = detail(row(state: .blocked, waitingFor: "permission: Bash"))
        #expect(d.passages.map(\.text) == ["permission: Bash"])
    }

    @Test func aDraftSaysNothingAndReadsAsADraft() {
        let d = detail(row(state: .blocked, draft: true, job: JobInfo(needs: "send a prompt to start")))
        #expect(d.passages.isEmpty)
        #expect(d.state == "draft · send a prompt to start")
        #expect(d.tone == .draft)
    }

    /// Every fact carries payload for *this* row or is not listed — the
    /// rule the banner earned (CLAUDE.md), applied where there is room to
    /// break it.
    @Test func onlyFactsThatSaySomethingAreListed() {
        let plain = detail(row(state: .done, pid: nil, job: JobInfo(result: "ok", remoteControl: false)))
        #expect(plain.facts.map(\.label) == ["folder", "started", "id"])

        let wt = WorktreeInfo(branch: "worktree-v2", base: "master", ahead: 3, behind: 1, repo: "/Users/x/code/a", unpushed: 2)
        let job = JobInfo(detail: "running", remoteControl: false, permissionMode: "plan",
                          updatedAt: now.addingTimeInterval(-720))
        let full = detail(row(state: .working, host: "studio", worktree: wt, job: job), showsHost: true)
        #expect(full.facts.map(\.label) == ["branch", "stands", "folder", "host", "started", "moved", "answer", "asks", "id"])
        let fact = { (label: String) in full.facts.first { $0.label == label } }
        #expect(fact("branch")?.value == "worktree-v2 → master")
        #expect(fact("branch")?.note == nil)
        #expect(fact("stands")?.value == "3 ahead, 1 behind (master moved), 2 unpushed")
        #expect(fact("folder")?.value == "~/code/a")
        #expect(fact("folder")?.full == "/Users/x/code/a")
        #expect(fact("moved")?.value == "12m ago")
        #expect(fact("answer")?.value == "only on studio")
        #expect(fact("asks")?.value == "--permission-mode plan")
        #expect(fact("id")?.value == "studio:a1b2c3d4")
        #expect(fact("id")?.full == "0000-full")
    }

    /// Remote Control is news only when it is off on a session that could
    /// still ask: `ccc spawn` defaults it on, and a finished row will
    /// never need answering from anywhere.
    @Test func remoteControlIsSaidOnlyWhenItIsOffAndLive() {
        let on = detail(row(state: .working, job: JobInfo(detail: "x", remoteControl: true)))
        #expect(!on.facts.contains { $0.label == "answer" })
        let offDone = detail(row(state: .done, job: JobInfo(result: "x", remoteControl: false)))
        #expect(!offDone.facts.contains { $0.label == "answer" })
        let offLive = detail(row(state: .blocked, job: JobInfo(needs: "x", remoteControl: false)))
        #expect(offLive.facts.first { $0.label == "answer" }?.value == "only on this Mac")
    }

    @Test func anInteractiveSessionSaysItCannotBeAttached() {
        let d = detail(row(state: nil, kind: .interactive))
        #expect(!d.attachable)
        #expect(d.facts.first { $0.label == "kind" }?.value == "interactive")
        #expect(d.tone == .live)
    }

    /// What `ccc show` prints. Read here because a string no test reads
    /// is a string nothing keeps true.
    @Test func theTextRenderingIsTheHeaderTheProseThenTheFacts() {
        let job = JobInfo(needs: "Merge PR #50?\nIt is green.", suggestedReply: "yes")
        let text = detail(row(state: .blocked, status: .waiting, job: job)).text
        #expect(text == """
        lane  blocked · waiting  opus-5-5

        asking
          Merge PR #50?
          It is green.

        suggested reply
          yes

        folder   ~/code/a
        started  06:00
        answer   only on this Mac · dispatched without Remote Control
        id       a1b2c3d4
        """)
    }

    /// The row's dot and the pane's header read one mapping.
    @Test func toneIsOneDefinition() {
        #expect(row(state: .working, status: .busy).tone == .busy)
        #expect(row(state: .working, status: .idle).tone == .working)
        #expect(row(state: .failed).tone == .failed)
        #expect(row(state: .done, pid: 7).tone == .rested)
        #expect(row(state: .stopped, pid: nil).tone == .gone)
        #expect(row(state: nil, pid: nil).tone == .unknown)
        #expect(row(state: .working, status: .busy).stateText == "working · busy")
    }

    /// The roster row's second line (2026-11-13) says a state only where
    /// the dot does not: the words repeated its colour on 13 rows of 13.
    @Test func theRowSaysAStateOnlyWhereTheDotDoesNot() {
        #expect(row(state: .working, status: .busy).stateWord == nil)
        #expect(row(state: .blocked, job: JobInfo(needs: "Merge?")).stateWord == nil)
        #expect(row(state: .blocked, waitingFor: "input needed").stateWord == nil)
        // Asking, with nothing on the row to show for it: say so.
        #expect(row(state: .blocked).stateWord == "blocked")
        #expect(row(state: .done, status: .idle).stateWord == "done")
        #expect(row(state: .stopped, pid: nil).stateWord == "stopped")
        #expect(row(state: .failed).stateWord == "failed")
        #expect(row(state: .blocked, draft: true).stateWord == "draft · send a prompt to start")
        #expect(row(state: nil, kind: .interactive).stateWord == "interactive")
    }

    /// One definition for the row's mark and the pane's `answer` line.
    @Test func lackingRemoteControlIsNewsOnlyOnALiveBackgroundSession() {
        #expect(row(state: .working, job: JobInfo(detail: "x", remoteControl: false)).lacksRemoteControl)
        #expect(row(state: .blocked, job: JobInfo(needs: "x", remoteControl: false)).lacksRemoteControl)
        #expect(!row(state: .working, job: JobInfo(detail: "x", remoteControl: true)).lacksRemoteControl)
        #expect(!row(state: .done, job: JobInfo(result: "x", remoteControl: false)).lacksRemoteControl)
        // No job file read is "I don't know", not "no".
        #expect(!row(state: .working).lacksRemoteControl)
        #expect(!row(state: nil, kind: .interactive, job: JobInfo(detail: "x")).lacksRemoteControl)
    }

    /// The row's folder is one word and its branch drops the harness's
    /// prefix: at 370 pt the old row read `wor…t-4204` and `…fun/attrition`.
    @Test func theRowNamesItsFolderAndBranchInAWordEach() {
        let short = { (path: String) in path.replacingOccurrences(of: "/Users/x", with: "~") }
        #expect(row().folderName(shortCwd: short) == "a")
        let wt = WorktreeInfo(branch: "worktree-att-4204", base: "master", ahead: 0, behind: 0, repo: "/Users/x/code/fun/attrition")
        #expect(row(worktree: wt).folderName(shortCwd: short) == "attrition")
        #expect(wt.shortBranch == "att-4204")
        #expect(WorktreeInfo(branch: "recorder", base: "master", ahead: 0, behind: 0, repo: "/r").shortBranch == "recorder")
        // A branch that is only the prefix is left alone rather than emptied.
        #expect(WorktreeInfo(branch: "worktree-", base: "master", ahead: 0, behind: 0, repo: "/r").shortBranch == "worktree-")
        var home = row()
        home.session.cwd = "/Users/x"
        #expect(home.folderName(shortCwd: short) == "~")
    }

    /// lore's ladder, inherited so the two apps say a moment the same
    /// way: the relative form lives one hour and no longer.
    @Test func stampsFollowTheLadder() {
        func stamp(_ ago: TimeInterval) -> String { Stamp.text(now.addingTimeInterval(-ago), now: now, calendar: utc) }
        // `now` is 2027-01-15 08:00:00 UTC.
        #expect(stamp(5) == "now")
        #expect(stamp(59) == "now")
        #expect(stamp(60) == "1m ago")
        #expect(stamp(59 * 60) == "59m ago")
        #expect(stamp(3600) == "07:00")
        #expect(stamp(7 * 3600 + 59 * 60) == "00:01")
        #expect(stamp(9 * 3600) == "yest")
        #expect(stamp(40 * 3600) == "13 jan")
        #expect(stamp(40 * 86400) == "6 dec")
    }
}

/// `PaneClock`: the rate the empty pane was first built into without — how much of
/// the window's time on screen the pane has no session in it.
@Suite struct PaneClockTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    @Test func timeIsSplitByWhatThePaneHeld() {
        var clock = PaneClock()
        clock.set(visible: true, at: at(0))
        clock.set(attached: true, at: at(30))
        clock.set(attached: false, at: at(120))
        let stats = clock.stats(at: at(130))
        #expect(stats.readingSeconds == 40)
        #expect(stats.attachedSeconds == 90)
        #expect(stats.readingShare == 40.0 / 130.0)
    }

    /// ccc is menubar-resident: a closed window's pane is empty all night
    /// and nobody is looking at it.
    @Test func aWindowNobodyCanSeeCountsForNothing() {
        var clock = PaneClock()
        clock.set(visible: true, at: at(0))
        clock.set(visible: false, at: at(10))
        clock.set(attached: true, at: at(500))
        clock.set(visible: true, at: at(1000))
        let stats = clock.stats(at: at(1005))
        #expect(stats.readingSeconds == 10)
        #expect(stats.attachedSeconds == 5)
    }

    /// A reading does not move the clock: asking twice is the same answer
    /// plus the time between.
    @Test func readingTheClockDoesNotCloseIt() {
        var clock = PaneClock()
        clock.set(visible: true, at: at(0))
        #expect(clock.stats(at: at(5)).readingSeconds == 5)
        #expect(clock.stats(at: at(9)).readingSeconds == 9)
        clock.set(attached: true, at: at(10))
        #expect(clock.stats(at: at(12)) == PaneTimeStats(attachedSeconds: 2, readingSeconds: 10, rowsRead: 0))
    }

    /// The 2 s poll redraws the same row all day; that is one read. A row
    /// behind a session, or in a window off screen, is not read at all.
    @Test func aRowIsReadOncePerStay() {
        let a = SessionRef(host: Host.localName, id: "a"), b = SessionRef(host: Host.localName, id: "b")
        var clock = PaneClock()
        clock.read(a)
        #expect(clock.stats(at: t0).rowsRead == 0)
        clock.set(visible: true, at: t0)
        clock.read(a)
        clock.read(a)
        clock.read(nil)
        clock.read(b)
        clock.read(a)
        #expect(clock.stats(at: t0).rowsRead == 3)
        clock.set(attached: true, at: t0)
        clock.read(b)
        #expect(clock.stats(at: t0).rowsRead == 3)
        // Back from the session to the row it was left on: a second look.
        clock.set(attached: false, at: t0)
        clock.read(a)
        #expect(clock.stats(at: t0).rowsRead == 4)
    }

    @Test func theStatsLineSaysTheShareAndIsAbsentBeforeAnyScreenTime() {
        #expect(PaneTimeStats(attachedSeconds: 0, readingSeconds: 0, rowsRead: 0).line == nil)
        let line = PaneTimeStats(attachedSeconds: 41 * 60, readingSeconds: 9 * 60, rowsRead: 14).line
        #expect(line == "window  attached 41m · reading 9m (18%) · 14 rows read")
        #expect(PaneTimeStats(attachedSeconds: 0, readingSeconds: 30, rowsRead: 1).line
            == "window  attached 0s · reading 30s (100%) · 1 row read")
    }
}
