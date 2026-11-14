import Foundation

/// `ccc clear <ref>` (item 27): the loop's "clear and continue" step, as a
/// verb instead of something the user types by hand.
///
/// **ccc can type into a pane, and is the only thing that can** — that is
/// the whole reason this lives here and not in lore, which keys on the job
/// and would be looking at the same job either way (a clear changes the
/// session uuid and nothing else: measured, `daemonShort`, `pid`,
/// `respawnFlags`, `name` and `bridgeSessionId` all hold).
///
/// The caller is normally the commander on **its own ref**, the last act
/// after an item lands — the only seat that knows the bank is complete.
/// Which is why the verb arms rather than waits: while `ccc clear` runs,
/// the row it names is busy *because of that call*, so a verb that blocked
/// until idle would be waiting for itself. It writes the intent to the
/// overlay and returns; whatever owns a pane on that Mac fires it on a
/// later poll (`PaneController.fireArmedClears`).
public enum ClearGuard {
    /// The bank has to be committed before the context goes. `nil` when
    /// there is nothing to refuse — no git here, or a clean tree.
    public static func refusal(cwd: String, git: String = WorktreeProbe.defaultGit) -> String? {
        guard let status = try? Git.run(git, ["-C", cwd, "status", "--porcelain", "--untracked-files=no"]).stdout,
              !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let n = status.split(separator: "\n").count
        return "\(cwd) has \(n) uncommitted change\(n == 1 ? "" : "s"); commit the bank first — a clear before it is committed is how state is lost"
    }
}

/// When an armed clear may fire, read off the row. The gate is not
/// politeness: measured 2026-09-06, a `/clear` typed while the session was
/// generating took effect immediately and the running turn's output was
/// gone — no error, no trace, the transcript simply empty.
///
/// **It asks the job file, not the daemon.** `ccc clear` shipped reading
/// the roster's `status`, and within the hour the first commander to use
/// it sat armed and never fired: `status` means *something live is
/// attached to this session* — a Monitor, a background bash — where the
/// question here is *is the turn over and the box free to type into*,
/// which is `tempo` (`docs/EVIDENCE.md` "item 27 — the gate read the
/// wrong field"). A commander holding a persistent watch is `busy` for as
/// long as it holds it, so reading `status` made the verb useless to
/// exactly the loop it was built for.
///
/// Firing with background tasks in flight is deliberate, not tolerated:
/// the turn is over, the box is free, and a Monitor that fires afterwards
/// simply opens a fresh turn in the fresh context — which is the point of
/// clearing.
///
/// **There is no `--after-tasks` flag, and the first user is why.** Asked
/// whether a clear should wait for `inFlight.tasks == 0`, attrition — a
/// commander that has held one to four live tasks all session — argued
/// against building it, and the argument is better than the question:
/// not all background tasks are equal. An ambient watch and a
/// load-bearing `cargo test --release` gate both surface as `local_bash`
/// and **cannot be told apart from out here**, so a flag could not
/// protect the case that needs protecting — a clear landing mid-gate,
/// handing the fresh context a bare "exit 0" for a merge it has no memory
/// of making. What prevents that is the caller's own rule, *arm only when
/// the gate is green and pushed*, which leaves only ambient tasks live at
/// arm time by construction. The discipline belongs where the knowledge
/// is. A flag that existed would be used to paper over arming at the
/// wrong moment; if a second user ever needs it, opt-in is the shape.
///
/// **`blocked` is two shapes, and only one of them waits** (amended
/// 2026-11-10). It used to wait on both, for a stated reason — a session
/// that ended its turn by asking "has not finished and whose question a
/// clear would throw away" — and that reading cost attrition's steer row
/// 7h35m armed, silent, on a Mac that was awake: its banking turn armed
/// the clear and closed with two asks, the daemon read the close as
/// `blocked`, and nothing fired until a person cleared by hand
/// (`docs/EVIDENCE.md` "item 27 — the arm that waited on its own ask").
/// The three clears that fired on the same row that day ended `done`.
///
/// Measured the same day on five owned fixtures (haiku and sonnet,
/// harness 2.1.321), the two shapes are separable from out here:
///
///     a dialog is up, mid-turn    roster blocked · status waiting · waitingFor set     job state working
///     the turn ended on an ask    roster blocked · status idle    · no waitingFor      job state blocked
///
/// (`tempo` reads `blocked` in both, so it cannot be the discriminator —
/// and it is why an ask-ended row was held twice: once by the roster's
/// state, once by a tempo that is not `idle`.)
///
/// A dialog still waits, and has to: the cursor is not in a prompt box,
/// the turn is not over, and Enter there answers a question that is the
/// user's. An ask-ended turn fires. The arm is an explicit instruction
/// that this context is finished, given by the only seat that knows the
/// bank is complete; the ask it clears over was already bannered by the
/// poll, stays in the transcript, and is quoted in the fire's record —
/// which is the same argument as `--after-tasks` above, pointed the
/// other way: the discipline belongs where the knowledge is, and a
/// daemon's reading of closing prose is not knowledge. `PromptBox` is
/// still the last word at the pane: a row that does not read as an input
/// box is never typed into, whatever the roster said.
public enum ClearWindow: String, Sendable {
    /// The turn is over and the box is ours to type into.
    case now
    /// Working, a dialog up, or between polls: wait.
    case wait
    /// Failed, stopped, or off the roster: the clear will never fire and
    /// the mark should go.
    case gone

