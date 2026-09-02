import Darwin
import Foundation

/// Our PTY (docs/TERMINAL.md "PTY: ours, forkpty over Darwin"). The master
/// fd is what we read and write; resize is one ioctl; the child is
/// `claude attach <id>` (v2: `ssh -t <host> claude attach <id>`).
///
/// Contract:
/// - `init` calls `forkpty` with the given window size, then in the child
///   sets the environment (inherit ours, override `TERM`, add `extra`),
///   chdir to `cwd` if given, and `execvp`s `argv[0]` with `argv`. If exec
///   fails the child `_exit(127)`.
/// - The master fd is set non-blocking? No: it is read on a dedicated
///   `DispatchSource.makeReadSource` on a background queue; each readable
///   event reads up to 64 KiB and delivers `Data` to `onData` on that queue.
///   The owner hops to the main actor itself. EOF or EIO (child gone) →
///   `onExit(status)` once, after `waitpid`.
/// - `write` appends to the master fd, handling partial writes and EAGAIN
///   by retrying (a pending-write queue is acceptable).
/// - `resize` = `ioctl(master, TIOCSWINSZ, &winsize)`; the kernel sends
///   SIGWINCH to the child.
/// - `terminate()` sends SIGHUP to the child process group; `kill()` sends
///   SIGKILL. Deinit closes the master and reaps the child if needed.
/// - Nothing here knows about terminals or sessions; it moves bytes.
public final class PTY: @unchecked Sendable {
    public let pid: pid_t
    public let masterFD: Int32

    /// Wire these before `start()`; `start()` captures them.
    public var onData: ((Data) -> Void)?
    public var onExit: ((Int32) -> Void)?

    public struct Size: Sendable, Equatable {
        public var cols: Int
        public var rows: Int
        public init(cols: Int, rows: Int) {
            self.cols = cols
            self.rows = rows
        }
    }

    /// One private serial queue owns both directions, so a `write` issued
    /// after a `read` is ordered against it and the exit delivery.
    private let queue = DispatchQueue(label: "app.ccc.pty", qos: .utility)
    private let lock = NSLock()

    /// All of these are guarded by `lock`.
    private var source: DispatchSourceRead?
    private var dataHandler: ((Data) -> Void)?
    private var exitHandler: ((Int32) -> Void)?
    private var started = false
    private var finished = false
    private var reaped = false
    private var fdClosed = false

    /// Read scratch, touched only on `queue`.
    private let readBuffer = UnsafeMutableRawPointer.allocate(byteCount: 64 * 1024, alignment: 16)
    private static let readCapacity = 64 * 1024

    // MARK: - Spawn

    public init(argv: [String], cwd: String? = nil, extraEnvironment: [String: String] = [:],
                term: String = "xterm-256color", size: Size) throws {
        // Everything that can fail is resolved before the stored properties
        // are assigned: a class initializer may not throw while properties
        // are still uninitialized.
        let outcome = PTY.spawn(argv: argv, cwd: cwd, extraEnvironment: extraEnvironment,
                                term: term, size: size)
        self.pid = outcome.pid
        self.masterFD = outcome.fd
        if let error = outcome.error { throw error }
        // Non-blocking master: the read source hands us readability, and a
        // partial write must never park the serial queue in the kernel.
        let flags = fcntl(masterFD, F_GETFL, 0)
        if flags >= 0 { _ = fcntl(masterFD, F_SETFL, flags | O_NONBLOCK) }
    }

    private struct Spawned {
        var pid: pid_t = -1
        var fd: Int32 = -1
        var error: PTY.Error?
    }

    private static func spawn(argv: [String], cwd: String?, extraEnvironment: [String: String],
                              term: String, size: Size) -> Spawned {
        guard let program = argv.first, !program.isEmpty else {
            return Spawned(error: .emptyArgv)
        }

        // Everything the child touches between fork and exec is a raw C
        // buffer built here, in the parent: no Swift allocation, no ARC, no
        // locks on the far side of the fork.
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = term
        for (key, value) in extraEnvironment { environment[key] = value }

        let argvC = makeCArray(argv)
        let envC = makeCArray(environment.map { "\($0.key)=\($0.value)" })
        // `execvp` would search PATH but only against the process-global
        // `environ`, which the Swift overlay exposes read-only (there is no
        // `_NSGetEnviron`, and mutating it after fork is the only way to
        // hand `execvp` our env). So the PATH search happens here, in the
        // parent, and the child `execve`s the candidates in order — same
        // semantics, and nothing on the far side of the fork allocates.
        let candidatesC = makeCArray(PTY.executableCandidates(for: program, in: environment))
        let cwdC = cwd.map { strdup($0) } ?? nil

        defer {
            freeCArray(argvC)
            freeCArray(envC)
            freeCArray(candidatesC)
            if let cwdC { free(cwdC) }
        }

        var emptyMask = sigset_t()
        sigemptyset(&emptyMask)

        var ws = winsize(ws_row: UInt16(clamping: size.rows), ws_col: UInt16(clamping: size.cols),
                         ws_xpixel: 0, ws_ypixel: 0)
        var master: Int32 = -1
        let child = forkpty(&master, nil, nil, &ws)

        if child < 0 {
            return Spawned(error: .forkptyFailed(errno: errno))
        }
        if child == 0 {
            // ---- child: async-signal-safe calls only ----
            // SIG_IGN dispositions and a blocked mask survive exec, so a host
            // that ignores SIGHUP (swift-testing's runner does) would hand the
            // child immunity to `terminate()`. Hand it a clean slate.
            sigprocmask(SIG_SETMASK, &emptyMask, nil)
            var signalNumber: Int32 = 1
            while signalNumber < 32 {
                signal(signalNumber, SIG_DFL)
                signalNumber += 1
            }
            if let cwdC { _ = chdir(cwdC) }
            var index = 0
            while let candidate = candidatesC[index] {
                execve(candidate, argvC, envC)
                index += 1
            }
            _exit(127)
        }
        return Spawned(pid: child, fd: master, error: nil)
    }

