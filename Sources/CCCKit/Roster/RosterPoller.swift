import Foundation
import Observation

/// The roster across every host: one `HostPoller` per host, ticking
/// concurrently, merged when read. Nothing is shared between the pollers —
/// no row array written from N tasks — so a host that is asleep, wedged, or
/// misconfigured can only ever affect its own slot (docs/DESIGN.md §4b).
/// The GUI observes `state`; the CLI runs one `tick()`.
@MainActor
@Observable
public final class RosterPoller {
    /// The merged view. Built on read from the hosts' slots; nothing here
    /// is stored twice.
    public struct State: Sendable, Equatable {
        public var hosts: [HostPoll]

        public init(hosts: [HostPoll] = []) {
            self.hosts = hosts
        }

        /// Every host's rows, stale ones included (`HostPoll.isStale`).
        public var rows: [SessionRow] { hosts.flatMap(\.rows) }
        public var issues: [RosterShapeIssue] { hosts.flatMap(\.issues) }
        /// Things of ours to say (a broken overlay file), never an error.
        public var notes: [String] { hosts.flatMap(\.notes) }

        /// Hosts whose last poll failed. Per host by construction: the
        /// banner names the host, the others keep their rows.
        public var failures: [HostPoll] { hosts.filter { $0.error != nil } }
        /// Every host failed — the only case that is a roster-wide error.
        /// (One host, as in v1, is the same sentence it always was.)
        public var error: String? {
            guard !hosts.isEmpty, failures.count == hosts.count else { return nil }
            return failures.map { hosts.count == 1 ? $0.error! : "\($0.host): \($0.error!)" }.joined(separator: "; ")
        }
        public var anyHostAnswered: Bool { hosts.contains { $0.error == nil && $0.pollCount > 0 } }

        /// The slowest *answering* host's last poll: what the footer shows,
        /// since the rows are only as fresh as the slowest answer. A host
        /// that is failing contributes no fresh rows, so its 5 s timeout
        /// is its own line (`failures`, `ccc stats`), not the roster's
        /// number — unless nothing answered at all.
        public var lastPollMs: Double? { measured(\.lastPollMs) }
        public var meanPollMs: Double? { measured(\.meanPollMs) }
        private func measured(_ key: KeyPath<HostPoll, Double?>) -> Double? {
            let healthy = hosts.filter { $0.error == nil }.compactMap { $0[keyPath: key] }
            return healthy.max() ?? hosts.compactMap { $0[keyPath: key] }.max()
        }
        public var pollCount: Int { hosts.map(\.pollCount).max() ?? 0 }
        public var lastPolledAt: Date? { hosts.compactMap(\.lastPolledAt).max() }
        /// The local host's join; a remote host's join happened on the far
        /// side and is not ours to measure.
        public var modelJoin: ModelJoinStats? { hosts.first { $0.host == Host.localName }?.modelJoin }
        /// The job join runs on the local host only, like the model join.
        public var jobJoin: JobProbe.Counters? { hosts.first { $0.host == Host.localName }?.jobCounters }

        public func host(_ name: String) -> HostPoll? { hosts.first { $0.host == name } }

        /// The default order — `rows(sortedBy: .activity)`, every row,
        /// archived included. One comparator, not two: until 2026-09-04
        /// this had its own, which ranked a draft as `blocked` (a draft
        /// *is* a blocked row in the harness's eyes) while the sort the
        /// window and `--json` use ranks it below live work, so the
        /// legacy `.list` reply and the New Session folder list disagreed
        /// with the roster over the same rows.
        public var sorted: [SessionRow] { rows(sortedBy: .activity) }

        /// What the roster shows by default: `sorted` without the archived
        /// rows (`SessionRow.isHidden` — a blocked one is never hidden).
        public var visible: [SessionRow] { sorted.filter { !$0.isHidden } }
        /// How many `sorted` has that `visible` does not.
        public var hiddenCount: Int { rows.count { $0.isHidden } }
    }

    public private(set) var pollers: [HostPoller]
    public var attachedRef: SessionRef? {
        didSet { for poller in pollers { poller.attachedRef = attachedRef } }
    }

    /// The `Host` each poller was built from, so `sync` can tell a host that
    /// merely moved in the file from one whose ssh destination or claude
    /// path was edited — the second needs a new poller, the first does not.
    /// Empty for the pollers-only init, which makes the first `sync` rebuild
    /// everything: correct, and that init has no config to compare against.
    private var built: [String: Host] = [:]
    /// Whether `start` has been called, so a poller added later joins a
    /// running fleet and stays idle in a stopped one.
    private var running = false

    public var state: State { State(hosts: pollers.map(\.state)) }

    public init(pollers: [HostPoller], built: [String: Host] = [:]) {
        self.pollers = pollers
        self.built = built
    }

