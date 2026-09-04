import Foundation
import Observation

/// One host's slot in the roster: its rows, and everything that can go
/// wrong with *this* host and no other. The fleet (`RosterPoller`) merges
/// N of these at read time, which is what makes "one unreachable host must
/// never blank the roster" structural rather than a rule (docs/DESIGN.md
/// §4b).
public struct HostPoll: Sendable, Equatable {
    public var host: String
    /// The last rows this host answered with. **Kept across a failed
    /// poll**: a Mac that just went to sleep still has its sessions, and a
    /// row that is a minute old beats an empty list. `isStale` says so.
    public var rows: [SessionRow] = []
    /// Non-empty when the roster changed shape; shown as the banner.
    public var issues: [RosterShapeIssue] = []
    /// Something of ours to say that is not a roster failure — a broken
    /// overlay file, ignored. Shown on the banner, never an exit status.
    public var notes: [String] = []
    /// The reader could not be run at all (not on PATH, non-zero exit, ssh
    /// down). `nil` after a good poll.
    public var error: String?
    /// Consecutive failed polls, reset by a success.
    public var failures: Int = 0
    public var lastPolledAt: Date?
    public var lastSuccessAt: Date?
    public var lastPollMs: Double?
    public var meanPollMs: Double?
    public var pollCount: Int = 0
    /// Times the ssh master was unlinked after a degraded poll — the §4b
    /// fix, counted so `ccc stats` can say whether it ever fires in real
    /// life (open: the long-sleep measurement).
    public var evictions: Int = 0
    /// The model join, timed apart from the roster call it rides on. The
    /// two have different natures — `claude agents` is a process spawn we
    /// cannot make cheaper, the join is filesystem work we control — so one
    /// number covering both hides which is which. Local host only.
    public var lastModelJoinMs: Double?
    public var meanModelJoinMs: Double?
    public var modelCounters: ModelProbe.Counters?
    /// The job join's cache behaviour (v10), counted for the same reason
    /// the model join's is: this one runs for **every** local background
    /// row on **every** tick, so "what does the cadence cost" has to be a
    /// number and not an argument. A terminal session's job file never
    /// changes again, so the steady state should be overwhelmingly `hits`.
    public var jobCounters: JobProbe.Counters?
    /// Calls into `WellPath.locateTranscript` and how many came back
    /// empty. A miss is the expensive shape: the direct path fails and
    /// the fallback stats every well (~100 here), and for a session
    /// whose transcript never appears that repeats every single tick.
    public var transcriptLookups: Int = 0
    public var transcriptUnresolved: Int = 0

    public init(host: String) {
        self.host = host
    }

    /// Rows are being shown from before the host stopped answering.
    public var isStale: Bool { error != nil && !rows.isEmpty }

    /// The join's cost as `ccc stats` reports it. `nil` before the first
    /// tick, so an idle process does not claim a measurement it never took.
    public var modelJoin: ModelJoinStats? {
        guard let counters = modelCounters else { return nil }
        return ModelJoinStats(lastMs: lastModelJoinMs, meanMs: meanModelJoinMs,
                              reads: counters.reads, hits: counters.hits, misses: counters.misses,
                              lookups: transcriptLookups, unresolved: transcriptUnresolved)
    }
}

/// The 2 s poll of one host (CLAUDE.md "The poll is the first notifier").
/// Runs this host's roster reader — `claude agents --json --all` decoded
/// here, or the far side's `ccc list --json` — joins the model column where
/// the filesystem is local, and publishes one `HostPoll`. One in-flight
/// tick per host, ever: a 5 s timeout on a sleeping Mac must not stack ssh
/// processes behind a 2 s interval.
@MainActor
@Observable
public final class HostPoller {
    public private(set) var state: HostPoll
    public var interval: Duration
    public var attachedRef: SessionRef?
    /// A successful poll slower than this on a remote host means the ssh
    /// master is wedged (measured: healthy 215–364 ms, wedged 5.3 s, and
    /// ssh retries the wedged master forever — docs/DESIGN.md §4b). A false
    /// positive costs one handshake, so the bar is low.
    public var degradedThreshold: Duration = .seconds(3)

