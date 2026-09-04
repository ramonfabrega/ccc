import Foundation
import Testing

@testable import CCCKit

/// Item 13: the hand. `SelectionTests` proves a selection *paints*; this
/// proves one can be *made* — press, drag, release, and the click sequence
/// that turns two clicks into a word and three into a line.
///
/// Everything here drives `GhosttySelectGesture` directly, which is exactly
/// what `PaneInputView.mouseDown` does with an `NSEvent` in its hand: same
/// cells, same times, same geometry. No window, no pointer, no AppKit — so
/// the drag is judged the way the colours were, by the text grid.
@Suite struct SelectionGestureTests {
    /// Cell metrics as a headless surface. The numbers only have to be
    /// consistent with the positions below, since what the core reads is the
    /// pointer *against* this geometry.
    static let cellWidth = 8
    static let cellHeight = 17

    /// Which half of a cell the pointer is in — and it matters, because a
    /// drag runs between the two nearest cell **boundaries**: the left half
    /// of a cell snaps to the boundary before it, the right half to the one
    /// after. That is what makes "drag past the middle of the character to
    /// take it" true here as in every other terminal. `theHalfCellRule`
    /// pins it; measured, not assumed.
    enum Half { case left, right }

    @MainActor private func host(_ bytes: String, cols: Int = 20, rows: Int = 3) -> GhosttyHost {
        let host = GhosttyHost(cols: cols, rows: rows)
        host.feed(Data(bytes.utf8))
        return host
    }

    @MainActor private func geometry(_ host: GhosttyHost) -> GhosttySelectGesture.Geometry {
        let grid = host.snapshot(colors: false)
        return .init(columns: grid.cols, cellWidth: Self.cellWidth,
                     screenHeight: Self.cellHeight * max(1, grid.rows))
    }

    private func position(col: Int, row: Int, _ half: Half = .left) -> CGPoint {
        CGPoint(x: CGFloat(col * Self.cellWidth + (half == .left ? 1 : Self.cellWidth - 1)),
                y: CGFloat(row * Self.cellHeight + Self.cellHeight / 2))
    }

    /// The selected columns of one row, read the way the renderer reads them.
    @MainActor private func selected(_ host: GhosttyHost, row: Int) -> Range<Int>? {
        host.frame()?.rows[row].selection
    }

    // MARK: the drag

    /// The whole gesture in one test: press on the "w", drag past the "d",
    /// release — and the five cells of "world" are selected, which is the
    /// same answer `ccc select 6 0 10 0` gives.
    @Test @MainActor func aPressAndDragSelectTheCellsBetween() {
        let host = self.host("hello world")
        let gesture = GhosttySelectGesture(host: host)

        // A press alone selects nothing: it puts the anchor down. That is
        // what makes a plain click a *clear* rather than a one-cell
        // selection — the pane clears first and the press installs nothing.
        #expect(!gesture.press(col: 6, row: 0, position: position(col: 6, row: 0), time: 1))
        #expect(!host.hasSelection)

        #expect(gesture.drag(col: 10, row: 0, position: position(col: 10, row: 0, .right), geometry: geometry(host)))
        #expect(selected(host, row: 0) == 6..<11)
        #expect(gesture.dragged)

        gesture.release(col: 10, row: 0)
        // The release ends the drag and leaves the selection standing.
        #expect(selected(host, row: 0) == 6..<11)
    }

    /// A drag that goes backwards selects the same cells: the rule is about
    /// boundaries, not about which end came first, so pressing past the "d"
    /// and dragging back to the "w" is the same five cells.
    @Test @MainActor func aBackwardsDragSelectsTheSameCells() {
        let host = self.host("hello world")
        let gesture = GhosttySelectGesture(host: host)
        gesture.press(col: 10, row: 0, position: position(col: 10, row: 0, .right), time: 1)
        #expect(gesture.drag(col: 6, row: 0, position: position(col: 6, row: 0), geometry: geometry(host)))
        #expect(selected(host, row: 0) == 6..<11)
    }

