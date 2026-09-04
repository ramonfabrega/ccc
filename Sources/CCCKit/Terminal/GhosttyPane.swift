import AppKit
import Foundation

/// The v1 pane: `GhosttyHost` (core) drawn by `MetalPaneView` (renderer),
/// with the window's input routed through the core's own encoders. This is
/// what replaces `SwiftTermHost` when it wins the six checks; until then
/// `CCC_CORE=ghostty` selects it.
///
/// Frame pacing follows Zed: output is fed to the core immediately, and a
/// frame is read and handed to the view at most once per 4 ms, so a burst
/// of PTY writes costs one draw. The view then draws on the next display
/// pass, so ten frames before a vsync still cost one encode.
@MainActor
public final class GhosttyPane: TerminalHost {
    public let core: GhosttyHost
    private let metalView: MetalPaneView
    private let container: PaneInputView
    private var frameScheduled = false
    private var pendingFrame = false
    /// Mouse encoding is the core's job too; the encoder retains `core` so
    /// the terminal handle outlives it. Built once, options synced per event.
    private lazy var mouse: GhosttyMouse = {
        let mouse = GhosttyMouse(host: core)
        mouse.setCellSize(width: Int(metrics.widthPixels), height: Int(metrics.heightPixels))
        return mouse
    }()
    /// Sub-line trackpad pixels not yet spent on a whole line of scroll.
    private var scrollRemainder: CGFloat = 0
    /// The drag's state machine (item 13), built on the same terms as the
    /// mouse encoder: the core owns the rules, this owns the handle.
    private lazy var selection = GhosttySelectGesture(host: core)
    /// True between a press this pane took for itself and its release, so
    /// the drag and the release that follow go to the gesture rather than
    /// to the child.
    fileprivate private(set) var selecting = false

    public var onOutput: ((Data) -> Void)?
    /// The grid changed because the view did (window resize); the owner
    /// mirrors it onto the PTY. Same contract as `SwiftTermHost`.
    public var onSizeChanged: ((Int, Int) -> Void)?
    /// A ⌘-click landed on a link. Unset means `NSWorkspace` opens it;
    /// the app sets it to count the gesture and name what it opened.
    public var onOpenLink: ((LinkScanner.Link) -> Void)?
    public var view: NSView? { container }
    public var metrics: CellMetrics { metalView.metrics }
    public var presentation: (frames: Int, lastAt: Date?)? {
        (metalView.presentedFrames, metalView.lastPresentedAt)
    }

    public init(
        frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
        font: NSFont? = nil, theme: Theme = .active
    ) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let metrics = CellMetrics(font: font ?? CellMetrics.defaultFont, scale: scale)
        // Both halves of the pane take the same theme: the core resolves
        // every cell colour out of it, the renderer keeps the two it never
        // sends us (cursor-text, selection).
        metalView = MetalPaneView(frame: CGRect(origin: .zero, size: frame.size), metrics: metrics, theme: theme)
        let grid = metalView.gridSize()
        core = GhosttyHost(cols: max(2, grid.cols), rows: max(1, grid.rows), theme: theme)
        core.setCellSize(width: Int(metrics.widthPixels), height: Int(metrics.heightPixels))
        container = PaneInputView(frame: frame)
        container.addSubview(metalView)
        metalView.autoresizingMask = [.width, .height]
        container.pane = self

