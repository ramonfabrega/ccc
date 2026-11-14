import Foundation

/// Keys typed between a click that attaches and the pane it attaches
/// arriving.
///
/// A switch keeps the old session on screen until the new one has drawn
/// (`PaneController.swap`), and for that long — a third of a second
/// locally, a second or more over ssh — the roster still has the
/// keyboard, where bare letters are commands: `t` opens a terminal, `a`
/// archives the row, `p` pins it, ⌫ asks to delete it. Someone who
/// double-clicks a session and starts typing is typing *to the session*
/// (Ramon, 2026-11-13: "if i type `t` as first letter it thinks its cmd
/// t"). So for the length of the wait the window holds the keys, and
/// hands them to the pane when it lands — what a terminal calls
/// type-ahead.
///
/// Generic so the bookkeeping is a test without an `NSEvent` in it.
public struct TypeAhead<Event> {
    /// More than this is not typing ahead of a pane, it is a stuck key.
    public static var limit: Int { 256 }

    private var token = 0
    private var open = false
    private var held: [Event] = []

    public init() {}

    public var isOpen: Bool { open }

    /// A click started an attach. Keys held for an earlier click were
    /// meant for *its* session and are dropped.
    public mutating func begin() -> Int {
        token += 1
        open = true
        held.removeAll()
        return token
    }

    public mutating func hold(_ event: Event) {
        guard open, held.count < Self.limit else { return }
        held.append(event)
    }

    /// The attach that `token` began is over. Its keys, when it is still
    /// the latest click — `nil` when a newer one took over, which owns
    /// whatever is typed from then on.
    public mutating func end(_ token: Int) -> [Event]? {
        guard open, token == self.token else { return nil }
        open = false
        defer { held.removeAll() }
        return held
    }
}
