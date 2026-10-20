import Foundation

/// "Open in lore": a row's job as lore renders it, `<lore>/job/<daemon id>`.
///
/// The split agreed with lore (2026-10-20): lore renders anything that
/// needs its index (history, cost, dialogue, threads, a job across /clears
/// and respawns), and ccc renders anything that needs a PTY or a live
/// control. Each links to the other for the thing the other owns.
/// `CCCURL` is the other direction.
///
/// **The lore asked is the one on the row's host.** That lore indexes the
/// row's transcripts. A local row asks this Mac's lore; a remote row asks
/// the far side's ccc (`ccc lore <id> --print --json`), which asks its own
/// lore. Air never needs to know studio's address. Nothing here hardcodes
/// one: the URL is whatever that lore says it is serving on.
public enum LoreLink {
    public enum LookupError: Error, CustomStringConvertible, Equatable {
        case notFound
        case notServing(String)
        case unreadable(String)
        case noRemoteCCC(String)

        public var description: String {
            switch self {
            case .notFound:
                return "lore is not installed on this Mac (looked on PATH, ~/.bun/bin, ~/.local/bin, /opt/homebrew/bin)"
            case .notServing(let why): return "lore's server is not answering (\(why)); `lore server up` starts it"
            case .unreadable(let why): return "lore did not say where it serves: \(why)"
            case .noRemoteCCC(let host):
                return "\(host) has no ccc to ask for its lore (`ccc hosts add \(host)` finds one)"
            }
        }
    }

    /// What `ccc lore --json` prints, and what the far side's answers.
    public struct Answer: Codable, Sendable, Equatable {
        public var ref: String
        public var url: String
        public init(ref: String, url: String) {
            self.ref = ref
            self.url = url
        }
    }

    /// `<base>/job/<id>`. lore's `/job/<key>` takes a daemon id, a bridge
    /// id, a session id or a name, so whatever the caller holds goes in.
    /// The roster's item passes the daemon id, the one that survives
    /// /clear.
    public static func jobURL(base: URL, id: String) -> URL {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        let key = id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
        let root = base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/"
        return URL(string: root + "job/" + key)!
    }

    /// This Mac's lore server, local only. `CCC_LORE_URL` wins (tests, or
    /// a lore elsewhere). Then `~/.lore/server.json`, which lore writes
    /// while its server runs and which a GUI app can read without exec'ing
    /// anything. Its pid is checked, since a crash leaves the file behind.
    /// Then `lore server status --json`.
    public static func serverURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                                 home: String = FileManager.default.homeDirectoryForCurrentUser.path) async throws -> URL {
        if let override = environment["CCC_LORE_URL"], !override.isEmpty {
            guard let url = URL(string: override), url.scheme != nil else {
                throw LookupError.unreadable("CCC_LORE_URL '\(override)' is not a URL")
            }
            return url
        }
        if let data = FileManager.default.contents(atPath: "\(home)/.lore/server.json"),
           let url = try? decodeServerFile(data, alive: { kill($0, 0) == 0 }) {
            return url
        }
        guard let lore = locate(environment: environment, home: home) else { throw LookupError.notFound }
        let output = try await Subprocess.run([lore, "server", "status", "--json"],
                                              environment: childEnvironment(lore: lore, environment: environment, home: home))
        return try decodeStatus(output.stdout, stderr: String(decoding: output.stderr, as: UTF8.self))
    }

    /// The lore executable: PATH, then where lore's installer and the
    /// usual package managers put it. A LaunchServices app's PATH is
    /// `/usr/bin:/bin:/usr/sbin:/sbin`, which is why there is a list.
    public static func locate(environment: [String: String], home: String) -> String? {
        var candidates = (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/lore" }
        candidates += ["\(home)/.bun/bin/lore", "\(home)/.local/bin/lore", "/opt/homebrew/bin/lore", "/usr/local/bin/lore"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// lore's bin is a shim that runs `exec bun …`, so the child needs
    /// `bun` on PATH as well as `lore`. Measured 2026-10-20 under a GUI
    /// PATH: "exec: bun: not found". The shim's own directory goes first,
    /// since bun installs beside it, and then the places a login shell
    /// would have added.
    static func childEnvironment(lore: String, environment: [String: String], home: String) -> [String: String] {
        var env = environment
        let dir = (lore as NSString).deletingLastPathComponent
        let extra = [dir, "\(home)/.bun/bin", "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        env["PATH"] = (extra + [environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        return env
    }

    /// `lore server status --json`: `.url` read leniently, with
    /// `.server.ok == false` taken as not serving. Anything else in the
    /// payload may move without costing this anything.
    static func decodeStatus(_ data: Data, stderr: String = "") throws -> URL {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            let said = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LookupError.unreadable(said.isEmpty ? "`lore server status --json` printed no JSON" : said)
        }
        if let server = object["server"] as? [String: Any], server["ok"] as? Bool == false {
            throw LookupError.notServing((server["error"] as? String) ?? "status says not ok")
        }
        guard let text = object["url"] as? String, let url = URL(string: text), url.scheme != nil else {
            throw LookupError.unreadable("no `url` in `lore server status --json`")
        }
        return url
    }

    /// `~/.lore/server.json`: `{url, pid, …}`. A pid that is not alive is
    /// the file a crashed server left, which is no answer.
    static func decodeServerFile(_ data: Data, alive: (pid_t) -> Bool) throws -> URL {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = object["url"] as? String, let url = URL(string: text), url.scheme != nil else {
            throw LookupError.unreadable("~/.lore/server.json has no url")
        }
        if let pid = (object["pid"] as? NSNumber)?.int32Value, !alive(pid) {
            throw LookupError.notServing("server.json names pid \(pid), which is gone")
        }
        return url
    }
}

extension ClaudeCLI {
    /// The lore page for a session on this host. Local: this Mac's lore
    /// server. Remote: the far side's `ccc lore`, which knows its own.
    public func loreURL(id: String) async throws -> URL {
        guard host.isLocal else {
            guard let ccc = host.ccc, let destination = host.ssh else { throw LoreLink.LookupError.noRemoteCCC(host.name) }
            try prepareControlDirectory()
            let out = try await run(sshPrefix(tty: false, destination: destination) + [ccc, "lore", id, "--print", "--json"],
                                    program: "ccc")
            guard let answer = try? JSONDecoder().decode(LoreLink.Answer.self, from: out),
                  let url = URL(string: answer.url) else {
                throw LoreLink.LookupError.unreadable("`ccc lore` on \(host.name) answered something that is not a link")
            }
            return url
        }
        return LoreLink.jobURL(base: try await LoreLink.serverURL(), id: id)
    }
}
