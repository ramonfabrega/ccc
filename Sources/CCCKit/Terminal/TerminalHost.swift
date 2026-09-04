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
    /// Asked before `press` encodes a key; true means the owner took the
    /// press and nothing is sent. The one gate on the key path, so the
    /// window's keyboard and `ccc send --key` meet the same answer. Set by
    /// `AttachSession` for the harness's ← gesture (`LeaveGesture`); nil
    /// on a pane that has no such gesture (a shell).
    var keyInterceptor: ((NamedKey) -> Bool)? { get set }
    /// Resize the grid. The owner mirrors the same size onto the PTY.
    func resize(cols: Int, rows: Int)
    /// The grid as the user sees it. The headless surface and the test
    /// oracle: the GUI pane and `ccc snapshot` produce it through the same
    /// function.
    ///
    /// `colors: true` asks for resolved colour as well (item 12a). It is a
    /// parameter rather than always-on because the callers that drive the
    /// pane — `waitUntilDrawn` every 250 ms, `LeaveGesture`, `LinkScanner` —
    /// want text and nothing else. A host that cannot answer in colour
    /// leaves `Grid.colors` nil; it never fabricates one.
    func snapshot(colors: Bool) -> Grid
    /// The AppKit view, if this host renders. Headless hosts return nil.
    var view: NSView? { get }
    /// What reached the screen: frames handed to the on-screen layer and
    /// when the last one was. `nil` for a host with no screen. This is the
    /// number that lets an agent and a human agree on whether the pane is
    /// actually visible (docs/DESIGN.md §7): the snapshot says what the
    /// core holds, this says what was presented.
    var presentation: (frames: Int, lastAt: Date?)? { get }
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

extension TerminalHost {
    /// Hosts without a screen (the headless replay host, SwiftTerm's stock
    /// view which draws through AppKit and needs no count) report nothing.
    public var presentation: (frames: Int, lastAt: Date?)? { nil }
}

/// A region of the viewport to select (item 12b), in the coordinates every
/// other verb uses: column and row of the grid a snapshot prints, both ends
/// **inclusive**, so `0,0 → 4,0` is five cells and not four.
///
/// `rectangle` is the block selection a terminal makes with ⌥-drag: the same
/// two corners read as opposite corners of a box instead of as a run of text
/// that wraps at the right margin. The core does both from these two points,
/// which is why the flag rides here rather than becoming a second verb.
public struct SelectionRegion: Codable, Sendable, Equatable {
    public struct Point: Codable, Sendable, Equatable {
        public var col: Int
        public var row: Int
        public init(col: Int, row: Int) {
            self.col = col
            self.row = row
        }
    }

    /// How much a point takes with it — the twin of the click count (item
    /// 13). One click selects cells, two select the word, three the line,
    /// and the core owns all three rules.
    public enum Grain: String, Codable, Sendable {
        case cell, word, line
    }

    public var from: Point
    public var to: Point
    public var rectangle: Bool
    /// Optional on the wire, not in meaning: a v9 `ccc select` sends no
    /// `grain` key at all and an older server must read that as `.cell`,
    /// which is what it always did (`ControlWireTests`, the `send`/`paste`
    /// precedent).
    public var grain: Grain?

    public init(from: Point, to: Point, rectangle: Bool = false, grain: Grain? = nil) {
        self.from = from
        self.to = to
        self.rectangle = rectangle
        self.grain = grain
    }

    public init(fromCol: Int, fromRow: Int, toCol: Int, toRow: Int, rectangle: Bool = false, grain: Grain? = nil) {
        self.init(from: Point(col: fromCol, row: fromRow), to: Point(col: toCol, row: toRow),
                  rectangle: rectangle, grain: grain)
    }

    /// Negative coordinates would clamp to zero on the way into the core's
    /// `uint16` and silently select from column 0; a host says no instead.
    public var isNonNegative: Bool {
        from.col >= 0 && from.row >= 0 && to.col >= 0 && to.row >= 0
    }
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
    /// Resolved colour, one run-length-encoded array per row, **present
    /// only when the snapshot was asked for it** (`snapshot(colors: true)`,
    /// `ccc snapshot --color`, `ccc replay --color`). `nil` otherwise, and
    /// `nil` from a core that cannot answer — which is honest rather than
    /// empty, and is why `color(col:row:)` returns an optional.
    ///
    /// Off by default because `snapshot()` is a hot path: `waitUntilDrawn`
    /// takes one every 250 ms during an attach transition, and `LeaveGesture`
    /// and `LinkScanner` each read one per gesture. None of them want colour,
    /// and a grid that always carried it would put ~4,400 cells of RGB
    /// through the control socket on every `ccc snapshot`.
    public var colors: [[ColorSpan]]?

    /// `len` cells from `col`, all painted the same. Colours are **resolved**
    /// — `inverse` applied, frame defaults substituted — so this is what is
    /// on the screen, comparable to `ccc pixel` by string equality.
    public struct ColorSpan: Codable, Sendable, Equatable {
        public var col: Int
        public var len: Int
        public var fg: Frame.RGB
        public var bg: Frame.RGB
        public init(col: Int, len: Int, fg: Frame.RGB, bg: Frame.RGB) {
            self.col = col
            self.len = len
            self.fg = fg
            self.bg = bg
        }
    }

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

extension TerminalHost {
    /// The text grid — every caller that drives the pane rather than judging
    /// its colour. Keeps the ~40 existing call sites reading as they did.
    public func snapshot() -> Grid { snapshot(colors: false) }
}
