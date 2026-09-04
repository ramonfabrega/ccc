import AppKit
import CCCKit
import UserNotifications

/// "It's your turn" on this Mac (v3). Reads the roster the window
/// already polls, runs the same `TransitionDetector` that `ccc watch`
/// runs, and posts one macOS notification per event; clicking one attaches
/// the pane to that session. No forwarding: a session blocked on studio
/// shows up on air because air's roster says so.
///
/// Slice 2 added two things. A host can be **muted** (`hosts.json`,
/// `ccc hosts mute <name>`, the View menu): its events are detected and
/// counted but never posted. And the harness's `Notification` hook reaches
/// here through `ccc hook` for what the roster cannot show — an
/// interactive session's permission prompt, the question a blocked
/// background session is asking — as `receive(_:)`.
///
/// Only from a bundle: `UNUserNotificationCenter` aborts the process when
/// there is no bundle identifier, so the bare dev binary (which has no
/// window face worth notifying from anyway) skips this entirely.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let poller: RosterPoller
    /// `nil` ref: nothing to attach to (an interactive session, or one the
    /// roster has not met); the window is shown and that is all.
    private let attach: (SessionRef?) -> Void
    private var detector = TransitionDetector()
    private var loop: Task<Void, Never>?
    private(set) var posted = 0
    private var lastEvent: String?
    private var authorization = "unavailable"
    /// The mute list, re-read when `hosts.json` moves (the overlay's
    /// pattern): `ccc hosts mute air` from a shell takes on the next tick.
    private let hostsPath: String
    private var muted: Set<String> = []
    private var mutedModifiedAt: Date?
    private var mutedLoaded = false
    private var hooks = 0
    private var hooksMuted = 0
    private var lastHook: String?

    /// What `ccc stats` prints: detected-but-unauthorized is a silent Mac,
    /// and this is how that is a number instead of a mystery.
    func stats() -> NotificationStats {
        NotificationStats(authorization: authorization, posted: posted, lastEvent: lastEvent,
                          muted: muted.sorted(), hooks: hooks, hooksMuted: hooksMuted, lastHook: lastHook)
    }

    init(poller: RosterPoller, hostsPath: String = HostConfig.defaultPath, attach: @escaping (SessionRef?) -> Void) {
        self.poller = poller
        self.hostsPath = hostsPath
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
                self.reloadMutesIfMoved()
                for event in self.detector.observe(self.poller.state) where !self.muted.contains(event.ref.host) {
                    self.post(event)
                }
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

    private func reloadMutesIfMoved() {
        let modified = HostConfig.modificationDate(path: hostsPath)
        if mutedLoaded, modified == mutedModifiedAt { return }
        // A broken file loads as local-only and unmuted, the way the
        // roster reads it; the banner about the file is the poller's.
        muted = Set(HostConfig.load(path: hostsPath).config.mutedHosts)
        mutedModifiedAt = modified
        mutedLoaded = true
    }

    /// More than one host is actually answering, which is the only case
    /// where naming the host tells you anything (v10). One hop means "on
    /// studio" is a constant with a single value.
    private var fleetIsPlural: Bool {
        poller.state.hosts.filter { $0.error == nil && $0.pollCount > 0 }.count > 1
    }

    private func post(_ event: SessionEvent) {
        let content = UNMutableNotificationContent()
        // Every line carries payload or is not drawn (v10). What was here
        // — "<name> is waiting" over "on studio" over "Click to attach" —
        // was three constants and a name: everything that notifies is
        // waiting, there is one host, and the click has always attached.
        content.title = event.title(showingHost: fleetIsPlural)
        // The receipt, for a session that ended having produced something:
        // "done" and "done, and there are two PRs" are different decisions.
        if let receipt = event.receipt { content.subtitle = receipt }
        // Whole and untruncated — macOS clamps it to two lines and gives
        // the rest back on hover, a better cut than any computed here.
        content.body = event.body ?? event.ref.description
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

    /// A hook event from `ccc hook` (v3, slice 2). The mapping is
    /// `HookEvent.notice(in:)`, tested on its own; this is the posting.
    /// Returns the sentence the command prints.
    func receive(_ event: HookEvent) -> String {
        hooks += 1
        reloadMutesIfMoved()
        let notice = event.notice(in: poller.state.rows)
        lastHook = notice.headline
        guard !muted.contains(Host.localName) else {
            hooksMuted += 1
            return "muted: \(notice.headline)"
        }
        guard Self.isAvailable else { return "no notification center (not a bundle): \(notice.headline)" }
        let content = UNMutableNotificationContent()
        content.title = notice.headline
        content.body = notice.body
        // The roster already rang for a blocked session; the hook is adding
        // the question under the same banner, and a second sound would be
        // the same turn announced twice.
        content.sound = notice.novel ? .default : nil
        content.threadIdentifier = notice.threadId
        if let ref = notice.ref { content.userInfo = ["host": ref.host, "id": ref.id] }
        let request = UNNotificationRequest(identifier: notice.threadId, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        posted += 1
        return (notice.novel ? "posted: " : "updated: ") + notice.headline
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
        let ref: SessionRef?
        if let host = info["host"] as? String, let id = info["id"] as? String {
            ref = SessionRef(host: host, id: id)
        } else {
            ref = nil
        }
        Task { @MainActor in
            NSApp.activate()
            self.attach(ref)
        }
        completionHandler()
    }
}