    /// The gate's answer **and its reason**, as one value, so the side
    /// that fires and the side that reports (`ccc clear --status`) cannot
    /// disagree. `why` is a clause: it follows "waiting: " or "it will be
    /// dropped: ". Before this the wait had no words at all — `--status`
    /// printed the constant "it fires when the row is idle" over a row
    /// that had been blocked for seven hours.
    public struct Reading: Sendable, Equatable {
        public var window: ClearWindow
        public var why: String

        public init(_ window: ClearWindow, _ why: String) {
            self.window = window
            self.why = why
        }
    }

    public static func of(_ session: Session, job: JobInfo? = nil) -> ClearWindow {
        read(session, job: job).window
    }

    public static func read(_ session: Session, job: JobInfo? = nil) -> Reading {
        guard session.kind == .background else { return Reading(.gone, "it is an interactive session") }
        switch session.state {
        case .failed: return Reading(.gone, "its session failed")
        case .stopped: return Reading(.gone, "its session was stopped")
        case .blocked:
            // A dialog: the roster says so in two fields, and either is
            // enough.
            if session.status == .waiting || !(session.waitingFor ?? "").isEmpty {
                return Reading(.wait, "a dialog is up (\(session.waitingFor ?? "the row is waiting on one"))")
            }
            // No dialog. Whether the turn is over is still the job file's
            // word, and without one a blocked row is not ours to judge.
            switch job?.tempo {
            case "blocked"?, "idle"?: return Reading(.now, "its turn ended on an ask")
            case "active"?: return Reading(.wait, "its turn is running")
            case let word?: return Reading(.wait, "its job file reads tempo `\(word)`, a word this build does not know")
            case nil: return Reading(.wait, "the row is blocked and no job file says its turn is over")
            }
        case .working, .done, .none: break
        }
        // The job file's word when there is one; a word this build has
        // not met is "not idle", never a crash and never a fire.
        if let tempo = job?.tempo {
            switch tempo {
            case "idle": return Reading(.now, "the row is idle")
            case "active": return Reading(.wait, "its turn is running")
            case "blocked": return Reading(.wait, "its job file says a question is up and the roster has not said which kind")
            default: return Reading(.wait, "its job file reads tempo `\(tempo)`, a word this build does not know")
            }
        }
        // No job file — a row read across the hop from a ccc that does
        // not carry `tempo` yet, or a job whose file said nothing. The
        // daemon's `status` is the older, coarser answer: it never fires
        // early, it only ever waits too long.
        switch session.status {
        case .idle?: return Reading(.now, "the row is idle")
        case let status?: return Reading(.wait, "the row is \(status.rawValue)")
        case nil: return Reading(.wait, "neither the job file nor the roster says the row is idle")
        }
    }
}

/// What an armed clear is going to do, said for a reader: the gate's
/// reading joined to the three things the gate does not look at — is the
/// row still there, is it still the session the arm named, and is any ccc
/// up to fire it. `--status` and bare `ccc clear` both print this, and
/// the pane records it once when an arm has waited past the bound.
public struct ClearOutlook: Sendable, Equatable {
    /// The clause after "a clear is armed on <ref> (<age> ago); ".
    public var said: String
    /// What it is waiting on, when it is waiting on something — `nil`
    /// when it is about to fire or about to be dropped.
    public var waiting: String?

