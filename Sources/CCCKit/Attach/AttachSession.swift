import Foundation

/// One attached session: a PTY running `claude attach <id>` — or the same
/// command behind `ssh -t` — wired to a `TerminalHost`. The window and
/// `ccc attach --headless` both own exactly one of these; the control socket
/// drives it. Nothing here knows whether a window exists, and nothing here
/// knows whether the session is local: that is entirely in the `argv` it is
/// handed, which is what makes a remote pane the same object as a local one.
@MainActor
public final class AttachSession {
    public let ref: SessionRef
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

    /// Spawns the child and starts pumping bytes. `argv` is
    /// `cli.attachArgv(id:)` for the ref's host — local, or `ssh -t` and the
    /// same words.
    public init(ref: SessionRef, argv: [String], host: TerminalHost, options: Options = Options()) throws {
        self.ref = ref
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

    /// Paste through the host, which applies the framing the child
    /// negotiated (bracketed when mode 2004 is on). Never the PTY directly:
    /// `send(text:)` is raw typing, this is a paste.
    @discardableResult
    public func paste(_ text: String) -> Bool {
        host.paste(text)
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
            modelJoin: pollState?.modelJoin,
            hosts: pollState?.hosts.map(HostPollStats.init),
            ptyBytesIn: throughput.total,
            ptyBytesPerSecond: throughput.bytesPerSecond(),
            uptimeSeconds: Date().timeIntervalSince(startedAt)
        )
    }
}
