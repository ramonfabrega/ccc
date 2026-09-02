import AppKit
import Foundation
import SwiftTerm

/// `TerminalHost` with no view: SwiftTerm's `Terminal` core driven directly.
/// Used by `ccc attach --headless`, by the replay test, and by anything that
/// wants a grid without a window.
@MainActor
public final class HeadlessHost: TerminalHost {
    private let terminal: Terminal
    private let bridge: Bridge
    private var cursorVisible = true

    public var onOutput: ((Data) -> Void)?
    public var view: NSView? { nil }

    public init(cols: Int = 80, rows: Int = 24, scrollback: Int = 2_000) {
        bridge = Bridge()
        var options = TerminalOptions.default
        options.cols = cols
        options.rows = rows
        options.scrollback = scrollback
        terminal = Terminal(delegate: bridge, options: options)
        bridge.host = self
    }

    public func feed(_ bytes: Data) {
        terminal.feed(byteArray: [UInt8](bytes))
    }

    public func resize(cols: Int, rows: Int) {
        terminal.resize(cols: cols, rows: rows)
    }

    public func snapshot() -> Grid {
        GridBuilder.grid(from: terminal, cursorVisible: cursorVisible)
    }

    // The terminal talks back through its delegate; we forward the two
    // things the seam cares about (bytes to the child, cursor visibility).
    fileprivate func terminalWantsToSend(_ data: ArraySlice<UInt8>) {
        onOutput?(Data(data))
    }

    fileprivate func setCursorVisible(_ visible: Bool) {
        cursorVisible = visible
    }

    /// SwiftTerm's delegate is a plain class protocol; this adapter keeps
    /// the host's public surface clean and pins the callbacks to the main
    /// actor, where the terminal is only ever touched.
    @MainActor private final class Bridge: @preconcurrency TerminalDelegate {
        weak var host: HeadlessHost?

        func send(source: Terminal, data: ArraySlice<UInt8>) {
            host?.terminalWantsToSend(data)
        }
        func showCursor(source: Terminal) {
            host?.setCursorVisible(true)
        }
        func hideCursor(source: Terminal) {
            host?.setCursorVisible(false)
        }
        // Everything else takes SwiftTerm's default implementation.
    }
}
