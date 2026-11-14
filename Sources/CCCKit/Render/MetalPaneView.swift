import AppKit
import CoreGraphics
import Metal
import QuartzCore

/// The `NSView` a `CAMetalLayer` lives in, and the only place in the renderer
/// that knows about windows, screens and backing scale.
///
/// It holds no input handling on purpose: the pane's key and mouse routing is
/// wired by whoever owns the view (`GhosttyHost` via the `TerminalHost` seam),
/// so that the same renderer can be driven by a test, by `ccc peek`, or by a
/// window without three copies of the event plumbing. It is willing to be
/// first responder so the owner can make it one.
@MainActor
public final class MetalPaneView: NSView {
    /// Called when — and only when — the *grid* changes size. Resizing a window
    /// by a few points inside one cell fires nothing, which is what keeps a
    /// live drag from spraying `TIOCSWINSZ` at the child.
    public var onResize: (((cols: Int, rows: Int)) -> Void)?

    public var metrics: CellMetrics {
        didSet {
            reportGridIfChanged()
            drawCurrentFrame()
        }
    }

    public private(set) var renderer: MetalRenderer?

    private let metalLayer = CAMetalLayer()

    /// What the pane's bytes are: sRGB, the space every `Theme` value and
    /// every truecolor SGR is written in.
    public static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    /// What the on-screen layer declares, by name — `nil` is an unmanaged
    /// layer. Public so the declaration is a test and not a comment.
    public var layerColorSpaceName: String? { metalLayer.colorspace?.name as String? }
    private var frameToDraw: Frame?
    private var lastReportedGrid: (cols: Int, rows: Int)?

    public init(frame frameRect: NSRect, metrics: CellMetrics = CellMetrics(), theme: Theme = .active) {
        self.metrics = metrics
        super.init(frame: frameRect)
        // The layer comes from `makeBackingLayer()`, never from assigning
        // `layer` after `wantsLayer`: a layer assigned by hand is one AppKit
        // does not display for us — `updateLayer` was never called, the pane
        // stayed black on screen, and only the offscreen `snapshotImage`
        // path (what `ccc peek` and the six checks look at) ever drew.
        // Found 2026-09-02 with a real `screencapture`; the checks had been
        // judging the renderer, not the presentation.
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize

        renderer = MetalRenderer()
        renderer?.theme = theme
        metalLayer.device = renderer?.device ?? MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        // The theme's values are sRGB, and a layer that does not say so is
        // not colour-matched: its bytes go to the panel as the panel's own.
        // On an sRGB display that is the identity, which is why studio
        // measured "no residual" (docs/EVIDENCE.md "8b") — and on a P3
        // panel an orange `#D97757` is shown where `#CC7C5E` is meant.
        metalLayer.colorspace = Self.colorSpace
        // We never read back from the drawable (snapshots go through their own
        // offscreen texture), so the driver may keep it write-only.
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        metalLayer.allowsNextDrawableTimeout = true
        // Presenting on the layer's own schedule rather than inside the
        // CATransaction: the pane is not synchronized with other AppKit
        // drawing, and `true` costs a main-thread wait per frame.
        metalLayer.presentsWithTransaction = false
        metalLayer.contentsScale = window?.backingScaleFactor ?? metrics.scale
        metalLayer.drawableSize = drawableSize()
        // Seeded so the first `setFrameSize` inside the same cell does not
        // report a "change"; the owner bootstraps with `gridSize()`.
        lastReportedGrid = metrics.gridSize(for: frameRect.size)
    }

