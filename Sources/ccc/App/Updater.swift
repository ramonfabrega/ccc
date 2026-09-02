import AppKit
import Sparkle

/// Self-update, the fleet's shape (disk's `Updater.swift`): installed copies
/// poll the CDN appcast (`SUFeedURL` in Info.plist) on Sparkle's schedule
/// and use its standard UI, so a window appears only when there is
/// something to say. The one piece of app surface is "Check for Updates…"
/// in the app menu. Started by the window face only: a CLI invocation or a
/// headless attach never checks for anything.
///
/// Only when there is a bundle to update: a bare `.build/debug/ccc` has no
/// Info.plist, and Sparkle answers that with a *modal* alert on startup
/// that blocks the main thread — found 2026-09-02 by `sample`, as a control
/// socket that never replied. The dev lane runs without Sparkle.
///
/// Dev builds are immune to self-downgrade: CFBundleVersion is the git
/// commit count (scripts/make-bundle), so a working copy always outranks
/// the last published release.
@MainActor
final class Updater {
    private let controller: SPUStandardUpdaterController?

    init() {
        let bundled = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        controller = bundled
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
    }

    /// The menu item, wired to Sparkle's own action so its enabled state
    /// follows `canCheckForUpdates` through the controller's validation.
    /// Disabled, with the reason as its title, when not running from a
    /// bundle.
    func menuItem() -> NSMenuItem {
        guard let controller else {
            let item = NSMenuItem(title: "Check for Updates… (not a bundle)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }
        let item = NSMenuItem(title: "Check for Updates…",
                              action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                              keyEquivalent: "")
        item.target = controller
        return item
    }
}
