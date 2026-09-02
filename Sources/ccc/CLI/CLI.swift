import CCCKit
import Foundation

/// The command face. Each verb is a click's twin.
///
///   ccc list [--json]                 the roster, with the model column
///   ccc attach <id> [--headless]      attach; headless drives a PTY and serves the socket
///   ccc snapshot [--json]             the pane's grid as text
///   ccc send <text> | --key <name>…   type into the pane
///   ccc detach                        detach the pane
///   ccc stats [--json]                memory, poll latency, PTY throughput
///   ccc replay <bytes> [--cols N --rows N]   render recorded bytes headlessly
@MainActor
enum CLI {
    static func run(_ arguments: [String]) async -> Int32 {
        var args = arguments
        let json = args.contains("--json")
        args.removeAll { $0 == "--json" }
        guard let verb = args.first else { return usage() }
        let rest = Array(args.dropFirst())
        do {
            switch verb {
            case "help", "--help", "-h":
                return usage(to: .standardOutput, status: 0)
            case "list":
                return try await list(json: json)
            case "attach":
                guard let id = rest.first(where: { !$0.hasPrefix("--") }) else { return usage() }
                if rest.contains("--headless") {
                    return Headless.run(id: id, cols: intFlag("--cols", rest) ?? 120, rows: intFlag("--rows", rest) ?? 40)
                }
                return try request(.attach(id: id), json: json)
            case "snapshot":
                return try request(.snapshot, json: json)
            case "send":
                return try send(rest, json: json)
            case "detach":
                return try request(.detach, json: json)
            case "resize":
                guard let cols = rest.first.flatMap({ Int($0) }), let rows = rest.dropFirst().first.flatMap({ Int($0) }) else { return usage() }
                return try request(.resize(cols: cols, rows: rows), json: json)
            case "stats":
                return try request(.stats, json: json)
            case "peek":
                return try peek(to: rest.first(where: { !$0.hasPrefix("--") }))
            case "bench":
                guard let path = rest.first(where: { !$0.hasPrefix("--") }) else { return usage() }
                return try await bench(path: path, cols: intFlag("--cols", rest) ?? 100, rows: intFlag("--rows", rest) ?? 30,
                                       repeats: intFlag("--repeat", rest) ?? 200, core: stringFlag("--core", rest), json: json)
            case "window":
                guard let action = rest.first, ["show", "hide", "close"].contains(action) else { return usage() }
                return try request(.window(action: action), json: json)
            case "replay":
                guard let path = rest.first(where: { !$0.hasPrefix("--") }) else { return usage() }
                return try await replay(path: path, cols: intFlag("--cols", rest) ?? 100, rows: intFlag("--rows", rest) ?? 30,
                                        bytes: intFlag("--bytes", rest), core: stringFlag("--core", rest) ?? "ghostty", json: json)
            default:
                stderr("ccc: unknown command '\(verb)'")
                return usage()
            }
        } catch {
            stderr("ccc: \(error)")
            return 1
        }
    }

    // MARK: verbs

    /// One poll, printed. Does not need a running app: the roster is the
    /// harness's, not ours.
    static func list(json: Bool) async throws -> Int32 {
        let poller = RosterPoller()
        await poller.tick()
        let state = poller.state
        if let error = state.error {
            stderr("ccc: \(error)")
            return 1
        }
        if json {
            printJSON(state.sorted)
        } else {
            printRoster(state.sorted, issues: state.issues)
        }
        return state.issues.isEmpty ? 0 : 3
    }

    static func send(_ rest: [String], json: Bool) throws -> Int32 {
        var keys: [String] = []
        var text: [String] = []
        var i = 0
        while i < rest.count {
            if rest[i] == "--key", i + 1 < rest.count {
                guard NamedKey(rest[i + 1]) != nil else {
                    stderr("ccc: unknown key '\(rest[i + 1])'")
                    return 2
                }
                keys.append(rest[i + 1])
                i += 2
            } else {
                text.append(rest[i])
                i += 1
            }
        }
        guard !keys.isEmpty || !text.isEmpty else { return usage() }
        return try request(.send(text: text.isEmpty ? nil : text.joined(separator: " "), keys: keys.isEmpty ? nil : keys), json: json)
    }

