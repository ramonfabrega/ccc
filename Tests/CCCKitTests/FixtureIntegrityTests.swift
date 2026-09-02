import CryptoKit
import Foundation
import Testing

/// Every recorded fixture carries its sha256 in its meta.json, and this
/// test checks the bytes on disk against it. The recording proves the
/// bytes, git proves the commit; neither sees the bytes change between
/// them — core.autocrlf rewrote stream.bin once (504,383 → 443,681) and
/// nothing noticed until the replay disagreed. Regenerate the hash only
/// with the fixture, via scripts/record-*.
@Suite struct FixtureIntegrityTests {
    struct Meta: Decodable { var sha256: String?; var bytes: Int? }

    @Test(arguments: ["attach/attach", "stream/stream"])
    func fixtureMatchesItsRecordedHash(_ base: String) throws {
        let meta = try JSONDecoder().decode(Meta.self, from: Fixtures.data("\(base).meta.json"))
        let bytes = try Fixtures.data("\(base).bin")
        let sha = try #require(meta.sha256, "\(base).meta.json has no sha256")
        #expect(bytes.count == meta.bytes, "\(base).bin is \(bytes.count) bytes, meta says \(meta.bytes ?? -1)")
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        #expect(digest == sha, "\(base).bin changed since it was recorded")
    }
}
