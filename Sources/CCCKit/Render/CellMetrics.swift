import AppKit
import CoreText

/// The grid geometry every other part of the renderer measures against.
///
/// Everything here is snapped to whole **device pixels** before it leaves the
/// initializer. That is the whole point of the type: Zed's renderer postmortem
/// (docs/TERMINAL.md) names unsnapped cell metrics as the source of the two
/// worst-looking bugs in a cell grid — 1px seams between background quads that
/// flicker as the window resizes, and text that shifts a fraction of a pixel
/// per row. If the cell box is an integral number of device pixels and the
/// baseline sits on a device-pixel line, neither can happen.
///
/// Values are in **points** unless the name says `Pixels`. `scale` converts:
/// `pixels = points * scale`.
@MainActor
public struct CellMetrics {
    /// System monospaced 13pt — the same face the harness's own TUI assumes.
    public static var defaultFont: NSFont { .monospacedSystemFont(ofSize: 13, weight: .regular) }

    public let font: NSFont
    /// Backing scale factor of the screen this grid is drawn on (1 or 2).
    public let scale: CGFloat

    /// Cell box, snapped so `width * scale` and `height * scale` are integers.
    public let width: CGFloat
    public let height: CGFloat
    /// Distance from the top of the cell box down to the text baseline.
    public let baseline: CGFloat

    public let ascent: CGFloat
    public let descent: CGFloat
    public let leading: CGFloat

    /// Distance *below* the baseline (positive) at which an underline is drawn.
    public let underlinePosition: CGFloat
    public let underlineThickness: CGFloat
    /// Distance *above* the baseline (positive) of the strikethrough line.
    public let strikethroughPosition: CGFloat
    /// Distance above the baseline of an overline (the top of the cell box).
    public let overlinePosition: CGFloat

    public var cellSize: CGSize { CGSize(width: width, height: height) }
    public var widthPixels: CGFloat { (width * scale).rounded() }
    public var heightPixels: CGFloat { (height * scale).rounded() }
    public var baselinePixels: CGFloat { (baseline * scale).rounded() }
    /// One device pixel expressed in points — the thinnest line we ever draw.
    public var hairline: CGFloat { 1 / scale }

    public var ctFont: CTFont { font as CTFont }

    public init(font: NSFont = CellMetrics.defaultFont, scale: CGFloat = 2) {
        let scale = max(1, scale)
        self.font = font
        self.scale = scale

        let ct = font as CTFont
        let ascent = CTFontGetAscent(ct)
        let descent = CTFontGetDescent(ct)
        let leading = CTFontGetLeading(ct)
        self.ascent = ascent
        self.descent = descent
        self.leading = leading

        // Cell width: the widest of the two glyphs every monospaced face agrees
        // on. `ceil` rather than `round` so a glyph is never clipped by its own
        // cell; the error is at most one device pixel of tracking.
        let advance = CellMetrics.advance(of: ["M", "0"], in: ct)
        self.width = max(1 / scale, (advance * scale).rounded(.up) / scale)

        let lineHeight = ascent + descent + leading
        self.height = max(2 / scale, (lineHeight * scale).rounded(.up) / scale)

        // Baseline sits a whole number of pixels above the cell bottom, so the
        // descender box is exact and rows never drift relative to each other.
        let descentSnapped = (descent * scale).rounded(.up) / scale
        self.baseline = self.height - descentSnapped

        let rawUnderline = -CTFontGetUnderlinePosition(ct)   // CT reports it negative (below baseline)
        self.underlinePosition = max(1 / scale, (rawUnderline * scale).rounded() / scale)
        self.underlineThickness = max(1 / scale, (CTFontGetUnderlineThickness(ct) * scale).rounded() / scale)

        let xHeight = CTFontGetXHeight(ct)
        self.strikethroughPosition = max(1 / scale, ((xHeight * 0.5) * scale).rounded() / scale)
        self.overlinePosition = self.baseline
    }

    /// Top-left corner of a cell, in points, in a top-left-origin coordinate
    /// space (the space the Metal renderer works in).
    public func origin(col: Int, row: Int) -> CGPoint {
        CGPoint(x: CGFloat(col) * width, y: CGFloat(row) * height)
    }

    /// Grid that fits in `size` points. Partial cells are dropped, never
    /// rounded up: a half-visible last row is worse than a 3pt margin.
    public func gridSize(for size: CGSize) -> (cols: Int, rows: Int) {
        let cols = max(1, Int((size.width / width).rounded(.down)))
        let rows = max(1, Int((size.height / height).rounded(.down)))
        return (cols, rows)
    }

    private static func advance(of samples: [Character], in font: CTFont) -> CGFloat {
        var best: CGFloat = 0
        for sample in samples {
            var chars = Array(String(sample).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: chars.count)
            guard CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count) else { continue }
            var advances = [CGSize](repeating: .zero, count: glyphs.count)
            CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, &advances, glyphs.count)
            best = max(best, advances.reduce(0) { $0 + $1.width })
        }
        // A face with no "M" at all (never in practice) still gets a sane box.
        return best > 0 ? best : CTFontGetSize(font) * 0.6
    }
}
