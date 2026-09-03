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
}
