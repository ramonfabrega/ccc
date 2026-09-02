import CCCKit
import Foundation
import Testing

@Suite struct RosterDecoderTests {
    // MARK: - The real capture

    @Test func realCaptureDecodesCleanly() throws {
        let result = RosterDecoder.decode(try Fixtures.data("roster/agents-2026-09-02.json"))
        #expect(result.issues.isEmpty, "issues: \(result.issues.map(\.description))")
        #expect(result.sessions.count == 17)
        #expect(result.sessions.allSatisfy { $0.kind == .background })
        #expect(result.sessions.allSatisfy { $0.extra.isEmpty })
        #expect(result.sessions.allSatisfy { $0.sessionId != nil })
        #expect(result.sessions.allSatisfy { $0.state != nil })
        #expect(result.sessions.allSatisfy { $0.waitingFor == nil })

        // `pid` and `status` arrive together, and only for a live process.
        #expect(result.sessions.allSatisfy { ($0.pid == nil) == ($0.status == nil) })
        #expect(result.sessions.filter { $0.pid != nil }.count == 6)
        // A live pid coexists with `state: done`: state and status are
        // independent axes, not one lifecycle (3 such rows in the capture).
        #expect(result.sessions.filter { $0.state == .done && $0.pid != nil }.count == 3)

        let lore = try #require(result.sessions.first { $0.name == "lore" })
        #expect(lore.id == "a18a763f")
        #expect(lore.pid == 32093)
        #expect(lore.status == .idle)
        // NOTE: the brief said `state == .working`; the capture says `blocked`
        // for this row (and `working` for the `ccc` row). The fixture wins.
        #expect(lore.state == .blocked)
        #expect(lore.sessionId == "2d03cb5d-a7a8-43bf-b8e1-fe5147e4711d")
        #expect(lore.cwd == "/Users/rf-studio/code/fun/lore")
        #expect(Int((lore.startedAt.timeIntervalSince1970 * 1000).rounded()) == 1_788_288_840_703)

        let ccc = try #require(result.sessions.first { $0.name == "ccc" })
        #expect(ccc.state == .working)
        #expect(ccc.status == .busy)

        // Rows with no live process carry neither pid nor status, whatever
        // their state.
        for session in result.sessions where session.pid == nil {
            #expect(session.status == nil)
        }
        let stopped = try #require(result.sessions.first { $0.state == .stopped })
        #expect(stopped.pid == nil)
        #expect(stopped.status == nil)

        // Order is the capture's order.
        #expect(result.sessions.first?.id == "a76974d4")
        #expect(result.sessions.last?.id == "b3919c35")
    }

    // MARK: - Shape drift

    @Test func shapeChangeKeepsEveryRow() throws {
        let result = RosterDecoder.decode(try Fixtures.data("roster/shape-changed.json"))
        #expect(result.sessions.count == 3)

        // Row 0 is untouched.
        #expect(result.sessions[0].id == "aaaa1111")
        #expect(result.sessions[0].state == .working)
        #expect(result.sessions[0].extra.isEmpty)

        // Row 1: missing `kind`, `startedAt` as an ISO string.
        let drift = result.sessions[1]
        #expect(drift.kind == .background)                 // defaulted
        #expect(drift.startedAt == .distantPast)
        #expect(drift.extra["startedAt"] == .string("2026-09-02T01:00:00.000Z"))
        #expect(drift.extra["kind"] == nil)                // absent, not mistyped
        #expect(drift.extra.count == 1)

        // Row 2: unknown state, two unknown fields.
        let paused = result.sessions[2]
        #expect(paused.state == nil)
        #expect(paused.extra["state"] == .string("paused"))
        #expect(paused.extra["tempo"] == .string("active"))
        #expect(paused.extra["fan"] == .array([.object(["id": .string("x")])]))
        #expect(paused.extra.count == 3)

        // Issues name the element and the field.
        let described = result.issues.map(\.description)
        #expect(result.issues.count == 3)
        #expect(described.contains { $0 == "[1] kind: missing" })
        #expect(described.contains { $0.hasPrefix("[1] startedAt:") && $0.contains("a string") })
        #expect(described.contains { $0 == "[2] state: unknown value \"paused\"" })
        #expect(result.issues.allSatisfy { $0.index != nil && $0.field != nil })
    }

