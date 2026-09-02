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
}
