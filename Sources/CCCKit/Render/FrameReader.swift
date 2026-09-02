import Foundation
import GhosttyVt

/// Reads libghostty-vt's render state into a `Frame`. This is the only
/// place that knows the C API's row/cell iterators; the renderer never
/// touches the core. Owned by `GhosttyHost`, called once per drawn frame.
///
/// Dirty tracking: `read()` calls `ghostty_render_state_update` (consuming
/// the terminal's dirty state), reports the render state's dirty level, and
/// then marks it clean — so the frame it returns is the delta since the
/// previous `read()`, and a renderer that draws every frame it is handed
/// stays consistent. Rows are always fully populated; `dirty` says which
/// ones changed.
@MainActor
final class FrameReader {
    private let terminal: GhosttyTerminal
    private let renderState: GhosttyRenderState
    private let rowIterator: GhosttyRenderStateRowIterator
    private let rowCells: GhosttyRenderStateRowCells
    private var utf8 = [UInt8](repeating: 0, count: 64)

    init?(terminal: GhosttyTerminal) {
        self.terminal = terminal
        var rs: GhosttyRenderState?
        var it: GhosttyRenderStateRowIterator?
        var cells: GhosttyRenderStateRowCells?
        guard ghostty_render_state_new(nil, &rs) == GHOSTTY_SUCCESS, let rs,
              ghostty_render_state_row_iterator_new(nil, &it) == GHOSTTY_SUCCESS, let it,
              ghostty_render_state_row_cells_new(nil, &cells) == GHOSTTY_SUCCESS, let cells else { return nil }
        renderState = rs
        rowIterator = it
        rowCells = cells
    }

    isolated deinit {
        ghostty_render_state_row_cells_free(rowCells)
        ghostty_render_state_row_iterator_free(rowIterator)
        ghostty_render_state_free(renderState)
    }