    // MARK: - Top-level shapes

    @Test func topLevelObjectIsOneIssue() {
        let result = RosterDecoder.decode(Data(#"{"agents": []}"#.utf8))
        #expect(result.sessions.isEmpty)
        #expect(result.issues.count == 1)
        #expect(result.issues[0].index == nil)
        #expect(result.issues[0].message.contains("an object"))
    }

    @Test func emptyDataIsOneIssue() {
        let result = RosterDecoder.decode(Data())
        #expect(result.sessions.isEmpty)
        #expect(result.issues.count == 1)
    }

    @Test func garbageIsOneIssue() {
        let result = RosterDecoder.decode(Data("not json at all".utf8))
        #expect(result.sessions.isEmpty)
        #expect(result.issues.count == 1)
    }

    @Test func emptyArrayIsClean() {
        let result = RosterDecoder.decode(Data("[]".utf8))
        #expect(result.sessions.isEmpty)
        #expect(result.issues.isEmpty)
    }

    // MARK: - Identity fallbacks

    @Test func idFallsBackToSessionId() {
        let json = #"""
        [{"cwd":"/tmp/a","kind":"background","startedAt":1000,
          "sessionId":"57084123-50ff-46c8-9e1b-431ac517df70"}]
        """#
        let result = RosterDecoder.decode(Data(json.utf8))
        #expect(result.issues.isEmpty)
        #expect(result.sessions.first?.id == "57084123-50ff-46c8-9e1b-431ac517df70")
    }

    @Test func idFallsBackToCwdAndStartedAt() {
        let json = #"[{"cwd":"/tmp/a","kind":"interactive","startedAt":1788331923028}]"#
        let result = RosterDecoder.decode(Data(json.utf8))
        #expect(result.issues.isEmpty)
        #expect(result.sessions.first?.id == "/tmp/a@1788331923028")
        #expect(result.sessions.first?.kind == .interactive)
    }

    @Test func mistypedKnownFieldsKeepRawValues() {
        let json = #"""
        [{"cwd":"/tmp/a","kind":7,"startedAt":1000,"pid":"nope","name":[],"status":"asleep"}]
        """#
        let result = RosterDecoder.decode(Data(json.utf8))
        let session = result.sessions.first
        #expect(session?.kind == .background)
        #expect(session?.pid == nil)
        #expect(session?.name == nil)
        #expect(session?.status == nil)
        #expect(session?.extra["kind"] == .number(7))
        #expect(session?.extra["pid"] == .string("nope"))
        #expect(session?.extra["name"] == .array([]))
        #expect(session?.extra["status"] == .string("asleep"))
        #expect(result.issues.count == 4)
    }

    @Test func rowWithoutCwdIsDroppedButOthersSurvive() {
        let json = #"""
        [{"kind":"background","startedAt":1000},
         {"cwd":"/tmp/b","kind":"background","startedAt":2000},
         12]
        """#
        let result = RosterDecoder.decode(Data(json.utf8))
        #expect(result.sessions.count == 1)
        #expect(result.sessions[0].cwd == "/tmp/b")
        #expect(result.issues.count == 2)
        #expect(result.issues[0].description == "[0] cwd: missing")
        #expect(result.issues[1].index == 2)
    }

    // MARK: - Round trip

    @Test func sessionRoundTrips() throws {
        let original = Session(
            id: "b3919c35", cwd: "/Users/rf-studio/code/fun/ccc/.claude/worktrees/v0",
            kind: .background, startedAt: Date(timeIntervalSince1970: 1_788_331_923.028),
            state: .working, status: .busy, pid: 85001, waitingFor: "input needed",
            sessionId: "57084123-50ff-46c8-9e1b-431ac517df70", name: "ccc",
            extra: ["tempo": .string("active"),
                    "fan": .array([.object(["id": .string("x"), "n": .number(2), "ok": .bool(true)])]),
                    "nothing": .null])
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(Session.self, from: data) == original)
    }

    @Test func jsonValueEncodesAsPlainJSON() throws {
        let value = JSONValue.object(["a": .number(1)])
        let data = try JSONEncoder().encode(value)
        #expect(String(decoding: data, as: UTF8.self) == #"{"a":1}"#)
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == value)
    }
}
