import Foundation

/// The harness's "← opens agents" gesture, recognized *before* the key is
/// sent (v7 slice 1; docs/HARNESS.md "Left arrow").
///
/// In `claude agents` a bare ← on an empty prompt takes you back to the
/// roster. `claude attach` — our pane's child — implements the same
/// gesture by detaching and opening the agents view *inside the attach
/// client*, which begins with the workspace-trust dialog for the client's
/// own cwd: measured 2026-09-03 (2.1.259) headless from an untrusted
/// folder, one ← on `❯ ` went from the transcript to "Waking session …"
/// and "Accessing workspace: <cwd> … Yes, I trust this folder". In the app
/// that cwd is whatever the bundle inherited. The harness's own gate
/// (`leftArrowOpensAgents`, on by default) lives in the user's
/// `~/.claude.json` and switches the gesture off everywhere, so ccc leaves
/// it alone and answers the press itself: when the grid says the press
/// would fire, the key is not sent and the roster takes the keyboard —
/// what "back to the list" means here.
///
/// The recognition is the harness's condition read off the grid: the
/// cursor is visible and sits right after the prompt glyph and its space
/// (`❯ ` normally; `>` in plain-ASCII terminals, `!` in bash mode, `#` in
/// memory mode) at column 2 of its row. Nothing after the cursor is
/// inspected: an empty prompt may carry a dim placeholder there, which
/// the grid cannot tell from a draft. So ← at the very start of a draft
/// is also ours — the harness would have answered that one with "Cannot
/// open agents — you have unsent text" and moved nothing, so the only
/// difference is where the keyboard ends up. A ← anywhere else — inside
/// text, on a continuation row, on a dialog row (cursor hidden) — is
/// sent through unchanged. What this does not replicate is the harness's
/// editing guard (a ← right after deleting to empty is absorbed there);
/// here it fires at once.
public enum LeaveGesture {
    /// The prompt glyphs the harness draws at column 0 of the input row.
    public static let prompts: Set<Character> = ["❯", ">", "!", "#"]
    /// What follows the glyph: measured 2026-09-03 (2.1.259), the harness
    /// draws a NO-BREAK SPACE (U+00A0) there, not U+0020 — a snapshot's
    /// `rstrip` hides the difference, the grid does not. Both are accepted.
    public static let gaps: Set<Character> = [" ", "\u{00A0}"]

    /// True when `key` is a bare ← and `grid` shows the cursor at the
    /// start of an input row.
    public static func matches(_ key: NamedKey, in grid: Grid) -> Bool {
        guard key.base == .left, !key.shift, !key.control, !key.option, !key.command else { return false }
        let cursor = grid.cursor
        guard cursor.visible, cursor.col == 2, cursor.row >= 0, cursor.row < grid.lines.count else { return false }
        let line = Array(grid.lines[cursor.row])
        guard line.count >= 2, prompts.contains(line[0]), gaps.contains(line[1]) else { return false }
        return true
    }
}
