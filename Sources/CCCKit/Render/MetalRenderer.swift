import CoreGraphics
import CoreText
import Foundation
import Metal
import QuartzCore
import os

/// The cell-grid renderer: a `Frame` in, quads on the GPU out.
///
/// Everything is an instanced unit quad. One pipeline draws solid rectangles
/// (backgrounds, underlines, cursor), one draws glyphs out of the A8 atlas
/// page tinted by a per-instance colour, and one draws glyphs out of the
/// colour page (emoji) which carry their own premultiplied pixels. A frame is
/// at most five draw calls no matter how much text is on screen, because
/// `RunMerge` has already collapsed the grid into spans and runs.
///
/// Order within a frame, which is also the order of the passes below:
/// clear → backgrounds → decorations → text → cursor. The cursor is last and
/// redraws its own cell's glyph in the background colour on top of the block,
/// which is how a block cursor inverts without a second render target.
@MainActor
public final class MetalRenderer {
    public let device: any MTLDevice
    /// Frames actually encoded. A frame skipped because nothing was dirty does
    /// not increment it — that is the "don't repaint when nothing changed"
    /// rule from docs/TERMINAL.md, and the test asserts on this counter.
    public private(set) var encodedFrames: Int = 0

    private let queue: any MTLCommandQueue
    private let solidPipeline: any MTLRenderPipelineState
    private let alphaGlyphPipeline: any MTLRenderPipelineState
    private let colorGlyphPipeline: any MTLRenderPipelineState

    private var glyphAtlas: GlyphAtlas?
    private var atlasFont: CTFont?
    private var atlasScale: CGFloat = 0

    /// Three sets of instance buffers so the CPU can build frame N+1 while the
    /// GPU still reads frame N. Buffers grow by reallocation and never shrink.
    private static let bufferCount = 3
    private var bufferIndex = 0
    private var solidBuffers = [(any MTLBuffer)?](repeating: nil, count: MetalRenderer.bufferCount)
    private var glyphBuffers = [(any MTLBuffer)?](repeating: nil, count: MetalRenderer.bufferCount)
    private let inFlight = DispatchSemaphore(value: MetalRenderer.bufferCount)

    private var hasRendered = false
    /// The colours the core was built with. The renderer needs its own copy
    /// because three of them never travel in a `Frame`: the core has no
    /// cursor-text or selection colours to hand us (`render.h` leaves
    /// "rendering policy for selected cells" to the caller), so this is
    /// where they live — the frame says *which* cells are selected (a range
    /// per row) and the theme says what that looks like. Everything else in
    /// a frame — default fg/bg, cursor, every resolved cell colour — already
    /// comes out of the same theme by way of the core, and is read from the
    /// frame, not from here.
    public var theme: Theme = .active

    private let log = Logger(subsystem: "app.cuanto.ccc", category: "MetalRenderer")

    // Instance layouts, matched field for field by the shader source below.
    private struct SolidInstance {
        var rect: SIMD4<Float>   // x, y, w, h in device pixels
        var color: SIMD4<Float>
    }

    private struct GlyphInstance {
        var rect: SIMD4<Float>
        var uv: SIMD4<Float>
        var color: SIMD4<Float>
    }

    private struct Batch {
        var solids: [SolidInstance] = []
        var alphaGlyphs: [GlyphInstance] = []
        var colorGlyphs: [GlyphInstance] = []
        var cursorSolids: [SolidInstance] = []
        var cursorAlphaGlyphs: [GlyphInstance] = []
        var cursorColorGlyphs: [GlyphInstance] = []
    }

