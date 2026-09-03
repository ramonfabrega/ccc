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
    /// show / hide / close, when there is a window. Returns false if unknown.
    var windowAction: (@MainActor (String) -> Bool)?
    /// The notifier's state, when there is one (the window face).
    var notificationStats: (@MainActor () -> NotificationStats?)?
    /// The window face's notifier taking a hook event (v3, slice 2);
    /// answers with what it did. `nil` headless.
    var hookSink: (@MainActor (HookEvent) -> String)?

    /// The hosts ccc knows about, and why any were dropped. Loaded once at
    /// start: a host list that changes under a running attach would change
    /// what the pane is talking to.
    let hosts: HostConfig
    let hostIssues: [String]

    /// The last attach and how it ended, for the wake-up reattach: a remote
    /// pane whose ssh died across a sleep comes back on its own.
    private var lastRef: SessionRef?
    private var lastExitStatus: Int32?
    private var wokeAt: ContinuousClock.Instant?
    /// The window face remembers what it was attached to across a relaunch
    /// (Sparkle's, or the user's) in UserDefaults; the headless face never
    /// does, or an agent's attach would steer the next window launch.
    var remembersAttach = false
    private static let rememberedRefKey = "ccc.lastAttachedRef"

    init(cli: ClaudeCLI, hosts: HostConfig.Loaded = HostConfig.load()) {
        self.cli = cli
        self.hosts = hosts.config
        self.hostIssues = hosts.issues
        // One poller per host, `local` reading through this process's own
        // resolved `claude` (the config's `local` has no path of its own).
        self.poller = RosterPoller(pollers: hosts.config.hosts.map { host in
            HostPoller(cli: host.isLocal ? cli : ClaudeCLI.of(host), hostName: host.name)
        })
    }

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
        server?.stop()
        server = nil
    }

    // MARK: gestures

    func attach(ref: SessionRef, cols: Int? = nil, rows: Int? = nil) throws {
        if let session, session.isRunning {
            throw AttachError.busy(session.ref)
        }
        let cli = try cli(for: ref)
        // The master socket's directory must exist before ssh is exec'd:
        // the PTY child has no way to report a mkdir failure back to us.
        try cli.prepareControlDirectory()
        let size = (cols ?? defaultSize.cols, rows ?? defaultSize.rows)
        let host = makeHost(size.0, size.1)
        let session = try AttachSession(ref: ref, argv: cli.attachArgv(id: ref.id), host: host,
                                        options: .init(cols: size.0, rows: size.1))
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
        onSessionStarted?(session)
    }

    /// The click's attach (v6, the same night as the shell pane): the
    /// pane follows the click. Nothing attached: attach. The same ref:
    /// nothing to do. Another ref: leave it — Ctrl+Z, the harness's own
    /// detach, which keeps the session and its draft — and attach the
    /// new one. The "busy" refusal was v0's guard, and every gesture that
    /// met it (⇧⌘N's attach-when-started, a second row's ⏎) had to work
    /// around it. Returns the sentence.
    func switchTo(ref: SessionRef, cols: Int? = nil, rows: Int? = nil) async throws -> String {
        if let session, session.isRunning {
            if session.ref == ref { return "already attached to \(ref)" }
            let previous = session.ref
            await session.detach()
            try attach(ref: ref, cols: cols, rows: rows)
            return "attached \(ref) (left \(previous))"
        }
        try attach(ref: ref, cols: cols, rows: rows)
        return "attached \(ref)"
    }

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

    /// "Ask the session" (v6 slice 6): a prompt through the pane. Attach
    /// (the pane follows the click, so a session on screen is left), wait
    /// for the TUI to draw when the attach was fresh, type the prompt,
    /// press Enter. The TUI queues a prompt typed while it is working, so
    /// a busy session is asked too — it reads it when it is done.
    func ask(_ ref: SessionRef, prompt: String) async throws -> String {
        let wasOnScreen = session?.isRunning == true && session?.ref == ref
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

    /// The grid has something on it and has stopped changing — two reads
    /// half a second apart agree — or eight seconds passed. A fresh
    /// `claude attach` draws its TUI in well under that; over ssh, a
    /// little later. Bytes typed before it is up would land in the
    /// harness's attach client, not the prompt box.
    private static func waitUntilDrawn(_ session: AttachSession, timeout: Duration = .seconds(8)) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        var previous: Grid?
        while clock.now < deadline, session.isRunning {
            try? await Task.sleep(for: .milliseconds(250))
            let grid = session.host.snapshot()
            let drawn = grid.lines.contains { !$0.allSatisfy(\.isWhitespace) }
            if drawn, let previous, previous == grid { return }
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
        // The repository's main checkout (`atRepo`): git's answer when the
        // row has one, the harness's path convention otherwise.
        let folder = atRepo ? (row.worktree?.repo ?? RepoPath.root(of: row.session.cwd)) : row.session.cwd
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
        return ("shell in \(hosts.shortCwd(folder, host: ref.host))" + (ref.isLocal ? "" : " on \(ref.host)"), true)
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
        let polls = await poller.reconnect(host: host)
        // Already dead when we woke: ssh noticed before we did.
        if let lastRef, session?.isRunning != true, lastExitStatus == Self.sshExit, lastRef.host != Host.localName,
           host == nil || host == lastRef.host {
            try? attach(ref: lastRef)
        }
        return polls
    }

    /// ssh's own exit status; `claude attach` ending by Ctrl+Z exits 0 and
    /// must never be re-run behind the user's back.
    private static let sshExit: Int32 = 255

    /// A remote attach that exits with ssh's status within a short window
    /// after wake is the sleep's doing, not the user's: run the same argv
    /// again. The draft lives with the session (experiment 5), so nothing
    /// typed is lost.
    private func reattachIfSleepKilledIt(ref: SessionRef, status: Int32) {
        guard status == Self.sshExit, ref.host != Host.localName,
              let wokeAt, wokeAt.duration(to: .now) < .seconds(20) else { return }
        try? attach(ref: ref)
    }

    enum AttachError: Error, CustomStringConvertible {
        case busy(SessionRef)
        case nothingAttached
        case unknownHost(String, known: [String])
        case badHost(String)
        var description: String {
            switch self {
            case .busy(let ref): return "already attached to \(ref); detach first"
            case .nothingAttached: return "nothing attached"
            case .unknownHost(let name, let known):
                return "unknown host '\(name)' (known: \(known.joined(separator: ", "))); add it with `ccc hosts add`"
            case .badHost(let problem): return problem
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
        case .snapshot:
            guard let session else { return .snapshot(SnapshotInfo(attachedTo: nil, grid: nil)) }
            return .snapshot(SnapshotInfo(attachedTo: session.isRunning ? session.ref : nil, grid: session.host.snapshot()))
        case .send(let text, let keys, let wheel, let paste):
            guard let session, session.isRunning else { return .error(AttachError.nothingAttached.description) }
            if let text { session.send(text: text) }
            if let paste {
                guard session.paste(paste) else { return .error("host cannot paste (\(PaneController.selectedCore) core)") }
            }
            for name in keys ?? [] {
                guard let key = NamedKey(name) else { return .error("unknown key '\(name)'") }
                guard session.press(key) else { return .error("host cannot encode '\(name)'") }
            }
            if let wheel, wheel != 0 {
                guard let pane = session.host as? GhosttyPane else { return .error("wheel needs the ghostty pane; this session is on the \(PaneController.selectedCore) core") }
                pane.wheel(lines: wheel)
            }
            return .ok("sent")
        case .resize(let cols, let rows):
            guard let session, session.isRunning else { return .error(AttachError.nothingAttached.description) }
            session.resize(cols: cols, rows: rows)
            return .ok("resized to \(cols)x\(rows)")
        case .peek:
            guard let peekProvider, let png = peekProvider() else { return .error("no window to peek (headless)") }
            return .peek(png: png)
        case .window(let action):
            guard let windowAction else { return .error("no window (headless)") }
            return windowAction(action) ? .ok("window \(action)") : .error("unknown window action '\(action)' (show|hide|close)")
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
                                  modelJoin: state.modelJoin, hosts: state.hosts.map(HostPollStats.init),
                                  ptyBytesIn: 0, ptyBytesPerSecond: 0, uptimeSeconds: 0)
            }
            stats.notifications = notificationStats?()
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
