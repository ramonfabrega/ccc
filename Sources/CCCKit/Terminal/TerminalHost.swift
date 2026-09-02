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
    /// Press a named key. The host encodes it (kitty protocol, application
    /// cursor mode, whatever the child negotiated) exactly as it would for
    /// the user — CLAUDE.md "Keys are the core's job". Returns false when
    /// this host cannot encode keys (the pure replay host).
    @discardableResult
    func press(_ key: NamedKey) -> Bool
    /// Paste text the way the child negotiated: bracketed (mode 2004) when
    /// on, raw when off, kitty clipboard event when that protocol is live.
    /// The host does the framing — never hand-roll `ESC[200~`. Returns
    /// false when this host cannot paste or nothing was written.
    @discardableResult
    func paste(_ text: String) -> Bool
}

/// The keys `ccc send --key` accepts. Spelled the way a human types them:
/// `enter`, `shift-enter`, `ctrl-c`, `ctrl-z`, `escape`, `tab`, `up`, `f1`.
public struct NamedKey: Sendable, Equatable, CustomStringConvertible {
    public enum Base: String, Sendable, CaseIterable {
        case enter, escape, tab, backspace, delete, space
        case up, down, left, right, home, end, pageup, pagedown
        case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    }
    public var base: Base?
    /// A single printable character when `base` is nil (`ctrl-c` → "c").
    public var character: Character?
    public var shift = false
    public var control = false
    public var option = false
    public var command = false

    public init?(_ text: String) {
        var parts = text.lowercased().split(separator: "-").map(String.init)
        guard let last = parts.popLast() else { return nil }
        for modifier in parts {
            switch modifier {
            case "shift", "s": shift = true
            case "ctrl", "control", "c": control = true
            case "opt", "option", "alt", "a", "meta", "m": option = true
            case "cmd", "command", "super": command = true
            default: return nil
            }
        }
        if let base = Base(rawValue: last) {
            self.base = base
        } else if last.count == 1, let ch = last.first {
            self.character = ch
        } else if last == "return" {
            self.base = .enter
        } else if last == "esc" {
            self.base = .escape
        } else {
            return nil
        }
    }

    public var description: String {
        var s: [String] = []
        if control { s.append("ctrl") }
        if option { s.append("opt") }
        if shift { s.append("shift") }
        if command { s.append("cmd") }
        s.append(base?.rawValue ?? String(character ?? "?"))
        return s.joined(separator: "-")
    }
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