        core.onOutput = { [weak self] bytes in self?.onOutput?(bytes) }
        metalView.onResize = { [weak self] grid in
            guard let self else { return }
            self.core.resize(cols: grid.cols, rows: grid.rows)
            self.onSizeChanged?(grid.cols, grid.rows)
            self.scheduleFrame()
        }
        scheduleFrame()
    }

    // MARK: seam

    public func feed(_ bytes: Data) {
        core.feed(bytes)
        scheduleFrame()
    }

    public func resize(cols: Int, rows: Int) {
        core.resize(cols: cols, rows: rows)
        scheduleFrame()
    }

    public func snapshot(colors: Bool) -> Grid { core.snapshot(colors: colors) }

    public func press(_ key: NamedKey) -> Bool { core.press(key) }

    /// The core's gate: `keyDown` goes to `core.press` too, so the window's
    /// keyboard and `ccc send --key` are answered by the same closure.
    public var keyInterceptor: ((NamedKey) -> Bool)? {
        get { core.keyInterceptor }
        set { core.keyInterceptor = newValue }
    }

    public func paste(_ text: String) -> Bool { core.paste(text) }

    /// Pixels of the pane as drawn — `ccc peek` composites this over the
    /// window capture, since a Metal layer is invisible to cacheDisplay.
    public func snapshotImage() -> CGImage? {
        if pendingFrame, let frame = core.frame() { metalView.render(frame) }
        return metalView.snapshotImage()
    }

    public var size: (cols: Int, rows: Int) { metalView.gridSize() }

    /// `ccc select`: the core's selection, and a frame to show it in. The
    /// twin of the drag below — both end in `GhosttyHost.install`, which is
    /// what makes the headless colour oracle and a real `screencapture` able
    /// to look at the same selected cells (item 12b).
    @discardableResult
    public func select(_ region: SelectionRegion?) -> Bool {
        let done = core.select(region)
        scheduleFrame()
        return done
    }

    /// `ccc copy`: the selected text, exactly as ⌘C would put it on the
    /// pasteboard. Nil when nothing is selected.
    public func selectionText() -> String? { core.selectionText() }

    public var hasSelection: Bool { core.hasSelection }

    /// `ccc send --wheel N`: the wheel gesture's twin, at the pane's center.
    /// Same path as a real wheel: the core's mouse encoder when the child
    /// tracks the mouse, arrow keys in the alternate screen otherwise.
    public func wheel(lines: Int) {
        guard lines != 0 else { return }
        let grid = metalView.gridSize()
        let cell = (col: grid.cols / 2, row: grid.rows / 2)
        let bytes = mouse.wheel(deltaLines: lines, col: cell.col, row: cell.row, mods: [])
        if !bytes.isEmpty {
            onOutput?(bytes)
            return
        }
        guard mouse.wantsArrowFallback, let key = NamedKey(lines > 0 ? "up" : "down") else { return }
        for _ in 0..<min(abs(lines), 5) { _ = core.press(key) }
    }

    // MARK: pacing

    private func scheduleFrame() {
        pendingFrame = true
        guard !frameScheduled else { return }
        frameScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(4)) { [weak self] in
            guard let self else { return }
            self.frameScheduled = false
            self.pendingFrame = false
            if let frame = self.core.frame() { self.metalView.render(frame) }
        }
    }

    // MARK: input (called by the container view)

    fileprivate func keyDown(_ event: NSEvent) {
        // Typing takes the selection away, as it does in every terminal.
        // ⌘C and ⌘V never reach here — `performKeyEquivalent` answers them
        // first — so a copy cannot clear what it is about to copy.
        clearSelection()
        if let key = Self.namedKey(for: event) {
            if core.press(key) { return }
        }
        // Plain text (including composed/non-ASCII input): hand the bytes
        // to the child as typed. Modifier-only or dead keys produce nothing.
        if let text = event.characters, !text.isEmpty,
           event.modifierFlags.intersection([.control, .command, .option]).isEmpty {
            onOutput?(Data(text.utf8))
        }
    }

    /// ⌘-click: open the link under the pointer (v7 slice 2). Answers
    /// whether it took the press, so the caller knows not to encode it.
    /// `onOpenLink` exists so the app can count the gesture and say what it
    /// opened; the default is `NSWorkspace`, which is what a terminal does.
    fileprivate func openLink(at event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        let cell = self.cell(for: event)
        guard let link = LinkScanner.link(in: snapshot(), atColumn: cell.col, row: cell.row) else { return false }
        open(link)
        return true
    }

    /// Open a link the way the window does. Also the road `ccc links --open`
    /// takes, so the gesture and its twin end in one place.
    public func open(_ link: LinkScanner.Link) {
        if let onOpenLink {
            onOpenLink(link)
        } else {
            NSWorkspace.shared.open(link.url)
        }
    }

    fileprivate func pasteFromPasteboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        _ = core.paste(text)
    }

    // MARK: the drag (item 13)

    /// Whether a press is ours rather than the child's.
    ///
    /// The child owns the mouse — Claude Code keeps tracking on and does its
    /// own drag-selection, answering "copied N chars to clipboard" — so ours
    /// has to be a gesture the child does not want. **Shift is that gesture**,
    /// and not by our invention: xterm, iTerm2, kitty and Ghostty all make
    /// shift the override that bypasses mouse reporting, so no child has ever
    /// seen a shift-drag in any terminal and none can miss it here. That is
    /// also why ⌘ is not it — ⌘ already opens links (v7 slice 2).
    ///
    /// When nothing is tracking the plain drag is ours too: the encoder would
    /// emit nothing at all, and an untracked drag that selects is simply what
    /// a terminal is. ⌥ makes the drag a rectangle, which is where a terminal
    /// puts it and what `GhosttySelection.rectangle` already takes.
    private func wantsSelection(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.shift) || !mouse.isTracking
    }

    /// Take the press, or leave it for the child. Answers which.
    ///
    /// The old selection goes away first, before the core is asked for a new
    /// one. That single line is the whole "what clears a selection" rule: a
    /// plain click leaves nothing installed and is therefore a clear, a
    /// double-click replaces it with a word, a drag replaces it as it moves.
    fileprivate func beginSelection(_ event: NSEvent) -> Bool {
        guard wantsSelection(event) else { return false }
        selecting = true
        clearSelection()
        let cell = self.cell(for: event)
        selection.press(
            col: cell.col, row: cell.row, position: surfacePoint(for: event),
            time: event.timestamp, repeatInterval: NSEvent.doubleClickInterval)
        scheduleFrame()
        return true
    }

    fileprivate func dragSelection(_ event: NSEvent) {
        let cell = self.cell(for: event)
        selection.drag(
            col: cell.col, row: cell.row, position: surfacePoint(for: event),
            geometry: selectionGeometry, rectangle: event.modifierFlags.contains(.option))
        scheduleFrame()
    }

    fileprivate func endSelection(_ event: NSEvent) {
        let cell = self.cell(for: event)
        selection.release(col: cell.col, row: cell.row)
        selecting = false
        scheduleFrame()
    }

    /// Take the selection away. The *gesture* is not reset: its click
    /// sequence has to survive this, or the second click of a double would
    /// count as a first.
    public func clearSelection() {
        guard core.hasSelection else { return }
        _ = core.install(selection: nil)
        scheduleFrame()
    }

    /// ⌘C, and `ccc copy`'s road: the selected text onto the system
    /// pasteboard, or nil when nothing is selected.
    ///
    /// The pane keeps no clipboard of its own. A terminal's selection *is*
    /// the pasteboard the moment the key is pressed, and a second store
    /// would only be one more thing to keep in sync.
    @discardableResult
    public func copySelection() -> String? {
        guard let text = core.selectionText(), !text.isEmpty else { return nil }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return text
    }

    /// The pointer in **surface pixels**, the space `GhosttySurfacePosition`
    /// and the gesture geometry are both expressed in: view points times the
    /// backing scale.
    private func surfacePoint(for event: NSEvent) -> CGPoint {
        let point = container.convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x * metrics.scale, y: point.y * metrics.scale)
    }

    private var selectionGeometry: GhosttySelectGesture.Geometry {
        let grid = metalView.gridSize()
        return .init(
            columns: grid.cols, cellWidth: Int(metrics.widthPixels),
            screenHeight: Int(metrics.heightPixels) * max(1, grid.rows))
    }

    fileprivate func scroll(_ event: NSEvent) {
        // Zed's `determine_scroll_lines` shape: a trackpad reports fractional
        // pixels, so they accumulate into a remainder and only whole lines
        // are emitted. A classic wheel reports whole lines already.
        let lines: Int
        if event.hasPreciseScrollingDeltas {
            scrollRemainder += event.scrollingDeltaY
            let whole = (scrollRemainder / metrics.height).rounded(.towardZero)
            scrollRemainder -= whole * metrics.height
            lines = Int(whole)
        } else {
            scrollRemainder = 0
            lines = Int(event.scrollingDeltaY.rounded())
        }
        guard lines != 0 else { return }

        let cell = self.cell(for: event)
        let bytes = mouse.wheel(deltaLines: lines, col: cell.col, row: cell.row, mods: Self.mods(for: event))
        if !bytes.isEmpty {
            onOutput?(bytes)
            return
        }
        // The core declined and told us why: alternate screen + mode 1007 +
        // no tracking. `GhosttyMouse.wheel` documents that alternate scroll
        // lives above the library line, so the arrows are ours to send —
        // through the key encoder, which applies DECCKM.
        guard mouse.wantsArrowFallback, let key = NamedKey(lines > 0 ? "up" : "down") else { return }
        for _ in 0..<min(abs(lines), 5) { _ = core.press(key) }
    }

    /// Cell under the pointer. The container is flipped, so the view's y
    /// already grows downward like the grid's row index.
    fileprivate func cell(for event: NSEvent) -> (col: Int, row: Int) {
        let point = container.convert(event.locationInWindow, from: nil)
        let grid = metalView.gridSize()
        let col = Int((point.x / metrics.width).rounded(.down))
        let row = Int((point.y / metrics.height).rounded(.down))
        return (min(max(col, 0), max(grid.cols - 1, 0)), min(max(row, 0), max(grid.rows - 1, 0)))
    }

    /// Mouse button events → the core's encoder. When the child has not
    /// enabled tracking the core emits nothing and we send nothing: that is
    /// the correct answer, not a dropped event — and since item 13 such a
    /// press never reaches here anyway, because `beginSelection` takes it
    /// for the local drag first, which is what a real terminal does with an
    /// untracked click.
    fileprivate func mouseEvent(_ event: NSEvent, button: GhosttyMouse.Button?, action: GhosttyMouse.Action) {
        let cell = self.cell(for: event)
        let bytes = mouse.encode(button: button, action: action, col: cell.col, row: cell.row, mods: Self.mods(for: event))
        guard !bytes.isEmpty else { return }
        onOutput?(bytes)
    }

    private static func mods(for event: NSEvent) -> GhosttyMouse.Modifiers {
        var mods: GhosttyMouse.Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.command) { mods.insert(.command) }
        return mods
    }

    /// NSEvent → the key the encoder understands. Letters/digits/punctuation
    /// with a modifier, and every special key, go through the core encoder;
    /// unmodified printable text is sent as text by the caller.
    static func namedKey(for event: NSEvent) -> NamedKey? {
        var parts: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option) { parts.append("opt") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.command) { parts.append("cmd") }
        if let special = specialKeys[event.keyCode] {
            return NamedKey((parts + [special]).joined(separator: "-"))
        }
        // Only route characters through the encoder when a modifier changes
        // their meaning; plain typing is text.
        guard !flags.intersection([.control, .option, .command]).isEmpty,
              let chars = event.charactersIgnoringModifiers, chars.count == 1 else { return nil }
        return NamedKey((parts + [String(chars)]).joined(separator: "-"))
    }

    /// macOS virtual key codes for the keys `NamedKey.Base` names.
    private static let specialKeys: [UInt16: String] = [
        36: "enter", 76: "enter", 53: "escape", 48: "tab", 51: "backspace", 117: "delete",
        126: "up", 125: "down", 123: "left", 124: "right", 115: "home", 119: "end", 116: "pageup", 121: "pagedown",
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
    ]
}

