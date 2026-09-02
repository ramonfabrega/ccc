import CCCKit
import Foundation
import Testing

/// The primary-screen stream (Fixtures/stream, made by scripts/record-stream):
/// 500 KB of real program output with scrollback and a mid-stream resize.
/// The alt-screen attach recording could not see scrollback or reflow; this
/// one exists because a blank grid after ~2000 lines slipped past it.
/// No goldens here: the oracle is agreement between the two cores, which is
/// what the swap decision rests on. A disagreement is a finding about one of
/// them and is printed as a row diff.
@Suite struct StreamReplayTests {
    struct Meta: Decodable {
        var cols: Int
        var rows: Int
        var resizeAtBytes: Int?
        var resizedTo: [Int]?
    }

    static func meta() throws -> Meta {
        try JSONDecoder().decode(Meta.self, from: Fixtures.data("stream/stream.meta.json"))
    }

    @MainActor
    static func replay(_ make: (Int, Int) -> TerminalHost, resize: Bool) throws -> Grid {
        let meta = try meta()
        let bytes = try Fixtures.data("stream/stream.bin")
        let host = make(meta.cols, meta.rows)
        if resize, let at = meta.resizeAtBytes, let to = meta.resizedTo, to.count == 2, at < bytes.count {
            host.feed(bytes.prefix(at))
            host.resize(cols: to[0], rows: to[1])
            host.feed(bytes.suffix(from: at))
        } else {
            host.feed(bytes)
        }
        return host.snapshot()
    }

    /// Compares what is on screen (size, rows, cursor). Scrollback row counts
    /// are each core's retention policy, not agreement about the screen, and
    /// are asserted separately.
    static func report(_ a: Grid, _ b: Grid, _ label: String) {
        guard a.cols != b.cols || a.rows != b.rows || a.lines != b.lines || a.cursor != b.cursor else { return }
        var diff: [String] = []
        for i in 0..<max(a.lines.count, b.lines.count) {
            let ra = i < a.lines.count ? a.lines[i] : "<missing>"
            let rb = i < b.lines.count ? b.lines[i] : "<missing>"
            if ra != rb { diff.append("row \(i)\n  ghostty:   \(ra)\n  swiftterm: \(rb)") }
        }
        let head = Array(diff.prefix(6)).joined(separator: "\n")
        Issue.record("\(label): \(a.cols)x\(a.rows) vs \(b.cols)x\(b.rows), cursor \(a.cursor) vs \(b.cursor), \(diff.count) rows differ\n\(head)")
    }

    @Test @MainActor func bothCoresAgreeWithoutResize() throws {
        let g = try Self.replay({ GhosttyHost(cols: $0, rows: $1) }, resize: false)
        let s = try Self.replay({ HeadlessHost(cols: $0, rows: $1) }, resize: false)
        #expect(g.lines.contains { $0.contains("bold red underline italic") }, "the last line of the stream should be on screen")
        #expect(s.lines.contains { $0.contains("bold red underline italic") }, "the last line of the stream should be on screen (SwiftTerm went blank here once)")
        Self.report(g, s, "no resize")
    }

    @Test @MainActor func bothCoresAgreeAfterTheRecordedResize() throws {
        let meta = try Self.meta()
        try #require(meta.resizeAtBytes != nil, "fixture has no resize point")
        let g = try Self.replay({ GhosttyHost(cols: $0, rows: $1) }, resize: true)
        let s = try Self.replay({ HeadlessHost(cols: $0, rows: $1) }, resize: true)
        #expect(g.cols == meta.resizedTo![0] && g.rows == meta.resizedTo![1])
        #expect(s.cols == g.cols && s.rows == g.rows)
        Self.report(g, s, "after resize to \(meta.resizedTo!)")
    }

    @Test @MainActor func scrollbackIsRetainedByBothCores() throws {
        let g = try Self.replay({ GhosttyHost(cols: $0, rows: $1) }, resize: false)
        let s = try Self.replay({ HeadlessHost(cols: $0, rows: $1) }, resize: false)
        #expect(g.scrollbackRows > 1000, "ghostty kept \(g.scrollbackRows) rows")
        #expect(s.scrollbackRows > 1000, "swiftterm kept \(s.scrollbackRows) rows")
    }
}
