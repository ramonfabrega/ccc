import Foundation

/// The spawner's refusals: what `ccc spawn` checks about the *fleet* before
/// it asks the harness for a session (queue item 19).
///
/// Both checks here exist because the harness cannot make them. The daemon
/// dispatches what it is told: it will hand a second live job the same
/// `--name` in the same folder, and it will start a session on a disk with
/// nothing left. ccc is the only thing standing between a commander's loop
/// and either outcome, so the guard belongs on this side of the seam and
/// nowhere else.
///
/// Everything here is **pure over rows and a free-space number**, so the
/// CLI (which polls once for them) and the New Session sheet (which already
/// holds a live roster) reach the same verdict from the same function —
/// CLAUDE.md's parity rule, applied to a refusal rather than to a gesture.
public enum SpawnGuard {

    // MARK: the name a live job already answers to

    /// A live job that already holds the name a spawn is asking for.
    ///
    /// Measured 2026-09-06: two jobs named `att-capture` existed for twenty
    /// minutes in one `lane-capture` worktree — the daemon still held
    /// Friday's, and the attrition commander, respawning its lane, asked
    /// for the same name and the same cwd. **By-name routing goes to the
    /// newest**: `SendMessage`, the lore thread and the roster all resolved
    /// to the new job while the old one kept working, so both halves
    /// mis-attributed and neither was addressable. Credit: the attrition
    /// commander, which reported it against itself.
    public struct NameHolder: Sendable, Equatable {
        public var ref: SessionRef
        public var name: String
        public var cwd: String
        public var state: Session.State?
        public var startedAt: Date
        /// The holder is in the very folder the new session would run in —
        /// the aggravating half of 09-06: not only is the name ambiguous,
        /// two live sessions share one working tree.
        public var sameFolder: Bool

        public init(ref: SessionRef, name: String, cwd: String, state: Session.State?,
                    startedAt: Date, sameFolder: Bool) {
            self.ref = ref
            self.name = name
            self.cwd = cwd
            self.state = state
            self.startedAt = startedAt
            self.sameFolder = sameFolder
        }

        /// The refusal, as the CLI prints it and the sheet shows it. It
        /// names the way out because a refusal an agent cannot act on is a
        /// wall: **`--replace` stops the holder and spawns**, and
        /// `--allow-duplicate` is the escape hatch — ccc refuses, it never
        /// forbids.
        public var said: String {
            let where_ = sameFolder ? "in that same folder" : "in \(cwd)"
            let doing = state.map { "\($0.rawValue)" } ?? "live"
            return "'\(name)' is already \(doing) as \(ref) \(where_) — messages, the roster and lore would all resolve to whichever started last. "
                + "Stop it first (`ccc stop \(ref)`), spawn with --replace to do that here, or --allow-duplicate to mean it."
        }
    }

    /// **Live** is every state that is not an ending. A `done`, `failed` or
    /// `stopped` job keeps its name in `--all` listings forever — the
    /// roster on 09-06 carried two `beta-fb-polish` and two
    /// `beta-fb-metadata` that way — and re-using a finished lane's name is
    /// the normal thing a commander does. Only a job that can still receive
    /// a message can be ambiguous. A `nil` state is live: the row is a
    /// shape ccc does not know, and the lenient rule is to assume it is
    /// running rather than to wave the spawn through.
    static func isLive(_ state: Session.State?) -> Bool {
        switch state {
        case .done, .failed, .stopped: return false
        case .working, .blocked, nil: return true
        }
    }

    /// The live job holding this request's name on this host, if any.
    ///
    /// **The name alone is the predicate, not name+cwd.** The 09-06 report
    /// named the conjunction, but the harm it describes — "by-name routing
    /// goes to the newest" — needs only the name; a duplicate name in a
    /// second folder mis-routes exactly as badly. The converse does *not*
    /// hold, and cwd alone is deliberately not a refusal: a second session
    /// in a repository root beside a long-running one is ordinary and
    /// wanted (the 09-06 roster had six such rows under
    /// `~/code/work/cuanto`). So the folder is reported, never decisive.
    ///
    /// **A spawn that will get a fresh worktree cannot collide on the
    /// folder** and is still checked on the name: `--worktree`/`--base`
    /// means ccc or the harness cuts a new tree, which is why workers never
    /// hit this and lanes do — but a worker with a stale name is still
    /// unaddressable.
    ///
    /// `cwd` is the folder the session will actually run in — after
    /// `prepareWorktree`, so it is the tree that would be shared — or `nil`
    /// when the caller does not know it yet (a remote spawn with no `--cwd`
    /// lands in the far side's home).
    public static func nameHolder(for request: SpawnRequest, on host: String, cwd: String?,
                                  rows: [SessionRow]) -> NameHolder? {
        guard let wanted = request.name?.trimmingCharacters(in: .whitespacesAndNewlines), !wanted.isEmpty else {
            return nil
        }
        let candidates = rows.filter { row in
            row.host == host
                && row.session.name == wanted
                && isLive(row.session.state)
        }
        // The newest, because that is the one by-name routing already
        // resolves to — the refusal should name the job a message would
        // reach today, not the oldest namesake.
        guard let held = candidates.max(by: { $0.session.startedAt < $1.session.startedAt }) else { return nil }
        return NameHolder(ref: held.ref, name: wanted, cwd: held.session.cwd,
                          state: held.session.state, startedAt: held.session.startedAt,
                          sameFolder: cwd.map { Self.sameFolder($0, held.session.cwd) } ?? false)
    }