    public init?(device: (any MTLDevice)? = nil) {
        guard let device = device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue

        do {
            let library = try device.makeLibrary(source: MetalRenderer.shaderSource, options: nil)
            solidPipeline = try MetalRenderer.pipeline(
                device: device, library: library,
                vertex: "ccc_solid_vertex", fragment: "ccc_solid_fragment",
                premultiplied: false
            )
            alphaGlyphPipeline = try MetalRenderer.pipeline(
                device: device, library: library,
                vertex: "ccc_glyph_vertex", fragment: "ccc_glyph_alpha_fragment",
                premultiplied: false
            )
            colorGlyphPipeline = try MetalRenderer.pipeline(
                device: device, library: library,
                vertex: "ccc_glyph_vertex", fragment: "ccc_glyph_color_fragment",
                premultiplied: true
            )
        } catch {
            Logger(subsystem: "app.cuanto.ccc", category: "MetalRenderer")
                .error("pipeline creation failed: \(String(describing: error))")
            return nil
        }
    }

    // MARK: - Public drawing

    /// Draw into a live drawable. Returns without encoding when the frame is
    /// clean, so an idle pane costs nothing.
    public func draw(
        frame: Frame, into drawable: any CAMetalDrawable, size: CGSize, metrics: CellMetrics
    ) {
        guard shouldDraw(frame) else { return }
        encode(frame: frame, target: drawable.texture, metrics: metrics, present: drawable, wait: false)
    }

    /// Draw into an offscreen texture. Used by `snapshotImage()` — and so by
    /// `ccc peek` — and by the tests, which is the only way a headless run can
    /// see what a Metal pane shows.
    public func render(
        frame: Frame, to texture: any MTLTexture, metrics: CellMetrics, force: Bool = true
    ) {
        guard force || shouldDraw(frame) else { return }
        encode(frame: frame, target: texture, metrics: metrics, present: nil, wait: true)
    }

    /// `nil` when nothing changed since the last encoded frame.
    private func shouldDraw(_ frame: Frame) -> Bool {
        if frame.dirty == .none && hasRendered { return false }
        return true
    }

