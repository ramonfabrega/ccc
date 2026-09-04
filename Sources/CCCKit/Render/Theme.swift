import Foundation
import os

/// The pane's colours.
///
/// **A terminal theme is 22 values, not 256.** Sixteen named ANSI colours
/// (`SGR 30–37` / `90–97`, and `SGR 38;5;n` for n < 16) plus six specials
/// that no escape sequence can name. Palette slots 16–255 are arithmetic
/// rather than a choice — a 6×6×6 cube on the axis `n*40+55` and a 24-step
/// grey ramp on `(n-232)*10+8` — and applications hardcode assumptions
/// about what they mean, so nothing here writes them: `GhosttyHost` seeds
/// all 256 from the core's own `ghostty_color_palette_default` and
/// overwrites the first sixteen, which keeps our cube identical to the
/// core's by construction rather than by a copied formula.
///
/// **bold-is-bright is a policy, not a colour** (iTerm's "Use Bright Bold",
/// on in the profile below): bold text wearing colour *n* paints colour
/// *n+8*. It lives here as a `Bool`, not as eight more values — the eight
/// it promotes into are `ansi[8...15]`, already above.
///
/// It was recorded here until 2026-09-03 as *impossible* from a `Frame`,
/// on the grounds that the core resolves palette indices to RGB before we
/// see a cell (`render.h`, `..._DATA_FG_COLOR`: "Bold color handling is not
/// applied") so no index is left to add 8 to. That was wrong about one word:
/// the *resolved colour* has no index, but `GhosttyStyle.fg_color` is a
/// tagged union and `FrameReader` was already reading that struct for `bold`
/// itself, throwing the colour half away. Nothing had to cross the seam that
/// was not crossing it (`Frame.Cell.fgPalette`, item 12c).
///
/// One thing that looks like a theme value is still deliberately absent:
///
/// - **a light variant.** The profile below has one; the user does not use
///   it and nothing else in ccc has a light mode, so building the switch
///   now would be a second untested path. `Codable` and `CCC_THEME` are
///   what make it a later edit rather than a later rewrite.
public struct Theme: Sendable, Equatable {
    /// Names the source, not the mood — this string is what `ccc theme`
    /// prints when someone asks where the colours came from.
    public var name: String

    /// The default background: what a cell with no explicit colour paints,
    /// and what a program is told when it asks (`OSC 11`), which is how a
    /// TUI decides whether it is running on a dark ground.
    public var background: Frame.RGB
    /// The default foreground (`OSC 10`).
    public var foreground: Frame.RGB
    /// The cursor's own colour (`OSC 12`).
    public var cursor: Frame.RGB
    /// The glyph *under* a block cursor. Not an `OSC`-addressable colour —
    /// the terminal picks it, and iTerm's pick is an explicit value rather
    /// than an inversion of the cell.
    public var cursorText: Frame.RGB
    /// Selection colours (item 12b). A selected cell paints these two and
    /// nothing else — not an inversion of what it was wearing, which is
    /// what v1 did — so the answer to "what colour is a selected cell" is
    /// the theme's, whatever SGR the child had set. `Theme.selection`
    /// below is the pair the renderer and the colour oracle both resolve
    /// through; the core never sees them (`GhosttyHost.install`).
    public var selectionBackground: Frame.RGB
    public var selectionForeground: Frame.RGB

    /// Exactly sixteen: 0–7 normal, 8–15 bright. Any other count is a
    /// decoding error, never a silently padded array.
    public var ansi: [Frame.RGB]

    /// bold-is-bright (item 12c). True by default because the profile these
    /// colours were read out of has "Use Bright Bold" on, so the built-in
    /// theme matches the terminal it was measured against — the same reason
    /// the sixteen are what they are. The knob exists because it is a policy
    /// and a terminal is allowed to disagree; `false` is a pane whose bold
    /// text is bold and nothing else.
    public var boldIsBright: Bool

    public static let ansiCount = 16

    public init(
        name: String,
        background: Frame.RGB, foreground: Frame.RGB,
        cursor: Frame.RGB, cursorText: Frame.RGB,
        selectionBackground: Frame.RGB, selectionForeground: Frame.RGB,
        ansi: [Frame.RGB],
        boldIsBright: Bool = true
    ) {
        precondition(ansi.count == Self.ansiCount, "a theme carries exactly 16 ANSI colours, got \(ansi.count)")
        self.boldIsBright = boldIsBright
        self.name = name
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.cursorText = cursorText
        self.selectionBackground = selectionBackground
        self.selectionForeground = selectionForeground
        self.ansi = ansi
    }

