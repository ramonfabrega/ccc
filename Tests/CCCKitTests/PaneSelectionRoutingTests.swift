import AppKit
import Metal
import Testing

@testable import CCCKit

/// Evaluated once, off the main actor, so it can gate `@Test(.enabled(if:))`.
private let hasMetalDevice = MTLCreateSystemDefaultDevice() != nil

/// Item 13's other half: **who gets the press**. `SelectionGestureTests`
/// proves the gesture makes the right selection; this proves the pane hands
/// it the right events — and, just as much, that it does not steal the ones
/// the child is waiting for.
///
/// The child owns the mouse (Claude Code keeps tracking on and does its own
/// drag-selection), so the rule has two halves and both are here: with
/// tracking on, only **shift** makes a drag ours; with tracking off, the
/// plain drag is ours because nothing else wants it.
///
/// These drive real `NSEvent`s through the real `PaneInputView`, so what is
/// under test is the routing as the window will run it. No assertion depends
/// on where a synthesized event lands in the grid — only on which of the two
/// outcomes happened, which is the question the routing answers.
@Suite struct PaneSelectionRoutingTests {
    /// Opposite corners of the pane. Deliberately the whole diagonal: a
    /// synthesized event has no window to be converted through, so which row
    /// a y lands on is not worth asserting — a drag across everything covers
    /// the text row whichever way the axis runs.
    static let from = CGPoint(x: 10, y: 5)
    static let to = CGPoint(x: 620, y: 395)

    @MainActor private func pane(tracking: Bool) -> (GhosttyPane, () -> Data) {
        let pane = GhosttyPane(frame: CGRect(x: 0, y: 0, width: 640, height: 400))
        var written = Data()
        pane.onOutput = { written.append($0) }
        // DEC 1002: button-event tracking, which is what a TUI turns on when
        // it wants drags. Anything the terminal replies to the child on the
        // way in is drained with it, so `written` is only what the drag sent.
        if tracking { pane.feed(Data("\u{1B}[?1002h".utf8)) }
        // Every row full of text, on purpose: a synthesized event has no
        // window to be converted through, so where in the grid the drag
        // lands is not worth pinning — filling the screen makes "is there
        // text in it" true for any selection that covers anything at all.
        let line = String(repeating: "the quick brown fox jumps over the lazy dog. ", count: 4)
        pane.feed(Data(Array(repeating: line, count: 40).joined(separator: "\r\n").utf8))
        written.removeAll()
        return (pane, { written })
    }

    @MainActor private func drag(_ pane: GhosttyPane, modifiers: NSEvent.ModifierFlags = []) {
        guard let view = pane.view else { return }
        func event(_ type: NSEvent.EventType, _ location: CGPoint, _ time: TimeInterval) -> NSEvent? {
            NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: modifiers, timestamp: time,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        guard let down = event(.leftMouseDown, Self.from, 1),
              let moved = event(.leftMouseDragged, Self.to, 1.05),
              let up = event(.leftMouseUp, Self.to, 1.1) else { return }
        view.mouseDown(with: down)
        view.mouseDragged(with: moved)
        view.mouseUp(with: up)
    }

    /// The child asked for drags, so it gets them: bytes on the wire, and
    /// nothing selected locally. This is the half that a wrong modifier
    /// would break — and break silently, since the pane would look right and
    /// the TUI would simply stop responding to the mouse.
    @Test(.enabled(if: hasMetalDevice)) @MainActor func aPlainDragGoesToATrackingChild() {
        let (pane, written) = pane(tracking: true)
        drag(pane)
        #expect(!written().isEmpty)
        #expect(!pane.hasSelection)
    }

    /// Shift is ours. The child sees nothing at all — not a press, not a
    /// release — because a child that saw no button-down must never get a
    /// button-up.
    @Test(.enabled(if: hasMetalDevice)) @MainActor func aShiftDragSelectsEvenWhileTheChildTracks() {
        let (pane, written) = pane(tracking: true)
        drag(pane, modifiers: .shift)
        #expect(written().isEmpty)
        #expect(pane.hasSelection)
        #expect(pane.selectionText()?.isEmpty == false)
    }

    /// Nothing is tracking, so the plain drag is ours — the case the pane
    /// used to answer by sending nothing and selecting nothing.
    @Test(.enabled(if: hasMetalDevice)) @MainActor func aPlainDragSelectsWhenNothingIsTracking() {
        let (pane, written) = pane(tracking: false)
        drag(pane)
        #expect(written().isEmpty)
        #expect(pane.hasSelection)
    }

    /// A click is a press that never moved, and it takes the selection away.
    /// That is what keeps ⌘C unambiguous: what is highlighted is what copies.
    @Test(.enabled(if: hasMetalDevice)) @MainActor func aClickClearsTheSelection() {
        let (pane, _) = pane(tracking: false)
        drag(pane)
        #expect(pane.hasSelection)

        guard let view = pane.view,
              let down = NSEvent.mouseEvent(
                with: .leftMouseDown, location: Self.from, modifierFlags: [], timestamp: 2,
                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(
                with: .leftMouseUp, location: Self.from, modifierFlags: [], timestamp: 2.05,
                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)
        else { return }
        view.mouseDown(with: down)
        view.mouseUp(with: up)
        #expect(!pane.hasSelection)
    }

    /// And so does typing, which is the other half of the same rule.
    @Test(.enabled(if: hasMetalDevice)) @MainActor func typingClearsTheSelection() {
        let (pane, _) = pane(tracking: false)
        drag(pane)
        #expect(pane.hasSelection)

        guard let view = pane.view,
              let key = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 2,
                windowNumber: 0, context: nil, characters: "x", charactersIgnoringModifiers: "x",
                isARepeat: false, keyCode: 7)
        else { return }
        view.keyDown(with: key)
        #expect(!pane.hasSelection)
    }

    /// ⌘C copies what is selected and takes the key; with nothing selected it
    /// leaves the key alone, which is how the menu keeps it.
    @Test(.enabled(if: hasMetalDevice)) @MainActor func commandCTakesTheKeyOnlyWhenSomethingIsSelected() {
        // This is the one test that writes to the real pasteboard, because
        // the copy *is* the pasteboard. Put the user's clipboard back.
        let previous = NSPasteboard.general.string(forType: .string)
        defer {
            NSPasteboard.general.clearContents()
            if let previous { NSPasteboard.general.setString(previous, forType: .string) }
        }
        let (pane, _) = pane(tracking: false)
        guard let view = pane.view,
              let copy = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 2,
                windowNumber: 0, context: nil, characters: "c", charactersIgnoringModifiers: "c",
                isARepeat: false, keyCode: 8)
        else { return }
        #expect(!view.performKeyEquivalent(with: copy))

        drag(pane)
        #expect(pane.hasSelection)
        #expect(view.performKeyEquivalent(with: copy))
        // The pane keeps no clipboard of its own: the pasteboard is the copy.
        #expect(NSPasteboard.general.string(forType: .string) == pane.selectionText())
    }
}
