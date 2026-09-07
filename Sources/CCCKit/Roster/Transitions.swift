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
        /// **Working, and not moving** (item 21). The one event that is a
        /// *non-*event: nothing happened to the row for long enough that
        /// the not-happening is the news. See `StallWindow`.
        case stalled
    }

    public var kind: Kind
    public var ref: SessionRef
    public var name: String?
    /// What it is waiting on, for `blocked`.
    public var waitingFor: String?
    /// How long the session had been still, for `stalled`.
    public var stillFor: TimeInterval?
    /// What the daemon's job file said at the moment of the transition
    /// (v10). The roster says *that* it is your turn; this is what for.
    public var job: JobInfo?
    public var at: Date

    public init(kind: Kind, ref: SessionRef, name: String?, waitingFor: String? = nil,
                job: JobInfo? = nil, at: Date, stillFor: TimeInterval? = nil) {
        self.kind = kind
        self.ref = ref
        self.name = name
        self.waitingFor = waitingFor
        self.job = job
        self.at = at
        self.stillFor = stillFor
    }

    /// The session as a person would name it: its name, else its ref.
    public var subject: String { name ?? ref.description }

    /// One sentence, for the places that want a sentence: `ccc watch`'s
    /// line, which already has a `kind` column, and `ccc stats`' last
    /// event. **Not the banner's title** — a banner that spends its bold
    /// line on "is waiting" has said nothing, since everything that
    /// notifies is waiting (v10).
    public var headline: String {
        switch kind {
        case .blocked: return "\(subject) is waiting" + (waitingFor.map { ": \($0)" } ?? "")
        case .done: return "\(subject) finished"
        case .failed: return "\(subject) failed"
        case .stopped: return "\(subject) stopped"
        case .stalled:
            return "\(subject) has not moved in \(Self.spell(stillFor ?? 0))"
        }
    }

    /// "45s", "35m", "2h10m", "2 days" — a duration a person reads at a
    /// glance, which is the whole content of a stall. Seconds only below a
    /// minute: no honest window is that short, but a test one is, and
    /// "has not moved in 0m" reads as a bug rather than as a small number.
    public static func spell(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "\(max(0, Int(seconds)))s" }
        if minutes < 90 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 48 { return hours * 60 == minutes ? "\(hours)h" : "\(hours)h\(minutes % 60)m" }
        return "\(hours / 24) days"
    }

    /// The payload: what the session is asking, or what it did. Whole and
    /// untruncated on purpose — the banner clamps it to two lines and
    /// gives the rest back on hover, which is a better cut than any this
    /// side could compute (v10).
    ///
    /// **The job file wins over `waitingFor`**, which is the opposite of
    /// what this first did. A fixture blocked on `AskUserQuestion`
    /// 2026-09-04 answered `waitingFor: "input needed"` — a placeholder,
    /// and precisely the sort of constant this slice exists to delete —
    /// while its job file held `"answer: Should the banner show the
    /// branch? (Yes, show it · No, keep it in the roster)"`. The roster's
    /// word is sometimes a sentence and sometimes a placeholder and
    /// nothing distinguishes them at the boundary, so it is the fallback
    /// for when there is no job file at all.
    public var body: String? {
        // A stall's body is the last thing the session said it was doing
        // — which is exactly the sentence that stopped changing, and the
        // most useful thing to read when deciding whether to look.
        let state: Session.State = kind == .blocked ? .blocked : kind == .stalled ? .working : .done
        guard let said = job?.say(for: state) else {
            let fallback = kind == .blocked ? waitingFor : nil
            return (fallback?.isEmpty == false) ? fallback : nil
        }
        // The daemon's extraction is ragged — a real one began "prod), and
        // do you want fake captures…" — so a fragment gets a leading
        // ellipsis and reads as deliberate instead of broken.
        return Self.looksClipped(said) ? "…\(said)" : said
    }

    // There is no receipt line. v10 gave the banner one — what came out
    // of the session, from the job file's `children` — and it never had
    // a `blocked` half, because mid-question is not the moment to list
    // what came out. v11 slice 4 deleted the exception rather than the
    // rule: a `done` banner is a title and a sentence too. `JobInfo`
    // carries why, and `docs/EVIDENCE.md` "Fresh at most 6%" the numbers.

    /// One character for the kind, so the banner's title need not spend a
    /// third of its width on a word. `✋` is the roster's own vocabulary —
    /// the header already draws `✋ N waiting` — and `ccc watch` prints the
    /// same mark, because two surfaces disagreeing about a symbol is how
    /// one definition becomes two.
    public var mark: String {
        switch kind {
        case .blocked: return "✋"
        case .done: return "✓"
        case .failed: return "✗"
        case .stopped: return "◼"
        case .stalled: return "⏳"
        }
    }

    /// The banner's title: the mark, the name, and the host only when the
    /// fleet has more than one answering (v10). The host goes **last** so
    /// that the ellipsis eats it rather than the name — a macOS title
    /// clips around 36 characters, and `✋ studio · linear cuanto bill
    /// project` is 37, which would lose the one token that identifies the
    /// session.
    public func title(showingHost: Bool) -> String {
        "\(mark) \(subject)" + (showingHost ? " · \(ref.host)" : "")
    }

    /// `ccc watch`'s line: the sentence, plus whatever the sentence did
    /// not already carry. The `kind` column makes the verb redundant
    /// there, but a log line reads better as prose than as a banner.
    public var watchLine: String {
        var line = headline
        if let body, !headline.hasSuffix(body) { line += " — \(body)" }
        return line
    }

    /// A sentence whose beginning was cut off. **A closing bracket with no
    /// opener**, which is what a lost prefix leaves behind: the real
    /// ragged one read `"prod), and do you want fake captures…"`.
    ///
    /// This started as "begins with a lowercase letter" and that was
    /// wrong — a fixture's `"answer: Should the banner show the branch?"`
    /// tripped it, and so would most honest `detail` lines, which are
    /// terse by nature (`"wiki: TCC identity fix scoped"`, `"detour
    /// arithmetic verified; awaiting capture"`). Lowercase is the normal
    /// register here, not damage.
    ///
    /// Only an unmatched *closer* counts. An unmatched opener means the
    /// tail was cut, which is macOS's job and not a fragment. Scanned over
    /// the opening only, where a lost prefix shows up, so a stray bracket
    /// deep in a 460-character result cannot trip it.
    static func looksClipped(_ text: String) -> Bool {
        var depth: [Character: Int] = ["(": 0, "[": 0, "{": 0]
        let openerFor: [Character: Character] = [")": "(", "]": "[", "}": "{"]
        for character in text.prefix(80) {
            if depth[character] != nil { depth[character]! += 1 }
            if let opener = openerFor[character] {
                if depth[opener]! == 0 { return true }
                depth[opener]! -= 1
            }
        }
        return false
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
        /// Part of the key so a draft that is prompted and then asks a
        /// `waitingFor`-less question still reads as a change.
        var draft = false
    }

    private var seen: [SessionRef: Key] = [:]
    private var primed: Set<String> = []
    /// Refs already reported stalled, so one stall is one event. Cleared
    /// the moment the session moves again, which re-arms it.
    private var stalled: Set<SessionRef> = []
    /// How long a `working` session may stay still before it is news.
    public var stallWindow: StallWindow

    public init(stallWindow: StallWindow = .fromEnvironment()) {
        self.stallWindow = stallWindow
    }

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
                let key = Key(state: s.state, waitingFor: s.waitingFor.flatMap { $0.isEmpty ? nil : $0 }, draft: row.draft)
                let before = seen[ref]
                seen[ref] = key
                // The stall check runs *before* the change guard, because
                // a stall is precisely what happens when the key does not
                // change. A host's first answer still arms it silently,
                // the way every other kind is armed: launching in front of
                // three long-still sessions must not fire three banners.
                // The standing ones are context, and the surfaces say them
                // as context (`ccc watch`'s opening line).
                if let event = stallEvent(row, now: now), !first { events.append(event) }
                guard !first, before != key else { continue }
                switch key.state {
                case .blocked:
                    // A draft is blocked on you starting it — the one
                    // "blocked" that is not your turn (v5). It becomes news
                    // when it is prompted and then asks something.
                    guard !key.draft else { continue }
                    events.append(SessionEvent(kind: .blocked, ref: ref, name: s.name, waitingFor: key.waitingFor,
                                               job: row.job, at: now))
                case .done, .failed, .stopped:
                    // Only a session that was live is news when it ends; a
                    // new row that arrives already finished is history.
                    guard let was = before, was.state == .working || was.state == .blocked else { continue }
                    events.append(SessionEvent(kind: key.state == .done ? .done : key.state == .failed ? .failed : .stopped,
                                               ref: ref, name: s.name, job: row.job, at: now))
                case .working, nil:
                    continue
                }
            }
            for ref in seen.keys where ref.host == host.host && !present.contains(ref) {
                seen.removeValue(forKey: ref)
                stalled.remove(ref)
            }
        }
        return events
    }
}

