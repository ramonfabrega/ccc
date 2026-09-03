import CCCKit
import Foundation
import Testing

/// The pane's colours, end to end: what a theme says, what the core is told,
/// and what comes back in a `Frame`.
///
/// Before this existed ccc set none of the four colour options and got the
/// core's own fallbacks — `#000000` on `#FFFFFF` with Ghostty's Tomorrow
/// Night palette — which is the whole of what "the colours feel off" was.
/// The measurement is in docs/EVIDENCE.md under "the pane wore Ghostty's
/// theme"; these tests are what stop it coming back.
@Suite struct ThemeTests {
    /// A theme with no colour in common with `Theme.iterm`, so a test that
    /// passes cannot be passing on a default.
    private static let probe = Theme(
        name: "probe",
        background: Frame.RGB(0x01, 0x02, 0x03),
        foreground: Frame.RGB(0xFE, 0xFD, 0xFC),
        cursor: Frame.RGB(0x11, 0x22, 0x33),
        cursorText: Frame.RGB(0x44, 0x55, 0x66),
        selectionBackground: Frame.RGB(0x77, 0x88, 0x99),
        selectionForeground: Frame.RGB(0xAA, 0xBB, 0xCC),
        ansi: (0..<16).map { Frame.RGB(UInt8($0 * 16), 0x10, UInt8(255 - $0 * 16)) })

    @MainActor
    private func frame(_ theme: Theme, feeding text: String, cols: Int = 40, rows: Int = 6) -> Frame? {
        let host = GhosttyHost(cols: cols, rows: rows, theme: theme)
        host.feed(Data(text.utf8))
        return host.frame()
    }

    // MARK: - The four options reach the core

    @Test @MainActor func defaultColoursComeFromTheTheme() throws {
        let f = try #require(frame(Self.probe, feeding: "plain"))
        #expect(f.background == Self.probe.background)
        #expect(f.foreground == Self.probe.foreground)
        #expect(f.cursor?.color == Self.probe.cursor)
        // A cell with no SGR carries no explicit colour: the renderer uses
        // the frame default, which is now ours.
        #expect(f.rows[0].cells[0].fg == nil)
    }

    @Test @MainActor func namedColoursResolveThroughOurSixteen() throws {
        // SGR 30–37 are palette 0–7, SGR 90–97 are 8–15.
        var sgr = ""
        for i in 0..<8 { sgr += "\u{1b}[3\(i)mX" }
        sgr += "\u{1b}[0m\r\n"
        for i in 0..<8 { sgr += "\u{1b}[9\(i)mX" }
        let f = try #require(frame(Self.probe, feeding: sgr))
        for i in 0..<8 {
            #expect(f.rows[0].cells[i].fg == Self.probe.ansi[i], "SGR 3\(i)")
            #expect(f.rows[1].cells[i].fg == Self.probe.ansi[i + 8], "SGR 9\(i)")
        }
    }

    @Test @MainActor func theItermThemeIsWhatShips() throws {
        let f = try #require(frame(.iterm, feeding: "\u{1b}[31mR\u{1b}[92mG"))
        #expect(f.background.hex == "#15191F")
        #expect(f.foreground.hex == "#DCDCDC")
        #expect(f.rows[0].cells[0].fg?.hex == "#B43C2A")   // ansi 1, red
        #expect(f.rows[0].cells[1].fg?.hex == "#58E790")   // ansi 10, bright green
    }

    /// Slots 16–255 are the xterm cube and grey ramp — arithmetic every
    /// application hardcodes, so a theme must not move them. The values are
    /// the core's own generator's, seeded before our sixteen are written
    /// over the top.
    @Test @MainActor func slotsAboveFifteenStayArithmetic() throws {
        var sgr = ""
        for i in [16, 100, 200, 231, 250] { sgr += "\u{1b}[38;5;\(i)mX" }
        let f = try #require(frame(Self.probe, feeding: sgr))
        #expect(f.rows[0].cells[0].fg?.hex == "#000000")   // 16, cube origin
        #expect(f.rows[0].cells[1].fg?.hex == "#878700")   // 100 = 40*n+55 on two axes
        #expect(f.rows[0].cells[2].fg?.hex == "#FF00D7")   // 200
        #expect(f.rows[0].cells[3].fg?.hex == "#FFFFFF")   // 231, cube corner
        #expect(f.rows[0].cells[4].fg?.hex == "#BCBCBC")   // 250 = (n-232)*10+8
    }

