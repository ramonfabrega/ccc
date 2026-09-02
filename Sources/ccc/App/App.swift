import AppKit
import CCCKit

/// The window face. Bootstraps NSApplication by hand (no storyboard, no
/// SwiftUI App lifecycle) so the same binary can skip all of it when run as
/// a CLI.
enum App {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
        // TODO(v0-m5): window, roster, pane, banner, menubar.
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
