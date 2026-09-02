import AppKit
import CoreGraphics
import CoreText
import Metal
import os

/// One glyph as CoreText resolved it: which face actually owns it (fallback
/// included), its id in that face, where it sits inside the run's text, and
/// how far it is offset from the base glyph of its cluster.
struct ShapedGlyph {
    /// The face CoreText chose — the primary font for Latin, a fallback for
    /// CJK, Apple Color Emoji for emoji. This is part of the atlas key.
    var font: CTFont
    var glyph: CGGlyph
    /// UTF-16 offset into the run's text; the run's `columnForUTF16` turns
    /// this into a grid column.
    var stringIndex: Int
    /// Offset from the *cluster's* origin, in points. Zero for the base glyph
    /// of a cluster, which is the common case; non-zero for combining marks,
    /// so a zero-width mark lands on its base instead of a cell of its own.
    var offset: CGPoint
}

/// CoreText rasterizer + Metal texture atlas.
///
/// Two pages, following the split docs/TERMINAL.md describes: an `.a8Unorm`
/// alpha mask for ordinary monochrome glyphs (tinted at draw time, so one
/// raster serves every colour) and a `.bgra8Unorm` page for colour glyphs
/// (emoji), which carry their own pixels. Four subpixel-x variants per glyph
/// keep intra-cluster positioning from snapping to whole pixels.
///
/// Packing is a shelf packer: fill a row left to right, start a new row when
/// the glyph does not fit, give up when the page is full. Giving up is loud
/// (a logged warning, once) and degrades to "that glyph is not drawn" rather
/// than to a crash or a corrupt page.
@MainActor
final class GlyphAtlas {
    /// 2048² of A8 is 4 MB and holds several thousand glyphs at 13pt — far
    /// more than a terminal ever shows. The colour page is 1024² (4 MB of
    /// BGRA) and is only allocated once a colour glyph actually appears, so
    /// the common attached pane pays 4 MB, not 8. Both matter against the
    /// < 40 MB bar in docs/CHECKS.md.
    static let alphaPageSize = 2048
    static let colorPageSize = 1024
    /// A single glyph larger than this is refused; at 13pt nothing is close.
    static let maxGlyphPixels = 256

    enum Page: Sendable { case alpha, color }

    /// Where a rasterized glyph lives and how to place it.
    ///
    /// `bearing` and `size` are in **device pixels** relative to the pen
    /// position (baseline, at the glyph's origin), y growing downward — the
    /// renderer's own space, so placement is integer arithmetic with no
    /// rounding left to do.
    struct Entry {
        var page: Page
        /// Texel rect in the page.
        var rect: CGRect
        /// Normalized uv (u0, v0, u1, v1).
        var uv: SIMD4<Float>
        /// Offset from the pen to the quad's top-left, device pixels, y down.
        var bearing: CGPoint
        /// Quad size in device pixels.
        var size: CGSize
    }

    private struct GlyphKey: Hashable {
        var fontID: Int
        var glyph: UInt16
        var subpixel: UInt8
    }

    private struct ShapeKey: Hashable {
        var text: String
        var bold: Bool
        var italic: Bool
    }

    private struct Shelf {
        var y: Int
        var height: Int
        var x: Int
    }

    private let device: any MTLDevice
    private let scale: CGFloat
    private let baseFont: CTFont
    /// Resolved by `CellMetrics`, which knows how to reach SF Mono Bold; equal
    /// to `baseFont` when the family has no bold face at all.
    private let boldBaseFont: CTFont

    private(set) var alphaTexture: (any MTLTexture)?
    private(set) var colorTexture: (any MTLTexture)?

    private var entries: [GlyphKey: Entry] = [:]
    private var shapeCache: [ShapeKey: [ShapedGlyph]] = [:]
    private var styledFonts: [ShapeKey: CTFont] = [:]

    private var alphaShelves: [Shelf] = []
    private var colorShelves: [Shelf] = []
    private var alphaFull = false
    private var colorFull = false

    /// CTFont has no stable identity we can hash directly, so faces are
    /// registered in order of first use and compared with `CFEqual`.
    private var fontRegistry: [CTFont] = []

    private let log = Logger(subsystem: "app.cuanto.ccc", category: "GlyphAtlas")

    init(device: any MTLDevice, font: CTFont, boldFont: CTFont? = nil, scale: CGFloat) {
        self.device = device
        self.baseFont = font
        self.boldBaseFont = boldFont ?? (CellMetrics.boldCounterpart(of: font as NSFont) as CTFont)
        self.scale = max(1, scale)
    }

    convenience init(device: any MTLDevice, metrics: CellMetrics) {
        self.init(device: device, font: metrics.ctFont, boldFont: metrics.boldCTFont, scale: metrics.scale)
    }

    /// Number of distinct rasterizations currently held. Used by tests and by
    /// `ccc stats` to see the atlas fill.
    var glyphCount: Int { entries.count }

