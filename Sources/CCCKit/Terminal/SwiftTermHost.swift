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
    /// Fired when the view's own layout changes its grid (window resize).
    /// The owner mirrors the size onto the PTY.
    public var onSizeChanged: ((Int, Int) -> Void)?
    public var view: NSView? { terminalView }

    public init(frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600), font: NSFont? = nil) {
        bridge = Bridge()
        terminalView = TerminalView(frame: frame, font: font)
        terminalView.terminalDelegate = bridge
        bridge.host = self
    }

    public func feed(_ bytes: Data) {
        terminalView.feed(byteArray: ArraySlice([UInt8](bytes)))
    }

    public func resize(cols: Int, rows: Int) {
        terminalView.resize(cols: cols, rows: rows)
    }

    public func snapshot() -> Grid {
        GridBuilder.grid(from: terminalView.getTerminal(), cursorVisible: cursorVisible)
    }

    public var size: (cols: Int, rows: Int) {
        terminalView.getTerminal().getDims()
    }

    fileprivate func terminalWantsToSend(_ data: ArraySlice<UInt8>) {
        onOutput?(Data(data))
    }

    fileprivate func sizeChanged(cols: Int, rows: Int) {
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