    /// The half-cell rule itself, in one place. Each pair is (where the
    /// pointer ended, which cells came with it) — and the boundary is sharp:
    /// the same cell, one pixel apart, is in or out.
    @Test @MainActor func theHalfCellRule() {
        for (half, expected) in [(Half.left, 6..<10), (Half.right, 6..<11)] {
            let host = self.host("hello world")
            let gesture = GhosttySelectGesture(host: host)
            gesture.press(col: 6, row: 0, position: position(col: 6, row: 0), time: 1)
            gesture.drag(col: 10, row: 0, position: position(col: 10, row: 0, half), geometry: geometry(host))
            #expect(selected(host, row: 0) == expected, "\(half)")
        }
        // And the anchor obeys it too: pressing in the right half of the "w"
        // starts the selection after it.
        let host = self.host("hello world")
        let gesture = GhosttySelectGesture(host: host)
        gesture.press(col: 6, row: 0, position: position(col: 6, row: 0, .right), time: 1)
        gesture.drag(col: 10, row: 0, position: position(col: 10, row: 0, .right), geometry: geometry(host))
        #expect(selected(host, row: 0) == 7..<11)
    }

    /// ⌥ is read per drag event, so the flag is what makes the box — and a
    /// rectangle keeps the *columns* on the middle row instead of taking the
    /// whole width, which is how the two shapes are told apart.
    @Test @MainActor func theRectangleFlagMakesABox() {
        let host = self.host("aaaaaaaaaa\r\nbbbbbbbbbb\r\ncccccccccc", cols: 10, rows: 3)
        let gesture = GhosttySelectGesture(host: host)
        gesture.press(col: 2, row: 0, position: position(col: 2, row: 0), time: 1)

        #expect(gesture.drag(col: 4, row: 2, position: position(col: 4, row: 2, .right),
                             geometry: geometry(host), rectangle: true))
        for row in 0..<3 { #expect(selected(host, row: row) == 2..<5, "row \(row)") }

        // The same drag without the flag is the linear selection, mid-drag:
        // the modifier can be let go of and the shape follows.
        #expect(gesture.drag(col: 4, row: 2, position: position(col: 4, row: 2, .right),
                             geometry: geometry(host), rectangle: false))
        #expect(selected(host, row: 1) == 0..<10)
    }

    // MARK: the click sequence

    /// Two presses inside the repeat interval are a double-click, and a
    /// double-click is a word. The core counts this from the times we hand
    /// it — an untimed press can only ever be a single click, which is the
    /// one detail that makes `time:` load-bearing rather than decorative.
    @Test @MainActor func aDoubleClickSelectsTheWord() {
        let host = self.host("hello world")
        let gesture = GhosttySelectGesture(host: host)

        gesture.press(col: 7, row: 0, position: position(col: 7, row: 0), time: 1)
        gesture.release(col: 7, row: 0)
        #expect(gesture.clickCount == 1)

        #expect(gesture.press(col: 7, row: 0, position: position(col: 7, row: 0), time: 1.1))
        #expect(gesture.clickCount == 2)
        #expect(selected(host, row: 0) == 6..<11)   // "world", not the cell
    }

    /// Three take the line — and the line is trimmed, so the 20-column
    /// grid's trailing blanks are not in it.
    @Test @MainActor func aTripleClickSelectsTheLine() {
        let host = self.host("hello world")
        let gesture = GhosttySelectGesture(host: host)
        for (index, time) in [1.0, 1.1, 1.2].enumerated() {
            gesture.press(col: 7, row: 0, position: position(col: 7, row: 0), time: time)
            if index < 2 { gesture.release(col: 7, row: 0) }
        }
        #expect(gesture.clickCount == 3)
        #expect(selected(host, row: 0) == 0..<11)
    }

    /// Two presses far apart in time are two single clicks, not a double —
    /// otherwise a click, a coffee, and a click would select a word.
    @Test @MainActor func aSlowSecondClickIsStillASingleClick() {
        let host = self.host("hello world")
        let gesture = GhosttySelectGesture(host: host)
        gesture.press(col: 7, row: 0, time: 1, repeatInterval: 0.5)
        gesture.release(col: 7, row: 0)
        #expect(!gesture.press(col: 7, row: 0, time: 9, repeatInterval: 0.5))
        #expect(gesture.clickCount == 1)
        #expect(!host.hasSelection)
    }

    // MARK: the twins

    /// `ccc select --word` is the double-click's twin and must answer the
    /// same cells the gesture does — the point of a twin is that the two
    /// roads end in one place.
    @Test @MainActor func theWordGrainMatchesADoubleClick() {
        let host = self.host("hello world")
        #expect(host.select(SelectionRegion(fromCol: 7, fromRow: 0, toCol: 7, toRow: 0, grain: .word)))
        let byCommand = selected(host, row: 0)

        host.select(nil)
        let gesture = GhosttySelectGesture(host: host)
        gesture.press(col: 7, row: 0, time: 1)
        gesture.release(col: 7, row: 0)
        gesture.press(col: 7, row: 0, time: 1.1)
        #expect(selected(host, row: 0) == byCommand)
        #expect(byCommand == 6..<11)
    }

    /// `ccc select --line` is the triple-click's twin: one point takes that
    /// row, trimmed. Two points take the rows between them the way a linear
    /// selection does — the first from its start to the margin, the last up
    /// to where its line ends.
    @Test @MainActor func theLineGrainTakesWholeLines() {
        let host = self.host("one\r\ntwo\r\nthree", cols: 20, rows: 3)
        #expect(host.select(SelectionRegion(fromCol: 1, fromRow: 1, toCol: 1, toRow: 1, grain: .line)))
        #expect(selected(host, row: 0) == nil)
        #expect(selected(host, row: 1) == 0..<3)
        #expect(selected(host, row: 2) == nil)

        #expect(host.select(SelectionRegion(fromCol: 2, fromRow: 0, toCol: 1, toRow: 2, grain: .line)))
        #expect(selected(host, row: 0) == 0..<20)
        #expect(selected(host, row: 2) == 0..<5)
    }

    /// A grain does not clamp: a point off the grid is refused, exactly as
    /// the cell grain refuses one.
    @Test @MainActor func aGrainOffTheGridIsRefused() {
        let host = self.host("hello", cols: 10, rows: 2)
        #expect(!host.select(SelectionRegion(fromCol: 0, fromRow: 9, toCol: 0, toRow: 9, grain: .word)))
        #expect(!host.select(SelectionRegion(fromCol: 0, fromRow: 9, toCol: 0, toRow: 9, grain: .line)))
        #expect(!host.hasSelection)
    }

    // MARK: copy

    /// What ⌘C puts on the pasteboard. Plain, and only the selected cells —
    /// the grid's trailing blanks are not text anyone asked for.
    @Test @MainActor func copyingAnswersTheSelectedText() {
        let host = self.host("hello world")
        #expect(host.selectionText() == nil)          // nothing selected, nothing to copy
        #expect(host.select(SelectionRegion(fromCol: 6, fromRow: 0, toCol: 10, toRow: 0)))
        #expect(host.selectionText() == "world")
    }

    /// The reason `unwrap` is set: a line the child soft-wrapped is one
    /// line, and copying it with the wrap in it would produce a path that
    /// does not paste. Ten columns, twelve characters, one selection.
    @Test @MainActor func copyingUndoesASoftWrap() {
        let host = self.host("abcdefghijkl", cols: 10, rows: 3)
        #expect(host.select(SelectionRegion(fromCol: 0, fromRow: 0, toCol: 1, toRow: 1)))
        #expect(host.selectionText() == "abcdefghijkl")
    }

    /// A multi-row selection keeps its newline: two lines copied are two
    /// lines pasted.
    @Test @MainActor func copyingKeepsTheLineBreaks() {
        let host = self.host("one\r\ntwo", cols: 10, rows: 3)
        #expect(host.select(SelectionRegion(fromCol: 0, fromRow: 0, toCol: 2, toRow: 1)))
        #expect(host.selectionText() == "one\ntwo")
    }

    // MARK: lifetimes

    /// The gesture holds tracked references inside the terminal and frees
    /// them against it. Building and dropping one around a live host must
    /// leave the host usable — the shape that would crash if the free ever
    /// went to the wrong terminal.
    @Test @MainActor func aGestureCanBeDroppedWhileTheHostLivesOn() {
        let host = self.host("hello world")
        do {
            let gesture = GhosttySelectGesture(host: host)
            gesture.press(col: 0, row: 0, time: 1)
            gesture.drag(col: 4, row: 0, geometry: geometry(host))
        }
        host.feed(Data("!".utf8))
        #expect(host.snapshot(colors: false).lines[0].hasPrefix("hello world!"))
        #expect(host.select(SelectionRegion(fromCol: 0, fromRow: 0, toCol: 2, toRow: 0)))
    }

    /// A selection outlives what the child prints next: the core converts it
    /// to tracked state on install, so output that scrolls under it moves it
    /// rather than invalidating it. Without that, every drag would be a race
    /// with the next frame.
    @Test @MainActor func aSelectionSurvivesTheChildPrinting() {
        let host = self.host("hello world")
        let gesture = GhosttySelectGesture(host: host)
        gesture.press(col: 6, row: 0, position: position(col: 6, row: 0), time: 1)
        gesture.drag(col: 10, row: 0, position: position(col: 10, row: 0, .right), geometry: geometry(host))
        gesture.release(col: 10, row: 0)

        host.feed(Data("\r\nmore output".utf8))
        #expect(selected(host, row: 0) == 6..<11)
        #expect(host.selectionText() == "world")
    }
}
