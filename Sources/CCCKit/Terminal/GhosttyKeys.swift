import Foundation
import GhosttyVt

/// Key encoding over libghostty-vt's own encoder — CLAUDE.md's "keys are the
/// core's job. Never hand-roll escape sequences." A `NamedKey` becomes a
/// `GhosttyKeyEvent` (physical key + mods + the layout text a US keyboard
/// would produce) and the core turns that into the bytes the child receives,
/// with the same rules a real keypress would take: legacy vs kitty CSI-u,
/// DECCKM application cursor keys, DECBKM backspace, alt-as-escape.
///
/// Options are refreshed from the terminal before every encode, so the
/// encoding tracks what the child negotiated rather than what we assumed.
@MainActor
public final class GhosttyKeys {
    /// Non-owning: the terminal belongs to the host that made it. We only
    /// read its modes.
    private let terminal: GhosttyTerminal?
    /// Strong, and deliberately so when we were built from a host: the
    /// terminal handle above is raw memory the host frees in its deinit, so
    /// an encoder that outlives its host would read freed memory on the next
    /// `refreshOptions()`. Nil when the caller passed a bare handle and owns
    /// that ordering itself. `GhosttyHost.press` builds the terminal-only
    /// form, so the host → encoder edge stays acyclic.
    private let owner: AnyObject?
    private var encoder: GhosttyKeyEncoder?
    private var event: GhosttyKeyEvent?

    public private(set) var lastError: String?

    public init(terminal: GhosttyTerminal?, owner: AnyObject? = nil) {
        self.terminal = terminal
        self.owner = owner
        var e: GhosttyKeyEncoder?
        if ghostty_key_encoder_new(nil, &e) == GHOSTTY_SUCCESS, let e {
            encoder = e
        } else {
            lastError = "ghostty_key_encoder_new failed"
        }
        var ev: GhosttyKeyEvent?
        if ghostty_key_event_new(nil, &ev) == GHOSTTY_SUCCESS, let ev {
            event = ev
        } else {
            lastError = "ghostty_key_event_new failed"
        }
    }

    /// The encoder for a host's terminal. The host keeps owning the handle.
    public convenience init(host: GhosttyHost) {
        self.init(terminal: host.terminal, owner: host)
    }

    isolated deinit {
        if let event { ghostty_key_event_free(event) }
        if let encoder { ghostty_key_encoder_free(encoder) }
    }

    // MARK: options

    /// Pull the encoder's options out of the terminal's live state.
    ///
    /// `ghostty_key_encoder_setopt_from_terminal` is the core's own sync and
    /// covers every mode the child can negotiate in one call: kitty keyboard
    /// flags (`GHOSTTY_TERMINAL_DATA_KITTY_KEYBOARD_FLAGS` →
    /// `OPT_KITTY_FLAGS`), DECCKM mode 1 → `OPT_CURSOR_KEY_APPLICATION`,
    /// DECKPAM mode 66 → `OPT_KEYPAD_KEY_APPLICATION`, mode 1035 →
    /// `OPT_IGNORE_KEYPAD_WITH_NUMLOCK`, mode 1036 → `OPT_ALT_ESC_PREFIX`,
    /// and xterm modifyOtherKeys → `OPT_MODIFY_OTHER_KEYS_STATE_2`. Reading
    /// each `GHOSTTY_TERMINAL_DATA_MODE` by hand and re-setting it would be
    /// the same values with a second copy of the mapping to keep in sync, so
    /// we let the core do it (`kittyFlags` / `mode(_:)` below stay for
    /// diagnostics and tests).
    ///
    /// Two things that call cannot know:
    /// - `OPT_MACOS_OPTION_AS_ALT`, which it resets to `FALSE` every time. We
    ///   set `GHOSTTY_OPTION_AS_ALT_TRUE`: a `NamedKey` with `option` is an
    ///   explicit request for Alt (`ccc send --key opt-b`, or an AppKit event
    ///   we already decided is Alt), never a raw physical Option press that
    ///   might be composing "∫". Dropping it would silently swallow the
    ///   modifier the caller asked for. A GUI pane that wants macOS's
    ///   compose behaviour resolves option-as-alt before it builds the
    ///   `NamedKey`, not here.
    /// - `OPT_BACKARROW_KEY_MODE` (DECBKM, mode 67), which the sync leaves at
    ///   the core's default `false` → backspace emits 0x7f. That is the
    ///   correct macOS default and matches `stty erase ^?`.
    private func refreshOptions() {
        guard let encoder else { return }
        if let terminal { ghostty_key_encoder_setopt_from_terminal(encoder, terminal) }
        var optionAsAlt = GHOSTTY_OPTION_AS_ALT_TRUE
        ghostty_key_encoder_setopt(encoder, GHOSTTY_KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT, &optionAsAlt)
    }

