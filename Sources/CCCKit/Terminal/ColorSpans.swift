import Foundation

/// Colour, in the shape a golden can assert (queue item 12a).
///
/// `Grid` was text alone, so the one oracle an agent can run with no screen
/// could not answer a colour question — `ccc capture` / `ccc pixel` can, but
/// they need a *window*, which a headless agent does not have. The RGB was
/// never far away: `GhosttyHost.snapshot()` already reads a colour-complete
/// `Frame` and was throwing every colour on the floor to keep `cell.text`.
///
/// **Resolution is shared with the renderer, the merge is not.** Both go
/// through `RunMerge.resolvedColors`, which applies `inverse` and the frame
/// defaults — so a span says the colour that is actually *painted*, and
/// `ccc pixel` reading that cell off a real screencapture must agree. The
/// merge deliberately differs: the renderer merges by full `RunStyle`
/// (fg + bold + italic + underline…) because that is what forces a new
/// shaping call, while a colour oracle merges by colour alone. Sharing the
/// merge would make one of the two wrong.
public enum ColorSpans {
    /// One row's cells as runs of equal resolved colour. A `bg` that
    /// resolves to nil — the renderer's "the clear colour already painted
    /// it" — is reported as the frame background, because the question a
    /// golden asks is what is on the screen, not which code path put it
    /// there.
    static func build(
        row: Frame.Row, background: Frame.RGB, foreground: Frame.RGB,
        selection: SelectionColors? = nil
    ) -> [Grid.ColorSpan] {
        var spans: [Grid.ColorSpan] = []
        var column = 0
        for cell in row.cells {
            // A wide glyph's spacer tail is not a cell of its own on screen;
            // it carries the head's colours and is merged into it by the
            // equality below. Counting it keeps `col` in step with the text
            // line, which pads a wide glyph with a following space.
            let resolved = RunMerge.resolvedColors(cell, frame: background, foreground: foreground,
                                                   selected: RunMerge.selected(column, in: row, selection))
            let fg = resolved.fg
            let bg = resolved.bg ?? background
            if var last = spans.last, last.fg == fg, last.bg == bg {
                last.len += 1
                spans[spans.count - 1] = last
            } else {
                spans.append(Grid.ColorSpan(col: column, len: 1, fg: fg, bg: bg))
            }
            column += 1
        }
        return spans
    }

    /// Every row of a frame. Nil rows are impossible here — a frame read
    /// without consuming dirty state carries the whole viewport.
    ///
    /// `selection` is the theme's pair, handed in by the host that owns the
    /// theme, so a selected cell reads the same here as it paints on screen
    /// (item 12b).
    static func build(frame: Frame, selection: SelectionColors? = nil) -> [[Grid.ColorSpan]] {
        frame.rows.map {
            build(row: $0, background: frame.background, foreground: frame.foreground, selection: selection)
        }
    }
}

extension Grid {
    /// The resolved colour at one cell, or nil when this grid carries no
    /// colour (`snapshot()` without `colors: true`, or a core that cannot
    /// answer). The twin of `ccc pixel --cell <col> <row>`, and the reason
    /// both spell a colour `#RRGGBB`.
    public func color(col: Int, row: Int) -> (fg: Frame.RGB, bg: Frame.RGB)? {
        guard let colors, row >= 0, row < colors.count else { return nil }
        for span in colors[row] where col >= span.col && col < span.col + span.len {
            return (span.fg, span.bg)
        }
        return nil
    }
}
