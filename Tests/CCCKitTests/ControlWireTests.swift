import Foundation
import Testing

@testable import CCCKit

/// The control socket is a wire between two builds of `ccc`: the CLI a user
/// has on PATH and the server a window started an hour ago. Adding a field to
/// a request must not break the older side, so the rule is pinned here.
@Suite struct ControlWireTests {
    private func roundTrip(_ request: ControlRequest) throws -> ControlRequest {
        try JSONDecoder().decode(ControlRequest.self, from: JSONEncoder().encode(request))
    }

    @Test func sendCarriesEveryChannel() throws {
        let decoded = try roundTrip(.send(text: "hi", keys: ["enter"], wheel: 3, paste: "two\nlines"))
        guard case .send(let text, let keys, let wheel, let paste) = decoded else {
            Issue.record("not a send: \(decoded)")
            return
        }
        #expect(text == "hi")
        #expect(keys == ["enter"])
        #expect(wheel == 3)
        #expect(paste == "two\nlines")
    }

    /// An older `ccc send` encodes no `paste` key at all. The server must read
    /// that as "no paste", never as a decode failure.
    @Test func aSendWithoutPasteStillDecodes() throws {
        let json = Data(#"{"send":{"text":"hi","keys":null}}"#.utf8)
        let decoded = try JSONDecoder().decode(ControlRequest.self, from: json)
        guard case .send(let text, _, let wheel, let paste) = decoded else {
            Issue.record("not a send: \(decoded)")
            return
        }
        #expect(text == "hi")
        #expect(wheel == nil)
        #expect(paste == nil)
    }

    @Test func reconnectCarriesAnOptionalHost() throws {
        guard case .reconnect(let host) = try roundTrip(.reconnect(host: "studio")) else {
            Issue.record("not a reconnect")
            return
        }
        #expect(host == "studio")
        guard case .reconnect(let all) = try roundTrip(.reconnect(host: nil)) else {
            Issue.record("not a reconnect")
            return
        }
        #expect(all == nil)
    }

    /// A v1 server sends no `hosts` key in its stats; this CLI must still
    /// read them.
    @Test func statsWithoutHostsStillDecode() throws {
        let json = Data("""
        {"pid":1,"footprintBytes":2,"lastPollMs":3,"meanPollMs":4,"pollCount":5,
         "ptyBytesIn":6,"ptyBytesPerSecond":7,"uptimeSeconds":8}
        """.utf8)
        let stats = try JSONDecoder().decode(StatsInfo.self, from: json)
        #expect(stats.hosts == nil)
        #expect(stats.build == nil)
        #expect(stats.notifications == nil)
        #expect(stats.pollCount == 5)
    }

    /// `select` carries a region or a nil that means "clear", and the two
    /// must stay distinguishable on the wire: a dropped `region` key would
    /// turn `ccc select 0 0 4 0` into a clear on the far side.
    @Test func selectCarriesARegionOrAClear() throws {
        let region = SelectionRegion(fromCol: 1, fromRow: 2, toCol: 3, toRow: 4, rectangle: true)
        guard case .select(let decoded) = try roundTrip(.select(region: region)) else {
            Issue.record("not a select")
            return
        }
        #expect(decoded == region)
        guard case .select(let cleared) = try roundTrip(.select(region: nil)) else {
            Issue.record("not a select")
            return
        }
        #expect(cleared == nil)
    }

    /// A v9 `ccc select` encodes no `grain` key at all — the field arrived
    /// with item 13. The server must read that as the cell selection it
    /// always was, never as a decode failure.
    @Test func aSelectWithoutAGrainStillDecodes() throws {
        let json = Data(#"{"select":{"region":{"from":{"col":1,"row":2},"to":{"col":3,"row":4},"rectangle":false}}}"#.utf8)
        guard case .select(let region) = try JSONDecoder().decode(ControlRequest.self, from: json) else {
            Issue.record("not a select")
            return
        }
        #expect(region?.grain == nil)
        // And nil is not a third meaning: it is `.cell`, which is what the
        // host reads it as.
        #expect((region?.grain ?? .cell) == .cell)

        guard case .select(let word) = try roundTrip(.select(region: SelectionRegion(
            fromCol: 1, fromRow: 2, toCol: 1, toRow: 2, grain: .word))) else {
            Issue.record("not a select")
            return
        }
        #expect(word?.grain == .word)
    }

    /// `roster` (item 4) carries an optional `fresh`; an older CLI's bare
    /// `{"roster":{}}` must read as "as you hold it", never as a failure.
    @Test func rosterCarriesAnOptionalFresh() throws {
        guard case .roster(let fresh) = try roundTrip(.roster(fresh: true)) else {
            Issue.record("not a roster")
            return
        }
        #expect(fresh == true)
        guard case .roster(let bare) = try JSONDecoder().decode(ControlRequest.self, from: Data(#"{"roster":{}}"#.utf8)) else {
            Issue.record("not a roster")
            return
        }
        #expect(bare == nil)
    }

    /// The answer is every host's slot as the app holds it. A slot from an
    /// app older than this CLI carries fewer keys; the CLI reads it with
    /// the struct's own defaults and never refuses the rows over a counter.
    @Test func aHostSlotCrossesTheSocketAndTolerantlyBack() throws {
        var slot = HostPoll(host: "studio")
        slot.pollCount = 4
        slot.lastPollMs = 210
        slot.error = nil
        slot.issues = [RosterShapeIssue(index: 2, field: "state", message: "unknown value")]
        slot.notes = ["overlay: unreadable"]
        let data = try JSONEncoder().encode(ControlResponse.roster([slot]))
        guard case .roster(let back) = try JSONDecoder.ccc.decode(ControlResponse.self, from: data) else {
            Issue.record("not a roster")
            return
        }
        #expect(back == [slot])

        let minimal = Data(#"{"host":"air","rows":[],"pollCount":1}"#.utf8)
        let old = try JSONDecoder.ccc.decode(HostPoll.self, from: minimal)
        #expect(old.host == "air")
        #expect(old.pollCount == 1)
        #expect(old.issues.isEmpty)
        #expect(old.evictions == 0)
        #expect(old.error == nil)
        // The one field with no default is the name: a slot with no host
        // is not a slot.
        #expect(throws: (any Error).self) {
            try JSONDecoder.ccc.decode(HostPoll.self, from: Data(#"{"rows":[]}"#.utf8))
        }
    }

    /// The far side's `ccc version --json` is read by `hosts check`; a
    /// newer ccc adding fields there must not break an older reader, and
    /// the two fields that carry the number are the ones pinned.
    @Test func versionCrossesTheHopOnTwoFields() throws {
        let json = Data(#"{"version":"0.1.5","build":57,"executablePath":"/x/ccc.app/Contents/MacOS/ccc","bundlePath":"/x/ccc.app","futureKey":true}"#.utf8)
        let info = try BuildInfo.decode(json, naming: cccName)
        #expect(info.short == "0.1.5 (57)")
        // No `dev` key: that ccc predates the lane split, and was a release.
        #expect(!info.dev)
        // No `name` key either — that ccc predates ota. The reader ran the
        // command, so the reader names it; a blank here is a blank row.
        #expect(info.name == "ccc")
    }
}

/// A server that never answers must not hold the command forever (found
/// 2026-09-04: a handler that awaits a poll rides an ssh with no keepalive,
/// and the client's read had no deadline). It times out and says so —
/// never "malformed".
@Suite struct ControlTimeoutTests {
    @Test @MainActor func aSilentServerTimesOutInsteadOfHanging() async throws {
        let path = NSTemporaryDirectory() + "ccc-t-\(UUID().uuidString.prefix(8)).sock"
        let server = ControlServer(path: path) { _ in
            try? await Task.sleep(for: .seconds(30))
            return .ok("late")
        }
        try server.start()
        defer { server.stop() }
        // The listener comes up asynchronously; a send before it is
        // bound is `unreachable`, which is a different answer.
        for _ in 0..<40 where !ControlClient(path: path).isReachable() {
            try await Task.sleep(for: .milliseconds(50))
        }
        let started = ContinuousClock.now
        let result = await Task.detached {
            Result { try ControlClient(path: path, timeout: 1).send(.stats) }
        }.value
        #expect(started.duration(to: .now) < .seconds(5))
        guard case .failure(let error) = result, case ControlClient.Error.timedOut = error else {
            Issue.record("expected timedOut, got \(result)")
            return
        }
        #expect("\(error)".contains("did not answer within 1 s"))
    }
}

/// `ccc stats`' first line is the app's — `pid`, `memory`, `uptime`. The
/// third of those was the attached *pane's* age until 2026-09-03, and `0`
/// whenever nothing was attached, so a week-old app read "uptime 0s" the
/// moment you detached. It comes from the process now.
@Suite struct ProcessUptimeTests {
    @Test func ourOwnUptimeIsRealAndDetachedIsNotZero() throws {
        let uptime = try #require(ProcessStats.uptime(of: getpid()))
        // A test process is seconds old, not zero and not a year: the two
        // failures worth catching are a stopped clock and mach timebase
        // arithmetic off by a factor.
        #expect(uptime > 0)
        #expect(uptime < 60 * 60 * 24)
    }

    @Test func aProcessWeCannotSeeIsNilNotZero() {
        // Same rule as the roster's: "I don't know" is not "none".
        #expect(ProcessStats.uptime(of: pid_t.max) == nil)
    }
}
