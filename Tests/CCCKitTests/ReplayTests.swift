import CCCKit
import Foundation
import Testing

/// The recorded `claude attach` (Fixtures/attach, made by scripts/record-attach)
/// replayed through the headless host and compared to golden grids taken at
/// each phase boundary. This is the oracle every renderer change is judged
/// against (CLAUDE.md "Recorded sessions are fixtures"). Regenerate goldens
/// deliberately with `ccc replay <bin> --bytes <phase.bytes>` when the
/// change in output is understood, never to make the test pass.
@Suite struct ReplayTests {
    struct Meta: Decodable {
        struct Phase: Decodable { var name: String; var bytes: Int }
        var cols: Int
        var rows: Int
        var phases: [Phase]
    }

    static func meta() throws -> Meta {
        try JSONDecoder().decode(Meta.self, from: Fixtures.data("attach/attach.meta.json"))
    }

    @Test @MainActor func everyPhaseMatchesItsGolden() throws {
        let meta = try Self.meta()
        let bytes = try Fixtures.data("attach/attach.bin")
        for phase in meta.phases {
            let host = HeadlessHost(cols: meta.cols, rows: meta.rows)
            host.feed(bytes.prefix(phase.bytes))
            let rendered = host.snapshot().rendered()
            let goldenURL = Fixtures.url("attach/attach.golden.\(phase.name).txt")
            let golden = try String(contentsOf: goldenURL, encoding: .utf8)
            #expect(rendered == golden.trimmingTrailingNewline(), "phase \(phase.name) differs from \(goldenURL.lastPathComponent)")
        }
    }

    /// Feeding the same bytes one chunk at a time (as the PTY would) must
    /// give the same grid as feeding them at once: the parser keeps state
    /// across chunk boundaries.
    @Test @MainActor func chunkedFeedEqualsWholeFeed() throws {
        let meta = try Self.meta()
        let bytes = try Fixtures.data("attach/attach.bin")
        let events = try String(contentsOf: Fixtures.url("attach/attach.events"), encoding: .utf8)
        let whole = HeadlessHost(cols: meta.cols, rows: meta.rows)
        let chunked = HeadlessHost(cols: meta.cols, rows: meta.rows)
        let last = meta.phases.first { $0.name == "type" }!.bytes
        whole.feed(bytes.prefix(last))
        for line in events.split(separator: "\n") {
            let parts = line.split(separator: " ").compactMap { Int($0) }
            guard parts.count == 3 else { continue }
            let (offset, length) = (parts[1], parts[2])
            guard offset + length <= last else { break }
            chunked.feed(bytes.subdata(in: offset..<(offset + length)))
        }
        #expect(whole.snapshot() == chunked.snapshot())
    }

    @Test @MainActor func startupScreenShowsTheSession() throws {
        let meta = try Self.meta()
        let bytes = try Fixtures.data("attach/attach.bin")
        let host = HeadlessHost(cols: meta.cols, rows: meta.rows)
        host.feed(bytes.prefix(meta.phases[0].bytes))
        let text = host.snapshot().rendered()
        #expect(text.contains("ccc-exp3"), "the session name bar should be on screen")
        #expect(text.contains("❯"), "the prompt should be on screen")
    }
}

extension String {
    func trimmingTrailingNewline() -> String {
        hasSuffix("\n") ? String(dropLast()) : self
    }
}
