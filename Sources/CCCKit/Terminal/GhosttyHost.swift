import AppKit
import Foundation
import GhosttyVt

/// `TerminalHost` over libghostty-vt (vendor/ghostty, docs/vt/surface.txt).
/// This is the v1 core: parser, screen state, render-state deltas, and the
/// terminal's own replies to the child (`WRITE_PTY`). Rendering is a
/// separate object that reads the same render state; without one this host
/// is the headless replay/snapshot core, which is where v1 starts — the
/// first check is "does the new core produce the v0 golden grids".
@MainActor
public final class GhosttyHost: TerminalHost {
    /// Internal, non-owning read for `GhosttyKeys` (the encoder syncs its
    /// options from this terminal's live modes). Nothing outside the package
    /// touches the raw handle.
    private(set) var terminal: GhosttyTerminal?
    private var keys: GhosttyKeys?
    /// What the window last said (nil until anyone says anything) and what
    /// was actually written to the child. They differ while the child has
    /// not yet enabled mode 1004 — see `setFocused`.
    private var desiredFocus: Bool?
    private var lastFocusReported: Bool?
    private var cellSize: (width: UInt32, height: UInt32) = (8, 17)

    public var onOutput: ((Data) -> Void)?
    public var keyInterceptor: ((NamedKey) -> Bool)?
    public var view: NSView? { nil }
    public private(set) var lastError: String?

    /// Bumped on every `feed` so a renderer can skip frames when nothing
    /// arrived; the render state's own dirty tracking is the fine grain.
    public private(set) var generation: UInt64 = 0

    /// The colours this terminal was built with. Read-only: the core copies
    /// them at `init`, and changing them afterwards would have to redraw
    /// every cached glyph batch as well.
    public let theme: Theme

    public init(cols: Int = 80, rows: Int = 24, theme: Theme = .active) {
        self.theme = theme
        var t: GhosttyTerminal?
        guard ghostty_terminal_new(nil, &t, UInt16(clamping: cols), UInt16(clamping: rows)) == GHOSTTY_SUCCESS, let t else {
            lastError = "ghostty_terminal_new failed"
            return
        }
        terminal = t

        // Replies (DA, DSR, kitty keyboard query, mode reports) go back to
        // the child through the seam's onOutput.
        // ghostty_terminal_set: pointer-typed options (userdata, callbacks)
        // are passed DIRECTLY as `value`; non-pointer types by pointer.
        _ = ghostty_terminal_set(t, GHOSTTY_TERMINAL_OPT_USERDATA, Unmanaged.passUnretained(self).toOpaque())
        let writePty: GhosttyTerminalWritePtyFn = { _, userdata, data, len in
            guard let userdata, let data, len > 0 else { return }
            let host = Unmanaged<GhosttyHost>.fromOpaque(userdata).takeUnretainedValue()
            let bytes = Data(bytes: data, count: Int(len))
            MainActor.assumeIsolated { host.onOutput?(bytes) }
        }
        _ = ghostty_terminal_set(t, GHOSTTY_TERMINAL_OPT_WRITE_PTY, unsafeBitCast(writePty, to: UnsafeRawPointer.self))

        // Scrollback policy is ours (docs/TERMINAL.md): the core's default
        // kept ~500 rows of a 60k-line stream (a byte cap). Match SwiftTerm's
        // 2000-line stand-in for a like-for-like scoreboard, and lift the
        // byte cap so lines, not bytes, are the limit. Non-pointer option
        // values are passed by pointer.
        var lines: Int = GhosttyHost.scrollbackLines
        _ = ghostty_terminal_set(t, GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_LINES, &lines)
        _ = ghostty_terminal_set(t, GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_BYTES, nil)

        install(theme, into: t)
    }

