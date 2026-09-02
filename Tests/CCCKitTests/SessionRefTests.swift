import Foundation
import Testing

@testable import CCCKit

/// The address. `id` alone stopped being one when a second daemon entered
/// view, so every surface now carries the host — but the local form must
/// still read and type exactly as it did in v0 and v1.
@Suite struct SessionRefTests {
    @Test func aBareIdIsLocal() throws {
        let ref = try #require(SessionRef.parse("a1b2c3d4"))
        #expect(ref.host == Host.localName)
        #expect(ref.id == "a1b2c3d4")
        #expect(ref.isLocal)
        // The whole point: what a v1 hand types keeps printing as it did.
        #expect(ref.description == "a1b2c3d4")
    }

    @Test func aHostQualifiedRefRoundTrips() throws {
        let ref = try #require(SessionRef.parse("studio:a1b2"))
        #expect(ref.host == "studio")
        #expect(ref.id == "a1b2")
        #expect(!ref.isLocal)
        #expect(ref.description == "studio:a1b2")
        #expect(SessionRef.parse(ref.description) == ref)
    }

    /// `local:a1b2` is the long way to write `a1b2`; it parses, and prints
    /// back as the short form so one session never has two spellings on
    /// screen.
    @Test func theExplicitLocalHostNormalizes() throws {
        let ref = try #require(SessionRef.parse("local:a1b2"))
        #expect(ref == SessionRef(id: "a1b2"))
        #expect(ref.description == "a1b2")
    }

    @Test(arguments: ["", ":", "a:", ":b", "a:b:c", "studio:"])
    func nonAddresses(text: String) {
        #expect(SessionRef.parse(text) == nil, "'\(text)' must not parse as a ref")
    }

    /// One string on the wire, not a nested object — an agent can paste what
    /// it read in `--json` straight back into `ccc attach`.
    @Test func codesAsOneString() throws {
        let encoded = try JSONEncoder().encode(SessionRef(host: "studio", id: "a1b2"))
        #expect(String(decoding: encoded, as: UTF8.self) == "\"studio:a1b2\"")
        let decoded = try JSONDecoder().decode(SessionRef.self, from: Data("\"a1b2\"".utf8))
        #expect(decoded == SessionRef(id: "a1b2"))
    }

    @Test func aMalformedRefIsADecodeError() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SessionRef.self, from: Data("\"a:b:c\"".utf8))
        }
    }

    /// The reason the wire label stayed `id`: a v1 `ccc` on PATH sends this
    /// exact bytes for `ccc attach a1b2`, and a v2 server must still take it.
    @Test func aV1AttachRequestStillDecodes() throws {
        let json = Data(#"{"attach":{"id":"a1b2"}}"#.utf8)
        let decoded = try JSONDecoder().decode(ControlRequest.self, from: json)
        guard case .attach(let ref) = decoded else {
            Issue.record("not an attach: \(decoded)")
            return
        }
        #expect(ref == SessionRef(id: "a1b2"))
    }

    @Test func aHostQualifiedAttachRequestRoundTrips() throws {
        let request = ControlRequest.attach(id: SessionRef(host: "studio", id: "a1b2"))
        let decoded = try JSONDecoder().decode(ControlRequest.self, from: JSONEncoder().encode(request))
        guard case .attach(let ref) = decoded else {
            Issue.record("not an attach: \(decoded)")
            return
        }
        #expect(ref.host == "studio")
        #expect(ref.id == "a1b2")
    }
}
