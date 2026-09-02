import Foundation
import GhosttyVt

/// Mouse encoding over libghostty-vt's own encoder — the same rule keys
/// follow (CLAUDE.md: "keys are the core's job. Never hand-roll escape
/// sequences"). A button + action + cell becomes a `GhosttyMouseEvent` and
/// the core turns it into X10 / UTF-8 / SGR / URXVT / SGR-pixels bytes
/// according to what the child negotiated, or into nothing at all when
/// tracking is off. This is check 3's ("mouse scroll in the transcript")
/// encoder half; the pane wires it to `NSEvent`.
///
/// Shaped after `GhosttyKeys`: one encoder and one reused event for the
/// lifetime of the object, options re-synced from the terminal before every
/// encode, and a strong reference to the owner so the raw terminal handle
/// cannot be freed under us (the ARC use-after-free `GhosttyKeys` documents).
@MainActor
public final class GhosttyMouse {
    /// The buttons we can name. `wheel*` are the scroll "buttons" the X11
    /// mouse protocols invented: the core maps FOUR/FIVE/SIX/SEVEN to codes
    /// 64/65/66/67, which is what a TUI reads as wheel up/down/left/right.
    public enum Button {
        case left, middle, right
        case wheelUp, wheelDown, wheelLeft, wheelRight

        var raw: GhosttyMouseButton {
            switch self {
            case .left: return GHOSTTY_MOUSE_BUTTON_LEFT
            case .middle: return GHOSTTY_MOUSE_BUTTON_MIDDLE
            case .right: return GHOSTTY_MOUSE_BUTTON_RIGHT
            case .wheelUp: return GHOSTTY_MOUSE_BUTTON_FOUR
            case .wheelDown: return GHOSTTY_MOUSE_BUTTON_FIVE
            case .wheelLeft: return GHOSTTY_MOUSE_BUTTON_SIX
            case .wheelRight: return GHOSTTY_MOUSE_BUTTON_SEVEN
            }
        }
    }

    public enum Action {
        case press, release, motion

        var raw: GhosttyMouseAction {
            switch self {
            case .press: return GHOSTTY_MOUSE_ACTION_PRESS
            case .release: return GHOSTTY_MOUSE_ACTION_RELEASE
            case .motion: return GHOSTTY_MOUSE_ACTION_MOTION
            }
        }
    }

