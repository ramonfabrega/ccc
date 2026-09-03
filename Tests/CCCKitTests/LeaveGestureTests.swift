import Foundation
import Testing

@testable import CCCKit

/// The harness's ← gesture, read off the grid (v7 slice 1). Pure over a
/// `Grid`, so these build one by hand.
@Suite struct LeaveGestureTests {
    private func grid(_ lines: [String], cursor: (col: Int, row: Int), visible: Bool = true) -> Grid {
        let cols = 40
        let padded = lines.map { $0.padding(toLength: cols, withPad: " ", startingAt: 0) }
        return Grid(cols: cols, rows: padded.count, lines: padded,
                    cursor: .init(col: cursor.col, row: cursor.row, visible: visible))
    }

    private let left = NamedKey("left")!

    @Test func emptyPromptIsTheGesture() {
        // What 2.1.259 actually draws: the glyph, then U+00A0.
        let g = grid(["──────── polish ─", "❯\u{00A0}", "────────"], cursor: (2, 1))
        #expect(LeaveGesture.matches(left, in: g))
        let plain = grid(["❯ "], cursor: (2, 0))
        #expect(LeaveGesture.matches(left, in: plain))
    }

    @Test func everyPromptGlyphCounts() {
        for glyph in ["❯", ">", "!", "#"] {
            let g = grid(["\(glyph) "], cursor: (2, 0))
            #expect(LeaveGesture.matches(left, in: g), "\(glyph)")
        }
    }

    @Test func startOfADraftIsOursToo() {
        // The harness would refuse with "unsent text" and move nothing; a
        // placeholder after the cursor looks the same on the grid.
        let g = grid(["❯ hello"], cursor: (2, 0))
        #expect(LeaveGesture.matches(left, in: g))
    }

    @Test func insideADraftIsSent() {
        let g = grid(["❯ hello"], cursor: (5, 0))
        #expect(!LeaveGesture.matches(left, in: g))
    }

    @Test func continuationRowIsSent() {
        let g = grid(["❯ first line", "  second"], cursor: (2, 1))
        #expect(!LeaveGesture.matches(left, in: g))
    }

    @Test func dialogRowWithHiddenCursorIsSent() {
        let g = grid([" ❯ No, exit", "   Yes, I trust this folder"], cursor: (2, 0), visible: false)
        #expect(!LeaveGesture.matches(left, in: g))
    }

    @Test func shellPromptIsSent() {
        #expect(!LeaveGesture.matches(left, in: grid(["$ "], cursor: (2, 0))))
        #expect(!LeaveGesture.matches(left, in: grid(["% "], cursor: (2, 0))))
    }

    @Test func modifiersAndOtherKeysAreSent() {
        let g = grid(["❯ "], cursor: (2, 0))
        for name in ["shift-left", "ctrl-left", "opt-left", "cmd-left", "right", "up", "h"] {
            #expect(!LeaveGesture.matches(NamedKey(name)!, in: g), "\(name)")
        }
    }

    @Test func cursorOffTheGridIsSent() {
        #expect(!LeaveGesture.matches(left, in: grid(["❯ "], cursor: (2, 3))))
    }

    // MARK: the guard fails closed until the TUI has painted (v8 slice 2)

    /// The hole this closes: a pane whose `claude attach` has not drawn
    /// yet answered the prompt read with "no", and "no" means *send it*.
    /// The child answers a ← by detaching the session and opening the
    /// agents view inside the attach client, workspace-trust dialog
    /// first. The window is seconds wide, not a frame.
    @Test func anUnpaintedGridTakesTheKey() {
        let blank = grid(["", "", ""], cursor: (0, 0))
        #expect(LeaveGesture.isUndrawn(blank))
        #expect(LeaveGesture.matches(left, in: blank))
    }

    /// A grid with no lines at all — a host built and never fed.
    @Test func anEmptyGridTakesTheKey() {
        let none = Grid(cols: 80, rows: 0, lines: [], cursor: .init(col: 0, row: 0, visible: false))
        #expect(LeaveGesture.isUndrawn(none))
        #expect(LeaveGesture.matches(left, in: none))
    }

    /// Why the predicate counts lines instead of asking whether anything
    /// is on the grid: `claude attach` prints this one line seconds
    /// before the session's screen arrives (peeked from a fresh attach,
    /// 2026-09-03), and one line is both non-blank and perfectly stable.
    /// A blank-check calls this painted; it is the pre-TUI window still.
    @Test func theAttachClientsWakeMessageIsNotPainted() {
        let waking = grid(["Waking session ad19c590…", "", ""], cursor: (0, 1))
        #expect(LeaveGesture.isUndrawn(waking))
        #expect(LeaveGesture.matches(left, in: waking))
    }

    /// Two rows is a screen. From there the prompt read decides again —
    /// and this one has no prompt, so the key goes to the child.
    @Test func twoPaintedRowsAreAScreenAgain() {
        let drawn = grid(["── polish ─", "some output", ""], cursor: (0, 1))
        #expect(!LeaveGesture.isUndrawn(drawn))
        #expect(!LeaveGesture.matches(left, in: drawn))
    }

    /// A grid with nothing under the one painted row is showing all it
    /// has, so it is a screen — otherwise every one-row pane would hold
    /// the key forever. The prompt read decides these, as it always did.
    @Test func aFullOneRowGridIsAScreen() {
        #expect(!LeaveGesture.isUndrawn(grid(["❯ "], cursor: (2, 0))))
        #expect(LeaveGesture.matches(left, in: grid(["❯ "], cursor: (2, 0))))
        #expect(!LeaveGesture.matches(left, in: grid(["$ "], cursor: (2, 0))))
    }

    /// Failing closed is about ←, not about every key: an unpainted pane
    /// still types, so only the one key that costs the session is held.
    @Test func onlyLeftIsHeldBackWhileUnpainted() {
        let blank = grid(["", ""], cursor: (0, 0))
        for name in ["right", "up", "enter", "escape", "ctrl-c", "shift-left", "cmd-left"] {
            #expect(!LeaveGesture.matches(NamedKey(name)!, in: blank), "\(name)")
        }
    }
}
