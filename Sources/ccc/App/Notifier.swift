import AppKit
import CCCKit
import UserNotifications

/// "It's your turn" on this Mac (v3, slice 1). Reads the roster the window
/// already polls, runs the same `TransitionDetector` that `ccc watch`
/// runs, and posts one macOS notification per event; clicking one attaches
/// the pane to that session. No hook, no forwarding: a session blocked on
/// studio shows up on air because air's roster says so.
///
/// Only from a bundle: `UNUserNotificationCenter` aborts the process when
/// there is no bundle identifier, so the bare dev binary (which has no
/// window face worth notifying from anyway) skips this entirely.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let poller: RosterPoller
    private let attach: (SessionRef) -> Void
    private var detector = TransitionDetector()
    private var loop: Task<Void, Never>?
    private(set) var posted = 0
    private var lastEvent: String?
    private var authorization = "unavailable"

    /// What `ccc stats` prints: detected-but-unauthorized is a silent Mac,
    /// and this is how that is a number instead of a mystery.
    func stats() -> NotificationStats {
        NotificationStats(authorization: authorization, posted: posted, lastEvent: lastEvent)
    }

    init(poller: RosterPoller, attach: @escaping (SessionRef) -> Void) {
        self.poller = poller
        self.attach = attach
    }

    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    func start() {
        guard Self.isAvailable, loop == nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        // The poll's own cadence: an event is at most one interval late,
        // and there is no second poll for the sake of a notification.
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                for event in self.detector.observe(self.poller.state) { self.post(event) }
                // Re-read each tick: the user answers the permission banner
                // whenever they like, and stats should say so when they do.
                let settings = await center.notificationSettings()
                self.authorization = Self.describe(settings.authorizationStatus)
                try? await Task.sleep(for: self.poller.interval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    private func post(_ event: SessionEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.headline
        if !event.ref.isLocal { content.subtitle = "on \(event.ref.host)" }
        content.body = event.kind == .blocked ? "Click to attach" : event.ref.description
        content.sound = event.kind == .blocked ? .default : nil
        content.threadIdentifier = event.ref.description
        content.userInfo = ["host": event.ref.host, "id": event.ref.id]
        // One request id per session: a newer event on the same session
        // replaces the older banner instead of stacking under it.
        let request = UNNotificationRequest(identifier: event.ref.description, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        posted += 1
        lastEvent = event.headline
    }

    private static func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .notDetermined: return "notDetermined"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show it even when ccc is the frontmost app: the pane may be on
    /// another session, and the roster row alone is easy to miss.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let host = info["host"] as? String, let id = info["id"] as? String {
            let ref = SessionRef(host: host, id: id)
            Task { @MainActor in
                NSApp.activate()
                self.attach(ref)
            }
        }
        completionHandler()
    }
}