    /// Tell the core what our colours are.
    ///
    /// Without this the core answers with its *own* fallbacks — pure black,
    /// pure white, and the Tomorrow Night palette it ships — because the
    /// embeddable terminal expects its host to state a preference and ccc
    /// stated none (measured 2026-09-03; see docs/EVIDENCE.md "the pane
    /// wore Ghostty's theme"). These four options are the whole of what the
    /// core owns; cursor-text and selection never reach it, because the
    /// renderer draws those.
    ///
    /// Each option is set as a *default*, which is the distinction that
    /// matters: `OSC 4/10/11/12` from the child still override it and keep
    /// overriding it, so a program that themes itself is not fighting us.
    /// Setting them is also what makes the *answers* right — `OSC 11` is
    /// how a TUI asks whether it is on a dark background, and an unset
    /// background is a question the core cannot answer.
    private func install(_ theme: Theme, into t: GhosttyTerminal) {
        func rgb(_ c: Frame.RGB) -> GhosttyColorRgb { GhosttyColorRgb(r: c.r, g: c.g, b: c.b) }

        var background = rgb(theme.background)
        var foreground = rgb(theme.foreground)
        var cursor = rgb(theme.cursor)
        _ = ghostty_terminal_set(t, GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND, &background)
        _ = ghostty_terminal_set(t, GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND, &foreground)
        _ = ghostty_terminal_set(t, GHOSTTY_TERMINAL_OPT_COLOR_CURSOR, &cursor)

        // Slots 16–255 are the xterm cube and grey ramp — arithmetic that
        // applications hardcode, not a choice. Seeding from the core's own
        // generator and overwriting only the named sixteen means our cube
        // cannot drift from the core's, which a copied formula eventually
        // would.
        var palette = [GhosttyColorRgb](repeating: GhosttyColorRgb(), count: 256)
        ghostty_color_palette_default(&palette)
        for (index, colour) in theme.ansi.enumerated() { palette[index] = rgb(colour) }
        _ = ghostty_terminal_set(t, GHOSTTY_TERMINAL_OPT_COLOR_PALETTE, &palette)
    }

    /// Lines of scrollback kept per pane. A setting once the roster is ours.
    public static var scrollbackLines = 2_000

    isolated deinit {
        frameReader = nil          // its render state must go before the terminal
        keys = nil
        if let terminal { ghostty_terminal_free(terminal) }
    }

    public func feed(_ bytes: Data) {
        guard let terminal, !bytes.isEmpty else { return }
        bytes.withUnsafeBytes { raw in
            ghostty_terminal_vt_write(terminal, raw.baseAddress!.assumingMemoryBound(to: UInt8.self), raw.count)
        }
        generation &+= 1
        // The chunk that just landed may be the one that turned mode 1004
        // on — the TUI negotiates its modes in its first writes — so a
        // focus report the window asked for before the child was listening
        // goes out now. One Bool compare when there is nothing pending.
        flushFocus()
    }

    public func resize(cols: Int, rows: Int) {
        guard let terminal else { return }
        _ = ghostty_terminal_resize(terminal, UInt16(clamping: cols), UInt16(clamping: rows), cellSize.width, cellSize.height)
        generation &+= 1
    }