    /// The pair a selected cell paints in, in the shape colour resolution
    /// wants it. One value rather than two loose colours because it travels
    /// as one: `RunMerge.resolvedColors` takes it non-nil for exactly the
    /// cells inside a row's `selection` range, and nil for every other cell.
    public var selection: SelectionColors {
        SelectionColors(foreground: selectionForeground, background: selectionBackground)
    }

    /// The bold-is-bright policy in the shape colour resolution wants it, or
    /// nil when the policy is off — the same nil-means-inert shape as
    /// `selection`, so `RunMerge.resolvedColors` reads as one rule per
    /// optional rather than one rule per flag.
    public var bold: BoldColors? {
        boldIsBright ? BoldColors(bright: Array(ansi[8..<Self.ansiCount])) : nil
    }
}

/// What bold-is-bright promotes into: the eight bright ANSI colours, indexed
/// by the *normal* slot they replace, so slot 0–7 maps to `bright[n]`.
///
/// Eight rather than the whole 256-entry palette, because that is the whole
/// of the policy — slots 8–15 are already bright and 16–255 are the xterm
/// cube, which nothing promotes. It also means the core's palette never has
/// to cross the seam: these eight are the theme's own, and the theme is what
/// seeded the core (`GhosttyHost.install`), so the two cannot disagree.
public struct BoldColors: Sendable, Equatable {
    public var bright: [Frame.RGB]
    public init(bright: [Frame.RGB]) {
        precondition(bright.count == 8, "bold-is-bright promotes into exactly 8 colours, got \(bright.count)")
        self.bright = bright
    }
}

/// What a selected cell paints. Non-nil at a call site means "this cell is
/// selected"; the colours ride along so no layer below the theme has to know
/// where they came from.
public struct SelectionColors: Sendable, Equatable {
    public var foreground: Frame.RGB
    public var background: Frame.RGB
    public init(foreground: Frame.RGB, background: Frame.RGB) {
        self.foreground = foreground
        self.background = background
    }
}

// MARK: - The built-in

extension Theme {
    /// The user's iTerm2 profile "Default", dark variants, read out of
    /// `~/Library/Preferences/com.googlecode.iterm2.plist` on 2026-09-03.
    ///
    /// It is the default because it is the only palette whose correctness
    /// can be *checked* rather than argued: put the two windows side by
    /// side on the same content and the residual difference is no longer
    /// the theme, it is colour management (`MetalPaneView` sets no
    /// `colorspace`, and studio's display answers `NSScreen.colorSpace`
    /// with its own EDID profile, "Mi monitor" — neither sRGB nor P3).
    /// Measuring that residual is the point of shipping this first.
    ///
    /// The sixteen are shared between the profile's light and dark
    /// variants; only the specials differ, and these are the dark ones.
    public static let iterm = Theme(
        name: "iterm-default-dark",
        background: Frame.RGB(0x15, 0x19, 0x1F),
        foreground: Frame.RGB(0xDC, 0xDC, 0xDC),
        cursor: Frame.RGB(0xFF, 0xFF, 0xFF),
        cursorText: Frame.RGB(0x00, 0x00, 0x00),
        selectionBackground: Frame.RGB(0xB3, 0xD7, 0xFF),
        selectionForeground: Frame.RGB(0x00, 0x00, 0x00),
        ansi: [
            Frame.RGB(0x14, 0x19, 0x1E),   // 0  black
            Frame.RGB(0xB4, 0x3C, 0x2A),   // 1  red
            Frame.RGB(0x00, 0xC2, 0x00),   // 2  green
            Frame.RGB(0xC7, 0xC4, 0x00),   // 3  yellow
            Frame.RGB(0x27, 0x44, 0xC7),   // 4  blue
            Frame.RGB(0xC0, 0x40, 0xBE),   // 5  magenta
            Frame.RGB(0x00, 0xC5, 0xC7),   // 6  cyan
            Frame.RGB(0xC7, 0xC7, 0xC7),   // 7  white
            Frame.RGB(0x68, 0x68, 0x68),   // 8  bright black
            Frame.RGB(0xDD, 0x79, 0x75),   // 9  bright red
            Frame.RGB(0x58, 0xE7, 0x90),   // 10 bright green
            Frame.RGB(0xEC, 0xE1, 0x00),   // 11 bright yellow
            Frame.RGB(0xA7, 0xAB, 0xF2),   // 12 bright blue
            Frame.RGB(0xE1, 0x7E, 0xE1),   // 13 bright magenta
            Frame.RGB(0x60, 0xFD, 0xFF),   // 14 bright cyan
            Frame.RGB(0xFF, 0xFF, 0xFF),   // 15 bright white
        ]
    )

