import Foundation
import Metal
import Testing

@testable import CCCKit

/// Evaluated once, off the main actor, so it can gate `@Test(.enabled(if:))`.
private let hasMetalDevice = MTLCreateSystemDefaultDevice() != nil

/// Item 12c: **a bold cell wearing ANSI colour 0–7 paints colour n+8.**
///
/// The item was queued as blocked — the core resolves palette indices to RGB
/// before a cell reaches us (`render.h`, `..._DATA_FG_COLOR`: "Bold color
/// handling is not applied"), so the reasoning went that no index was left to
/// add 8 to and one would have to be carried across the seam first. That was
/// wrong about which field: the *resolved colour* has no index, but
/// `GhosttyStyle.fg_color` is a tagged union and `FrameReader` was already
/// reading that struct for `bold` itself. Nothing new crosses the seam; the
/// reader stopped throwing half of it away (`Frame.Cell.fgPalette`).
///
/// These drive the real core with real SGR bytes, for `ColorSpansTests`'
/// reason: the claim is about what the *core* hands us, and a hand-built
/// frame would pass just as happily if the tagged union were never read.
@Suite struct BoldIsBrightTests {
    /// The built-in theme's slots 1 and 9, as `ccc pixel` spells them. The
    /// whole of 12c is the distance between these two strings.
    static let red = "#B43C2A"          // ansi 1
    static let brightRed = "#DD7975"    // ansi 9
    static let defaultForeground = "#DCDCDC"

    @MainActor private func grid(_ bytes: String, theme: Theme = .iterm,
                                 cols: Int = 40, rows: Int = 2) -> Grid {
        let host = GhosttyHost(cols: cols, rows: rows, theme: theme)
        host.feed(Data(bytes.utf8))
        return host.snapshot(colors: true)
    }

    /// The rule, and nothing else: the same colour, bold and not bold.
    @Test @MainActor func boldPromotesAnAnsiColourToItsBright() throws {
        let g = grid("\u{1B}[31mplain\u{1B}[0m\u{1B}[1;31mbold\u{1B}[0m")
        #expect(g.lines[0].hasPrefix("plainbold"))
        #expect(g.color(col: 0, row: 0)?.fg.hex == Self.red)
        #expect(g.color(col: 5, row: 0)?.fg.hex == Self.brightRed)
    }