    /// `execvp`'s PATH search, done in the parent: an absolute or relative
    /// path is used as-is, a bare name is expanded against the environment
    /// the child will actually run with.
    static func executableCandidates(for program: String, in environment: [String: String]) -> [String] {
        guard !program.contains("/") else { return [program] }
        let path = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        return path.split(separator: ":", omittingEmptySubsequences: false).map { directory in
            (directory.isEmpty ? "." : String(directory)) + "/" + program
        }
    }

    /// A NULL-terminated `char *[]`, each element `strdup`'d.
    private static func makeCArray(_ values: [String]) -> UnsafeMutablePointer<UnsafeMutablePointer<CChar>?> {
        let array = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: values.count + 1)
        for (index, value) in values.enumerated() { array[index] = strdup(value) }
        array[values.count] = nil
        return array
    }

    private static func freeCArray(_ array: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) {
        var index = 0
        while let element = array[index] {
            free(element)
            index += 1
        }
        array.deallocate()
    }

    // MARK: - Lifecycle

    /// Start delivering `onData` / `onExit`. Separate from init so the owner
    /// can wire the callbacks first.
    public func start() {
        lock.lock()
        if started || masterFD < 0 {
            lock.unlock()
            return
        }
        started = true
        dataHandler = onData
        exitHandler = onExit
        let readSource = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: queue)
        source = readSource
        lock.unlock()

        readSource.setEventHandler { [weak self] in self?.readable() }
        // Only the cancel handler closes the master, and it captures the fd
        // by value so it stays correct if `self` is already gone.
        let fd = masterFD
        readSource.setCancelHandler { [weak self] in
            if let self {
                self.lock.lock()
                let alreadyClosed = self.fdClosed
                self.fdClosed = true
                self.lock.unlock()
                if alreadyClosed { return }
            }
            Darwin.close(fd)
        }
        readSource.resume()
    }

    private func readable() {
        // A false drain means 0 (EOF) or EIO / any hard error: the child's
        // side of the pty is gone. Cancel, reap, report once.
        if !drainOnce() { finish() }
    }

    /// One read of up to 64 KiB, delivered to `onData`. Returns false when
    /// the child's end of the pty is gone. Queue-confined.
    private func drainOnce() -> Bool {
        var count = 0
        repeat {
            count = Darwin.read(masterFD, readBuffer, PTY.readCapacity)
        } while count < 0 && errno == EINTR

        if count > 0 {
            let data = Data(bytes: readBuffer, count: count)
            lock.lock()
            let handler = dataHandler
            lock.unlock()
            handler?(data)
            return true
        }
        if count < 0 {
            let code = errno
            // Nothing pending: wait for the next readable event.
            if code == EAGAIN || code == EWOULDBLOCK { return true }
        }
        return false
    }

    private func finish() {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        let readSource = source
        let handler = exitHandler
        lock.unlock()

        readSource?.cancel()
        let status = reap()
        handler?(status)
    }

    /// Reap the child, safe to call more than once: after the first reap it
    /// returns the cached status. Polls rather than blocking, because EIO on
    /// the master does not strictly prove the child is gone (it may have
    /// closed its tty fds and kept running) and parking the serial queue in
    /// `waitpid` would stall the read side forever. After the grace period
    /// the child is unreachable anyway, so it gets SIGKILL.
    private func reap() -> Int32 {
        lock.lock()
        if reaped {
            lock.unlock()
            return cachedExitStatus
        }
        lock.unlock()

        guard pid > 0 else { return 0 }
        var raw: Int32 = 0
        var result: pid_t = 0
        var waitedMilliseconds = 0
        while true {
            result = waitpid(pid, &raw, WNOHANG)
            if result == pid { break }
            if result < 0 && errno == EINTR { continue }
            if result < 0 { break }   // ECHILD: someone else reaped it
            if waitedMilliseconds >= 2000 {
                _ = Darwin.kill(pid, SIGKILL)
                repeat {
                    result = waitpid(pid, &raw, 0)
                } while result < 0 && errno == EINTR
                break
            }
            usleep(1000)
            waitedMilliseconds += 1
        }

        let status = result == pid ? PTY.exitCode(fromWaitStatus: raw) : 0
        lock.lock()
        reaped = true
        cachedExitStatus = status
        lock.unlock()
        return status
    }

    private var cachedExitStatus: Int32 = 0

    /// `WIFEXITED`/`WEXITSTATUS`/`WIFSIGNALED`/`WTERMSIG` by hand: they are
    /// function-like macros and Swift does not import them.
    static func exitCode(fromWaitStatus raw: Int32) -> Int32 {
        let low = raw & 0o177
        if low == 0 { return (raw >> 8) & 0xFF }        // exited normally
        if low == 0o177 { return 128 + ((raw >> 8) & 0xFF) }  // stopped
        return 128 + low                                 // killed by signal
    }

    // MARK: - IO

    public func write(_ bytes: Data) {
        guard !bytes.isEmpty else { return }
        queue.async { [weak self] in self?.writeNow(bytes) }
    }

    /// Serial-queue side of `write`: loops over partial writes and waits for
    /// POLLOUT on EAGAIN. While it waits it also drains the read side —
    /// reads and writes share this queue for ordering, and a child that
    /// echoes what we send (every shell does) fills the master's output
    /// buffer, stops reading its input, and deadlocks a writer that is not
    /// simultaneously reading. Bounded by a deadline so a child that has
    /// genuinely stopped reading cannot park the queue forever.
    private func writeNow(_ bytes: Data) {
        lock.lock()
        let closed = fdClosed || finished
        lock.unlock()
        if closed { return }

        let deadline = Date().addingTimeInterval(5)
        var childGone = false
        bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(masterFD, base + offset, raw.count - offset)
                if written > 0 {
                    offset += written
                    continue
                }
                let code = errno
                if code == EINTR { continue }
                if code == EAGAIN || code == EWOULDBLOCK {
                    if Date() >= deadline { return }
                    var pfd = pollfd(fd: masterFD, events: Int16(POLLOUT | POLLIN), revents: 0)
                    _ = poll(&pfd, 1, 100)
                    if pfd.revents & Int16(POLLIN) != 0, !drainOnce() {
                        childGone = true
                        return
                    }
                    continue
                }
                childGone = true  // EIO / EBADF: the child is gone.
                return
            }
        }
        if childGone { finish() }
    }

    public func resize(_ size: Size) {
        lock.lock()
        let closed = fdClosed
        lock.unlock()
        guard !closed, masterFD >= 0 else { return }
        var ws = winsize(ws_row: UInt16(clamping: size.rows), ws_col: UInt16(clamping: size.cols),
                         ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &ws)
    }

    // MARK: - Signals

    public func terminate() {
        signalChild(SIGHUP)
    }

    public func kill() {
        signalChild(SIGKILL)
    }

    /// forkpty's child is a session leader, so its process group is its pid;
    /// signal the group so `sh -c` children go too, and fall back to the
    /// bare pid if the group is already gone.
    private func signalChild(_ signal: Int32) {
        guard pid > 0 else { return }
        lock.lock()
        let done = reaped
        lock.unlock()
        guard !done else { return }
        if Darwin.kill(-pid, signal) != 0 {
            _ = Darwin.kill(pid, signal)
        }
    }

    // MARK: - Teardown

    deinit {
        lock.lock()
        let readSource = source
        let alreadyClosed = fdClosed
        let alreadyReaped = reaped
        lock.unlock()

        if let readSource {
            readSource.cancel()   // the cancel handler closes the master
        } else if !alreadyClosed, masterFD >= 0 {
            Darwin.close(masterFD)
        }

        if !alreadyReaped, pid > 0 {
            var raw: Int32 = 0
            var result: pid_t = 0
            repeat {
                result = waitpid(pid, &raw, WNOHANG)
            } while result < 0 && errno == EINTR
            if result == 0 {
                // Still running: only then is it safe to signal this pid.
                _ = Darwin.kill(pid, SIGKILL)
                repeat {
                    result = waitpid(pid, &raw, 0)
                } while result < 0 && errno == EINTR
            }
        }

        readBuffer.deallocate()
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case forkptyFailed(errno: Int32)
        case emptyArgv
        public var description: String {
            switch self {
            case .forkptyFailed(let e): return "forkpty failed: \(String(cString: strerror(e)))"
            case .emptyArgv: return "argv is empty"
            }
        }
    }
}
