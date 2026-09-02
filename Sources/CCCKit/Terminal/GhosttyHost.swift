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
    private var renderState: GhosttyRenderState?
    private var rowIterator: GhosttyRenderStateRowIterator?
    private var rowCells: GhosttyRenderStateRowCells?
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

        var rs: GhosttyRenderState?
        if ghostty_render_state_new(nil, &rs) == GHOSTTY_SUCCESS { renderState = rs }
        var it: GhosttyRenderStateRowIterator?
        if ghostty_render_state_row_iterator_new(nil, &it) == GHOSTTY_SUCCESS { rowIterator = it }
        var cells: GhosttyRenderStateRowCells?
        if ghostty_render_state_row_cells_new(nil, &cells) == GHOSTTY_SUCCESS { rowCells = cells }
    }

    isolated deinit {
        if let rowCells { ghostty_render_state_row_cells_free(rowCells) }
        if let rowIterator { ghostty_render_state_row_iterator_free(rowIterator) }
        if let renderState { ghostty_render_state_free(renderState) }
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

    // MARK: snapshot

    public func snapshot() -> Grid {
        guard let terminal, let renderState, let rowIterator, let rowCells else {
            return Grid(cols: 0, rows: 0, lines: [], cursor: .init(col: 0, row: 0, visible: false))
        }
        _ = ghostty_render_state_update(renderState, terminal)

        var cols: UInt16 = 0, rows: UInt16 = 0
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_COLS, &cols)
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_ROWS, &rows)

        var lines: [String] = []
        lines.reserveCapacity(Int(rows))
        // ROW_ITERATOR / ROW_DATA_CELLS populate a PRE-ALLOCATED handle; the
        // getters follow the "out points at a value of the type" rule, so
        // the out pointer is the address of the handle variable.
        var iterator = rowIterator
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, &iterator)
        var utf8 = [UInt8](repeating: 0, count: 64)
        while ghostty_render_state_row_iterator_next(iterator) {
            var cells = rowCells
            _ = ghostty_render_state_row_get(iterator, GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, &cells)
            var line = ""
            line.reserveCapacity(Int(cols))
            var x = 0
            while ghostty_render_state_row_cells_next(cells), x < Int(cols) {
                var buffer = GhosttyBuffer()
                utf8.withUnsafeMutableBufferPointer { buf in
                    buffer.ptr = buf.baseAddress
                    buffer.cap = buf.count
                    buffer.len = 0
                    let result = ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_UTF8, &buffer)
                    if result == GHOSTTY_SUCCESS, buffer.len > 0 {
                        line += String(decoding: UnsafeRawBufferPointer(start: buf.baseAddress, count: Int(buffer.len)), as: UTF8.self)
                    } else if result != GHOSTTY_SUCCESS && buffer.len > 0 {
                        line += "?"   // grapheme longer than 64 bytes; grow later
                    } else {
                        line += " "
                    }
                }
                x += 1
            }
            lines.append(line)
        }
        while lines.count < Int(rows) { lines.append(String(repeating: " ", count: Int(cols))) }

        var hasCursor = false, visible = false
        var cx: UInt16 = 0, cy: UInt16 = 0
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_HAS_VALUE, &hasCursor)
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VISIBLE, &visible)
        if hasCursor {
            _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_X, &cx)
            _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_Y, &cy)
        }
        var scrollback: Int = 0
        _ = ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_SCROLLBACK_ROWS, &scrollback)

        return Grid(
            cols: Int(cols), rows: Int(rows),
            lines: lines.map { pad($0, to: Int(cols)) },
            cursor: .init(col: Int(cx), row: Int(cy), visible: visible && hasCursor),
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
