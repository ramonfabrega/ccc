import CCCKit
import Foundation

/// The command face. Each verb is a click's twin.
///
///   ccc hosts [add|remove|check|discover]  the machines ccc can reach
///   ccc list [--json]                 the roster, with the model and `rc` columns
///   ccc archive|unarchive|pin|unpin <ref>   our marks on a session (v4) — the context menu's twin
///   ccc watch [--json]                one line per transition — the notification's twin
///   ccc attach <ref> [--headless]     attach; headless drives a PTY and serves the socket
///   ccc spawn [--host <name>] [--cwd <dir>] [--from <ref>] [<prompt>… | -]   `claude --bg` on a host (v5) — the New Session sheet's twin
///
/// A `<ref>` is `id` (this Mac) or `host:id` (any host in `ccc hosts`).
///   ccc snapshot [--json]             the pane's grid as text
///   ccc send <text> | --key <name>… | --paste <text>   type into the pane
///   ccc detach                        detach the pane
///   ccc focus [in|out]                DEC 1004 focus, the window's twin — what decides
///                                     whether the harness suppresses your phone's push
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
        // Item 22: a verb's own `--help` beats the verb. It is checked
        // here rather than inside each parser because "unknown flag
        // '--help' for spawn" was one parser's honest answer to a question
        // the CLI had never been taught — and teaching thirty parsers the
        // same thing is how they disagree.
        if rest.contains("--help") || rest.contains("-h"), CommandManifest.verb(named: verb) != nil {
            return help(for: verb)
        }
        do {
            switch verb {
            case "help", "--help", "-h":
                // `ccc help spawn` and `ccc --help spawn` are the same ask.
                if let word = rest.first(where: { !$0.hasPrefix("-") }) { return help(for: word) }
                return usage(to: .standardOutput, status: 0)
            case "--llms", "llms":
                print(CommandManifest.llms())
                return 0
            case "--schema", "schema":
                // The manifest as JSON: the thing an agent reads once and
                // then never has to guess a flag from prose again.
                if let word = rest.first(where: { !$0.hasPrefix("-") }) {
                    guard let one = CommandManifest.verb(named: word) else {
                        stderr("ccc: no verb '\(word)' (try `ccc --schema`)")
                        return 2
                    }
                    printJSON(one)
                } else {
                    printJSON(CommandManifest.verbs)
                }
                return 0
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
                                      group: group, sort: sort, fresh: rest.contains("--fresh"), json: json)
            case "watch":
                return try await watch(host: stringFlag("--host", rest), interval: intFlag("--interval", rest) ?? 2,
                                       all: rest.contains("--all"),
                                       stall: intFlag("--stall", rest).map { StallWindow(minutes: Double($0)) },
                                       json: json)
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
                    guard let grid = gridFlags(rest, cols: 120, rows: 40) else { return 2 }
                    return Headless.run(ref: ref, cols: grid.cols, rows: grid.rows)
                }
                return try request(.attach(id: ref), json: json)
            case "rm":
                guard let text = rest.first(where: { !$0.hasPrefix("--") }) else { return usage() }
                guard let ref = SessionRef.parse(text) else {
                    stderr("ccc: '\(text)' is not a session ref (id, or host:id)")
                    return 2
                }
                return try await rm(ref: ref, json: json)
            case "stop":
                guard let text = rest.first(where: { !$0.hasPrefix("--") }) else { return usage() }
                guard let ref = SessionRef.parse(text) else {
                    stderr("ccc: '\(text)' is not a session ref (id, or host:id)")
                    return 2
                }
                return try await stop(ref: ref, json: json)
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
            case "update":
                guard let text = rest.first(where: { !$0.hasPrefix("--") }) else { return usage() }
                guard let ref = SessionRef.parse(text) else {
                    stderr("ccc: '\(text)' is not a session ref (id, or host:id)")
                    return 2
                }
                for flag in rest.filter({ $0.hasPrefix("--") }) where flag != "--ask" && flag != "--json" {
                    stderr("ccc: unknown flag '\(flag)' (--ask)")
                    return 2
                }
                return try await update(ref: ref, ask: rest.contains("--ask"), json: json)
            case "fetch", "pull":
                guard let text = rest.first(where: { !$0.hasPrefix("--") }) else { return usage() }
                guard let ref = SessionRef.parse(text) else {
                    stderr("ccc: '\(text)' is not a session ref (id, or host:id)")
                    return 2
                }
                for flag in rest.filter({ $0.hasPrefix("--") }) where flag != "--json" {
                    stderr("ccc: unknown flag '\(flag)'")
                    return 2
                }
                return try await originVerb(verb, ref: ref, json: json)
            case "archive", "unarchive", "pin", "unpin":
                guard let text = rest.first(where: { !$0.hasPrefix("--") }) else { return usage() }
                guard let ref = SessionRef.parse(text) else {
                    stderr("ccc: '\(text)' is not a session ref (id, or host:id)")
                    return 2
                }
                return try await mark(MarkChange(rawValue: verb)!, ref: ref, json: json)
            case "base":
                // `ccc base <ref>` reads, `ccc base <ref> <branch>` records,
                // `ccc base <ref> --clear` forgets (item 18).
                let words = rest.filter { !$0.hasPrefix("--") }
                guard let text = words.first else { return usage() }
                guard let ref = SessionRef.parse(text) else {
                    stderr("ccc: '\(text)' is not a session ref (id, or host:id)")
                    return 2
                }
                return try await base(ref: ref, set: words.dropFirst().first, clear: rest.contains("--clear"), json: json)
            case "snapshot":
                // `--color` asks for resolved RGB alongside the text (item
                // 12a): the headless oracle's half of the pair whose other
                // half is `ccc pixel`, and it spells a colour the same way.
                return try request(.snapshot(colors: args.contains("--color")), json: json)
            case "links":
                // `ccc links` lists; `ccc links --open N` opens the Nth,
                // which is the ⌘-click on that link.
                var open: Int?
                if let flag = rest.firstIndex(of: "--open") {
                    guard let n = rest.dropFirst(flag + 1).first.flatMap({ Int($0) }) else {
                        stderr("ccc: --open needs a link number (ccc links to see them)")
                        return 2
                    }
                    open = n
                }
                return try request(.links(open: open), json: json)
            case "send":
                return try send(rest, json: json)
            case "detach":
                return try request(.detach, json: json)
            case "resize":
                guard let cols = rest.first.flatMap({ Int($0) }), let rows = rest.dropFirst().first.flatMap({ Int($0) }) else { return usage() }
                guard cols >= 1, rows >= 1 else {
                    stderr("ccc: cols and rows must be at least 1 (got \(cols)x\(rows))")
                    return 2
                }
                return try request(.resize(cols: cols, rows: rows), json: json)
            case "select":
                // `ccc select COL ROW COL ROW [--rect]`, both ends inclusive;
                // `ccc select --clear` puts it back. `--word` and `--line`
                // are the double- and triple-click's twins and take one
                // point, so `ccc select --word 6 0` is a double-click there;
                // a second point drags the grain across, as the gesture does.
                if rest.contains("--clear") { return try request(.select(region: nil), json: json) }
                let grain: SelectionRegion.Grain? =
                    rest.contains("--word") ? .word : (rest.contains("--line") ? .line : nil)
                let numbers = rest.filter { !$0.hasPrefix("--") }.compactMap { Int($0) }
                // A grained selection may name one point (the click) or two
                // (the drag); a cell selection is always two corners.
                let points: [Int]
                switch (grain, numbers.count) {
                case (_, 4): points = numbers
                case (.some, 2): points = numbers + numbers
                default: return usage()
                }
                return try request(.select(region: SelectionRegion(
                    fromCol: points[0], fromRow: points[1], toCol: points[2], toRow: points[3],
                    rectangle: rest.contains("--rect"), grain: grain)), json: json)
            case "copy":
                return try request(.copy, json: json)
            case "stats":
                return try request(.stats, json: json)
            case "peek":
                return try peek(to: rest.first(where: { !$0.hasPrefix("--") }))
            case "geometry":
                return try request(.geometry, json: json)
            case "capture":
                return try await capture(to: rest.first(where: { !$0.hasPrefix("--") }), json: json)
            case "pixel":
                return try pixel(rest, json: json)
            case "theme":
                return theme(json: json)
            case "bench":
                guard let path = rest.first(where: { !$0.hasPrefix("--") }) else { return usage() }
                guard let grid = gridFlags(rest, cols: 100, rows: 30) else { return 2 }
                return try await bench(path: path, cols: grid.cols, rows: grid.rows,
                                       repeats: intFlag("--repeat", rest) ?? 200, core: stringFlag("--core", rest), json: json)
            case "window":
                // The grammar is `WindowAction`'s, not a second copy of it:
                // a gesture that is added there is accepted here the same
                // day, with the same arity and the same refusal.
                let words = rest.filter { !$0.hasPrefix("--") }
                guard let action = WindowAction(words.joined(separator: " ")) else { return usage() }
                return try request(.window(action: action.text), json: json)
            case "focus":
                // `ccc focus` reads, `ccc focus in|out` asserts. The verb
                // exists because the state it drives is invisible here and
                // visible on a phone (item 17 slice 2).
                let words = rest.filter { !$0.hasPrefix("--") }
                switch words.first {
                case nil: return try request(.focus(), json: json)
                case "in": return try request(.focus(focused: true), json: json)
                case "out": return try request(.focus(focused: false), json: json)
                default: return usage()
                }
            case "replay":
                guard let path = rest.first(where: { !$0.hasPrefix("--") }) else { return usage() }
                guard let grid = gridFlags(rest, cols: 100, rows: 30) else { return 2 }
                return try await replay(path: path, cols: grid.cols, rows: grid.rows,
                                        bytes: intFlag("--bytes", rest), core: stringFlag("--core", rest) ?? "ghostty", json: json,
                                        colors: rest.contains("--color"))
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
    ///
    /// **Answered by the running app when there is one** (item 4). The
    /// window already holds every host's slot, at most one tick old, with
    /// every join warm; a fresh `ccc list` process redid all of it cold —
    /// 450–670 ms here against the app's 190 ms tick — and that cold
    /// process is exactly what the far side runs on every poll, which is
    /// why air's poll cost a whole tick. `--fresh` asks the app to poll
    /// once more first; with no app on the socket the tick is ours, as
    /// it always was. What the far side reads is the *same* roster the
    /// window shows, which is the twin rule stated as a fact.
    static func list(host name: String?, archived: Bool = false, group: RosterGroup = .none,
                     sort: RosterSort = .activity, fresh: Bool = false, json: Bool) async throws -> Int32 {
        let loaded = HostConfig.load()
        for issue in loaded.issues { stderr("ccc: \(issue)") }
        if let name, loaded.config.host(named: name) == nil {
            stderr("ccc: unknown host '\(name)' (known: \(loaded.config.hosts.map(\.name).joined(separator: ", ")))")
            return 2
        }
        let state: RosterPoller.State
        if let served = rosterFromApp(host: name, fresh: fresh) {
            state = served
        } else {
            let poller: RosterPoller
            if let name, let host = loaded.config.host(named: name) {
                guard let cli = ClaudeCLI.of(host) else {
                    stderr("ccc: \(host.validate() ?? "claude not found for host '\(name)'")")
                    return 1
                }
                poller = RosterPoller(cli: cli)
            } else {
                poller = RosterPoller(hosts: loaded.config)
            }
            await poller.tick()
            state = poller.state
        }
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

    /// The app's slots over the socket, narrowed to `host` when asked.
    /// `nil` when no app is serving, when the one serving is older than
    /// the `roster` request (it answers "malformed request"), or when it
    /// does not know the host — every one of which means "poll it
    /// yourself", never an error: the CLI has always worked without the
    /// app and still does.
    static func rosterFromApp(host: String?, fresh: Bool) -> RosterPoller.State? {
        guard let response = try? ControlClient().send(.roster(fresh: fresh ? true : nil)),
              case .roster(let hosts) = response else { return nil }
        // An app that has not finished its first tick has nothing to
        // show yet; that is not a roster, so poll it here.
        guard hosts.contains(where: { $0.pollCount > 0 }) else { return nil }
        guard let host else { return RosterPoller.State(hosts: hosts) }
        guard let slot = hosts.first(where: { $0.host == host }) else { return nil }
        return RosterPoller.State(hosts: [slot])
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

    /// `ccc base <ref> [<branch> | --clear]` (item 18): what a session's
    /// worktree branch is measured against, and the one write the column
    /// owes — record a base for a worktree cut by hand, or forget one.
    static func base(ref: SessionRef, set: String?, clear: Bool, json: Bool) async throws -> Int32 {
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
        let reading: ClaudeCLI.BaseReading
        do {
            reading = try await cli.base(id: ref.id, set: set, clear: clear)
        } catch {
            stderr("ccc: \(error)")
            return 1
        }
        if json { printJSON(reading) } else { print(reading.said) }
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

    /// `ccc update <ref> [--ask]` (v6 slice 6): merge the session's base
    /// — recorded for the branch, else the repository's default branch —
    /// into its worktree branch, in the worktree, where it is.
    ///
    /// **This is the git verb a session has for its own base** (item 20).
    /// On 2026-09-06 a worker's `git merge --no-edit origin/<its base>`
    /// was refused by the auto-mode permission classifier and handed back
    /// to its commander, which was the right failure — and it happened
    /// while a verb that does exactly that, with guards the raw merge has
    /// not, sat one word away. Two things had made it unfindable: this
    /// help said "the repo's default branch" long after v0.1.25 taught it
    /// the recorded base, and it merged the local ref while the worker
    /// wanted origin's. Both are fixed; briefs should say `ccc update`. Exit 0 when it merged, 1 when it refused
    /// or backed out of a conflict; `--json` carries `ask` on a conflict,
    /// the prompt a session could be given, and `--ask` gives it — the
    /// pane attaches to the session and types it (needs the app). The
    /// exit stays 1 then: the update itself did not happen.
    static func update(ref: SessionRef, ask: Bool, json: Bool) async throws -> Int32 {
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
        let outcome = try await cli.update(id: ref.id)
        var asked: String?
        if ask, let prompt = outcome.ask {
            switch try ControlClient().send(.ask(id: ref, prompt: prompt)) {
            case .ok(let message): asked = message
            case .error(let message): stderr("ccc: \(message)")
            default: stderr("ccc: unexpected response to ask")
            }
        }
        if json {
            var object = ["ref": ref.description, "updated": outcome.merged ? "true" : "false", "said": outcome.said]
            if let prompt = outcome.ask { object["ask"] = prompt }
            if let asked { object["asked"] = asked }
            printJSON(object)
        } else {
            print(outcome.said)
            if let asked { print(asked) }
        }
        return outcome.merged ? 0 : 1
    }

    /// `ccc fetch <ref>` and `ccc pull <ref>` (v6 slice 7): the
    /// repository's one network call, and master's fast-forward from
    /// origin. Exit 0 when it did, 1 when it refused (the sentence says
    /// why); the far side's own verb for a remote ref.
    static func originVerb(_ verb: String, ref: SessionRef, json: Bool) async throws -> Int32 {
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
        let outcome = verb == "fetch" ? try await cli.fetch(id: ref.id) : try await cli.pull(id: ref.id)
        if json {
            printJSON(["ref": ref.description, verb == "fetch" ? "fetched" : "pulled": outcome.merged ? "true" : "false", "said": outcome.said])
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

    /// Stop a session: `claude stop` behind the ref's host prefix. The
    /// conversation and the worktree both stay — `rm` is the one that
    /// deletes. `stopped` has been a state on every row since v1 with no
    /// verb to produce it; this is that verb, and `spawn --replace` is its
    /// first caller.
    static func stop(ref: SessionRef, json: Bool) async throws -> Int32 {
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
        let result = try await cli.stop(id: ref.id)
        if json {
            printJSON(["ref": ref.description, "stopped": result.stopped ? "true" : "false", "said": result.said])
        } else {
            print(result.said)
        }
        return result.stopped ? 0 : 1
    }

    /// `ccc spawn` (v5): `claude --bg` on a host, the New Session sheet's
    /// twin. Needs no running app; `--attach` then asks the app to attach,
    /// the way `ccc attach` does. The prompt is every word that is not a
    /// flag, joined by spaces — or stdin when that one word is `-`, which
    /// is how an agent hands over a prompt with its newlines intact. No
    /// prompt is the draft: the session registers and waits for one.
    static func spawn(_ args: [String], json: Bool) async throws -> Int32 {
        let valued = ["--host", "--cwd", "--name", "--model", "--agent", "--permission-mode", "--effort", "--from", "--base"]
        var spec = SpawnRequest()
        var hostFlag: String?
        var from: SessionRef?
        var attach = false
        var replace = false
        var allowDuplicate = false
        var noSpaceCheck = false
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
                case "--base": spec.base = value
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
            case "--rc", "--remote-control": spec.rc = true
            // The two guards' escape hatches (item 19). ccc refuses; it
            // never forbids, so each refusal names the flag that means it.
            case "--replace": replace = true
            case "--allow-duplicate": allowDuplicate = true
            case "--no-space-check": noSpaceCheck = true
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
        // One poll answers both the fork's lookup and the name guard, so a
        // named spawn costs one `claude agents --json` and no more.
        var rows: [SessionRow]?
        if from != nil || (spec.name?.isEmpty == false && !allowDuplicate) {
            let poller = RosterPoller(cli: cli)
            await poller.tick()
            if let failed = poller.state.failures.first {
                // A roster ccc cannot read is not a reason to refuse a
                // spawn — it is a reason to say so and let the fork's
                // lookup, which genuinely needs it, be the one that fails.
                if from != nil {
                    stderr("ccc: \(failed.host): \(failed.error ?? "unreachable")")
                    return 1
                }
                stderr("ccc: \(failed.host): \(failed.error ?? "unreachable") — spawning without the name check")
            } else {
                rows = poller.state.rows
            }
        }
        // The source's row: `--resume` needs the full session id (the
        // short one opens the harness's picker — docs/HARNESS.md), and the
        // row is where that id and the source's folder are.
        if let from {
            guard let row = (rows ?? []).first(where: { $0.ref == from }) else {
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
        // Item 19a: a live job already answering to this name. The cwd the
        // guard compares is the one the session will run in — which is not
        // `spec.cwd` when a worktree is about to be cut, so that case
        // reports no folder rather than the wrong one.
        if let rows, !allowDuplicate {
            let landing = (spec.worktree == nil && spec.base == nil) ? spec.cwd : nil
            if let held = SpawnGuard.nameHolder(for: spec, on: host.name, cwd: landing, rows: rows) {
                guard replace else {
                    stderr("ccc: \(held.said)")
                    return 1
                }
                let stopped = try await cli.stop(id: held.ref.id)
                guard stopped.stopped else {
                    stderr("ccc: --replace could not stop \(held.ref): \(stopped.said)")
                    return 1
                }
                stderr("ccc: stopped \(held.ref) (\(held.name)) before respawning it")
            }
        }
        // Item 19b: the disk the session would land on. Local only — the
        // far side's ccc guards its own volume, and a `df` over ssh would
        // put a round trip in front of every remote spawn.
        if !noSpaceCheck, host.isLocal {
            let probe = spec.cwd ?? FileManager.default.currentDirectoryPath
            if let refusal = SpawnGuard.spaceRefusal(SpawnGuard.space(at: probe), floorGB: SpawnGuard.floorGB()) {
                stderr("ccc: \(refusal)")
                return 1
            }
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
    static func watch(host name: String?, interval: Int, all: Bool,
                      stall: StallWindow? = nil, json: Bool) async throws -> Int32 {
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
        var detector = TransitionDetector(stallWindow: stall ?? .fromEnvironment())
        await poller.tick()
        var state = poller.state
        for failed in state.failures { stderr("ccc: \(failed.host): \(failed.error ?? "unreachable")") }
        guard state.anyHostAnswered else { return 1 }
        _ = detector.observe(state)
        let blocked = state.rows.filter(\.isWaiting)
        let muted = filter.mutedHosts
        // Standing stalls are context, not news (`StallWindow`): a session
        // still for two days when the watch starts is a thing to know now,
        // and firing it as an event would be indistinguishable from one
        // that stalled while you watched.
        let standing = state.standingStalls(detector.stallWindow)
        let hostCount = config.hosts.count
        var opening = "ccc: watching \(hostCount) host\(hostCount == 1 ? "" : "s"), \(state.rows.count) sessions, \(blocked.count) blocked"
        if !blocked.isEmpty {
            let names: [String] = blocked.map { $0.session.name ?? $0.ref.description }
            opening += ": " + names.joined(separator: ", ")
        }
        if !standing.isEmpty {
            let names: [String] = standing.map { "\($0.row.session.name ?? $0.row.ref.description) (\(SessionEvent.spell($0.still)))" }
            opening += "; already still: " + names.joined(separator: ", ")
        }
        if !muted.isEmpty {
            opening += "; muted: " + muted.joined(separator: ", ") + " (--all hears them)"
        }
        stderr(opening)
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
                    print("\(clock.string(from: event.at))  \(event.mark) \(event.kind.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0))  \(event.ref.description.padding(toLength: 14, withPad: " ", startingAt: 0))  \(event.watchLine)")
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
                stderr("ccc: usage: ccc hosts add <name> [--ssh <destination>] [--claude <absolute path>]")
                return 2
            }
            // The add itself is `HostSetup.add`, shared with the app's
            // picker so the two cannot drift about what a host needs
            // (CLAUDE.md: one definition, many surfaces). This case reads
            // flags and prints; it decides nothing.
            switch await HostSetup.add(
                name: name,
                ssh: stringFlag("--ssh", rest),
                claude: stringFlag("--claude", rest),
                ccc: stringFlag("--ccc", rest),
                wantCCC: !rest.contains("--no-ccc")
            ) {
            case .failure(let problem):
                stderr("ccc: \(problem)")
                if case .invalid = problem { return 2 }
                return 1
            case .success(let added):
                let host = added.host
                let reader = host.ccc.map { "ccc \($0)" } ?? "claude agents (no model column)"
                let home = host.home.map { ", home \($0)" } ?? ", home unknown (`ccc hosts check` learns it)"
                print("added \(name) (ssh \(host.ssh ?? "-"), claude \(host.claude ?? "-"), roster via \(reader)\(home)); `ccc hosts check \(name)` to prove it")
                for note in added.notes { stderr("ccc: \(note)") }
                return 0
            }

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
                        // Element-wise, as the poller reads it: a row this
                        // build cannot read is counted and named, not fatal.
                        let elements = try JSONDecoder.roster.decode([LenientElement<SessionRow>].self, from: reading.data)
                        let rows = elements.compactMap(\.value)
                        let unread = elements.compactMap(\.error)
                        var said = reading.warning
                        if !unread.isEmpty {
                            said = ((said.map { $0 + "; " }) ?? "") + "\(unread.count) row\(unread.count == 1 ? "" : "s") this build cannot read (\(unread[0]))"
                        }
                        var check = Check(host: host.name, ok: true, ms: ms, reader: reader,
                                          sessions: rows.count, models: rows.count { $0.model != nil },
                                          home: home, error: said)
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

        case "discover":
            // The picker's twin (queue item 3): what Macs are on the tailnet
            // and which of them ccc already has. It enumerates and stops
            // there — `hosts add` is what probes over the real ssh and
            // refuses a machine that cannot answer `claude`, so nothing here
            // has to guess who runs an sshd. Nothing in `tailscale status`
            // says, either (measured 2026-09-04).
            let peers: [Tailnet.Peer]
            do {
                peers = try Tailnet.scan()
            } catch {
                stderr("ccc: \(error)")
                return 1
            }
            let known = Set(loaded.config.hosts.compactMap { $0.ssh })
            let knownNames = Set(loaded.config.hosts.map(\.name))
            struct Row: Encodable {
                var name: String, dnsName: String, hostName: String
                var online: Bool, isSelf: Bool, added: Bool
                var lastSeen: Date?
            }
            let rows = peers.map {
                Row(name: $0.name, dnsName: $0.dnsName, hostName: $0.hostName,
                    online: $0.online, isSelf: $0.isSelf,
                    added: known.contains($0.dnsName) || known.contains($0.name) || knownNames.contains($0.name),
                    lastSeen: $0.lastSeen)
            }
            if json { printJSON(rows); return 0 }
            guard !rows.isEmpty else {
                print("no Macs on the tailnet besides this one")
                return 0
            }
            let width = rows.map(\.name.count).max() ?? 0
            for row in rows {
                let name = row.name.padding(toLength: width, withPad: " ", startingAt: 0)
                var note = row.isSelf ? "  this Mac" : ""
                if row.added { note += "  (added)" }
                if !row.online {
                    let when = row.lastSeen.map { "last seen \(Self.ago($0))" } ?? "offline"
                    note += "  \(when)"
                }
                print("\(name)  \(row.dnsName)  \(row.hostName)\(note)")
            }
            // The short label, not the full MagicDNS name: known_hosts and
            // ~/.ssh/config are keyed on what a human types, and `--ssh`
            // defaults to the name, so there is nothing to pass.
            print("\n`ccc hosts add <name>` to add one; it probes for claude over the real ssh before it saves")
            return 0

        default:
            stderr("ccc: unknown hosts action '\(action)' (list|discover|add|remove|check|reconnect|mute|unmute)")
            return 2
        }
    }

    /// Rough age for a `LastSeen`, in the words a listing wants. Coarse on
    /// purpose: the question a dead peer answers is "months or minutes",
    /// never "how many days exactly".
    static func ago(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        switch seconds {
        case ..<90: return "just now"
        case ..<5400: return "\(Int(seconds / 60)) minutes ago"
        case ..<172_800: return "\(Int(seconds / 3600)) hours ago"
        case ..<5_184_000: return "\(Int(seconds / 86400)) days ago"
        default: return "\(Int(seconds / 2_592_000)) months ago"
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
    static func replay(path: String, cols: Int, rows: Int, bytes limit: Int?, core: String, json: Bool,
                       colors: Bool = false) async throws -> Int32 {
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
        let grid = host.snapshot(colors: colors)
        if colors && grid.colors == nil {
            stderr("ccc: core '\(core)' carries no colour; the grid is text only")
        }
        if json { printJSON(grid) } else { print(grid.rendered()) }
        return 0
    }

    /// The window as PNG, written to `path` (default: a temp file), path printed.
    /// The presentation oracle's twin (v8 slice 3).
    ///
    /// `peek` composites the pane from an offscreen render, so it can show
    /// a perfect TUI over a pane that is black on screen — it did, for a
    /// day (docs/DESIGN.md §7). This is the other one: `screencapture -l`
    /// against the window's real `CGWindowID`, so what lands in the file is
    /// what a camera pointed at the display would see.
    ///
    /// The capture runs *here*, not in the app, deliberately. Screen
    /// Recording permission belongs to whoever asks — this terminal, or an
    /// agent's shell — and doing it in the app would put the app behind
    /// that prompt forever, including for `peek`, which needs no permission
    /// at all. The split is the point: `peek` always works, `capture`
    /// tells the truth.
    static func capture(to path: String?, json: Bool) async throws -> Int32 {
        let response = try ControlClient().send(.geometry)
        guard case .geometry(let geometry) = response else {
            if case .error(let message) = response { stderr("ccc: \(message)") } else {
                stderr("ccc: unexpected geometry response")
            }
            return 1
        }
        let out = path ?? NSTemporaryDirectory() + "ccc-capture-\(Int(Date().timeIntervalSince1970)).png"
        // -l one window, -o no shadow (the shadow is not the window and
        // would offset every pixel in it), -x no shutter sound.
        // Through `Subprocess`, which drains both pipes before waiting;
        // the old shape waited first and read stderr after, which hangs
        // the day the child says more than a pipe holds.
        let shot = try await Subprocess.run(["/usr/sbin/screencapture", "-l", "\(geometry.windowID)", "-o", "-x", out])
        let said = String(decoding: shot.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard shot.status == 0, FileManager.default.fileExists(atPath: out) else {
            stderr("""
                ccc: screencapture failed\(said.isEmpty ? "" : " (\(said))"); \
                window \(geometry.windowID). Screen Recording permission belongs to \
                whoever runs this — grant it in System Settings ▸ Privacy & Security \
                ▸ Screen Recording for this terminal. `ccc peek` needs no permission.
                """)
            return 1
        }
        if json {
            printJSON(CaptureInfo(path: out, geometry: geometry))
        } else {
            print(out)
        }
        return 0
    }

    struct CaptureInfo: Codable {
        var path: String
        var geometry: WindowGeometry
    }

    /// Read one colour out of an image, and optionally judge it.
    ///
    /// The queue's other half of item 10: nothing in the repo could turn a
    /// PNG into a number, so every colour question ended with a human
    /// looking at a picture. `--cell` is the useful form — it asks the
    /// running app where the pane is and how big a cell is, so "what
    /// colour is the top-left cell" is one command rather than arithmetic
    /// done by hand.
    static func pixel(_ rest: [String], json: Bool) throws -> Int32 {
        guard let file = rest.first(where: { !$0.hasPrefix("--") }) else { return usage() }
        guard let data = FileManager.default.contents(atPath: file) else {
            stderr("ccc: cannot read '\(file)'")
            return 2
        }
        let image: PixelReader.Image
        do { image = try PixelReader.decode(data) } catch {
            stderr("ccc: \(error)")
            return 2
        }

        var x: Int, y: Int
        if let cell = pairFlag("--cell", rest) {
            let response = try ControlClient().send(.geometry)
            guard case .geometry(let geometry) = response else {
                if case .error(let message) = response { stderr("ccc: \(message)") } else {
                    stderr("ccc: unexpected geometry response")
                }
                return 1
            }
            guard let pane = geometry.pane else {
                stderr("ccc: nothing attached, so there is no grid to take a cell from")
                return 1
            }
            guard cell.0 >= 0, cell.0 < pane.cols, cell.1 >= 0, cell.1 < pane.rows else {
                stderr("ccc: no cell \(cell.0),\(cell.1); the grid is \(pane.cols)x\(pane.rows)")
                return 2
            }
            (x, y) = pane.pixel(col: cell.0, row: cell.1, scale: geometry.scale)
        } else if let at = pairFlag("--at", rest) {
            (x, y) = at
        } else {
            stderr("ccc: pixel needs --cell <col> <row> or --at <x> <y>")
            return 2
        }

        guard let colour = image.rgb(x: x, y: y) else {
            stderr("ccc: no pixel \(x),\(y); the image is \(image.width)x\(image.height)")
            return 2
        }
        let hex = PixelReader.hex(colour)

        // `--expect` is what makes this a judgement rather than a reading:
        // the exit code is the answer, so a script can assert a colour.
        if let wanted = stringFlag("--expect", rest) {
            guard let expected = PixelReader.parse(hex: wanted) else {
                stderr("ccc: '\(wanted)' is not a colour (#RRGGBB)")
                return 2
            }
            let tolerance = intFlag("--tolerance", rest) ?? 0
            let off = PixelReader.distance(colour, expected)
            let ok = off <= tolerance
            if json {
                printJSON(PixelInfo(x: x, y: y, hex: hex, r: Int(colour.r), g: Int(colour.g), b: Int(colour.b),
                                    expected: PixelReader.hex(expected), off: off, ok: ok))
            } else if ok {
                print("\(hex) at \(x),\(y) — matches \(PixelReader.hex(expected))\(tolerance > 0 ? " (within \(tolerance))" : "")")
            } else {
                stderr("ccc: \(hex) at \(x),\(y) — expected \(PixelReader.hex(expected)), off by \(off)")
            }
            return ok ? 0 : 1
        }

        if json {
            printJSON(PixelInfo(x: x, y: y, hex: hex, r: Int(colour.r), g: Int(colour.g), b: Int(colour.b)))
        } else {
            print("\(hex)  rgb(\(colour.r), \(colour.g), \(colour.b))  at \(x),\(y)")
        }
        return 0
    }

    struct PixelInfo: Codable {
        var x: Int
        var y: Int
        var hex: String
        var r: Int, g: Int, b: Int
        var expected: String?
        var off: Int?
        var ok: Bool?

        init(x: Int, y: Int, hex: String, r: Int, g: Int, b: Int,
             expected: String? = nil, off: Int? = nil, ok: Bool? = nil) {
            self.x = x; self.y = y; self.hex = hex
            self.r = r; self.g = g; self.b = b
            self.expected = expected; self.off = off; self.ok = ok
        }
    }

    /// Two integers after a flag (`--cell 3 5`), spelled the way `resize`
    /// takes its pair rather than as a comma-joined string.
    static func pairFlag(_ name: String, _ args: [String]) -> (Int, Int)? {
        guard let i = args.firstIndex(of: name), i + 2 < args.count,
              let a = Int(args[i + 1]), let b = Int(args[i + 2]) else { return nil }
        return (a, b)
    }

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

    /// The pane's colours, as text or as the JSON `CCC_THEME` reads back.
    ///
    /// The command twin of a thing with no gesture yet: there is no colour
    /// picker, so this is the only surface that answers "what are my
    /// colours", and `--json` is the file to copy, edit and point
    /// `CCC_THEME` at. Slots 16–255 are not printed because they are not a
    /// choice — the xterm cube and grey ramp, seeded from the core.
    static func theme(json: Bool) -> Int32 {
        let theme = Theme.active
        if json { printJSON(theme); return 0 }

        let names = [
            "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
            "bright black", "bright red", "bright green", "bright yellow",
            "bright blue", "bright magenta", "bright cyan", "bright white",
        ]
        var out = "\(theme.name)\n\n"
        for (index, colour) in theme.ansi.enumerated() {
            // A swatch of the colour itself: the point of looking is to see it.
            let swatch = "\u{1b}[48;2;\(colour.r);\(colour.g);\(colour.b)m  \u{1b}[0m"
            out += String(format: "  %@  %3d  %@  %@\n", swatch, index, colour.hex, names[index])
        }
        out += "\n"
        for (label, colour) in [
            ("background", theme.background), ("foreground", theme.foreground),
            ("cursor", theme.cursor), ("cursor text", theme.cursorText),
            ("selection", theme.selectionBackground), ("selected text", theme.selectionForeground),
        ] {
            let swatch = "\u{1b}[48;2;\(colour.r);\(colour.g);\(colour.b)m  \u{1b}[0m"
            out += String(format: "  %@       %@  %@\n", swatch, colour.hex, label)
        }
        // Item 12b drew it; item 13 gave it a hand. The note said neither.
        out += "\n  selection: shift-drag the pane (⌥ for a rectangle), or `ccc select`\n"
        // The one theme value that is a policy rather than a colour, so it
        // has to be said in words: it is why bold red reads as slot 9 above
        // and not slot 1, which is otherwise an unexplained difference
        // between this table and the screen (item 12c).
        out += "  bold is bright: \(theme.boldIsBright ? "on" : "off")"
            + " — bold text wearing colours 0–7 paints 8–15\n"
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
        case .roster(let hosts):
            // `ccc list` reads this through `rosterFromApp`; here it is the
            // raw slots, for a script that wants the app's own numbers.
            let state = RosterPoller.State(hosts: hosts)
            if json { printJSON(hosts) } else { printRoster(state.sorted, issues: state.issues, hosts: HostConfig.load().config) }
        case .snapshot(let info):
            if json { printJSON(info) } else if let grid = info.grid { print(grid.rendered()) } else { print("(nothing attached)") }
        case .links(let found):
            if json {
                printJSON(found)
            } else if found.isEmpty {
                print("(no links on the grid)")
            } else {
                // 1-based, matching what --open takes.
                for (i, link) in found.enumerated() {
                    print("\(i + 1)  \(link.url)  (row \(link.row), col \(link.col))")
                }
            }
        case .stats(let stats):
            if json { printJSON(stats) } else { printStats(stats) }
        case .geometry(let geometry):
            if json { printJSON(geometry) } else {
                // The state first when it is not the ordinary one: a frame
                // for a window nobody can see is a number that lies.
                let state = [geometry.visible ? nil : "hidden", geometry.minimized ? "minimized" : nil,
                             geometry.fullScreen ? "full screen" : (geometry.zoomed ? "zoomed" : nil)].compactMap { $0 }
                print("window \(geometry.windowID)  \(Int(geometry.x)),\(Int(geometry.y))  \(Int(geometry.width))x\(Int(geometry.height))pt  @\(geometry.scale)x\(state.isEmpty ? "" : "  " + state.joined(separator: " "))")
                print("roster \(Int(geometry.rosterWidth))pt wide")
                if let pane = geometry.pane {
                    print("pane   \(Int(pane.x)),\(Int(pane.y))  \(Int(pane.width))x\(Int(pane.height))pt  \(pane.cols)x\(pane.rows) cells  cell \(pane.cellWidth)x\(pane.cellHeight)pt")
                } else {
                    print("pane   (nothing attached)")
                }
            }
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
            // Only when nothing better follows on the ↳ line: `waitingFor`
            // is often the placeholder "input needed", and printing that
            // directly above the actual question is the redundancy this
            // slice deletes. Same rule as the window's row.
            let say = row.say.flatMap { $0 == s.waitingFor ? nil : $0 }
            let waiting = say == nil ? (s.waitingFor.map { " ⏸ \($0)" } ?? "") : ""
            let archived = row.archived ? " (archived)" : ""
            let model = row.model.map { shortModel($0) } ?? "-"
            // Remote Control (item 17): this session was dispatched `--rc`,
            // so it is answerable from the phone and not only from here.
            // Two narrow ASCII columns rather than a glyph, for the reason
            // the rest of this line is columns at all — an emoji is two
            // cells in some terminals and one in others, and this row is
            // aligned. The word is the flag the user typed, so nothing has
            // to be looked up to read it.
            let rc = (row.job?.remoteControl ?? false) ? "rc" : "  "
            // Launched without a mode that answers for itself: this one
            // stops at its first permission prompt, which on a phone is
            // "until someone is at a laptop". Drawn only when it asks —
            // the v11 rule — and only for a background job, since an
            // interactive session has someone at it by definition.
            let asks = (row.job?.asksForPermission ?? false) && row.session.kind == .background ? "asks" : "    "
            // The worktree (v6): the repository, then the branch and its
            // standing — the same reading as the window's row.
            let cwd = hosts.shortCwd(row.worktree?.repo ?? s.cwd, host: row.host) + (row.worktree?.baseMark.map { " \($0)" } ?? "")
            let worktree = row.worktree.map { " ⎇ \($0.summary)" } ?? ""
            print("\(marker) \(host)\(s.id.padding(toLength: 8, withPad: " ", startingAt: 0))  \(state.padding(toLength: 11, withPad: " ", startingAt: 0)) \(live.padding(toLength: 4, withPad: " ", startingAt: 0))  \(rc) \(asks)  \(name)  \(model.padding(toLength: 10, withPad: " ", startingAt: 0))  \(cwd)\(worktree)\(waiting)\(archived)")
            // What the session has to say for itself (v10 slice 2), on its
            // own indented line: the row above is columns, and a sentence
            // of up to 460 characters would destroy them. `--json` carries
            // it whole; this is the reading, cut to one terminal line.
            if let say {
                // 14, not 10: the `rc` column above it is four cells wide.
                print("  \(host.isEmpty ? "" : String(repeating: " ", count: hostWidth + 2))\(String(repeating: " ", count: 14))↳ \(ellipsized(say, to: 96))")
            }
        }
        }
    }

    /// One line's worth, cut at the tail with the ellipsis that says so.
    /// Counts Characters, so an emoji or an accent is one column-ish and
    /// never half a scalar.
    static func ellipsized(_ text: String, to limit: Int) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit - 1)) + "…"
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
        if let j = s.jobJoin {
            // No wall time of its own: it rides the block `model join`
            // already times. What it needs to say is how often the cadence
            // actually opens a file, since it runs for every local
            // background row on every tick.
            let total = j.reads + j.hits
            let share = total > 0 ? String(format: "  %.0f%% cached", 100 * Double(j.hits) / Double(total)) : ""
            print("job join     reads \(j.reads)  cached \(j.hits)  none \(j.misses)\(share)")
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
        if let f = s.fetch {
            // The launch-and-wake fetch (v6 slice 7), measured: a timer
            // has to earn its place against these numbers.
            let ago = f.lastSecondsAgo.map { String(format: "%.0f s ago", $0) } ?? "never"
            let failed = f.failed > 0 ? "  failed \(f.failed)" : ""
            let last = f.last.map { "  last \"\($0)\"" } ?? ""
            print("fetch   rounds \(f.rounds)  repos \(f.repos)\(failed)  last \(ms(f.lastMs)) \(ago)\(last)")
        }
        if let w = s.wake, w.wakes > 0 {
            // Item 6. Wakes with no attempts is the interesting silence:
            // ssh never noticed the sleep killed the pane, so the window
            // that follows was never the thing standing between the user
            // and a live pane. Say it rather than leave three zeroes to be
            // read as "nothing to see".
            // Only a wake that HAD a remote pane could have reattached, so
            // only those make silence mean anything. A Mac that woke with
            // nothing attached is the everyday case and gets no warning —
            // the field is optional, and an older server that sends none
            // has to stay silent rather than guess.
            let armed = w.withRemotePane ?? 0
            let quiet = armed > 0 && w.attempts == 0 && w.gaveUp == 0
                ? "  ⚠ \(armed) wake(s) with a remote pane and not one reattach — ssh never noticed it die" : ""
            let withPane = armed > 0 ? "  with a remote pane \(armed)" : ""
            let gave = w.gaveUp > 0 ? "  gave up \(w.gaveUp)" : ""
            let last = w.last.map { "  last \"\($0)\"" } ?? ""
            print("wake    \(w.wakes) wakes\(withPane)  reattach attempts \(w.attempts)\(gave)\(last)\(quiet)")
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

    /// `--cols N --rows N` as a grid, refused below 1×1. The vt core
    /// rejects a zero axis (and the result was discarded) while the PTY
    /// forks at whatever it is given, so `--cols 0` used to make a host
    /// that answered every snapshot 0×0 behind an "attached (0x0)".
    static func gridFlags(_ args: [String], cols: Int, rows: Int) -> (cols: Int, rows: Int)? {
        let c = intFlag("--cols", args) ?? cols, r = intFlag("--rows", args) ?? rows
        guard c >= 1, r >= 1 else {
            stderr("ccc: --cols and --rows must be at least 1 (got \(c)x\(r))")
            return nil
        }
        return (c, r)
    }

    static func stringFlag(_ name: String, _ args: [String]) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func stderr(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    @discardableResult
    /// The usage block, rendered from `CommandManifest` (item 22). It was
    /// a 126-line string literal, which is where `update`'s entry went a
    /// release stale saying "the repo's default branch": a string no test
    /// can read is a string nothing keeps honest. `ManifestTests` reads
    /// this one.
    static func usage(to handle: FileHandle = .standardError, status: Int32 = 2) -> Int32 {
        handle.write(Data(CommandManifest.usage().utf8))
        return status
    }

    /// `ccc <verb> --help` — the thing that did not exist. `ccc spawn
    /// --help` answered "unknown flag '--help' for spawn", which is the
    /// worst of both: it looked like a typo rather than a missing feature,
    /// so nobody filed it for months.
    static func help(for word: String, to handle: FileHandle = .standardOutput) -> Int32 {
        guard let verb = CommandManifest.verb(named: word) else {
            stderr("ccc: no verb '\(word)' (try `ccc --help`)")
            return 2
        }
        handle.write(Data(CommandManifest.help(for: verb).utf8))
        return 0
    }
}