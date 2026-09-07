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

/// When an armed clear may fire, read off the roster row. The gate is not
/// politeness: measured 2026-09-06, a `/clear` typed while the session was
/// generating took effect immediately and the running turn's output was
/// gone — no error, no trace, the transcript simply empty.
public enum ClearWindow: String, Sendable {
    /// Idle, and ours to type into.
    case now
    /// Working, blocked on a question, or between polls: wait.
    case wait
    /// Failed, stopped, or off the roster: the clear will never fire and
    /// the mark should go.
    case gone

    public static func of(_ session: Session) -> ClearWindow {
        guard session.kind == .background else { return .gone }
        switch session.state {
        case .failed, .stopped: return .gone
        // `blocked` is a session waiting on a question, and the box under
        // that question is a dialog, not a prompt: typing there answers
        // it. Never our seat.
        case .blocked: return .wait
        case .working, .done, .none: break
        }
        // No `status` at all is a row with no live process behind it.
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

        public init(ref: String, armed: Bool, then: String? = nil, cancelled: Bool = false, said: String) {
            self.ref = ref
            self.armed = armed
            self.then = then
            self.cancelled = cancelled
            self.said = said
        }
    }

    public enum ClearError: Error, CustomStringConvertible {
        case noSuchSession(String)
        case notBackground(String)
        case dirty(String)
        case noRemoteCCC(String)
        public var description: String {
            switch self {
            case .noSuchSession(let id): return "no session '\(id)' in the roster"
            case .notBackground(let id): return "\(id) is an interactive session; ccc has no pane on it to type into"
            case .dirty(let reason): return reason
            case .noRemoteCCC(let host): return "a clear is armed where the session lives, and \(host) has no ccc for it (`ccc hosts add \(host)` finds one)"
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
                      overlayPath: String = RosterOverlay.defaultPath) async throws -> ClearOutcome {
        guard host.isLocal else {
            guard let ccc = host.ccc, let destination = host.ssh else { throw ClearError.noRemoteCCC(host.name) }
            var words = [ccc, "clear", id]
            if cancel { words.append("--cancel") }
            if let then { words += ["--then", Self.remoteWord(then)] }
            try prepareControlDirectory()
            let out = try await run(sshPrefix(tty: false, destination: destination) + words, program: "ccc")
            let said = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return ClearOutcome(ref: id, armed: !cancel, then: then, cancelled: cancel, said: said)
        }

        if cancel {
            return try RosterOverlay.locked(path: overlayPath) {
                var overlay = RosterOverlay.load(path: overlayPath).overlay
                let previous = overlay.arm(nil, id: id, sessionId: overlay.marks[id]?.sessionId)
                guard previous != nil else {
                    return ClearOutcome(ref: id, armed: false, said: "no clear was armed on \(id)")
                }
                try overlay.save(path: overlayPath)
                return ClearOutcome(ref: id, armed: false, cancelled: true, said: "cancelled the clear armed on \(id)")
            }
        }

        let roster = RosterDecoder.decode(try await agentsJSON())
        guard let row = roster.sessions.first(where: { $0.id == id }) else { throw ClearError.noSuchSession(id) }
        guard row.kind == .background else { throw ClearError.notBackground(id) }
        if let reason = ClearGuard.refusal(cwd: row.cwd) { throw ClearError.dirty(reason) }

        let pending = PendingClear(then: then)
        return try RosterOverlay.locked(path: overlayPath) {
            var overlay = RosterOverlay.load(path: overlayPath).overlay
            overlay.arm(pending, id: id, sessionId: row.sessionId)
            try overlay.save(path: overlayPath)
            return ClearOutcome(ref: id, armed: true, then: then, said: pending.said(id))
        }
    }
}