    // MARK: - Shaping

    /// Shape a merged run's text with CoreText, once.
    ///
    /// Shaping the whole run at once (rather than a glyph per cell) is what
    /// buys font fallback for free: `CTLineCreateWithAttributedString` picks
    /// a face per sub-run, and `CTLineGetGlyphRuns` hands each sub-run back
    /// with the face it chose. Results are cached by (text, bold, italic) —
    /// a terminal redraws the same words constantly.
    func shape(_ text: String, bold: Bool = false, italic: Bool = false) -> [ShapedGlyph] {
        let key = ShapeKey(text: text, bold: bold, italic: italic)
        if let cached = shapeCache[key] { return cached }

        let font = styledFont(bold: bold, italic: italic)
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            // Ligatures off: a cell grid wants one glyph per cell, and "!=" as
            // a single glyph would land in the wrong column.
            .ligature: 0,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return [] }

        var out: [ShapedGlyph] = []
        // Cluster origins: the first glyph seen for a UTF-16 index defines the
        // origin every other glyph of that cluster is measured against.
        var clusterOrigin: [Int: CGPoint] = [:]

        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            let attrs = CTRunGetAttributes(run) as NSDictionary
            // swiftlint:disable:next force_cast
            let runFont = (attrs[kCTFontAttributeName as String] as! CTFont)

            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRangeMake(0, count), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, count), &positions)
            CTRunGetStringIndices(run, CFRangeMake(0, count), &indices)

            for i in 0..<count {
                let index = Int(indices[i])
                let origin: CGPoint
                if let known = clusterOrigin[index] {
                    origin = known
                } else {
                    clusterOrigin[index] = positions[i]
                    origin = positions[i]
                }
                out.append(ShapedGlyph(
                    font: runFont,
                    glyph: glyphs[i],
                    stringIndex: index,
                    offset: CGPoint(x: positions[i].x - origin.x, y: positions[i].y - origin.y)
                ))
            }
        }

        if shapeCache.count > 4096 { shapeCache.removeAll(keepingCapacity: true) }
        shapeCache[key] = out
        return out
    }

    /// The face to shape a run in.
    ///
    /// Bold starts from `boldBaseFont` (a real bold face, resolved by
    /// `CellMetrics`) rather than from a symbolic-trait copy of the regular
    /// one, and every branch ends at a face that exists: a style we cannot
    /// synthesize degrades to the nearest face we have, never to nothing.
    /// Synthetic obliquing is not attempted — if the family has no italic,
    /// text stays upright, which is what every terminal does.
    func styledFont(bold: Bool, italic: Bool) -> CTFont {
        guard bold || italic else { return baseFont }
        let key = ShapeKey(text: "", bold: bold, italic: italic)
        if let cached = styledFonts[key] { return cached }

        let base = bold ? boldBaseFont : baseFont
        var font = base
        if italic,
           let oblique = CTFontCreateCopyWithSymbolicTraits(base, 0, nil, .traitItalic, .traitItalic) {
            font = oblique
        }
        styledFonts[key] = font
        return font
    }

    // MARK: - Rasterizing

    /// Atlas entry for one shaped glyph at one of the four subpixel-x buckets.
    /// Returns nil for glyphs with no ink (spaces) and for glyphs the atlas
    /// refused.
    func entry(for glyph: ShapedGlyph, subpixel: Int) -> Entry? {
        let bucket = UInt8(min(3, max(0, subpixel)))
        let key = GlyphKey(fontID: fontID(glyph.font), glyph: glyph.glyph, subpixel: bucket)
        if let hit = entries[key] { return hit }
        guard let made = rasterize(font: glyph.font, glyph: glyph.glyph, subpixel: bucket) else {
            return nil
        }
        entries[key] = made
        return made
    }

    /// Which of the four x-buckets a device-pixel position falls into.
    static func subpixelBucket(forPixelX x: CGFloat) -> Int {
        let frac = x - x.rounded(.down)
        return min(3, max(0, Int(frac * 4)))
    }

    private func isColorFont(_ font: CTFont) -> Bool {
        CTFontGetSymbolicTraits(font).contains(.traitColorGlyphs)
    }

    private func rasterize(font: CTFont, glyph: CGGlyph, subpixel: UInt8) -> Entry? {
        var glyphs = [glyph]
        var bounds = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyphs, &bounds, 1)
        guard !bounds.isNull, !bounds.isInfinite, bounds.width > 0, bounds.height > 0 else { return nil }

        let subPixels = CGFloat(subpixel) / 4
        // The bitmap covers the glyph's ink box in device pixels, padded by one
        // pixel on every side so antialiasing is never clipped at the edge.
        let x0 = (bounds.minX * scale + subPixels).rounded(.down) - 1
        let x1 = (bounds.maxX * scale + subPixels).rounded(.up) + 1
        let y0 = (bounds.minY * scale).rounded(.down) - 1
        let y1 = (bounds.maxY * scale).rounded(.up) + 1
        let width = Int(x1 - x0)
        let height = Int(y1 - y0)
        guard width > 0, height > 0 else { return nil }
        guard width <= Self.maxGlyphPixels, height <= Self.maxGlyphPixels else {
            log.warning("glyph \(glyph) is \(width)x\(height)px, larger than the atlas allows; not drawn")
            return nil
        }

        let color = isColorFont(font)
        guard let context = makeContext(width: width, height: height, color: color) else { return nil }

        context.scaleBy(x: scale, y: scale)
        var position = CGPoint(x: (-x0 + subPixels) / scale, y: -y0 / scale)
        if color {
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        } else {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
        }
        CTFontDrawGlyphs(font, &glyphs, &position, 1, context)

        guard let data = context.data else { return nil }
        let bytesPerRow = context.bytesPerRow
        guard let rect = pack(width: width, height: height, page: color ? .color : .alpha) else {
            return nil
        }
        guard let texture = color ? colorTexture : alphaTexture else { return nil }
        texture.replace(
            region: MTLRegionMake2D(Int(rect.minX), Int(rect.minY), width, height),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: bytesPerRow
        )

        let pageSize = CGFloat(color ? Self.colorPageSize : Self.alphaPageSize)
        return Entry(
            page: color ? .color : .alpha,
            rect: rect,
            uv: SIMD4<Float>(
                Float(rect.minX / pageSize), Float(rect.minY / pageSize),
                Float(rect.maxX / pageSize), Float(rect.maxY / pageSize)
            ),
            // y flips: the bitmap's top edge is `y1` above the baseline, and the
            // renderer's y grows downward.
            bearing: CGPoint(x: x0, y: -y1),
            size: CGSize(width: width, height: height)
        )
    }

    private func makeContext(width: Int, height: Int, color: Bool) -> CGContext? {
        if color {
            guard let context = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return nil }
            context.setAllowsAntialiasing(true)
            context.setShouldSmoothFonts(false)
            return context
        }
        // One byte per pixel: a grayscale page with no alpha channel, cleared
        // to black, with the glyph drawn in white. The resulting byte *is* the
        // coverage, so it uploads unchanged into the A8 atlas page. (A true
        // `alphaOnly` context would be the obvious choice, but CoreGraphics
        // will not build one through the Swift initializer, which requires a
        // non-nil colour space.)
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        // Subpixel *positioning* is ours (the four buckets); subpixel
        // *rendering* (RGB fringing) is not, and would need an RGB page.
        context.setShouldSubpixelPositionFonts(false)
        context.setShouldSubpixelQuantizeFonts(false)
        context.setShouldSmoothFonts(false)
        return context
    }

    // MARK: - Packing

    private func pack(width: Int, height: Int, page: Page) -> CGRect? {
        let size = page == .alpha ? Self.alphaPageSize : Self.colorPageSize
        guard ensureTexture(page: page, size: size) else { return nil }

        var shelves = page == .alpha ? alphaShelves : colorShelves
        defer {
            if page == .alpha { alphaShelves = shelves } else { colorShelves = shelves }
        }

        for i in shelves.indices where shelves[i].height >= height && shelves[i].x + width <= size {
            let rect = CGRect(x: shelves[i].x, y: shelves[i].y, width: width, height: height)
            shelves[i].x += width
            return rect
        }
        let nextY = (shelves.last.map { $0.y + $0.height }) ?? 0
        guard nextY + height <= size else {
            let full = page == .alpha ? alphaFull : colorFull
            if !full {
                log.warning("glyph atlas page \(String(describing: page)) is full at \(size)x\(size); further glyphs are not drawn")
                if page == .alpha { alphaFull = true } else { colorFull = true }
            }
            return nil
        }
        shelves.append(Shelf(y: nextY, height: height, x: width))
        return CGRect(x: 0, y: nextY, width: width, height: height)
    }

    private func ensureTexture(page: Page, size: Int) -> Bool {
        switch page {
        case .alpha:
            if alphaTexture != nil { return true }
            alphaTexture = makeTexture(format: .a8Unorm, size: size, label: "ccc.atlas.alpha")
            return alphaTexture != nil
        case .color:
            if colorTexture != nil { return true }
            colorTexture = makeTexture(format: .bgra8Unorm, size: size, label: "ccc.atlas.color")
            return colorTexture != nil
        }
    }

    private func makeTexture(format: MTLPixelFormat, size: Int, label: String) -> (any MTLTexture)? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: size, height: size, mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }

    private func fontID(_ font: CTFont) -> Int {
        for (i, known) in fontRegistry.enumerated() where CFEqual(known, font) { return i }
        fontRegistry.append(font)
        return fontRegistry.count - 1
    }
}
