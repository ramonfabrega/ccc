import CCCKit
import Foundation
import Testing

/// Regression: after more lines than the scrollback limit (2000) the grid
/// went blank, because `GridBuilder` read rows through the scroll-invariant
/// accessor without SwiftTerm's `linesTop` offset once the ring buffer had
/// trimmed. The alt-screen attach fixture never scrolls, so it could not
/// see this; the primary-screen stream fixture on v1 did.
@Suite struct ScrollbackTests {
    @Test @MainActor func gridStaysVisiblePastTheScrollbackLimit() {
        let host = HeadlessHost(cols: 40, rows: 10, scrollback: 2_000)
        var bytes = Data()
        for i in 1...5_000 { bytes.append(contentsOf: "line \(i)\r\n".utf8) }
        host.feed(bytes)
        let grid = host.snapshot()
        let text = grid.rendered()
        #expect(text.contains("line 4999"), "the last lines must be on screen, got:\n\(text)")
        #expect(grid.lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count >= 9)
        #expect(grid.scrollbackRows > 0)
    }
}
