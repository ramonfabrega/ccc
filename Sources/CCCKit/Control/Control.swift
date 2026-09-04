import Foundation

/// The agent-legible surface: newline-delimited JSON over a unix socket, one
/// request per connection, the server replies and closes (scry's pattern).
/// Whoever holds a PTY serves it — the GUI app or a headless `ccc attach`.
/// Attach is exclusive at the daemon, so this is the only way a second
/// process (an agent, a test, the CLI) can see what the pane shows.
public enum ControlRequest: Codable, Sendable {
    /// The roster as the server last polled it, with model column.
    case list
    /// Attach the pane to a session (the click's twin). The payload is a
    /// `SessionRef`, so an agent on this Mac can drive a session on another.
    ///
    /// The label stays `id` because a case label *is* the wire key: a v1
    /// `ccc` on PATH sends `{"attach":{"id":"a1b2"}}`, and a `SessionRef`
    /// decodes from that bare string as the local ref it always meant. The
    /// suite's rule (an older side must keep working) costs one comment here
    /// instead of a hand-written decoder for eleven cases.
    case attach(id: SessionRef)
    /// Detach the pane from its session by ending the child process the way
    /// the harness documents (Ctrl+Z is the default; see `DetachGesture`).
    case detach
    /// The pane's grid. `nil` session when nothing is attached. `colors`
    /// asks for resolved RGB alongside the text (item 12a) — off by default
    /// so the common snapshot stays the cheap text one.
    case snapshot(colors: Bool = false)
    /// Bytes to the child: `text` is UTF-8 as typed; `keys` are named keys
    /// (`enter`, `escape`, `ctrl-c`, `ctrl-z`, `up`, `shift-enter`, …) that
    /// the terminal host encodes — never hand-rolled escape sequences.
    /// `wheel`: scroll lines (positive = up) through the host's mouse path.
    /// `paste`: text handed to the host's paste path, which frames it the
    /// way the child negotiated (bracketed under mode 2004) — the twin of
    /// Command-V on the pane, and the only way to prove check 2 live.
    case send(text: String?, keys: [String]?, wheel: Int? = nil, paste: String? = nil)
    /// Resize the pane's grid (headless only; the window resizes itself).
    case resize(cols: Int, rows: Int)
    /// Memory, poll latency, PTY throughput — how we're doing.
    case stats
    /// A PNG of the app window drawn from our own view hierarchy (no
    /// screen-recording permission, works while another app has focus).
    /// Headless servers have no window and answer with an error.
    case peek
    /// `show` brings the window forward, `hide` orders it out, `close` is
    /// exactly ⌘W (so the reopen path can be exercised without a hand).
    case window(action: String)
    /// The wake-up gesture's twin (docs/DESIGN.md §4b): drop the ssh
    /// master of every remote host — or of `host` — and poll again now.
    /// The app does this itself on `NSWorkspace.didWakeNotification`; this
    /// is how a hand or a script does the same.
    case reconnect(host: String?)
    /// The harness's `Notification` hook, relayed by `ccc hook` (v3, slice
    /// 2): the app looks the session up in its roster and posts what the
    /// roster could not show. Headless servers have no notifier and say so.
    case hook(event: HookEvent)
    /// A shell pane under the session pane (v6 slice 4), in the folder of
    /// the session `id` names — the user's login shell, over `ssh -t` when
    /// the session is remote. One at a time; asking again focuses it.
    /// Headless servers have no second pane and say so.
    /// `repo` asks for the repository's main checkout instead of the
    /// worktree — where `git merge --ff-only` and `scripts/install` run.
    case shell(id: SessionRef, repo: Bool? = nil)
    /// Close the shell pane (SIGHUP to its shell), if one is open.
    case shellClose
    /// A prompt to a session through the pane (v6 slice 6): attach to
    /// `id` (switching if another is on screen), wait for its TUI to
    /// draw, type `prompt`, press Enter. What "Ask the session to merge
    /// master" does when an update backs out of a conflict; `ccc update
    /// --ask` is its twin. `ccc send`'s road, with the attach in front.
    case ask(id: SessionRef, prompt: String)
    /// The ⌘-click gesture's twin (v7 slice 2): the URLs on the pane's
    /// grid, in reading order. `open` is a 1-based index into that same
    /// list and opens it the way the click does — so what the hand can
    /// click, a script can name.
    case links(open: Int? = nil)
    /// Select a region of the pane, or clear it with a nil `region` (item
    /// 12b). Viewport coordinates, both ends inclusive — the same grid
    /// `snapshot` prints and `pixel --cell` aims at, so `select` then
    /// `snapshot --color` (headless) and `select` then `capture` + `pixel`
    /// (on screen) are two readings of one thing.
    ///
    /// Since item 13 this is the **drag's twin** rather than the only
    /// producer: shift-drag on the pane installs a selection the same way,
    /// and `region.grain` is the twin of the click count — `word` is a
    /// double-click, `line` a triple.
    case select(region: SelectionRegion?)
    /// The ⌘C gesture's twin (item 13): the selected text, plain, with soft
    /// wraps undone — and onto the system pasteboard, exactly as the key
    /// does it, because a copy that did not reach the pasteboard would be a
    /// different verb wearing this one's name. An error when nothing is
    /// selected; `select` first.
    case copy
    /// Where the window is and how big a cell is (v8 slice 3), so a real
    /// `screencapture` can be aimed at this one window and a cell can be
    /// turned into a pixel. Headless servers have no window and say so.
    case geometry
}