    /// The kitty keyboard flags the child has pushed, straight from the
    /// terminal. Diagnostics and tests; the encoder gets its copy through
    /// `refreshOptions()`.
    public var kittyFlags: UInt8 {
        guard let terminal else { return 0 }
        var flags: GhosttyKittyKeyFlags = 0
        guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_KITTY_KEYBOARD_FLAGS, &flags) == GHOSTTY_SUCCESS else { return 0 }
        return flags
    }

    /// Read one DEC/ANSI mode (`GHOSTTY_MODE_DECCKM`, …). The mode getter is
    /// in/out: `mode` is set by the caller, `value` comes back.
    public func mode(_ mode: GhosttyMode) -> Bool {
        guard let terminal else { return false }
        var config = GhosttyTerminalModeConfig(mode: mode, value: false)
        guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_MODE, &config) == GHOSTTY_SUCCESS else { return false }
        return config.value
    }

    /// DECCKM (mode 1): arrows send SS3 (`ESC O A`) instead of CSI.
    ///
    /// Header surprise: the `GHOSTTY_MODE_*` constants in modes.h are macros
    /// wrapping the `ghostty_mode_new` static inline, so Swift reports them
    /// "unavailable: structure not supported" and they are not in scope. Call
    /// the same inline directly — value, plus false for "DEC private".
    public var cursorKeyApplication: Bool { mode(ghostty_mode_new(1, false)) }

    // MARK: encoding

    /// The bytes the child should receive for one press of `key`. Empty when
    /// the core produces nothing (a bare modifier, an unmapped key).
    public func encode(_ key: NamedKey) -> Data {
        guard encoder != nil, let event else { return Data() }
        refreshOptions()

        // Reset every field: the event is reused across presses.
        ghostty_key_event_set_action(event, GHOSTTY_KEY_ACTION_PRESS)
        ghostty_key_event_set_consumed_mods(event, 0)
        ghostty_key_event_set_composing(event, false)
        ghostty_key_event_set_utf8(event, nil, 0)
        ghostty_key_event_set_unshifted_codepoint(event, 0)
        ghostty_key_event_set_mods(event, mods(for: key))

        if let base = key.base {
            ghostty_key_event_set_key(event, Self.key(for: base))
            // Space is the one base key with real layout text; the rest are
            // C0 or function keys, which event.h says to leave NULL so the
            // encoder works from the logical key.
            if base == .space {
                ghostty_key_event_set_unshifted_codepoint(event, 0x20)
                return withText(" ") { encodeCurrent() }
            }
            return encodeCurrent()
        }

        guard let character = key.character else { return Data() }
        let (physical, unshifted) = Self.key(for: character)
        ghostty_key_event_set_key(event, physical)
        ghostty_key_event_set_unshifted_codepoint(event, unshifted)
        // event.h: utf8 is the layout text BEFORE any ctrl/meta transform,
        // so ctrl-c carries "c" and the encoder makes the 0x03.
        return withText(Self.text(for: character, shift: key.shift)) { encodeCurrent() }
    }

    private func withText(_ text: String, _ body: () -> Data) -> Data {
        guard let event else { return Data() }
        // The event does NOT own the pointer, so it must outlive the encode.
        let bytes = Array(text.utf8)
        let out = bytes.withUnsafeBufferPointer { buf -> Data in
            buf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buf.count) { ptr in
                ghostty_key_event_set_utf8(event, ptr, buf.count)
                return body()
            }
        }
        ghostty_key_event_set_utf8(event, nil, 0)
        return out
    }

    /// One `ghostty_key_encoder_encode` with a stack-sized buffer; on
    /// OUT_OF_SPACE `written` carries the size the core needs, so grow to it
    /// and retry exactly once.
    private func encodeCurrent() -> Data {
        guard let encoder, let event else { return Data() }
        var buffer = [CChar](repeating: 0, count: 128)
        var written = 0
        var result = buffer.withUnsafeMutableBufferPointer { buf in
            ghostty_key_encoder_encode(encoder, event, buf.baseAddress, buf.count, &written)
        }
        if result == GHOSTTY_OUT_OF_SPACE {
            buffer = [CChar](repeating: 0, count: max(written, 256))
            result = buffer.withUnsafeMutableBufferPointer { buf in
                ghostty_key_encoder_encode(encoder, event, buf.baseAddress, buf.count, &written)
            }
        }
        guard result == GHOSTTY_SUCCESS, written > 0 else { return Data() }
        return buffer.prefix(written).withUnsafeBufferPointer {
            Data(bytes: $0.baseAddress!, count: written)
        }
    }

    private func mods(for key: NamedKey) -> GhosttyMods {
        var mods: GhosttyMods = 0
        if key.shift { mods |= GhosttyMods(GHOSTTY_MODS_SHIFT) }
        if key.control { mods |= GhosttyMods(GHOSTTY_MODS_CTRL) }
        if key.option { mods |= GhosttyMods(GHOSTTY_MODS_ALT) }
        if key.command { mods |= GhosttyMods(GHOSTTY_MODS_SUPER) }
        return mods
    }

    // MARK: key tables

    private static func key(for base: NamedKey.Base) -> GhosttyKey {
        switch base {
        case .enter: return GHOSTTY_KEY_ENTER
        case .escape: return GHOSTTY_KEY_ESCAPE
        case .tab: return GHOSTTY_KEY_TAB
        case .backspace: return GHOSTTY_KEY_BACKSPACE
        case .delete: return GHOSTTY_KEY_DELETE
        case .space: return GHOSTTY_KEY_SPACE
        case .up: return GHOSTTY_KEY_ARROW_UP
        case .down: return GHOSTTY_KEY_ARROW_DOWN
        case .left: return GHOSTTY_KEY_ARROW_LEFT
        case .right: return GHOSTTY_KEY_ARROW_RIGHT
        case .home: return GHOSTTY_KEY_HOME
        case .end: return GHOSTTY_KEY_END
        case .pageup: return GHOSTTY_KEY_PAGE_UP
        case .pagedown: return GHOSTTY_KEY_PAGE_DOWN
        case .f1: return GHOSTTY_KEY_F1
        case .f2: return GHOSTTY_KEY_F2
        case .f3: return GHOSTTY_KEY_F3
        case .f4: return GHOSTTY_KEY_F4
        case .f5: return GHOSTTY_KEY_F5
        case .f6: return GHOSTTY_KEY_F6
        case .f7: return GHOSTTY_KEY_F7
        case .f8: return GHOSTTY_KEY_F8
        case .f9: return GHOSTTY_KEY_F9
        case .f10: return GHOSTTY_KEY_F10
        case .f11: return GHOSTTY_KEY_F11
        case .f12: return GHOSTTY_KEY_F12
        }
    }

    /// The layout text the key produces. `shift-a` is "A" and `shift-1` is
    /// "!" — the same US layout the physical-key table assumes, so the two
    /// spellings of one keypress (`!` and `shift-1`) encode identically.
    private static func text(for character: Character, shift: Bool) -> String {
        guard shift else { return String(character) }
        if character.isLowercase { return String(character).uppercased() }
        let usShifted: [Character: Character] = [
            "1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
            "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
            "`": "~", "-": "_", "=": "+", "[": "{", "]": "}",
            "\\": "|", ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?",
        ]
        return String(usShifted[character] ?? character)
    }

    /// Physical key + unshifted codepoint for a character, US layout — the
    /// keys are W3C `KeyboardEvent.code` values, which are layout-independent
    /// positions, so this table is exactly "where is this character on a US
    /// keyboard". Anything not on it goes out as `UNIDENTIFIED` with the text
    /// still set, which is what the core wants for a layout it cannot place.
    private static func key(for character: Character) -> (GhosttyKey, UInt32) {
        let scalars = character.unicodeScalars
        let codepoint = scalars.count == 1 ? scalars.first!.value : 0

        if let ascii = character.asciiValue {
            switch ascii {
            case UInt8(ascii: "a")...UInt8(ascii: "z"):
                let key = GhosttyKey(rawValue: GHOSTTY_KEY_A.rawValue + Int32(ascii - UInt8(ascii: "a")))
                return (key, UInt32(ascii))
            case UInt8(ascii: "A")...UInt8(ascii: "Z"):
                let lower = ascii + 0x20
                let key = GhosttyKey(rawValue: GHOSTTY_KEY_A.rawValue + Int32(lower - UInt8(ascii: "a")))
                return (key, UInt32(lower))
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                let key = GhosttyKey(rawValue: GHOSTTY_KEY_DIGIT_0.rawValue + Int32(ascii - UInt8(ascii: "0")))
                return (key, UInt32(ascii))
            default: break
            }
        }

        // Punctuation, unshifted and shifted, on a US layout. The second
        // element is the UNSHIFTED codepoint the kitty protocol reports.
        switch character {
        case "`": return (GHOSTTY_KEY_BACKQUOTE, 0x60)
        case "~": return (GHOSTTY_KEY_BACKQUOTE, 0x60)
        case "\\": return (GHOSTTY_KEY_BACKSLASH, 0x5c)
        case "|": return (GHOSTTY_KEY_BACKSLASH, 0x5c)
        case "[": return (GHOSTTY_KEY_BRACKET_LEFT, 0x5b)
        case "{": return (GHOSTTY_KEY_BRACKET_LEFT, 0x5b)
        case "]": return (GHOSTTY_KEY_BRACKET_RIGHT, 0x5d)
        case "}": return (GHOSTTY_KEY_BRACKET_RIGHT, 0x5d)
        case ",": return (GHOSTTY_KEY_COMMA, 0x2c)
        case "<": return (GHOSTTY_KEY_COMMA, 0x2c)
        case ".": return (GHOSTTY_KEY_PERIOD, 0x2e)
        case ">": return (GHOSTTY_KEY_PERIOD, 0x2e)
        case "=": return (GHOSTTY_KEY_EQUAL, 0x3d)
        case "+": return (GHOSTTY_KEY_EQUAL, 0x3d)
        case "-": return (GHOSTTY_KEY_MINUS, 0x2d)
        case "_": return (GHOSTTY_KEY_MINUS, 0x2d)
        case "'": return (GHOSTTY_KEY_QUOTE, 0x27)
        case "\"": return (GHOSTTY_KEY_QUOTE, 0x27)
        case ";": return (GHOSTTY_KEY_SEMICOLON, 0x3b)
        case ":": return (GHOSTTY_KEY_SEMICOLON, 0x3b)
        case "/": return (GHOSTTY_KEY_SLASH, 0x2f)
        case "?": return (GHOSTTY_KEY_SLASH, 0x2f)
        case " ": return (GHOSTTY_KEY_SPACE, 0x20)
        case "!": return (GHOSTTY_KEY_DIGIT_1, 0x31)
        case "@": return (GHOSTTY_KEY_DIGIT_2, 0x32)
        case "#": return (GHOSTTY_KEY_DIGIT_3, 0x33)
        case "$": return (GHOSTTY_KEY_DIGIT_4, 0x34)
        case "%": return (GHOSTTY_KEY_DIGIT_5, 0x35)
        case "^": return (GHOSTTY_KEY_DIGIT_6, 0x36)
        case "&": return (GHOSTTY_KEY_DIGIT_7, 0x37)
        case "*": return (GHOSTTY_KEY_DIGIT_8, 0x38)
        case "(": return (GHOSTTY_KEY_DIGIT_9, 0x39)
        case ")": return (GHOSTTY_KEY_DIGIT_0, 0x30)
        default: return (GHOSTTY_KEY_UNIDENTIFIED, codepoint)
        }
    }
}