    public func makeOffscreenTexture(width: Int, height: Int) -> (any MTLTexture)? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: max(1, width), height: max(1, height), mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "ccc.offscreen"
        return texture
    }

    /// BGRA8, row-major, `width * height * 4` bytes.
    public func readPixels(from texture: any MTLTexture) -> [UInt8] {
        let bytesPerRow = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.getBytes(
                base, bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return bytes
    }

    // MARK: - Encoding

    private func encode(
        frame: Frame, target: any MTLTexture, metrics: CellMetrics,
        present drawable: (any CAMetalDrawable)?, wait: Bool
    ) {
        // Never stall more than one frame's worth waiting for a buffer set.
        guard inFlight.wait(timeout: .now() + .milliseconds(17)) == .success else {
            log.debug("dropped a frame waiting for an instance buffer")
            return
        }
        var signalled = false
        defer { if !signalled { inFlight.signal() } }

        let batch = build(frame: frame, metrics: metrics)

        bufferIndex = (bufferIndex + 1) % Self.bufferCount
        let solidCount = batch.solids.count + batch.cursorSolids.count
        let glyphCount = batch.alphaGlyphs.count + batch.colorGlyphs.count
            + batch.cursorAlphaGlyphs.count + batch.cursorColorGlyphs.count

        let solidBuffer = buffer(
            &solidBuffers, index: bufferIndex,
            bytes: MemoryLayout<SolidInstance>.stride * max(1, solidCount), label: "ccc.solids"
        )
        let glyphBuffer = buffer(
            &glyphBuffers, index: bufferIndex,
            bytes: MemoryLayout<GlyphInstance>.stride * max(1, glyphCount), label: "ccc.glyphs"
        )
        guard let solidBuffer, let glyphBuffer else { return }

        // Offsets into the two shared buffers, one contiguous region per draw.
        let bgOffset = 0
        let cursorSolidOffset = batch.solids.count
        write(batch.solids, to: solidBuffer, at: bgOffset)
        write(batch.cursorSolids, to: solidBuffer, at: cursorSolidOffset)

        let alphaOffset = 0
        let colorOffset = alphaOffset + batch.alphaGlyphs.count
        let cursorAlphaOffset = colorOffset + batch.colorGlyphs.count
        let cursorColorOffset = cursorAlphaOffset + batch.cursorAlphaGlyphs.count
        write(batch.alphaGlyphs, to: glyphBuffer, at: alphaOffset)
        write(batch.colorGlyphs, to: glyphBuffer, at: colorOffset)
        write(batch.cursorAlphaGlyphs, to: glyphBuffer, at: cursorAlphaOffset)
        write(batch.cursorColorGlyphs, to: glyphBuffer, at: cursorColorOffset)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(frame.background.r) / 255,
            green: Double(frame.background.g) / 255,
            blue: Double(frame.background.b) / 255,
            alpha: 1
        )

        guard let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        commands.label = "ccc.frame"

        var viewport = SIMD2<Float>(Float(target.width), Float(target.height))

        func drawSolids(_ instances: [SolidInstance], offset: Int) {
            guard !instances.isEmpty else { return }
            encoder.setRenderPipelineState(solidPipeline)
            encoder.setVertexBuffer(solidBuffer, offset: MemoryLayout<SolidInstance>.stride * offset, index: 0)
            encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instances.count)
        }

        func drawGlyphs(_ instances: [GlyphInstance], offset: Int, page: GlyphAtlas.Page) {
            guard !instances.isEmpty else { return }
            let texture = page == .alpha ? glyphAtlas?.alphaTexture : glyphAtlas?.colorTexture
            guard let texture else { return }
            encoder.setRenderPipelineState(page == .alpha ? alphaGlyphPipeline : colorGlyphPipeline)
            encoder.setVertexBuffer(glyphBuffer, offset: MemoryLayout<GlyphInstance>.stride * offset, index: 0)
            encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instances.count)
        }

        drawSolids(batch.solids, offset: bgOffset)
        drawGlyphs(batch.alphaGlyphs, offset: alphaOffset, page: .alpha)
        drawGlyphs(batch.colorGlyphs, offset: colorOffset, page: .color)
        drawSolids(batch.cursorSolids, offset: cursorSolidOffset)
        drawGlyphs(batch.cursorAlphaGlyphs, offset: cursorAlphaOffset, page: .alpha)
        drawGlyphs(batch.cursorColorGlyphs, offset: cursorColorOffset, page: .color)

        encoder.endEncoding()
        if let drawable { commands.present(drawable) }

        let semaphore = inFlight
        commands.addCompletedHandler { _ in semaphore.signal() }
        signalled = true
        commands.commit()
        if wait { commands.waitUntilCompleted() }

        encodedFrames += 1
        hasRendered = true
    }

    private func buffer(
        _ pool: inout [(any MTLBuffer)?], index: Int, bytes: Int, label: String
    ) -> (any MTLBuffer)? {
        if let existing = pool[index], existing.length >= bytes { return existing }
        // Grow with headroom so a slowly filling screen does not reallocate
        // every frame.
        let made = device.makeBuffer(length: max(bytes * 2, 4096), options: .storageModeShared)
        made?.label = label
        pool[index] = made
        return made
    }

    private func write<T>(_ instances: [T], to buffer: any MTLBuffer, at offset: Int) {
        guard !instances.isEmpty else { return }
        let stride = MemoryLayout<T>.stride
        instances.withUnsafeBytes { source in
            guard let base = source.baseAddress else { return }
            buffer.contents().advanced(by: stride * offset).copyMemory(from: base, byteCount: source.count)
        }
    }

    // MARK: - Frame → instances

    private func build(frame: Frame, metrics: CellMetrics) -> Batch {
        let atlas = self.atlas(for: metrics)
        let foreground = frame.foreground
        var batch = Batch()

        let cellW = metrics.widthPixels
        let cellH = metrics.heightPixels
        let baseline = metrics.baselinePixels
        let scale = metrics.scale

        // The theme's, not the frame's: the core has no selection colour to
        // resolve into a cell (`GhosttyHost.install`), so the pair enters
        // here and in `ColorSpans` — the two places that turn a frame into
        // something visible — and nowhere else.
        let selection = theme.selection

        for row in frame.rows {
            let top = CGFloat(row.y) * cellH

            for span in RunMerge.backgroundSpans(row, background: frame.background, foreground: foreground, selection: selection) {
                batch.solids.append(SolidInstance(
                    rect: SIMD4<Float>(
                        Float(CGFloat(span.x) * cellW), Float(top),
                        Float(CGFloat(span.length) * cellW), Float(cellH)
                    ),
                    color: Self.color(span.color, alpha: 1)
                ))
            }

            for span in RunMerge.decorationSpans(row, background: frame.background, foreground: foreground, selection: selection) {
                appendDecoration(span, top: top, metrics: metrics, into: &batch.solids)
            }

            for run in RunMerge.textRuns(row, background: frame.background, foreground: foreground, selection: selection) {
                let color = Self.color(run.style.fg, alpha: run.style.faint ? 0.6 : 1)
                appendGlyphs(
                    run.text,
                    columnForUTF16: run.columnForUTF16,
                    bold: run.style.bold, italic: run.style.italic,
                    originX: CGFloat(run.x) * cellW, baselineY: top + baseline,
                    cellWidth: cellW, scale: scale, color: color, atlas: atlas,
                    alpha: &batch.alphaGlyphs, colorGlyphs: &batch.colorGlyphs
                )
            }
        }

        appendCursor(frame: frame, foreground: foreground, metrics: metrics, atlas: atlas, into: &batch)
        return batch
    }

    private func appendGlyphs(
        _ text: String, columnForUTF16: [Int], bold: Bool, italic: Bool,
        originX: CGFloat, baselineY: CGFloat, cellWidth: CGFloat, scale: CGFloat,
        color: SIMD4<Float>, atlas: GlyphAtlas,
        alpha: inout [GlyphInstance], colorGlyphs: inout [GlyphInstance]
    ) {
        for shaped in atlas.shape(text, bold: bold, italic: italic) {
            let column = shaped.stringIndex < columnForUTF16.count ? columnForUTF16[shaped.stringIndex] : 0
            // Cell origins are whole device pixels by construction (CellMetrics
            // rounds them), so only the intra-cluster offset can be fractional
            // and only it needs a subpixel variant.
            let penX = originX + CGFloat(column) * cellWidth + shaped.offset.x * scale
            let penY = (baselineY - shaped.offset.y * scale).rounded()
            let bucket = GlyphAtlas.subpixelBucket(forPixelX: penX)
            guard let entry = atlas.entry(for: shaped, subpixel: bucket) else { continue }
            let x = penX.rounded(.down) + entry.bearing.x
            let y = penY + entry.bearing.y
            let instance = GlyphInstance(
                rect: SIMD4<Float>(Float(x), Float(y), Float(entry.size.width), Float(entry.size.height)),
                uv: entry.uv,
                color: color
            )
            if entry.page == .alpha { alpha.append(instance) } else { colorGlyphs.append(instance) }
        }
    }

    private func appendDecoration(
        _ span: RunMerge.DecorationSpan, top: CGFloat, metrics: CellMetrics,
        into solids: inout [SolidInstance]
    ) {
        let cellW = metrics.widthPixels
        let x = CGFloat(span.x) * cellW
        let width = CGFloat(span.length) * cellW
        let thickness = max(1, (metrics.underlineThickness * metrics.scale).rounded())
        let color = Self.color(span.color, alpha: 1)

        func line(y: CGFloat, dash: (on: CGFloat, off: CGFloat)? = nil) {
            guard let dash else {
                solids.append(SolidInstance(
                    rect: SIMD4<Float>(Float(x), Float(y), Float(width), Float(thickness)), color: color))
                return
            }
            var cursor = x
            while cursor < x + width {
                let segment = min(dash.on, x + width - cursor)
                solids.append(SolidInstance(
                    rect: SIMD4<Float>(Float(cursor), Float(y), Float(segment), Float(thickness)), color: color))
                cursor += dash.on + dash.off
            }
        }

        let underlineY = top + metrics.baselinePixels
            + max(1, (metrics.underlinePosition * metrics.scale).rounded())
        switch span.underline {
        case .none: break
        case .single: line(y: underlineY)
        case .double:
            line(y: underlineY)
            line(y: underlineY + thickness * 2)
        // A curly underline needs a per-pixel wave; until the shader grows one,
        // it is drawn as a fine dotted line so it is still visibly *a* squiggle
        // marker and still distinguishable from a plain underline. Noted as a
        // known gap in the renderer's report.
        case .curly: line(y: underlineY, dash: (on: thickness, off: thickness))
        case .dotted: line(y: underlineY, dash: (on: thickness, off: thickness))
        case .dashed: line(y: underlineY, dash: (on: thickness * 3, off: thickness * 3))
        }

        if span.strikethrough {
            let y = (top + metrics.baselinePixels
                - (metrics.strikethroughPosition * metrics.scale).rounded()).rounded()
            line(y: y)
        }
        if span.overline {
            line(y: top)
        }
    }

    private func appendCursor(
        frame: Frame, foreground: Frame.RGB, metrics: CellMetrics,
        atlas: GlyphAtlas, into batch: inout Batch
    ) {
        guard let cursor = frame.cursor, cursor.visible else { return }
        guard cursor.y >= 0, cursor.y < frame.rows.count else { return }
        let row = frame.rows[cursor.y]
        guard cursor.x >= 0, cursor.x < row.cells.count else { return }
        let cell = row.cells[cursor.x]

        let cellW = metrics.widthPixels
        let cellH = metrics.heightPixels
        let x = CGFloat(cursor.x) * cellW
        let top = CGFloat(cursor.y) * cellH
        // A cursor over a wide glyph covers the glyph, never half of it.
        let width = (cursor.wideTail || cell.wide == .wide) ? cellW * 2 : cellW

        let cursorColor = cursor.color ?? foreground
        let solid = Self.color(cursorColor, alpha: 1)
        let hairline = max(1, metrics.scale)

        // Blink is deliberately ignored: the frame carries `blinking`, and a
        // steady cursor is drawn instead. A blink timer belongs to the view's
        // display link, not to a stateless renderer, and a terminal that never
        // blinks is a defensible default.
        switch cursor.style {
        case .block:
            batch.cursorSolids.append(SolidInstance(
                rect: SIMD4<Float>(Float(x), Float(top), Float(width), Float(cellH)), color: solid))
            // The cell's own glyph, redrawn on top in the theme's cursor-text
            // colour. This used to be the cell's background — an inversion,
            // which is what you do when you have no cursor-text colour to
            // reach for. A theme has one, and iTerm draws that one flat
            // rather than inverting, so a cursor over coloured text looks the
            // same wherever it lands.
            let textColor = Self.color(theme.cursorText, alpha: 1)
            if !cell.text.isEmpty, !cell.flags.contains(.invisible) {
                appendGlyphs(
                    cell.text, columnForUTF16: Array(repeating: 0, count: cell.text.utf16.count),
                    bold: cell.flags.contains(.bold), italic: cell.flags.contains(.italic),
                    originX: x, baselineY: top + metrics.baselinePixels,
                    cellWidth: cellW, scale: metrics.scale, color: textColor, atlas: atlas,
                    alpha: &batch.cursorAlphaGlyphs, colorGlyphs: &batch.cursorColorGlyphs
                )
            }
        case .blockHollow:
            let edges: [SIMD4<Float>] = [
                SIMD4(Float(x), Float(top), Float(width), Float(hairline)),
                SIMD4(Float(x), Float(top + cellH - hairline), Float(width), Float(hairline)),
                SIMD4(Float(x), Float(top), Float(hairline), Float(cellH)),
                SIMD4(Float(x + width - hairline), Float(top), Float(hairline), Float(cellH)),
            ]
            for edge in edges { batch.cursorSolids.append(SolidInstance(rect: edge, color: solid)) }
        case .bar:
            batch.cursorSolids.append(SolidInstance(
                rect: SIMD4<Float>(Float(x), Float(top), Float(max(2, hairline)), Float(cellH)), color: solid))
        case .underline:
            let thickness = max(2, hairline)
            batch.cursorSolids.append(SolidInstance(
                rect: SIMD4<Float>(Float(x), Float(top + cellH - thickness), Float(width), Float(thickness)),
                color: solid))
        }
    }

    private func atlas(for metrics: CellMetrics) -> GlyphAtlas {
        if let existing = glyphAtlas, let font = atlasFont,
           CFEqual(font, metrics.ctFont), atlasScale == metrics.scale {
            return existing
        }
        let made = GlyphAtlas(device: device, metrics: metrics)
        glyphAtlas = made
        atlasFont = metrics.ctFont
        atlasScale = metrics.scale
        return made
    }

    private static func color(_ rgb: Frame.RGB, alpha: Float) -> SIMD4<Float> {
        SIMD4<Float>(Float(rgb.r) / 255, Float(rgb.g) / 255, Float(rgb.b) / 255, alpha)
    }

    private static func pipeline(
        device: any MTLDevice, library: any MTLLibrary,
        vertex: String, fragment: String, premultiplied: Bool
    ) throws -> any MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: vertex)
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = .bgra8Unorm
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = premultiplied ? .one : .sourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Compiled at runtime rather than shipped as a `.metal` resource: it keeps
    /// the shader next to the Swift that feeds it, and SwiftPM does not have to
    /// learn about the Metal toolchain for `swift test` to work headless.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    constant float2 kCorners[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(0, 1), float2(1, 0), float2(1, 1)
    };

    struct SolidInstance { float4 rect; float4 color; };
    struct GlyphInstance { float4 rect; float4 uv; float4 color; };

    struct VertexOut {
        float4 position [[position]];
        float4 color;
        float2 uv;
    };

    static inline float4 to_clip(float2 pixel, float2 viewport) {
        return float4(pixel.x / viewport.x * 2.0 - 1.0,
                      1.0 - pixel.y / viewport.y * 2.0,
                      0.0, 1.0);
    }

    vertex VertexOut ccc_solid_vertex(uint vid [[vertex_id]],
                                      uint iid [[instance_id]],
                                      const device SolidInstance *instances [[buffer(0)]],
                                      constant float2 &viewport [[buffer(1)]]) {
        SolidInstance inst = instances[iid];
        float2 corner = kCorners[vid];
        float2 pixel = inst.rect.xy + corner * inst.rect.zw;
        VertexOut out;
        out.position = to_clip(pixel, viewport);
        out.color = inst.color;
        out.uv = float2(0.0);
        return out;
    }

    fragment float4 ccc_solid_fragment(VertexOut in [[stage_in]]) {
        return in.color;
    }

    vertex VertexOut ccc_glyph_vertex(uint vid [[vertex_id]],
                                      uint iid [[instance_id]],
                                      const device GlyphInstance *instances [[buffer(0)]],
                                      constant float2 &viewport [[buffer(1)]]) {
        GlyphInstance inst = instances[iid];
        float2 corner = kCorners[vid];
        float2 pixel = inst.rect.xy + corner * inst.rect.zw;
        VertexOut out;
        out.position = to_clip(pixel, viewport);
        out.color = inst.color;
        out.uv = mix(inst.uv.xy, inst.uv.zw, corner);
        return out;
    }

    fragment float4 ccc_glyph_alpha_fragment(VertexOut in [[stage_in]],
                                             texture2d<float> atlas [[texture(0)]]) {
        constexpr sampler nearest(filter::nearest, address::clamp_to_edge);
        float mask = atlas.sample(nearest, in.uv).a;
        return float4(in.color.rgb, in.color.a * mask);
    }

    fragment float4 ccc_glyph_color_fragment(VertexOut in [[stage_in]],
                                             texture2d<float> atlas [[texture(0)]]) {
        constexpr sampler nearest(filter::nearest, address::clamp_to_edge);
        float4 texel = atlas.sample(nearest, in.uv);
        return texel * in.color.a;
    }
    """
}
