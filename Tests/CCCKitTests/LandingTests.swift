import Foundation
import Testing

@testable import CCCKit

/// Item 25: the detector that does not use the clock.
///
/// The fixture is attrition's night of 2026-09-07 (`docs/EVIDENCE.md`
/// "the stall stream's first run"). Ten landings, three streams, **zero**
/// `stalled` events at either window — and in the same run three sessions
/// finished quietly, every one found by a human eyeballing the roster.
/// `loop-284` is the sharpest of them: committed, pushed, two commits
/// ahead of base, and its row read `working idle` until someone said so
/// out loud. `loop-252` is the reason a headline here carries numbers —
/// its `↳` read "shutdown assertions failing" while the work was merged
/// and pushed, so state and detail were stale in the *same* direction and
/// agreed with each other.
///
/// Both are replayed below. Neither needs a window, because neither is a
/// stall.
@Suite struct LandingTests {
    private static let t0 = Date(timeIntervalSince1970: 1_757_000_000)

    private func tree(_ ahead: Int, unpushed: Int?, branch: String = "loop-284",
                      base: String = "master") -> WorktreeInfo {
        WorktreeInfo(branch: branch, base: base, ahead: ahead, behind: 0,
                     repo: "/x", unpushed: unpushed)
    }

    private func row(_ id: String, _ state: Session.State?, tree: WorktreeInfo?,
                     detail: String? = "running the release suite",
                     draft: Bool = false) -> SessionRow {
        SessionRow(session: Session(id: id, cwd: "/x", kind: .background,
                                    startedAt: Self.t0.addingTimeInterval(-86_400),
                                    state: state, name: id),
                   host: Host.localName, model: nil, attached: false, draft: draft,
                   worktree: tree, job: JobInfo(detail: detail, updatedAt: Self.t0))
    }

    private func poll(_ rows: [SessionRow], count: Int = 1) -> RosterPoller.State {
        var p = HostPoll(host: Host.localName)
        p.rows = rows
        p.pollCount = count
        return RosterPoller.State(hosts: [p])
    }

