import Foundation

/// The agent-legible surface: newline-delimited JSON over a unix socket, one
/// request per connection, the server replies and closes (scry's pattern).
/// Whoever holds a PTY serves it — the GUI app or a headless `ccc attach`.
/// Attach is exclusive at the daemon, so this is the only way a second
/// process (an agent, a test, the CLI) can see what the pane shows.
public enum ControlRequest: Codable, Sendable {
    /// The roster as the server last polled it, with model column.
    case list
    /// Attach the pane to a session (the click's twin).
    case attach(id: String)
    /// Detach the pane from its session by ending the child process the way
    /// the harness documents (Ctrl+Z is the default; see `DetachGesture`).
    case detach
    /// The pane's grid as text. `nil` session when nothing is attached.
    case snapshot
    /// Bytes to the child: `text` is UTF-8 as typed; `keys` are named keys
    /// (`enter`, `escape`, `ctrl-c`, `ctrl-z`, `up`, `shift-enter`, …) that
    /// the terminal host encodes — never hand-rolled escape sequences.
    /// `wheel`: scroll lines (positive = up) through the host's mouse path.
    case send(text: String?, keys: [String]?, wheel: Int? = nil)
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
}

public enum ControlResponse: Codable, Sendable {
    case list([SessionRow])
    case snapshot(SnapshotInfo)
    case stats(StatsInfo)
    case peek(png: Data)
    case ok(String)
    case error(String)
}

/// One roster row as ccc shows it: the harness's session plus what ccc adds
/// (the model that is actually serving it).
public struct SessionRow: Codable, Sendable, Equatable {
    public var session: Session
    public var model: String?
    public var attached: Bool
    public init(session: Session, model: String?, attached: Bool) {
        self.session = session
        self.model = model
        self.attached = attached
    }
}

public struct SnapshotInfo: Codable, Sendable {
    public var attachedTo: String?
    public var grid: Grid?
    public init(attachedTo: String?, grid: Grid?) {
        self.attachedTo = attachedTo
        self.grid = grid
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
    /// Bytes fed to the terminal since attach, and the rate over the last second.
    public var ptyBytesIn: UInt64
    public var ptyBytesPerSecond: Double
    public var uptimeSeconds: Double

    public init(pid: Int32, footprintBytes: UInt64, childPID: Int32?, childFootprintBytes: UInt64?,
                lastPollMs: Double?, meanPollMs: Double?, pollCount: Int,
                ptyBytesIn: UInt64, ptyBytesPerSecond: Double, uptimeSeconds: Double) {
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