    /// Pixel size of one cell, for size reports and image protocols.
    public func setCellSize(width: Int, height: Int) {
        cellSize = (UInt32(clamping: width), UInt32(clamping: height))
        guard let terminal else { return }
        var cols: UInt16 = 0, rows: UInt16 = 0
        _ = ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_COLS, &cols)
        _ = ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_ROWS, &rows)
        _ = ghostty_terminal_resize(terminal, cols, rows, cellSize.width, cellSize.height)
    }

    /// Keys are the core's job (CLAUDE.md): `GhosttyKeys` hands the event to
    /// `ghostty_key_encoder_encode`, whose options are synced from this
    /// terminal first, so the bytes match what the child negotiated (kitty
    /// CSI-u, DECCKM, DECBKM). False when the core produced nothing — a bare
    /// modifier, or an unmapped key.
    public func press(_ key: NamedKey) -> Bool {
        guard terminal != nil else { return false }
        if keyInterceptor?(key) == true { return true }
        let keys = self.keys ?? GhosttyKeys(terminal: terminal)
        self.keys = keys
        let bytes = keys.encode(key)
        guard !bytes.isEmpty else { return false }
        onOutput?(bytes)
        return true
    }

    /// Paste through the core: it frames per mode 2004 (or emits a kitty
    /// clipboard event) and streams the result to WRITE_PTY → onOutput.
    /// Text the core deems unsafe (newlines, the bracketed-paste end
    /// sequence) is pasted anyway — `allow_unsafe` is true — because the
    /// caller here is `ccc send`, whose operator chose the text; the GUI
    /// pane confirms with the user first and passes it back through here.
    public func paste(_ text: String) -> Bool {
        guard let terminal, !text.isEmpty else { return false }
        let bytes = Array(text.utf8)
        let mime = Array("text/plain".utf8)
        return bytes.withUnsafeBufferPointer { body -> Bool in
            mime.withUnsafeBufferPointer { mimeBuf -> Bool in
                var mimes = [GhosttyString(ptr: mimeBuf.baseAddress, len: mimeBuf.count)]
                // The reader hands the writer our bytes; `userdata` carries
                // the buffer pointer, valid for the duration of the call.
                var payload = (ptr: body.baseAddress, len: body.count)
                let read: GhosttyMimeReaderFn = { userdata, _, writer in
                    guard let userdata else { return false }
                    let payload = userdata.assumingMemoryBound(to: (ptr: UnsafePointer<UInt8>?, len: Int).self).pointee
                    guard let ptr = payload.ptr, payload.len > 0, let write = writer.write else { return true }
                    return write(writer.userdata, ptr, payload.len)
                }
                return withUnsafeMutablePointer(to: &payload) { payloadPtr in
                    mimes.withUnsafeMutableBufferPointer { mimesBuf in
                        var paste = GhosttyPaste()
                        paste.size = MemoryLayout<GhosttyPaste>.size
                        paste.location = GHOSTTY_CLIPBOARD_LOCATION_STANDARD
                        paste.source = GHOSTTY_PASTE_SOURCE_CLIPBOARD
                        paste.mimes = UnsafePointer(mimesBuf.baseAddress)
                        paste.mimes_len = 1
                        paste.reader = GhosttyMimeReader(read: read, userdata: UnsafeMutableRawPointer(payloadPtr))
                        paste.allow_unsafe = true
                        var written = false
                        let result = ghostty_terminal_paste(terminal, &paste, &written)
                        if result != GHOSTTY_SUCCESS { lastError = "ghostty_terminal_paste: \(result.rawValue)" }
                        return result == GHOSTTY_SUCCESS && written
                    }
                }
            }
        }
    }

    // MARK: selection

    /// Select a region of the viewport, both ends inclusive, or clear the
    /// selection with `nil` (item 12b). Coordinates are the ones every other
    /// verb here uses — column and row of the *viewport*, the grid a
    /// snapshot prints — never screen or history points.
    ///
    /// The destination half of a selection: two points and a grain. The
    /// *hand* is `GhosttySelectGesture` (item 13), which turns a real drag
    /// into these same installs; this stays the twin's road — what `ccc
    /// select` and every golden drive — so the gesture and the command end
    /// in one place.
    ///
    /// `grain` is the double- and triple-click's twin: `.word` asks the core
    /// for the nearest word between the two points, `.line` for the lines
    /// they land on. The word and line *rules* are Ghostty's, never ours.
    ///
    /// Returns false when a point is off the grid, which is the core's
    /// answer, not a guess of ours.
    @discardableResult
    public func select(_ region: SelectionRegion?) -> Bool {
        guard let terminal else { return false }
        guard let region else { return install(selection: nil) }
        guard region.isNonNegative, let start = gridRef(col: region.from.col, row: region.from.row),
              let end = gridRef(col: region.to.col, row: region.to.row) else { return false }

        switch region.grain ?? .cell {
        case .cell:
            var selection = GhosttySelection()
            selection.size = MemoryLayout<GhosttySelection>.size
            selection.start = start
            selection.end = end
            selection.rectangle = region.rectangle
            return install(selection: selection)

        case .word:
            // `select_word_between` is the double-click-and-drag primitive the
            // header names: from the anchor toward the pointer, the first
            // selectable word. With both points equal it is the word under
            // the one point, which is the plain double-click.
            var options = GhosttyTerminalSelectWordBetweenOptions()
            options.size = MemoryLayout<GhosttyTerminalSelectWordBetweenOptions>.size
            options.start = start
            options.end = end
            var selection = GhosttySelection()
            selection.size = MemoryLayout<GhosttySelection>.size
            guard ghostty_terminal_select_word_between(terminal, &options, &selection) == GHOSTTY_SUCCESS else { return false }
            return install(selection: selection)

        case .line:
            // No `select_line_between` exists, so a multi-row line selection
            // is the union of the two ends' lines, taken in viewport order —
            // the same order the caller passed the rows in.
            guard let first = line(at: start), let last = line(at: end) else { return false }
            var selection = GhosttySelection()
            selection.size = MemoryLayout<GhosttySelection>.size
            let downward = region.from.row <= region.to.row
            selection.start = downward ? first.start : last.start
            selection.end = downward ? last.end : first.end
            selection.rectangle = false
            return install(selection: selection)
        }
    }

    /// One row's line selection, trimmed by the core's own whitespace rules.
    private func line(at ref: GhosttyGridRef) -> GhosttySelection? {
        guard let terminal else { return nil }
        var options = GhosttyTerminalSelectLineOptions()
        options.size = MemoryLayout<GhosttyTerminalSelectLineOptions>.size
        options.ref = ref
        var selection = GhosttySelection()
        selection.size = MemoryLayout<GhosttySelection>.size
        guard ghostty_terminal_select_line(terminal, &options, &selection) == GHOSTTY_SUCCESS else { return nil }
        return selection
    }

    /// A viewport cell as the grid reference every selection API takes. Nil
    /// when the cell is off the grid — which is how `select` refuses a point
    /// rather than clamping it to column 0.
    func gridRef(col: Int, row: Int) -> GhosttyGridRef? {
        guard let terminal, col >= 0, row >= 0 else { return nil }
        var point = GhosttyPoint()
        point.tag = GHOSTTY_POINT_TAG_VIEWPORT
        point.value.coordinate = GhosttyPointCoordinate(x: UInt16(clamping: col), y: UInt32(clamping: row))
        var out = GhosttyGridRef()
        out.size = MemoryLayout<GhosttyGridRef>.size   // sized struct, as everywhere in this API
        guard ghostty_terminal_grid_ref(terminal, point, &out) == GHOSTTY_SUCCESS else { return nil }
        return out
    }

    /// Install a selection the core built (a gesture's, a word's, a line's)
    /// or clear it with nil. The core copies it and converts it to tracked
    /// state, so the untracked grid refs inside do not outlive this call.
    ///
    /// Only a selection that took needs a frame; a refused one changed
    /// nothing on screen.
    @discardableResult
    func install(selection: GhosttySelection?) -> Bool {
        guard let terminal else { return false }
        var done = false
        if var selection {
            done = ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_SELECTION, &selection) == GHOSTTY_SUCCESS
        } else {
            done = ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_SELECTION, nil) == GHOSTTY_SUCCESS
        }
        needsFullRedraw = needsFullRedraw || done
        return done
    }

    /// DEC 1004 focus reporting: `CSI I` on focus in, `CSI O` on focus out,
    /// and **only when the child has turned the mode on**. The mode is read
    /// from the core rather than remembered here, so a child that enables
    /// or disables 1004 mid-session is answered correctly on the next
    /// change — the same discipline `paste` follows for 2004.
    ///
    /// The last state sent is held so a redundant report is not written.
    /// AppKit is generous with key-window notifications (a sheet, a menu, a
    /// space switch), the harness pulses presence *on* focus-gained, and a
    /// duplicated "focused" would be a duplicated pulse.
    ///
    /// These two sequences are hand-written, which CLAUDE.md forbids for
    /// keys — "keys are the core's job" — and the exemption is narrow and
    /// worth naming. Mode 1004 has no encoder in libghostty-vt at the
    /// pinned commit (`modes.h` defines `GHOSTTY_MODE_FOCUS_EVENT` and
    /// nothing writes it), and unlike a key these two sequences carry no
    /// state: no modifiers, no kitty variant, no application-cursor form.
    /// `CSI I` and `CSI O` are the whole protocol. If the core grows a
    /// focus writer on a later pin, this becomes a call to it.
    /// What the window says is remembered separately from what has been
    /// written, and the gap between them is the attach case. At the moment
    /// a pane mounts, the child has not started and 1004 is off, so the
    /// report cannot be sent — and that is exactly the case that matters,
    /// because a session attached while nobody is looking must be able to
    /// say so. The desire is therefore held and `flushFocus` retries it
    /// after every chunk the child writes, so it lands on the same read
    /// that negotiates the mode. No timer, and nothing for the owner to
    /// remember to call twice.
    @discardableResult
    public func setFocused(_ focused: Bool) -> Bool {
        desiredFocus = focused
        return flushFocus()
    }

    /// Write the pending focus report if there is one and the child is
    /// listening. Ordered cheapest-first: in the steady state this is one
    /// optional comparison and no call into the core.
    @discardableResult
    private func flushFocus() -> Bool {
        guard let desiredFocus, desiredFocus != lastFocusReported else { return false }
        guard terminal != nil, mode(1004) else { return false }
        lastFocusReported = desiredFocus
        onOutput?(Data(desiredFocus ? [0x1b, 0x5b, 0x49] : [0x1b, 0x5b, 0x4f]))
        return true
    }

    /// Read one DEC mode, the same in/out shape `GhosttyMouse.mode` uses —
    /// `GHOSTTY_MODE_*` are macros Swift cannot see, so the mode is built
    /// with `ghostty_mode_new`.
    func mode(_ number: UInt16, dec: Bool = true) -> Bool {
        guard let terminal else { return false }
        var config = GhosttyTerminalModeConfig(mode: ghostty_mode_new(number, !dec), value: false)
        guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_MODE, &config) == GHOSTTY_SUCCESS else { return false }
        return config.value
    }

    /// Whether anything is selected right now.
    public var hasSelection: Bool {
        guard let terminal else { return false }
        var selection = GhosttySelection()
        selection.size = MemoryLayout<GhosttySelection>.size
        return ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_SELECTION, &selection) == GHOSTTY_SUCCESS
    }

    /// The selected text, or nil when nothing is selected — what ⌘C copies
    /// and what `ccc copy` prints.
    ///
    /// Plain, unwrapped, trimmed, because `selection.h` says exactly that:
    /// "for copy/clipboard behavior matching Ghostty's
    /// `Screen.selectionString()`, use plain output with unwrap and trim both
    /// set to true". Unwrap is the one that matters — a soft-wrapped path
    /// copied with its wrap points in it is a path that will not paste.
    public func selectionText() -> String? {
        guard let terminal else { return nil }
        var options = GhosttyTerminalSelectionFormatOptions()
        options.size = MemoryLayout<GhosttyTerminalSelectionFormatOptions>.size
        options.emit = GHOSTTY_FORMATTER_FORMAT_PLAIN
        options.unwrap = true
        options.trim = true
        options.selection = nil   // the terminal's own active selection

        // Ask for the size first: a selection can be the whole scrollback,
        // so there is no stack buffer worth guessing at.
        var needed = 0
        let sized = ghostty_terminal_selection_format_buf(terminal, options, nil, 0, &needed)
        guard sized == GHOSTTY_OUT_OF_SPACE, needed > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: needed)
        var written = 0
        let result = buffer.withUnsafeMutableBufferPointer { buf in
            ghostty_terminal_selection_format_buf(terminal, options, buf.baseAddress, buf.count, &written)
        }
        guard result == GHOSTTY_SUCCESS, written > 0 else { return nil }
        return String(decoding: buffer.prefix(written), as: UTF8.self)
    }

    // MARK: frames (the renderer's input)

    private var frameReader: FrameReader?

    /// Set when something *we* changed has to reach the screen even though
    /// the terminal's own dirty tracking saw no writes: a selection. The
    /// render state's dirty level is recomputed from the terminal on every
    /// `update`, so it cannot be pre-set — the frame is marked instead, on
    /// the renderer's path only.
    private var needsFullRedraw = false

    /// The resolved viewport for the renderer, as a delta since the last
    /// call (see `FrameReader`). Separate from `snapshot()`, which is the
    /// text oracle and must not consume dirty state.
    public func frame() -> Frame? {
        guard let terminal else { return nil }
        if frameReader == nil { frameReader = FrameReader(terminal: terminal) }
        guard var frame = frameReader?.read() else { return nil }
        if needsFullRedraw {
            needsFullRedraw = false
            frame.dirty = .full
            for index in frame.rows.indices { frame.rows[index].dirty = true }
        }
        return frame
    }

    // MARK: snapshot

    /// The text oracle. Derived from the same `FrameReader` the renderer
    /// uses (one render state per terminal), without consuming dirty flags.
    public func snapshot(colors: Bool) -> Grid {
        guard let terminal else {
            return Grid(cols: 0, rows: 0, lines: [], cursor: .init(col: 0, row: 0, visible: false))
        }
        if frameReader == nil { frameReader = FrameReader(terminal: terminal) }
        guard let frame = frameReader?.read(consume: false) else {
            return Grid(cols: 0, rows: 0, lines: [], cursor: .init(col: 0, row: 0, visible: false))
        }
        let lines = frame.rows.map { row -> String in
            var line = ""
            line.reserveCapacity(frame.cols)
            for cell in row.cells {
                // One String element per column: a wide glyph followed by a
                // space for its spacer tail keeps text positions aligned with
                // the grid (and with the SwiftTerm goldens).
                line += cell.text.isEmpty ? " " : cell.text
            }
            return pad(line, to: frame.cols)
        }
        var scrollback: Int = 0
        _ = ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_SCROLLBACK_ROWS, &scrollback)
        var grid = Grid(
            cols: frame.cols, rows: frame.rows.count, lines: lines,
            cursor: .init(col: frame.cursor?.x ?? 0, row: frame.cursor?.y ?? 0, visible: frame.cursor?.visible ?? false),
            scrollbackRows: scrollback
        )
        // The colour was in hand the whole time — this same `frame` is what
        // the renderer paints from, and the text above is it with every
        // colour dropped. Item 12a is only ever this: stop dropping it when
        // asked (`ColorSpans`).
        if colors { grid.colors = ColorSpans.build(frame: frame, selection: theme.selection, bold: theme.bold) }
        return grid
    }

    private func pad(_ text: String, to cols: Int) -> String {
        let count = text.count
        if count == cols { return text }
        if count < cols { return text + String(repeating: " ", count: cols - count) }
        return String(text.prefix(cols))
    }
}
