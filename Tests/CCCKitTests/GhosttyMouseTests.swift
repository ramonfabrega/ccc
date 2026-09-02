import CCCKit
import Foundation
import Testing

/// What libghostty-vt's mouse encoder actually emits, pinned byte for byte.
///
/// Same rule as `GhosttyKeysTests`: every expectation here is a sequence the
/// core produced, not one we wished for, and each carries the protocol it
/// belongs to. This is the encoder half of check 3 ("mouse scroll in the
/// transcript", docs/CHECKS.md) and the place a libghostty bump announces a
/// change in mouse behaviour.
@Suite struct GhosttyMouseTests {
    /// A 40×10 terminal that has been fed `setup`, plus a mouse encoder
    /// bound to it. The encoder retains the host, so the terminal outlives
    /// the encode even where the test never names the host again.
    @MainActor
    private static func mouse(after setup: String? = nil) -> GhosttyMouse {
        let host = GhosttyHost(cols: 40, rows: 10)
        if let setup { host.feed(Data(setup.utf8)) }
        return GhosttyMouse(host: host)
    }

    /// DEC 1000 (normal tracking: press + release, no motion) with DEC 1006
    /// (SGR output format) — what a modern TUI negotiates.
    private static let sgrTracking = "\u{1b}[?1000h\u{1b}[?1006h"

    // MARK: 1 — tracking off is silence, not a dropped event

    @Test @MainActor func trackingOffEncodesNothing() {
        let mouse = Self.mouse()
        #expect(mouse.isTracking == false)
        // `shouldReport` returns false for tracking mode `.none`
        // (input/mouse_encode.zig), so the core writes zero bytes and
        // returns success. Empty Data is the correct answer.
        #expect(mouse.encode(button: .left, action: .press, col: 5, row: 3) == Data())
        #expect(mouse.encode(button: .left, action: .release, col: 5, row: 3) == Data())
    }

    // MARK: 2 — SGR press and release

