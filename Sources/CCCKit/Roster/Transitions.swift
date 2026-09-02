import Foundation

/// Something that happened to a session between two polls — the unit of
/// "it's your turn" (v3). The poll is the first notifier (CLAUDE.md): the
/// roster already carries `blocked` and `waitingFor` for every host, so
/// air learns that a session on studio wants input without anything being
/// forwarded. One event feeds both faces: a macOS notification in the
/// window face, a line from `ccc watch` for an agent.
public struct SessionEvent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// Became blocked, or blocked on something new. The one that is
        /// actionable: attach and answer.
        case blocked
        /// Left `working`/`blocked` for a terminal state.
        case done, failed, stopped
    }

    public var kind: Kind
    public var ref: SessionRef
    public var name: String?
    /// What it is waiting on, for `blocked`.
    public var waitingFor: String?
    public var at: Date

    public init(kind: Kind, ref: SessionRef, name: String?, waitingFor: String? = nil, at: Date) {
        self.kind = kind
        self.ref = ref
        self.name = name
        self.waitingFor = waitingFor
        self.at = at
    }

    /// The session as a person would name it: its name, else its ref.
    public var subject: String { name ?? ref.description }

    /// One sentence, the same in the notification and on the watch line.
    public var headline: String {
        switch kind {
        case .blocked: return "\(subject) is waiting" + (waitingFor.map { ": \($0)" } ?? "")
        case .done: return "\(subject) finished"
        case .failed: return "\(subject) failed"
        case .stopped: return "\(subject) stopped"
        }
    }
}

/// Turns successive roster states into events. Pure and value-typed: the
/// tests feed it two rosters and read the events, the app and `ccc watch`
/// feed it every tick. Dedup is structural — an event is a *change* in a
/// session's (state, waitingFor) pair, so a 2 s poll that sees the same
/// blocked session thirty times says it once, and a new question on the
/// same session is a new event.
///
/// Rules that keep it honest:
/// - A host's first successful answer is its baseline and says nothing.
///   Launching ccc in front of five blocked sessions must not fire five
///   notifications; the status item already counts them.
/// - A host that is failing contributes nothing: its rows are stale
///   (`HostPoll.isStale`), frozen at the last answer, and re-reading them
///   is not news. When it comes back, what changed meanwhile is reported
///   once, against the last thing it said.
/// - A session that leaves the roster is forgotten silently. Archiving is
///   not an event, and the daemon's own pruning is not our business.
public struct TransitionDetector: Sendable, Equatable {
    private struct Key: Sendable, Equatable {
        var state: Session.State?
        var waitingFor: String?
    }

    private var seen: [SessionRef: Key] = [:]
    private var primed: Set<String> = []

    public init() {}

    /// Hosts that have answered at least once.
    public var primedHosts: Set<String> { primed }

    public mutating func observe(_ roster: RosterPoller.State, at now: Date = Date()) -> [SessionEvent] {
        var events: [SessionEvent] = []
        for host in roster.hosts where host.error == nil && host.pollCount > 0 {
            let first = primed.insert(host.host).inserted
            var present = Set<SessionRef>()
            for row in host.rows {
                let s = row.session
                let ref = row.ref
                present.insert(ref)
                let key = Key(state: s.state, waitingFor: s.waitingFor.flatMap { $0.isEmpty ? nil : $0 })
                let before = seen[ref]
                seen[ref] = key
                guard !first, before != key else { continue }
                switch key.state {
                case .blocked:
                    events.append(SessionEvent(kind: .blocked, ref: ref, name: s.name, waitingFor: key.waitingFor, at: now))
                case .done, .failed, .stopped:
                    // Only a session that was live is news when it ends; a
                    // new row that arrives already finished is history.
                    guard let was = before, was.state == .working || was.state == .blocked else { continue }
                    events.append(SessionEvent(kind: key.state == .done ? .done : key.state == .failed ? .failed : .stopped,
                                               ref: ref, name: s.name, at: now))
                case .working, nil:
                    continue
                }
            }
            for ref in seen.keys where ref.host == host.host && !present.contains(ref) {
                seen.removeValue(forKey: ref)
            }
        }
        return events
    }
}