    /// The same four modifiers `NamedKey` carries, as a set so a caller can
    /// build them from `NSEvent.modifierFlags` in one expression.
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let shift = Modifiers(rawValue: 1 << 0)
        public static let control = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        var raw: GhosttyMods {
            var mods: GhosttyMods = 0
            if contains(.shift) { mods |= GhosttyMods(GHOSTTY_MODS_SHIFT) }
            if contains(.control) { mods |= GhosttyMods(GHOSTTY_MODS_CTRL) }
            if contains(.option) { mods |= GhosttyMods(GHOSTTY_MODS_ALT) }
            if contains(.command) { mods |= GhosttyMods(GHOSTTY_MODS_SUPER) }
            return mods
        }
    }

    /// Non-owning: the terminal belongs to the host that made it.
    private let terminal: GhosttyTerminal?
    /// Strong, for the same reason `GhosttyKeys.owner` is: the handle above
    /// is raw memory the host frees in its deinit.
    private let owner: AnyObject?
    private var encoder: GhosttyMouseEncoder?
    private var event: GhosttyMouseEvent?

    public private(set) var lastError: String?

    /// True after a `wheel(...)` the core declined to encode because the
    /// terminal is in the alternate screen with alternate scroll (DEC 1007)
    /// on and no mouse tracking active. The core has **no** alternate-scroll
    /// support (see `wheel`), so the pane must send arrow keys itself.
    public private(set) var wantsArrowFallback = false

    /// Pixel size of one cell, and therefore the unit the encoder's size
    /// context is expressed in. The default 1×1 makes surface pixels equal
    /// grid cells, which is all the non-pixel formats need; a GUI pane sets
    /// the real metrics so SGR-Pixels (format 1016) reports true pixels.
    private var cellPixels: (width: UInt32, height: UInt32) = (1, 1)

    /// Our own motion dedup. `GHOSTTY_MOUSE_ENCODER_OPT_TRACK_LAST_CELL`
    /// cannot be used from here: `ghostty_mouse_encoder_setopt_from_terminal`
    /// clears the encoder's `last_cell` on every call (c/mouse_encode.zig:195),
    /// and we call it before every encode, so the core's dedup would never
    /// fire. Keeping the last reported cell in Swift gives the same result.
    private var lastMotionCell: (col: Int, row: Int)?

    public init(terminal: GhosttyTerminal?, owner: AnyObject? = nil) {
        self.terminal = terminal
        self.owner = owner
        var e: GhosttyMouseEncoder?
        if ghostty_mouse_encoder_new(nil, &e) == GHOSTTY_SUCCESS, let e {
            encoder = e
        } else {
            lastError = "ghostty_mouse_encoder_new failed"
        }
        var ev: GhosttyMouseEvent?
        if ghostty_mouse_event_new(nil, &ev) == GHOSTTY_SUCCESS, let ev {
            event = ev
        } else {
            lastError = "ghostty_mouse_event_new failed"
        }
    }

    /// The encoder for a host's terminal. The host keeps owning the handle.
    public convenience init(host: GhosttyHost) {
        self.init(terminal: host.terminal, owner: host)
    }

    isolated deinit {
        if let event { ghostty_mouse_event_free(event) }
        if let encoder { ghostty_mouse_encoder_free(encoder) }
    }

    // MARK: geometry

    /// Cell size in pixels, mirroring `GhosttyHost.setCellSize`. Only
    /// SGR-Pixels reporting reads it; every other format works in cells.
    public func setCellSize(width: Int, height: Int) {
        cellPixels = (UInt32(clamping: max(1, width)), UInt32(clamping: max(1, height)))
    }

    // MARK: options

    /// Sync tracking mode and output format from the terminal, then restate
    /// the two things that call does not touch.
    ///
    /// `ghostty_mouse_encoder_setopt_from_terminal` copies exactly
    /// `t.flags.mouse_event` → `OPT_EVENT` and `t.flags.mouse_format` →
    /// `OPT_FORMAT` (c/mouse_encode.zig:187). It explicitly "does not modify
    /// size or any-button state", and a fresh encoder's default size is
    /// **1×1 pixels of screen** (`defaultSize()`), so every position but
    /// (0,0) would fall out of the viewport and encode to nothing. Setting
    /// `OPT_SIZE` from the live cols/rows is therefore mandatory, not
    /// optional — it is the one non-obvious step in this file.
    private func refreshOptions(anyButtonPressed: Bool) {
        guard let encoder else { return }
        if let terminal { ghostty_mouse_encoder_setopt_from_terminal(encoder, terminal) }

        let grid = gridSize()
        // Sized struct: `size` must be set or the library fills nothing and
        // still returns success (docs/TERMINAL.md, "sized structs").
        var size = GhosttyMouseEncoderSize()
        size.size = MemoryLayout<GhosttyMouseEncoderSize>.size
        size.cell_width = cellPixels.width
        size.cell_height = cellPixels.height
        size.screen_width = UInt32(grid.cols) * cellPixels.width
        size.screen_height = UInt32(grid.rows) * cellPixels.height
        ghostty_mouse_encoder_setopt(encoder, GHOSTTY_MOUSE_ENCODER_OPT_SIZE, &size)

        // Out-of-viewport motion is only reported while a button is held;
        // the core wants this to include the event being encoded.
        var pressed = anyButtonPressed
        ghostty_mouse_encoder_setopt(encoder, GHOSTTY_MOUSE_ENCODER_OPT_ANY_BUTTON_PRESSED, &pressed)
    }

    private func gridSize() -> (cols: Int, rows: Int) {
        guard let terminal else { return (1, 1) }
        var cols: UInt16 = 0, rows: UInt16 = 0
        _ = ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_COLS, &cols)
        _ = ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_ROWS, &rows)
        return (Int(max(cols, 1)), Int(max(rows, 1)))
    }

    // MARK: terminal state

    /// True when any of DEC 9 / 1000 / 1002 / 1003 is on
    /// (`GHOSTTY_TERMINAL_DATA_MOUSE_TRACKING` is the core's own "any mouse
    /// tracking mode is active", so we never enumerate the modes ourselves).
    public var isTracking: Bool {
        guard let terminal else { return false }
        var tracking = false
        guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_MOUSE_TRACKING, &tracking) == GHOSTTY_SUCCESS else { return false }
        return tracking
    }

    /// The child is on the alternate screen (DEC 1047/1049 or 47).
    public var isAlternateScreen: Bool {
        guard let terminal else { return false }
        var screen = GHOSTTY_TERMINAL_SCREEN_PRIMARY
        guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN, &screen) == GHOSTTY_SUCCESS else { return false }
        return screen == GHOSTTY_TERMINAL_SCREEN_ALTERNATE
    }

    /// Read one DEC/ANSI mode. Same shape as `GhosttyKeys.mode`: the getter
    /// is in/out, and `GHOSTTY_MODE_*` are macros Swift cannot see, so the
    /// mode is built with `ghostty_mode_new(n, isDECPrivate:)`.
    public func mode(_ number: UInt16, dec: Bool = true) -> Bool {
        guard let terminal else { return false }
        var config = GhosttyTerminalModeConfig(mode: ghostty_mode_new(number, !dec), value: false)
        guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_MODE, &config) == GHOSTTY_SUCCESS else { return false }
        return config.value
    }

    /// DEC 1007, alternate scroll: in the alternate screen the wheel should
    /// become cursor keys. **Ghostty's default is on** (modes.zig:316), so
    /// this is true for a fresh terminal that has never seen `CSI ? 1007 h`.
    public var alternateScroll: Bool { mode(1007) }

    // MARK: encoding

    /// The bytes the child should receive for one mouse event at cell
    /// (`col`, `row`), zero-based. Empty when the core emits nothing — which
    /// is the normal, correct answer whenever mouse tracking is off, and
    /// also for events a given mode filters out (X10 reports presses only;
    /// normal mode drops motion; button mode drops button-less motion).
    ///
    /// Coordinates go in as cells and come back 1-based in the sequence: the
    /// core does the +1 (input/mouse_encode.zig).
    @discardableResult
    public func encode(button: Button?, action: Action, col: Int, row: Int, mods: Modifiers = []) -> Data {
        guard encoder != nil, let event else { return Data() }

        // Motion dedup: a drag inside one cell is one report, not one per
        // pixel. SGR-Pixels genuinely wants every pixel, so it opts out.
        if action == .motion, !isPixelFormat, let last = lastMotionCell, last == (col, row) {
            return Data()
        }
        if action == .motion { lastMotionCell = (col, row) } else { lastMotionCell = nil }

        refreshOptions(anyButtonPressed: action != .release && button != nil)

        ghostty_mouse_event_set_action(event, action.raw)
        if let button {
            ghostty_mouse_event_set_button(event, button.raw)
        } else {
            // event.h: "no button" for a motion with nothing held is
            // `clear_button`, not button 0.
            ghostty_mouse_event_clear_button(event)
        }
        ghostty_mouse_event_set_mods(event, mods.raw)
        // The event carries surface-space *pixels*; aim at the middle of the
        // cell so rounding never lands us in the neighbour.
        ghostty_mouse_event_set_position(event, GhosttyMousePosition(
            x: Float(col) * Float(cellPixels.width) + Float(cellPixels.width) / 2,
            y: Float(row) * Float(cellPixels.height) + Float(cellPixels.height) / 2
        ))

        return encodeCurrent()
    }

    /// DEC 1016, SGR-Pixels: the child asked for pixel coordinates, so a
    /// motion that stays inside one cell is still news and dedup must not
    /// swallow it (the core makes the same exception,
    /// `input/mouse_encode.zig`: dedup applies `if format != .sgr_pixels`).
    /// There is no `GHOSTTY_TERMINAL_DATA_*` for the mouse format, only for
    /// "is anything tracking", so this reads the mode directly.
    private var isPixelFormat: Bool { mode(1016) }

    /// One `ghostty_mouse_encoder_encode` with a stack-sized buffer; on
    /// OUT_OF_SPACE `written` carries the size the core needs, so grow to it
    /// and retry exactly once. Same contract as the key encoder.
    private func encodeCurrent() -> Data {
        guard let encoder, let event else { return Data() }
        var buffer = [CChar](repeating: 0, count: 64)
        var written = 0
        var result = buffer.withUnsafeMutableBufferPointer { buf in
            ghostty_mouse_encoder_encode(encoder, event, buf.baseAddress, buf.count, &written)
        }
        if result == GHOSTTY_OUT_OF_SPACE {
            buffer = [CChar](repeating: 0, count: max(written, 128))
            result = buffer.withUnsafeMutableBufferPointer { buf in
                ghostty_mouse_encoder_encode(encoder, event, buf.baseAddress, buf.count, &written)
            }
        }
        guard result == GHOSTTY_SUCCESS, written > 0 else { return Data() }
        return buffer.prefix(written).withUnsafeBufferPointer {
            Data(bytes: $0.baseAddress!, count: written)
        }
    }

    // MARK: wheel

    /// Bytes for a wheel scroll of `deltaLines` whole lines at cell
    /// (`col`, `row`) — positive is up, negative is down. Each line is one
    /// press of the wheel button, exactly as a real mouse reports it, so the
    /// result is `|deltaLines|` concatenated reports.
    ///
    /// **The core does not implement alternate scroll.** Verified two ways
    /// against the pinned vendor tree: `mouse/encoder.h` has only
    /// `OPT_EVENT`, `OPT_FORMAT`, `OPT_SIZE`, `OPT_ANY_BUTTON_PRESSED` and
    /// `OPT_TRACK_LAST_CELL` — nothing named alt/alternate scroll — and
    /// `src/input/mouse_encode.zig` never reads mode 1007; the only mention
    /// of `mouse_alternate_scroll` outside `modes.zig` is `src/Surface.zig`,
    /// i.e. Ghostty-the-app's own scroll callback, above the library line.
    /// So the arrow-key translation is the embedder's job, and we do what
    /// Surface.zig does: alternate screen **and** no mouse tracking **and**
    /// mode 1007 on → no bytes here, `wantsArrowFallback` set, and the pane
    /// presses up/down through `GhosttyKeys` (which applies DECCKM for us,
    /// the other half of what Surface.zig hand-rolls).
    ///
    /// Ordering matters: mouse tracking wins over alternate scroll, because
    /// a TUI that asked for reports wants reports even in the alt screen.
    public func wheel(deltaLines: Int, col: Int, row: Int, mods: Modifiers = []) -> Data {
        wantsArrowFallback = false
        guard deltaLines != 0 else { return Data() }

        if !isTracking, isAlternateScreen, alternateScroll {
            wantsArrowFallback = true
            return Data()
        }

        let button: Button = deltaLines > 0 ? .wheelUp : .wheelDown
        var out = Data()
        for _ in 0..<abs(deltaLines) {
            out.append(encode(button: button, action: .press, col: col, row: row, mods: mods))
        }
        // A wheel that produced nothing while tracking is off is still a
        // scroll the user made; in the primary screen there is no in-band
        // answer, so the pane's local scrollback handles it (v1: nothing).
        return out
    }

    /// Horizontal companion to `wheel`; positive is right. No alternate-scroll
    /// path — Surface.zig only translates the vertical axis.
    public func wheelHorizontal(deltaCells: Int, col: Int, row: Int, mods: Modifiers = []) -> Data {
        guard deltaCells != 0 else { return Data() }
        let button: Button = deltaCells > 0 ? .wheelRight : .wheelLeft
        var out = Data()
        for _ in 0..<abs(deltaCells) {
            out.append(encode(button: button, action: .press, col: col, row: row, mods: mods))
        }
        return out
    }
}
