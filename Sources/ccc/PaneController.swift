import AppKit
import CCCKit
import Foundation

/// The one pane and the one roster, and every gesture on them — as one
/// object both faces share. The window binds buttons to these methods; the
/// control socket maps `ControlRequest`s onto the same methods. That is the
/// parity rule made structural: there is no second code path to drift.
@MainActor
final class PaneController {
    let cli: ClaudeCLI
    let poller: RosterPoller
    private(set) var server: ControlServer?
    private(set) var session: AttachSession?
    /// The shell pane (v6 slice 4): a login shell in a session's folder,
    /// under the session pane. Same object as a session, different argv.
    private(set) var shell: AttachSession?
    private var shellCwd: String?
    /// Called when the attached child exits (detach or crash).
    var onSessionEnded: ((Int32) -> Void)?
    /// Called when a ← was taken instead of sent (`LeaveGesture`, v7 slice
    /// 1): on an empty prompt, or on a pane that has not painted yet (v8
    /// slice 2). The window hands the keyboard to the roster; headless
    /// says so on stderr. `leaveGestures` counts them for the send reply
    /// and `ccc stats`.
    var onLeaveRequested: (() -> Void)?
    private(set) var leaveGestures = 0
    /// ⌘-click on a link, and its twin `ccc links --open` (v7 slice 2),
    /// end here — one definition, so the gesture and the command cannot
    /// drift apart.
    func openLink(_ link: LinkScanner.Link) {
        NSWorkspace.shared.open(link.url)
    }
    /// Called when a session is attached; the window mounts `host.view`.
    var onSessionStarted: ((AttachSession) -> Void)?
    /// The shell pane's mount and unmount; nil headless, which is how
    /// `openShell` knows there is no second pane to open.
    var onShellStarted: ((AttachSession) -> Void)?
    var onShellEnded: (() -> Void)?
    /// The host factory: off-screen for headless, in-window for the app.
    /// The v1 pane (libghostty-vt + our Metal renderer) is the default since
    /// it won the six checks (docs/CHECKS.md, 2026-09-02); `CCC_CORE=swiftterm`
    /// falls back to the v0 stand-in, which is kept only as that escape hatch.
    var makeHost: @MainActor (Int, Int) -> TerminalHost = { cols, rows in
        PaneController.makeDefaultHost(frame: CGRect(x: 0, y: 0, width: 8 * cols, height: 17 * rows))
    }

    static var selectedCore: String { ProcessInfo.processInfo.environment["CCC_CORE"] ?? "ghostty" }

    static func makeDefaultHost(frame: CGRect) -> TerminalHost {
        selectedCore == "ghostty" ? GhosttyPane(frame: frame) : SwiftTermHost(frame: frame)
    }
    /// Sizes the window (or nothing, headless) wants the next attach to use.
    var defaultSize: (cols: Int, rows: Int) = (120, 40)
    /// The window's PNG, when there is a window.
    var peekProvider: (@MainActor () -> Data?)?
    /// Where the window and its pane are, when there is a window (v8 slice
    /// 3). The app fills it; headless leaves it nil, which is how `ccc
    /// capture` learns there is no window to point a camera at.
    var geometryProvider: (@MainActor () -> WindowGeometry?)?
    /// show / hide / close, when there is a window. Returns false if unknown.
    var windowAction: (@MainActor (String) -> Bool)?
    /// The notifier's state, when there is one (the window face).
    var notificationStats: (@MainActor () -> NotificationStats?)?
    /// The window face's notifier taking a hook event (v3, slice 2);
    /// answers with what it did. `nil` headless.
    var hookSink: (@MainActor (HookEvent) -> String)?

    /// Whether the human is looking at ccc — DEC 1004, forwarded to both
    /// panes, which each pass it to the child only if that child turned
    /// mode 1004 on. Item 17 slice 2.
    ///
    /// **The signal is the window being key**, not which pane holds first
    /// responder. A stricter reading would report the session pane blurred
    /// while the user works in the shell pane under it, and that is the
    /// wrong answer to the question the mode is actually being asked here:
    /// the harness turns 1004 on to decide whether to suppress the *phone*,
    /// and someone typing in ccc's shell pane is at this Mac. Two panes in
    /// one window are not two windows.
    ///
    /// Idempotent downstream — the host drops a repeat — so AppKit's
    /// generosity with key-window notifications costs nothing.
    private(set) var paneFocused = false

    @discardableResult
    func setPaneFocus(_ focused: Bool) -> Bool {
        paneFocused = focused
        // Both, and `||` rather than `&&`: "something was told" is the
        // answer, and a shell that never enabled 1004 must not make the
        // session's report look unsent.
        let toSession = session?.host.setFocused(focused) ?? false
        let toShell = shell?.host.setFocused(focused) ?? false
        return toSession || toShell
    }

    /// The hosts ccc knows about, and why any were dropped. Re-read when
    /// hosts.json's mtime moves, so `ccc hosts add studio` from a shell
    /// reaches a running app on the next tick — the same rule the roster
    /// overlay already follows, and one `stat` per tick to hold it.
    ///
    /// The load-once comment this replaces feared that a changing list
    /// would "change what the pane is talking to". It cannot: an attached
    /// pane holds an `AttachSession` whose argv was built when it started,
    /// so a reload moves what *new* refs resolve against and which hosts
    /// are polled, and never the running child.
    private(set) var hosts: HostConfig
    private(set) var hostIssues: [String]
    private let hostsPath: String
    private var hostsModifiedAt: Date?
    private var hostsWatch: Task<Void, Never>?
    /// Said once per change, for the window's notice and `ccc stats`.
    private(set) var lastHostChange: String?

