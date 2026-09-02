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

    public init(argv: [String], cwd: String? = nil, extraEnvironment: [String: String] = [:],
                term: String = "xterm-256color", size: Size) throws {
        fatalError("TODO: PTY.init — spawn-owned")
    }

    /// Start delivering `onData` / `onExit`. Separate from init so the owner
    /// can wire the callbacks first.
    public func start() {
        fatalError("TODO")
    }

    public func write(_ bytes: Data) {
        fatalError("TODO")
    }

    public func resize(_ size: Size) {
        fatalError("TODO")
    }

    public func terminate() {
        fatalError("TODO")
    }

    public func kill() {
        fatalError("TODO")
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