extension TransitionDetector {
    /// The stall, if this row is one now. Mutating, because "one stall is
    /// one event" is state: a ref is marked when it fires and unmarked the
    /// moment it moves, which re-arms it for the next one.
    ///
    /// Three things must all hold, and each excludes a false alarm:
    /// - the row says **working**. A `blocked` session that sits is not
    ///   stalled, it is waiting for you, and it already fired its own
    ///   event; a finished one is not doing anything by definition.
    /// - the job file carries an **`updatedAt`**. No clock, no claim: a
    ///   session ccc cannot time is never called stalled, which is the
    ///   same leniency every other read at this boundary has.
    /// - the gap exceeds the window, and the window is **on**.
    private mutating func stallEvent(_ row: SessionRow, now: Date) -> SessionEvent? {
        guard row.session.state == .working, !row.draft else {
            stalled.remove(row.ref)
            return nil
        }
        guard let window = stallWindow.seconds, let moved = row.job?.updatedAt else { return nil }
        let still = now.timeIntervalSince(moved)
        guard still >= window else {
            // It moved since we last looked: whatever this is, it is not
            // the stall we reported.
            stalled.remove(row.ref)
            return nil
        }
        guard stalled.insert(row.ref).inserted else { return nil }
        return SessionEvent(kind: .stalled, ref: row.ref, name: row.session.name,
                            job: row.job, at: now, stillFor: still)
    }
}

