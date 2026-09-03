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

    // MARK: frames (the renderer's input)

    private var frameReader: FrameReader?

    /// The resolved viewport for the renderer, as a delta since the last
    /// call (see `FrameReader`). Separate from `snapshot()`, which is the
    /// text oracle and must not consume dirty state.
    public func frame() -> Frame? {
        guard let terminal else { return nil }
        if frameReader == nil { frameReader = FrameReader(terminal: terminal) }
        return frameReader?.read()
    }

    // MARK: snapshot

    /// The text oracle. Derived from the same `FrameReader` the renderer
    /// uses (one render state per terminal), without consuming dirty flags.
    public func snapshot() -> Grid {
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
        return Grid(
            cols: frame.cols, rows: frame.rows.count, lines: lines,
            cursor: .init(col: frame.cursor?.x ?? 0, row: frame.cursor?.y ?? 0, visible: frame.cursor?.visible ?? false),
            scrollbackRows: scrollback
        )
    }

    private func pad(_ text: String, to cols: Int) -> String {
        let count = text.count
        if count == cols { return text }
        if count < cols { return text + String(repeating: " ", count: cols - count) }
        return String(text.prefix(cols))
    }
}