public enum ControlResponse: Codable, Sendable {
    case list([SessionRow])
    case snapshot(SnapshotInfo)
    case links([LinkInfo])
    case stats(StatsInfo)
    case peek(png: Data)
    case geometry(WindowGeometry)
    case ok(String)
    case error(String)
}

/// Where the window and its pane are on screen, in points, with the scale
/// that turns points into the pixels of a captured image.
///
/// This exists because of one missing number. CLAUDE.md makes a real
/// `screencapture` the oracle for presentation — `ccc peek` composites the
/// pane from an offscreen render, so it can show a perfect TUI over a pane
/// that is black on screen, and it did for a day (docs/DESIGN.md §7) — but
/// `screencapture -l` wants a `CGWindowID` that nothing in the repo
/// produced. `NSWindow.windowNumber` *is* that id; it just never left the
/// app. Queue item 10.
public struct WindowGeometry: Codable, Sendable, Equatable {
    /// The id `screencapture -l` takes.
    public var windowID: Int
    /// Backing scale of the screen the window is on: 2.0 on Retina. A
    /// captured image is this many pixels per point, and every rect here
    /// is in points, so nothing in this struct changes when the window
    /// moves between displays — only this number does.
    public var scale: Double
    /// The window's frame size, which is what a window capture covers —
    /// title bar included. Pane coordinates are relative to *this*, not to
    /// the content view, because that is what indexes the image.
    public var width: Double
    public var height: Double
    /// Where the window sits on the desktop, **top-left down** in the global
    /// screen space CoreGraphics uses — the same space `screencapture -R`
    /// takes — rather than AppKit's bottom-left up, so it reads the way the
    /// pane rect above already does. This is the answer to "did it come back
    /// where I left it": quit, relaunch, compare.
    public var x: Double
    public var y: Double
    /// The attached pane, when one is mounted.
    public var pane: Pane?

    /// The pane's rect inside the window, origin **top-left** so it
    /// indexes a captured image directly rather than AppKit's bottom-left.
    public struct Pane: Codable, Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public var cols: Int
        public var rows: Int
        /// One cell, in points. Taken from the renderer's own `CellMetrics`
        /// rather than divided out of the pane's size: the grid is laid
        /// from the top-left with exact metrics and any remainder is slack
        /// at the right and bottom, so dividing would drift a little
        /// further from the truth with every column.
        public var cellWidth: Double
        public var cellHeight: Double

        public init(x: Double, y: Double, width: Double, height: Double,
                    cols: Int, rows: Int, cellWidth: Double, cellHeight: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
            self.cols = cols; self.rows = rows
            self.cellWidth = cellWidth; self.cellHeight = cellHeight
        }

        /// The centre of a cell, in **pixels** of an image captured at
        /// `scale`, measured from the image's top-left. The centre and not
        /// a corner on purpose: a corner sits on the boundary between two
        /// cells and on the edge of a glyph's antialiasing, where the
        /// answer to "what colour is this" is legitimately ambiguous.
        public func pixel(col: Int, row: Int, scale: Double) -> (x: Int, y: Int) {
            let px = x + (Double(col) + 0.5) * cellWidth
            let py = y + (Double(row) + 0.5) * cellHeight
            return (Int((px * scale).rounded(.down)), Int((py * scale).rounded(.down)))
        }
    }

    public init(windowID: Int, scale: Double, x: Double, y: Double,
                width: Double, height: Double, pane: Pane? = nil) {
        self.windowID = windowID
        self.scale = scale
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.pane = pane
    }
}

