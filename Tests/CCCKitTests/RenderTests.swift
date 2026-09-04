import AppKit
import CoreText
import Foundation
import Metal
import Testing

@testable import CCCKit

/// Evaluated once, off the main actor, so it can gate `@Test(.enabled(if:))`.
private let hasMetalDevice = MTLCreateSystemDefaultDevice() != nil

@Suite @MainActor
struct RenderTests {
    // MARK: - Helpers

    private static let black = Frame.RGB(0, 0, 0)
    private static let white = Frame.RGB(255, 255, 255)
    private static let red = Frame.RGB(255, 0, 0)

    private func cell(
        _ text: String,
        fg: Frame.RGB? = nil, bg: Frame.RGB? = nil,
        flags: Frame.Cell.Flags = [], wide: Frame.Cell.Wide = .narrow,
        underline: Frame.Cell.Underline = .none
    ) -> Frame.Cell {
        Frame.Cell(text: text, wide: wide, fg: fg, bg: bg, flags: flags,
                   underline: underline, underlineColor: nil)
    }

    private func row(_ y: Int, _ cells: [Frame.Cell], cols: Int) -> Frame.Row {
        var padded = cells
        while padded.count < cols { padded.append(.blank) }
        return Frame.Row(y: y, dirty: true, cells: padded, selection: nil)
    }

    /// (b, g, r, a) at a device pixel of a BGRA8 readback.
    private func pixel(_ bytes: [UInt8], width: Int, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }

    private func rgb(_ p: (UInt8, UInt8, UInt8, UInt8)) -> Frame.RGB {
        Frame.RGB(p.2, p.1, p.0)
    }

    // MARK: - a. Cell metrics

    @Test func metricsAreWholeDevicePixels() {
        let metrics = CellMetrics(scale: 2)
        #expect(metrics.width > 0)
        #expect(metrics.height > metrics.width, "a 13pt monospaced cell is taller than it is wide")

        let widthPixels = metrics.width * metrics.scale
        let heightPixels = metrics.height * metrics.scale
        #expect(widthPixels == widthPixels.rounded(), "cell width must land on a device pixel")
        #expect(heightPixels == heightPixels.rounded(), "cell height must land on a device pixel")

        // The baseline is what glyph placement is measured from; if it is not
        // pixel-aligned every row of text jitters against every other.
        let baselinePixels = metrics.baseline * metrics.scale
        #expect(baselinePixels == baselinePixels.rounded())
        #expect(metrics.baseline > 0 && metrics.baseline < metrics.height)
        #expect(metrics.underlineThickness >= metrics.hairline)
    }

    @Test func gridSizeDropsPartialCells() {
        let metrics = CellMetrics(scale: 2)
        let size = CGSize(width: metrics.width * 10.5, height: metrics.height * 3.9)
        let grid = metrics.gridSize(for: size)
        #expect(grid == (cols: 10, rows: 3))
    }

    // MARK: - b. Atlas

    @Test(.enabled(if: hasMetalDevice))
    func atlasRasterizesAndCaches() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let metrics = CellMetrics(scale: 2)
        let atlas = GlyphAtlas(device: device, metrics: metrics)

        let shaped = atlas.shape("M")
        #expect(shaped.count == 1)
        let first = try #require(atlas.entry(for: shaped[0], subpixel: 0))
        #expect(first.page == .alpha)
        #expect(first.size.width > 0 && first.size.height > 0)
        #expect(atlas.alphaTexture?.pixelFormat == .a8Unorm)
        #expect(atlas.glyphCount == 1)

        // Same glyph, same bucket → the same rect, not a second raster.
        let second = try #require(atlas.entry(for: shaped[0], subpixel: 0))
        #expect(second.rect == first.rect)
        #expect(atlas.glyphCount == 1)

