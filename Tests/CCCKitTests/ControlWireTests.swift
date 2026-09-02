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

    /// The far side's `ccc version --json` is read by `hosts check`; a
    /// newer ccc adding fields there must not break an older reader, and
    /// the two fields that carry the number are the ones pinned.
    @Test func versionCrossesTheHopOnTwoFields() throws {
        let json = Data(#"{"version":"0.1.5","build":57,"executablePath":"/x/ccc.app/Contents/MacOS/ccc","bundlePath":"/x/ccc.app","futureKey":true}"#.utf8)
        let info = try JSONDecoder().decode(BuildInfo.self, from: json)
        #expect(info.short == "0.1.5 (57)")
        // No `dev` key: that ccc predates the lane split, and was a release.
        #expect(!info.dev)
    }
}
