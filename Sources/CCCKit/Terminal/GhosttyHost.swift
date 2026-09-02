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
    public var view: NSView? { nil }
    public private(set) var lastError: String?

    /// Bumped on every `feed` so a renderer can skip frames when nothing
    /// arrived; the render state's own dirty tracking is the fine grain.
    public private(set) var generation: UInt64 = 0

    public init(cols: Int = 80, rows: Int = 24) {
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
    }

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
        let keys = self.keys ?? GhosttyKeys(terminal: terminal)
        self.keys = keys
        let bytes = keys.encode(key)
        guard !bytes.isEmpty else { return false }
        onOutput?(bytes)
        return true
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