    /// The last attach and how it ended, for the wake-up reattach: a remote
    /// pane whose ssh died across a sleep comes back on its own.
    private var lastRef: SessionRef?
    private var lastExitStatus: Int32?
    private var wokeAt: ContinuousClock.Instant?
    /// What the wake reattach did, for `ccc stats` (item 6). A night of
    /// `wakes` with no `attempts` and no `gaveUp` says the guard never
    /// fired — a different bug from the one the window bounds.
    private(set) var wakeStats = WakeStats()
    private var attemptsThisWake = 0
    /// The window face remembers what it was attached to across a relaunch
    /// (Sparkle's, or the user's) in UserDefaults; the headless face never
    /// does, or an agent's attach would steer the next window launch.
    var remembersAttach = false
    private static let rememberedRefKey = "ccc.lastAttachedRef"

    init(cli: ClaudeCLI, hosts: HostConfig.Loaded = HostConfig.load(),
         hostsPath: String = HostConfig.defaultPath) {
        self.cli = cli
        self.hosts = hosts.config
        self.hostIssues = hosts.issues
        self.hostsPath = hostsPath
        self.hostsModifiedAt = HostConfig.modificationDate(path: hostsPath)
        self.poller = RosterPoller(
            pollers: hosts.config.hosts.map { Self.makePoller(for: $0, local: cli) },
            built: Dictionary(uniqueKeysWithValues: hosts.config.hosts.map { ($0.name, $0) }))
    }

    /// One poller per host: `local` reads through this process's own
    /// resolved `claude` (the config's `local` has no path of its own),
    /// everything else goes behind its ssh prefix. Static so `init` and
    /// `reloadHostsIfChanged` share the one recipe — a host added at
    /// runtime has to be wired exactly like one present at launch, and two
    /// copies of this line is precisely how that would stop being true.
    private static func makePoller(for host: CCCKit.Host, local: ClaudeCLI) -> HostPoller {
        HostPoller(cli: host.isLocal ? local : ClaudeCLI.of(host), hostName: host.name)
    }