/// **How long a working session may stay still before the stillness is the
/// news** (item 21).
///
/// The transition ccc did not have. `blocked`, `done`, `failed` and
/// `stopped` are the only things that ever happen to a row, and on
/// 2026-09-04 cuanto's Lane B — contracted to report at each landing point
/// — sent zero messages and sat with two unpushed commits for two days
/// while every one of those four stayed silent, because it was `working`
/// the whole time. Nothing was wrong with the watcher; there was simply no
/// event for "nothing is happening".
///
/// **30 minutes is a constant, not a measurement**, and it is the only
/// honest thing to say about it: no number here can distinguish a wedged
/// session from one twenty minutes into a release suite. What makes it
/// safe to ship at a guess is the *shape* rather than the value — one
/// event per stall, re-armed only by real movement, so a long legitimate
/// step costs exactly one line and never a stream. `CCC_STALL_MINUTES`
/// moves it and `0` turns it off; the next version of this is
/// cadence-relative (each session against its own median gap), and the
/// thing to do before building that is count how often the fixed one was
/// useful — this fleet's own rule about UI noise, applied in advance.
public struct StallWindow: Sendable, Equatable {
    /// Nil is off.
    public var seconds: TimeInterval?

    public init(minutes: Double?) {
        seconds = (minutes ?? 0) > 0 ? minutes! * 60 : nil
    }

    public static let defaultMinutes = 30.0
    public static let off = StallWindow(minutes: nil)

    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> StallWindow {
        guard let raw = environment["CCC_STALL_MINUTES"], let value = Double(raw), value >= 0 else {
            return StallWindow(minutes: defaultMinutes)
        }
        return StallWindow(minutes: value)
    }
}

extension RosterPoller.State {
    /// The sessions that are `working` and have not moved inside `window`
    /// — the standing stalls, which a surface reports as context at start
    /// rather than as news (see `StallWindow`). Newest movement last, so
    /// the worst offender reads first.
    public func standingStalls(_ window: StallWindow, now: Date = Date()) -> [(row: SessionRow, still: TimeInterval)] {
        guard let seconds = window.seconds else { return [] }
        return rows.compactMap { row in
            guard row.session.state == .working, !row.draft, let moved = row.job?.updatedAt else { return nil }
            let still = now.timeIntervalSince(moved)
            return still >= seconds ? (row, still) : nil
        }.sorted { $0.still > $1.still }
    }
}
