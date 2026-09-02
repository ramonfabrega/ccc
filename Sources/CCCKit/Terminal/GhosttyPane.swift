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

    public var onOutput: ((Data) -> Void)?
    /// The grid changed because the view did (window resize); the owner
    /// mirrors it onto the PTY. Same contract as `SwiftTermHost`.
    public var onSizeChanged: ((Int, Int) -> Void)?
    public var view: NSView? { container }
    public var metrics: CellMetrics { metalView.metrics }

    public init(frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600), font: NSFont? = nil) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let metrics = CellMetrics(font: font ?? CellMetrics.defaultFont, scale: scale)
        metalView = MetalPaneView(frame: CGRect(origin: .zero, size: frame.size), metrics: metrics)
        let grid = metalView.gridSize()
        core = GhosttyHost(cols: max(2, grid.cols), rows: max(1, grid.rows))
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

    public func snapshot() -> Grid { core.snapshot() }

    public func press(_ key: NamedKey) -> Bool { core.press(key) }

    public func paste(_ text: String) -> Bool { core.paste(text) }

    /// Pixels of the pane as drawn — `ccc peek` composites this over the
    /// window capture, since a Metal layer is invisible to cacheDisplay.
    public func snapshotImage() -> CGImage? {
        if pendingFrame, let frame = core.frame() { metalView.render(frame) }
        return metalView.snapshotImage()
    }

    public var size: (cols: Int, rows: Int) { metalView.gridSize() }

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

    fileprivate func pasteFromPasteboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        _ = core.paste(text)
    }

    fileprivate func scroll(_ event: NSEvent) {
        // v1 start: wheel → arrow keys, which the alt-screen TUI understands
        // (Zed does the same in alternate-scroll mode). Mouse reporting via
        // the core's mouse API is check 3's proper answer and comes next.
        let lines = Int((event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? metrics.height : 1)).rounded())
        guard lines != 0, let key = NamedKey(lines > 0 ? "up" : "down") else { return }
        for _ in 0..<min(abs(lines), 5) { _ = core.press(key) }
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
        return super.performKeyEquivalent(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        pane?.scroll(event)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }
}
