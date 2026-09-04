import Foundation
import Testing

@testable import CCCKit

/// `Subprocess.run` is what every poll, probe and remote verb goes through
/// (item 4). Three things it must do that the blocking version could not
/// be trusted to: not deadlock on a child that fills both pipes, not park
/// a thread per child, and stop the child when its task is cancelled.
@Suite struct SubprocessTests {
    @Test func capturesBothStreamsAndTheStatus() async throws {
        let out = try await Subprocess.run(["/bin/sh", "-c", "printf out; printf err >&2; exit 3"])
        #expect(String(decoding: out.stdout, as: UTF8.self) == "out")
        #expect(String(decoding: out.stderr, as: UTF8.self) == "err")
        #expect(out.status == 3)
    }

    /// A pipe holds 64 KiB; a child writing more than that to *both* pipes
    /// blocks unless both are drained at once. 300 KB each, byte-exact.
    @Test func drainsBothPipesPastThePipeBuffer() async throws {
        let n = 300_000
        let script = "head -c \(n) /dev/zero | tr '\\0' a; head -c \(n) /dev/zero | tr '\\0' b >&2"
        let out = try await Subprocess.run(["/bin/sh", "-c", script])
        #expect(out.status == 0)
        #expect(out.stdout.count == n)
        #expect(out.stderr.count == n)
        #expect(out.stdout.allSatisfy { $0 == UInt8(ascii: "a") })
        #expect(out.stderr.allSatisfy { $0 == UInt8(ascii: "b") })
    }

    /// Thirty-two children sleeping 300 ms each, awaited concurrently. A
    /// runner that blocks a cooperative-pool thread per child serialises
    /// them in rounds of `ncpu` and takes over a second; one that suspends
    /// finishes in about one sleep.
    @Test func doesNotParkAThreadPerChild() async throws {
        let started = ContinuousClock.now
        try await withThrowingTaskGroup(of: Int32.self) { group in
            for _ in 0..<32 {
                group.addTask { try await Subprocess.run(["/bin/sleep", "0.3"]).status }
            }
            for try await status in group { #expect(status == 0) }
        }
        let elapsed = started.duration(to: .now)
        #expect(elapsed < .seconds(1), "32 concurrent 300 ms sleeps took \(elapsed)")
    }

    /// Cancelling the awaiting task ends the child: a `ccc list` that gives
    /// up on a host must not leave its ssh behind.
    @Test func cancellationTerminatesTheChild() async throws {
        let task = Task { try await Subprocess.run(["/bin/sleep", "30"]) }
        try await Task.sleep(for: .milliseconds(100))
        let started = ContinuousClock.now
        task.cancel()
        let result = await task.result
        #expect(started.duration(to: .now) < .seconds(2))
        switch result {
        case .success(let out):
            Issue.record("expected cancellation, got exit \(out.status)")
        case .failure(let error):
            #expect(error is CancellationError)
        }
    }

    /// A child that has already exited before anyone awaits it is still
    /// reported: the exit signal is armed before `run`, and remembers.
    @Test func anExitBeforeTheAwaitIsNotLost() async throws {
        for _ in 0..<20 {
            let out = try await Subprocess.run(["/usr/bin/true"])
            #expect(out.status == 0)
        }
    }
}
