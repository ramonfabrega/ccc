import Foundation
import Testing

@testable import CCCKit

/// v3 slice 2: the harness's Notification hook is for what the roster
/// cannot show. Everything here is a payload plus a roster in, a notice
/// out — the banner itself is the app's, this is what it says and whether
/// it rings.
@Suite struct HookTests {
    private func row(_ id: String, sessionId: String, kind: Session.Kind = .background, state: Session.State? = nil,
                     name: String? = nil, host: String = Host.localName) -> SessionRow {
        SessionRow(session: Session(id: id, cwd: "/Users/me/code/thing", kind: kind, startedAt: Date(timeIntervalSince1970: 0),
                                    state: state, sessionId: sessionId, name: name),
                   host: host, model: nil, attached: false)
    }

    private let permission = Data(#"""
    {"session_id":"sid-1","transcript_path":"/t.jsonl","cwd":"/Users/me/code/thing","permission_mode":"default",
     "hook_event_name":"Notification","message":"Claude needs your permission to use Bash","title":"Claude Code",
     "notification_type":"permission_prompt"}
    """#.utf8)

    @Test func theHarnessPayloadDecodesLeniently() {
        let event = HookEvent.decode(permission, at: Date(timeIntervalSince1970: 5))
        #expect(event?.sessionId == "sid-1")
        #expect(event?.notificationType == "permission_prompt")
        #expect(event?.message == "Claude needs your permission to use Bash")
        #expect(event?.at == Date(timeIntervalSince1970: 5))
        // A field of the wrong type is dropped, never a failure; an object
        // with nothing we know is still an event.
        let epoch = Date(timeIntervalSince1970: 0)
        #expect(HookEvent.decode(Data(#"{"session_id":42,"unknown":true}"#.utf8), at: epoch) == HookEvent(at: epoch))
        #expect(HookEvent.decode(Data("not json".utf8)) == nil)
        #expect(HookEvent.decode(Data("[1,2]".utf8)) == nil)
    }

    /// The case the hook exists for: a foreground `claude` has no state on
    /// its roster row, so only the hook says it wants permission. Nothing
    /// to attach to; it rings.
    @Test func anInteractiveSessionIsNovelAndNotAttachable() throws {
        let event = try #require(HookEvent.decode(permission))
        let notice = event.notice(in: [row("cc-thing-f7", sessionId: "sid-1", kind: .interactive, name: "cc-thing-f7")])
        #expect(notice.ref == nil)
        #expect(notice.subject == "cc-thing-f7")
        #expect(notice.headline == "cc-thing-f7 needs permission")
        #expect(notice.body == "Claude needs your permission to use Bash")
        #expect(notice.novel)
        #expect(notice.threadId == "hook:sid-1")
    }

    /// A background session the roster already shows blocked has rung
    /// once through the poll. The hook adds the question under the same
    /// request id — the poll's banner is replaced, not stacked — quietly.
    @Test func aBlockedBackgroundSessionIsUpdatedUnderThePollsBanner() throws {
        let event = try #require(HookEvent.decode(permission))
        let notice = event.notice(in: [row("a1b2", sessionId: "sid-1", state: .blocked, name: "worker")])
        #expect(notice.ref == SessionRef(id: "a1b2"))
        #expect(notice.threadId == "a1b2")
        #expect(notice.headline == "worker needs permission")
        #expect(!notice.novel)
    }

    /// The hook can beat the poll by up to one tick: a background session
    /// the roster still shows working is news, and attachable.
    @Test func aWorkingBackgroundSessionIsNovelAndAttachable() throws {
        let event = try #require(HookEvent.decode(permission))
        let notice = event.notice(in: [row("a1b2", sessionId: "sid-1", state: .working)])
        #expect(notice.ref == SessionRef(id: "a1b2"))
        #expect(notice.subject == "a1b2")
        #expect(notice.novel)
    }

    /// A session the roster has not met (started a moment ago, or a child
    /// session that never registers — docs/HARNESS.md) is named by its
    /// folder. And a remote row with the same session id is not it: the
    /// hook only ever fires on this Mac.
    @Test func anUnknownSessionIsNamedByItsFolder() throws {
        let event = try #require(HookEvent.decode(permission))
        let notice = event.notice(in: [row("zz", sessionId: "sid-1", state: .blocked, host: "air")])
        #expect(notice.ref == nil)
        #expect(notice.subject == "thing")
        #expect(notice.headline == "thing needs permission")
        #expect(notice.novel)
    }

    @Test func theVerbFollowsTheKind() {
        func headline(_ type: String?) -> String {
            HookEvent(sessionId: "s", cwd: "/x/proj", notificationType: type).notice(in: []).headline
        }
        #expect(headline("idle_prompt") == "proj is waiting")
        #expect(headline("elicitation_dialog") == "proj is asking")
        #expect(headline(nil) == "proj is waiting")
        #expect(headline("quota_auto_resume_started") == "proj quota auto resume started")
        let bare = HookEvent().notice(in: [])
        #expect(bare.headline == "claude is waiting")
        #expect(bare.threadId == "hook:unknown")
    }

    /// The snippet is what goes in settings.json by hand; the command is
    /// absolute when `ccc` is installed, and the matcher names only the
    /// "your turn" kinds.
    @Test func theSettingsSnippetRoutesTheHookHere() throws {
        let snippet = HookSettings.snippet(command: "/opt/homebrew/bin/ccc")
        let object = try #require(try JSONSerialization.jsonObject(with: Data(snippet.utf8)) as? [String: Any])
        let hooks = try #require(object["hooks"] as? [String: Any])
        let entries = try #require(hooks["Notification"] as? [[String: Any]])
        #expect(entries.count == 1)
        #expect(entries[0]["matcher"] as? String == "permission_prompt|idle_prompt|elicitation_.*")
        let command = try #require((entries[0]["hooks"] as? [[String: Any]])?.first)
        #expect(command["command"] as? String == "/opt/homebrew/bin/ccc hook")
        #expect(command["type"] as? String == "command")
    }

    /// The wire: an event crosses the socket whole, and an older `ccc`
    /// that never sends `hook` is unaffected — the case is additive.
    @Test func aHookRequestCrossesTheSocket() throws {
        let event = HookEvent(sessionId: "s", cwd: "/x", notificationType: "idle_prompt", message: "m",
                              at: Date(timeIntervalSince1970: 1_700_000_000))
        let decoded = try JSONDecoder().decode(ControlRequest.self, from: JSONEncoder().encode(ControlRequest.hook(event: event)))
        guard case .hook(let back) = decoded else {
            Issue.record("not a hook: \(decoded)")
            return
        }
        #expect(back == event)
    }

    /// `ccc stats` from a newer command against an older app: the new
    /// notification fields are absent and that decodes as "not reported".
    @Test func notificationStatsWithoutTheNewFieldsStillDecode() throws {
        let json = Data(#"{"authorization":"authorized","posted":3}"#.utf8)
        let stats = try JSONDecoder().decode(NotificationStats.self, from: json)
        #expect(stats.muted == nil)
        #expect(stats.hooks == nil)
        #expect(stats.lastHook == nil)
    }
}
