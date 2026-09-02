import Foundation
import Testing

@testable import CCCKit

/// Real children on a real pty. Every wait has a deadline that fails the
/// test instead of hanging the suite.
private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    private var status: Int32?
    private var exitCount = 0
    private let exited = DispatchSemaphore(value: 0)

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: bytes, as: UTF8.self)
    }

    var byteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return bytes.count
    }

    var exitDeliveries: Int {
        lock.lock()
        defer { lock.unlock() }
        return exitCount
    }

    func attach(to pty: PTY) {
        pty.onData = { [self] data in
            lock.lock()
            bytes.append(data)
            lock.unlock()
        }
        pty.onExit = { [self] code in
            lock.lock()
            exitCount += 1
            let first = status == nil
            if first { status = code }
            lock.unlock()
            if first { exited.signal() }
        }
    }

    /// The child's exit status, or nil if it did not exit in time.
    func waitForExit(seconds: Double = 5) -> Int32? {
        guard exited.wait(timeout: .now() + seconds) == .success else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return status
    }

    func waitForText(_ needle: String, seconds: Double = 5) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if text.contains(needle) { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return text.contains(needle)
    }
}

@Suite(.serialized)
struct PTYTests {
    private func makePTY(_ argv: [String], cols: Int = 80, rows: Int = 24,
                         cwd: String? = nil, env: [String: String] = [:],
                         term: String = "xterm-256color") throws -> (PTY, Collector) {
        let pty = try PTY(argv: argv, cwd: cwd, extraEnvironment: env, term: term,
                          size: PTY.Size(cols: cols, rows: rows))
        let collector = Collector()
        collector.attach(to: pty)
        return (pty, collector)
    }

    @Test("echo reaches onData and the child exits 0")
    func echo() throws {
        let (pty, collector) = try makePTY(["/bin/sh", "-c", "echo hello"])
        pty.start()
        let status = collector.waitForExit()
        #expect(status == 0)
        #expect(collector.text.contains("hello"))
        // The pty translates the newline on output.
        #expect(collector.text.contains("\r\n"))
        #expect(collector.exitDeliveries == 1)
    }

    @Test("the child sees the window size it was forked with")
    func initialWindowSize() throws {
        let (pty, collector) = try makePTY(["/bin/sh", "-c", "stty size"], cols: 132, rows: 43)
        pty.start()
        let status = collector.waitForExit()
        #expect(status == 0)
        #expect(collector.text.contains("43 132"))
    }

    @Test("resize lands before the child asks")
    func resize() throws {
        let (pty, collector) = try makePTY(["/bin/sh", "-c", "sleep 0.3; stty size"],
                                           cols: 80, rows: 24)
        pty.start()
        pty.resize(PTY.Size(cols: 100, rows: 30))
        let status = collector.waitForExit()
        #expect(status == 0)
        #expect(collector.text.contains("30 100"))
    }

    @Test("write reaches the child, terminate ends it")
    func writeAndTerminate() throws {
        let (pty, collector) = try makePTY(["/bin/cat"])
        pty.start()
        pty.write(Data("ping\r".utf8))
        #expect(collector.waitForText("ping", seconds: 3))
        pty.terminate()
        let status = collector.waitForExit(seconds: 3)
        // SIGHUP: 128 + 1. A cat that raced to a clean exit would be 0.
        #expect(status == 129)
        #expect(collector.exitDeliveries == 1)
    }

    @Test("TERM is overridden and extraEnvironment is merged")
    func environment() throws {
        let (pty, collector) = try makePTY(["/bin/sh", "-c", "echo $TERM $CCC_TEST"],
                                           env: ["CCC_TEST": "yes"])
        pty.start()
        let status = collector.waitForExit()
        #expect(status == 0)
        #expect(collector.text.contains("xterm-256color yes"))
    }

    @Test("cwd is honored")
    func workingDirectory() throws {
        let (pty, collector) = try makePTY(["/bin/sh", "-c", "pwd"], cwd: "/usr/lib")
        pty.start()
        let status = collector.waitForExit()
        #expect(status == 0)
        #expect(collector.text.contains("/usr/lib"))
    }

    @Test("a failed exec exits 127")
    func execFailure() throws {
        let (pty, collector) = try makePTY(["/nonexistent/binary"])
        pty.start()
        #expect(collector.waitForExit() == 127)
    }

    @Test("PATH is searched for a bare program name")
    func pathSearch() throws {
        let (pty, collector) = try makePTY(["sh", "-c", "echo onpath"])
        pty.start()
        #expect(collector.waitForExit() == 0)
        #expect(collector.text.contains("onpath"))
    }

    @Test("a long stream arrives whole")
    func throughput() throws {
        let (pty, collector) = try makePTY(["/bin/sh", "-c", "yes hello | head -30000"])
        pty.start()
        #expect(collector.waitForExit() == 0)
        // "hello\n" → "hello\r\n" on the way out: 7 bytes a line, none
        // dropped between the source's 64 KiB reads.
        #expect(collector.text.components(separatedBy: "hello").count - 1 == 30000)
        #expect(collector.byteCount >= 30000 * 7)
    }

    @Test("a write larger than the pty buffer drains without deadlocking")
    func largeWrite() throws {
        let (pty, collector) = try makePTY(["/bin/cat"])
        pty.start()
        // Lines, not one blob: the line discipline drops a canonical-mode
        // line past MAX_CANON. This is well past the master's buffer, so it
        // only completes if the writer drains the echo while it waits.
        var payload = ""
        for index in 0..<1500 {
            payload += "line\(index)-" + String(repeating: "x", count: 40) + "\r"
        }
        payload += "END\r"
        pty.write(Data(payload.utf8))
        #expect(collector.waitForText("END", seconds: 8))
        pty.terminate()
        _ = collector.waitForExit(seconds: 3)
    }

    @Test("empty argv throws before forking")
    func emptyArgv() {
        #expect(throws: PTY.Error.self) {
            _ = try PTY(argv: [], size: PTY.Size(cols: 80, rows: 24))
        }
    }
}