    /// AppKit asks for this when `wantsLayer` is set; answering with our
    /// `CAMetalLayer` makes it the view's backing layer, with AppKit as its
    /// delegate — which is what routes `needsDisplay` to `updateLayer`.
    public override func makeBackingLayer() -> CALayer { metalLayer }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("MetalPaneView is created in code") }

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public override var wantsUpdateLayer: Bool { true }

    // MARK: - Frames

    /// Frames handed to the layer's drawable, and when the last one was.
    /// A Metal layer that is drawn to but never presented is black on
    /// screen while every offscreen snapshot looks perfect — which is what
    /// happened for a whole day (2026-09-02): `ccc peek` composites the
    /// snapshot, so the agent saw text and the human saw black. This number
    /// is the one both can read (`ccc stats`).
    public private(set) var presentedFrames: Int = 0
    public private(set) var lastPresentedAt: Date?

    /// Hand the view the frame to show — and draw it now. A `CAMetalLayer`
    /// owns its contents: `needsDisplay` on the view is a no-op for it
    /// (AppKit reports the flag false straight after it is set, measured)
    /// and `updateLayer` never comes, so the invalidate-and-wait pattern
    /// that works for every other layer-backed view shows nothing here.
    /// Coalescing is the caller's job (`GhosttyPane.scheduleFrame` paces
    /// output to one frame per few milliseconds).
    public func render(_ frame: Frame) {
        frameToDraw = frame
        drawCurrentFrame()
    }

    public override func updateLayer() {
        drawCurrentFrame()
    }

    public override func draw(_ dirtyRect: NSRect) {
        drawCurrentFrame()
    }

    /// A frame arrived while the view was in no window and was not drawn;
    /// the next draw that reaches a drawable is owed in full.
    private var owesDraw = false

    private func drawCurrentFrame() {
        guard let renderer, var frame = frameToDraw else { return }
        // Not on a screen, no render pass. On an Apple GPU *any* render
        // pass — an empty clear into a 64×64 texture will do — brings a
        // driver pool into the process: ~230 MB on an M4 Max, 23 purgeable
        // 8 MB regions, given back a few seconds after the last pass. It
        // is not ours to shrink, only to not ask for, and it was being
        // asked for where nothing could be seen: a headless attach, the
        // incoming pane of every switch (it parses behind the outgoing
        // one before it is mounted), a pane in a window that is ordered
        // out (measured 2026-11-13, docs/EVIDENCE.md "the pool a render
        // pass brings"). Snapshots do not come through here; they make
        // their own pass, and pay for it, when someone asks to look.
        guard isOnScreen(window) else {
            owesDraw = true
            return
        }
        let size = drawableSize()
        guard size.width >= 1, size.height >= 1 else { return }
        if metalLayer.drawableSize != size { metalLayer.drawableSize = size }
        // One drawable per pass, and never a stall: if the pool is empty the
        // frame is dropped and the next call draws the same state.
        guard let drawable = metalLayer.nextDrawable() else { return }
        // The renderer declines a clean frame because the last one is on
        // screen. For a frame that was skipped above it is not.
        if owesDraw { frame.dirty = .full }
        // Counted only when the renderer actually encoded and presented:
        // it declines a clean frame, a starved instance pool, a failed
        // buffer, and none of those reached the screen. This number is
        // the black-pane oracle (CLAUDE.md), and until 2026-09-04 it
        // counted *calls* — a window dragged by a pixel "presented"
        // hundreds of frames it never drew.
        let encoded = renderer.encodedFrames
        renderer.draw(frame: frame, into: drawable, size: size, metrics: metrics)
        if renderer.encodedFrames > encoded {
            presentedFrames += 1
            lastPresentedAt = Date()
            owesDraw = false
        }
    }

    /// "Is there a screen this would reach": in a window, and the window
    /// ordered in. Deliberately `isVisible` and not the occlusion state —
    /// a window covered by another keeps drawing, so `ccc capture` of it
    /// is never stale. A property so a test can stand in for a window
    /// server that will not order a window in.
    var isOnScreen: (NSWindow?) -> Bool = { $0?.isVisible == true }

    private var visibility: NSKeyValueObservation?

    /// Mounted, or the window it is in was ordered in: show what arrived
    /// while there was nowhere to show it.
    ///
    /// The trigger is the predicate's own property, observed. v0.1.44
    /// listened for the occlusion notification instead, and the two are
    /// different questions: `ccc window show` from a shell orders the
    /// window in *behind* the frontmost app, so it became visible to
    /// AppKit and stayed occluded — no notification, no draw, and `ccc
    /// stats` called a pane nobody could see black until something
    /// uncovered it (docs/EVIDENCE.md "ordered in is not uncovered").
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        visibility = window?.observe(\.isVisible, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.screenMayHaveChanged() }
        }
        screenMayHaveChanged()
    }

    /// Something that decides `isOnScreen` moved; draw if a draw is owed.
    func screenMayHaveChanged() {
        drawCurrentFrame()
    }

    /// Whether the layer has a screen to present to — what makes "0
    /// frames presented" mean a black pane rather than a hidden one.
    public var hasScreen: Bool { isOnScreen(window) }

    // MARK: - Geometry

    public func gridSize() -> (cols: Int, rows: Int) {
        metrics.gridSize(for: bounds.size)
    }

    private func drawableSize() -> CGSize {
        let scale = metalLayer.contentsScale
        return CGSize(
            width: (bounds.width * scale).rounded(),
            height: (bounds.height * scale).rounded()
        )
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        metalLayer.drawableSize = drawableSize()
        reportGridIfChanged()
        drawCurrentFrame()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? metrics.scale
        metalLayer.contentsScale = scale
        if metrics.scale != scale {
            // Re-derive the cell box for the new screen; the atlas rebuilds
            // itself when the renderer notices the scale changed.
            metrics = CellMetrics(font: metrics.font, scale: scale)
        } else {
            metalLayer.drawableSize = drawableSize()
            reportGridIfChanged()
        }
        drawCurrentFrame()
    }

    private func reportGridIfChanged() {
        let grid = gridSize()
        guard lastReportedGrid == nil || lastReportedGrid! != grid else { return }
        lastReportedGrid = grid
        onResize?(grid)
    }

    // MARK: - Snapshot

    /// Render the current frame into an offscreen texture and read it back.
    ///
    /// This is the Metal answer to `cacheDisplay(in:to:)`, which cannot see a
    /// `CAMetalLayer`'s contents at all — so it is how `ccc peek` gets pixels
    /// out of a Metal pane, and how a screenshot test judges feel while the
    /// text grid judges correctness.
    public func snapshotImage() -> CGImage? {
        guard let renderer, let frame = frameToDraw else { return nil }
        let size = drawableSize()
        let width = Int(size.width), height = Int(size.height)
        guard width >= 1, height >= 1,
              let texture = renderer.makeOffscreenTexture(width: width, height: height)
        else { return nil }
        renderer.render(frame: frame, to: texture, metrics: metrics, force: true)
        return MetalPaneView.image(from: renderer.readPixels(from: texture), width: width, height: height)
    }

    /// BGRA8 bytes → CGImage.
    static func image(from bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        let bytesPerRow = width * 4
        guard bytes.count >= bytesPerRow * height,
              let provider = CGDataProvider(data: Data(bytes) as CFData)
        else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}
