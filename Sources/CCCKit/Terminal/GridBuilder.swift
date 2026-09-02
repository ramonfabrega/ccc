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
            // getLine(row:) is the visible viewport: SwiftTerm adds yDisp
            // itself. The scroll-invariant accessor needs a `linesTop`
            // offset once the ring buffer has trimmed (past the scrollback
            // limit), and without it every row came back nil — a blank grid
            // after ~2000 lines of primary-screen output. Found by the stream
            // fixture; the alt-screen recording could not see it.
            // Empty cells hold NUL in SwiftTerm's buffer; the grid is text.
            let text = terminal.getLine(row: row)?
                .translateToString(trimRight: false, characterProvider: { cell in
                    let ch = cell.getCharacter()
                    return ch == "\u{0}" ? " " : ch
                }) ?? ""
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