/// One roster row as ccc shows it: the harness's session plus what ccc adds
/// — the host it was polled from, and the model that is actually serving it.
///
/// `host` lives here and not on `Session` on purpose: `Session` is the
/// harness's shape, decoded leniently at the boundary, and the daemon has no
/// idea other Macs exist. Which daemon answered is ccc's knowledge.
public struct SessionRow: Codable, Sendable, Equatable, Identifiable {
    public var session: Session
    public var host: String
    public var model: String?
    public var attached: Bool
    /// Our marks (v4, `RosterOverlay`), joined where the session lives and
    /// carried across the hop like the model. Off the wire they default to
    /// false: an older ccc on the far side has no marks to send.
    public var archived: Bool
    public var pinned: Bool
    /// A never-prompted session (v5, `DraftProbe`): `blocked · idle` to the
    /// harness, but waiting for *you to start it*, not for an answer. Joined
    /// where the daemon's files are and carried across the hop like the
    /// model; false off the wire from an older ccc.
    public var draft: Bool
    /// The session's folder as a worktree (v6, `WorktreeProbe`): its
    /// branch and how it stands against the default branch. Joined where
    /// the repository is and carried across the hop like the model; nil
    /// off the wire from an older ccc, and nil for a plain folder.
    public var worktree: WorktreeInfo?
    /// What the daemon's job file says this session is doing or asking
    /// (v10, `JobProbe`): the roster carries a state, this carries the
    /// sentence. Joined where the daemon's files are and carried across
    /// the hop like the model; nil off the wire from an older ccc, and nil
    /// for an interactive session, which has no job directory.
    public var job: JobInfo?

    /// The address: what `ccc attach` takes and the roster's row identity.
    public var ref: SessionRef { SessionRef(host: host, id: session.id) }
    public var id: SessionRef { ref }

    /// "It's your turn": blocked on something — a draft is blocked only
    /// on you choosing to begin, which is not a turn.
    public var isWaiting: Bool { session.state == .blocked && !draft }

    /// What this row has to say for itself (v10 slice 2): the daemon's own
    /// sentence for whatever state the roster says it is in — the live
    /// activity while working, the question while blocked, the result once
    /// done. The same string the banner carries, so a row and its
    /// notification cannot disagree.
    ///
    /// A **draft** says nothing: its `needs` is the harness's "send a
    /// prompt to start", which the row already tells you by being a draft.
    public var say: String? {
        guard !draft else { return nil }
        return job?.say(for: session.state)
    }

    /// Archived rows are out of the default list — unless the session is
    /// asking for input, which is never hidden (v4's rule: "it's your
    /// turn" beats tidiness). An archived draft folds away.
    public var isHidden: Bool { archived && !isWaiting }

    /// The activity order's rank: waiting, working, drafts, failed, then
    /// done/stopped. A draft sits below live work — it is yours to start
    /// whenever, and nothing about it is urgent.
    public var rank: Int { draft ? 2 : session.rank }

    public init(session: Session, host: String = Host.localName, model: String?, attached: Bool,
                archived: Bool = false, pinned: Bool = false, draft: Bool = false, worktree: WorktreeInfo? = nil,
                job: JobInfo? = nil) {
        self.session = session
        self.host = host
        self.model = model
        self.attached = attached
        self.archived = archived
        self.pinned = pinned
        self.draft = draft
        self.worktree = worktree
        self.job = job
    }

    /// Lenient on everything ccc adds, because these rows now arrive over
    /// ssh from *another build of ccc* (`ClaudeCLI.RosterSource.ccc`), which
    /// may be older than this one — a v1 `ccc list --json` has no `host` key
    /// at all. Only `session` is required; the rest fall back, and the
    /// poller overwrites `host` and `attached` with what it knows locally
    /// anyway. `Session` itself stays as lenient as the harness boundary
    /// demands.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        session = try container.decode(Session.self, forKey: .session)
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? Host.localName
        model = try container.decodeIfPresent(String.self, forKey: .model)
        attached = try container.decodeIfPresent(Bool.self, forKey: .attached) ?? false
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        worktree = try? container.decodeIfPresent(WorktreeInfo.self, forKey: .worktree)
        job = try? container.decodeIfPresent(JobInfo.self, forKey: .job)
    }
}