    /// One host — what v1 had, and what `ccc list --host` still wants.
    public convenience init(cli: ClaudeCLI? = ClaudeCLI.locate(), interval: Duration = .seconds(2)) {
        self.init(pollers: [HostPoller(cli: cli, interval: interval)])
    }

    /// Every usable host in a config. A host `ClaudeCLI.of` refuses still
    /// gets a slot, with the refusal as its error: the roster must say
    /// "studio: no claude path" rather than quietly listing one host fewer.
    public convenience init(hosts: HostConfig, interval: Duration = .seconds(2)) {
        self.init(pollers: hosts.hosts.map { host in
            HostPoller(cli: ClaudeCLI.of(host), hostName: host.name, interval: interval)
        }, built: Dictionary(uniqueKeysWithValues: hosts.hosts.map { ($0.name, $0) }))
    }

    /// What a `sync` did, as the sentence to show.
    public struct HostChanges: Sendable, Equatable {
        public var added: [String] = []
        public var removed: [String] = []
        public var replaced: [String] = []
        public var isEmpty: Bool { added.isEmpty && removed.isEmpty && replaced.isEmpty }

        public var said: String? {
            guard !isEmpty else { return nil }
            var parts: [String] = []
            if !added.isEmpty { parts.append("added \(added.joined(separator: ", "))") }
            if !replaced.isEmpty { parts.append("reloaded \(replaced.joined(separator: ", "))") }
            if !removed.isEmpty { parts.append("dropped \(removed.joined(separator: ", "))") }
            return "hosts: " + parts.joined(separator: "; ")
        }
    }

    /// Bring the poller set in line with a host list that changed on disk —
    /// the twin of what the overlay already does (`HostPoller.currentOverlay`),
    /// applied to hosts.json, so `ccc hosts add studio` shows up in a running
    /// app on the next tick instead of at the next launch. Measured
    /// 2026-09-03: without this, the first real remote host answered
    /// `ccc hosts check` and `ccc list` from the CLI while the app said
    /// "unknown host 'studio'", because the app had loaded the file once.
    ///
    /// **A live attach is never touched.** A pane holds its own
    /// `AttachSession` with an argv already built, so dropping a host stops
    /// polling it and nothing else; the pane keeps working until it exits.
    /// That is what makes reloading safe where the load-once comment feared
    /// it would not be.
    @discardableResult
    public func sync(to config: HostConfig, make: (Host) -> HostPoller) -> HostChanges {
        var changes = HostChanges()
        let wanted = config.hosts
        let wantedNames = Set(wanted.map(\.name))
        var kept: [String: HostPoller] = [:]
        for poller in pollers {
            guard wantedNames.contains(poller.hostName) else {
                poller.stop()
                changes.removed.append(poller.hostName)
                continue
            }
            kept[poller.hostName] = poller
        }
        for host in wanted {
            if let existing = kept[host.name] {
                guard built[host.name] != host else { continue }
                existing.stop()
                changes.replaced.append(host.name)
            } else {
                changes.added.append(host.name)
            }
            let fresh = make(host)
            fresh.interval = interval
            fresh.attachedRef = attachedRef
            if running { fresh.start() }
            kept[host.name] = fresh
        }
        // The file's order is the roster's order.
        pollers = wanted.compactMap { kept[$0.name] }
        built = Dictionary(uniqueKeysWithValues: wanted.map { ($0.name, $0) })
        return changes
    }

    public var interval: Duration {
        get { pollers.first?.interval ?? .seconds(2) }
        set { for poller in pollers { poller.interval = newValue } }
    }

    public func start() {
        running = true
        for poller in pollers { poller.start() }
    }

    public func stop() {
        running = false
        for poller in pollers { poller.stop() }
    }

    /// One poll of every host, concurrently; returns when the slowest has
    /// answered or timed out. Each host's own in-flight guard means this
    /// never doubles up on a poller that is already mid-tick.
    public func tick() async {
        await withTaskGroup(of: Void.self) { group in
            for poller in pollers {
                group.addTask { await poller.tick() }
            }
        }
    }

    /// The wake-up gesture (docs/DESIGN.md §4b): drop every remote host's
    /// ssh master and poll again at once, so a stale socket costs one fresh
    /// handshake instead of a 5 s discovery per tick. `host` narrows it.
    /// Returns what was evicted and what each host answered, for the
    /// command twin to print.
    @discardableResult
    public func reconnect(host name: String? = nil) async -> [HostPoll] {
        let targets = pollers.filter { name == nil || $0.hostName == name }
        for poller in targets { poller.evictControlMaster() }
        // `fresh`: a poll already in flight opened its ssh before the
        // eviction and rides the wedged master, so joining it would hand
        // the wake gesture the pre-eviction answer (found 2026-09-04).
        await withTaskGroup(of: Void.self) { group in
            for poller in targets {
                group.addTask { await poller.tick(fresh: true) }
            }
        }
        return targets.map(\.state)
    }

    public func poller(for host: String) -> HostPoller? {
        pollers.first { $0.hostName == host }
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
