import Foundation

/// One attached session: a PTY running `claude attach <id>` wired to a
/// `TerminalHost`. The window and `ccc attach --headless` both own exactly
/// one of these; the control socket drives it. Nothing here knows whether a
/// window exists.
@MainActor
public final class AttachSession {
    public let id: String
    public let host: TerminalHost
    private let pty: PTY
    private var throughput = Throughput()
    public private(set) var exitStatus: Int32?
    public var onExit: ((Int32) -> Void)?
    public let startedAt = Date()

    public struct Options: Sendable {
        public var cols: Int
        public var rows: Int
        public var cwd: String?
        public init(cols: Int = 120, rows: Int = 40, cwd: String? = nil) {
            self.cols = cols
            self.rows = rows
            self.cwd = cwd
        }
    }

    /// Spawns the child and starts pumping bytes. `argv` is normally
    /// `cli.attachArgv(id:)`; v2 prefixes `ssh -t host`.
    public init(id: String, argv: [String], host: TerminalHost, options: Options = Options()) throws {
        self.id = id
        self.host = host
        // A child session must never look like one of ours to the daemon
        // (experiment 1): strip the CLAUDE* markers this process may carry.
        var scrubbed: [String: String] = [:]
        for key in ProcessInfo.processInfo.environment.keys where key.hasPrefix("CLAUDE") {
            scrubbed[key] = ""
        }
        pty = try PTY(argv: argv, cwd: options.cwd, extraEnvironment: scrubbed,
                      size: .init(cols: options.cols, rows: options.rows))
        host.resize(cols: options.cols, rows: options.rows)
        host.onOutput = { [pty] data in pty.write(data) }
        pty.onData = { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.throughput.record(data.count)
                self.host.feed(data)
            }
        }
        pty.onExit = { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.exitStatus = status
                self.onExit?(status)
            }
        }
        pty.start()
    }

    public var isRunning: Bool { exitStatus == nil }
    public var childPID: pid_t { pty.pid }

    public func send(text: String) {
        pty.write(Data(text.utf8))
    }

    @discardableResult
    public func press(_ key: NamedKey) -> Bool {
        host.press(key)
    }

    /// Programmatic resize: grid and PTY together.
    public func resize(cols: Int, rows: Int) {
        host.resize(cols: cols, rows: rows)
        pty.resize(.init(cols: cols, rows: rows))
    }

    /// The view already changed its grid (window resize); only the child
    /// needs to hear about it.
    public func viewResized(cols: Int, rows: Int) {
        pty.resize(.init(cols: cols, rows: rows))
    }

    /// The documented detach gesture (docs/HARNESS.md): Ctrl+Z leaves the
    /// session running and ends the attach client. Falls back to SIGHUP if
    /// the child has not exited after `grace`.
    public func detach(grace: Duration = .seconds(3)) async {
        guard isRunning else { return }
        if !press(NamedKey("ctrl-z")!) {
            pty.write(Data([0x1a]))
        }
        let deadline = ContinuousClock.now + grace
        while isRunning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        if isRunning { pty.terminate() }
    }

    public func stats(pollState: RosterPoller.State?) -> StatsInfo {
        let me = getpid()
        return StatsInfo(
            pid: me,
            footprintBytes: ProcessStats.footprint(of: me) ?? 0,
            childPID: isRunning ? pty.pid : nil,
            childFootprintBytes: isRunning ? ProcessStats.footprint(of: pty.pid) : nil,
            lastPollMs: pollState?.lastPollMs,
            meanPollMs: pollState?.meanPollMs,
            pollCount: pollState?.pollCount ?? 0,
            ptyBytesIn: throughput.total,
            ptyBytesPerSecond: throughput.bytesPerSecond(),
            uptimeSeconds: Date().timeIntervalSince(startedAt)
        )
    }
}
