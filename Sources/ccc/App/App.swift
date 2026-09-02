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
    private var controller: PaneController?
    private var window: MainWindowController?
    private var statusItem: NSStatusItem?
    private let updater = Updater()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        guard let cli = ClaudeCLI.locate() else {
            let alert = NSAlert()
            alert.messageText = "claude not found"
            alert.informativeText = "ccc drives the Claude Code CLI. Put `claude` on PATH or set CCC_CLAUDE to its path."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let controller = PaneController(cli: cli)
        controller.remembersAttach = true
        self.controller = controller
        let window = MainWindowController(controller: controller)
        self.window = window
        controller.peekProvider = { [weak window] in window?.peek() }
        controller.windowAction = { [weak window] action in window?.windowAction(action) ?? false }
        do {
            try controller.serve()
        } catch {
            // Another ccc (or a headless attach) holds the socket. The window
            // still works; the CLI just talks to the other one.
            window.showNotice("\(error)")
        }
        controller.poller.start()
        installStatusItem()
        window.showWindow(nil)
        NSApp.activate()
        // A relaunch — Sparkle's, or ⌘Q and back — lands on the session the
        // window was in, the way the agents view keeps its focus. After the
        // first poll, so a session that ended meanwhile is not attached to.
        Task { @MainActor [weak controller] in
            await controller?.poller.tick()
            controller?.reattachAfterRelaunch()
        }
        // What sleeps is this Mac (docs/DESIGN.md §4b): on wake, drop every
        // remote ssh master and poll at once rather than let a 2 s tick
        // discover a stale socket the slow way. Same gesture as
        // `ccc hosts reconnect`.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { [weak controller] _ in
            Task { @MainActor in await controller?.reconnect() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.showWindow(nil)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    // MARK: menubar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "ccc"
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        statusItem = item
        // Reflect "your turn" in the title: a count of blocked sessions.
        Task { @MainActor [weak self] in
            while let self, let controller = self.controller {
                let blocked = controller.poller.state.rows.filter { $0.session.state == .blocked }.count
                let working = controller.poller.state.rows.filter { $0.session.state == .working }.count
                self.statusItem?.button?.title = blocked > 0 ? "ccc ⏸\(blocked)" : (working > 0 ? "ccc ·\(working)" : "ccc")
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    @objc private func statusItemClicked() {
        window?.showWindow(nil)
        NSApp.activate()
    }

    private func buildMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About ccc", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(updater.menuItem())
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide ccc", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit ccc", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let session = NSMenu(title: "Session")
        session.addItem(withTitle: "Detach", action: #selector(MainWindowController.detachAction(_:)), keyEquivalent: "d")
        session.addItem(withTitle: "Refresh Roster", action: #selector(MainWindowController.refreshAction(_:)), keyEquivalent: "r")
        let sessionItem = NSMenuItem()
        sessionItem.submenu = session
        main.addItem(sessionItem)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)

        let windowMenu = NSMenu(title: "Window")
        // Targeted at the delegate: with the window closed, the responder
        // chain has no window controller to find.
        let show = windowMenu.addItem(withTitle: "Show ccc", action: #selector(statusItemClicked), keyEquivalent: "0")
        show.target = self
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = main
    }
}