    /// Start the roster and the hosts.json watch together. Both faces call
    /// this — the window at launch, `--headless` when it takes the socket —
    /// so neither can have the roster without the watch.
    func start() {
        poller.start()
        guard hostsWatch == nil else { return }
        hostsWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.reloadHostsIfChanged()
            }
        }
    }

    /// Re-read hosts.json when its mtime moved, and bring the pollers in
    /// line. Returns what changed, or nil when nothing did — one `stat` in
    /// the common case. A file that goes bad degrades exactly as it does at
    /// launch (`HostConfig.load`): local only, with the reason kept.
    @discardableResult
    func reloadHostsIfChanged() -> String? {
        let modified = HostConfig.modificationDate(path: hostsPath)
        guard modified != hostsModifiedAt else { return nil }
        hostsModifiedAt = modified
        let loaded = HostConfig.load(path: hostsPath)
        guard loaded.config != hosts || loaded.issues != hostIssues else { return nil }
        hosts = loaded.config
        hostIssues = loaded.issues
        let said = poller.sync(to: loaded.config) { Self.makePoller(for: $0, local: cli) }.said
        lastHostChange = said
        if let said { onHostsChanged?(said) }
        return said
    }

    /// The window's notice when the host list moved under it. `nil` headless.
    var onHostsChanged: ((String) -> Void)?

    /// The CLI for one host — this process's own `claude` for `local`, the
    /// ssh prefix for anything else. The single place a ref becomes a command.
    func cli(for ref: SessionRef) throws -> ClaudeCLI {
        guard let host = hosts.host(named: ref.host) else {
            throw AttachError.unknownHost(ref.host, known: hosts.hosts.map(\.name))
        }
        if host.isLocal { return cli }
        if let problem = host.validate() { throw AttachError.badHost(problem) }
        guard let remote = ClaudeCLI.of(host) else { throw AttachError.badHost("host '\(host.name)' is not usable") }
        return remote
    }

    /// The attach command for a ref, as a pasteable line (the roster's
    /// "copy" and the pane run the same words).
    func attachCommandLine(for ref: SessionRef) -> String {
        guard let cli = try? cli(for: ref) else { return "claude attach \(ref.id)" }
        return cli.attachCommandLine(id: ref.id)
    }

    func serve(path: String = ControlSocket.defaultPath) throws {
        let server = ControlServer(path: path) { [weak self] request in
            guard let self else { return .error("controller gone") }
            return await self.handle(request)
        }
        try server.start()
        self.server = server
    }

    func stop() {
        poller.stop()
        hostsWatch?.cancel()
        hostsWatch = nil
        server?.stop()
        server = nil
    }

    // MARK: gestures

    func attach(ref: SessionRef, cols: Int? = nil, rows: Int? = nil) throws {
        if let session, session.isRunning {
            throw AttachError.busy(session.ref)
        }
        install(try viewer(for: ref, cols: cols, rows: rows))
    }

    /// A viewer for `ref`: the child is running and its core is filling,
    /// but it is not *the* pane — nothing above has been told it exists,
    /// the roster carries no mark for it, and its exit is nobody's news.
    ///
    /// Split out of `attach` for the overlapped switch (`swap`), which
    /// needs precisely this: something it can wait on before the pane on
    /// screen has paid anything for it.
    private func viewer(for ref: SessionRef, cols: Int?, rows: Int?) throws -> AttachSession {
        let cli = try cli(for: ref)
        // The master socket's directory must exist before ssh is exec'd:
        // the PTY child has no way to report a mkdir failure back to us.
        try cli.prepareControlDirectory()
        let size = (cols ?? defaultSize.cols, rows ?? defaultSize.rows)
        let host = makeHost(size.0, size.1)
        // The click and `ccc links --open` end in the same `openLink`, so
        // the gesture is counted once wherever it came from.
        (host as? GhosttyPane)?.onOpenLink = { [weak self] in self?.openLink($0) }
        let session = try AttachSession(ref: ref, argv: cli.attachArgv(id: ref.id), host: host,
                                        options: .init(cols: size.0, rows: size.1))
        session.onLeaveGesture = { [weak self] in
            guard let self else { return }
            self.leaveGestures += 1
            self.onLeaveRequested?()
        }
        return session
    }

    /// Make a viewer the pane: the exit wiring, the roster's mark, the
    /// remembered ref, the mount. Everything here is what being on screen
    /// means, which is why the overlapped switch does it last and all at
    /// once — the swap *is* this call.
    private func install(_ session: AttachSession) {
        let ref = session.ref
        session.onExit = { [weak self] status in
            guard let self else { return }
            self.poller.attachedRef = nil
            self.lastExitStatus = status
            // A clean exit is the user leaving (Ctrl+Z, or the session
            // ending); anything else is the process dying under them and
            // is worth coming back to.
            if status == 0, self.remembersAttach {
                UserDefaults.standard.removeObject(forKey: Self.rememberedRefKey)
            }
            self.onSessionEnded?(status)
            self.reattachIfSleepKilledIt(ref: ref, status: status)
        }
        self.session = session
        self.lastRef = ref
        self.lastExitStatus = nil
        if remembersAttach {
            UserDefaults.standard.set(ref.description, forKey: Self.rememberedRefKey)
        }
        poller.attachedRef = ref
        // Tell the new child straight away whether anyone is looking. It
        // has not negotiated mode 1004 yet and cannot hear this, which is
        // why the host holds the answer and re-sends it on the read that
        // turns the mode on. The case this exists for is a session
        // attached while the window is *not* key: with no report, the
        // harness treats unknown focus as present and suppresses the
        // user's phone for a pane nobody is watching.
        setPaneFocus(paneFocused)
        onSessionStarted?(session)
    }

    /// The click's attach (v6, the same night as the shell pane): the
    /// pane follows the click. Nothing attached: attach. The same ref:
    /// nothing to do. Another ref: `swap` — which since v8 slice 2 leaves
    /// the old one only *after* the new one is on screen, rather than
    /// before. The "busy" refusal was v0's guard, and every gesture that
    /// met it (⇧⌘N's attach-when-started, a second row's ⏎) had to work
    /// around it. Returns the sentence.
    func switchTo(ref: SessionRef, cols: Int? = nil, rows: Int? = nil) async throws -> String {
        guard let outgoing = session, outgoing.isRunning else {
            try attach(ref: ref, cols: cols, rows: rows)
            return "attached \(ref)"
        }
        if outgoing.ref == ref { return "already attached to \(ref)" }
        return try await swap(to: ref, from: outgoing, cols: cols, rows: rows)
    }

    /// The overlapped switch (v8 slice 2). The old way — detach, then
    /// attach — cost two things, and the second one was not cosmetic:
    ///
    /// 1. **A blank pane for seconds.** `attach` builds a brand-new host,
    ///    so the window mounted an empty grid and sat on it until the new
    ///    `claude attach` painted: up to 12 s over ssh (experiment 3), on
    ///    an 8 s `waitUntilDrawn` timeout. Not a flicker, the wait.
    /// 2. **A hole in the ← guard.** `LeaveGesture` is a read of the grid
    ///    and its "no" means *send the key*, so across that blank window
    ///    ← went to the child — which answers it by detaching the session
    ///    and opening the agents view inside the attach client, starting
    ///    with the workspace-trust dialog for whatever cwd the bundle
    ///    inherited. Raised by the user 2026-09-03: the folder warning.
    ///
    /// Both go away by never showing the blank grid. Experiment 2 measured
    /// that the daemon accepts concurrent attaches and mirrors one PTY to
    /// every viewer, so the incoming session runs *behind* the outgoing
    /// one — unmounted, parsing into its own core, costing the screen
    /// nothing — and the swap happens in one `install` once it has drawn.
    ///
    /// Which pane owns the keyboard during the overlap is not the taste
    /// call the queue called it: the old pane must keep it, because the
    /// old pane's grid is the one still showing `❯ `, and that grid is
    /// what makes the guard fire. Leaving the keyboard put is what closes
    /// hole 2 across the whole overlap; `LeaveGesture.isUndrawn` closes
    /// what is left, which is the first attach, with no pane to overlap.
    private func swap(to ref: SessionRef, from outgoing: AttachSession,
                      cols: Int?, rows: Int?) async throws -> String {
        // The incoming grid is built at the size the outgoing one is
        // *showing*, read back through the seam rather than re-estimated.
        // A pane that paints at one size and is resized on mount reflows
        // the TUI in the exact frame the change is meant to be invisible.
        let showing = outgoing.host.snapshot()
        let incoming = try viewer(for: ref,
                                  cols: cols ?? showing.cols, rows: rows ?? showing.rows)
        swapGeneration += 1
        let mine = swapGeneration
        await Self.waitUntilDrawn(incoming)
        // A newer click during the wait wins: this viewer goes away
        // without ever having been seen, and the pane never moved.
        guard mine == swapGeneration else {
            incoming.terminate()
            return "superseded by a newer attach"
        }
        // It died instead of drawing (a bad ref, ssh refused, the session
        // ended). Keep the pane that works and say what happened.
        guard incoming.isRunning else {
            throw AttachError.attachDied(ref, incoming.exitStatus ?? -1)
        }
        // The outgoing child's exit is ours to expect, not news: its
        // `onExit` would tell the window a session ended and unmount the
        // pane we are about to mount. Same for its gesture — the keyboard
        // belongs to the incoming pane from here.
        outgoing.onExit = nil
        outgoing.onLeaveGesture = nil
        let previous = outgoing.ref
        install(incoming)
        // Ctrl+Z, the harness's own detach, which keeps the session and
        // its draft. After the mount, so nothing waits on it to see the
        // new pane.
        await outgoing.detach()
        return "attached \(ref) (left \(previous))"
    }

    /// Bumped by every swap, so a wait that finishes after a newer click
    /// knows it has been superseded.
    private var swapGeneration = 0

    /// Spawn (v5): `claude --bg` on `hostName` with the request's words —
    /// what `ccc spawn --host <name>` runs — then a poll so the roster
    /// carries the row before the sheet closes. The one place the sheet's
    /// fields become a command.
    func spawn(_ request: SpawnRequest, on hostName: String) async throws -> SpawnResult {
        let cli = try cli(for: SessionRef(host: hostName, id: "-"))
        let result = try await cli.spawn(request)
        await poller.tick()
        return result
    }

    /// Attach to what the last run was attached to, if it is still in the
    /// roster and attachable. Called by the window after its first poll.
    func reattachAfterRelaunch() {
        guard remembersAttach, session?.isRunning != true,
              let stored = UserDefaults.standard.string(forKey: Self.rememberedRefKey),
              let ref = SessionRef.parse(stored) else { return }
        guard let row = poller.state.rows.first(where: { $0.ref == ref }), row.session.isAttachable else {
            UserDefaults.standard.removeObject(forKey: Self.rememberedRefKey)
            return
        }
        try? attach(ref: ref)
    }

    func detach() async {
        guard let session, session.isRunning else { return }
        await session.detach()
    }

    /// Archive / pin (v4): exactly `ccc archive <ref>` — the overlay file
    /// here for a local ref, the far side's own verb for a remote one —
    /// then a poll, so the row moves now rather than a tick later.
    func mark(_ ref: SessionRef, _ change: MarkChange) async throws -> String {
        let said = try await cli(for: ref).mark(change, id: ref.id)
        await poller.poller(for: ref.host)?.tick()
        return said
    }

    /// Land a worktree branch (v6): exactly `ccc merge <ref> --<strategy>`
    /// — git in the main checkout here, the far side's own verb for a
    /// remote ref — then a poll, so the row's ↑ count moves now.
    func merge(_ ref: SessionRef, _ strategy: MergeStrategy) async throws -> MergeOutcome {
        let outcome = try await cli(for: ref).merge(strategy, id: ref.id)
        await poller.poller(for: ref.host)?.tick()
        return outcome
    }

    /// Update from master (v6 slice 6): exactly `ccc update <ref>` — git
    /// in the worktree here, the far side's own verb for a remote ref —
    /// then a poll, so the row's ↓ count moves now. A conflict comes back
    /// with `ask` set, the prompt the session could be handed.
    func update(_ ref: SessionRef) async throws -> MergeOutcome {
        let outcome = try await cli(for: ref).update(id: ref.id)
        await poller.poller(for: ref.host)?.tick()
        return outcome
    }

    /// Fetch (v6 slice 7): exactly `ccc fetch <ref>`, then a poll so the
    /// ⇣ marks move now.
    func fetch(_ ref: SessionRef) async throws -> MergeOutcome {
        let outcome = try await cli(for: ref).fetch(id: ref.id)
        await poller.poller(for: ref.host)?.tick()
        return outcome
    }

    /// Pull master (v6 slice 7): exactly `ccc pull <ref>`, then a poll.
    func pull(_ ref: SessionRef) async throws -> MergeOutcome {
        let outcome = try await cli(for: ref).pull(id: ref.id)
        await poller.poller(for: ref.host)?.tick()
        return outcome
    }

    /// The fetch the app runs on its own (slice 7): once after the first
    /// poll and once on wake — every distinct repository among the local
    /// worktree rows, concurrently, off the main actor. Remote hosts fetch
    /// on their own launch and wake. No timer: `ccc stats` measures these
    /// two first, and a timer has to earn its place against the number.
    private(set) var fetchStats = FetchStats(rounds: 0, repos: 0, failed: 0)
    private var lastFetchAt: Date?

    func fetchAll(reason: String) async {
        let repos = Set(poller.state.rows.filter { $0.host == Host.localName }.compactMap { $0.worktree?.repo })
        guard !repos.isEmpty else {
            fetchStats = FetchStats(rounds: fetchStats.rounds + 1, repos: 0, failed: 0, lastMs: 0, last: "\(reason): no local worktree rows")
            lastFetchAt = Date()
            return
        }
        let started = ContinuousClock.now
        let results = await withTaskGroup(of: (String, MergeOutcome).self) { group in
            for repo in repos {
                group.addTask { (repo, GitFetch.perform(repo: repo)) }
            }
            var out: [(String, MergeOutcome)] = []
            for await result in group { out.append(result) }
            return out.sorted { $0.0 < $1.0 }
        }
        let ms = Double((ContinuousClock.now - started).ms)
        let failed = results.filter { !$0.1.merged }.count
        let summary = results.map { "\(URL(filePath: $0.0).lastPathComponent): \($0.1.said)" }.joined(separator: "; ")
        fetchStats = FetchStats(rounds: fetchStats.rounds + 1, repos: results.count, failed: failed, lastMs: ms, last: "\(reason): \(summary)")
        lastFetchAt = Date()
        await poller.poller(for: Host.localName)?.tick()
    }

    /// "Ask the session" (v6 slice 6): a prompt through the pane. Attach
    /// (the pane follows the click, so a session on screen is left), wait
    /// for the TUI to draw when the attach was fresh, type the prompt,
    /// press Enter. The TUI queues a prompt typed while it is working, so
    /// a busy session is asked too — it reads it when it is done.
    func ask(_ ref: SessionRef, prompt: String) async throws -> String {
        // A switch now waits for the incoming pane to draw before it
        // becomes the pane (`swap`), so the only wait left here is the
        // first attach — the one with no pane to overlap with.
        let wasOnScreen = session?.isRunning == true
        _ = try await switchTo(ref: ref)
        guard let session, session.isRunning else { throw AttachError.nothingAttached }
        if !wasOnScreen { await Self.waitUntilDrawn(session) }
        session.send(text: prompt)
        // The Enter after the text, not with it: a "\r" inside the same
        // read is a paste's newline to the TUI, not a submit.
        try? await Task.sleep(for: .milliseconds(200))
        session.press(NamedKey("enter")!)
        return "asked \(ref): \(prompt)"
    }

    /// The TUI is up and has stopped changing — two reads a quarter second
    /// apart agree — or eight seconds passed. A fresh `claude attach`
    /// draws in well under that; over ssh, a little later. Bytes typed
    /// before it is up land in the harness's attach client, not the
    /// prompt box, which is why anything that types waits on this.
    ///
    /// "Up" is `LeaveGesture.isUndrawn` inverted, and deliberately not
    /// "the grid has something on it": the attach client prints a one-line
    /// wake message first, and one line is both non-blank and perfectly
    /// stable, so the old check returned on it. Harmless when all this did
    /// was delay typing; not harmless now that `swap` mounts on it — the
    /// swap would land on the wake message, which is the blank pane over
    /// again with a word on it.
    private static func waitUntilDrawn(_ session: AttachSession, timeout: Duration = .seconds(8)) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        var previous: Grid?
        while clock.now < deadline, session.isRunning {
            try? await Task.sleep(for: .milliseconds(250))
            let grid = session.host.snapshot()
            if !LeaveGesture.isUndrawn(grid), let previous, previous == grid { return }
            previous = grid
        }
    }

    /// Open in Terminal (v6 slice 4): exactly `ccc shell <ref>` — a login
    /// shell in the row's folder, the ssh hop included, in the pane under
    /// the session. One shell at a time, and it follows the click when it
    /// is free: the same folder is focused; a different folder replaces a
    /// shell sitting at its prompt, and focuses one that is running
    /// something, saying so. Returns the sentence, and whether a pane was
    /// opened (false when the open one was focused).
    @discardableResult
    func openShell(_ ref: SessionRef, atRepo: Bool = false, cols: Int? = nil, rows: Int? = nil) async throws -> (said: String, opened: Bool) {
        guard onShellStarted != nil else { throw AttachError.badHost("no window for a shell pane (headless)") }
        guard let row = poller.state.rows.first(where: { $0.ref == ref }) else {
            throw AttachError.badHost("no session '\(ref)' in the roster")
        }
        let folder = shellFolder(row, atRepo: atRepo)
        if let shell, shell.isRunning {
            let where_ = hosts.shortCwd(shellCwd ?? "", host: shell.ref.host)
            if shellCwd == folder && shell.ref.host == ref.host {
                return ("the shell pane is already open, in \(where_)", false)
            }
            guard shell.isAtPrompt else {
                return ("the shell in \(where_) is running something; ⇧⌘T closes it", false)
            }
            // Free, so it follows the click: SIGHUP, wait for the exit so
            // the window unmounts the old pane before mounting the new.
            shell.terminate()
            let deadline = ContinuousClock.now + .seconds(2)
            while shell.isRunning, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            if shell.isRunning { throw AttachError.badHost("the shell in \(where_) did not exit; ⇧⌘T closes it") }
        }
        let cli = try cli(for: ref)
        try cli.prepareControlDirectory()
        let size = (cols ?? defaultSize.cols, rows ?? min(defaultSize.rows, 14))
        let host = makeHost(size.0, size.1)
        // Local: the shell's cwd is the PTY's. Remote: the `cd` is in the
        // words, and the PTY's own cwd means nothing to ssh.
        let cwd = ref.isLocal ? folder : nil
        let shell = try AttachSession(ref: ref, argv: cli.shellArgv(cwd: folder), host: host,
                                      options: .init(cols: size.0, rows: size.1, cwd: cwd))
        shell.onExit = { [weak self] _ in
            guard let self else { return }
            self.shell = nil
            self.shellCwd = nil
            self.onShellEnded?()
        }
        self.shell = shell
        self.shellCwd = folder
        onShellStarted?(shell)
        // The sentence names the way out. Until v12 slice 1 only the two
        // *refusals* did ("… is running something; ⇧⌘T closes it"), so the
        // shortcut was advertised exactly when something had gone wrong and
        // never on the open that raises the question. One shell at a time
        // means the close verb needs no argument, so it fits the sentence.
        return ("shell in \(hosts.shortCwd(folder, host: ref.host))" + (ref.isLocal ? "" : " on \(ref.host)")
                + " — ⇧⌘T closes it", true)
    }

    /// Where `openShell` would put a shell for this row — the one rule,
    /// asked by the row's menu (`shellIsOpen`) as well, so the item that
    /// says "Close Terminal" and the open that says "already open" can
    /// never disagree about which folder is which.
    ///
    /// The repository's main checkout (`atRepo`): git's answer when the row
    /// has one, the harness's path convention otherwise.
    private func shellFolder(_ row: SessionRow, atRepo: Bool) -> String {
        atRepo ? (row.worktree?.repo ?? RepoPath.root(of: row.session.cwd)) : row.session.cwd
    }

    /// True when the shell pane on screen is the one this row's item would
    /// open — which is what makes that item read **Close Terminal** instead
    /// (v12 slice 1). Read when the menu opens, like the mute mark below it.
    ///
    /// The condition is `openShell`'s own "already open" test, not a looser
    /// "some shell exists": a shell sitting in another row's folder is
    /// something this item would *replace*, so it stays "Open in Terminal"
    /// there. One shell at a time makes the two mutually exclusive across
    /// the whole roster — at most one row, and at most one of its two
    /// items, is ever the close.
    func shellIsOpen(_ ref: SessionRef, atRepo: Bool = false) -> Bool {
        guard let shell, shell.isRunning, shell.ref.host == ref.host else { return false }
        guard let row = poller.state.rows.first(where: { $0.ref == ref }) else { return false }
        return shellCwd == shellFolder(row, atRepo: atRepo)
    }

    /// ⇧⌘T's twin: SIGHUP to the shell; `onExit` unmounts the pane.
    func closeShell() -> Bool {
        guard let shell, shell.isRunning else { return false }
        shell.terminate()
        return true
    }

    /// Push (v6 slice 3): exactly `ccc push <ref> [--base]`, then a poll
    /// so the ⇡ mark clears now.
    func push(_ ref: SessionRef, _ target: PushTarget) async throws -> MergeOutcome {
        let outcome = try await cli(for: ref).push(target, id: ref.id)
        await poller.poller(for: ref.host)?.tick()
        return outcome
    }

    /// The harness's `rm` behind the host prefix (`ccc rm <ref>`), its
    /// sentence returned whether it removed or kept. A poll after, so a
    /// removed row leaves the roster at once.
    func delete(_ ref: SessionRef) async throws -> String {
        let result = try await cli(for: ref).rm(id: ref.id)
        await poller.poller(for: ref.host)?.tick()
        return result.said
    }

    /// The wake-up gesture: evict every remote ssh master and poll again,
    /// then bring back a remote pane the sleep killed. Called by the app on
    /// `NSWorkspace.didWakeNotification` and by `ccc hosts reconnect`.
    @discardableResult
    func reconnect(host: String? = nil) async -> [HostPoll] {
        wokeAt = .now
        wakeStats.wakes += 1
        attemptsThisWake = 0
        // Only a wake with a remote pane in play can produce a reattach, so
        // only those make `attempts == 0` mean anything. Read before the
        // poll, because the poll is what may notice the pane is gone.
        if let lastRef, lastRef.host != Host.localName, session != nil || lastExitStatus == Self.sshExit {
            wakeStats.withRemotePane = (wakeStats.withRemotePane ?? 0) + 1
        }
        let polls = await poller.reconnect(host: host)
        // Already dead when we woke: ssh noticed before we did.
        if let lastRef, session?.isRunning != true, lastExitStatus == Self.sshExit, lastRef.host != Host.localName,
           host == nil || host == lastRef.host {
            reattach(ref: lastRef)
        }
        return polls
    }

    /// ssh's own exit status; `claude attach` ending by Ctrl+Z exits 0 and
    /// must never be re-run behind the user's back.
    private static let sshExit: Int32 = 255

    /// How long after a wake a remote pane's ssh death still counts as the
    /// sleep's doing. **60 s since 2026-09-04, from 20** — the lid night
    /// (docs/EVIDENCE.md "item 6 — the lid") measured what this window is
    /// up against and 20 s was inside it, not around it:
    ///
    /// A wake is 14–22 s of failing ssh before the tailnet answers. Each
    /// attempt costs `ConnectTimeout=5`, and the first cannot start until
    /// `reconnect`'s own poll has failed, so the retries land at roughly
    /// +5, +10 and +15 s and the window shuts at +20 — **giving up one or
    /// two seconds before the network comes back**, on the three wakes in
    /// eighteen that took 21–22 s. The old bound was not merely tight, it
    /// was aligned to fail. 60 s is ~3x the measured worst case, the same
    /// headroom `waitUntilDrawn` carries, and it stays safe because 255 is
    /// ssh's own status: a detach or a finished session exits 0 and is
    /// never replayed.
    private static let wakeWindow: Duration = .seconds(60)

    /// A remote attach that exits with ssh's status within `wakeWindow` of
    /// a wake is the sleep's doing, not the user's: run the same argv
    /// again. The draft lives with the session (experiment 5), so nothing
    /// typed is lost. A failed replay exits 255 in its turn and comes back
    /// through here, which is what makes this a retry rather than one shot.
    private func reattachIfSleepKilledIt(ref: SessionRef, status: Int32) {
        guard status == Self.sshExit, ref.host != Host.localName, let wokeAt else { return }
        let since = wokeAt.duration(to: .now)
        guard since < Self.wakeWindow else {
            // The pane stays dead until the user clicks. Counted, because
            // from the outside this is indistinguishable from ssh never
            // having noticed the death at all.
            wakeStats.gaveUp += 1
            wakeStats.last = "gave up on \(ref) after \(attemptsThisWake) attempts, \(Self.seconds(since)) s after wake"
            return
        }
        reattach(ref: ref)
    }

    /// One replay of the same argv, counted. Every reattach path lands here
    /// so `attempts` cannot drift from what actually ran. `attempts` is the
    /// lifetime total and `attemptsThisWake` is what the sentence says —
    /// the two differ the moment there is a second wake, which the lid
    /// night says is every fifteen minutes.
    private func reattach(ref: SessionRef) {
        wakeStats.attempts += 1
        attemptsThisWake += 1
        let since = wokeAt.map { Self.seconds($0.duration(to: .now)) } ?? "?"
        wakeStats.last = "reattaching \(ref), attempt \(attemptsThisWake), \(since) s after wake"
        try? attach(ref: ref)
    }

    private static func seconds(_ d: Duration) -> String {
        String(format: "%.0f", Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18)
    }

    enum AttachError: Error, CustomStringConvertible {
        case busy(SessionRef)
        case nothingAttached
        case unknownHost(String, known: [String])
        case badHost(String)
        /// The incoming half of an overlapped switch never drew: it exited
        /// while the pane on screen still had the keyboard. Nothing moved,
        /// which is what the sentence has to say.
        case attachDied(SessionRef, Int32)
        var description: String {
            switch self {
            case .busy(let ref): return "already attached to \(ref); detach first"
            case .nothingAttached: return "nothing attached"
            case .unknownHost(let name, let known):
                return "unknown host '\(name)' (known: \(known.joined(separator: ", "))); add it with `ccc hosts add`"
            case .badHost(let problem): return problem
            case .attachDied(let ref, let status):
                return "\(ref) did not attach (exit \(status)); the pane did not move"
            }
        }
    }

    // MARK: the socket → the same gestures

    func handle(_ request: ControlRequest) async -> ControlResponse {
        switch request {
        case .list:
            await poller.tick()
            return .list(poller.state.sorted)
        case .attach(let ref):    // a SessionRef; the label is the wire key
            do {
                return .ok(try await switchTo(ref: ref))
            } catch {
                return .error("\(error)")
            }
        case .detach:
            guard let session, session.isRunning else { return .error(AttachError.nothingAttached.description) }
            await session.detach()
            return .ok("detached \(session.ref)")
        case .snapshot(let colors):
            guard let session else { return .snapshot(SnapshotInfo(attachedTo: nil, grid: nil)) }
            return .snapshot(SnapshotInfo(attachedTo: session.isRunning ? session.ref : nil,
                                          grid: session.host.snapshot(colors: colors)))
        case .links(let open):
            guard let session, session.isRunning else { return .error(AttachError.nothingAttached.description) }
            let found = LinkScanner.links(in: session.host.snapshot())
            guard let open else {
                return .links(found.map { LinkInfo(url: $0.url.absoluteString, row: $0.row, col: $0.columns.lowerBound) })
            }
            // 1-based, because the list it indexes is printed 1-based.
            guard open >= 1, open <= found.count else {
                return .error(found.isEmpty ? "no links on the grid" : "no link \(open); the grid has \(found.count)")
            }
            let link = found[open - 1]
            openLink(link)
            return .ok("opened \(link.url.absoluteString)")
        case .send(let text, let keys, let wheel, let paste):
            guard let session, session.isRunning else { return .error(AttachError.nothingAttached.description) }
            if let text { session.send(text: text) }
            if let paste {
                guard session.paste(paste) else { return .error("host cannot paste (\(PaneController.selectedCore) core)") }
            }
            var taken = 0
            for name in keys ?? [] {
                guard let key = NamedKey(name) else { return .error("unknown key '\(name)'") }
                let before = leaveGestures
                guard session.press(key) else { return .error("host cannot encode '\(name)'") }
                taken += leaveGestures - before
            }
            // The gesture's twin says what the window did instead of
            // sending: the reply is how a script learns the key went to
            // the roster, not the child.
            // Not "on an empty prompt" any more: the guard also takes the
            // key on a pane that has not painted, where there is no prompt
            // to be at (`LeaveGesture.isUndrawn`).
            if taken > 0 { return .ok("sent; ← taken (the roster takes the keyboard, the key is not sent)") }
            if let wheel, wheel != 0 {
                guard let pane = session.host as? GhosttyPane else { return .error("wheel needs the ghostty pane; this session is on the \(PaneController.selectedCore) core") }
                pane.wheel(lines: wheel)
            }
            return .ok("sent")
        case .select(let region):
            guard let session, session.isRunning else { return .error(AttachError.nothingAttached.description) }
            guard let pane = session.host as? GhosttyPane else {
                return .error("selection needs the ghostty pane; this session is on the \(PaneController.selectedCore) core")
            }
            guard let region else {
                pane.select(nil)
                return .ok("selection cleared")
            }
            guard pane.select(region) else {
                let size = pane.size
                let grain = region.grain ?? .cell
                // A word or line grain can also come back empty-handed — the
                // core answers NO_VALUE for a point with nothing selectable
                // under it — so the message names both ways to fail.
                if grain != .cell, pane.select(SelectionRegion(from: region.from, to: region.from)) {
                    pane.select(nil)
                    return .error("no \(grain.rawValue) at \(region.from.col),\(region.from.row)")
                }
                return .error("\(region.from.col),\(region.from.row) → \(region.to.col),\(region.to.row) is not on a \(size.cols)x\(size.rows) grid")
            }
            let grain = (region.grain ?? .cell) == .cell ? "" : " (\(region.grain!.rawValue))"
            return .ok("selected \(region.from.col),\(region.from.row) → \(region.to.col),\(region.to.row)\(region.rectangle ? " (rectangle)" : "")\(grain)")
        case .copy:
            guard let session, session.isRunning else { return .error(AttachError.nothingAttached.description) }
            guard let pane = session.host as? GhosttyPane else {
                return .error("copy needs the ghostty pane; this session is on the \(PaneController.selectedCore) core")
            }
            guard let text = pane.copySelection() else { return .error("nothing selected") }
            return .ok(text)
        case .resize(let cols, let rows):
            guard let session, session.isRunning else { return .error(AttachError.nothingAttached.description) }
            session.resize(cols: cols, rows: rows)
            return .ok("resized to \(cols)x\(rows)")
        case .peek:
            guard let peekProvider, let png = peekProvider() else { return .error("no window to peek (headless)") }
            return .peek(png: png)
        case .geometry:
            guard let geometryProvider, let geometry = geometryProvider() else {
                return .error("no window (headless)")
            }
            return .geometry(geometry)
        case .window(let action):
            guard let windowAction else { return .error("no window (headless)") }
            return windowAction(action) ? .ok("window \(action)") : .error("unknown window action '\(action)' (\(WindowAction.usage))")
        case .focus(let focused):
            // A read says what the window last reported; a write asserts
            // it and says whether the child was actually told. "not
            // reported" is the honest answer, not a failure: it is what a
            // child with mode 1004 off looks like, and a shell pane at a
            // bare prompt is exactly that.
            guard let focused else {
                return .ok("focus \(paneFocused ? "in" : "out")")
            }
            // Three outcomes, and they must not be spelled the same. A
            // repeat is silent because the child already knows; a pane
            // with mode 1004 off is silent because it never asked. Saying
            // "no pane has 1004 on" for a repeat sends the reader hunting
            // a mode that is in fact on — which it did, once, live.
            let repeated = paneFocused == focused
            let sent = setPaneFocus(focused)
            let word = focused ? "in" : "out"
            if sent { return .ok("focus \(word)") }
            if repeated { return .ok("focus \(word) (already)") }
            return .ok("focus \(word) (not reported — no attached pane has DEC 1004 on)")
        case .stats:
            var stats: StatsInfo
            if let session {
                stats = session.stats(pollState: poller.state)
            } else {
                let me = getpid()
                let state = poller.state
                stats = StatsInfo(pid: me, footprintBytes: ProcessStats.footprint(of: me) ?? 0, childPID: nil,
                                  childFootprintBytes: nil, lastPollMs: state.lastPollMs,
                                  meanPollMs: state.meanPollMs, pollCount: state.pollCount,
                                  modelJoin: state.modelJoin, jobJoin: state.jobJoin,
                                  hosts: state.hosts.map(HostPollStats.init),
                                  ptyBytesIn: 0, ptyBytesPerSecond: 0,
                                  uptimeSeconds: ProcessStats.uptime(of: me) ?? 0)
            }
            stats.notifications = notificationStats?()
            var fetch = fetchStats
            fetch.lastSecondsAgo = lastFetchAt.map { Date().timeIntervalSince($0) }
            stats.fetch = fetch
            stats.wake = wakeStats
            return .stats(stats)
        case .reconnect(let host):
            if let host, poller.poller(for: host) == nil {
                return .error(AttachError.unknownHost(host, known: hosts.hosts.map(\.name)).description)
            }
            let polls = await reconnect(host: host)
            let report = polls.map { poll -> String in
                let ms = poll.lastPollMs.map { String(format: "%.0f ms", $0) } ?? "-"
                let evicted = poll.evictions > 0 ? "" : " (no master to evict)"
                return poll.error.map { "\(poll.host) FAILED \(ms): \($0)" } ?? "\(poll.host) ok \(ms), \(poll.rows.count) sessions\(evicted)"
            }
            return .ok("reconnected: " + report.joined(separator: "; "))
        case .hook(let event):
            guard let hookSink else { return .error("no notifier (headless)") }
            return .ok(hookSink(event))
        case .shell(let ref, let repo):
            do {
                return .ok(try await openShell(ref, atRepo: repo ?? false).said)
            } catch {
                return .error("\(error)")
            }
        case .shellClose:
            return closeShell() ? .ok("shell closed") : .error("no shell pane is open")
        case .ask(let ref, let prompt):
            do {
                return .ok(try await ask(ref, prompt: prompt))
            } catch {
                return .error("\(error)")
            }
        }
    }
}
