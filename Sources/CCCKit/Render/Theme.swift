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
/// Two things that look like theme values are deliberately absent:
///
/// - **bold-is-bright** (iTerm's "Use Bright Bold", on in the profile
///   below) promotes bold text from colour *n* to *n+8*. It is a policy,
///   not a colour, and it cannot be done from a `Frame`: the core resolves
///   palette indices to RGB before we see a cell (`render.h`, `..._DATA_
///   FG_COLOR`: "Bold color handling is not applied") so there is no index
///   left to add 8 to. It needs the index carried through the seam first.
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
    /// Selection colours. **Nothing consumes these yet**: `FrameReader`
    /// always builds rows with `selection: nil` and the renderer draws no
    /// selection at all. They are here because they are part of the answer
    /// to "what are my colours", and because the day selection lands it
    /// should reach for the theme rather than invent two more constants.
    public var selectionBackground: Frame.RGB
    public var selectionForeground: Frame.RGB

    /// Exactly sixteen: 0–7 normal, 8–15 bright. Any other count is a
    /// decoding error, never a silently padded array.
    public var ansi: [Frame.RGB]

    public static let ansiCount = 16

    public init(
        name: String,
        background: Frame.RGB, foreground: Frame.RGB,
        cursor: Frame.RGB, cursorText: Frame.RGB,
        selectionBackground: Frame.RGB, selectionForeground: Frame.RGB,
        ansi: [Frame.RGB]
    ) {
        precondition(ansi.count == Self.ansiCount, "a theme carries exactly 16 ANSI colours, got \(ansi.count)")
        self.name = name
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.cursorText = cursorText
        self.selectionBackground = selectionBackground
        self.selectionForeground = selectionForeground
        self.ansi = ansi
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
        case selectionBackground, selectionForeground, ansi
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
            ansi: ansi)
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
    }
}
