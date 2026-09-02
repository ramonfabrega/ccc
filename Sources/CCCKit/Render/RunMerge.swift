import CoreGraphics
import Foundation

/// Turning a `Frame` row of resolved cells into the two things a GPU wants:
/// a handful of background rectangles and a handful of shaped text runs.
///
/// This is the technique docs/TERMINAL.md credits to Zed: greedily merge
/// adjacent cells that share a style into one run, shape that run once, and
/// merge adjacent equal backgrounds into spans drawn as quads. A row of 120
/// cells of ordinary prose becomes one or two runs and zero or one spans
/// instead of 120 of each, which is the difference between a shaping call per
/// cell per frame and a shaping call per style change.
///
/// Kept free of Metal and CoreText so it can be tested as pure data.
enum RunMerge {
    /// Everything about a cell that forces a new text run when it changes.
    /// Colours are already resolved (inverse applied) by the time we get here.
    struct RunStyle: Hashable {
        var fg: Frame.RGB
        var bold: Bool
        var italic: Bool
        var faint: Bool
        var underline: Frame.Cell.Underline
        var underlineColor: Frame.RGB?
        var strikethrough: Bool
        var overline: Bool
    }

    /// A background rectangle: `length` cells starting at column `x`.
    struct BackgroundSpan: Equatable {
        var x: Int
        var length: Int
        var color: Frame.RGB
    }

    struct TextRun {
        /// First column of the run.
        var x: Int
        /// How many cells the run covers, wide cells counting 2.
        var cellCount: Int
        /// The run's text, concatenated from its cells.
        var text: String
        /// For every UTF-16 offset in `text`, the column offset from `x` of the
        /// cell that contributed it. This is what lets the renderer place a
        /// shaped glyph on the *grid* instead of at the position the font's
        /// advances imply — the accumulated rounding error of 120 columns of
        /// "advance ≈ cell width" is exactly the drift that makes a cell grid
        /// look wrong.
        var columnForUTF16: [Int]
        var style: RunStyle
    }

    /// Colours after `inverse` is applied. `bg == nil` means "the frame default",
    /// which the renderer skips because the clear colour already painted it.
    static func resolvedColors(
        _ cell: Frame.Cell, frame background: Frame.RGB, foreground: Frame.RGB
    ) -> (fg: Frame.RGB, bg: Frame.RGB?) {
        if cell.flags.contains(.inverse) {
            return (cell.bg ?? background, cell.fg ?? foreground)
        }
        return (cell.fg ?? foreground, cell.bg)
    }

    static func style(
        of cell: Frame.Cell, frame background: Frame.RGB, foreground: Frame.RGB
    ) -> RunStyle {
        RunStyle(
            fg: resolvedColors(cell, frame: background, foreground: foreground).fg,
            bold: cell.flags.contains(.bold),
            italic: cell.flags.contains(.italic),
            faint: cell.flags.contains(.faint),
            underline: cell.underline,
            underlineColor: cell.underlineColor,
            strikethrough: cell.flags.contains(.strikethrough),
            overline: cell.flags.contains(.overline)
        )
    }

    /// Adjacent cells with the same resolved background become one span. Cells
    /// whose background resolves to nil, or to the frame default, produce no
    /// span at all: the clear already drew them.
    static func backgroundSpans(
        _ row: Frame.Row, background: Frame.RGB, foreground: Frame.RGB
    ) -> [BackgroundSpan] {
        var spans: [BackgroundSpan] = []
        var current: BackgroundSpan?
        for (x, cell) in row.cells.enumerated() {
            let bg = resolvedColors(cell, frame: background, foreground: foreground).bg
            let painted: Frame.RGB? = (bg == nil || bg == background) ? nil : bg
            if let painted, var open = current, open.color == painted, open.x + open.length == x {
                open.length += 1
                current = open
            } else {
                if let open = current { spans.append(open) }
                current = painted.map { BackgroundSpan(x: x, length: 1, color: $0) }
            }
        }
        if let open = current { spans.append(open) }
        return spans
    }

