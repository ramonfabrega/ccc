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
    /// `CCC_CORE=ghostty` selects the v1 pane (libghostty-vt + our Metal
    /// renderer); the default stays SwiftTerm until the six checks are won.
    var makeHost: @MainActor (Int, Int) -> TerminalHost = { cols, rows in
        PaneController.makeDefaultHost(frame: CGRect(x: 0, y: 0, width: 8 * cols, height: 17 * rows))
    }

    static var selectedCore: String { ProcessInfo.processInfo.environment["CCC_CORE"] ?? "swiftterm" }

    static func makeDefaultHost(frame: CGRect) -> TerminalHost {
        selectedCore == "ghostty" ? GhosttyPane(frame: frame) : SwiftTermHost(frame: frame)
    }
    /// Sizes the window (or nothing, headless) wants the next attach to use.
    var defaultSize: (cols: Int, rows: Int) = (120, 40)
    /// The window's PNG, when there is a window.
    var peekProvider: (@MainActor () -> Data?)?
    /// show / hide / close, when there is a window. Returns false if unknown.
    var windowAction: (@MainActor (String) -> Bool)?

    init(cli: ClaudeCLI) {
        self.cli = cli
        self.poller = RosterPoller(cli: cli)
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

    func attach(id: String, cols: Int? = nil, rows: Int? = nil) throws {
        if let session, session.isRunning {
            throw AttachError.busy(session.id)
        }
        let size = (cols ?? defaultSize.cols, rows ?? defaultSize.rows)
        let host = makeHost(size.0, size.1)
        let session = try AttachSession(id: id, argv: cli.attachArgv(id: id), host: host,
                                        options: .init(cols: size.0, rows: size.1))
        session.onExit = { [weak self] status in
            guard let self else { return }
            self.poller.attachedID = nil
            self.onSessionEnded?(status)
        }
        self.session = session
        poller.attachedID = id
        onSessionStarted?(session)
    }

    func detach() async {
        guard let session, session.isRunning else { return }
        await session.detach()
    }

    enum AttachError: Error, CustomStringConvertible {
        case busy(String)
        case nothingAttached
        var description: String {
            switch self {
            case .busy(let id): return "already attached to \(id); detach first"
            case .nothingAttached: return "nothing attached"
            }
        }
    }

    // MARK: the socket → the same gestures

    func handle(_ request: ControlRequest) async -> ControlResponse {
        switch request {
        case .list:
            await poller.tick()
            return .list(poller.state.sorted)
        case .attach(let id):
            do {
                try attach(id: id)
                return .ok("attached \(id)")
            } catch {
                return .error("\(error)")
            }
        case .detach:
            guard let session, session.isRunning else { return .error(AttachError.nothingAttached.description) }
            await session.detach()
            return .ok("detached \(session.id)")
        case .snapshot:
            guard let session else { return .snapshot(SnapshotInfo(attachedTo: nil, grid: nil)) }
            return .snapshot(SnapshotInfo(attachedTo: session.isRunning ? session.id : nil, grid: session.host.snapshot()))
        case .send(let text, let keys):
            guard let session, session.isRunning else { return .error(AttachError.nothingAttached.description) }
            if let text { session.send(text: text) }
            for name in keys ?? [] {
                guard let key = NamedKey(name) else { return .error("unknown key '\(name)'") }
                guard session.press(key) else { return .error("host cannot encode '\(name)'") }
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
                                    ptyBytesIn: 0, ptyBytesPerSecond: 0, uptimeSeconds: 0))
        }
    }
}