    /// The four options are installed as *defaults*, not overrides, so a
    /// child that themes itself still wins. Anything else would make ccc
    /// fight programs that set their own colours.
    @Test @MainActor func theChildsOwnPaletteStillWins() throws {
        // OSC 4: set palette entry 1 to pure green, then print SGR 31.
        let osc = "\u{1b}]4;1;rgb:00/ff/00\u{1b}\\\u{1b}[31mX"
        let f = try #require(frame(Self.probe, feeding: osc))
        #expect(f.rows[0].cells[0].fg?.hex == "#00FF00", "OSC 4 from the child must override the theme")
    }

    // MARK: - The file the knob reads

    @Test func hexRoundTrips() {
        #expect(Frame.RGB(hex: "#15191F") == Frame.RGB(0x15, 0x19, 0x1F))
        #expect(Frame.RGB(hex: "15191f") == Frame.RGB(0x15, 0x19, 0x1F))
        #expect(Frame.RGB(hex: "#abc") == Frame.RGB(0xAA, 0xBB, 0xCC))
        #expect(Frame.RGB(0x0A, 0x0B, 0x0C).hex == "#0A0B0C")
        #expect(Frame.RGB(hex: "#12345") == nil)
        #expect(Frame.RGB(hex: "not a colour") == nil)
        #expect(Frame.RGB(hex: "") == nil)
    }

    @Test func aThemeSurvivesJSON() throws {
        let data = try JSONEncoder().encode(Theme.iterm)
        #expect(try JSONDecoder().decode(Theme.self, from: data) == Theme.iterm)
        // The encoding is hex strings, so the file is hand-editable — that
        // is the whole point of CCC_THEME.
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("#15191F"))
    }

    @Test func aBadThemeIsNamedRatherThanGuessed() throws {
        func decode(_ json: String) throws -> Theme {
            try JSONDecoder().decode(Theme.self, from: Data(json.utf8))
        }
        var fields = """
            "name":"x","background":"#000000","foreground":"#FFFFFF",
            "cursor":"#FFFFFF","cursorText":"#000000",
            "selectionBackground":"#B3D7FF","selectionForeground":"#000000"
            """
        let fifteen = (0..<15).map { _ in "\"#101010\"" }.joined(separator: ",")
        #expect(throws: DecodingError.self) { try decode("{\(fields),\"ansi\":[\(fifteen)]}") }

        let sixteen = (0..<15).map { _ in "\"#101010\"" } + ["\"nope\""]
        #expect(throws: DecodingError.self) {
            try decode("{\(fields),\"ansi\":[\(sixteen.joined(separator: ","))]}")
        }

        fields = fields.replacingOccurrences(of: "\"#000000\"", with: "\"zzz\"")
        let ok = (0..<16).map { _ in "\"#101010\"" }.joined(separator: ",")
        #expect(throws: DecodingError.self) { try decode("{\(fields),\"ansi\":[\(ok)]}") }
    }

    /// The built-in, pinned. Read out of the user's iTerm2 profile
    /// "Default" (dark variants) on 2026-09-03; the point of ccc's default
    /// being *this* set is that a side-by-side against iTerm is a diff
    /// rather than a matter of taste, and that only holds while these
    /// twenty-two values are the profile's.
    @Test func theBuiltInMatchesTheProfileItWasReadFrom() {
        #expect(Theme.iterm.name == "iterm-default-dark")
        #expect(Theme.iterm.background.hex == "#15191F")
        #expect(Theme.iterm.foreground.hex == "#DCDCDC")
        #expect(Theme.iterm.cursor.hex == "#FFFFFF")
        #expect(Theme.iterm.cursorText.hex == "#000000")
        #expect(Theme.iterm.selectionBackground.hex == "#B3D7FF")
        #expect(Theme.iterm.selectionForeground.hex == "#000000")
        #expect(Theme.iterm.ansi.map(\.hex) == [
            "#14191E", "#B43C2A", "#00C200", "#C7C400",
            "#2744C7", "#C040BE", "#00C5C7", "#C7C7C7",
            "#686868", "#DD7975", "#58E790", "#ECE100",
            "#A7ABF2", "#E17EE1", "#60FDFF", "#FFFFFF",
        ])
    }
}
