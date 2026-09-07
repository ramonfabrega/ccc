import Foundation
import Testing

@testable import CCCKit

/// Item 21: the transition that was missing. On 2026-09-04 cuanto's Lane B
/// was contracted to report at each landing point, sent zero messages, and
/// sat with two unpushed commits for two days — and `ccc watch` was silent
/// the whole time, correctly: `blocked`, `done`, `failed` and `stopped`
/// are the only things that ever happen to a row, and it was `working`
/// throughout. A stall is a non-event, and a non-event needs a clock.
@Suite struct StallTests {
    private static let t0 = Date(timeIntervalSince1970: 1_757_000_000)

    private func row(_ id: String, _ state: Session.State?, movedAgo: TimeInterval?,
                     detail: String? = "running the release suite", draft: Bool = false,
                     now: Date = StallTests.t0) -> SessionRow {
        let job = movedAgo.map { JobInfo(detail: detail, updatedAt: now.addingTimeInterval(-$0)) }
        return SessionRow(session: Session(id: id, cwd: "/x", kind: .background,
                                           startedAt: now.addingTimeInterval(-86_400),
                                           state: state, name: id),
                          host: Host.localName, model: nil, attached: false, draft: draft, job: job)
    }

    private func poll(_ rows: [SessionRow], count: Int = 1) -> RosterPoller.State {
        var p = HostPoll(host: Host.localName)
        p.rows = rows
        p.pollCount = count
        return RosterPoller.State(hosts: [p])
    }

    private func detector(minutes: Double? = 30) -> TransitionDetector {
        TransitionDetector(stallWindow: StallWindow(minutes: minutes))
    }