    /// The whole point, replayed: the row never leaves `working`, so the
    /// three kinds that read the daemon say nothing for the session's
    /// entire life — and the tip says it twice.
    @Test func aTipThatMovesIsNewsWhileTheStateNeverIs() {
        var d = TransitionDetector(stallWindow: .off)
        _ = d.observe(poll([row("loop-284", .working, tree: tree(0, unpushed: 0))]), at: Self.t0)

        let committed = d.observe(poll([row("loop-284", .working, tree: tree(2, unpushed: 2))],
                                       count: 2), at: Self.t0)
        #expect(committed.map(\.kind) == [.landed])
        #expect(committed.first?.headline == "loop-284 committed — 2 commits ahead of master, 2 unpushed")
        #expect(committed.first?.mark == "↑")

        let pushed = d.observe(poll([row("loop-284", .working, tree: tree(2, unpushed: 0))],
                                    count: 3), at: Self.t0)
        #expect(pushed.map(\.kind) == [.landed])
        #expect(pushed.first?.landing?.half == .pushed)
        #expect(pushed.first?.headline == "loop-284 pushed — 2 commits ahead of master, all on origin")

        // And then it sits at `working idle` forever, saying nothing.
        for _ in 0..<100 {
            #expect(d.observe(poll([row("loop-284", .working, tree: tree(2, unpushed: 0))], count: 4),
                              at: Self.t0).isEmpty)
        }
    }

    /// `loop-252`: the numbers are git's and the sentence is the
    /// daemon's, so a stale `↳` next to a fresh count is the
    /// contradiction that was missing when the two agreed.
    @Test func theHeadlineCannotGoStaleAndTheBodyStillCan() {
        var d = TransitionDetector(stallWindow: .off)
        _ = d.observe(poll([row("loop-252", .working, tree: tree(0, unpushed: 0),
                                detail: "shutdown assertions failing; 5 tests need fix")]), at: Self.t0)
        let events = d.observe(poll([row("loop-252", .working, tree: tree(3, unpushed: 0),
                                         detail: "shutdown assertions failing; 5 tests need fix")],
                                    count: 2), at: Self.t0)
        #expect(events.first?.headline == "loop-252 pushed — 3 commits ahead of master, all on origin")
        #expect(events.first?.body == "shutdown assertions failing; 5 tests need fix")
        #expect(events.first?.watchLine ==
                "loop-252 pushed — 3 commits ahead of master, all on origin — shutdown assertions failing; 5 tests need fix")
    }

    /// A worker commits and pushes seconds apart, which is one 2 s poll:
    /// `ahead` grows and `unpushed` is already 0 in the same reading.
    /// Calling that `committed` would be true and would cost it the
    /// banner, since only `pushed` notifies.
    @Test func commitAndPushInsideOneTickReportThePushedHalf() {
        var d = TransitionDetector(stallWindow: .off)
        _ = d.observe(poll([row("w", .working, tree: tree(0, unpushed: 0))]), at: Self.t0)
        let events = d.observe(poll([row("w", .working, tree: tree(2, unpushed: 0))], count: 2), at: Self.t0)
        #expect(events.map(\.kind) == [.landed])
        #expect(events.first?.landing?.half == .pushed)
        #expect(events.first?.drawsBanner == true)
    }

    /// The banner rule, as one definition both faces read: everything
    /// reaches `ccc watch`, a bare commit does not reach the phone.
    @Test func onlyThePushedHalfIsWorthThePhone() {
        var d = TransitionDetector(stallWindow: .off)
        _ = d.observe(poll([row("w", .working, tree: tree(0, unpushed: 0))]), at: Self.t0)
        let committed = d.observe(poll([row("w", .working, tree: tree(1, unpushed: 1))], count: 2), at: Self.t0)
        #expect(committed.first?.drawsBanner == false)
        let pushed = d.observe(poll([row("w", .working, tree: tree(1, unpushed: 0))], count: 3), at: Self.t0)
        #expect(pushed.first?.drawsBanner == true)
        // Every other kind draws, and that is the default rather than a list.
        #expect(SessionEvent(kind: .blocked, ref: SessionRef(host: "studio", id: "a"), name: nil,
                             at: Self.t0).drawsBanner)
    }

    /// A host's first answer arms the tip silently. Launching ccc in
    /// front of five branches that are already ahead must not announce
    /// five landings — the same rule `blocked`, `done` and `stalled` all
    /// follow here.
    @Test func aBranchThatIsAlreadyAheadIsHistory() {
        var d = TransitionDetector(stallWindow: .off)
        #expect(d.observe(poll([row("w", .working, tree: tree(7, unpushed: 0))]), at: Self.t0).isEmpty)
        #expect(d.observe(poll([row("w", .working, tree: tree(7, unpushed: 0))], count: 2), at: Self.t0).isEmpty)
    }

    /// When the daemon does say `done` in the same tick the tip moves,
    /// that is one piece of news twice. The terminal event is the better
    /// half and the row already draws `↑N` beside it.
    @Test func aDoneInTheSameTickSwallowsTheLanding() {
        var d = TransitionDetector(stallWindow: .off)
        _ = d.observe(poll([row("w", .working, tree: tree(0, unpushed: 0))]), at: Self.t0)
        let events = d.observe(poll([row("w", .done, tree: tree(2, unpushed: 0))], count: 2), at: Self.t0)
        #expect(events.map(\.kind) == [.done])
    }

    /// The tip is kept out of the change key on purpose: a commit landing
    /// while a session is blocked is not a new question, and re-firing
    /// the question it is already blocked on would be the noisiest bug
    /// available here.
    @Test func aCommitWhileBlockedDoesNotReAskTheQuestion() {
        var d = TransitionDetector(stallWindow: .off)
        _ = d.observe(poll([row("w", .blocked, tree: tree(0, unpushed: 0))]), at: Self.t0)
        let events = d.observe(poll([row("w", .blocked, tree: tree(1, unpushed: 1))], count: 2), at: Self.t0)
        #expect(events.map(\.kind) == [.landed])
    }

    /// A session that moves no tip is not a session this detector has an
    /// opinion about — a research or review worker produces no commits,
    /// and a claim about a branch it does not have is exactly the
    /// unverified claim keying on git avoids.
    @Test func aSessionWithNoWorktreeSaysNothing() {
        var d = TransitionDetector(stallWindow: .off)
        _ = d.observe(poll([row("w", .working, tree: nil)]), at: Self.t0)
        #expect(d.observe(poll([row("w", .working, tree: nil)], count: 2), at: Self.t0).isEmpty)
        // Nor does a draft, which has not been prompted and has no work.
        _ = d.observe(poll([row("d", .blocked, tree: tree(0, unpushed: 0), draft: true)], count: 3), at: Self.t0)
        #expect(d.observe(poll([row("d", .blocked, tree: tree(4, unpushed: 4), draft: true)], count: 4),
                          at: Self.t0).isEmpty)
    }

    /// A merge drops `ahead` back to zero, and that is not a landing. But
    /// the new reading is recorded, so the *next* commit is news again —
    /// the same re-arming a stall gets from real movement.
    @Test func aMergeIsNotALandingAndItReArms() {
        var d = TransitionDetector(stallWindow: .off)
        _ = d.observe(poll([row("w", .working, tree: tree(0, unpushed: 0))]), at: Self.t0)
        #expect(d.observe(poll([row("w", .working, tree: tree(2, unpushed: 0))], count: 2), at: Self.t0).count == 1)
        #expect(d.observe(poll([row("w", .working, tree: tree(0, unpushed: 0))], count: 3), at: Self.t0).isEmpty)
        let again = d.observe(poll([row("w", .working, tree: tree(1, unpushed: 1))], count: 4), at: Self.t0)
        #expect(again.map(\.kind) == [.landed])
        #expect(again.first?.landing?.half == .committed)
    }

    /// A repository with no origin can only ever report the commit half,
    /// and says nothing about pushing — the word means nothing there.
    @Test func withNoOriginThereIsOnlyTheCommitHalf() {
        var d = TransitionDetector(stallWindow: .off)
        _ = d.observe(poll([row("w", .working, tree: tree(0, unpushed: nil))]), at: Self.t0)
        let events = d.observe(poll([row("w", .working, tree: tree(1, unpushed: nil))], count: 2), at: Self.t0)
        #expect(events.first?.landing?.half == .committed)
        #expect(events.first?.headline == "w committed — 1 commit ahead of master")
        #expect(events.first?.drawsBanner == false)
    }

    /// `ahead` is counted against whatever tip the row is measured
    /// against, and the sentence names that tip rather than a constant:
    /// a worker branched off a base another session holds is measured
    /// against `origin/<base>` (`WorktreeInfo.baseTipName`), which is the
    /// shape attrition's commander makes constantly.
    @Test func theSentenceNamesTheTipItWasMeasuredAgainst() {
        var d = TransitionDetector(stallWindow: .off)
        var followsOrigin = tree(0, unpushed: 0, base: "replan-pdb")
        followsOrigin.baseTip = "origin/replan-pdb"
        _ = d.observe(poll([row("w", .working, tree: followsOrigin)]), at: Self.t0)
        var moved = followsOrigin
        moved.ahead = 1
        let events = d.observe(poll([row("w", .working, tree: moved)], count: 2), at: Self.t0)
        #expect(events.first?.headline == "w pushed — 1 commit ahead of origin/replan-pdb, all on origin")
    }

    /// The event crosses the hop as JSON like every other one: `ccc
    /// watch --json` is an agent's surface, and a payload that does not
    /// survive the encoder is a payload the far side never sees.
    @Test func aLandingSurvivesTheWire() throws {
        let event = SessionEvent(kind: .landed, ref: SessionRef(host: "studio", id: "a3f1"),
                                 name: "loop-284", at: Self.t0,
                                 landing: Landing(half: .pushed, branch: "loop-284", base: "master",
                                                  ahead: 2, unpushed: 0))
        let data = try JSONEncoder().encode(event)
        let back = try JSONDecoder().decode(SessionEvent.self, from: data)
        #expect(back == event)
        #expect(back.landing?.half == .pushed)
        #expect(back.headline == "loop-284 pushed — 2 commits ahead of master, all on origin")
    }
}