        // A different subpixel bucket is a *different* raster on purpose.
        _ = atlas.entry(for: shaped[0], subpixel: 2)
        #expect(atlas.glyphCount == 2)
    }

    @Test(.enabled(if: hasMetalDevice))
    func emojiLandsInTheColorPage() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let atlas = GlyphAtlas(device: device, metrics: CellMetrics(scale: 2))
        let shaped = atlas.shape("🙂")
        #expect(!shaped.isEmpty)
        let entry = try #require(atlas.entry(for: shaped[0], subpixel: 0))
        #expect(entry.page == .color)
        #expect(atlas.colorTexture?.pixelFormat == .bgra8Unorm)
    }

    @Test(.enabled(if: hasMetalDevice))
    func cjkResolvesToAFallbackFace() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let metrics = CellMetrics(scale: 2)
        let atlas = GlyphAtlas(device: device, metrics: metrics)

        let latin = atlas.shape("M")
        #expect(CFEqual(latin[0].font, metrics.ctFont), "ASCII must stay in the primary face")

        let cjk = atlas.shape("日")
        #expect(!cjk.isEmpty)
        // The system monospaced face carries no CJK; CoreText must have picked
        // another one, and the atlas keys on that one.
        #expect(!CFEqual(cjk[0].font, metrics.ctFont))
        #expect(atlas.entry(for: cjk[0], subpixel: 0) != nil)
    }

    @Test func metalAvailability() {
        if !hasMetalDevice {
            withKnownIssue("No MTLCreateSystemDefaultDevice() in this environment: the GPU render tests are disabled and only the pure-data merging and metrics tests ran.") {
                Issue.record("Metal device unavailable")
            }
        }
    }

    // MARK: - d. Run merging (no GPU needed)

    @Test func mergesRunsByStyle() {
        let cells = [
            cell("a", fg: Self.white),
            cell("b", fg: Self.white),
            cell("c", fg: Self.red),
        ]
        let runs = RunMerge.textRuns(row(0, cells, cols: 3), background: Self.black, foreground: Self.white)
        #expect(runs.count == 2)
        #expect(runs[0].text == "ab")
        #expect(runs[0].x == 0)
        #expect(runs[0].cellCount == 2)
        #expect(runs[0].columnForUTF16 == [0, 1])
        #expect(runs[1].text == "c")
        #expect(runs[1].x == 2)
    }

    @Test func wideCellAndSpacerTailAreOneRunOfTwoCells() {
        let cells = [
            cell("日", fg: Self.white, wide: .wide),
            cell("", fg: Self.white, wide: .spacerTail),
        ]
        let runs = RunMerge.textRuns(row(0, cells, cols: 2), background: Self.black, foreground: Self.white)
        #expect(runs.count == 1)
        #expect(runs[0].text == "日")
        #expect(runs[0].cellCount == 2, "the tail contributes width but no text")
    }

    @Test func nilBackgroundsProduceNoSpans() {
        let cells = [cell("a"), cell("b"), cell("c")]
        let spans = RunMerge.backgroundSpans(row(0, cells, cols: 8), background: Self.black, foreground: Self.white)
        #expect(spans.isEmpty, "the clear colour already painted these cells")
    }

    @Test func adjacentEqualBackgroundsMergeAndDefaultsAreDropped() {
        let cells = [
            cell(" "),
            cell(" ", bg: Self.red),
            cell(" ", bg: Self.red),
            cell(" ", bg: Self.black),      // equals the frame background → no span
            cell(" ", bg: Self.white),
        ]
        let spans = RunMerge.backgroundSpans(row(0, cells, cols: 5), background: Self.black, foreground: Self.white)
        #expect(spans == [
            RunMerge.BackgroundSpan(x: 1, length: 2, color: Self.red),
            RunMerge.BackgroundSpan(x: 4, length: 1, color: Self.white),
        ])
    }

    @Test func inverseSwapsForegroundAndBackground() {
        let inverted = cell("x", fg: Self.white, bg: Self.red, flags: [.inverse])
        let resolved = RunMerge.resolvedColors(inverted, frame: Self.black, foreground: Self.white)
        #expect(resolved.fg == Self.red)
        #expect(resolved.bg == Self.white)
    }

    @Test func decorationSpansSurviveBlankCells() {
        // An underlined run of spaces has no glyphs at all; the line must still
        // be drawn, which is why decorations merge separately from text.
        let cells = [
            cell(" ", fg: Self.white, underline: .single),
            cell(" ", fg: Self.white, underline: .single),
            cell(" ", fg: Self.white),
        ]
        let spans = RunMerge.decorationSpans(row(0, cells, cols: 3), background: Self.black, foreground: Self.white)
        #expect(spans.count == 1)
        #expect(spans[0].x == 0 && spans[0].length == 2)
        #expect(spans[0].underline == .single)
    }

    // MARK: - c. Offscreen render

    /// Ink in one cell of a rendered frame, as a count of non-background pixels.
    private func inkedPixels(
        _ bytes: [UInt8], width: Int, metrics: CellMetrics, col: Int, row: Int, background: Frame.RGB
    ) -> Int {
        let cellW = Int(metrics.widthPixels), cellH = Int(metrics.heightPixels)
        var count = 0
        for y in (row * cellH)..<((row + 1) * cellH) {
            for x in (col * cellW)..<((col + 1) * cellW)
            where rgb(pixel(bytes, width: width, x: x, y: y)) != background {
                count += 1
            }
        }
        return count
    }

    /// Regression for the live finding: bold text drew nothing at all while
    /// italic and regular text drew fine ("Claude Code" blank in the header,
    /// the bold "ok" after "⏺" blank). Every style must put ink in its cell.
    @Test(.enabled(if: hasMetalDevice), arguments: [
        ("regular", Frame.Cell.Flags()),
        ("bold", Frame.Cell.Flags.bold),
        ("italic", Frame.Cell.Flags.italic),
        ("bold+italic", Frame.Cell.Flags([.bold, .italic])),
        ("faint", Frame.Cell.Flags.faint),
    ])
    func everyStyleDrawsInk(name: String, flags: Frame.Cell.Flags) throws {
        let renderer = try #require(MetalRenderer())
        let metrics = CellMetrics(scale: 2)
        let text = "Claude"
        let cells = text.map { self.cell(String($0), fg: Self.white, flags: flags) }
        let frame = Frame(
            cols: text.count, rows: [row(0, cells, cols: text.count)], cursor: nil,
            background: Self.black, foreground: Self.white, dirty: .full
        )
        let width = Int(metrics.widthPixels) * frame.cols
        let height = Int(metrics.heightPixels)
        let texture = try #require(renderer.makeOffscreenTexture(width: width, height: height))
        renderer.render(frame: frame, to: texture, metrics: metrics)
        let bytes = renderer.readPixels(from: texture)

        for col in 0..<text.count {
            let ink = inkedPixels(bytes, width: width, metrics: metrics, col: col, row: 0, background: Self.black)
            #expect(ink > 0, "\(name): column \(col) of \"\(text)\" drew no glyph")
        }
    }

    // Two tests stood here — `defaultForegroundEqualToBackgroundStillDrawsText`
    // and `aUsablePaletteIsLeftAlone` — guarding a fallback foreground the
    // renderer substituted when a frame arrived black-on-black. Both are
    // deleted with the fallback (2026-09-03). The condition they guarded had
    // two causes and neither survives: the sized-struct bug in `FrameReader`
    // (fixed) and an unstated palette (a `Theme` is now installed into the
    // core at `init`, see `ThemeTests`). What remains is a theme whose own
    // foreground equals its own background, which is a `CCC_THEME` file
    // asking for exactly that and should be drawn as asked rather than
    // second-guessed by the renderer.

    /// A bold face must always be *some* face: if the family has no bold, the
    /// regular one is drawn rather than nothing.
    @Test(.enabled(if: hasMetalDevice))
    func boldFallsBackToAFaceThatExists() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let metrics = CellMetrics(scale: 2)
        let atlas = GlyphAtlas(device: device, metrics: metrics)
        let bold = atlas.styledFont(bold: true, italic: false)
        #expect(CTFontGetSize(bold) == CTFontGetSize(metrics.ctFont))

        // SF Mono has a real Bold weight, reachable only through
        // `monospacedSystemFont(ofSize:weight:)`.
        #expect(metrics.boldFont.fontName != metrics.font.fontName)
        #expect(CTFontGetSymbolicTraits(bold).contains(.traitBold))

        // A family with no bold at all degrades to itself, never to nothing.
        let plain = NSFont(name: "Zapfino", size: 13) ?? NSFont.systemFont(ofSize: 13)
        #expect(CellMetrics.boldCounterpart(of: plain).pointSize == plain.pointSize)

        let shaped = atlas.shape("C", bold: true)
        #expect(shaped.count == 1)
        let entry = try #require(atlas.entry(for: shaped[0], subpixel: 0),
                                 "a bold glyph must rasterize into the atlas")
        #expect(entry.size.width > 0 && entry.size.height > 0)

        // Bold and regular are different rasters, not one shared cache entry.
        let regular = atlas.shape("C")
        let regularEntry = try #require(atlas.entry(for: regular[0], subpixel: 0))
        #expect(entry.rect != regularEntry.rect)
    }

    private func demoFrame() -> Frame {
        let cols = 10
        var hello: [Frame.Cell] = []
        for character in "hello" { hello.append(cell(String(character), fg: Self.white)) }
        let redSpan = (0..<cols).map { x in
            (2..<5).contains(x) ? cell(" ", bg: Self.red) : Frame.Cell.blank
        }
        return Frame(
            cols: cols,
            rows: [
                row(0, hello, cols: cols),
                row(1, redSpan, cols: cols),
                row(2, [], cols: cols),
            ],
            cursor: Frame.Cursor(x: 1, y: 0, style: .block, visible: true,
                                 blinking: false, wideTail: false, color: nil),
            background: Self.black,
            foreground: Self.white,
            dirty: .full
        )
    }

    @Test(.enabled(if: hasMetalDevice))
    func offscreenRenderMatchesTheFrame() throws {
        let renderer = try #require(MetalRenderer())
        let metrics = CellMetrics(scale: 2)
        let frame = demoFrame()

        let cellW = Int(metrics.widthPixels)
        let cellH = Int(metrics.heightPixels)
        let width = cellW * frame.cols
        let height = cellH * frame.rows.count
        let texture = try #require(renderer.makeOffscreenTexture(width: width, height: height))
        renderer.render(frame: frame, to: texture, metrics: metrics)
        let bytes = renderer.readPixels(from: texture)

        // Inside the red span (row 1, cell 3).
        let inRed = pixel(bytes, width: width, x: 3 * cellW + cellW / 2, y: cellH + cellH / 2)
        #expect(rgb(inRed) == Self.red)

        // An untouched cell is exactly the frame background.
        let empty = pixel(bytes, width: width, x: 8 * cellW + cellW / 2, y: 2 * cellH + cellH / 2)
        #expect(rgb(empty) == Self.black)

        // The "h" cell has ink in it.
        var inkedPixels = 0
        for y in 0..<cellH {
            for x in 0..<cellW where rgb(pixel(bytes, width: width, x: x, y: y)) != Self.black {
                inkedPixels += 1
            }
        }
        #expect(inkedPixels > 0, "the glyph for \"h\" was not drawn")

        // The block cursor fills its cell in the foreground colour, and the
        // cell's own glyph is redrawn in the background colour on top.
        var cursorFilled = 0
        var cursorInverted = 0
        for y in 0..<cellH {
            for x in cellW..<(2 * cellW) {
                let value = rgb(pixel(bytes, width: width, x: x, y: y))
                if value == Self.white { cursorFilled += 1 }
                if value != Self.white { cursorInverted += 1 }
            }
        }
        #expect(cursorFilled > 0, "the block cursor did not fill its cell with the foreground colour")
        #expect(cursorInverted > 0, "the cursor cell's glyph was not inverted on top of the block")
    }

    // MARK: - e. Dirty

    @Test(.enabled(if: hasMetalDevice))
    func aCleanFrameIsNotEncoded() throws {
        let renderer = try #require(MetalRenderer())
        let metrics = CellMetrics(scale: 2)
        var frame = demoFrame()
        let texture = try #require(renderer.makeOffscreenTexture(
            width: Int(metrics.widthPixels) * frame.cols,
            height: Int(metrics.heightPixels) * frame.rows.count
        ))

        renderer.render(frame: frame, to: texture, metrics: metrics, force: false)
        #expect(renderer.encodedFrames == 1)

        frame.dirty = .none
        renderer.render(frame: frame, to: texture, metrics: metrics, force: false)
        renderer.render(frame: frame, to: texture, metrics: metrics, force: false)
        #expect(renderer.encodedFrames == 1, "a frame with nothing dirty must not reach the GPU")

        frame.dirty = .partial
        renderer.render(frame: frame, to: texture, metrics: metrics, force: false)
        #expect(renderer.encodedFrames == 2)
    }

    // MARK: - The view

    @Test(.enabled(if: hasMetalDevice))
    func paneViewSnapshotsWithoutAWindow() throws {
        let metrics = CellMetrics(scale: 2)
        let frame = demoFrame()
        let view = MetalPaneView(
            frame: NSRect(x: 0, y: 0, width: metrics.width * 10, height: metrics.height * 3),
            metrics: metrics
        )
        #expect(view.acceptsFirstResponder)
        #expect(view.gridSize() == (cols: 10, rows: 3))
        #expect(view.snapshotImage() == nil, "nothing to snapshot before the first frame")

        view.render(frame)
        // `cacheDisplay(in:to:)` cannot see a CAMetalLayer; this offscreen path
        // is the only way `ccc peek` gets pixels out of a Metal pane.
        let image = try #require(view.snapshotImage())
        #expect(image.width == Int(metrics.widthPixels) * 10)
        #expect(image.height == Int(metrics.heightPixels) * 3)
    }

    /// `presentedFrames` is the black-pane oracle (CLAUDE.md), and it
    /// counted draw *calls*: a frame the renderer declined — nothing dirty,
    /// already on screen — still counted, so a window dragged by a pixel
    /// "presented" hundreds of frames it never encoded. It counts encodes.
    @Test(.enabled(if: hasMetalDevice))
    func presentedFramesCountEncodesNotCalls() throws {
        let metrics = CellMetrics(scale: 2)
        var frame = demoFrame()
        let view = MetalPaneView(
            frame: NSRect(x: 0, y: 0, width: metrics.width * 10, height: metrics.height * 3),
            metrics: metrics
        )
        view.render(frame)
        #expect(view.presentedFrames == 1)
        frame.dirty = .none
        view.render(frame)
        view.render(frame)
        #expect(view.presentedFrames == 1, "a clean frame the renderer declined was not presented")
        frame.dirty = .partial
        view.render(frame)
        #expect(view.presentedFrames == 2)
    }

    /// Why the atlas may be written while frames are still on the GPU:
    /// it only ever writes fresh space. Every rect is disjoint from every
    /// other and inside the page, so a frame in flight samples nothing a
    /// later raster touches (verified 2026-09-04 against the `.shared`
    /// texture and the monotone shelf packer). The day eviction or a
    /// repack arrives this fails, and that is the day `replace(region:)`
    /// needs a staging blit inside the frame's own command buffer.
    @Test(.enabled(if: hasMetalDevice))
    func atlasRectsNeverOverlap() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let atlas = GlyphAtlas(device: device, metrics: CellMetrics(scale: 2))
        // Distinct rects: two characters that shape to one glyph share an
        // entry, and a shared entry is a cache hit, not an overlap.
        var seen = Set<[Int]>()
        var rects: [CGRect] = []
        for scalar in 0x21...0x17E {
            guard let unicode = UnicodeScalar(scalar) else { continue }
            for glyph in atlas.shape(String(unicode)) {
                for bucket in 0..<3 {
                    guard let entry = atlas.entry(for: glyph, subpixel: bucket) else { continue }
                    let r = entry.rect
                    if seen.insert([Int(r.minX), Int(r.minY), Int(r.width), Int(r.height)]).inserted { rects.append(r) }
                }
            }
        }
        #expect(rects.count > 300)
        let page = CGRect(x: 0, y: 0, width: GlyphAtlas.alphaPageSize, height: GlyphAtlas.alphaPageSize)
        #expect(rects.allSatisfy { page.contains($0) })
        var overlap: (CGRect, CGRect)?
        outer: for i in rects.indices {
            for j in rects.indices where j > i && rects[i].intersects(rects[j]) {
                overlap = (rects[i], rects[j])
                break outer
            }
        }
        #expect(overlap == nil, "\(String(describing: overlap)) share texels")
    }

    @Test(.enabled(if: hasMetalDevice))
    func resizeOnlyReportsWhenTheGridChanges() {
        let metrics = CellMetrics(scale: 2)
        let view = MetalPaneView(
            frame: NSRect(x: 0, y: 0, width: metrics.width * 10, height: metrics.height * 3),
            metrics: metrics
        )
        var reported: [(cols: Int, rows: Int)] = []
        view.onResize = { reported.append($0) }

        // A drag that stays inside the same cell must not reach the child.
        view.setFrameSize(NSSize(width: metrics.width * 10 + 3, height: metrics.height * 3 + 3))
        #expect(reported.isEmpty)

        view.setFrameSize(NSSize(width: metrics.width * 14, height: metrics.height * 5))
        #expect(reported.count == 1)
        #expect(reported.last! == (cols: 14, rows: 5))

        view.setFrameSize(NSSize(width: metrics.width * 14 + 1, height: metrics.height * 5 + 1))
        #expect(reported.count == 1)
    }

    // MARK: - Timing (reported, not asserted)

    @Test(.enabled(if: hasMetalDevice))
    func offscreenFrameTiming() throws {
        let renderer = try #require(MetalRenderer())
        let metrics = CellMetrics(scale: 2)
        let cols = 120, rows = 40
        let palette: [Frame.RGB] = [
            Frame.RGB(220, 220, 220), Frame.RGB(120, 200, 140),
            Frame.RGB(200, 160, 90), Frame.RGB(140, 160, 220),
        ]
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJ0123456789 ()[]{}<>/\\|-_=+")

        var frameRows: [Frame.Row] = []
        for y in 0..<rows {
            var cells: [Frame.Cell] = []
            for x in 0..<cols {
                var flags: Frame.Cell.Flags = []
                if (x + y) % 7 == 0 { flags.insert(.bold) }
                if (x + y) % 11 == 0 { flags.insert(.faint) }
                if (x + y) % 23 == 0 { flags.insert(.inverse) }
                cells.append(cell(
                    String(alphabet[(x * 7 + y * 13) % alphabet.count]),
                    fg: palette[(x + y) % palette.count],
                    bg: (x / 8 + y) % 5 == 0 ? Frame.RGB(30, 30, 40) : nil,
                    flags: flags,
                    underline: (x + y) % 31 == 0 ? .single : .none
                ))
            }
            frameRows.append(Frame.Row(y: y, dirty: true, cells: cells, selection: nil))
        }
        let frame = Frame(
            cols: cols, rows: frameRows,
            cursor: Frame.Cursor(x: 4, y: 4, style: .block, visible: true,
                                 blinking: false, wideTail: false, color: nil),
            background: Self.black, foreground: Self.white, dirty: .full
        )

        let texture = try #require(renderer.makeOffscreenTexture(
            width: Int(metrics.widthPixels) * cols,
            height: Int(metrics.heightPixels) * rows
        ))
        // Warm the atlas and the shape cache; the steady state is what matters.
        renderer.render(frame: frame, to: texture, metrics: metrics)

        let iterations = 100
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<iterations {
                renderer.render(frame: frame, to: texture, metrics: metrics)
            }
        }
        let msPerFrame = Double(elapsed.components.attoseconds) / 1e15 / Double(iterations)
            + Double(elapsed.components.seconds) * 1000 / Double(iterations)
        print("RenderTests: \(cols)x\(rows) mixed-style frame, offscreen, \(iterations)x: "
            + String(format: "%.3f ms/frame", msPerFrame))
        #expect(msPerFrame > 0)
    }
}
