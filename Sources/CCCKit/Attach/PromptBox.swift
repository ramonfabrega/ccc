import Foundation

/// What is in the pane's input box, and whether it is anybody's.
///
/// `LeaveGesture` says of the same row that "an empty prompt may carry a
/// dim placeholder there, which the grid cannot tell from a draft", and
/// for a key it does not have to: ← at the start of a draft and ← on an
/// empty box mean the same thing. Anything that *types* does have to.
/// Measured 2026-09-06 on a background session (docs/EVIDENCE.md "item
/// 27"): with `ZZ` sitting unsent in the box, typing `/clear` and pressing
/// enter submitted **`ZZ/clear` as a prompt** — no clear, and the model
/// answered "Conversation cleared. Ready for new tasks.", a false clear
/// that reads exactly like a real one. Whatever is in the box is prefixed
/// onto what we type, so a verb that types has to know.
///
/// The discriminator is the cursor, not the text. The harness draws a
/// history hint in the box without moving the cursor off the prompt
/// column, and leaves it there through `end` and `ctrl-u` — measured, and
/// the hint vanished the moment a character was typed. A draft moves the
/// cursor with it. So: press `end`, then read.
///
///   `❯ cat marker.txt` with the cursor at column 2  → a hint; safe to type
///   `❯ ZZ`             with the cursor at column 4  → a draft; not ours
///
/// Fails closed. A row that cannot be read as an input box at all — a
/// wrapped draft's continuation row, a dialog, a pane that has not
/// painted — is `.unreadable`, and a caller that types must treat that
/// the way it treats a draft.
public enum PromptBox {
    public enum Reading: Sendable, Equatable {
        /// An input box with nothing of anyone's in it.
        case empty
        /// Unsent text, and the cursor is in it.
        case draft(String)
        /// Text drawn past the cursor: the harness's own hint, which the
        /// next character typed replaces.
        case hint(String)
        /// Not an input row, or nothing painted yet.
        case unreadable

        /// Is it safe for us to type here?
        public var isOurs: Bool {
            switch self {
            case .empty, .hint: return true
            case .draft, .unreadable: return false
            }
        }

        /// The words in the box, for the sentence a refusal prints.
        public var text: String? {
            switch self {
            case .draft(let t), .hint(let t): return t
            case .empty, .unreadable: return nil
            }
        }
    }

    /// Read the box on the cursor's row. A `.hint` is the only reading
    /// that is not final: text is drawn past the cursor, which is either
    /// the harness's hint or a draft whose cursor was left at home, and
    /// `end` then a second read separates them. The other three need no
    /// keystroke — which matters, because a key sent to an `.unreadable`
    /// row is a key sent into somebody's dialog.
    public static func read(_ grid: Grid) -> Reading {
        if LeaveGesture.isUndrawn(grid) { return .unreadable }
        let cursor = grid.cursor
        guard cursor.visible, cursor.row >= 0, cursor.row < grid.lines.count else { return .unreadable }
        let line = Array(grid.lines[cursor.row])
        guard line.count >= 2, LeaveGesture.prompts.contains(line[0]), LeaveGesture.gaps.contains(line[1]) else {
            return .unreadable
        }
        // Trailing blanks the way `Grid.rendered` drops them, with the
        // harness's NO-BREAK SPACE counted as one.
        let drawn = String(line.dropFirst(2).reversed()
            .drop { $0 == " " || LeaveGesture.gaps.contains($0) }.reversed())
        if drawn.isEmpty { return cursor.col == 2 ? .empty : .unreadable }
        // The cursor is at or past the end of what is drawn: the text
        // moved with it, so it is real.
        return cursor.col >= 2 + drawn.count ? .draft(drawn) : .hint(drawn)
    }
}