    /// `--bytes N` replays only the first N bytes: a phase boundary from the
    /// recording's `.meta.json`, so a golden can be taken mid-session.
    static func replay(path: String, cols: Int, rows: Int, bytes limit: Int?, core: String, json: Bool) async throws -> Int32 {
        var bytes = try Data(contentsOf: URL(filePath: path))
        if let limit, limit < bytes.count { bytes = bytes.prefix(limit) }
        let host: TerminalHost
        switch core {
        case "ghostty": host = GhosttyHost(cols: cols, rows: rows)
        case "swiftterm": host = HeadlessHost(cols: cols, rows: rows)
        default:
            stderr("ccc: unknown core '\(core)' (ghostty|swiftterm)")
            return 2
        }
        host.feed(bytes)
        let grid = host.snapshot()
        if json { printJSON(grid) } else { print(grid.rendered()) }
        return 0
    }

    /// The window as PNG, written to `path` (default: a temp file), path printed.
    static func peek(to path: String?) throws -> Int32 {
        let response = try ControlClient().send(.peek)
        guard case .peek(let png) = response else {
            if case .error(let m) = response { stderr("ccc: \(m)") }
            return 1
        }
        let out = path ?? NSTemporaryDirectory() + "ccc-peek-\(Int(Date().timeIntervalSince1970)).png"
        try png.write(to: URL(filePath: out))
        print(out)
        return 0
    }

    /// Check 4 of docs/CHECKS.md: streaming throughput of a core. Feeds the
    /// recording `repeats` times as the PTY would (chunk by chunk) and times
    /// parse and snapshot separately. `--core` omitted runs both.
    static func bench(path: String, cols: Int, rows: Int, repeats: Int, core: String?, json: Bool) async throws -> Int32 {
        let bytes = try Data(contentsOf: URL(filePath: path))
        let chunks: [Data] = {
            // Prefer the recording's real chunking when its .events file sits beside it.
            let events = URL(filePath: path).deletingPathExtension().appendingPathExtension("events")
            if let text = try? String(contentsOf: events, encoding: .utf8) {
                var out: [Data] = []
                for line in text.split(separator: "\n") {
                    let parts = line.split(separator: " ").compactMap { Int($0) }
                    guard parts.count == 3, parts[1] + parts[2] <= bytes.count else { continue }
                    out.append(bytes.subdata(in: parts[1]..<(parts[1] + parts[2])))
                }
                if !out.isEmpty { return out }
            }
            return stride(from: 0, to: bytes.count, by: 4096).map { bytes.subdata(in: $0..<min($0 + 4096, bytes.count)) }
        }()
        struct Result: Encodable { var core: String; var bytes: Int; var repeats: Int; var parseMs: Double; var snapshotMs: Double; var mbPerSecond: Double; var footprintMB: Double }
        var results: [Result] = []
        for name in (core.map { [$0] } ?? ["swiftterm", "ghostty"]) {
            let host: TerminalHost = name == "ghostty" ? GhosttyHost(cols: cols, rows: rows) : HeadlessHost(cols: cols, rows: rows)
            let clock = ContinuousClock()
            let parse = clock.measure {
                for _ in 0..<repeats { for chunk in chunks { host.feed(chunk) } }
            }
            let snap = clock.measure { for _ in 0..<repeats { _ = host.snapshot() } }
            let parseMs = Double(parse.components.seconds) * 1000 + Double(parse.components.attoseconds) / 1e15
            let snapMs = Double(snap.components.seconds) * 1000 + Double(snap.components.attoseconds) / 1e15
            let total = Double(bytes.count * repeats)
            results.append(Result(core: name, bytes: bytes.count, repeats: repeats, parseMs: parseMs, snapshotMs: snapMs,
                                  mbPerSecond: total / 1_048_576 / (parseMs / 1000),
                                  footprintMB: Double(ProcessStats.footprint(of: getpid()) ?? 0) / 1_048_576))
        }
        if json { printJSON(results) } else {
            for r in results {
                print(String(format: "%-9@ parse %8.1f ms (%6.1f MB/s)   snapshot %7.2f ms/frame   footprint %.1f MB",
                             r.core as NSString, r.parseMs, r.mbPerSecond, r.snapshotMs / Double(max(1, repeats)), r.footprintMB))
            }
        }
        return 0
    }

