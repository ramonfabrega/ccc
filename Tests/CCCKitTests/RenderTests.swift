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