    public let cli: ClaudeCLI?
    private let probe = ModelProbe()
    /// The worktree column (v6), local rows only — same rule as the model.
    private let worktrees = WorktreeProbe()
    /// What the daemon's job file says (v10), local rows only — same rule
    /// again, and the read the draft column used to make for itself.
    private let jobs = JobProbe()
    private var loop: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?
    private var totalPollMs: Double = 0
    private var totalJoinMs: Double = 0
    private var joinCount: Int = 0
    /// sessionId → transcript path, once found; saves the well scan.
    private var transcriptPaths: [String: URL] = [:]
    /// Our marks (v4), joined on the local host only — a remote host's rows
    /// arrive with theirs already set by the far side's ccc. Re-read when
    /// the file's mtime moves, so `ccc archive` from a shell shows in the
    /// window on the next tick; one `stat` per tick otherwise.
    public let overlayPath: String
    private var overlay = RosterOverlay()
    private var overlayModifiedAt: Date?
    private var overlayLoaded = false

    public init(cli: ClaudeCLI?, hostName: String? = nil, interval: Duration = .seconds(2),
                overlayPath: String = RosterOverlay.defaultPath) {
        self.cli = cli
        self.interval = interval
        self.overlayPath = overlayPath
        self.state = HostPoll(host: hostName ?? cli?.host.name ?? Host.localName)
    }

    /// The overlay as of now: the file when it changed, memory otherwise.
    /// A broken file is one issue on the banner and no marks, never no rows.
    private func currentOverlay() -> (RosterOverlay, issue: String?) {
        let modified = RosterOverlay.modificationDate(path: overlayPath)
        if overlayLoaded, modified == overlayModifiedAt { return (overlay, nil) }
        let loaded = RosterOverlay.load(path: overlayPath)
        overlay = loaded.overlay
        overlayModifiedAt = modified
        overlayLoaded = true
        return (overlay, loaded.issue)
    }