    public static func of(mark: SessionMark, row: Session?, rosterRead: Bool, job: JobInfo?,
                          serving: Bool, socket: String = ControlSocket.defaultPath, now: Date = Date()) -> ClearOutlook {
        // No roster to read it against: the old sentence, which is true
        // and says nothing — and is all this side knows.
        guard rosterRead else { return ClearOutlook(said: "it fires when its turn ends", waiting: nil) }
        guard let row else { return ClearOutlook(said: "it will be dropped: its session is off the roster", waiting: nil) }
        if let theirs = mark.sessionId, let ours = row.sessionId, theirs != ours {
            return ClearOutlook(said: "it will be dropped: another session answers to that id now", waiting: nil)
        }
        let reading = ClearWindow.read(row, job: job)
        switch reading.window {
        case .gone: return ClearOutlook(said: "it will be dropped: \(reading.why)", waiting: nil)
        case .wait:
            let moved = job?.updatedAt.map { ", row last moved \(SessionEvent.spell(now.timeIntervalSince($0))) ago" } ?? ""
            let waiting = reading.why + moved
            return ClearOutlook(said: "waiting: \(waiting)", waiting: waiting)
        case .now:
            guard serving else {
                let waiting = "no ccc is serving \(socket) to fire it — open ccc.app or run `ccc attach <ref> --headless`"
                return ClearOutlook(said: "\(reading.why), but \(waiting)", waiting: waiting)
            }
            return ClearOutlook(said: "\(reading.why); it fires on the next tick", waiting: nil)
        }
    }
}

extension ClaudeCLI {
    public struct ClearOutcome: Codable, Sendable {
        public var ref: String
        /// Whether a clear is armed on the row now.
        public var armed: Bool
        /// What it will type after the clear, when it was given one.
        public var then: String?
        /// Whether this call cancelled one that was already armed.
        public var cancelled: Bool
        public var said: String
        /// `--status` only: when the armed clear was armed, ISO 8601 — a
        /// string, so it crosses the hop in whatever shape it left in.
        public var armedAt: String?
        /// `--status` only: what became of the last clear on the row —
        /// fired, refused or dropped — as the firing side said it.
        public var last: String?
        /// `--status` only: what an armed clear is waiting on, read live
        /// off the row — "a dialog is up (permission prompt), row last
        /// moved 3h ago". Absent when it is about to fire, about to be
        /// dropped, or the roster could not be read.
        public var waiting: String?
        /// `--status` only: the `--then` prompt the last clear on the row
        /// carried and never typed, whole — `ccc clear <ref> --then` with
        /// it is the re-arm. Absent when the last clear typed all it had.
        public var undelivered: String?

        public init(ref: String, armed: Bool, then: String? = nil, cancelled: Bool = false, said: String,
                    armedAt: String? = nil, last: String? = nil, waiting: String? = nil, undelivered: String? = nil) {
            self.ref = ref
            self.armed = armed
            self.then = then
            self.cancelled = cancelled
            self.said = said
            self.armedAt = armedAt
            self.last = last
            self.waiting = waiting
            self.undelivered = undelivered
        }
    }

    /// What `ccc clear` does to the row. `status` is the read — the one a
    /// commander asking "am I still armed?" reaches for — and before it
    /// existed the only per-row question the verb took was `--cancel`,
    /// which answers by disarming: attrition's commander asked it four
    /// times across two tranches and no clear fired in either
    /// (2026-09-30 – 10-01, sessions ran to 402 k and 322 k of context).
    public enum ClearAction: String, Sendable {
        case arm, cancel, status

        var flag: String? {
            switch self {
            case .arm: return nil
            case .cancel: return "--cancel"
            case .status: return "--status"
            }
        }
    }

    public enum ClearError: Error, CustomStringConvertible {
        case notBackground(String)
        case dirty(String)
        case noRemoteCCC(String)
        /// The socket, and — when the CLI tried to start the app — why
        /// that did not work.
        case nothingToFireIt(String, String?)
        public var description: String {
            switch self {
            case .notBackground(let id): return "\(id) is an interactive session; ccc has no pane on it to type into"
            case .dirty(let reason): return reason
            case .noRemoteCCC(let host): return "a clear is armed where the session lives, and \(host) has no ccc for it (`ccc hosts add \(host)` finds one)"
            case .nothingToFireIt(let path, let wake):
                let tried = wake.map { " (\($0))" } ?? ""
                return "nothing would fire it: no ccc is serving \(path)\(tried) — open ccc.app or run `ccc attach <ref> --headless` there, then arm it again"
            }
        }
    }