    @Test @MainActor func sgrPressAndRelease() {
        let mouse = Self.mouse(after: Self.sgrTracking)
        #expect(mouse.isTracking == true)

        // SGR mouse (DEC 1006): CSI < Cb ; Cx ; Cy M for a press. Button
        // code 0 = left; coordinates are 1-based, so our zero-based cell
        // (col 5, row 3) reports as 6;4.
        #expect(mouse.encode(button: .left, action: .press, col: 5, row: 3)
                == Data("\u{1b}[<0;6;4M".utf8))
        // Release is the same report with a lowercase final `m` — the whole
        // point of SGR over X10, which loses the button identity on release.
        #expect(mouse.encode(button: .left, action: .release, col: 5, row: 3)
                == Data("\u{1b}[<0;6;4m".utf8))
    }

    // MARK: 3 — wheel

    @Test @MainActor func wheelUnderSgrTracking() {
        let mouse = Self.mouse(after: Self.sgrTracking)
        // Wheel up is X11 button 4, whose SGR code is 64 (the 0x40 bit marks
        // the wheel class). Cell (1,1) → 2;2, and a wheel is a press only.
        #expect(mouse.wheel(deltaLines: 1, col: 1, row: 1) == Data("\u{1b}[<64;2;2M".utf8))
        #expect(mouse.wantsArrowFallback == false)
        // Wheel down is button 5 → code 65.
        #expect(mouse.wheel(deltaLines: -1, col: 1, row: 1) == Data("\u{1b}[<65;2;2M".utf8))
        // N lines is N reports, exactly as a real mouse sends them.
        #expect(mouse.wheel(deltaLines: 3, col: 1, row: 1)
                == Data(String(repeating: "\u{1b}[<64;2;2M", count: 3).utf8))
    }

    // MARK: 4 — alternate scroll is NOT in the core

    @Test @MainActor func alternateScrollFallsBackToArrows() {
        // DEC 1049 (alt screen) + DEC 1007 (alternate scroll; Ghostty's
        // default is already on, modes.zig:316 — feeding it makes the intent
        // explicit rather than changing anything).
        let mouse = Self.mouse(after: "\u{1b}[?1049h\u{1b}[?1007h")
        #expect(mouse.isAlternateScreen == true)
        #expect(mouse.alternateScroll == true)
        #expect(mouse.isTracking == false)

        // Observed: the core emits NOTHING. `ghostty_mouse_encoder_*` has no
        // alternate-scroll option and `input/mouse_encode.zig` never reads
        // mode 1007 — the arrow-key translation lives in `src/Surface.zig`,
        // i.e. Ghostty-the-app, above the library line. So `GhosttyMouse`
        // detects the case and hands it to the pane's key encoder.
        #expect(mouse.wheel(deltaLines: 1, col: 1, row: 1) == Data())
        #expect(mouse.wantsArrowFallback == true)
        #expect(mouse.wheel(deltaLines: -2, col: 1, row: 1) == Data())
        #expect(mouse.wantsArrowFallback == true)

        // And mouse tracking wins over alternate scroll: a TUI that asked
        // for reports gets reports even on the alternate screen.
        let tracked = Self.mouse(after: "\u{1b}[?1049h\u{1b}[?1007h" + Self.sgrTracking)
        #expect(tracked.wheel(deltaLines: 1, col: 1, row: 1) == Data("\u{1b}[<64;2;2M".utf8))
        #expect(tracked.wantsArrowFallback == false)
    }

    // MARK: 5 — motion under button-event tracking

    @Test @MainActor func motionUnderButtonTracking() {
        // DEC 1002: report motion, but only while a button is held.
        let mouse = Self.mouse(after: "\u{1b}[?1002h\u{1b}[?1006h")
        #expect(mouse.encode(button: .left, action: .press, col: 2, row: 2)
                == Data("\u{1b}[<0;3;3M".utf8))
        // Motion sets bit 0x20 on the button code: left (0) + 32 = 32.
        #expect(mouse.encode(button: .left, action: .motion, col: 3, row: 3)
                == Data("\u{1b}[<32;4;4M".utf8))
        // Dedup: a second motion inside the same cell is not news. Ours, not
        // the core's — `setopt_from_terminal` clears the encoder's own
        // last-cell state on every call, so `OPT_TRACK_LAST_CELL` can never
        // fire from here (documented in GhosttyMouse).
        #expect(mouse.encode(button: .left, action: .motion, col: 3, row: 3) == Data())
        #expect(mouse.encode(button: .left, action: .motion, col: 4, row: 3)
                == Data("\u{1b}[<32;5;4M".utf8))
        // Button-less motion needs any-event tracking (DEC 1003); under 1002
        // `shouldReport` requires a button, so this is silence.
        #expect(mouse.encode(button: nil, action: .motion, col: 6, row: 3) == Data())
    }

    // MARK: 6 — modifiers

    @Test @MainActor func modifiersAddToTheButtonCode() {
        let mouse = Self.mouse(after: Self.sgrTracking)
        // xterm's modifier bits, added to the button code: shift 4, alt 8,
        // ctrl 16 (`buttonCode`, input/mouse_encode.zig).
        #expect(mouse.encode(button: .left, action: .press, col: 5, row: 3, mods: .shift)
                == Data("\u{1b}[<4;6;4M".utf8))
        #expect(mouse.encode(button: .left, action: .press, col: 5, row: 3, mods: .option)
                == Data("\u{1b}[<8;6;4M".utf8))
        #expect(mouse.encode(button: .left, action: .press, col: 5, row: 3, mods: .control)
                == Data("\u{1b}[<16;6;4M".utf8))
        #expect(mouse.encode(button: .left, action: .press, col: 5, row: 3, mods: [.shift, .control])
                == Data("\u{1b}[<20;6;4M".utf8))
        // Command/super has no place in the mouse protocols and is ignored,
        // the same way it has no key encoding.
        #expect(mouse.encode(button: .left, action: .press, col: 5, row: 3, mods: .command)
                == Data("\u{1b}[<0;6;4M".utf8))
    }

    // MARK: 7 — the other buttons and the legacy format

    @Test @MainActor func buttonIdentitiesAndX10Format() {
        let sgr = Self.mouse(after: Self.sgrTracking)
        #expect(sgr.encode(button: .middle, action: .press, col: 0, row: 0)
                == Data("\u{1b}[<1;1;1M".utf8))
        #expect(sgr.encode(button: .right, action: .press, col: 0, row: 0)
                == Data("\u{1b}[<2;1;1M".utf8))

        // DEC 1000 alone: the default X10 *output format*, CSI M followed by
        // three bytes biased by 32. Left press at (0,0) → 32, 33, 33.
        let legacy = Self.mouse(after: "\u{1b}[?1000h")
        #expect(Array(legacy.encode(button: .left, action: .press, col: 0, row: 0))
                == [0x1b, 0x5b, 0x4d, 32, 33, 33])
        // Legacy releases lose the button identity: always code 3 → byte 35.
        #expect(Array(legacy.encode(button: .left, action: .release, col: 0, row: 0))
                == [0x1b, 0x5b, 0x4d, 35, 33, 33])
    }
}