    public var hostName: String { state.host }
    public var isLocal: Bool { cli?.host.isLocal ?? true }

    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: self.interval)
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    /// One poll. If one is already running, waits for *that* one instead
    /// of starting another — so `ccc list` and the wake re-poll get a fresh
    /// answer without ever doubling up on a slow host.
    public func tick() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await self.poll() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// Unlink this host's ssh master socket. The next invocation makes a
    /// fresh master (316 ms, measured) instead of retrying the wedged one
    /// (5.3 s, forever). Never `ssh -O exit`: that talks to the wedged
    /// master and pays the same wait. Nothing to do for `local`.
    @discardableResult
    public func evictControlMaster() -> Bool {
        guard let cli, !cli.host.isLocal, cli.evictControlMaster() else { return false }
        state.evictions += 1
        return true
    }

    private func poll() async {
        guard let cli else {
            fail("claude not found on PATH (set CCC_CLAUDE to its path)", started: nil)
            return
        }
        let started = ContinuousClock.now
        let reading: ClaudeCLI.RosterReading
        do {
            reading = try await cli.rosterJSON()
        } catch {
            // A failed hop leaves nothing worth keeping on the socket: if
            // the master is dead, ssh already ignored it; if it is wedged,
            // this is the eviction. Either way the next tick starts clean.
            if !cli.host.isLocal { evictControlMaster() }
            fail("\(error)", started: started)
            return
        }
        let data = reading.data
        // A warning crossed the hop: the far side's banner becomes ours, so
        // "roster shape changed" on studio is visible from air.
        let remoteIssues = reading.warning.map { [RosterShapeIssue(message: $0)] } ?? []
        // The far side's own ccc already did the transcript join, so its
        // rows arrive finished: take them, and only re-stamp what is ours to
        // know (which host answered, and what this process is attached to).
        if cli.rosterSource == .ccc {
            let hostName = state.host
            let attached = attachedRef
            do {
                let remote = try JSONDecoder.roster.decode([SessionRow].self, from: data)
                state.rows = remote.map { row in
                    var row = row
                    row.host = hostName
                    row.attached = SessionRef(host: hostName, id: row.session.id) == attached
                    return row
                }
                state.issues = remoteIssues
                succeed(started)
            } catch {
                // Do not silently fall back to the harness reader: that would
                // trade the model column for a slower tick without saying so.
                fail("\(hostName): could not read `ccc list --json` (\(error.localizedDescription)); "
                     + "is the remote ccc older than this one? `ccc hosts add \(hostName) --no-ccc` falls back to the harness",
                     started: started)
            }
            return
        }
        let decoded = RosterDecoder.decode(data)
        let probe = self.probe
        let worktrees = self.worktrees
        let jobs = self.jobs
        let attached = attachedRef
        let known = transcriptPaths
        let hostName = state.host
        // Model lookups touch the filesystem; keep them off the main actor.
        let isLocal = cli.host.isLocal
        let joinStarted = ContinuousClock.now
        let (joined, found, lookups, unresolved) = await Task.detached(priority: .utility) {
            var found: [String: URL] = [:]
            var lookups = 0, unresolved = 0
            let rows = decoded.sessions.map { session -> SessionRow in
                var model: String?
                // The transcript is a file under the *session's* `~/.claude`,
                // so this join only works where the daemon and the filesystem
                // are the same machine. A remote row shows no model rather
                // than this Mac's answer to a question about another one;
                // the far side's own ccc answers that (docs/DESIGN.md §4a).
                if isLocal, let id = session.sessionId {
                    // A cached path can go stale: the transcript follows the
                    // session's CURRENT worktree well on every entry (lore
                    // canon e085cbb), so a populated well empties under us.
                    let cached = known[id].flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                    var url = cached
                    if url == nil {
                        lookups += 1
                        url = WellPath.locateTranscript(sessionId: id, cwd: session.cwd)
                        if url == nil { unresolved += 1 }
                    }
                    if let url {
                        found[id] = url
                        model = probe.model(forTranscriptAt: url)?.model
                    }
                }
                let ref = SessionRef(host: hostName, id: session.id)
                // The job reading (v10): what the daemon's own file says
                // this session is doing or asking. Same shape as the model
                // join — local only, carried across the hop on the row —
                // and it subsumes the read the draft reading used to do
                // for itself, so `state.json` is opened once per row.
                let job = isLocal && session.kind == .background ? jobs.info(forJob: session.id) : nil
                // The draft reading (v5) is the same kind of join: the
                // daemon's job file, which only this Mac can open for its
                // own sessions; the far side's ccc answers for its rows.
                let draft = isLocal && DraftProbe.isDraft(session, job: job,
                                                          transcriptFound: found[session.sessionId ?? ""] != nil)
                // The worktree reading (v6): files, and one `git rev-list`
                // per moved sha — steady state costs no process at all.
                let worktree = isLocal ? worktrees.info(forCwd: session.cwd) : nil
                return SessionRow(session: session, host: hostName, model: model, attached: ref == attached, draft: draft,
                                  worktree: worktree, job: job)
            }
            return (rows, found, lookups, unresolved)
        }.value
        transcriptPaths.merge(found) { _, new in new }
        var rows = joined
        if isLocal {
            let (marks, issue) = currentOverlay()
            state.notes = issue.map { [$0] } ?? []
            for i in rows.indices {
                let mark = marks.mark(for: rows[i].session.id, sessionId: rows[i].session.sessionId)
                rows[i].archived = mark?.archived != nil
                rows[i].pinned = mark?.pinned != nil
            }
            // A good roster is the moment to forget marks on sessions that
            // left it long ago. Written only when something was dropped.
            var pruned = marks
            if pruned.prune(keeping: Set(rows.map(\.session.id))), (try? pruned.save(path: overlayPath)) != nil {
                overlay = pruned
                overlayModifiedAt = RosterOverlay.modificationDate(path: overlayPath)
            }
        }
        state.rows = rows
        state.issues = decoded.issues + remoteIssues
        state.transcriptLookups += lookups
        state.transcriptUnresolved += unresolved
        state.modelCounters = probe.stats
        state.jobCounters = isLocal ? jobs.stats : nil
        recordJoin(joinStarted)
        succeed(started)
    }

    private func succeed(_ started: ContinuousClock.Instant) {
        state.error = nil
        state.failures = 0
        state.lastSuccessAt = Date()
        let ms = record(started)
        // Succeeded, but slowly: the wedged-master shape (§4b). Evict now so
        // the next tick is 300 ms again instead of 5 s forever.
        if !isLocal, ms > Self.milliseconds(of: degradedThreshold) {
            evictControlMaster()
        }
    }

    private func fail(_ message: String, started: ContinuousClock.Instant?) {
        state.error = message
        state.failures += 1
        if let started { record(started) } else { state.lastPolledAt = Date() }
    }

    private func recordJoin(_ started: ContinuousClock.Instant) {
        let ms = Self.milliseconds(since: started)
        state.lastModelJoinMs = ms
        totalJoinMs += ms
        joinCount += 1
        state.meanModelJoinMs = totalJoinMs / Double(joinCount)
    }

    static func milliseconds(since started: ContinuousClock.Instant) -> Double {
        milliseconds(of: started.duration(to: .now))
    }

    static func milliseconds(of elapsed: Duration) -> Double {
        Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }

    @discardableResult
    private func record(_ started: ContinuousClock.Instant) -> Double {
        let ms = Self.milliseconds(since: started)
        state.lastPolledAt = Date()
        state.lastPollMs = ms
        state.pollCount += 1
        totalPollMs += ms
        state.meanPollMs = totalPollMs / Double(state.pollCount)
        return ms
    }
}
