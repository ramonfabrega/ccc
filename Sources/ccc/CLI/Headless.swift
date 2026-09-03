import AppKit
import CCCKit
import Foundation

/// `ccc attach <id> --headless`: the pane without the window. Owns one
/// `AttachSession` on an off-screen host built by `PaneController.makeHost` —
/// the same core the window would use, so keys, mouse and paste encode
/// identically — polls the roster, and serves the control socket until the
/// child exits or `ccc detach` arrives. This is how an agent sees what the
/// user sees.
enum Headless {
    @MainActor
    static func run(ref: SessionRef, cols: Int, rows: Int) -> Int32 {
        // AppKit views need an NSApplication even with no window; .prohibited
        // keeps us out of the Dock and off the screen.
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        guard let cli = ClaudeCLI.locate() else {
            CLI.stderr("ccc: claude not found on PATH (set CCC_CLAUDE)")
            return 1
        }
        let controller = PaneController(cli: cli)
        do {
            try controller.serve()
        } catch {
            CLI.stderr("ccc: \(error)")
            return 1
        }
        controller.start()

        do {
            try controller.attach(ref: ref, cols: cols, rows: rows)
        } catch {
            CLI.stderr("ccc: attach failed: \(error)")
            controller.stop()
            return 1
        }
        CLI.stderr("ccc: attached \(ref) headless (\(cols)x\(rows)); socket \(controller.server?.path ?? "-"); `ccc snapshot` to look, `ccc detach` to leave")

        // No roster to focus without a window; the send reply carries the
        // same fact to the script that pressed it.
        controller.onLeaveRequested = {
            CLI.stderr("ccc: ← taken — in the window the roster takes the keyboard; the key was not sent")
        }

        nonisolated(unsafe) var exitCode: Int32 = 0
        controller.onSessionEnded = { status in
            exitCode = status
            // The exit usually arrives while a `ccc detach` reply is in
            // flight; give the socket a beat to flush before leaving.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                app.stop(nil)
                // stop() only takes effect after an event; post one.
                app.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                                                 timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!,
                              atStart: false)
            }
        }
        app.run()
        controller.stop()
        return exitCode
    }
}