    /// `consume: false` (the text snapshot) leaves the render state's dirty
    /// flags in place so the next consuming read still sees every change:
    /// the terminal's own dirty state is taken by `update` either way, so
    /// there must be exactly one render state per terminal, this one.
    func read(consume: Bool = true) -> Frame {
        _ = ghostty_render_state_update(renderState, terminal)

        var cols: UInt16 = 0, rows: UInt16 = 0
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_COLS, &cols)
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_ROWS, &rows)

        var dirtyRaw = GHOSTTY_RENDER_STATE_DIRTY_FALSE
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_DIRTY, &dirtyRaw)
        let dirty: Frame.Dirty = switch dirtyRaw {
        case GHOSTTY_RENDER_STATE_DIRTY_FULL: .full
        case GHOSTTY_RENDER_STATE_DIRTY_PARTIAL: .partial
        default: .none
        }

        var colors = GhosttyRenderStateColors()
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_COLORS, &colors)

        var frameRows: [Frame.Row] = []
        frameRows.reserveCapacity(Int(rows))
        var iterator: GhosttyRenderStateRowIterator? = rowIterator
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, &iterator)
        var y = 0
        while ghostty_render_state_row_iterator_next(iterator) {
            var rowDirty = false
            _ = ghostty_render_state_row_get(iterator, GHOSTTY_RENDER_STATE_ROW_DATA_DIRTY, &rowDirty)
            var cells: GhosttyRenderStateRowCells? = rowCells
            _ = ghostty_render_state_row_get(iterator, GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, &cells)
            var rowCellsOut: [Frame.Cell] = []
            rowCellsOut.reserveCapacity(Int(cols))
            var x = 0
            while ghostty_render_state_row_cells_next(cells), x < Int(cols) {
                rowCellsOut.append(readCell(cells))
                x += 1
            }
            while rowCellsOut.count < Int(cols) { rowCellsOut.append(.blank) }
            frameRows.append(Frame.Row(y: y, dirty: dirty == .full || rowDirty, cells: rowCellsOut, selection: nil))
            y += 1
        }

        var cursor: Frame.Cursor?
        var hasCursor = false, visible = false, blinking = false, wideTail = false
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_HAS_VALUE, &hasCursor)
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VISIBLE, &visible)
        if hasCursor {
            var cx: UInt16 = 0, cy: UInt16 = 0
            var styleRaw = GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK
            _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_X, &cx)
            _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_Y, &cy)
            _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VISUAL_STYLE, &styleRaw)
            _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_BLINKING, &blinking)
            _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_WIDE_TAIL, &wideTail)
            let style: Frame.Cursor.Style = switch styleRaw {
            case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BAR: .bar
            case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_UNDERLINE: .underline
            case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK_HOLLOW: .blockHollow
            default: .block
            }
            var hasCursorColor = false
            var cursorColor = GhosttyColorRgb()
            _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_COLOR_CURSOR_HAS_VALUE, &hasCursorColor)
            if hasCursorColor { _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_COLOR_CURSOR, &cursorColor) }
            cursor = Frame.Cursor(x: Int(cx), y: Int(cy), style: style, visible: visible, blinking: blinking,
                                  wideTail: wideTail, color: hasCursorColor ? rgb(cursorColor) : nil)
        }

        if consume { _ = ghostty_render_state_clean(renderState) }

        return Frame(cols: Int(cols), rows: frameRows, cursor: cursor,
                     background: rgb(colors.background), foreground: rgb(colors.foreground), dirty: dirty)
    }

    private func readCell(_ cells: GhosttyRenderStateRowCells?) -> Frame.Cell {
        var cell = Frame.Cell.blank

        var raw: GhosttyCell = 0   // packed uint64, passed by value to ghostty_cell_get
        if ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW, &raw) == GHOSTTY_SUCCESS {
            var wide = GHOSTTY_CELL_WIDE_NARROW
            _ = ghostty_cell_get(raw, GHOSTTY_CELL_DATA_WIDE, &wide)
            cell.wide = switch wide {
            case GHOSTTY_CELL_WIDE_WIDE: .wide
            case GHOSTTY_CELL_WIDE_SPACER_TAIL: .spacerTail
            case GHOSTTY_CELL_WIDE_SPACER_HEAD: .spacerHead
            default: .narrow
            }
        }

        if cell.wide != .spacerTail {
            var buffer = GhosttyBuffer()
            utf8.withUnsafeMutableBufferPointer { buf in
                buffer.ptr = buf.baseAddress
                buffer.cap = buf.count
                let result = ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_UTF8, &buffer)
                if result == GHOSTTY_SUCCESS, buffer.len > 0 {
                    cell.text = String(decoding: UnsafeRawBufferPointer(start: buf.baseAddress, count: Int(buffer.len)), as: UTF8.self)
                }
            }
        }

        var color = GhosttyColorRgb()
        if ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_FG_COLOR, &color) == GHOSTTY_SUCCESS {
            cell.fg = rgb(color)
        }
        if ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_BG_COLOR, &color) == GHOSTTY_SUCCESS {
            cell.bg = rgb(color)
        }

        var hasStyling = false
        _ = ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_HAS_STYLING, &hasStyling)
        if hasStyling {
            var style = GhosttyStyle()
            if ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE, &style) == GHOSTTY_SUCCESS {
                var flags: Frame.Cell.Flags = []
                if style.bold { flags.insert(.bold) }
                if style.italic { flags.insert(.italic) }
                if style.faint { flags.insert(.faint) }
                if style.blink { flags.insert(.blink) }
                if style.inverse { flags.insert(.inverse) }
                if style.invisible { flags.insert(.invisible) }
                if style.strikethrough { flags.insert(.strikethrough) }
                if style.overline { flags.insert(.overline) }
                cell.flags = flags
                cell.underline = switch style.underline {
                case 1: .single
                case 2: .double
                case 3: .curly
                case 4: .dotted
                case 5: .dashed
                default: .none
                }
            }
        }

        var selected = false
        _ = ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_SELECTED, &selected)
        if selected { cell.flags.insert(.inverse) }   // v1 selection policy: invert; refine with a selection color later

        return cell
    }

    private func rgb(_ c: GhosttyColorRgb) -> Frame.RGB { Frame.RGB(c.r, c.g, c.b) }
}
