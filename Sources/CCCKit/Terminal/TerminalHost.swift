import AppKit
import Foundation

/// The one-page seam (docs/TERMINAL.md). Everything above it — roster, PTY,
/// control socket, CLI — talks to a terminal only through these five
/// members. v0 fills it with SwiftTerm (`SwiftTermHost` for the window,
/// `HeadlessHost` for tests and `--headless`); v1 fills it with libghostty-vt
/// and our Metal renderer. Nothing outside `Terminal/` may import SwiftTerm.
@MainActor
public protocol TerminalHost: AnyObject {
    /// Bytes from the child (the PTY master) into the terminal core.
    func feed(_ bytes: Data)
    /// Bytes the terminal wants sent to the child — key encodings, replies
    /// to queries (DA, cursor position), bracketed-paste wrapping. The owner
    /// wires this to the PTY's write side.
    var onOutput: ((Data) -> Void)? { get set }
    /// Resize the grid. The owner mirrors the same size onto the PTY.
    func resize(cols: Int, rows: Int)
    /// The text grid as the user sees it. The headless surface and the
    /// test oracle: the GUI pane and `ccc snapshot` produce it through the
    /// same function.
    func snapshot() -> Grid
    /// The AppKit view, if this host renders. Headless hosts return nil.
    var view: NSView? { get }
}

/// A rendered terminal grid: rows of text, cursor, size. Deliberately plain —
/// no attributes yet. Attributes join when a renderer check needs them.
public struct Grid: Codable, Sendable, Equatable {
    public var cols: Int
    public var rows: Int
    /// Exactly `rows` strings, each padded or clipped to `cols` characters.
    public var lines: [String]
    public var cursor: Cursor
    /// Scrollback rows above the viewport, when the host knows.
    public var scrollbackRows: Int

    public struct Cursor: Codable, Sendable, Equatable {
        public var col: Int
        public var row: Int
        public var visible: Bool
        public init(col: Int, row: Int, visible: Bool) {
            self.col = col
            self.row = row
            self.visible = visible
        }
    }

    public init(cols: Int, rows: Int, lines: [String], cursor: Cursor, scrollbackRows: Int = 0) {
        self.cols = cols
        self.rows = rows
        self.lines = lines
        self.cursor = cursor
        self.scrollbackRows = scrollbackRows
    }

    /// The grid as text: one line per row, trailing spaces trimmed. This is
    /// what `ccc snapshot` prints and what golden files store.
    public func rendered(trimTrailing: Bool = true) -> String {
        lines.map { line in
            trimTrailing ? String(line.reversed().drop(while: { $0 == " " }).reversed()) : line
        }.joined(separator: "\n")
    }
}
