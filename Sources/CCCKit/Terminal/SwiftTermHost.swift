import AppKit
import Foundation
import SwiftTerm

/// `TerminalHost` backed by SwiftTerm's stock `TerminalView`: the v0 pane
/// stand-in (docs/DESIGN.md §3). Key handling, mouse, and drawing are
/// SwiftTerm's; ccc only moves bytes across the seam and reads the grid.
/// Replaced by `GhosttyHost` in v1 when it wins the six checks.
@MainActor
public final class SwiftTermHost: TerminalHost {
    private let terminalView: TerminalView
    private let bridge: Bridge
    private var cursorVisible = true

    public var onOutput: ((Data) -> Void)?
    /// Consulted by `press` only: the stock view's own `keyDown` goes
    /// straight to SwiftTerm, so the window's keyboard is not gated on
    /// this core (the escape hatch; `ccc send --key` is).
    public var keyInterceptor: ((NamedKey) -> Bool)?
    /// Fired when the view's own layout changes its grid (window resize).
    /// The owner mirrors the size onto the PTY.
    public var onSizeChanged: ((Int, Int) -> Void)?
    public var view: NSView? { terminalView }

    /// `metal`: SwiftTerm 1.20's public Metal path (docs/DESIGN.md §3
    /// finding). Opt-in via `CCC_METAL=1`: measured 2026-09-02, the Metal
    /// renderer costs ~250 MB of phys_footprint (287 MB vs 40 MB attached),
    /// and cacheDisplay-based `ccc peek` cannot capture an MTKView. Falls
    /// back to CoreGraphics if the device or shader load refuses;
    /// `usingMetal` says which we got.
    public init(frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600), font: NSFont? = nil,
                metal: Bool = ProcessInfo.processInfo.environment["CCC_METAL"] != nil) {
        bridge = Bridge()
        terminalView = TerminalView(frame: frame, font: font)
        terminalView.terminalDelegate = bridge
        terminalView.getTerminal().silentLog = true
        bridge.host = self
        if metal {
            do { try terminalView.setUseMetal(true) } catch { metalError = "\(error)" }
        }
    }

    /// Why Metal is off, when it was asked for and refused.
    public private(set) var metalError: String?
    public var usingMetal: Bool { terminalView.isUsingMetalRenderer }

    /// Cell size at SwiftTerm's default font, for sizing a grid to a view
    /// before the view exists.
    public static func estimatedCellSize() -> CGSize {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let width = ("W" as NSString).size(withAttributes: [.font: font]).width
        let height = font.ascender - font.descender + font.leading
        return CGSize(width: ceil(width), height: ceil(height))
    }

    public func feed(_ bytes: Data) {
        terminalView.feed(byteArray: ArraySlice([UInt8](bytes)))
    }

    /// Programmatic resize (headless, `ccc resize`). In a window the view
    /// owns its grid size and reports changes through `onSizeChanged`;
    /// SwiftTerm's `resize` also soft-resets the terminal, so never call it
    /// for a size we already have or from inside its own size callback.
    public func resize(cols: Int, rows: Int) {
        let current = terminalView.getTerminal().getDims()
        guard !inSizeCallback, current.cols != cols || current.rows != rows else { return }
        terminalView.resize(cols: cols, rows: rows)
    }

    private var inSizeCallback = false

    public func snapshot() -> Grid {
        GridBuilder.grid(from: terminalView.getTerminal(), cursorVisible: cursorVisible)
    }

    public var size: (cols: Int, rows: Int) {
        terminalView.getTerminal().getDims()
    }

    /// SwiftTerm frames pastes inside its own NSResponder `paste:` path from
    /// the pasteboard; there is no text-in API that applies mode 2004, so
    /// this host cannot paste programmatically. Check 2 runs on the Ghostty
    /// host only until that changes.
    public func paste(_ text: String) -> Bool { false }

    /// Synthesizes the NSEvent the user's keypress would produce and hands
    /// it to SwiftTerm's `keyDown`, so `ccc send --key ctrl-z` takes the
    /// same path — kitty encoding included — as a finger on the keyboard.
    public func press(_ key: NamedKey) -> Bool {
        if keyInterceptor?(key) == true { return true }
        guard let event = Self.event(for: key) else { return false }
        terminalView.keyDown(with: event)
        return true
    }

    private static func event(for key: NamedKey) -> NSEvent? {
        var flags: NSEvent.ModifierFlags = []
        if key.shift { flags.insert(.shift) }
        if key.control { flags.insert(.control) }
        if key.option { flags.insert(.option) }
        if key.command { flags.insert(.command) }

        let characters: String
        let unmodified: String
        let keyCode: UInt16
        if let base = key.base {
            let (scalar, code) = Self.special(base)
            characters = String(Character(scalar))
            unmodified = characters
            keyCode = code
        } else if let ch = key.character {
            unmodified = String(ch)
            if key.control, let ascii = ch.asciiValue, ascii >= 0x61 && ascii <= 0x7a {
                characters = String(Character(UnicodeScalar(ascii - 0x60)))   // ctrl-a … ctrl-z
            } else {
                characters = key.shift ? unmodified.uppercased() : unmodified
            }
            keyCode = Self.letterKeyCodes[ch] ?? 0
        } else {
            return nil
        }
        return NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: unmodified,
            isARepeat: false, keyCode: keyCode
        )
    }

    /// NSEvent character + macOS virtual key code for the named keys.
    private static func special(_ base: NamedKey.Base) -> (UnicodeScalar, UInt16) {
        switch base {
        case .enter: return (UnicodeScalar(0x0d), 36)
        case .escape: return (UnicodeScalar(0x1b), 53)
        case .tab: return (UnicodeScalar(0x09), 48)
        case .backspace: return (UnicodeScalar(0x7f), 51)
        case .delete: return (UnicodeScalar(NSDeleteFunctionKey)!, 117)
        case .space: return (UnicodeScalar(0x20), 49)
        case .up: return (UnicodeScalar(NSUpArrowFunctionKey)!, 126)
        case .down: return (UnicodeScalar(NSDownArrowFunctionKey)!, 125)
        case .left: return (UnicodeScalar(NSLeftArrowFunctionKey)!, 123)
        case .right: return (UnicodeScalar(NSRightArrowFunctionKey)!, 124)
        case .home: return (UnicodeScalar(NSHomeFunctionKey)!, 115)
        case .end: return (UnicodeScalar(NSEndFunctionKey)!, 119)
        case .pageup: return (UnicodeScalar(NSPageUpFunctionKey)!, 116)
        case .pagedown: return (UnicodeScalar(NSPageDownFunctionKey)!, 121)
        case .f1: return (UnicodeScalar(NSF1FunctionKey)!, 122)
        case .f2: return (UnicodeScalar(NSF2FunctionKey)!, 120)
        case .f3: return (UnicodeScalar(NSF3FunctionKey)!, 99)
        case .f4: return (UnicodeScalar(NSF4FunctionKey)!, 118)
        case .f5: return (UnicodeScalar(NSF5FunctionKey)!, 96)
        case .f6: return (UnicodeScalar(NSF6FunctionKey)!, 97)
        case .f7: return (UnicodeScalar(NSF7FunctionKey)!, 98)
        case .f8: return (UnicodeScalar(NSF8FunctionKey)!, 100)
        case .f9: return (UnicodeScalar(NSF9FunctionKey)!, 101)
        case .f10: return (UnicodeScalar(NSF10FunctionKey)!, 109)
        case .f11: return (UnicodeScalar(NSF11FunctionKey)!, 103)
        case .f12: return (UnicodeScalar(NSF12FunctionKey)!, 111)
        }
    }

    private static let letterKeyCodes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
        "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
        "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
    ]

    fileprivate func terminalWantsToSend(_ data: ArraySlice<UInt8>) {
        onOutput?(Data(data))
    }

    fileprivate func sizeChanged(cols: Int, rows: Int) {
        inSizeCallback = true
        defer { inSizeCallback = false }
        onSizeChanged?(cols, rows)
    }

    @MainActor private final class Bridge: @preconcurrency TerminalViewDelegate {
        weak var host: SwiftTermHost?

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            host?.terminalWantsToSend(data)
        }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            host?.sizeChanged(cols: newCols, rows: newRows)
        }
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) { NSWorkspace.shared.open(url) }
        }
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(String(decoding: content, as: UTF8.self), forType: .string)
        }
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