extension JSONDecoder {
    /// Reads what `ccc list --json` writes. The one thing that must agree is
    /// the date strategy: `Session.startedAt` goes out ISO-8601 (the CLI's
    /// printer sets it), and the default strategy would read that string as
    /// a number and fail. Pinned by `RemoteRosterTests`.
    public static var roster: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// One URL on the pane's grid, as `ccc links` reports it. `row` and `col`
/// are where the ⌘-click would have to land to open the same link.
public struct LinkInfo: Codable, Sendable, Equatable {
    public var url: String
    public var row: Int
    public var col: Int
    public init(url: String, row: Int, col: Int) {
        self.url = url
        self.row = row
        self.col = col
    }
}

public struct SnapshotInfo: Codable, Sendable {
    public var attachedTo: SessionRef?
    public var grid: Grid?
    public init(attachedTo: SessionRef?, grid: Grid?) {
        self.attachedTo = attachedTo
        self.grid = grid
    }
}

/// What the model column costs per tick, and which shape each row took.
/// Measured before the cadence is changed, so "the join is cheap" or "the
/// join is the poll" is a number rather than an intuition (CLAUDE.md's
/// perf rule).
public struct ModelJoinStats: Codable, Sendable, Equatable {
    /// Wall time of the join on the last tick, and the running mean.
    public var lastMs: Double?
    public var meanMs: Double?
    /// Cumulative, from `ModelProbe`: transcripts read, rows answered from
    /// the cache after one `stat`, rows whose file was gone.
    public var reads: Int
    public var hits: Int
    public var misses: Int
    /// Cumulative well lookups, and how many resolved to nothing — the
    /// expensive shape, since an unresolved id re-scans every well each tick.
    public var lookups: Int
    public var unresolved: Int

    public init(lastMs: Double?, meanMs: Double?, reads: Int, hits: Int, misses: Int,
                lookups: Int, unresolved: Int) {
        self.lastMs = lastMs
        self.meanMs = meanMs
        self.reads = reads
        self.hits = hits
        self.misses = misses
        self.lookups = lookups
        self.unresolved = unresolved
    }
}

/// One host's poll as `ccc stats` reports it. The fleet-wide numbers on
/// `StatsInfo` are the slowest host's; these say which.
public struct HostPollStats: Codable, Sendable, Equatable {
    public var host: String
    public var rows: Int
    public var lastMs: Double?
    public var meanMs: Double?
    public var count: Int
    /// Consecutive failures, and the last error when there is one.
    public var failures: Int
    public var error: String?
    public var stale: Bool
    public var evictions: Int
    public var lastSuccessAt: Date?

    public init(_ poll: HostPoll) {
        host = poll.host
        rows = poll.rows.count
        lastMs = poll.lastPollMs
        meanMs = poll.meanPollMs
        count = poll.pollCount
        failures = poll.failures
        error = poll.error
        stale = poll.isStale
        evictions = poll.evictions
        lastSuccessAt = poll.lastSuccessAt
    }
}

/// Whether "it's your turn" can reach the screen (v3). The black-pane
/// lesson (docs/DESIGN.md §7) applied to banners: events detected but
/// none authorized is a silent Mac, and the number has to say so.
public struct NotificationStats: Codable, Sendable, Equatable {
    /// `authorized`, `denied`, `notDetermined`, `provisional`, or
    /// `unavailable` (no bundle, so no notification center).
    public var authorization: String
    /// Events handed to the notification center since launch.
    public var posted: Int
    public var lastEvent: String?
    /// Hosts whose events are not posted (v3, slice 2), so a quiet Mac can
    /// be told apart from a broken one. Optional: an older server sends no
    /// such key.
    public var muted: [String]?
    /// Hook events received over the socket, how many were dropped for a
    /// muted host, and the last one's headline. Optional for the same wire
    /// reason.
    public var hooks: Int?
    public var hooksMuted: Int?
    public var lastHook: String?

