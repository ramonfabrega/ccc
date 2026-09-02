import CCCKit
import Foundation
import Testing

/// The first v1 check: the libghostty-vt core replaying the v0 fixture must
/// produce the same grids SwiftTerm did (the goldens in Fixtures/attach).
/// Differences are findings about one core or the other, never silently
/// accepted: the test prints a row-level diff so the disagreement is legible.
@Suite struct GhosttyReplayTests {
    @Test @MainActor func coreConstructs() {
        let host = GhosttyHost(cols: 20, rows: 4)
        #expect(host.lastError == nil)
        host.feed(Data("hello\r\nworld".utf8))
        let grid = host.snapshot()
        #expect(grid.cols == 20 && grid.rows == 4)
        #expect(grid.lines[0].hasPrefix("hello"))
        #expect(grid.lines[1].hasPrefix("world"))
        #expect(grid.cursor.row == 1 && grid.cursor.col == 5)
    }

    @Test @MainActor func repliesGoBackThroughTheSeam() {
        let host = GhosttyHost(cols: 20, rows: 4)
        var replies = Data()
        host.onOutput = { replies.append($0) }
        host.feed(Data("\u{1b}[6n".utf8))        // DSR: cursor position report
        #expect(replies == Data("\u{1b}[1;1R".utf8), "got \(Array(replies))")
    }

    /// Check 2 of docs/CHECKS.md: the core frames a paste per mode 2004.
    @Test @MainActor func pasteIsBracketedOnlyWhenTheChildAskedForIt() {
        let host = GhosttyHost(cols: 40, rows: 4)
        var out = Data()
        host.onOutput = { out.append($0) }
        #expect(host.paste("plain\nmulti") == true)
        // Unbracketed: the core rewrites LF to CR, as a typed Return would
        // arrive (xterm behaviour); the child never sees a bare \n.
        #expect(out == Data("plain\rmulti".utf8), "raw-with-CR when mode 2004 is off; got \(Array(out))")
        out.removeAll()
        host.feed(Data("\u{1b}[?2004h".utf8))            // child enables bracketed paste
        #expect(host.paste("plain\nmulti") == true)
        #expect(out == Data("\u{1b}[200~plain\nmulti\u{1b}[201~".utf8), "bracketed when on; got \(Array(out))")
        #expect(host.paste("") == false)
    }

    @Test @MainActor func everyPhaseMatchesTheSwiftTermGolden() throws {
        let meta = try ReplayTests.meta()
        let bytes = try Fixtures.data("attach/attach.bin")
        for phase in meta.phases {
            let host = GhosttyHost(cols: meta.cols, rows: meta.rows)
            host.feed(bytes.prefix(phase.bytes))
            let rendered = host.snapshot().rendered()
            let golden = try String(contentsOf: Fixtures.url("attach/attach.golden.\(phase.name).txt"), encoding: .utf8)
                .trimmingTrailingNewline()
            if rendered != golden {
                let a = rendered.split(separator: "\n", omittingEmptySubsequences: false)
                let b = golden.split(separator: "\n", omittingEmptySubsequences: false)
                var diff: [String] = []
                for i in 0..<max(a.count, b.count) {
                    let ra = i < a.count ? String(a[i]) : "<missing>"
                    let rb = i < b.count ? String(b[i]) : "<missing>"
                    if ra != rb { diff.append("row \(i)\n  ghostty: \(ra)\n  swiftterm: \(rb)") }
                }
                let detail = Array(diff.prefix(6)).joined(separator: "\n")
                Issue.record("phase \(phase.name): \(diff.count) rows differ\n\(detail)")
            }
        }
    }
}
