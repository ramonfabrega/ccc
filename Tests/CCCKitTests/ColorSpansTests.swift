import Foundation
import Testing

@testable import CCCKit

/// Item 12a: colour a golden can assert, so the one oracle an agent can run
/// with no screen stops being text-only.
///
/// These drive the real Ghostty core with real SGR bytes rather than
/// hand-built `Frame`s, because the claim being pinned is about what the
/// *core* resolves — a hand-built frame would only test the merge loop and
/// would pass just as happily if the palette lookup were wrong.
@Suite struct ColorSpansTests {
    /// The default theme's two anchors, as `ccc pixel` spells them. `#15191F`
    /// is the value docs/EVIDENCE.md "8b: there is no colour-management
    /// residual" measured off a real `screencapture` and found bit-identical
    /// between ccc's pane and iTerm — so this string appearing here is the
    /// headless oracle agreeing with the screen oracle by string equality,
    /// which is the whole reason both spell a colour `#RRGGBB`.
    static let defaultBackground = "#15191F"
    static let defaultForeground = "#DCDCDC"

    @MainActor private func grid(_ bytes: String, cols: Int = 40, rows: Int = 3) -> Grid {
        let host = GhosttyHost(cols: cols, rows: rows)
        host.feed(Data(bytes.utf8))
        return host.snapshot(colors: true)
    }

