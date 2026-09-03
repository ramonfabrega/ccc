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
///
/// **The guard fails closed on a pane that has not painted.** The
/// recognition above is a read of what is on the grid *now*, and its
/// `false` means "send it" — so a grid with nothing on it, which is what
/// a freshly built host shows until its `claude attach` draws, used to
/// hand the child the one key it must never get. That window is seconds
/// wide, not a frame: experiment 3 measured the TUI taking up to 12 s to
/// paint over ssh. An unpainted grid is not "the cursor is not at a
/// prompt", it is "we cannot see yet", and the two must not answer the
/// same. So `isUndrawn` takes the press as well: nothing typed at an
/// unpainted TUI means anything, and the roster is where ← was going
/// anyway.
public enum LeaveGesture {
    /// The prompt glyphs the harness draws at column 0 of the input row.
    public static let prompts: Set<Character> = ["❯", ">", "!", "#"]
    /// What follows the glyph: measured 2026-09-03 (2.1.259), the harness
    /// draws a NO-BREAK SPACE (U+00A0) there, not U+0020 — a snapshot's
    /// `rstrip` hides the difference, the grid does not. Both are accepted.
    public static let gaps: Set<Character> = [" ", "\u{00A0}"]

    /// The pane has not painted its screen yet.
    ///
    /// Not simply "the grid is blank". `claude attach` prints its own
    /// one-line wake message — "Waking session <id>…", peeked from a fresh
    /// attach 2026-09-03 — seconds before the session's screen arrives,
    /// and one line is enough to make a blank-check answer "drawn" while
    /// the prompt is still nowhere.
    ///
    /// So the shape is what is read, not the emptiness: **at most one row
    /// carries anything, and there are still empty rows under it.** That
    /// is exactly a wake message on a 40-row pane, and it is never a TUI,
    /// which fills its rows with an input box, a status line and whatever
    /// transcript it is replaying. The second half of the condition is
    /// what keeps a small grid honest — a pane with one row *is* showing
    /// everything it has, and the prompt read below decides it.
    ///
    /// `PaneController.waitUntilDrawn` waits on this same predicate, so
    /// the guard closes over exactly the window that wait covers and the
    /// swap never mounts a screen this would hold a key back for.
    public static func isUndrawn(_ grid: Grid) -> Bool {
        let painted = grid.lines.filter { !$0.allSatisfy(\.isWhitespace) }.count
        // Nothing at all, whatever the grid's size — including a host
        // built and never fed, whose grid has no rows to count.
        if painted == 0 { return true }
        // One row, with room under it: the wake message's shape.
        return painted == 1 && grid.lines.count > 1
    }

    /// True when `key` is a bare ← and either the grid shows the cursor
    /// at the start of an input row, or the grid has not been painted yet.
    public static func matches(_ key: NamedKey, in grid: Grid) -> Bool {
        guard key.base == .left, !key.shift, !key.control, !key.option, !key.command else { return false }
        // Fail closed while there is nothing to read.
        if isUndrawn(grid) { return true }
        let cursor = grid.cursor
        guard cursor.visible, cursor.col == 2, cursor.row >= 0, cursor.row < grid.lines.count else { return false }
        let line = Array(grid.lines[cursor.row])
        guard line.count >= 2, prompts.contains(line[0]), gaps.contains(line[1]) else { return false }
        return true
    }
}
