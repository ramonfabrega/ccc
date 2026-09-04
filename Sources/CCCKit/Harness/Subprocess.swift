import Foundation

/// One child process, run to completion without parking a thread on it.
///
/// `ClaudeCLI.run` used to read both pipes with `readDataToEndOfFile` and
/// then `waitUntilExit` — three blocking calls inside an `async` function,
/// which is a cooperative-pool thread held for the whole ssh round trip.
/// At two hosts that is invisible; at a 5 s `ConnectTimeout` against a
/// sleeping Mac it is a pool thread gone for five seconds per host per
/// tick (docs/QUEUE.md item 4). Here the pipes are drained by `DispatchIO`
/// and the exit arrives through `terminationHandler`, so the awaiting task
/// is suspended, not blocked, and cancelling it terminates the child.
public enum Subprocess {
    public struct Output: Sendable {
        public var stdout: Data
        public var stderr: Data
        public var status: Int32
    }

    /// Run `argv` to completion. stdin is `/dev/null`: nothing here ever
    /// answers a prompt, and a child that asks must fail rather than wait.
    /// A cancelled task sends the child SIGTERM and throws
    /// `CancellationError` once it has gone.
    public static func run(_ argv: [String],
                           cwd: String? = nil,
                           environment: [String: String]? = nil) async throws -> Output {
        precondition(!argv.isEmpty, "Subprocess.run needs a program")
        let process = Process()
        process.executableURL = URL(filePath: argv[0])
        process.arguments = Array(argv.dropFirst())
        if let cwd { process.currentDirectoryURL = URL(filePath: cwd) }
        if let environment { process.environment = environment }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        // Armed before `run`, so an exit that lands before anyone awaits
        // is not lost: `terminationHandler` fires exactly once, whenever
        // the child goes, and the signal remembers it.
        let exited = ExitSignal()
        process.terminationHandler = { _ in exited.fire() }
        try process.run()
        // `Process` closes the parent's copy of each write end once the
        // child holds it, which is what lets EOF reach the drains — the
        // same fact the blocking `readDataToEndOfFile` relied on.
        let outHandle = out.fileHandleForReading
        let errHandle = err.fileHandleForReading
        return try await withTaskCancellationHandler {
            // Both pipes drain concurrently: a child that fills stderr
            // while stdout is being read must not deadlock (the rule the
            // blocking version learned the hard way).
            async let stdout = drain(outHandle)
            async let stderr = drain(errHandle)
            let (o, e) = await (stdout, stderr)
            await exited.wait()
            try Task.checkCancellation()
            return Output(stdout: o, stderr: e, status: process.terminationStatus)
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// Everything the handle will ever deliver, read as it arrives. The
    /// handle stays open: the `Pipe` owns the descriptor and closes it.
    static func drain(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "ccc.subprocess.drain")
            let io = DispatchIO(type: .stream, fileDescriptor: handle.fileDescriptor, queue: queue) { _ in }
            // Deliver whatever is there rather than waiting for a full
            // buffer; the roster is small and the caller wants it now.
            io.setLimit(lowWater: 1)
            let collected = Collected()
            io.read(offset: 0, length: .max, queue: queue) { done, chunk, _ in
                if let chunk, !chunk.isEmpty { collected.append(chunk) }
                if done {
                    io.close()
                    continuation.resume(returning: collected.data)
                }
            }
        }
    }

    /// The bytes one drain has seen. Touched only on the drain's own
    /// serial queue, which is what makes the unchecked mark true.
    private final class Collected: @unchecked Sendable {
        var data = Data()
        func append(_ chunk: DispatchData) {
            for region in chunk.regions {
                region.withUnsafeBytes { data.append(contentsOf: $0) }
            }
        }
    }

    /// A one-shot flag that can be awaited from before or after it fires.
    final class ExitSignal: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false
        private var waiter: CheckedContinuation<Void, Never>?

        func fire() {
            lock.lock()
            fired = true
            let resume = waiter
            waiter = nil
            lock.unlock()
            resume?.resume()
        }

        func wait() async {
            await withCheckedContinuation { continuation in
                lock.lock()
                if fired {
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiter = continuation
                    lock.unlock()
                }
            }
        }
    }
}