    /// The outlook for every clear armed on this Mac, keyed by row id —
    /// bare `ccc clear`'s half of the same read `--status` makes. One
    /// roster read for all of them, and none when nothing is armed.
    public func clearOutlooks(overlayPath: String = RosterOverlay.defaultPath,
                              serving: @Sendable () -> Bool = { ControlClient().isReachable() },
                              job: @Sendable (String) -> JobInfo? = { JobProbe().info(forJob: $0) }) async -> [String: ClearOutlook] {
        let armed = RosterOverlay.load(path: overlayPath).overlay.armedClears
        guard !armed.isEmpty else { return [:] }
        let sessions = (try? await agentsJSON()).map { RosterDecoder.decode($0).sessions }
        let up = serving()
        return Dictionary(uniqueKeysWithValues: armed.map { entry in
            (entry.id, ClearOutlook.of(mark: entry.mark, row: sessions?.first { $0.id == entry.id },
                                       rosterRead: sessions != nil, job: job(entry.id), serving: up))
        })
    }

    /// Arm (or, with `cancel`, disarm) a clear on this host's session.
    /// Local: the roster read, the bank check, then the overlay under its
    /// lock. Remote: the same verb on the far side, its answer passed
    /// through — the mark road `ccc archive` takes, for the same reason
    /// (the pending clear belongs next to the session, and the pane that
    /// fires it is over there).
    public func clear(id: String, then: String? = nil, cancel: Bool = false,
                      overlayPath: String = RosterOverlay.defaultPath,
                      serving: @Sendable () -> Bool = { ControlClient().isReachable() },
                      wake: (@Sendable () async -> AppWake.Refusal?)? = nil) async throws -> ClearOutcome {
        try await clear(id: id, then: then, action: cancel ? .cancel : .arm, overlayPath: overlayPath,
                        serving: serving, wake: wake)
    }

