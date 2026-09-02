import Foundation
import SwiftTerm

/// The one function both hosts share: SwiftTerm's screen state → `Grid`.
/// Because the window pane and the headless pane both call this, a headless
/// snapshot is, by construction, what the user sees.
enum GridBuilder {
    @MainActor
    static func grid(from terminal: Terminal, cursorVisible: Bool) -> Grid {
        let dims = terminal.getDims()
        let top = terminal.getTopVisibleRow()
        var lines: [String] = []
        lines.reserveCapacity(dims.rows)
        for row in 0..<dims.rows {
            // getLine is relative to the visible viewport when the user has
            // not scrolled; use the buffer row so a scrolled-back view still
            // renders what is on screen.
            let text = terminal.getScrollInvariantLine(row: top + row)?
                .translateToString(trimRight: false) ?? ""
            lines.append(pad(text, to: dims.cols))
        }
        let cursor = terminal.getCursorLocation()
        return Grid(
            cols: dims.cols,
            rows: dims.rows,
            lines: lines,
            cursor: .init(col: cursor.x, row: cursor.y, visible: cursorVisible),
            scrollbackRows: top
        )
    }

    private static func pad(_ text: String, to cols: Int) -> String {
        let count = text.count
        if count == cols { return text }
        if count < cols { return text + String(repeating: " ", count: cols - count) }
        return String(text.prefix(cols))
    }
}