/// The NSView that owns focus and events for a Ghostty pane. Kept apart
/// from `MetalPaneView` so the renderer stays free of input plumbing.
@MainActor
final class PaneInputView: NSView {
    weak var pane: GhosttyPane?
    /// A left press swallowed by the ⌘-click link gesture, so its release
    /// and drag are swallowed with it.
    private var swallowedPress = false

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func keyDown(with event: NSEvent) {
        pane?.keyDown(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘V pastes through the core; everything else with ⌘ stays with AppKit.
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
            pane?.pasteFromPasteboard()
            return true
        }
        // ⌘C copies the selection — and only when there *is* one. With
        // nothing selected the key belongs to AppKit (and to the menu), the
        // way a terminal leaves it.
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c",
           pane?.copySelection() != nil {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        pane?.scroll(event)
    }

    // Buttons go to the core's mouse encoder. `makeFirstResponder` stays on
    // the left press so a click still focuses the pane; everything else is
    // pure encoding, and produces no bytes at all while tracking is off.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        // ⌘-click is ours (v7 slice 2): a link under the pointer opens and
        // nothing is encoded. Without a link the press falls through, so a
        // ⌘-click on ordinary text still reaches a child that asked for it.
        if pane?.openLink(at: event) == true {
            swallowedPress = true
            return
        }
        // Ours or the child's? Shift, or nothing tracking, makes it ours
        // (item 13) — and a press we take is never encoded, for the same
        // reason the link gesture's is not.
        if pane?.beginSelection(event) == true { return }
        pane?.mouseEvent(event, button: .left, action: .press)
    }

