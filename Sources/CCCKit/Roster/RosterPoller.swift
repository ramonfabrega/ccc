import Foundation
import Observation

/// The 2 s poll (CLAUDE.md "The poll is the first notifier"). Runs
/// `claude agents --json --all`, decodes leniently, joins the model column
/// from each session's transcript tail, and publishes one `RosterState`.
/// The GUI observes it; the CLI runs one tick.
@MainActor
@Observable
public final class RosterPoller {
    public struct State: Sendable, Equatable {
        public var rows: [SessionRow] = []
        /// Non-empty when the roster changed shape; shown as the banner.
        public var issues: [RosterShapeIssue] = []
        /// The harness could not be run at all (not on PATH, non-zero exit).
        public var error: String?
        public var lastPolledAt: Date?
        public var lastPollMs: Double?
        public var meanPollMs: Double?
        public var pollCount: Int = 0
        public init() {}
    }

    public private(set) var state = State()
    public var interval: Duration
    public var attachedRef: SessionRef?

    private let cli: ClaudeCLI?
    private let probe = ModelProbe()
    private var task: Task<Void, Never>?
    private var totalPollMs: Double = 0
    /// sessionId → transcript path, once found; saves the well scan.
    private var transcriptPaths: [String: URL] = [:]

    public init(cli: ClaudeCLI? = ClaudeCLI.locate(), interval: Duration = .seconds(2)) {
        self.cli = cli
        self.interval = interval
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: self.interval)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// One poll. Public so the CLI and tests can drive it without a loop.
    public func tick() async {
        guard let cli else {
            state.error = "claude not found on PATH (set CCC_CLAUDE to its path)"
            return
        }
        let started = ContinuousClock.now
        let data: Data
        do {
            data = try await cli.agentsJSON(all: true)
        } catch {
            state.error = "\(error)"
            record(started)
            return
        }
        let decoded = RosterDecoder.decode(data)
        let probe = self.probe
        let attached = attachedRef
        let known = transcriptPaths
        let hostName = cli.host.name
        // Model lookups touch the filesystem; keep them off the main actor.
        let isLocal = cli.host.isLocal
        let (rows, found) = await Task.detached(priority: .utility) {
            var found: [String: URL] = [:]
            let rows = decoded.sessions.map { session -> SessionRow in
                var model: String?
                // The transcript is a file under the *session's* `~/.claude`,
                // so this join only works where the daemon and the filesystem
                // are the same machine. A remote row shows no model rather
                // than this Mac's answer to a question about another one;
                // reading it over the hop is its own decision (docs/DESIGN.md
                // "The model column over ssh").
                if isLocal, let id = session.sessionId {
                    // A cached path can go stale: the transcript follows the
                    // session's CURRENT worktree well on every entry (lore
                    // canon e085cbb), so a populated well empties under us.
                    let cached = known[id].flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                    let url = cached ?? WellPath.locateTranscript(sessionId: id, cwd: session.cwd)
                    if let url {
                        found[id] = url
                        model = probe.model(forTranscriptAt: url)?.model
                    }
                }
                let ref = SessionRef(host: hostName, id: session.id)
                return SessionRow(session: session, host: hostName, model: model, attached: ref == attached)
            }
            return (rows, found)
        }.value
        transcriptPaths.merge(found) { _, new in new }
        state.rows = rows
        state.issues = decoded.issues
        state.error = nil
        record(started)
    }

    private func record(_ started: ContinuousClock.Instant) {
        let elapsed = started.duration(to: .now)
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        state.lastPolledAt = Date()
        state.lastPollMs = ms
        state.pollCount += 1
        totalPollMs += ms
        state.meanPollMs = totalPollMs / Double(state.pollCount)
    }
}

extension RosterPoller.State {
    /// Presentation order: live and blocked first, then by most recent start.
    public var sorted: [SessionRow] {
        rows.sorted { a, b in
            let ra = a.session.rank, rb = b.session.rank
            if ra != rb { return ra < rb }
            return a.session.startedAt > b.session.startedAt
        }
    }
}

extension Session {
    /// Lower sorts first. Blocked outranks working: it is "your turn".
    var rank: Int {
        switch state {
        case .blocked: return 0
        case .working: return 1
        case nil: return pid != nil ? 1 : 3     // interactive rows: live or not
        case .failed: return 2
        case .done, .stopped: return 3
        }
    }
}
