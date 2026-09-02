import Foundation
import Testing

@testable import CCCKit

/// v3's unit: an event is a change in a session's (state, waitingFor)
/// between two polls. Everything here is two rosters in, events out.
@Suite struct TransitionTests {
    private func session(_ id: String, _ state: Session.State?, waitingFor: String? = nil, name: String? = nil) -> Session {
        Session(id: id, cwd: "/x", kind: .background, startedAt: Date(timeIntervalSince1970: 0),
                state: state, waitingFor: waitingFor, name: name ?? id)
    }

    private func poll(_ sessions: [Session], error: String? = nil, count: Int = 1) -> HostPoll {
        poll(Host.localName, sessions, error: error, count: count)
    }

    private func poll(_ host: String, _ sessions: [Session], error: String? = nil, count: Int = 1) -> HostPoll {
        var p = HostPoll(host: host)
        p.rows = sessions.map { SessionRow(session: $0, host: host, model: nil, attached: false) }
        p.error = error
        p.pollCount = count
        return p
    }

    @Test func theBaselineSaysNothing() {
        var d = TransitionDetector()
        let events = d.observe(.init(hosts: [poll([session("a", .blocked, waitingFor: "input needed"), session("b", .working)])]))
        #expect(events.isEmpty)
        #expect(d.primedHosts == [Host.localName])
    }

    @Test func becomingBlockedIsOneEventNotThirty() {
        var d = TransitionDetector()
        _ = d.observe(.init(hosts: [poll([session("a", .working)])]))
        let blocked = RosterPoller.State(hosts: [poll([session("a", .blocked, waitingFor: "approve rm -rf?")])])
        let first = d.observe(blocked)
        #expect(first.map(\.kind) == [.blocked])
        #expect(first.first?.ref == SessionRef(id: "a"))
        #expect(first.first?.waitingFor == "approve rm -rf?")
        #expect(first.first?.headline == "a is waiting: approve rm -rf?")
        for _ in 0..<30 { #expect(d.observe(blocked).isEmpty) }
    }

    /// The same session, a new question: that is new.
    @Test func aNewQuestionOnTheSameSessionIsANewEvent() {
        var d = TransitionDetector()
        _ = d.observe(.init(hosts: [poll([session("a", .blocked, waitingFor: "one")])]))
        let events = d.observe(.init(hosts: [poll([session("a", .blocked, waitingFor: "two")])]))
        #expect(events.map(\.waitingFor) == ["two"])
    }

    @Test func aLiveSessionEndingIsAnEventAFinishedNewcomerIsNot() {
        var d = TransitionDetector()
        _ = d.observe(.init(hosts: [poll([session("a", .working), session("b", .blocked)])]))
        let events = d.observe(.init(hosts: [poll([session("a", .done), session("b", .failed), session("c", .done)])]))
        #expect(events.map(\.kind) == [.done, .failed])
        #expect(events.map(\.ref.id) == ["a", "b"])
        #expect(events.map(\.headline) == ["a finished", "b failed"])
    }

    /// Working → working with a different waitingFor is not news; only a
    /// blocked state carries a question.
    @Test func workingIsNeverAnEvent() {
        var d = TransitionDetector()
        _ = d.observe(.init(hosts: [poll([session("a", .done)])]))
        #expect(d.observe(.init(hosts: [poll([session("a", .working)])])).isEmpty)
        #expect(d.observe(.init(hosts: [poll([session("a", .working, waitingFor: "x")])])).isEmpty)
    }

    /// A host that stops answering keeps its rows on screen but says
    /// nothing; when it is back, what changed meanwhile is one event.
    @Test func aFailingHostIsSilentAndCatchesUpOnce() {
        var d = TransitionDetector()
        _ = d.observe(.init(hosts: [poll("studio", [session("a", .working)])]))
        // Down: the rows are the old ones, marked by the error.
        let down = RosterPoller.State(hosts: [poll("studio", [session("a", .working)], error: "ssh to studio failed", count: 2)])
        #expect(d.observe(down).isEmpty)
        #expect(d.observe(down).isEmpty)
        let back = d.observe(.init(hosts: [poll("studio", [session("a", .blocked, waitingFor: "q")], count: 3)]))
        #expect(back.map(\.kind) == [.blocked])
        #expect(back.first?.ref == SessionRef(host: "studio", id: "a"))
        #expect(back.first?.ref.description == "studio:a")
    }

    /// Each host has its own baseline: a host that first answers after
    /// launch does not report its whole roster as news.
    @Test func aLateHostGetsItsOwnBaseline() {
        var d = TransitionDetector()
        _ = d.observe(.init(hosts: [poll([session("a", .working)]),
                                    poll("air", [], error: "ssh to air failed", count: 0)]))
        let events = d.observe(.init(hosts: [poll([session("a", .working)]),
                                             poll("air", [session("z", .blocked, waitingFor: "q")])]))
        #expect(events.isEmpty)
        #expect(d.primedHosts == [Host.localName, "air"])
        let later = d.observe(.init(hosts: [poll([session("a", .blocked)]),
                                            poll("air", [session("z", .blocked, waitingFor: "q")])]))
        #expect(later.map(\.ref.id) == ["a"])
    }

    /// A session that leaves and comes back blocked is a fresh event, not
    /// a suppressed repeat of its last known state.
    @Test func aSessionThatLeavesIsForgotten() {
        var d = TransitionDetector()
        _ = d.observe(.init(hosts: [poll([session("a", .blocked, waitingFor: "q")])]))
        #expect(d.observe(.init(hosts: [poll([])])).isEmpty)
        let events = d.observe(.init(hosts: [poll([session("a", .blocked, waitingFor: "q")])]))
        #expect(events.map(\.kind) == [.blocked])
    }

    @Test func anEventRoundTripsAsJSON() throws {
        let event = SessionEvent(kind: .blocked, ref: SessionRef(host: "studio", id: "a1b2"), name: "fantasy",
                                 waitingFor: "input needed", at: Date(timeIntervalSince1970: 1_000))
        let data = try JSONEncoder().encode(event)
        #expect(try JSONDecoder().decode(SessionEvent.self, from: data) == event)
    }
}