    override func mouseUp(with event: NSEvent) {
        // The press that opened a link was never encoded, so its release
        // and any drag in between must not be either: a child that saw no
        // button-down would otherwise get a button-up out of nowhere.
        if swallowedPress {
            swallowedPress = false
            return
        }
        if pane?.selecting == true {
            pane?.endSelection(event)
            return
        }
        pane?.mouseEvent(event, button: .left, action: .release)
    }

    override func mouseDragged(with event: NSEvent) {
        if swallowedPress { return }
        if pane?.selecting == true {
            pane?.dragSelection(event)
            return
        }
        pane?.mouseEvent(event, button: .left, action: .motion)
    }

    override func rightMouseDown(with event: NSEvent) {
        pane?.mouseEvent(event, button: .right, action: .press)
    }

    override func rightMouseUp(with event: NSEvent) {
        pane?.mouseEvent(event, button: .right, action: .release)
    }

    override func rightMouseDragged(with event: NSEvent) {
        pane?.mouseEvent(event, button: .right, action: .motion)
    }

    // AppKit funnels every button past the second through `otherMouse*`;
    // button number 2 is the middle button, and the rest have no place in
    // the protocols we encode, so they are dropped.
    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        pane?.mouseEvent(event, button: .middle, action: .press)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        pane?.mouseEvent(event, button: .middle, action: .release)
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        pane?.mouseEvent(event, button: .middle, action: .motion)
    }

    // Button-less motion is only meaningful under any-event tracking (DEC
    // 1003); the encoder drops it in every other mode, so no tracking-area
    // is installed until a pane needs 1003 — this override exists for when
    // one is.
    override func mouseMoved(with event: NSEvent) {
        pane?.mouseEvent(event, button: nil, action: .motion)
    }
}