    /// `wake` is what an arm does when nothing is serving: bring a ccc up
    /// and answer `nil`, or say why it could not. It defaults to **none**
    /// — the library never starts an app on its own; the CLI passes
    /// `AppWake.wake` and a test passes a closure.
    public func clear(id: String, then: String? = nil, action: ClearAction,
                      overlayPath: String = RosterOverlay.defaultPath,
                      serving: @Sendable () -> Bool = { ControlClient().isReachable() },
                      wake: (@Sendable () async -> AppWake.Refusal?)? = nil,
                      job: @Sendable (String) -> JobInfo? = { JobProbe().info(forJob: $0) }) async throws -> ClearOutcome {
        let cancel = action == .cancel
        guard host.isLocal else {
            guard let ccc = host.ccc, let destination = host.ssh else { throw ClearError.noRemoteCCC(host.name) }
            var words = [ccc, "clear", id]
            if let flag = action.flag { words.append(flag) }
            if let then { words += ["--then", Self.remoteWord(then)] }
            // The read's answer has a shape a sentence cannot carry back
            // (armed or not is the whole question), so it asks for JSON.
            if action == .status { words.append("--json") }
            try prepareControlDirectory()
            let out = try await run(sshPrefix(tty: false, destination: destination) + words, program: "ccc")
            if action == .status, let answer = try? JSONDecoder().decode(ClearOutcome.self, from: out) {
                return answer
            }
            let said = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return ClearOutcome(ref: id, armed: action == .arm, then: then, cancelled: cancel, said: said)
        }

        if action == .status {
            // Read-only, and lock-free for it: nothing is written, and a
            // name resolves the way cancel's does — the overlay's own key
            // first, the roster only as the fallback, and a roster that
            // cannot answer is "no such key", never an error.
            let overlay = RosterOverlay.load(path: overlayPath).overlay
            var key = id
            // The roster is read once, and only when something needs it:
            // a name to resolve, or an arm whose wait wants a reason.
            var sessions: [Session]?
            if overlay.marks[id] == nil || overlay.marks[id]?.clear != nil, let json = try? await agentsJSON() {
                sessions = RosterDecoder.decode(json).sessions
            }
            if overlay.marks[id] == nil, let row = sessions?.sessionIfAny(matching: id) {
                key = row.id
            }
            let mark = overlay.marks[key]
            let stamp = ISO8601DateFormatter()
            let last = mark?.fired.map { "\(SessionEvent.spell(Date().timeIntervalSince($0.at))) ago · \($0.said)" }
            // The prompt the last clear left untyped, in full: the reader
            // here is usually another session, and these words are what
            // it needs to arm again.
            let undelivered = mark?.fired?.undelivered
            let tail = (last.map { "; last: \($0)" } ?? "") + (undelivered.map { "; undelivered: \($0)" } ?? "")
            guard let pending = mark?.clear else {
                return ClearOutcome(ref: key, armed: false, said: "no clear is armed on \(key)\(tail)", last: last,
                                    undelivered: undelivered)
            }
            let then = pending.then.map { ", then: \($0)" } ?? ""
            // What it is waiting on, read off the row the way the firing
            // side reads it. "Armed" with no reason is what a row blocked
            // for seven hours printed (2026-11-10).
            let outlook = ClearOutlook.of(mark: mark ?? SessionMark(), row: sessions?.first { $0.id == key },
                                          rosterRead: sessions != nil, job: job(key), serving: serving())
            return ClearOutcome(ref: key, armed: true, then: pending.then,
                                said: "a clear is armed on \(key) (\(SessionEvent.spell(Date().timeIntervalSince(pending.armedAt))) ago); \(outlook.said)\(then)\(tail)",
                                armedAt: stamp.string(from: pending.armedAt), last: last, waiting: outlook.waiting,
                                undelivered: undelivered)
        }

        if cancel {
            // A name only needs resolving when it is not already a key —
            // and cancel must keep working on a row the roster has
            // forgotten, so the roster read is the fallback, not the road.
            var key = id
            if RosterOverlay.load(path: overlayPath).overlay.marks[id] == nil,
               let row = RosterDecoder.decode(try await agentsJSON()).sessions.sessionIfAny(matching: id) {
                key = row.id
            }
            return try RosterOverlay.locked(path: overlayPath) {
                var overlay = RosterOverlay.load(path: overlayPath).overlay
                let previous = overlay.arm(nil, id: key, sessionId: overlay.marks[key]?.sessionId)
                guard previous != nil else {
                    return ClearOutcome(ref: key, armed: false, said: "no clear was armed on \(key)")
                }
                try overlay.save(path: overlayPath)
                return ClearOutcome(ref: key, armed: false, cancelled: true, said: "cancelled the clear armed on \(key)")
            }
        }

        let roster = RosterDecoder.decode(try await agentsJSON())
        let row = try roster.sessions.session(matching: id)
        guard row.kind == .background else { throw ClearError.notBackground(id) }
        // An arm is a promise that something types minutes from now, and
        // the only things that can are the app and a headless attach —
        // both of which serve the control socket. When neither is up the
        // mark would sit in the file until it was pruned, and the caller
        // (a session arming a clear on itself) would never learn that.
        // `armed: true` has to mean it can fire. So when nothing is up
        // the arm starts the app rather than report its absence to a
        // caller that cannot open one (`AppWake`), and refuses only when
        // that did not work — with the reason, which is the part a
        // session can act on.
        if !serving() {
            guard let wake else { throw ClearError.nothingToFireIt(ControlSocket.defaultPath, nil) }
            if let refusal = await wake() {
                throw ClearError.nothingToFireIt(ControlSocket.defaultPath, "\(refusal)")
            }
        }
        if let reason = ClearGuard.refusal(cwd: row.cwd) { throw ClearError.dirty(reason) }

        let pending = PendingClear(then: then)
        return try RosterOverlay.locked(path: overlayPath) {
            var overlay = RosterOverlay.load(path: overlayPath).overlay
            // Keyed on the ROW's id, never on the word the caller used.
            // `ccc clear desk` resolves the name for every check above and
            // then filed the mark under "desk", where the poller — which
            // joins marks on `session.id` — could not see it and the pane
            // read "no such row" and dropped it on the next tick. Measured
            // twice by hail on a live `--bg` session, both times reported
            // as "the arm succeeds and nothing ever happens"
            // (`docs/EVIDENCE.md`, "the name that resolved for the read
            // and not for the write").
            overlay.arm(pending, id: row.id, sessionId: row.sessionId)
            try overlay.save(path: overlayPath)
            return ClearOutcome(ref: row.id, armed: true, then: then, said: pending.said(row.id))
        }
    }
}
