import Foundation
import Metal
import Testing

@testable import CCCKit

/// Evaluated once, off the main actor, so it can gate `@Test(.enabled(if:))`.
private let hasMetalDevice = MTLCreateSystemDefaultDevice() != nil

/// Item 12b: a selected cell paints the theme's two colours.
///
/// The oracle item 12a promised, cashed: these drive the real core, make a
/// real selection through the real `GHOSTTY_TERMINAL_OPT_SELECTION`, and read
/// the colours back through `snapshot(colors:)` — no window, no screen, no
/// `screencapture`. The strings below are the same `#RRGGBB` spelling
/// `ccc pixel --expect` takes, so the day someone points a camera at a real
/// selection the two oracles are comparable by string equality.
@Suite struct SelectionTests {
    static let selectionBackground = "#B3D7FF"
    static let selectionForeground = "#000000"
    static let defaultBackground = "#15191F"
    static let defaultForeground = "#DCDCDC"

    @MainActor private func host(_ bytes: String, cols: Int = 40, rows: Int = 3) -> GhosttyHost {
        let host = GhosttyHost(cols: cols, rows: rows)
        host.feed(Data(bytes.utf8))
        return host
    }

    /// The whole item in one assertion: select three columns of plain text
    /// and exactly those three cells change colour, to the theme's pair.
    @Test @MainActor func aSelectedRunPaintsTheThemesTwoColours() throws {
        let host = self.host("hello world")
        #expect(host.select(SelectionRegion(fromCol: 6, fromRow: 0, toCol: 10, toRow: 0)))

        let grid = host.snapshot(colors: true)
        for column in 0..<grid.cols {
            let colour = try #require(grid.color(col: column, row: 0), "column \(column)")
            let selected = (6...10).contains(column)
            #expect(colour.bg.hex == (selected ? Self.selectionBackground : Self.defaultBackground),
                    "column \(column) background")
            #expect(colour.fg.hex == (selected ? Self.selectionForeground : Self.defaultForeground),
                    "column \(column) foreground")
        }
        // "world" is five cells, and both ends of the range are selected —
        // the off-by-one a half-open range would have introduced.
        let runs = try #require(grid.colors?[0]).map { "\($0.col)+\($0.len) \($0.fg.hex) on \($0.bg.hex)" }
        #expect(runs == [
            "0+6 \(Self.defaultForeground) on \(Self.defaultBackground)",
            "6+5 \(Self.selectionForeground) on \(Self.selectionBackground)",
            "11+29 \(Self.defaultForeground) on \(Self.defaultBackground)",
        ])
    }

    /// Selection wins over whatever the child painted — an SGR background,
    /// and `inverse`, which is what v1 used to *implement* selection with.
    /// That is the rule: a selected cell is the theme's pair, full stop.
    @Test @MainActor func selectionBeatsInverseAndSGRColour() throws {
        // "blue inv": 0–3 on an SGR blue ground, 4 a space, 5–7 inverse.
        // The selection covers the blue run and the first inverse cell.
        let host = self.host("\u{1B}[44mblue\u{1B}[0m \u{1B}[7minv\u{1B}[0m")
        #expect(host.select(SelectionRegion(fromCol: 0, fromRow: 0, toCol: 5, toRow: 0)))

        let grid = host.snapshot(colors: true)
        for column in 0...5 {
            let colour = try #require(grid.color(col: column, row: 0))
            #expect(colour.bg.hex == Self.selectionBackground, "column \(column)")
            #expect(colour.fg.hex == Self.selectionForeground, "column \(column)")
        }
        // Past the selection the SGR is untouched: the rest of the inverse
        // run still wears its swapped pair, which is how we know selection
        // replaced the colours rather than the cells.
        #expect(grid.color(col: 6, row: 0)?.fg.hex == Self.defaultBackground)
        #expect(grid.color(col: 6, row: 0)?.bg.hex == Self.defaultForeground)
    }

    /// A linear selection over three rows is what a drag does: from the
    /// anchor to the right margin, whole rows in the middle, up to the
    /// pointer on the last. The core computes those row-local ranges; the
    /// reader carries them; this pins that they arrive as they should.
    @Test @MainActor func aMultiRowSelectionCarriesOneRangePerRow() throws {
        let host = self.host("aaaaaaaaaa\r\nbbbbbbbbbb\r\ncccccccccc", cols: 10, rows: 3)
        #expect(host.select(SelectionRegion(fromCol: 4, fromRow: 0, toCol: 2, toRow: 2)))

        let frame = try #require(host.frame())
        #expect(frame.rows[0].selection == 4..<10)
        #expect(frame.rows[1].selection == 0..<10)
        #expect(frame.rows[2].selection == 0..<3)

        let grid = host.snapshot(colors: true)
        #expect(grid.color(col: 3, row: 0)?.bg.hex == Self.defaultBackground)
        #expect(grid.color(col: 4, row: 0)?.bg.hex == Self.selectionBackground)
        #expect(grid.color(col: 2, row: 2)?.bg.hex == Self.selectionBackground)
        #expect(grid.color(col: 3, row: 2)?.bg.hex == Self.defaultBackground)
    }

    /// A rectangle takes the same two corners and reads them as a box: the
    /// middle row keeps the *columns*, not the whole width.
    @Test @MainActor func aRectangleSelectsTheSameColumnsOnEveryRow() throws {
        let host = self.host("aaaaaaaaaa\r\nbbbbbbbbbb\r\ncccccccccc", cols: 10, rows: 3)
        #expect(host.select(SelectionRegion(fromCol: 2, fromRow: 0, toCol: 4, toRow: 2, rectangle: true)))

        let frame = try #require(host.frame())
        for row in 0..<3 { #expect(frame.rows[row].selection == 2..<5, "row \(row)") }
    }

    /// Rows the selection misses answer nil rather than an empty range, and
    /// a cleared selection leaves the grid exactly as it was.
    @Test @MainActor func clearingTakesEveryColourBack() throws {
        let host = self.host("hello")
        #expect(host.select(SelectionRegion(fromCol: 0, fromRow: 0, toCol: 4, toRow: 0)))
        #expect(try #require(host.frame()).rows[1].selection == nil)
        let selected = host.snapshot(colors: true)

        #expect(host.select(nil))
        let cleared = host.snapshot(colors: true)
        #expect(try #require(host.frame()).rows[0].selection == nil)
        #expect(cleared.colors != selected.colors)
        #expect(cleared.colors?[0].count == 1)
        #expect(cleared.colors?[0].first?.bg.hex == Self.defaultBackground)
    }

    /// Off the grid is refused, not clamped: a selection that silently began
    /// at column 0 would be a wrong answer wearing a success.
    @Test @MainActor func aPointOffTheGridIsRefused() {
        let host = self.host("hello", cols: 10, rows: 3)
        #expect(!host.select(SelectionRegion(fromCol: 0, fromRow: 0, toCol: 0, toRow: 99)))
        #expect(!host.select(SelectionRegion(fromCol: -1, fromRow: 0, toCol: 2, toRow: 0)))
        #expect(host.frame()?.rows[0].selection == nil)
    }

    /// The selection has to *reach the screen*. Nothing was written to the
    /// terminal, so the core's own dirty tracking says "clean" and the
    /// renderer's `shouldDraw` would skip the frame — the pane would keep
    /// showing an unselected grid until the child next printed something.
    /// `GhosttyHost` marks the frame instead (`needsFullRedraw`).
    @Test @MainActor func selectingForcesTheNextFrameToRedraw() throws {
        let host = self.host("hello")
        _ = host.frame()                                   // drain the dirty state
        #expect(host.frame()?.dirty == Frame.Dirty.none)   // …and it stays drained

        #expect(host.select(SelectionRegion(fromCol: 0, fromRow: 0, toCol: 4, toRow: 0)))
        let frame = try #require(host.frame())
        #expect(frame.dirty == .full)
        #expect(frame.rows.allSatisfy { $0.dirty })
        // One frame, not forever.
        #expect(host.frame()?.dirty == Frame.Dirty.none)
    }

    /// The anti-drift check, in the shape `ColorSpansTests` established: the
    /// renderer and the oracle resolve a selected cell through the same
    /// `RunMerge.resolvedColors`, so what a background quad is filled with
    /// and what `ccc snapshot --color` reports cannot come apart.
    @Test @MainActor func theRendererFillsWhatTheOracleReports() throws {
        let host = self.host("hello world")
        #expect(host.select(SelectionRegion(fromCol: 6, fromRow: 0, toCol: 10, toRow: 0)))
        let frame = try #require(host.frame())
        let grid = host.snapshot(colors: true)

        let spans = RunMerge.backgroundSpans(
            frame.rows[0], background: frame.background, foreground: frame.foreground,
            selection: Theme.iterm.selection)
        let selection = try #require(spans.first { $0.color.hex == Self.selectionBackground })
        #expect(selection.x == 6)
        #expect(selection.length == 5)
        #expect(spans.count == 1)   // nothing else on the row is painted

        for column in 6...10 {
            #expect(grid.color(col: column, row: 0)?.bg == selection.color, "column \(column)")
        }
        // And the text runs carry the selection foreground, so the glyphs
        // are legible on it rather than drawn in the old colour.
        let runs = RunMerge.textRuns(
            frame.rows[0], background: frame.background, foreground: frame.foreground,
            selection: Theme.iterm.selection)
        let word = try #require(runs.first { $0.text == "world" })
        #expect(word.style.fg.hex == Self.selectionForeground)
    }

    /// The last link in the chain: **pixels**. Everything above reads spans;
    /// this renders the same selected frame through the real Metal renderer
    /// into an offscreen texture and reads the colour back out of the image,
    /// which is as close to `ccc capture` as a machine with no screen gets.
    /// A cell is sampled at its centre, exactly as `WindowGeometry.pixel`
    /// aims `ccc pixel --cell`, and spelled `#RRGGBB` so the two answers are
    /// comparable by string equality.
    @Test(.enabled(if: hasMetalDevice)) @MainActor func aSelectedCellIsBlueInTheRenderedPixels() throws {
        let host = self.host("hello world", cols: 12, rows: 2)
        // From the space to the "d", so the run holds both a blank cell —
        // pure selection ground, nothing drawn over it — and five glyphs.
        #expect(host.select(SelectionRegion(fromCol: 5, fromRow: 0, toCol: 10, toRow: 0)))
        let frame = try #require(host.frame())

        let renderer = try #require(MetalRenderer())
        let metrics = CellMetrics(scale: 2)
        let cellWidth = Int(metrics.widthPixels), cellHeight = Int(metrics.heightPixels)
        let width = cellWidth * frame.cols, height = cellHeight * frame.rows.count
        let texture = try #require(renderer.makeOffscreenTexture(width: width, height: height))
        renderer.render(frame: frame, to: texture, metrics: metrics)
        let bytes = renderer.readPixels(from: texture)

        func colour(_ x: Int, _ y: Int) -> String {
            let index = (y * width + x) * 4   // BGRA8
            return PixelReader.hex(Frame.RGB(bytes[index + 2], bytes[index + 1], bytes[index]))
        }
        /// A cell's centre, exactly as `WindowGeometry.pixel` aims
        /// `ccc pixel --cell`: a corner sits on the boundary between two
        /// cells and on the edge of a glyph's antialiasing, where the answer
        /// is legitimately ambiguous.
        func centre(col: Int, row: Int) -> String {
            colour(col * cellWidth + cellWidth / 2, row * cellHeight + cellHeight / 2)
        }
        #expect(centre(col: 5, row: 0) == Self.selectionBackground)   // selected blank
        // A blank cell outside the selection, on the row below — column 11
        // of row 0 is where the cursor block is, and that is white.
        #expect(centre(col: 11, row: 1) == Self.defaultBackground)

        // The whole of a selected *glyph* cell stands on the selection
        // ground — no pixel of it is the default background — and some of it
        // is neither ground nor default, which is the glyph drawn on top.
        var ink = 0
        for y in 0..<cellHeight {
            for x in (6 * cellWidth)..<(7 * cellWidth) {
                let value = colour(x, y)
                #expect(value != Self.defaultBackground, "the \"w\" cell shows the unselected ground at \(x),\(y)")
                if value != Self.selectionBackground { ink += 1 }
            }
        }
        #expect(ink > 0, "the glyph for \"w\" was not drawn over the selection")
    }

    /// The theme is one file away (`CCC_THEME`), and the selection colours
    /// come from it like everything else — no constant in the renderer.
    @Test @MainActor func theColoursComeFromTheThemeNotFromTheRenderer() throws {
        var theme = Theme.iterm
        theme.selectionBackground = Frame.RGB(0x10, 0x20, 0x30)
        theme.selectionForeground = Frame.RGB(0xFF, 0xEE, 0xDD)
        let host = GhosttyHost(cols: 10, rows: 2, theme: theme)
        host.feed(Data("hello".utf8))
        #expect(host.select(SelectionRegion(fromCol: 0, fromRow: 0, toCol: 4, toRow: 0)))

        let colour = try #require(host.snapshot(colors: true).color(col: 2, row: 0))
        #expect(colour.bg.hex == "#102030")
        #expect(colour.fg.hex == "#FFEEDD")
    }
}