    /// Two paths that are the same folder. Trailing slashes only; no
    /// symlink resolution, because the roster's cwd and a `--cwd` are both
    /// already what the shell handed over, and resolving would need the
    /// far side's filesystem for a remote row.
    static func sameFolder(_ a: String, _ b: String) -> Bool {
        func trim(_ p: String) -> String {
            var s = p
            while s.count > 1, s.hasSuffix("/") { s.removeLast() }
            return s
        }
        return trim(a) == trim(b)
    }

    // MARK: the disk a spawn is about to land on

    /// What a spawn found on the volume it would run in.
    ///
    /// Measured 2026-09-04, 23:13Z: the machine locked when an attrition
    /// worker's release test suite reached 27.6 GB with 53 GB of swap
    /// already full, on a disk crowded by six Rust `target/` trees (1–18 GB
    /// each) and 25 Next `.next/` trees. Nothing in ccc noticed, because
    /// nothing in ccc looked. The spawner is where a floor belongs: it is
    /// the one moment ccc knows a new consumer is about to start, and the
    /// only moment refusing is cheap.
    public struct Space: Sendable, Equatable {
        /// Free bytes on the volume the session's cwd lives on.
        public var freeBytes: Int64
        /// The volume's mount path, so the refusal names what to clear.
        public var path: String

        public init(freeBytes: Int64, path: String) {
            self.freeBytes = freeBytes
            self.path = path
        }

        public var freeGB: Double { Double(freeBytes) / 1_073_741_824 }
    }

    /// **The floor, in GB.** 10 is not a measurement of what a session
    /// needs — no such number exists, and Friday's worker would have
    /// cleared any floor at spawn time and eaten the disk an hour later.
    /// It is the point below which *the Mac* stops working: under ~10 GB,
    /// macOS has no room to grow swap, which is the failure that actually
    /// happened. So this refuses the spawn that starts on an already-doomed
    /// disk and says nothing about the one that dooms it — a smaller claim
    /// than the crash invites, and the only one the spawner can honestly
    /// make. `CCC_SPAWN_FLOOR_GB` moves it; `0` turns it off.
    public static let defaultFloorGB = 10.0

    /// The floor this process runs with.
    public static func floorGB(environment: [String: String] = ProcessInfo.processInfo.environment) -> Double {
        guard let raw = environment["CCC_SPAWN_FLOOR_GB"], let value = Double(raw), value >= 0 else {
            return defaultFloorGB
        }
        return value
    }

    /// Free space on the volume holding `path`, or `nil` when it cannot be
    /// read — an unreadable volume is never a refusal. Local only: the far
    /// side's disk is the far side's ccc to judge, and a `df` over ssh
    /// would put a second round trip in front of every remote spawn.
    public static func space(at path: String) -> Space? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                             .volumeURLKey]),
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        let volume = values.volume?.path ?? "/"
        return Space(freeBytes: free, path: volume)
    }

    /// The refusal for a disk under the floor, or `nil` to proceed.
    public static func spaceRefusal(_ space: Space?, floorGB: Double) -> String? {
        guard floorGB > 0, let space, space.freeGB < floorGB else { return nil }
        return String(format: "%.1f GB free on %@, under the %.0f GB floor — a session that starts here can lock the Mac before it finishes (2026-09-04, 23:13Z). "
                      + "Clear space, or pass --no-space-check to mean it (CCC_SPAWN_FLOOR_GB moves the floor; 0 turns it off).",
                      space.freeGB, space.path, floorGB)
    }
}