    /// Plain text, ANSI red, `inverse`, and a background colour in one row:
    /// the palette is resolved, `inverse` swaps, and adjacent equal cells
    /// merge — 40 columns become 7 runs.
    @Test @MainActor func oneRowOfSGRResolvesAndMerges() throws {
        let g = grid("plain \u{1B}[31mred\u{1B}[0m \u{1B}[7minverse\u{1B}[0m \u{1B}[44mbluebg\u{1B}[0m")
        #expect(g.lines[0] == "plain red inverse bluebg" + String(repeating: " ", count: 16))
        let spans = try #require(g.colors?[0])
        let described = spans.map { "\($0.col)+\($0.len) \($0.fg.hex) on \($0.bg.hex)" }
        #expect(described == [
            "0+6 \(Self.defaultForeground) on \(Self.defaultBackground)",   // plain
            "6+3 #B43C2A on \(Self.defaultBackground)",                     // ANSI red, resolved
            "9+1 \(Self.defaultForeground) on \(Self.defaultBackground)",   // the space
            "10+7 \(Self.defaultBackground) on \(Self.defaultForeground)",  // inverse: swapped
            "17+1 \(Self.defaultForeground) on \(Self.defaultBackground)",
            "18+6 \(Self.defaultForeground) on #2744C7",                    // bluebg
            "24+16 \(Self.defaultForeground) on \(Self.defaultBackground)", // the tail
        ])
        // Every column is covered exactly once, and the runs are in order.
        #expect(spans.first?.col == 0)
        #expect(spans.reduce(0) { $0 + $1.len } == g.cols)
        for (a, b) in zip(spans, spans.dropFirst()) { #expect(a.col + a.len == b.col) }
    }

    /// The anti-drift test, and the reason this file exists at all. The
    /// renderer and the oracle **share `RunMerge.resolvedColors`** and differ
    /// only in how they merge — the renderer by full `RunStyle` because that
    /// is what forces a shaping call, the oracle by colour alone. If anyone
    /// re-implements resolution on the oracle's side, `ccc pixel` and
    /// `ccc snapshot --color` start disagreeing and neither is trustworthy.
    /// This pins them cell by cell against the shared function.
    @Test @MainActor func theOracleResolvesExactlyAsTheRendererDoes() throws {
        let host = GhosttyHost(cols: 40, rows: 3)
        host.feed(Data("\u{1B}[31mred\u{1B}[0m \u{1B}[7minv\u{1B}[0m \u{1B}[44mbg\u{1B}[0m".utf8))
        let frame = try #require(host.frame())
        let grid = host.snapshot(colors: true)
        let spans = try #require(grid.colors?[0])

        for (column, cell) in frame.rows[0].cells.enumerated() {
            let expected = RunMerge.resolvedColors(cell, frame: frame.background, foreground: frame.foreground)
            let got = try #require(grid.color(col: column, row: 0), "column \(column) has no span")
            #expect(got.fg == expected.fg, "column \(column) foreground")
            // A nil background is "the clear colour already painted it",
            // which on screen IS the frame background — the oracle reports
            // what is painted, not which path painted it.
            #expect(got.bg == (expected.bg ?? frame.background), "column \(column) background")
        }
        #expect(spans.count < frame.rows[0].cells.count)  // it did merge
    }

    /// `snapshot()` — every caller that drives the pane rather than judging
    /// it — carries no colour at all. `waitUntilDrawn` takes one of these
    /// every 250 ms; it must stay the cheap text grid.
    @Test @MainActor func theDefaultSnapshotCarriesNoColour() {
        let host = GhosttyHost(cols: 20, rows: 2)
        host.feed(Data("\u{1B}[31mred\u{1B}[0m".utf8))
        #expect(host.snapshot().colors == nil)
        #expect(host.snapshot(colors: false).colors == nil)
        #expect(host.snapshot(colors: true).colors != nil)
    }

    /// A grid with no colour answers "I don't know" rather than a guess —
    /// the same rule the roster follows for a host that did not answer.
    @Test @MainActor func lookupOnAColourlessGridIsNil() {
        let host = GhosttyHost(cols: 20, rows: 2)
        host.feed(Data("hello".utf8))
        #expect(host.snapshot().color(col: 0, row: 0) == nil)
        let coloured = host.snapshot(colors: true)
        #expect(coloured.color(col: 0, row: 0)?.bg.hex == Self.defaultBackground)
        // Out of range in either axis is nil, never a crash.
        #expect(coloured.color(col: 999, row: 0) == nil)
        #expect(coloured.color(col: 0, row: 999) == nil)
        #expect(coloured.color(col: 0, row: -1) == nil)
    }

    /// The notation is the contract with `ccc pixel`: one colour, one
    /// `#RRGGBB` string, round-tripping through JSON unchanged and equal to
    /// what `PixelReader.hex` prints for the same value.
    @Test func rgbIsCodableAsTheHexPixelPrints() throws {
        let rgb = Frame.RGB(0x15, 0x19, 0x1F)
        let data = try JSONEncoder().encode(rgb)
        #expect(String(data: data, encoding: .utf8) == "\"#15191F\"")
        #expect(PixelReader.hex(rgb) == "#15191F")
        #expect(try JSONDecoder().decode(Frame.RGB.self, from: data) == rgb)
        // A span survives the control socket's encoding whole.
        let span = Grid.ColorSpan(col: 3, len: 4, fg: rgb, bg: Frame.RGB(0xDC, 0xDC, 0xDC))
        let round = try JSONDecoder().decode(Grid.ColorSpan.self, from: JSONEncoder().encode(span))
        #expect(round == span)
    }

    @Test func aBadColourIsNamedNotGuessed() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Frame.RGB.self, from: Data("\"not-a-colour\"".utf8))
        }
    }

    /// The real `claude attach` capture, replayed: it carries no SGR colour
    /// anywhere, so every row is one run of the default pair. That is worth
    /// pinning precisely *because* it is uniform — it is the fixture the
    /// text goldens are taken from, and this says what colour those goldens
    /// were always being drawn in.
    @Test @MainActor func theAttachCaptureIsOneRunOfTheDefaultPair() throws {
        let bytes = try Data(contentsOf: Fixtures.url("attach/attach.bin"))
        let host = GhosttyHost(cols: 100, rows: 30)
        host.feed(bytes)
        let grid = host.snapshot(colors: true)
        let colors = try #require(grid.colors)
        #expect(colors.count == 30)
        for (row, spans) in colors.enumerated() {
            #expect(spans.count == 1, "row \(row) unexpectedly has \(spans.count) runs")
            #expect(spans.first?.len == 100)
            #expect(spans.first?.bg.hex == Self.defaultBackground)
            #expect(spans.first?.fg.hex == Self.defaultForeground)
        }
    }

    /// The SwiftTerm escape hatch reads text alone, and says so by leaving
    /// `colors` nil rather than returning empty runs a golden would read as
    /// "no colour anywhere".
    @Test @MainActor func theSwiftTermCoreAnswersNilRatherThanEmpty() {
        let host = HeadlessHost(cols: 20, rows: 2)
        host.feed(Data("\u{1B}[31mred\u{1B}[0m".utf8))
        #expect(host.snapshot(colors: true).colors == nil)
        #expect(host.snapshot().colors == nil)
    }
}