    /// What the pane, the headless renderer and `ccc theme` all use.
    ///
    /// `CCC_THEME` points at a JSON file in the shape `ccc theme --json`
    /// prints, which is the whole knob: edit hex, relaunch, compare. Read
    /// once per process — a theme that changed under a running pane would
    /// have to invalidate the core's palette and every glyph batch, and
    /// nothing asks for that yet. A file that will not parse is named on
    /// stderr and the built-in is used; a broken theme must not be a
    /// terminal that will not open.
    public static let active: Theme = {
        let env = ProcessInfo.processInfo.environment["CCC_THEME"] ?? ""
        guard !env.isEmpty else { return .iterm }
        let path = (env as NSString).expandingTildeInPath
        do {
            return try load(from: URL(filePath: path))
        } catch {
            Logger(subsystem: "app.cuanto.ccc", category: "Theme")
                .error("CCC_THEME=\(path, privacy: .public) not used: \(error.localizedDescription, privacy: .public)")
            return .iterm
        }
    }()

    public static func load(from url: URL) throws -> Theme {
        try JSONDecoder().decode(Theme.self, from: Data(contentsOf: url))
    }
}

// MARK: - Hex

extension Frame.RGB {
    public var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    /// `#RRGGBB`, `#RGB`, or either without the `#`. Anything else is nil
    /// rather than a guess — a typo in a theme file should be named, not
    /// rendered.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }
}

/// One colour, one `#RRGGBB` string — **the same spelling `ccc pixel` and
/// `ccc theme` print**, so a colour an agent reads out of `ccc snapshot
/// --color --json` can be handed straight to `ccc pixel --expect` with no
/// conversion. That is the whole point of the notation: the headless oracle
/// and the screen oracle have to be comparable by string equality, or an
/// agent has to trust arithmetic it cannot see.
extension Frame.RGB: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let rgb = Frame.RGB(hex: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "\(raw.debugDescription) is not a #RRGGBB colour")
        }
        self = rgb
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }
}

// MARK: - Codable, as hex strings

extension Theme: Codable {
    private enum Key: String, CodingKey {
        case name, background, foreground, cursor, cursorText
        case selectionBackground, selectionForeground, ansi, boldIsBright
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        func colour(_ key: Key) throws -> Frame.RGB {
            let raw = try c.decode(String.self, forKey: key)
            guard let rgb = Frame.RGB(hex: raw) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key, in: c, debugDescription: "\(raw.debugDescription) is not a #RRGGBB colour")
            }
            return rgb
        }
        let rawAnsi = try c.decode([String].self, forKey: .ansi)
        guard rawAnsi.count == Self.ansiCount else {
            throw DecodingError.dataCorruptedError(
                forKey: .ansi, in: c,
                debugDescription: "a theme carries exactly \(Self.ansiCount) ANSI colours, got \(rawAnsi.count)")
        }
        let ansi = try rawAnsi.enumerated().map { index, raw -> Frame.RGB in
            guard let rgb = Frame.RGB(hex: raw) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .ansi, in: c,
                    debugDescription: "ansi[\(index)] \(raw.debugDescription) is not a #RRGGBB colour")
            }
            return rgb
        }
        self.init(
            name: try c.decode(String.self, forKey: .name),
            background: try colour(.background), foreground: try colour(.foreground),
            cursor: try colour(.cursor), cursorText: try colour(.cursorText),
            selectionBackground: try colour(.selectionBackground),
            selectionForeground: try colour(.selectionForeground),
            ansi: ansi,
            // Absent means on: a theme file written before 12c described a
            // pane that already promoted bold, so reading it as `false`
            // would change how an existing file renders.
            boldIsBright: try c.decodeIfPresent(Bool.self, forKey: .boldIsBright) ?? true)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(name, forKey: .name)
        try c.encode(background.hex, forKey: .background)
        try c.encode(foreground.hex, forKey: .foreground)
        try c.encode(cursor.hex, forKey: .cursor)
        try c.encode(cursorText.hex, forKey: .cursorText)
        try c.encode(selectionBackground.hex, forKey: .selectionBackground)
        try c.encode(selectionForeground.hex, forKey: .selectionForeground)
        try c.encode(ansi.map(\.hex), forKey: .ansi)
        try c.encode(boldIsBright, forKey: .boldIsBright)
    }
}