    /// Lane B, replayed: working, and the daemon has not written its file
    /// in two days. One event, not one per tick — and the sentence carries
    /// how long, because that is the whole content of a stall.
    @Test func aWorkingSessionThatStopsMovingIsOneEvent() {
        var d = detector()
        let before = poll([row("lane-b", .working, movedAgo: 60)])
        #expect(d.observe(before, at: Self.t0).isEmpty)

        let after = poll([row("lane-b", .working, movedAgo: 2 * 86_400)], count: 2)
        let events = d.observe(after, at: Self.t0)
        #expect(events.map(\.kind) == [.stalled])
        #expect(events.first?.headline == "lane-b has not moved in 2 days")
        #expect(events.first?.mark == "⏳")
        // The body is the sentence that stopped changing.
        #expect(events.first?.body == "running the release suite")
        // A hundred more ticks say nothing.
        for _ in 0..<100 { #expect(d.observe(after, at: Self.t0).isEmpty) }
    }

    /// And it re-arms: a session that moves, then stops again, is news
    /// again. Without this, one stall a day would silence a session for
    /// the rest of its life.
    @Test func movingAgainRearmsIt() {
        var d = detector()
        _ = d.observe(poll([row("w", .working, movedAgo: 60)]), at: Self.t0)
        #expect(d.observe(poll([row("w", .working, movedAgo: 3600)], count: 2), at: Self.t0).count == 1)
        // It moved — nothing to say, but the arm is reset.
        #expect(d.observe(poll([row("w", .working, movedAgo: 30)], count: 3), at: Self.t0).isEmpty)
        #expect(d.observe(poll([row("w", .working, movedAgo: 3600)], count: 4), at: Self.t0).count == 1)
    }

    /// Three exclusions, each against a false alarm a fixed window invites.
    @Test func onlyAWorkingSessionWithAClockCanStall() {
        var d = detector()
        _ = d.observe(poll([row("a", .working, movedAgo: 60), row("b", .blocked, movedAgo: 60),
                            row("c", .working, movedAgo: nil), row("d", .blocked, movedAgo: 60, draft: true)]),
                      at: Self.t0)
        let stale = poll([
            // Blocked and sitting is not stalled — it is waiting for you,
            // and it already fired its own event.
            row("b", .blocked, movedAgo: 3 * 3600),
            // No clock, no claim: a job file ccc cannot time is never
            // called stalled.
            row("c", .working, movedAgo: nil),
            // A draft has never been prompted; it is still by design.
            row("d", .blocked, movedAgo: 3 * 3600, draft: true),
            // Only this one.
            row("a", .working, movedAgo: 3 * 3600),
        ], count: 2)
        let events = d.observe(stale, at: Self.t0)
        #expect(events.map(\.ref.id) == ["a"])
    }

    /// A finished session is not doing anything by definition, and its own
    /// ending is the event.
    @Test func anEndedSessionNeverStalls() {
        var d = detector()
        _ = d.observe(poll([row("x", .working, movedAgo: 60)]), at: Self.t0)
        let events = d.observe(poll([row("x", .done, movedAgo: 5 * 86_400)], count: 2), at: Self.t0)
        #expect(events.map(\.kind) == [.done])
    }

    /// Launching in front of three long-still sessions must not fire three
    /// banners — the same rule the baseline already has for `blocked`.
    /// The standing ones are context, and `standingStalls` is where a
    /// surface reads them.
    @Test func aHostsFirstAnswerArmsSilently() {
        var d = detector()
        let state = poll([row("a", .working, movedAgo: 3 * 3600),
                          row("b", .working, movedAgo: 9 * 3600)])
        #expect(d.observe(state, at: Self.t0).isEmpty)
        #expect(d.observe(state, at: Self.t0).isEmpty, "armed, so it stays quiet after the baseline too")

        let standing = state.standingStalls(StallWindow(minutes: 30), now: Self.t0)
        #expect(standing.map(\.row.ref.id) == ["b", "a"], "worst offender first")
        #expect(SessionEvent.spell(standing[0].still) == "9h")
    }

    @Test func zeroTurnsItOff() {
        var d = detector(minutes: 0)
        _ = d.observe(poll([row("a", .working, movedAgo: 60)]), at: Self.t0)
        #expect(d.observe(poll([row("a", .working, movedAgo: 30 * 86_400)], count: 2), at: Self.t0).isEmpty)
        #expect(StallWindow(minutes: 0).seconds == nil)
        #expect(poll([row("a", .working, movedAgo: 86_400)]).standingStalls(.off, now: Self.t0).isEmpty)
    }

    @Test func theWindowIsThirtyMinutesAndTheEnvironmentMovesIt() {
        #expect(StallWindow.fromEnvironment([:]).seconds == 1800.0)
        #expect(StallWindow.fromEnvironment(["CCC_STALL_MINUTES": "90"]).seconds == 5400.0)
        #expect(StallWindow.fromEnvironment(["CCC_STALL_MINUTES": "0"]).seconds == nil)
        // Nonsense falls back rather than silently disabling the watcher.
        #expect(StallWindow.fromEnvironment(["CCC_STALL_MINUTES": "soon"]).seconds == 1800.0)
    }

    @Test func durationsReadAtAGlance() {
        #expect(SessionEvent.spell(12) == "12s", "a sub-minute window is a test's, and 0m reads as a bug")
        #expect(SessionEvent.spell(59) == "59s")
        #expect(SessionEvent.spell(60) == "1m")
        #expect(SessionEvent.spell(30 * 60) == "30m")
        #expect(SessionEvent.spell(89 * 60) == "89m")
        #expect(SessionEvent.spell(90 * 60) == "1h30m")
        #expect(SessionEvent.spell(2 * 3600) == "2h")
        #expect(SessionEvent.spell(47 * 3600) == "47h")
        #expect(SessionEvent.spell(2 * 86_400) == "2 days")
    }

    /// The daemon writes fractional seconds; `.iso8601` alone does not
    /// read them, and a clock ccc cannot parse would silently mean "never
    /// stalls". Both shapes, off the real file's spelling.
    @Test func theDaemonsClockIsRead() {
        let json = Data("""
        {"detail":"still going","updatedAt":"2026-09-07T00:58:17.563Z","state":"working"}
        """.utf8)
        let info = JobInfo.decode(json)
        #expect(info?.updatedAt != nil)
        #expect(JobInfo.instant("2026-09-07T00:58:17.563Z") != nil)
        #expect(JobInfo.instant("2026-09-07T00:58:17Z") != nil)
        #expect(JobInfo.instant("last tuesday") == nil)
        // And it survives the hop: the row crosses as `ccc list --json`.
        let row = SessionRow(session: Session(id: "a", cwd: "/x", kind: .background, startedAt: Self.t0),
                             model: nil, attached: false,
                             job: JobInfo(detail: "d", updatedAt: Self.t0))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let back = try? JSONDecoder.roster.decode(SessionRow.self, from: encoder.encode(row))
        #expect(back?.job?.updatedAt == Self.t0)
    }
}
