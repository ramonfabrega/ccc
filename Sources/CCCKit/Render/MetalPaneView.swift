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
            needsDisplay = true
        }
    }

    public private(set) var renderer: MetalRenderer?

    private let metalLayer = CAMetalLayer()
    private var frameToDraw: Frame?
    private var lastReportedGrid: (cols: Int, rows: Int)?

    public init(frame frameRect: NSRect, metrics: CellMetrics = CellMetrics()) {
        self.metrics = metrics
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize

        renderer = MetalRenderer()
        metalLayer.device = renderer?.device ?? MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
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
        layer = metalLayer
        // Seeded so the first `setFrameSize` inside the same cell does not
        // report a "change"; the owner bootstraps with `gridSize()`.
        lastReportedGrid = metrics.gridSize(for: frameRect.size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("MetalPaneView is created in code") }

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public override var wantsUpdateLayer: Bool { true }

    // MARK: - Frames

    /// Hand the view the frame to show. Cheap: it stores and invalidates, and
    /// the actual encode happens in `updateLayer` on the next display pass, so
    /// a burst of output that produces ten frames before the next vsync costs
    /// one draw, not ten.
    public func render(_ frame: Frame) {
        frameToDraw = frame
        needsDisplay = true
    }

    public override func updateLayer() {
        drawCurrentFrame()
    }

    public override func draw(_ dirtyRect: NSRect) {
        drawCurrentFrame()
    }

    private func drawCurrentFrame() {
        guard let renderer, let frame = frameToDraw else { return }
        let size = drawableSize()
        guard size.width >= 1, size.height >= 1 else { return }
        if metalLayer.drawableSize != size { metalLayer.drawableSize = size }
        // One drawable per pass, and never a stall: if the pool is empty the
        // frame is dropped and the next display pass draws the same state.
        guard let drawable = metalLayer.nextDrawable() else { return }
        renderer.draw(frame: frame, into: drawable, size: size, metrics: metrics)
    }

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
        needsDisplay = true
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
        needsDisplay = true
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
