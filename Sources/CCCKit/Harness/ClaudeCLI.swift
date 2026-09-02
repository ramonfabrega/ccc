import Foundation

/// Where the harness is and how ccc invokes it. ccc reads the roster, spawns
/// (v5), and attaches — nothing else (CLAUDE.md hard constraints). Every
/// invocation is the documented `claude` command; no daemon files are read
/// in v0.
public struct ClaudeCLI: Sendable {
    /// Absolute path of the `claude` executable.
    public var executable: String

    public init(executable: String) {
        self.executable = executable
    }

    /// Resolve `claude` the way a shell would (PATH), then the launcher's
    /// default location. A GUI app launched by LaunchServices has a minimal
    /// PATH, so the fallback matters.
    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) -> ClaudeCLI? {
        if let override = environment["CCC_CLAUDE"], !override.isEmpty {
            return ClaudeCLI(executable: override)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates: [String] = []
        for dir in (environment["PATH"] ?? "").split(separator: ":") {
            candidates.append("\(dir)/claude")
        }
        candidates += ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return ClaudeCLI(executable: path)
        }
        return nil
    }

    /// `claude agents --json --all`, raw bytes. Throws on a non-zero exit
    /// with stderr in the error; decoding is the caller's job.
    public func agentsJSON(all: Bool = true) async throws -> Data {
        var args = ["agents", "--json"]
        if all { args.append("--all") }
        return try await run(args)
    }

    /// The argv for attaching. The PTY execs this; v2 prefixes `ssh -t host`.
    public func attachArgv(id: String) -> [String] {
        [executable, "attach", id]
    }

    public struct RunError: Error, CustomStringConvertible {
        public var status: Int32
        public var stderr: String
        public var description: String { "claude exited \(status): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))" }
    }

    private func run(_ arguments: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()
        // Read both pipes to EOF before waiting, or a full pipe deadlocks.
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RunError(status: process.terminationStatus, stderr: String(decoding: stderr, as: UTF8.self))
        }
        return stdout
    }
}
