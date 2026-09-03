import CCCKit
import Foundation

/// The command face. Each verb is a click's twin.
///
///   ccc hosts [add|remove|check]      the machines ccc can reach
///   ccc list [--json]                 the roster, with the model column
///   ccc archive|unarchive|pin|unpin <ref>   our marks on a session (v4) — the context menu's twin
///   ccc watch [--json]                one line per transition — the notification's twin
///   ccc attach <ref> [--headless]     attach; headless drives a PTY and serves the socket
///   ccc spawn [--host <name>] [--cwd <dir>] [--from <ref>] [<prompt>… | -]   `claude --bg` on a host (v5) — the New Session sheet's twin
///
/// A `<ref>` is `id` (this Mac) or `host:id` (any host in `ccc hosts`).
///   ccc snapshot [--json]             the pane's grid as text
///   ccc send <text> | --key <name>… | --paste <text>   type into the pane
///   ccc detach                        detach the pane
///   ccc stats [--json]                memory, poll latency, PTY throughput
///   ccc replay <bytes> [--cols N --rows N]   render recorded bytes headlessly
///   ccc version                       which build this is (the bundle's)
///   ccc install-cli [--dir <dir>]     `ccc` on PATH as a symlink into the bundle
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
            case "version", "--version", "-v":
                if json { printJSON(BuildInfo.current) } else { print(BuildInfo.current.description) }
                return 0
            case "install-cli":
                return installCLI(directory: stringFlag("--dir", rest), force: rest.contains("--force"), json: json)
            case "list":
                var group = RosterGroup.none, sort = RosterSort.activity
                if let word = stringFlag("--group", rest) {
                    guard let g = RosterGroup(rawValue: word) else {
                        stderr("ccc: unknown group '\(word)' (\(RosterGroup.allCases.map(\.rawValue).joined(separator: "|")))")
                        return 2
                    }
                    group = g
                }
                if let word = stringFlag("--sort", rest) {
                    guard let s = RosterSort(rawValue: word) else {
                        stderr("ccc: unknown sort '\(word)' (\(RosterSort.allCases.map(\.rawValue).joined(separator: "|")))")
                        return 2
                    }
                    sort = s
                }
                return try await list(host: stringFlag("--host", rest), archived: rest.contains("--archived"),
                                      group: group, sort: sort, json: json)
            case "watch":
                return try await watch(host: stringFlag("--host", rest), interval: intFlag("--interval", rest) ?? 2,
                                       all: rest.contains("--all"), json: json)
            case "hook":
                return hook(settings: rest.contains("--settings"), json: json)
            case "hosts":
                return try await hosts(rest, json: json)
            case "attach":
                guard let text = rest.first(where: { !$0.hasPrefix("--") }) else { return usage() }
                guard let ref = SessionRef.parse(text) else {
                    stderr("ccc: '\(text)' is not a session ref (id, or host:id)")
                    return 2
                }
                if rest.contains("--headless") {
                    return Headless.run(ref: ref, cols: intFlag("--cols", rest) ?? 120, rows: intFlag("--rows", rest) ?? 40)
                }
                return try request(.attach(id: ref), json: json)
            case "rm":
                guard let text = rest.first(where: { !$0.hasPrefix("--") }) else { return usage() }
                guard let ref = SessionRef.parse(text) else {
                    stderr("ccc: '\(text)' is not a session ref (id, or host:id)")
                    return 2
                }
                return try await rm(ref: ref, json: json)
            case "spawn", "new":
                return try await spawn(rest, json: json)
            case "merge":
                guard let text = rest.first(where: { !$0.hasPrefix("--") }) else { return usage() }
                guard let ref = SessionRef.parse(text) else {
                    stderr("ccc: '\(text)' is not a session ref (id, or host:id)")
                    return 2
                }
                var strategy = MergeStrategy.ffOnly
                for flag in rest.filter({ $0.hasPrefix("--") }) {
                    guard let s = MergeStrategy.parse(flag: flag) else {
                        stderr("ccc: unknown flag '\(flag)' (\(MergeStrategy.allCases.map(\.flag).joined(separator: "|")))")
                        return 2
                    }
                    strategy = s
                }
                return try await merge(strategy, ref: ref, json: json)
            case "shell":
                if rest.contains("--close") { return try request(.shellClose, json: json) }
                guard let text = rest.first(where: { !$0.hasPrefix("--") }) else { return usage() }
                guard let ref = SessionRef.parse(text) else {
                    stderr("ccc: '\(text)' is not a session ref (id, or host:id)")
                    return 2
                }
                return try request(.shell(id: ref, repo: rest.contains("--repo") ? true : nil), json: json)
            case "push":
                guard let text = rest.first(where: { !$0.hasPrefix("--") }) else { return usage() }
                guard let ref = SessionRef.parse(text) else {
                    stderr("ccc: '\(text)' is not a session ref (id, or host:id)")
                    return 2
                }
                for flag in rest.filter({ $0.hasPrefix("--") }) where flag != "--base" {
                    stderr("ccc: unknown flag '\(flag)' (--base)")
                    return 2
                }
                return try await push(rest.contains("--base") ? .base : .branch, ref: ref, json: json)
            case "archive", "unarchive", "pin", "unpin":
                guard let text = rest.first(where: { !$0.hasPrefix("--") }) else { return usage() }
                guard let ref = SessionRef.parse(text) else {
                    stderr("ccc: '\(text)' is not a session ref (id, or host:id)")
                    return 2
                }
                return try await mark(MarkChange(rawValue: verb)!, ref: ref, json: json)
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
                guard let action = rest.first, ["show", "hide", "close", "resize"].contains(action) else { return usage() }
                if action == "resize" {
                    guard rest.count == 3, Int(rest[1]) != nil, Int(rest[2]) != nil else { return usage() }
                    return try request(.window(action: "resize \(rest[1]) \(rest[2])"), json: json)
                }
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

    /// One poll of every host, printed — what the window shows. Does not
    /// need a running app: the roster is the harness's, not ours. `--host`
    /// narrows it to one (this is how another ccc reads us over ssh:
    /// `--host local`, so the hop never fans out again on the far side).
    ///
    /// Exit: 0 with rows; 3 when a roster changed shape (rows still
    /// printed); 1 only when *no* host answered. A host that failed is one
    /// line on stderr and its last known rows are kept — never a blank
    /// roster over one sleeping Mac.
    ///
    /// Archived rows (v4) are folded out of the text the way the window
    /// folds them; `--archived` shows them. `--json` always carries every
    /// row with its `archived` / `pinned` flags: it is data, it is what the
    /// far side reads to build *its* roster, and a machine filters for
    /// itself. `--group` and `--sort` are the View menu's twins; grouping
    /// is presentation and never reaches `--json`, the sort does.
    static func list(host name: String?, archived: Bool = false, group: RosterGroup = .none,
                     sort: RosterSort = .activity, json: Bool) async throws -> Int32 {
        let loaded = HostConfig.load()
        for issue in loaded.issues { stderr("ccc: \(issue)") }
        let poller: RosterPoller
        if let name {
            guard let host = loaded.config.host(named: name) else {
                stderr("ccc: unknown host '\(name)' (known: \(loaded.config.hosts.map(\.name).joined(separator: ", ")))")
                return 2
            }
            guard let cli = ClaudeCLI.of(host) else {
                stderr("ccc: \(host.validate() ?? "claude not found for host '\(name)'")")
                return 1
            }
            poller = RosterPoller(cli: cli)
        } else {
            poller = RosterPoller(hosts: loaded.config)
        }
        await poller.tick()
        let state = poller.state
        for failed in state.failures {
            stderr("ccc: \(failed.host): \(failed.error ?? "unreachable")")
        }
        guard state.anyHostAnswered else { return 1 }
        for note in state.notes { stderr("ccc: \(note)") }
        if json {
            printJSON(state.rows(sortedBy: sort))
            // stdout stays pure JSON, but the banner must not vanish just
            // because a machine is reading: exit 3 alone told a caller
            // *that* something changed and never *what*. This is also what
            // crosses the ssh hop when another ccc polls this one.
            for issue in state.issues { stderr("⚠ roster shape changed: \(issue.description)") }
        } else {
            let sections = state.sections(group: group, sort: sort, archived: archived) { cwd, host in
                loaded.config.shortCwd(cwd, host: host)
            }
            printRoster(sections, issues: state.issues, hosts: loaded.config)
            let hidden = state.hiddenCount
            if !archived, hidden > 0 { print("(\(hidden) archived; --archived shows them)") }
        }
        return state.issues.isEmpty ? 0 : 3
    }

    /// `ccc archive|unarchive|pin|unpin <ref>` (v4): a mark on the session,
    /// kept with the session's host — the overlay file here, or the same
    /// verb on the far side's ccc, its answer passed through. Needs no
    /// running app; the window sees the file change on its next tick.
    static func mark(_ change: MarkChange, ref: SessionRef, json: Bool) async throws -> Int32 {
        let loaded = HostConfig.load()
        for issue in loaded.issues { stderr("ccc: \(issue)") }
        guard let host = loaded.config.host(named: ref.host) else {
            stderr("ccc: unknown host '\(ref.host)' (known: \(loaded.config.hosts.map(\.name).joined(separator: ", ")))")
            return 2
        }
        guard let cli = ClaudeCLI.of(host) else {
            stderr("ccc: \(host.validate() ?? "claude not found for host '\(ref.host)'")")
            return 1
        }
        let said = try await cli.mark(change, id: ref.id)
        if json { printJSON(["ref": ref.description, change.rawValue: "true", "said": said]) } else { print(said) }
        return 0
    }

    /// `ccc merge <ref> [--ff-only|--no-ff|--squash]` (v6): land the
    /// session's worktree branch on the repository's default branch, where
    /// the repository is — git here, or the same verb on the far side's
    /// ccc. Exit 0 when something merged, 1 when it refused (the reason is
    /// the sentence): a refusal is the guard working, not an error of ours.
    static func merge(_ strategy: MergeStrategy, ref: SessionRef, json: Bool) async throws -> Int32 {
        let loaded = HostConfig.load()
        for issue in loaded.issues { stderr("ccc: \(issue)") }
        guard let host = loaded.config.host(named: ref.host) else {
            stderr("ccc: unknown host '\(ref.host)' (known: \(loaded.config.hosts.map(\.name).joined(separator: ", ")))")
            return 2
        }
        guard let cli = ClaudeCLI.of(host) else {
            stderr("ccc: \(host.validate() ?? "claude not found for host '\(ref.host)'")")
            return 1
        }
        let outcome = try await cli.merge(strategy, id: ref.id)
        if json {
            printJSON(["ref": ref.description, "strategy": strategy.rawValue, "merged": outcome.merged ? "true" : "false", "said": outcome.said])
        } else {
            print(outcome.said)
        }
        return outcome.merged ? 0 : 1
    }

    /// `ccc push <ref> [--base]` (v6 slice 3): the session's worktree
    /// branch — or, with `--base`, the repository's default branch — to
    /// origin, never forced. Exit 0 when it pushed, 1 when git refused
    /// or there was nothing to send.
    static func push(_ target: PushTarget, ref: SessionRef, json: Bool) async throws -> Int32 {
        let loaded = HostConfig.load()
        for issue in loaded.issues { stderr("ccc: \(issue)") }
        guard let host = loaded.config.host(named: ref.host) else {
            stderr("ccc: unknown host '\(ref.host)' (known: \(loaded.config.hosts.map(\.name).joined(separator: ", ")))")
            return 2
        }
        guard let cli = ClaudeCLI.of(host) else {
            stderr("ccc: \(host.validate() ?? "claude not found for host '\(ref.host)'")")
            return 1
        }
        let outcome = try await cli.push(target, id: ref.id)
        if json {
            printJSON(["ref": ref.description, "target": target.rawValue, "pushed": outcome.merged ? "true" : "false", "said": outcome.said])
        } else {
            print(outcome.said)
        }
        return outcome.merged ? 0 : 1
    }

    /// Delete a session: `claude rm` behind the ref's host prefix, its
    /// answer and exit status passed through. The dirty-worktree guard is
    /// the harness's (docs/HARNESS.md); ccc adds no `--force` because the
    /// harness has none, and "kept" is the correct answer, not an error
    /// of ours.
    static func rm(ref: SessionRef, json: Bool) async throws -> Int32 {
        let loaded = HostConfig.load()
        for issue in loaded.issues { stderr("ccc: \(issue)") }
        guard let host = loaded.config.host(named: ref.host) else {
            stderr("ccc: unknown host '\(ref.host)' (known: \(loaded.config.hosts.map(\.name).joined(separator: ", ")))")
            return 2
        }
        guard let cli = ClaudeCLI.of(host) else {
            stderr("ccc: \(host.validate() ?? "claude not found for host '\(ref.host)'")")
            return 1
        }
        let result = try await cli.rm(id: ref.id)
        if json {
            printJSON(["ref": ref.description, "removed": result.removed ? "true" : "false", "said": result.said])
        } else {
            print(result.said)
        }
        return result.removed ? 0 : 1
    }

    /// `ccc spawn` (v5): `claude --bg` on a host, the New Session sheet's
    /// twin. Needs no running app; `--attach` then asks the app to attach,
    /// the way `ccc attach` does. The prompt is every word that is not a
    /// flag, joined by spaces — or stdin when that one word is `-`, which
    /// is how an agent hands over a prompt with its newlines intact. No
    /// prompt is the draft: the session registers and waits for one.
    static func spawn(_ args: [String], json: Bool) async throws -> Int32 {
        let valued = ["--host", "--cwd", "--name", "--model", "--agent", "--permission-mode", "--effort", "--from"]
        var spec = SpawnRequest()
        var hostFlag: String?
        var from: SessionRef?
        var attach = false
        var words: [String] = []
        var i = 0
        while i < args.count {
            let arg = args[i]
            if valued.contains(arg) {
                guard i + 1 < args.count else {
                    stderr("ccc: \(arg) needs a value")
                    return 2
                }
                let value = args[i + 1]
                switch arg {
                case "--host": hostFlag = value
                case "--cwd": spec.cwd = value
                case "--name": spec.name = value
                case "--model": spec.model = value
                case "--agent": spec.agent = value
                case "--permission-mode": spec.permissionMode = value
                case "--from":
                    guard let ref = SessionRef.parse(value) else {
                        stderr("ccc: '\(value)' is not a session ref (id, or host:id)")
                        return 2
                    }
                    from = ref
                default: spec.effort = value
                }
                i += 2
                continue
            }
            switch arg {
            case "--attach": attach = true
            // `--worktree` is bare (the harness names it) or `--worktree=<name>`:
            // never `--worktree <name>`, which would eat the prompt's first word.
            case "--worktree": spec.worktree = ""
            case _ where arg.hasPrefix("--worktree="): spec.worktree = String(arg.dropFirst("--worktree=".count))
            case _ where arg.hasPrefix("--") && arg.count > 2:
                stderr("ccc: unknown flag '\(arg)' for spawn")
                return 2
            default: words.append(arg)
            }
            i += 1
        }
        if words == ["-"] {
            spec.prompt = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        } else if !words.isEmpty {
            spec.prompt = words.joined(separator: " ")
        }
        // A fork (slice 3) runs where its source lives — the transcript is
        // there — so `--from host:id` names the host, and `--host` may only
        // agree with it.
        if let from, let hostFlag, hostFlag != from.host {
            stderr("ccc: \(from) lives on '\(from.host)', not '\(hostFlag)' — a fork runs where its transcript is")
            return 2
        }
        let hostName = from?.host ?? hostFlag ?? Host.localName
        // A cwd given as `~/…` or relative is this shell's to resolve for
        // a local spawn; a remote one keeps `~` for the far side's shell.
        // No cwd is this shell's directory — or, for a fork, the source's
        // (resolved below with its session id).
        if hostName == Host.localName, let cwd = spec.cwd {
            spec.cwd = (cwd as NSString).expandingTildeInPath
            if !spec.cwd!.hasPrefix("/") {
                spec.cwd = FileManager.default.currentDirectoryPath + "/" + spec.cwd!
            }
        } else if hostName == Host.localName, from == nil {
            spec.cwd = FileManager.default.currentDirectoryPath
        }

        let loaded = HostConfig.load()
        for issue in loaded.issues { stderr("ccc: \(issue)") }
        guard let host = loaded.config.host(named: hostName) else {
            stderr("ccc: unknown host '\(hostName)' (known: \(loaded.config.hosts.map(\.name).joined(separator: ", ")))")
            return 2
        }
        guard let cli = ClaudeCLI.of(host) else {
            stderr("ccc: \(host.validate() ?? "claude not found for host '\(hostName)'")")
            return 1
        }
        // The source's row: `--resume` needs the full session id (the
        // short one opens the harness's picker — docs/HARNESS.md), and the
        // row is where that id and the source's folder are.
        if let from {
            let poller = RosterPoller(cli: cli)
            await poller.tick()
            if let failed = poller.state.failures.first {
                stderr("ccc: \(failed.host): \(failed.error ?? "unreachable")")
                return 1
            }
            guard let row = poller.state.rows.first(where: { $0.ref == from }) else {
                stderr("ccc: no session \(from) in the roster of \(host.name)")
                return 1
            }
            guard let sessionId = row.session.sessionId, !sessionId.isEmpty else {
                stderr("ccc: \(from) carries no session id to resume from")
                return 1
            }
            spec.from = sessionId
            if spec.cwd == nil { spec.cwd = row.session.cwd }
        }
        let result: SpawnResult
        do {
            result = try await cli.spawn(spec)
        } catch {
            stderr("ccc: \(error)")
            return 1
        }
        if json {
            printJSON(result)
        } else {
            print(result.description)
        }
        guard attach else { return 0 }
        return try request(.attach(id: result.ref), json: json)
    }

    /// The notification center's twin (v3): the same poll, the same
    /// `TransitionDetector`, one line per event on stdout until interrupted.
    /// Needs no running app, like `list`. The first poll is the baseline
    /// and prints what is already blocked to stderr, so a reader knows the
    /// standing state without it counting as news.
    static func watch(host name: String?, interval: Int, all: Bool, json: Bool) async throws -> Int32 {
        let loaded = HostConfig.load()
        for issue in loaded.issues { stderr("ccc: \(issue)") }
        let config: HostConfig
        if let name {
            guard let host = loaded.config.host(named: name) else {
                stderr("ccc: unknown host '\(name)' (known: \(loaded.config.hosts.map(\.name).joined(separator: ", ")))")
                return 2
            }
            config = HostConfig(hosts: [host])
        } else {
            config = loaded.config
        }
        // The notification's twin honours the notification's mute; `--all`
        // is the ear that hears every host (and a muted host named with
        // `--host` is what was asked for).
        let filter = (all || name != nil) ? HostConfig(hosts: []) : config
        let poller = RosterPoller(hosts: config, interval: .seconds(interval))
        var detector = TransitionDetector()
        await poller.tick()
        var state = poller.state
        for failed in state.failures { stderr("ccc: \(failed.host): \(failed.error ?? "unreachable")") }
        guard state.anyHostAnswered else { return 1 }
        _ = detector.observe(state)
        let blocked = state.rows.filter(\.isWaiting)
        let muted = filter.mutedHosts
        stderr("ccc: watching \(config.hosts.count) host\(config.hosts.count == 1 ? "" : "s"), \(state.rows.count) sessions, \(blocked.count) blocked"
               + (blocked.isEmpty ? "" : ": " + blocked.map { "\($0.session.name ?? $0.ref.description)" }.joined(separator: ", "))
               + (muted.isEmpty ? "" : "; muted: \(muted.joined(separator: ", ")) (--all hears them)"))
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm:ss"
        var reported = Set<String>()
        while true {
            try? await Task.sleep(for: .seconds(interval))
            await poller.tick()
            state = poller.state
            // A host's failure is said once per outage, not every tick.
            for failed in state.failures where reported.insert(failed.host).inserted {
                stderr("ccc: \(failed.host): \(failed.error ?? "unreachable") (rows kept; silent until it answers)")
            }
            for host in state.hosts where host.error == nil { reported.remove(host.host) }
            for event in filter.unmuted(detector.observe(state)) {
                if json {
                    printJSON(event)
                } else {
                    let mark = event.kind == .blocked ? "⏸" : (event.kind == .done ? "✓" : "✗")
                    print("\(clock.string(from: event.at))  \(mark) \(event.kind.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0))  \(event.ref.description.padding(toLength: 14, withPad: " ", startingAt: 0))  \(event.headline)")
                }
                fflush(stdout)
            }
        }
    }

    /// The harness's `Notification` hook, as a command (v3, slice 2). The
    /// hook JSON arrives on stdin and goes to the app over the control
    /// socket; the app posts what the roster could not show. Exit 0 in
    /// every case — no app, an older app that does not know the verb, an
    /// unreadable payload — because a hook's failure is printed inside the
    /// session it fired from, and that session is the user's. What went
    /// wrong is one line on stderr, where the harness's verbose mode finds
    /// it. `--settings` prints the settings.json entry that routes the
    /// hook here; ccc never writes that file.
    static func hook(settings: Bool, json: Bool) -> Int32 {
        if settings {
            let command = CLIInstall.ccc.status().path ?? "ccc"
            print(HookSettings.snippet(command: command))
            return 0
        }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let event = HookEvent.decode(data) else {
            stderr("ccc hook: stdin was not a JSON object (\(data.count) bytes); nothing posted")
            return 0
        }
        do {
            switch try ControlClient().send(.hook(event: event)) {
            case .ok(let message):
                if json { printJSON(["ok": message]) } else { stderr("ccc hook: \(message)") }
            case .error(let message):
                stderr("ccc hook: \(message)")
            default:
                stderr("ccc hook: unexpected response")
            }
        } catch {
            stderr("ccc hook: \(error) — nothing posted")
        }
        return 0
    }

    /// The machines ccc can reach, and the gestures on that list. `check`
    /// is the one that proves something: it runs the *real* poll command on
    /// each host — `claude agents --json --all` behind the ssh prefix — and
    /// reports what came back and how long it took. Run it twice and the
    /// second is the multiplexed connection (`ControlPersist`) not paying a
    /// handshake, which is the whole reason the master socket exists.
    static func hosts(_ rest: [String], json: Bool) async throws -> Int32 {
        let action = rest.first.flatMap { $0.hasPrefix("--") ? nil : $0 } ?? "list"
        var loaded = HostConfig.load()
        for issue in loaded.issues { stderr("ccc: \(issue)") }
        switch action {
        case "list":
            if json { printJSON(loaded.config.hosts); return 0 }
            let width = loaded.config.hosts.map(\.name.count).max() ?? 0
            for host in loaded.config.hosts {
                let name = host.name.padding(toLength: width, withPad: " ", startingAt: 0)
                let reader = host.isLocal ? "" : "  roster via \(host.ccc.map { "ccc \($0)" } ?? "claude agents (no model column)")"
                let home = host.isLocal ? "" : "  home \(host.home ?? "(unknown; `ccc hosts check` learns it)")"
                let muted = host.isMuted ? "  (muted)" : ""
                print("\(name)  \(host.ssh.map { "ssh \($0)" } ?? "(this Mac)")  \(host.claude ?? "")\(reader)\(home)\(muted)")
            }
            print("\n\(HostConfig.defaultPath)")
            return loaded.issues.isEmpty ? 0 : 3

        case "add":
            guard let name = rest.dropFirst().first, !name.hasPrefix("--") else {
                stderr("ccc: usage: ccc hosts add <name> --ssh <destination> [--claude <absolute path>]")
                return 2
            }
            // Ask the host where things are — home, claude, ccc — in one
            // ssh, rather than guess (`ClaudeCLI.Probe`). Flags override
            // what it says; `--no-ccc` reads the harness instead of the far
            // side's ccc (a correct roster with a blank model column).
            let ssh = stringFlag("--ssh", rest) ?? name
            var notes: [String] = []
            var probed: ClaudeCLI.Probe?
            do {
                probed = try await ClaudeCLI(executable: "claude", host: Host(name: name, ssh: ssh)).probe()
            } catch {
                notes.append("could not reach \(ssh) to look for claude and ccc (\(error))")
            }
            let claude = stringFlag("--claude", rest) ?? probed?.claude
            guard let claude else {
                stderr("ccc: no claude found on \(name) at \(ClaudeCLI.Probe.claudeCandidates.joined(separator: ", ")); pass --claude <absolute path>"
                       + (notes.isEmpty ? "" : " (\(notes.joined(separator: "; ")))"))
                return 1
            }
            let remoteCCC = rest.contains("--no-ccc") ? nil : (stringFlag("--ccc", rest) ?? probed?.ccc)
            if remoteCCC == nil, !rest.contains("--no-ccc") {
                notes.append("no ccc on \(name) (looked in \(ClaudeCLI.Probe.cccCandidates.joined(separator: ", "))): roster via claude agents, no model column; install ccc there and re-add")
            }
            let host = Host(name: name, ssh: ssh, claude: claude, ccc: remoteCCC, home: probed?.home)
            if let problem = host.validate() {
                stderr("ccc: \(problem)")
                return 2
            }
            loaded.config.hosts.removeAll { $0.name == name }
            loaded.config.hosts.append(host)
            try loaded.config.save()
            let reader = host.ccc.map { "ccc \($0)" } ?? "claude agents (no model column)"
            let home = host.home.map { ", home \($0)" } ?? ", home unknown (`ccc hosts check` learns it)"
            print("added \(name) (ssh \(host.ssh ?? "-"), claude \(host.claude ?? "-"), roster via \(reader)\(home)); `ccc hosts check \(name)` to prove it")
            for note in notes { stderr("ccc: \(note)") }
            return 0

        case "reconnect":
            // The wake-up gesture by hand (docs/DESIGN.md §4b). The app owns
            // the pollers, so ask it; with no app running, evict the masters
            // here and prove the hop with the same check the poller runs.
            let wanted = rest.dropFirst().first
            if let wanted, loaded.config.host(named: wanted) == nil {
                stderr("ccc: no host '\(wanted)'")
                return 1
            }
            var note = "no app running"
            if let response = try? ControlClient().send(.reconnect(host: wanted)) {
                note = "the running ccc is older and has no `reconnect` (restart it to pick up the new build)"
                switch response {
                case .error(let message) where message.contains("malformed"):
                    // An older ccc holds the socket and has no reconnect;
                    // its pollers keep their wedged masters until it is
                    // restarted, but evicting here still helps every new
                    // ssh, including its next poll.
                    break
                case .error(let message):
                    stderr("ccc: \(message)")
                    return 1
                case .ok(let message):
                    if json { printJSON(["ok": message]) } else { print(message) }
                    return 0
                default:
                    stderr("ccc: unexpected reply to reconnect")
                    return 1
                }
            }
            var evicted: [String] = []
            for host in loaded.config.hosts where !host.isLocal && (wanted == nil || host.name == wanted) {
                if ClaudeCLI.of(host)?.evictControlMaster() == true { evicted.append(host.name) }
            }
            stderr("ccc: \(note); evicted \(evicted.isEmpty ? "no masters (none were open)" : "the master for " + evicted.joined(separator: ", ")), checking")
            return try await hosts(["check"] + (wanted.map { [$0] } ?? []), json: json)

        case "remove":
            guard let name = rest.dropFirst().first else { return usage() }
            guard name != Host.localName else {
                stderr("ccc: local is this Mac and cannot be removed")
                return 2
            }
            guard loaded.config.host(named: name) != nil else {
                stderr("ccc: no host '\(name)'")
                return 1
            }
            loaded.config.hosts.removeAll { $0.name == name }
            try loaded.config.save()
            print("removed \(name)")
            return 0

        case "mute", "unmute":
            // The notifier's per-host mute (v3, slice 2): a mark in this
            // file, read by the app on its next tick and by `ccc watch`.
            guard let name = rest.dropFirst().first else {
                stderr("ccc: usage: ccc hosts \(action) <name>")
                return 2
            }
            guard loaded.config.setMuted(name, action == "mute") else {
                stderr("ccc: unknown host '\(name)' (known: \(loaded.config.hosts.map(\.name).joined(separator: ", ")))")
                return 1
            }
            try loaded.config.save()
            let muted = loaded.config.mutedHosts
            print("\(action == "mute" ? "muted" : "unmuted") \(name)"
                  + (muted.isEmpty ? "; nothing is muted" : "; muted: \(muted.joined(separator: ", "))"))
            return 0

        case "check":
            let wanted = rest.dropFirst().first
            let targets = loaded.config.hosts.filter { wanted == nil || $0.name == wanted }
            if targets.isEmpty {
                stderr("ccc: no host '\(wanted ?? "")'")
                return 1
            }
            // Runs the reader the poller would actually use, so a green row
            // here means the roster works — including whether the model
            // column came back, which is the whole reason `ccc` on the far
            // side exists.
            struct Check: Encodable {
                var host: String; var ok: Bool; var ms: Double; var reader: String
                var sessions: Int?; var models: Int?; var home: String?; var error: String?
                /// The far side's ccc, when that is the reader: its version
                /// and build, and the build's distance from this Mac's
                /// (negative = behind). A number, so "air is four builds
                /// behind studio" is read off the row rather than deduced
                /// from a decode failure.
                var ccc: BuildInfo?; var buildSkew: Int?
            }
            let mine = BuildInfo.current
            var results: [Check] = []
            var learned = false
            for host in targets {
                let started = ContinuousClock.now
                guard let cli = ClaudeCLI.of(host) else {
                    results.append(Check(host: host.name, ok: false, ms: 0, reader: "-", sessions: nil, models: nil,
                                         home: host.home, error: host.validate() ?? "claude not found"))
                    continue
                }
                let reader = cli.rosterSource.rawValue
                // A reachable host is the moment to learn its home if we
                // never did (`add` may have run while it was down). Before
                // the roster read, so a host whose ssh works but whose
                // `ccc` path is wrong still gets its home — and the two
                // share one master, so this is not a second handshake.
                var home = host.home
                if !host.isLocal, home == nil {
                    do {
                        let found = try await cli.home()
                        if let i = loaded.config.hosts.firstIndex(where: { $0.name == host.name }) {
                            loaded.config.hosts[i].home = found
                            home = found
                            learned = true
                        }
                    } catch let error as ClaudeCLI.RunError where error.status == 255 {
                        // ssh itself failed: the roster read would only pay
                        // the same timeout again to say the same thing.
                        results.append(Check(host: host.name, ok: false, ms: elapsedMs(since: started), reader: reader,
                                             sessions: nil, models: nil, home: nil, error: "\(error)"))
                        continue
                    } catch {
                        // Anything else (an odd shell answer) is not the
                        // host's fault; the roster read decides.
                    }
                }
                do {
                    let reading = try await cli.rosterJSON()
                    let ms = elapsedMs(since: started)
                    if cli.rosterSource == .ccc {
                        let rows = try JSONDecoder.roster.decode([SessionRow].self, from: reading.data)
                        var check = Check(host: host.name, ok: true, ms: ms, reader: reader,
                                          sessions: rows.count, models: rows.count { $0.model != nil },
                                          home: home, error: reading.warning)
                        // The roster worked, so the hop is warm: one more
                        // round trip says which build answered it.
                        if !host.isLocal {
                            do {
                                check.ccc = try await cli.cccVersion()
                                if let theirs = check.ccc?.build, let ours = mine.build { check.buildSkew = theirs - ours }
                            } catch let error as ClaudeCLI.RunError where error.status == 2 {
                                check.error = (check.error.map { $0 + "; " } ?? "") + "ccc there predates `ccc version` (build < 56); update it"
                            } catch {
                                check.error = (check.error.map { $0 + "; " } ?? "") + "\(error)"
                            }
                        }
                        results.append(check)
                    } else {
                        let decoded = RosterDecoder.decode(reading.data)
                        results.append(Check(host: host.name, ok: true, ms: ms, reader: reader,
                                             sessions: decoded.sessions.count, models: nil, home: home,
                                             error: decoded.issues.isEmpty ? nil : decoded.issues.map(\.description).joined(separator: "; ")))
                    }
                } catch {
                    results.append(Check(host: host.name, ok: false, ms: elapsedMs(since: started), reader: reader,
                                         sessions: nil, models: nil, home: host.home, error: "\(error)"))
                }
            }
            if learned { try loaded.config.save() }
            if json { printJSON(results) } else {
                let width = results.map(\.host.count).max() ?? 0
                for r in results {
                    let name = r.host.padding(toLength: width, withPad: " ", startingAt: 0)
                    let head = r.ok ? String(format: "ok   %5.0f ms  %-6@ %d sessions", r.ms, r.reader as NSString, r.sessions ?? 0)
                                    : String(format: "FAIL %5.0f ms  %-6@", r.ms, r.reader as NSString)
                    let models = r.models.map { ", \($0) with a model" } ?? ""
                    let home = r.host == Host.localName ? "" : (r.home.map { "  home \($0)" } ?? "  home unknown")
                    var build = r.ccc.map { "  ccc \($0.short)" } ?? ""
                    if let skew = r.buildSkew, skew != 0 {
                        let n = abs(skew), s = n == 1 ? "" : "s"
                        build += skew < 0 ? " — \(n) build\(s) behind this Mac's \(mine.short)"
                                          : " — \(n) build\(s) ahead of this Mac's \(mine.short)"
                    }
                    print("\(name)  \(head)\(models)\(build)\(home)\(r.error.map { "  \($0)" } ?? "")")
                }
            }
            return results.allSatisfy(\.ok) ? 0 : 1

        default:
            stderr("ccc: unknown hosts action '\(action)' (list|add|remove|check|reconnect|mute|unmute)")
            return 2
        }
    }

    /// The app's first-launch offer, by hand. Idempotent: an existing link
    /// to this build is reported, not remade.
    static func installCLI(directory: String?, force: Bool, json: Bool) -> Int32 {
        let me = BuildInfo.current
        guard me.isBundled else {
            stderr("ccc: \(me.executablePath) is not in an app bundle, so there is nothing to link into; `scripts/install` makes one")
            return 1
        }
        do {
            let result = try CLIInstall.ccc.install(executable: me.executablePath, directory: directory, force: force)
            if json {
                printJSON(["path": result.path, "replaced": result.replaced ?? "", "build": me.short])
            } else {
                print("\(result.description)  (\(me.short))")
            }
            return 0
        } catch {
            stderr("ccc: \(error)")
            return 1
        }
    }

    static func elapsedMs(since started: ContinuousClock.Instant) -> Double {
        let d = started.duration(to: .now)
        return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    /// `--paste` takes one argument and goes through the host's paste path,
    /// so the child sees it framed as a paste (bracketed under mode 2004) —
    /// bare `<text>` is raw typing straight at the PTY. `-` reads stdin, so a
    /// multi-line paste needs no shell quoting. Applied before `--key`, which
    /// makes `send --paste "$(cat x)" --key enter` the scripted ⌘V + return.
    static func send(_ rest: [String], json: Bool) throws -> Int32 {
        var keys: [String] = []
        var text: [String] = []
        var wheel: Int?
        var paste: String?
        var i = 0
        while i < rest.count {
            if rest[i] == "--key", i + 1 < rest.count {
                guard NamedKey(rest[i + 1]) != nil else {
                    stderr("ccc: unknown key '\(rest[i + 1])'")
                    return 2
                }
                keys.append(rest[i + 1])
                i += 2
            } else if rest[i] == "--wheel", i + 1 < rest.count, let n = Int(rest[i + 1]) {
                wheel = n
                i += 2
            } else if rest[i] == "--paste", i + 1 < rest.count {
                let argument = rest[i + 1]
                if argument == "-" {
                    let stdin = FileHandle.standardInput.readDataToEndOfFile()
                    paste = String(decoding: stdin, as: UTF8.self)
                } else {
                    paste = argument
                }
                i += 2
            } else {
                text.append(rest[i])
                i += 1
            }
        }
        guard !keys.isEmpty || !text.isEmpty || wheel != nil || paste != nil else { return usage() }
        guard paste?.isEmpty != true else {
            stderr("ccc: --paste got empty text")
            return 2
        }
        return try request(.send(text: text.isEmpty ? nil : text.joined(separator: " "), keys: keys.isEmpty ? nil : keys,
                                 wheel: wheel, paste: paste), json: json)
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
        // Equal-work evidence beside the rate: what each core materialized
        // (scrollback rows retained, grid text) and the footprint delta of
        // running it. A parser that skips bookkeeping looks faster and is
        // not comparable; these columns show whether both did the same job.
        struct Result: Encodable {
            var core: String; var bytes: Int; var repeats: Int
            var parseMs: Double; var snapshotMs: Double; var mbPerSecond: Double
            var footprintDeltaMB: Double; var scrollbackRows: Int; var gridDigest: String
        }
        // A recording made by scripts/record-stream carries a mid-stream
        // resize; replaying it at the same byte offset is what makes reflow
        // cost part of the measurement.
        struct StreamMeta: Decodable { var cols: Int?; var rows: Int?; var resizeAtBytes: Int?; var resizedTo: [Int]? }
        let metaURL = URL(filePath: path).deletingPathExtension().appendingPathExtension("meta.json")
        let meta = (try? Data(contentsOf: metaURL)).flatMap { try? JSONDecoder().decode(StreamMeta.self, from: $0) }
        let startCols = meta?.cols ?? cols, startRows = meta?.rows ?? rows
        var results: [Result] = []
        for name in (core.map { [$0] } ?? ["swiftterm", "ghostty"]) {
            let before = ProcessStats.footprint(of: getpid()) ?? 0
            let host: TerminalHost = name == "ghostty" ? GhosttyHost(cols: startCols, rows: startRows) : HeadlessHost(cols: startCols, rows: startRows)
            let clock = ContinuousClock()
            let parse = clock.measure {
                for _ in 0..<repeats {
                    host.resize(cols: startCols, rows: startRows)
                    var offset = 0
                    var resized = false
                    for chunk in chunks {
                        host.feed(chunk)
                        offset += chunk.count
                        if !resized, let at = meta?.resizeAtBytes, let to = meta?.resizedTo, to.count == 2, offset >= at {
                            host.resize(cols: to[0], rows: to[1])
                            resized = true
                        }
                    }
                }
            }
            let snap = clock.measure { for _ in 0..<repeats { _ = host.snapshot() } }
            let grid = host.snapshot()
            let after = ProcessStats.footprint(of: getpid()) ?? 0
            let parseMs = Double(parse.components.seconds) * 1000 + Double(parse.components.attoseconds) / 1e15
            let snapMs = Double(snap.components.seconds) * 1000 + Double(snap.components.attoseconds) / 1e15
            let total = Double(bytes.count * repeats)
            let digest = String(grid.rendered().hashValue, radix: 16).suffix(8)
            results.append(Result(core: name, bytes: bytes.count, repeats: repeats, parseMs: parseMs, snapshotMs: snapMs,
                                  mbPerSecond: total / 1_048_576 / (parseMs / 1000),
                                  footprintDeltaMB: Double(Int64(after) - Int64(before)) / 1_048_576,
                                  scrollbackRows: grid.scrollbackRows, gridDigest: String(digest)))
        }
        if json { printJSON(results) } else {
            for r in results {
                print(String(format: "%-9@ parse %8.1f ms (%6.1f MB/s)   snapshot %5.2f ms/frame   Δfootprint %6.1f MB   scrollback %6d rows   grid %@",
                             r.core as NSString, r.parseMs, r.mbPerSecond, r.snapshotMs / Double(max(1, repeats)),
                             r.footprintDeltaMB, r.scrollbackRows, r.gridDigest as NSString))
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
            if json { printJSON(rows) } else { printRoster(rows, issues: [], hosts: HostConfig.load().config) }
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

    static func printRoster(_ rows: [SessionRow], issues: [RosterShapeIssue], hosts: HostConfig) {
        printRoster(rows.isEmpty ? [] : [RosterSection(title: "", rows: rows)], issues: issues, hosts: hosts)
    }

    /// Sections print as a heading line each (none when untitled); the
    /// columns are sized across the whole roster so headings never shift
    /// them.
    static func printRoster(_ sections: [RosterSection], issues: [RosterShapeIssue], hosts: HostConfig) {
        if !issues.isEmpty {
            print("⚠ roster shape changed: \(issues.map(\.description).joined(separator: "; "))")
        }
        let rows = sections.flatMap(\.rows)
        if rows.isEmpty { print("(no sessions)"); return }
        let width = rows.map { ($0.session.name ?? "").count }.max() ?? 0
        // One Mac prints exactly what v1 printed; the column appears with
        // the second host, and then every id is shown as the ref that
        // `ccc attach` will take.
        let showsHost = rows.contains { $0.host != Host.localName }
        let hostWidth = rows.map(\.host.count).max() ?? 0
        for (i, section) in sections.enumerated() {
        if !section.title.isEmpty { print("\(i == 0 ? "" : "\n")── \(section.title)") }
        for row in section.rows {
            let s = row.session
            // The attached mark, else the pin: one column, the pin is what
            // sorts a row to the top and this is why it is there.
            let marker = row.attached ? "●" : (row.pinned ? "📌" : " ")
            let host = showsHost ? row.host.padding(toLength: hostWidth, withPad: " ", startingAt: 0) + "  " : ""
            // A draft (v5) is `blocked · idle` to the harness and "yours to
            // start" to us; the word replaces both columns.
            let state = row.draft ? "draft" : (s.state?.rawValue ?? (s.kind == .interactive ? "interactive" : "-"))
            let live = row.draft ? "" : (s.pid != nil ? (s.status?.rawValue ?? "live") : "")
            let name = (s.name ?? "").padding(toLength: width, withPad: " ", startingAt: 0)
            let waiting = s.waitingFor.map { " ⏸ \($0)" } ?? ""
            let archived = row.archived ? " (archived)" : ""
            let model = row.model.map { shortModel($0) } ?? "-"
            // The worktree (v6): the repository, then the branch and its
            // standing — the same reading as the window's row.
            let cwd = hosts.shortCwd(row.worktree?.repo ?? s.cwd, host: row.host) + (row.worktree?.baseMark.map { " \($0)" } ?? "")
            let worktree = row.worktree.map { " ⎇ \($0.summary)" } ?? ""
            print("\(marker) \(host)\(s.id.padding(toLength: 8, withPad: " ", startingAt: 0))  \(state.padding(toLength: 11, withPad: " ", startingAt: 0)) \(live.padding(toLength: 4, withPad: " ", startingAt: 0))  \(name)  \(model.padding(toLength: 10, withPad: " ", startingAt: 0))  \(cwd)\(worktree)\(waiting)\(archived)")
        }
        }
    }

    static func shortModel(_ model: String) -> String {
        model.replacingOccurrences(of: "claude-", with: "")
    }

    static func printStats(_ s: StatsInfo) {
        func mb(_ b: UInt64?) -> String { b.map { String(format: "%.1f MB", Double($0) / 1_048_576) } ?? "-" }
        func ms(_ v: Double?) -> String { v.map { String(format: "%.0f ms", $0) } ?? "-" }
        let build = s.build.map { " \($0.short)" } ?? ""
        print("ccc\(build)  pid \(s.pid)  memory \(mb(s.footprintBytes))  uptime \(Int(s.uptimeSeconds))s")
        // The command on PATH and the app on the socket are the same file
        // until an update lands while the app is up; then the difference
        // is a number and a restart, not a "malformed request" on the next
        // new verb.
        let mine = BuildInfo.current
        if let theirs = s.build?.build, let ours = mine.build, theirs != ours {
            let n = abs(ours - theirs), plural = n == 1 ? "" : "s"
            print("  ⚠ this command is \(mine.short); the app on the socket is \(n) build\(plural) \(theirs < ours ? "older — restart it" : "newer")")
        }
        if let child = s.childPID { print("child pid \(child)  memory \(mb(s.childFootprintBytes))") }
        print("roster poll  last \(ms(s.lastPollMs))  mean \(ms(s.meanPollMs))  n=\(s.pollCount)")
        // Per host once there is more than one, or one that is failing:
        // the fleet numbers above are the slowest host's, and this says which.
        if let hosts = s.hosts, hosts.count > 1 || hosts.contains(where: { $0.error != nil }) {
            let width = hosts.map(\.host.count).max() ?? 0
            for h in hosts {
                let name = h.host.padding(toLength: width, withPad: " ", startingAt: 0)
                let evicted = h.evictions > 0 ? "  evictions \(h.evictions)" : ""
                let health = h.error.map { "  FAILING ×\(h.failures)\(h.stale ? " (rows stale)" : ""): \($0)" } ?? ""
                print("  \(name)  last \(ms(h.lastMs))  mean \(ms(h.meanMs))  n=\(h.count)  rows \(h.rows)\(evicted)\(health)")
            }
        }
        if let j = s.modelJoin {
            print("model join   last \(ms(j.lastMs))  mean \(ms(j.meanMs))  reads \(j.reads)  cached \(j.hits)  gone \(j.misses)  well lookups \(j.lookups) (\(j.unresolved) unresolved)")
        }
        if let n = s.notifications {
            // Posted but not authorized is the banner that never reached
            // the screen: say it in the same breath as the count.
            let warn = n.posted > 0 && n.authorization != "authorized" && n.authorization != "provisional"
                ? "  ⚠ events were posted but notifications are \(n.authorization) — none reached the screen" : ""
            let last = n.lastEvent.map { "  last \"\($0)\"" } ?? ""
            let muted = (n.muted ?? []).isEmpty ? "" : "  muted \(n.muted!.joined(separator: ","))"
            print("notifications  \(n.authorization)  posted \(n.posted)\(last)\(muted)\(warn)")
            if let hooks = n.hooks, hooks > 0 {
                let dropped = (n.hooksMuted ?? 0) > 0 ? "  muted \(n.hooksMuted!)" : ""
                let last = n.lastHook.map { "  last \"\($0)\"" } ?? ""
                print("hook events    \(hooks)\(dropped)\(last)")
            }
        }
        print("pty in  \(s.ptyBytesIn) bytes  \(String(format: "%.0f", s.ptyBytesPerSecond)) B/s")
        // The number a black pane cannot hide behind: bytes in but no frames
        // presented means the human sees nothing while snapshots look fine.
        if let frames = s.paneFramesPresented {
            let ago = s.paneLastPresentedSecondsAgo.map { String(format: "%.1f s ago", $0) } ?? "never"
            let warn = s.ptyBytesIn > 0 && frames == 0 ? "  ⚠ bytes arrived but nothing was presented — the pane is black on screen" : ""
            print("pane    \(frames) frames presented  last \(ago)\(warn)")
        }
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
               ccc hosts [list|check [<name>]]     the machines ccc can reach (check runs the real poll)
               ccc hosts add <name> [--ssh <dest>] [--claude <path>] [--ccc <path>|--no-ccc] | remove <name>
                                                  (paths are found on the host unless given)
               ccc hosts reconnect [<name>]        drop the ssh master(s) and poll again (the wake-up gesture)
               ccc hosts mute|unmute <name>        no banners for that host's sessions (rows and counts stay)
               ccc list [--host <name>] [--archived] [--group none|host|repo|state] [--sort activity|name|started|folder] [--json]
                                                  every host's roster; --host narrows to one, --archived shows the
                                                  folded rows (--json always has every row, sorted, never grouped)
               ccc archive|unarchive|pin|unpin <ref>   a mark on a session, kept with the session's host
                                                  (archived rows fold away unless blocked; pinned sort first)
               ccc watch [--host <name>] [--interval S] [--all] [--json]
                                                  one line per transition (blocked, done, failed, stopped);
                                                  muted hosts are skipped unless --all or named with --host
               ccc hook [--settings]              the harness's Notification hook: JSON on stdin → a banner from the app
                                                  for what the roster cannot show; --settings prints the settings.json entry
               ccc attach <ref> [--headless [--cols N --rows N]]
                                                  <ref> is `id` (this Mac) or `host:id`; the pane follows: an attached
                                                  session is left (Ctrl+Z, the harness's detach) for the new one
               ccc snapshot [--json]
               ccc send <text> | --key <name>... | --wheel N | --paste <text>|-
                                                              (N>0 scrolls up; --paste frames as a paste, - reads stdin)
               ccc detach
               ccc spawn [--host <name>] [--cwd <dir>] [--name <n>] [--model <m>] [--agent <a>] [--permission-mode <m>]
                         [--effort <e>] [--worktree[=<name>]] [--from <ref>] [--attach] [--json] [<prompt>... | -]
                                                  `claude --bg` on a host (cwd: here, or the far side's home); the
                                                  prompt is the remaining words, or stdin for `-`; none makes a
                                                  draft that waits for one; --from forks a new session off <ref>'s
                                                  transcript, on its host and in its folder unless told otherwise
                                                  (`--resume <session id> --fork-session`); --attach opens it in the app
               ccc merge <ref> [--ff-only|--no-ff|--squash] [--json]
                                                  land the session's worktree branch on the repo's default branch,
                                                  where the repo is; --ff-only (default) refuses when master moved;
                                                  every strategy refuses a dirty or wrong-branch checkout and backs
                                                  out of a conflict (exit 1 with the reason; nothing is ever lost)
               ccc shell <ref> [--repo] | --close a shell pane under the session pane, in <ref>'s folder (over ssh -t
                                                  when remote) — ⌘T's twin; --repo is the repository's main checkout
                                                  instead of the worktree (⌥⌘T); --close is ⇧⌘T
               ccc push <ref> [--base] [--json]   push the session's worktree branch — or, with --base, the repo's
                                                  default branch — to origin, never forced; git's own refusal is the
                                                  answer (exit 1; nothing changes anywhere)
               ccc rm <ref> [--json]              delete a session and its worktree when the harness says that is safe
               ccc resize <cols> <rows>
               ccc stats [--json]
               ccc peek [out.png]                 PNG of the app window (no screen permission)
               ccc window show|hide|close|resize W H   the window's own gestures (close = Cmd-W)
               ccc replay <bytes-file> [--cols N --rows N --bytes N --core ghostty|swiftterm] [--json]
               ccc bench <bytes-file> [--repeat N --core ghostty|swiftterm] [--json]   parse + snapshot throughput
               ccc version [--json]               this build (version, build number, bundle)
               ccc install-cli [--dir <dir>] [--force]   link `ccc` on PATH into the installed app

        """.utf8))
        return status
    }
}