    /// Everything that needs the pane goes over the socket to whoever holds it.
    static func request(_ request: ControlRequest, json: Bool) throws -> Int32 {
        let response = try ControlClient().send(request)
        switch response {
        case .error(let message):
            stderr("ccc: \(message)")
            return 1
        case .ok(let message):
            if json { printJSON(["ok": message]) } else { print(message) }
        case .list(let rows):
            if json { printJSON(rows) } else { printRoster(rows, issues: []) }
        case .snapshot(let info):
            if json { printJSON(info) } else if let grid = info.grid { print(grid.rendered()) } else { print("(nothing attached)") }
        case .stats(let stats):
            if json { printJSON(stats) } else { printStats(stats) }
        case .peek:
            stderr("ccc: unexpected peek response")
            return 1
        }
        return 0
    }

    // MARK: rendering

    static func printRoster(_ rows: [SessionRow], issues: [RosterShapeIssue]) {
        if !issues.isEmpty {
            print("⚠ roster shape changed: \(issues.map(\.description).joined(separator: "; "))")
        }
        if rows.isEmpty { print("(no sessions)"); return }
        let width = rows.map { ($0.session.name ?? "").count }.max() ?? 0
        for row in rows {
            let s = row.session
            let marker = row.attached ? "●" : " "
            let state = s.state?.rawValue ?? (s.kind == .interactive ? "interactive" : "-")
            let live = s.pid != nil ? (s.status?.rawValue ?? "live") : ""
            let name = (s.name ?? "").padding(toLength: width, withPad: " ", startingAt: 0)
            let waiting = s.waitingFor.map { " ⏸ \($0)" } ?? ""
            let model = row.model.map { shortModel($0) } ?? "-"
            let cwd = s.cwd.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
            print("\(marker) \(s.id.padding(toLength: 8, withPad: " ", startingAt: 0))  \(state.padding(toLength: 11, withPad: " ", startingAt: 0)) \(live.padding(toLength: 4, withPad: " ", startingAt: 0))  \(name)  \(model.padding(toLength: 10, withPad: " ", startingAt: 0))  \(cwd)\(waiting)")
        }
    }

    static func shortModel(_ model: String) -> String {
        model.replacingOccurrences(of: "claude-", with: "")
    }

    static func printStats(_ s: StatsInfo) {
        func mb(_ b: UInt64?) -> String { b.map { String(format: "%.1f MB", Double($0) / 1_048_576) } ?? "-" }
        func ms(_ v: Double?) -> String { v.map { String(format: "%.0f ms", $0) } ?? "-" }
        print("ccc pid \(s.pid)  memory \(mb(s.footprintBytes))  uptime \(Int(s.uptimeSeconds))s")
        if let child = s.childPID { print("child pid \(child)  memory \(mb(s.childFootprintBytes))") }
        print("roster poll  last \(ms(s.lastPollMs))  mean \(ms(s.meanPollMs))  n=\(s.pollCount)")
        print("pty in  \(s.ptyBytesIn) bytes  \(String(format: "%.0f", s.ptyBytesPerSecond)) B/s")
    }

    static func printJSON(_ value: some Encodable) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: try! encoder.encode(value), as: UTF8.self))
    }

    static func intFlag(_ name: String, _ args: [String]) -> Int? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return Int(args[i + 1])
    }

    static func stringFlag(_ name: String, _ args: [String]) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func stderr(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    @discardableResult
    static func usage(to handle: FileHandle = .standardError, status: Int32 = 2) -> Int32 {
        handle.write(Data("""
        usage: ccc                              open the app
               ccc list [--json]
               ccc attach <id> [--headless [--cols N --rows N]]
               ccc snapshot [--json]
               ccc send <text> | --key <name>...
               ccc detach
               ccc resize <cols> <rows>
               ccc stats [--json]
               ccc peek [out.png]                 PNG of the app window (no screen permission)
               ccc window show|hide|close         the window's own gestures (close = Cmd-W)
               ccc replay <bytes-file> [--cols N --rows N --bytes N --core ghostty|swiftterm] [--json]
               ccc bench <bytes-file> [--repeat N --core ghostty|swiftterm] [--json]   parse + snapshot throughput

        """.utf8))
        return status
    }
}
