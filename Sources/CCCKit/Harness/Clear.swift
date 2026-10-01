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
/// `blocked` still comes from the roster. That is the right source for
/// "a question is up", and it covers both shapes: a permission dialog,
/// where the cursor is not in a prompt box at all, and a session that
/// ended its turn by asking something, which has not finished and whose
/// question a clear would throw away.
public enum ClearWindow: String, Sendable {
    /// Idle, and ours to type into.
    case now
    /// Working, blocked on a question, or between polls: wait.
    case wait
    /// Failed, stopped, or off the roster: the clear will never fire and
    /// the mark should go.
    case gone

    public static func of(_ session: Session, job: JobInfo? = nil) -> ClearWindow {
        guard session.kind == .background else { return .gone }
        switch session.state {
        case .failed, .stopped: return .gone
        case .blocked: return .wait
        case .working, .done, .none: break
        }
        // The job file's word when there is one; a word this build has
        // not met is "not idle", never a crash and never a fire.
        if let tempo = job?.tempo { return tempo == "idle" ? .now : .wait }
        // No job file — a row read across the hop from a ccc that does
        // not carry `tempo` yet, or a job whose file said nothing. The
        // daemon's `status` is the older, coarser answer: it never fires
        // early, it only ever waits too long.
        return session.status == .idle ? .now : .wait
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

        public init(ref: String, armed: Bool, then: String? = nil, cancelled: Bool = false, said: String,
                    armedAt: String? = nil, last: String? = nil) {
            self.ref = ref
            self.armed = armed
            self.then = then
            self.cancelled = cancelled
            self.said = said
            self.armedAt = armedAt
            self.last = last
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
        case nothingToFireIt(String)
        public var description: String {
            switch self {
            case .notBackground(let id): return "\(id) is an interactive session; ccc has no pane on it to type into"
            case .dirty(let reason): return reason
            case .noRemoteCCC(let host): return "a clear is armed where the session lives, and \(host) has no ccc for it (`ccc hosts add \(host)` finds one)"
            case .nothingToFireIt(let path):
                return "nothing would fire it: no ccc is serving \(path) — open ccc.app or run `ccc attach <ref> --headless` there, then arm it again"
            }
        }
    }

    /// Arm (or, with `cancel`, disarm) a clear on this host's session.
    /// Local: the roster read, the bank check, then the overlay under its
    /// lock. Remote: the same verb on the far side, its answer passed
    /// through — the mark road `ccc archive` takes, for the same reason
    /// (the pending clear belongs next to the session, and the pane that
    /// fires it is over there).
    public func clear(id: String, then: String? = nil, cancel: Bool = false,
                      overlayPath: String = RosterOverlay.defaultPath,
                      serving: @Sendable () -> Bool = { ControlClient().isReachable() }) async throws -> ClearOutcome {
        try await clear(id: id, then: then, action: cancel ? .cancel : .arm, overlayPath: overlayPath, serving: serving)
    }

    public func clear(id: String, then: String? = nil, action: ClearAction,
                      overlayPath: String = RosterOverlay.defaultPath,
                      serving: @Sendable () -> Bool = { ControlClient().isReachable() }) async throws -> ClearOutcome {
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
            if overlay.marks[id] == nil, let json = try? await agentsJSON(),
               let row = RosterDecoder.decode(json).sessions.sessionIfAny(matching: id) {
                key = row.id
            }
            let mark = overlay.marks[key]
            let stamp = ISO8601DateFormatter()
            let last = mark?.fired.map { "\(SessionEvent.spell(Date().timeIntervalSince($0.at))) ago · \($0.said)" }
            let tail = last.map { "; last: \($0)" } ?? ""
            guard let pending = mark?.clear else {
                return ClearOutcome(ref: key, armed: false, said: "no clear is armed on \(key)\(tail)", last: last)
            }
            let then = pending.then.map { ", then: \($0)" } ?? ""
            return ClearOutcome(ref: key, armed: true, then: pending.then,
                                said: "a clear is armed on \(key) (\(SessionEvent.spell(Date().timeIntervalSince(pending.armedAt))) ago); it fires when the row is idle\(then)\(tail)",
                                armedAt: stamp.string(from: pending.armedAt), last: last)
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
        // `armed: true` has to mean it can fire.
        guard serving() else { throw ClearError.nothingToFireIt(ControlSocket.defaultPath) }
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