    /// A line under, through or over a stretch of cells. Merged independently
    /// of text runs because a run of underlined *spaces* has no glyphs at all
    /// and would otherwise lose its line.
    struct DecorationSpan: Equatable {
        var x: Int
        var length: Int
        var underline: Frame.Cell.Underline
        var strikethrough: Bool
        var overline: Bool
        /// Colour of the line: the underline colour when set, else the text fg.
        var color: Frame.RGB
        var underlineColor: Frame.RGB?
    }

    static func decorationSpans(
        _ row: Frame.Row, background: Frame.RGB, foreground: Frame.RGB
    ) -> [DecorationSpan] {
        var spans: [DecorationSpan] = []
        var current: DecorationSpan?
        for (x, cell) in row.cells.enumerated() {
            let hasLine = cell.underline != .none
                || cell.flags.contains(.strikethrough)
                || cell.flags.contains(.overline)
            guard hasLine else {
                if let open = current { spans.append(open) }
                current = nil
                continue
            }
            let fg = resolvedColors(cell, frame: background, foreground: foreground).fg
            let span = DecorationSpan(
                x: x, length: 1,
                underline: cell.underline,
                strikethrough: cell.flags.contains(.strikethrough),
                overline: cell.flags.contains(.overline),
                color: cell.underlineColor ?? fg,
                underlineColor: cell.underlineColor
            )
            if var open = current,
               open.x + open.length == x,
               open.underline == span.underline,
               open.strikethrough == span.strikethrough,
               open.overline == span.overline,
               open.color == span.color {
                open.length += 1
                current = open
            } else {
                if let open = current { spans.append(open) }
                current = span
            }
        }
        if let open = current { spans.append(open) }
        return spans
    }

    /// Adjacent cells with the same style become one run. A wide cell and its
    /// spacer tail always stay in the same run — the tail contributes no text
    /// but two cells of width, which is how the run's `cellCount` ends up
    /// matching what the grid actually occupies.
    ///
    /// Invisible cells and blank cells end the current run rather than joining
    /// it: there is no glyph to shape, and keeping a run of spaces alive only
    /// makes the shaped text longer for nothing.
    static func textRuns(
        _ row: Frame.Row, background: Frame.RGB, foreground: Frame.RGB
    ) -> [TextRun] {
        var runs: [TextRun] = []
        var current: TextRun?

        func close() {
            if let run = current, !run.text.isEmpty { runs.append(run) }
            current = nil
        }

        var x = 0
        while x < row.cells.count {
            let cell = row.cells[x]

            if cell.wide == .spacerTail {
                // Width belonging to the wide cell to our left; never its own run.
                if let open = current, open.x + open.cellCount == x { current?.cellCount += 1 }
                x += 1
                continue
            }

            let drawable = !cell.text.isEmpty
                && cell.text != " "
                && !cell.flags.contains(.invisible)
            guard drawable else {
                close()
                x += 1
                continue
            }

            let style = style(of: cell, frame: background, foreground: foreground)
            // A wide cell normally owns one cell here and one more when its
            // spacer tail arrives next iteration. Frames that omit the tail
            // still get the two cells they occupy.
            let tailFollows = x + 1 < row.cells.count && row.cells[x + 1].wide == .spacerTail
            let span = (cell.wide == .wide && !tailFollows) ? 2 : 1

            if var open = current, open.style == style, open.x + open.cellCount == x {
                let column = x - open.x
                open.text += cell.text
                open.columnForUTF16.append(contentsOf: repeatElement(column, count: cell.text.utf16.count))
                open.cellCount += span
                current = open
            } else {
                close()
                current = TextRun(
                    x: x,
                    cellCount: span,
                    text: cell.text,
                    columnForUTF16: Array(repeating: 0, count: cell.text.utf16.count),
                    style: style
                )
            }
            x += 1
        }
        close()
        return runs
    }
}