    public init(authorization: String, posted: Int, lastEvent: String?,
                muted: [String]? = nil, hooks: Int? = nil, hooksMuted: Int? = nil, lastHook: String? = nil) {
        self.authorization = authorization
        self.posted = posted
        self.lastEvent = lastEvent
        self.muted = muted
        self.hooks = hooks
        self.hooksMuted = hooksMuted
        self.lastHook = lastHook
    }
}

public struct StatsInfo: Codable, Sendable {
    public var pid: Int32
    /// phys_footprint — the number Activity Monitor calls "Memory".
    public var footprintBytes: UInt64
    public var childPID: Int32?
    public var childFootprintBytes: UInt64?
    /// Last roster poll wall time, and the running mean.
    public var lastPollMs: Double?
    public var meanPollMs: Double?
    public var pollCount: Int
    /// The model join measured apart from the `claude agents` call it rides
    /// on. Optional as one field so an older server (which sends no such
    /// key) still decodes here — the wire rule in `ControlWireTests`.
    public var modelJoin: ModelJoinStats?
    /// The job join's cache behaviour (v10). It has no wall time of its
    /// own — `modelJoin.lastMs` times the whole detached block, this one
    /// included — but it needs its counters, because unlike the model join
    /// it runs for every local background row on every tick. Optional for
    /// the same wire reason as `modelJoin`.
    public var jobJoin: JobProbe.Counters?
    /// Per host, once there is more than one (v2). Optional for the same
    /// wire reason as `modelJoin`.
    public var hosts: [HostPollStats]?
    /// Bytes fed to the terminal since attach, and the rate over the last second.
    public var ptyBytesIn: UInt64
    public var ptyBytesPerSecond: Double
    /// How long the **app** has been running, which is what it prints beside
    /// (`ccc stats`' first line is pid, memory, uptime — all the app's). Read
    /// from the process, not from an attach: it used to be the pane's age,
    /// and `0` whenever nothing was attached.
    public var uptimeSeconds: Double
    /// Frames the pane actually handed to its on-screen layer, and how long
    /// ago the last one was. Bytes in without frames presented is a pane
    /// that is black to the human while every snapshot looks fine to the
    /// agent (2026-09-02) — the two must be able to read the same number.
    /// Optional: an older server sends no such key, and a headless pane
    /// has no screen.
    public var paneFramesPresented: Int?
    public var paneLastPresentedSecondsAgo: Double?
    /// The build serving the socket, so `ccc stats` from a newer command on
    /// PATH can say "the app is 4 builds behind, restart it" instead of
    /// meeting a "malformed request" on the next new verb. Optional: an
    /// older server sends no such key.
    public var build: BuildInfo?
    /// The window face's notifier; `nil` headless or from an older server.
    public var notifications: NotificationStats?
    /// The launch-and-wake fetch (v6 slice 7): how many rounds ran, what
    /// the last one cost, what it said — the measurement a fetch timer
    /// would have to earn its place against. `nil` headless or from an
    /// older server.
    public var fetch: FetchStats?

    public init(pid: Int32, footprintBytes: UInt64, childPID: Int32?, childFootprintBytes: UInt64?,
                lastPollMs: Double?, meanPollMs: Double?, pollCount: Int, modelJoin: ModelJoinStats? = nil,
                jobJoin: JobProbe.Counters? = nil, hosts: [HostPollStats]? = nil,
                ptyBytesIn: UInt64, ptyBytesPerSecond: Double, uptimeSeconds: Double,
                paneFramesPresented: Int? = nil, paneLastPresentedSecondsAgo: Double? = nil,
                build: BuildInfo? = .current) {
        self.build = build
        self.modelJoin = modelJoin
        self.jobJoin = jobJoin
        self.hosts = hosts
        self.paneFramesPresented = paneFramesPresented
        self.paneLastPresentedSecondsAgo = paneLastPresentedSecondsAgo
        self.pid = pid
        self.footprintBytes = footprintBytes
        self.childPID = childPID
        self.childFootprintBytes = childFootprintBytes
        self.lastPollMs = lastPollMs
        self.meanPollMs = meanPollMs
        self.pollCount = pollCount
        self.ptyBytesIn = ptyBytesIn
        self.ptyBytesPerSecond = ptyBytesPerSecond
        self.uptimeSeconds = uptimeSeconds
    }
}

/// One line of `ccc stats` (v6 slice 7): the fetch rounds the app ran on
/// its own — at launch and on wake, every distinct repository among the
/// local worktree rows — so "does a timer earn its place" is answered by
/// a number rather than a feeling.
public struct FetchStats: Codable, Sendable, Equatable {
    /// Rounds run (launch, wake), not repositories.
    public var rounds: Int
    /// Repositories fetched in the last round, and how many failed.
    public var repos: Int
    public var failed: Int
    /// The last round's wall time.
    public var lastMs: Double?
    /// The last round's reason and answers, one sentence.
    public var last: String?
    public var lastSecondsAgo: Double?

    public init(rounds: Int, repos: Int, failed: Int, lastMs: Double? = nil, last: String? = nil, lastSecondsAgo: Double? = nil) {
        self.rounds = rounds
        self.repos = repos
        self.failed = failed
        self.lastMs = lastMs
        self.last = last
        self.lastSecondsAgo = lastSecondsAgo
    }
}

public enum ControlSocket {
    /// `~/Library/Application Support/ccc/control.sock`. One app instance per
    /// user; a headless attach that finds a live socket refuses to start a
    /// second server and tells the user which process holds it.
    public static var defaultPath: String {
        if let override = ProcessInfo.processInfo.environment["CCC_CONTROL_SOCKET"], !override.isEmpty {
            return override
        }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "ccc/control.sock").path
    }
}
