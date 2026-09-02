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
    /// Called when the attached child exits (detach or crash).
    var onSessionEnded: ((Int32) -> Void)?
    /// Called when a session is attached; the window mounts `host.view`.
    var onSessionStarted: ((AttachSession) -> Void)?
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

    /// The hosts ccc knows about, and why any were dropped. Loaded once at
    /// start: a host list that changes under a running attach would change
    /// what the pane is talking to.
    let hosts: HostConfig
    let hostIssues: [String]

    init(cli: ClaudeCLI, hosts: HostConfig.Loaded = HostConfig.load()) {
        self.cli = cli
        self.hosts = hosts.config
        self.hostIssues = hosts.issues
        self.poller = RosterPoller(cli: cli)
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
            self.onSessionEnded?(status)
        }
        self.session = session
        poller.attachedRef = ref
        onSessionStarted?(session)
    }

    func detach() async {
        guard let session, session.isRunning else { return }
        await session.detach()
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
                try attach(ref: ref)
                return .ok("attached \(ref)")
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
            if let session {
                return .stats(session.stats(pollState: poller.state))
            }
            let me = getpid()
            return .stats(StatsInfo(pid: me, footprintBytes: ProcessStats.footprint(of: me) ?? 0, childPID: nil,
                                    childFootprintBytes: nil, lastPollMs: poller.state.lastPollMs,
                                    meanPollMs: poller.state.meanPollMs, pollCount: poller.state.pollCount,
                                    modelJoin: poller.state.modelJoin,
                                    ptyBytesIn: 0, ptyBytesPerSecond: 0, uptimeSeconds: 0))
        }
    }
}
