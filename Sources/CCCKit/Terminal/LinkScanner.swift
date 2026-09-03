import Foundation

/// URLs on the grid, found by reading the text (v7 slice 2).
///
/// ⌘-click opens the link under the pointer. A plain click is the child's
/// business — Claude Code keeps mouse tracking on and does its own
/// selection with it (measured 2026-09-03: a drag highlights the row and
/// the TUI answers "copied N chars to clipboard") — so the gesture that is
/// ours has to be one the child does not want. ⌘-click is intercepted
/// before the mouse encoder, exactly as ← is intercepted before the key
/// encoder (`LeaveGesture`), and no bytes reach the PTY.
///
/// **A link here is text, not OSC 8.** The core does carry real hyperlinks
/// (`ghostty_grid_ref_hyperlink_uri`), but the URLs that actually show up
/// in an agent's pane — a CDN link in a tool result, a PR URL in a commit
/// message — are printed as plain characters by a program that never
/// emitted a hyperlink sequence. So the scan is over the rendered grid,
/// which is also what makes it work headless, on either core, and through
/// `ccc links` on another Mac.
///
/// **One row at a time, deliberately.** A URL that wraps is found only as
/// far as its first row. Rejoining rows needs the soft-wrap flag, and the
/// render state ccc reads has no such field — `GHOSTTY_RENDER_STATE_ROW_DATA_*`
/// is dirty/raw/cells/selection, while `GHOSTTY_ROW_DATA_WRAP` lives on the
/// screen API the snapshot path never touches. The tempting guess — "the run
/// reached the last column, so join the next row" — is wrong more often than
/// right in this app, because Claude Code hard-wraps its own output: the next
/// row is usually a fresh line of prose, and joining would silently hand the
/// browser a URL with a sentence glued to its path. Carrying a real wrap flag
/// through the seam is what makes wrapped links correct, and it is its own
/// slice.
public enum LinkScanner {
    /// One URL found on one row.
    public struct Link: Equatable, Sendable {
        public let url: URL
        /// The matched text exactly as it appears on the grid.
        public let text: String
        public let row: Int
        /// The columns the text occupies on `row`.
        public let columns: Range<Int>

        public init(url: URL, text: String, row: Int, columns: Range<Int>) {
            self.url = url
            self.text = text
            self.row = row
            self.columns = columns
        }
    }

    /// Only schemes worth handing to `NSWorkspace` unattended. `file://`
    /// is here because an agent's output names local paths constantly;
    /// anything that could launch a helper (`mailto:`, custom schemes) is
    /// not, since the pane's content is written by a program, not typed by
    /// the user.
    public static let schemes = ["https://", "http://", "file://"]

    /// RFC 3986's unreserved + reserved sets, plus `%` for escapes. The
    /// trailing-punctuation trim below is what keeps `,` `;` `!` `'` `)`
    /// from swallowing the sentence a URL sits in.
    static func isURLCharacter(_ c: Character) -> Bool {
        if c.isLetter || c.isNumber { return c.isASCII }
        return "-._~:/?#[]@!$&'()*+,;=%".contains(c)
    }

    /// Every link on the visible grid, in reading order.
    public static func links(in grid: Grid) -> [Link] {
        grid.lines.enumerated().flatMap { row, line in links(inRow: line, row: row) }
    }

    /// The link under `column` on `row`, if there is one.
    public static func link(in grid: Grid, atColumn column: Int, row: Int) -> Link? {
        guard row >= 0, row < grid.lines.count else { return nil }
        return links(inRow: grid.lines[row], row: row).first { $0.columns.contains(column) }
    }

    static func links(inRow line: String, row: Int) -> [Link] {
        let chars = Array(line)
        var found: [Link] = []
        var i = 0
        while i < chars.count {
            guard let scheme = schemes.first(where: { matches($0, in: chars, at: i) }) else {
                i += 1
                continue
            }
            var end = i + scheme.count
            while end < chars.count, isURLCharacter(chars[end]) { end += 1 }
            let start = i
            i = max(end, i + 1)
            // A scheme with nothing after it is not a link.
            guard end > start + scheme.count else { continue }
            end = trimmedEnd(chars, from: start, to: end)
            guard end > start + scheme.count else { continue }
            let text = String(chars[start..<end])
            guard let url = URL(string: text), url.host != nil || scheme == "file://" else { continue }
            found.append(Link(url: url, text: text, row: row, columns: start..<end))
        }
        return found
    }

    private static func matches(_ scheme: String, in chars: [Character], at index: Int) -> Bool {
        let s = Array(scheme)
        guard index + s.count <= chars.count else { return false }
        for (k, c) in s.enumerated() {
            guard chars[index + k].lowercased() == String(c) else { return false }
        }
        return true
    }

    /// Where the URL really ends. Sentence punctuation that is legal *inside*
    /// a URL is almost never meant as part of one at its tail, and a closing
    /// bracket only belongs if this URL opened it — the "(see https://x/y)"
    /// case, which is how these appear in prose.
    private static func trimmedEnd(_ chars: [Character], from start: Int, to end: Int) -> Int {
        var end = end
        while end > start {
            let c = chars[end - 1]
            if ".,;:!?'\"".contains(c) {
                end -= 1
            } else if let opener = closers[c] {
                let span = chars[start..<end]
                guard span.filter({ $0 == c }).count > span.filter({ $0 == opener }).count else { break }
                end -= 1
            } else {
                break
            }
        }
        return end
    }

    private static let closers: [Character: Character] = [")": "(", "]": "[", "}": "{"]
}
