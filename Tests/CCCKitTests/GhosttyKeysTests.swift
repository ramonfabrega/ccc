import CCCKit
import Foundation
import Testing

/// What libghostty-vt's key encoder actually emits for each `NamedKey`.
///
/// Every expectation here is a byte sequence the core produced, not one we
/// wished for: where the core disagreed with the obvious guess (shift-enter
/// in legacy mode, home/end) the observed bytes are pinned and the protocol
/// named in a comment. That makes this file the regression net for the
/// "kitty keyboard / shift-enter" item in the six checks (CLAUDE.md), and
/// the place a libghostty bump announces itself.
@Suite struct GhosttyKeysTests {
    /// A terminal that has been fed `setup`, plus an encoder bound to it.
    @MainActor
    private static func keys(after setup: String? = nil) -> (GhosttyHost, GhosttyKeys) {
        let host = GhosttyHost(cols: 20, rows: 4)
        if let setup { host.feed(Data(setup.utf8)) }
        return (host, GhosttyKeys(host: host))
    }

    @MainActor
    private static func encode(_ spec: String, after setup: String? = nil) -> [UInt8] {
        // `GhosttyKeys` holds the host, so the terminal outlives the encode
        // even though nothing here names it again.
        let keys = Self.keys(after: setup).1
        guard let key = NamedKey(spec) else { return [] }
        return Array(keys.encode(key))
    }

    // MARK: 1 — the C0 keys

    @Test @MainActor func c0Keys() {
        #expect(Self.encode("enter") == [0x0d])       // CR, legacy Return (LNM off)
        #expect(Self.encode("escape") == [0x1b])      // ESC
        #expect(Self.encode("tab") == [0x09])         // HT
        // DEL, not BS: DECBKM (backarrow key mode, DEC private 67) is off by
        // default, and encoder.h documents that default as "backspace emits
        // 0x7f". Matches macOS `stty erase ^?`.
        #expect(Self.encode("backspace") == [0x7f])
        #expect(Self.encode("delete") == Array("\u{1b}[3~".utf8))  // CSI 3~, VT220 Remove
        #expect(Self.encode("space") == [0x20])
    }

    // MARK: 2 — DECCKM

    @Test @MainActor func arrowsFollowCursorKeyMode() {
        // Normal mode: CSI final A/B/D/C (ANSI cursor keys).
        #expect(Self.encode("up") == Array("\u{1b}[A".utf8))
        #expect(Self.encode("down") == Array("\u{1b}[B".utf8))
        #expect(Self.encode("left") == Array("\u{1b}[D".utf8))
        #expect(Self.encode("right") == Array("\u{1b}[C".utf8))

        // DECCKM on (CSI ? 1 h): the same finals over SS3.
        let decckm = "\u{1b}[?1h"
        #expect(Self.encode("up", after: decckm) == Array("\u{1b}OA".utf8))
        #expect(Self.encode("down", after: decckm) == Array("\u{1b}OB".utf8))
        #expect(Self.encode("left", after: decckm) == Array("\u{1b}OD".utf8))
        #expect(Self.encode("right", after: decckm) == Array("\u{1b}OC".utf8))

        // The encoder reads the mode off the terminal, so the host agrees.
        let (_, keys) = Self.keys(after: decckm)
        #expect(keys.cursorKeyApplication)
        #expect(Self.keys().1.cursorKeyApplication == false)
    }

    // MARK: 3 — control and text

    @Test @MainActor func controlAndText() {
        #expect(Self.encode("ctrl-c") == [0x03])   // ETX
        #expect(Self.encode("ctrl-z") == [0x1a])   // SUB
        #expect(Self.encode("ctrl-u") == [0x15])   // NAK
        #expect(Self.encode("a") == [0x61])
        #expect(Self.encode("shift-a") == [0x41])
        // Shift picks the US layout's shifted text, so `shift-1` and `!` are
        // the same keypress spelled two ways.
        #expect(Self.encode("shift-1") == [0x21])
        #expect(Self.encode("!") == [0x21])
        // Option is Alt (macos-option-as-alt TRUE, see GhosttyKeys): ESC
        // prefix, DEC private 1036.
        #expect(Self.encode("opt-b") == Array("\u{1b}b".utf8))
        // Command/Super has no terminal encoding — the app owns ⌘.
        #expect(Self.encode("cmd-a") == [])
    }

    // MARK: 4 — kitty keyboard / shift-enter (six checks)

