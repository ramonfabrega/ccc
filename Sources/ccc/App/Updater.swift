import AppKit
import Sparkle

/// Self-update, the fleet's shape (disk's `Updater.swift`): installed copies
/// poll the CDN appcast (`SUFeedURL` in Info.plist) on Sparkle's schedule
/// and use its standard UI, so a window appears only when there is
/// something to say. The one piece of app surface is "Check for Updates…"
/// in the app menu. Started by the window face only: a CLI invocation or a
/// headless attach never checks for anything.
///
/// Dev builds are immune to self-downgrade: CFBundleVersion is the git
/// commit count (scripts/make-bundle), so a working copy always outranks
/// the last published release.
@MainActor
final class Updater {
    private let controller = SPUStandardUpdaterController(startingUpdater: true,
                                                          updaterDelegate: nil, userDriverDelegate: nil)

    /// The menu item, wired to Sparkle's own action so its enabled state
    /// follows `canCheckForUpdates` through the controller's validation.
    func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Check for Updates…",
                              action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                              keyEquivalent: "")
        item.target = controller
        return item
    }
}
