import CCCKit
import Foundation
import ServiceManagement

/// Launch at login — a locked decision since 2026-09-02 ("menubar-resident,
/// launch at login") that nothing implemented until 2026-11-13, which is
/// why ccc.app was simply not running on studio the night attrition's
/// handover needed it (`AppWake`).
///
/// `SMAppService.mainApp` is the whole mechanism: no helper bundle, no
/// LaunchAgent plist of ours, and the user's own switch for it is System
/// Settings › General › Login Items. It registers **once**, the first
/// launch of a build that knows how, and after that the setting is the
/// user's — a removal in System Settings is not undone at the next launch.
@MainActor enum LoginItem {
    /// Set once the first registration has been attempted, so a later
    /// "off" — from the menu, `ccc login off`, or System Settings — holds.
    static let offeredKey = "loginItem.offered"

    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    /// The state as a sentence fragment: what `ccc login` and `ccc stats`
    /// print.
    static var status: String {
        guard BuildInfo.current.isBundled else { return "off (not an app bundle)" }
        switch SMAppService.mainApp.status {
        case .enabled: return "on"
        case .notRegistered: return "off"
        case .requiresApproval: return "off (waiting for approval in System Settings › General › Login Items)"
        case .notFound: return "off (the system does not know this app)"
        @unknown default: return "unknown"
        }
    }

    /// Turn it on or off, and say what happened.
    @discardableResult
    static func set(_ on: Bool, defaults: UserDefaults = .standard) -> String {
        guard BuildInfo.current.isBundled else { return "launch at login is \(status)" }
        defaults.set(true, forKey: offeredKey)
        do {
            if on {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            return "launch at login is \(status): \(error.localizedDescription)"
        }
        return "launch at login is \(status)"
    }

    /// The first launch registers; every later one leaves the setting
    /// alone. `nil` when there was nothing to do.
    static func offerOnce(defaults: UserDefaults = .standard) -> String? {
        guard BuildInfo.current.isBundled, !defaults.bool(forKey: offeredKey) else { return nil }
        return set(true, defaults: defaults)
    }
}
