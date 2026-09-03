import Foundation

/// What the harness's `Notification` hook hands `ccc hook` on stdin (v3,
/// slice 2). The poll is the first notifier and stays it; the hook is for
/// **what the roster cannot show** (CLAUDE.md): a foreground `claude` in a
/// terminal has no `state` on its roster row, and a background session
/// blocked on `AskUserQuestion` carries no `waitingFor` (docs/HARNESS.md),
/// so neither can say *what* is being asked. The hook's `message` can.
///
/// Localhost only, by decision (docs/EVIDENCE.md, v3 slice 2): the hook fires on
/// the Mac the session runs on and reaches that Mac's app over the control
/// socket. Nothing is forwarded — another Mac learns of the same session
/// from its own roster poll.
///
/// Decoded leniently: this is a boundary (docs/HARNESS.md lists the fields
/// as documented, not promised), so every field is optional and an
/// unrecognized payload is still an event with whatever it carried.
public struct HookEvent: Codable, Sendable, Equatable {
    public var sessionId: String?
    public var cwd: String?
    /// `permission_prompt`, `idle_prompt`, `elicitation_dialog`, …; the
    /// matcher in settings decides which ever arrive.
    public var notificationType: String?
    /// The harness's own sentence ("Claude needs your permission to use
    /// Bash"). Shown as written, never parsed.
    public var message: String?
    public var title: String?
    public var transcriptPath: String?
    /// When `ccc hook` received it.
    public var at: Date

    public init(sessionId: String? = nil, cwd: String? = nil, notificationType: String? = nil,
                message: String? = nil, title: String? = nil, transcriptPath: String? = nil, at: Date = Date()) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.notificationType = notificationType
        self.message = message
        self.title = title
        self.transcriptPath = transcriptPath
        self.at = at
    }

    /// The hook's stdin: snake_case JSON from the harness. Anything that is
    /// a JSON object decodes; a missing field is `nil`, a field of the
    /// wrong type is dropped rather than failing the event. Not an object
    /// (or not JSON) is `nil` — the caller says so once and exits 0, because
    /// a hook that fails is noise inside the session it fired from.
    public static func decode(_ data: Data, at now: Date = Date()) -> HookEvent? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func string(_ key: String) -> String? {
            guard let value = object[key] as? String, !value.isEmpty else { return nil }
            return value
        }
        return HookEvent(sessionId: string("session_id"), cwd: string("cwd"),
                         notificationType: string("notification_type"), message: string("message"),
                         title: string("title"), transcriptPath: string("transcript_path"), at: now)
    }
}

/// What the app does with a hook event once it has looked the session up
/// in the roster it already polls. Pure, so the mapping is a test and not a
/// banner someone has to watch for.
public struct HookNotice: Sendable, Equatable {
    /// The session to attach to on click, when the roster knows it as a
    /// background session. An interactive session (no short id) or one the
    /// roster has not seen yet has nothing to attach to; the click shows
    /// the window.
    public var ref: SessionRef?
    /// The session as a person would name it: the roster's name, else its
    /// ref, else the last component of its cwd.
    public var subject: String
    public var headline: String
    /// The harness's message, else the session's address.
    public var body: String
    /// The notification request id. A background session's is its ref —
    /// the same id the poll's banner uses — so this *replaces* that banner
    /// rather than stacking a second one under it.
    public var threadId: String
    /// `false` when the roster already shows this session as blocked: the
    /// poll has said "your turn" and rung once; the hook only adds the
    /// reason, quietly. `true` is the case the hook exists for — a session
    /// the roster cannot show as waiting — and rings.
    public var novel: Bool
}

extension HookEvent {
    /// Look the event's session up among `rows` (the local host's — the
    /// hook never fires for a remote one) and decide what to show.
    public func notice(in rows: [SessionRow]) -> HookNotice {
        let row = sessionId.flatMap { sid in
            rows.first { $0.host == Host.localName && $0.session.sessionId == sid }
        }
        let attachable = row.flatMap { $0.session.kind == .background ? $0.ref : nil }
        let folder = cwd.flatMap { URL(filePath: $0).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
        let subject = row?.session.name ?? attachable?.description ?? folder ?? "claude"
        let verb: String
        switch notificationType {
        case "permission_prompt": verb = "needs permission"
        case "idle_prompt", nil: verb = "is waiting"
        case let type? where type.hasPrefix("elicitation"): verb = "is asking"
        case let type?: verb = type.replacingOccurrences(of: "_", with: " ")
        }
        return HookNotice(
            ref: attachable,
            subject: subject,
            headline: "\(subject) \(verb)",
            body: message ?? attachable?.description ?? cwd ?? "",
            threadId: attachable?.description ?? "hook:\(sessionId ?? cwd ?? "unknown")",
            novel: row?.session.state != .blocked
        )
    }
}

/// What `ccc hook --settings` prints: the `hooks` entry for
/// `~/.claude/settings.json` that routes the harness's notifications to
/// this command. ccc never writes that file — it is the user's (and their
/// dotfiles'); this is the line to paste.
public enum HookSettings {
    /// The `notification_type`s worth a banner. `auth_success` and the
    /// quota notices are not "your turn"; `agent_*` fire only while the
    /// agents view is open (docs/HARNESS.md) and the poll covers them.
    public static let matcher = "permission_prompt|idle_prompt|elicitation_.*"

    public static func snippet(command: String) -> String {
        let object: [String: Any] = [
            "hooks": [
                "Notification": [[
                    "matcher": matcher,
                    "hooks": [["type": "command", "command": "\(command) hook", "timeout": 5]],
                ]],
            ],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