    @Test @MainActor func kittyKeyboardAndShiftEnter() {
        // Legacy, no kitty flags. NOT a bare CR: the core reaches for the
        // xterm modifyOtherKeys "CSI 27 ; mods ; codepoint ~" form so that
        // shift+enter stays distinguishable from enter. 27 is the form's own
        // introducer, 2 is shift, 13 is CR.
        #expect(Self.encode("shift-enter") == Array("\u{1b}[27;2;13~".utf8))
        #expect(Self.encode("enter") == [0x0d])

        // Push the disambiguate flag (CSI > 1 u). Now shift+enter is kitty
        // CSI-u: ESC [ 13 ; 2 u — codepoint 13, modifier 2 (shift).
        let kitty = "\u{1b}[>1u"
        #expect(Self.encode("shift-enter", after: kitty) == Array("\u{1b}[13;2u".utf8))
        // Unmodified enter stays legacy CR even with the flag set.
        #expect(Self.encode("enter", after: kitty) == [0x0d])
        // ctrl-c becomes CSI-u too: 99 is 'c', 5 is ctrl.
        #expect(Self.encode("ctrl-c", after: kitty) == Array("\u{1b}[99;5u".utf8))
        // Escape is the disambiguation this flag exists for: ESC [ 27 u.
        #expect(Self.encode("escape", after: kitty) == Array("\u{1b}[27u".utf8))
        // Plain text keys stay plain text.
        #expect(Self.encode("a", after: kitty) == [0x61])
        // Backspace stays 0x7f — disambiguate alone does not move it.
        #expect(Self.encode("backspace", after: kitty) == [0x7f])
        // F1 loses the SS3 form under kitty: CSI P, not SS3 P.
        #expect(Self.encode("f1", after: kitty) == Array("\u{1b}[P".utf8))

        let (_, keys) = Self.keys(after: kitty)
        #expect(keys.kittyFlags == 1)          // GHOSTTY_KITTY_KEY_DISAMBIGUATE
        #expect(Self.keys().1.kittyFlags == 0)
    }

    // MARK: 5 — function and navigation keys

    @Test @MainActor func functionAndNavigationKeys() {
        // F1-F4 are SS3 P/Q/R/S (VT100 PF1-PF4); F5+ are CSI n ~ with the
        // xterm numbering that skips 16 and 22.
        #expect(Self.encode("f1") == Array("\u{1b}OP".utf8))
        #expect(Self.encode("f2") == Array("\u{1b}OQ".utf8))
        #expect(Self.encode("f3") == Array("\u{1b}OR".utf8))
        #expect(Self.encode("f4") == Array("\u{1b}OS".utf8))
        #expect(Self.encode("f5") == Array("\u{1b}[15~".utf8))
        #expect(Self.encode("f12") == Array("\u{1b}[24~".utf8))
        // Home/End are the xterm CSI H / CSI F forms, not CSI 1~ / CSI 4~.
        #expect(Self.encode("home") == Array("\u{1b}[H".utf8))
        #expect(Self.encode("end") == Array("\u{1b}[F".utf8))
        // ...and they follow DECCKM into SS3, same as the arrows.
        #expect(Self.encode("home", after: "\u{1b}[?1h") == Array("\u{1b}OH".utf8))
        #expect(Self.encode("end", after: "\u{1b}[?1h") == Array("\u{1b}OF".utf8))
        // PageUp/PageDown are VT220 CSI 5~ / CSI 6~ in both modes.
        #expect(Self.encode("pageup") == Array("\u{1b}[5~".utf8))
        #expect(Self.encode("pagedown") == Array("\u{1b}[6~".utf8))
    }

    // MARK: 6 — the seam

    @Test @MainActor func pressDeliversThroughOnOutput() {
        let host = GhosttyHost(cols: 20, rows: 4)
        var sent = Data()
        host.onOutput = { sent.append($0) }
        #expect(host.press(NamedKey("ctrl-z")!))
        #expect(Array(sent) == [0x1a])

        // The host's press path sees the same negotiated state the encoder
        // does: DECCKM on moves the arrow it writes to the child.
        sent = Data()
        host.feed(Data("\u{1b}[?1h".utf8))
        #expect(host.press(NamedKey("up")!))
        #expect(Array(sent) == Array("\u{1b}OA".utf8))

        // Nothing to send is `false`, and nothing reaches the child.
        sent = Data()
        #expect(host.press(NamedKey("cmd-a")!) == false)
        #expect(sent.isEmpty)
    }
}