    /// Every one of the eight, so the promotion is `n + 8` rather than a
    /// single lucky index — an off-by-one in the slot arithmetic passes the
    /// test above for red and fails here for six of the eight.
    @Test @MainActor func allEightSlotsPromoteToTheirOwnBright() throws {
        for slot in 0...7 {
            let g = grid("\u{1B}[1;\(30 + slot)mX\u{1B}[0m")
            #expect(g.color(col: 0, row: 0)?.fg == Theme.iterm.ansi[slot + 8],
                    "slot \(slot) should paint ansi[\(slot + 8)]")
        }
    }

    /// Three cells with no slot to promote, each keeping its colour: a
    /// truecolor `SGR 38;2`, the default foreground under a bare `SGR 1`,
    /// and — the one most likely to be got wrong — a *background* colour,
    /// which bold never touches.
    @Test @MainActor func acellWithNoSlotKeepsItsColour() throws {
        let truecolor = grid("\u{1B}[1;38;2;10;20;30mX\u{1B}[0m")
        #expect(truecolor.color(col: 0, row: 0)?.fg.hex == "#0A141E")

        let bareBold = grid("\u{1B}[1mX\u{1B}[0m")
        #expect(bareBold.color(col: 0, row: 0)?.fg.hex == Self.defaultForeground)

        let onRed = grid("\u{1B}[1;41mX\u{1B}[0m")
        #expect(onRed.color(col: 0, row: 0)?.bg.hex == Self.red)
        #expect(onRed.color(col: 0, row: 0)?.fg.hex == Self.defaultForeground)
    }

    /// Slots 8–15 are already bright and slots 16–255 are the xterm cube,
    /// where +8 is a different colour rather than a brighter one. Stated as
    /// "bold changes nothing here" rather than against a hardcoded hex, so
    /// the cube's arithmetic stays the core's business.
    @Test @MainActor func brightSlotsAndTheCubeAreLeftAlone() throws {
        for sgr in ["91", "38;5;9", "38;5;196", "38;5;240"] {
            let plain = grid("\u{1B}[\(sgr)mX\u{1B}[0m").color(col: 0, row: 0)
            let bold = grid("\u{1B}[1;\(sgr)mX\u{1B}[0m").color(col: 0, row: 0)
            #expect(plain?.fg == bold?.fg, "SGR \(sgr) should not move")
        }
        // …and the two spellings of bright red agree, which is what makes
        // "promoted" indistinguishable from "asked for" on screen.
        #expect(grid("\u{1B}[91mX").color(col: 0, row: 0)?.fg.hex == Self.brightRed)
    }

    /// **The `Frame` still says only what the core said.** The promotion is a
    /// policy resolved with the theme's colours, exactly like selection, so a
    /// cell carries the unpromoted colour *and* the slot it came from — and
    /// `RunMerge` is the only place the two become one answer.
    @Test @MainActor func theSeamCarriesTheSlotNotThePromotion() throws {
        let host = GhosttyHost(cols: 20, rows: 2)
        host.feed(Data("\u{1B}[1;31mA\u{1B}[0m\u{1B}[38;2;10;20;30mB\u{1B}[0m".utf8))
        let frame = try #require(host.frame())

        let bold = frame.rows[0].cells[0]
        #expect(bold.fgPalette == 1)
        #expect(bold.fg?.hex == Self.red, "the frame carries the resolved slot, unpromoted")
        #expect(bold.flags.contains(.bold))

        #expect(frame.rows[0].cells[1].fgPalette == nil, "truecolor has no slot")
        #expect(frame.rows[0].cells[2].fgPalette == nil, "an unstyled cell has no slot")
    }

    /// Promotion happens **before** inversion: the bright colour is what the
    /// cell is wearing, and `inverse` then decides which side wears it. Doing
    /// it the other way round would leave the text bright-on-nothing.
    @Test @MainActor func inversionSwapsThePromotedColour() throws {
        let g = grid("\u{1B}[1;7;31mX\u{1B}[0m")
        let cell = try #require(g.color(col: 0, row: 0))
        #expect(cell.bg.hex == Self.brightRed)
        #expect(cell.fg.hex == "#15191F")   // the frame background, swapped in
    }

    /// Item 12b's rule outranks this one: a selected cell is the theme's two
    /// colours whatever SGR the child had set, and "bold red" is no exception.
    @Test @MainActor func selectionStillWinsOutright() throws {
        let host = GhosttyHost(cols: 20, rows: 2)
        host.feed(Data("\u{1B}[1;31mbold\u{1B}[0m".utf8))
        #expect(host.select(SelectionRegion(fromCol: 0, fromRow: 0, toCol: 3, toRow: 0)))
        let grid = host.snapshot(colors: true)
        #expect(grid.color(col: 0, row: 0)?.fg == Theme.iterm.selectionForeground)
        #expect(grid.color(col: 0, row: 0)?.bg == Theme.iterm.selectionBackground)
    }

    /// The anti-drift check in the shape 12a established: the renderer and
    /// the oracle share `RunMerge.resolvedColors`, so `ccc pixel` reading a
    /// bold cell off a screencapture and `ccc snapshot --color` reading the
    /// same cell headlessly cannot come apart. Pinned cell by cell.
    @Test @MainActor func theOracleResolvesExactlyAsTheRendererDoes() throws {
        let host = GhosttyHost(cols: 40, rows: 2)
        host.feed(Data("\u{1B}[1;31mbold\u{1B}[0m \u{1B}[31mplain\u{1B}[0m \u{1B}[1;7;32minv\u{1B}[0m".utf8))
        let frame = try #require(host.frame())
        let grid = host.snapshot(colors: true)

        for (column, cell) in frame.rows[0].cells.enumerated() {
            let expected = RunMerge.resolvedColors(
                cell, frame: frame.background, foreground: frame.foreground,
                bold: Theme.iterm.bold)
            let got = try #require(grid.color(col: column, row: 0), "column \(column) has no span")
            #expect(got.fg == expected.fg, "column \(column) foreground")
            #expect(got.bg == (expected.bg ?? frame.background), "column \(column) background")
        }
    }

    /// It is a policy, so a terminal is allowed to disagree — and `false` has
    /// to be a real path, not a field nothing reads. A theme with the policy
    /// off leaves bold red exactly where the core resolved it.
    @Test @MainActor func theSwitchTurnsItOff() throws {
        var plainBold = Theme.iterm
        plainBold.boldIsBright = false
        #expect(plainBold.bold == nil)
        let g = grid("\u{1B}[1;31mX\u{1B}[0m", theme: plainBold)
        #expect(g.color(col: 0, row: 0)?.fg.hex == Self.red)
    }

    /// `CCC_THEME`'s side of the switch. Absent means on: a theme file
    /// written before 12c described a pane that already promoted bold, so
    /// reading a missing key as `false` would change how an existing file
    /// renders.
    @Test func theKnobRoundTripsAndDefaultsToOn() throws {
        let encoded = try JSONEncoder().encode(Theme.iterm)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["boldIsBright"] as? Bool == true)
        #expect(try JSONDecoder().decode(Theme.self, from: encoded).boldIsBright)

        var stripped = object
        stripped.removeValue(forKey: "boldIsBright")
        let older = try JSONSerialization.data(withJSONObject: stripped)
        #expect(try JSONDecoder().decode(Theme.self, from: older).boldIsBright)
    }

    /// The last link: **pixels**. Everything above reads spans; this renders
    /// the same bytes through the real Metal renderer into an offscreen
    /// texture and reads the colour back out, which is as close to
    /// `ccc capture` as a machine with no Screen Recording permission gets.
    ///
    /// It uses `inverse` for a reason. A promoted foreground is glyph ink —
    /// antialiased, so no single pixel is honestly `#DD7975` — while the
    /// same promotion under `inverse` becomes a solid background quad that a
    /// centre sample can state exactly, the way `ccc pixel --cell` does.
    /// Two cells, identical but for the `1`, and the whole item is whether
    /// they differ.
    @Test(.enabled(if: hasMetalDevice)) @MainActor func theBrightColourReachesThePixels() throws {
        let host = GhosttyHost(cols: 6, rows: 2)
        host.feed(Data("\u{1B}[1;7;31m  \u{1B}[0m\u{1B}[7;31m  \u{1B}[0m".utf8))
        let frame = try #require(host.frame())

        let renderer = try #require(MetalRenderer())
        let metrics = CellMetrics(scale: 2)
        let cellWidth = Int(metrics.widthPixels), cellHeight = Int(metrics.heightPixels)
        let width = cellWidth * frame.cols, height = cellHeight * frame.rows.count
        let texture = try #require(renderer.makeOffscreenTexture(width: width, height: height))
        renderer.render(frame: frame, to: texture, metrics: metrics)
        let bytes = renderer.readPixels(from: texture)

        func centre(col: Int, row: Int) -> String {
            let x = col * cellWidth + cellWidth / 2, y = row * cellHeight + cellHeight / 2
            let index = (y * width + x) * 4   // BGRA8
            return PixelReader.hex(Frame.RGB(bytes[index + 2], bytes[index + 1], bytes[index]))
        }
        #expect(centre(col: 0, row: 0) == Self.brightRed)   // bold
        #expect(centre(col: 2, row: 0) == Self.red)         // the same SGR without it
    }

    /// The theme's own arithmetic: `bold` is the eight brights in the order
    /// the slots they replace appear, so `bright[1]` is ansi 9 and not ansi 1.
    @Test func theBrightEightAreTheSecondHalfOfTheSixteen() throws {
        let bold = try #require(Theme.iterm.bold)
        #expect(bold.bright.count == 8)
        #expect(bold.bright == Array(Theme.iterm.ansi[8...15]))
        #expect(bold.bright[1].hex == Self.brightRed)
    }
}
