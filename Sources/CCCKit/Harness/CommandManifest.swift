import Foundation

/// **The verb list, as data** (item 22).
///
/// Every surface that has to say what ccc can do reads this: `ccc --help`,
/// `ccc <verb> --help`, `ccc --llms`, `ccc --schema`, and the tests that
/// check the two faces have not drifted apart. It exists because they had
/// drifted: `ccc spawn --help` answered *"unknown flag '--help' for
/// spawn"*, the one-line usage block was the only description of anything
/// and it lived as a 126-line string literal no test could reach, and
/// `update`'s entry there still said "the repo's default branch" a release
/// after the code learned the recorded base. A string a test cannot read is
/// a string that goes stale, and this one was three verbs stale.
///
/// **The reader is an agent as often as a person.** ccc's whole parity rule
/// is that every gesture has a command twin (CLAUDE.md); a twin an agent
/// cannot discover is half a twin. So the manifest carries what a person
/// needs (a synopsis and prose) *and* what a program needs: which verbs
/// answer `--json`, what shape the answer has, and what the exit code
/// means. Conventions borrowed from `incur`, which lore is built on —
/// `--llms` for the whole surface, `--schema` for the machine shape.
/// Borrowed, not depended on: incur is Bun/TS and could not be a Swift
/// dependency, but a convention costs nothing to carry across.
///
/// **What was deliberately not borrowed**, and why, so nobody re-derives
/// it: `--format toon` and `--token-limit`. TOON pays for itself over
/// thousands of homogeneous rows; ccc's largest answer is a roster of
/// about thirty, where the saving is smaller than the cost of a second
/// encoder and a second thing for a reader to know. And a `--token-limit`
/// that trims a roster answers a different question than the one asked —
/// `--host` and `--archived` are the honest narrowings, and they exist.
/// Both become worth it the day an answer here is genuinely large.
public struct CommandManifest: Sendable {
    public struct Verb: Codable, Sendable, Equatable {
        /// The word typed after `ccc`.
        public var name: String
        /// Other words that reach the same verb.
        public var aliases: [String]
        /// Usage lines, each already beginning with the verb.
        public var synopsis: [String]
        /// What it does, in the words the usage block used.
        public var about: [String]
        /// What `--json` answers with, or nil when the verb has no
        /// `--json`. A sentence, not a JSON Schema: the shapes are Swift
        /// `Codable` types whose field names are the wire, and naming the
        /// type is what lets a reader find the definition.
        public var json: String?
        /// The gesture this is the twin of, when there is one.
        public var twin: String?
        /// What a non-zero exit means, when it means something specific.
        public var exit: String?
        public var group: String

        public init(name: String, aliases: [String] = [], synopsis: [String], about: [String],
                    json: String? = nil, twin: String? = nil, exit: String? = nil, group: String) {
            self.name = name
            self.aliases = aliases
            self.synopsis = synopsis
            self.about = about
            self.json = json
            self.twin = twin
            self.exit = exit
            self.group = group
        }
    }

    /// The groups, in the order a reader meets them.
    public static let groups = ["hosts", "roster", "session", "git", "pane", "window", "build"]

    public static func verb(named word: String) -> Verb? {
        verbs.first { $0.name == word || $0.aliases.contains(word) }
    }

    public static let verbs: [Verb] = [
        Verb(name: "hosts",
             synopsis: ["hosts [list|check [<name>]]",
                        "hosts discover [--json]",
                        "hosts add <name> [--ssh <dest>] [--claude <path>] [--ccc <path>|--no-ccc]",
                        "hosts remove <name>",
                        "hosts reconnect [<name>]",
                        "hosts mute|unmute <name>"],
             about: ["the machines ccc can reach; `check` runs the real poll.",
                     "`discover` lists Macs on the tailnet, this one included, and probes over ssh.",
                     "`add` finds the paths on the host unless given them.",
                     "`reconnect` drops the ssh master(s) and polls again — the wake-up gesture.",
                     "`mute` stops banners for that host's sessions; rows and counts stay."],
             json: "hosts discover: an array of candidates (name, ssh, reachable, claude, ccc)",
             twin: "the Add Host sheet",
             group: "hosts"),

        Verb(name: "list",
             synopsis: ["list [--host <name>] [--archived] [--group none|host|repo|state]",
                        "     [--sort activity|name|started|folder] [--fresh] [--json]"],
             about: ["every host's roster; --host narrows to one, --archived shows the folded rows",
                     "(--json always has every row, sorted, never grouped).",
                     "Answered by the running app's roster (≤ one tick old, joins warm); --fresh polls",
                     "once more first, and no app means polling here.",
                     "The `rc` column marks a session dispatched --rc: answerable from the Claude app,",
                     "not only here. `ccc spawn` defaults to it, so a row WITHOUT the mark is the one",
                     "that carries news — it can only be answered on the Mac it runs on."],
             json: "[SessionRow] — session (the harness's row), host, model, attached, archived, pinned, draft, worktree, job",
             twin: "the roster",
             group: "roster"),

        Verb(name: "archive", aliases: ["unarchive", "pin", "unpin"],
             synopsis: ["archive|unarchive|pin|unpin <ref>"],
             about: ["a mark on a session, kept with the session's host.",
                     "Archived rows fold away unless blocked; pinned rows sort first."],
             twin: "the row's context menu",
             group: "roster"),

        Verb(name: "watch",
             synopsis: ["watch [--host <name>] [--interval S] [--all] [--stall <minutes>] [--json]"],
             about: ["one line per transition (blocked, done, failed, stopped, stalled, landed);",
                     "muted hosts are skipped unless --all or named with --host.",
                     "`stalled` is the non-event: WORKING, and the daemon has not written the job's",
                     "file for N minutes (default 30, CCC_STALL_MINUTES, 0 off). One line per stall,",
                     "re-armed only when the session moves again; sessions already still when the",
                     "watch starts are named on the opening line instead.",
                     "`landed` is the one kind git answers rather than the daemon: the branch tip",
                     "moved. Two halves — committed, then pushed — and only pushed draws a banner,",
                     "because a mid-item commit is not worth a phone. Both print here."],
             json: "JSONL: one compact SessionEvent per line, flushed as it happens — kind, ref, "
                 + "name, waitingFor, stillFor, landing, job, at",
             twin: "the notification banners",
             exit: "1 when no host answered at all",
             group: "roster"),

        Verb(name: "hook",
             synopsis: ["hook [--settings]"],
             about: ["the harness's Notification hook: JSON on stdin → a banner from the app, for what",
                     "the roster cannot show. --settings prints the settings.json entry; ccc never",
                     "writes that file."],
             exit: "always 0 — a hook's failure prints inside the user's own session",
             group: "roster"),

        Verb(name: "spawn", aliases: ["new"],
             synopsis: ["spawn [--host <name>] [--cwd <dir>] [--name <n>] [--model <m>] [--agent <a>]",
                        "      [--permission-mode <m>] [--no-rc] [--effort <e>] [--worktree[=<name>]]",
                        "      [--base <branch>] [--from <ref>] [--attach] [--json]",
                        "      [--replace|--allow-duplicate] [--no-space-check] [<prompt>... | -]"],
             about: ["`claude --bg` on a host (cwd: here, or the far side's home); the prompt is the",
                     "remaining words, or stdin for `-`; none makes a draft that waits for one.",
                     "--from forks a new session off <ref>'s transcript, on its host and in its folder",
                     "unless told otherwise (`--resume <session id> --fork-session`).",
                     "--attach opens it in the app. --permission-mode defaults to auto, and Remote",
                     "Control is on: every spawn is answerable from the Claude app, and --no-rc is the",
                     "opt-out (an RC session's transcript lives on Anthropic servers while connected).",
                     "--worktree from a folder on the default branch is the harness's; from any other",
                     "branch, or with --base, ccc cuts the worktree off that branch and records the base.",
                     "A worktree ccc cuts honours .worktreeinclude the way the harness's own does: the",
                     "ignored files it names (a .env, a Rails master.key) are copied in, and the answer",
                     "lists them under `worktree.carried`.",
                     "A --name a LIVE job already answers to is refused (messages and the roster would",
                     "resolve to whichever started last): --replace stops that one first,",
                     "--allow-duplicate means it. A local spawn under the free-space floor is refused",
                     "too (CCC_SPAWN_FLOOR_GB, default 10; 0 or --no-space-check turns it off)."],
             json: "SpawnResult — ref, draft, cwd, said, from, worktree {path, branch, base, carried[]}",
             twin: "the New Session sheet",
             exit: "1 on a refusal (name taken, disk under the floor, the harness said no); 2 on a bad flag",
             group: "session"),

        Verb(name: "attach",
             synopsis: ["attach <ref> [--headless [--cols N --rows N]]"],
             about: ["<ref> is `id` (this Mac) or `host:id`. The pane follows: an attached session is",
                     "left (Ctrl+Z, the harness's detach) for the new one.",
                     "--headless drives a PTY and serves the control socket with no window — how an",
                     "agent sees what the user sees."],
             twin: "clicking a row",
             group: "session"),

        Verb(name: "detach", synopsis: ["detach"],
             about: ["let go of the attached session; it keeps running."],
             group: "session"),

        Verb(name: "stop",
             synopsis: ["stop <ref> [--json]"],
             about: ["end a running session; its conversation and its worktree are both kept",
                     "(`ccc attach` resumes it). `ccc rm` is the one that deletes."],
             json: "{ ref, stopped, said }",
             exit: "1 when the harness refused, with its reason in `said`",
             group: "session"),

        Verb(name: "rm",
             synopsis: ["rm <ref> [--json]"],
             about: ["delete a session and its worktree, when the harness says that is safe.",
                     "A worktree ccc cut (--base) is one the harness never knew about, so ccc",
                     "removes that one itself, after. Neither adds a --force: the guards are the",
                     "harness's and git's, and \"kept\" is a correct answer rather than an error."],
             json: "{ ref, removed, said, worktree? { path, branch, removed, branchDeleted, said } }",
             exit: "1 when the harness kept it, with its reason in `said`",
             group: "session"),

        Verb(name: "clear",
             synopsis: ["clear <ref> [--then \"<prompt>\"] [--json]",
                        "clear <ref> --cancel",
                        "clear"],
             about: ["arm a `/clear` on a session: when the row next goes idle, ccc types /clear",
                     "into its pane, and then --then's prompt if one was given.",
                     "THE CALLER IS NORMALLY THE COMMANDER ON ITS OWN REF, as the last act after an",
                     "item lands — which is why it ARMS rather than waits: while this call runs, the",
                     "row it names is busy because of this call. Commit the bank first; a dirty",
                     "worktree is refused here and again when it fires.",
                     "Needs a ccc with a pane on that Mac (the app, or `ccc attach --headless`).",
                     "A person's unsent draft in the prompt box stops it — those words are not ours",
                     "to submit or delete. --cancel disarms; no ref lists what is armed on this Mac."],
             json: "{ ref, armed, then?, cancelled, said } — bare `clear --json` is the armed list",
             twin: "typing /clear in the pane",
             exit: "1 on a refusal (dirty worktree, no such session, an interactive one)",
             group: "session"),

        Verb(name: "base",
             synopsis: ["base <ref> [<branch> | --clear]"],
             about: ["what the worktree branch is measured against and lands on: read it, record one",
                     "for a worktree cut by hand, or forget it — `branch.<b>.ccc-base` in the repo's",
                     "config. VS Code's vscode-merge-base is honoured too."],
             group: "git"),

        Verb(name: "merge",
             synopsis: ["merge <ref> [--ff-only|--no-ff|--squash] [--json]"],
             about: ["land the session's worktree branch on its base — recorded, else the repo's",
                     "default branch — where the repo is. --ff-only (default) refuses when the base",
                     "moved. Every strategy refuses a dirty or wrong-branch checkout and backs out of",
                     "a conflict; nothing is ever lost."],
             json: "{ ref, merged, strategy, said }",
             exit: "1 with the reason in `said`; nothing changed anywhere",
             group: "git"),

        Verb(name: "update",
             synopsis: ["update <ref> [--ask] [--json]"],
             about: ["merge the session's BASE — recorded, else the repo's default branch — into its",
                     "worktree branch, in the worktree (GitHub's \"Update branch\").",
                     "THIS IS THE VERB A SESSION USES ON ITS OWN BASE: it is `git merge` with the",
                     "guards, and it reaches origin/<base> when the local ref is behind it (the ↓",
                     "column counts the same tip, and the answer names which it used). A worker brief",
                     "should say `ccc update`, never `git merge` — the raw merge is what the auto-mode",
                     "permission classifier refuses.",
                     "Refuses uncommitted changes and backs out of a conflict; --ask then hands the",
                     "session the merge as a prompt through the pane (needs the app)."],
             json: "{ ref, updated, said, ask } — `ask` is the prompt a conflict would hand the session",
             exit: "1 on a refusal or a backed-out conflict; the branch is untouched either way",
             group: "git"),

        Verb(name: "fetch",
             synopsis: ["fetch <ref> [--json]",
                        "fetch --repo [<path>] [--json]"],
             about: ["`git fetch origin` in the session's repository — the one network call.",
                     "Every ⇡⇣ mark reads \"as of the last fetch\" (the app fetches once at launch and",
                     "once on wake; `ccc stats` measures those).",
                     "--repo names the checkout instead of a session, for when no session is left to",
                     "name it: bare it means this folder, and any path inside a repository answers",
                     "for that repository's ROOT. Local only; a remote one is named by a ref."],
             json: "{ ref, fetched, said } — { repo, fetched, said } for --repo",
             group: "git"),

        Verb(name: "pull", aliases: ["ff"],
             synopsis: ["pull <ref> [--json]",
                        "pull --repo [<path>] [--json]"],
             about: ["fast-forward the base to origin's, never a merge commit. Runs in the MAIN",
                     "checkout, so a base another worktree holds checked out is refused — `ccc update`",
                     "follows origin's tip instead, and writes into nobody else's tree.",
                     "A diverged base is refused with the way out named.",
                     "--repo names the checkout instead of a session (same rules as `ccc fetch`),",
                     "which is what the END of a reap needs: the ref form resolves through a live",
                     "roster row and its cwd, so it must run BEFORE `git worktree remove` and",
                     "`ccc rm`, and --repo is what still works after them.",
                     "`ccc ff` is this verb under the name that says fast-forward-only."],
             json: "{ ref, pulled, said } — { repo, pulled, said } for --repo",
             exit: "1 on a refusal; nothing changed",
             group: "git"),

        Verb(name: "push",
             synopsis: ["push <ref> [--base] [--json]"],
             about: ["push the session's worktree branch — or, with --base, the repo's default branch",
                     "— to origin, never forced. git's own refusal is the answer."],
             json: "{ ref, pushed, target, said }",
             exit: "1 on git's refusal; nothing changes anywhere",
             group: "git"),

        Verb(name: "shell",
             synopsis: ["shell <ref> [--repo] | --close"],
             about: ["a shell pane under the session pane, in <ref>'s folder (over `ssh -t` when",
                     "remote). --repo is the repository's main checkout instead of the worktree."],
             twin: "⌘T; --repo is ⌥⌘T, --close is ⇧⌘T",
             group: "git"),

        Verb(name: "snapshot",
             synopsis: ["snapshot [--json] [--color]"],
             about: ["the pane's grid as text — how an agent sees what you see.",
                     "--color adds the resolved RGB per run (`#RRGGBB`, the spelling `ccc pixel`",
                     "prints), so a colour can be judged with no window and no Screen Recording",
                     "permission."],
             json: "SnapshotInfo — attachedTo, grid { cols, rows, cursor, rows[] with runs }",
             group: "pane"),

        Verb(name: "send",
             synopsis: ["send <text> | --key <name>... | --wheel N | --paste <text>|-"],
             about: ["type into the pane. Named keys go through the core's key encoder, never a",
                     "hand-rolled escape sequence. --wheel N scrolls (N>0 is up); --paste frames the",
                     "text as a paste the way the child negotiated, and `-` reads stdin."],
             twin: "typing in the pane",
             group: "pane"),

        Verb(name: "select",
             synopsis: ["select <col> <row> <col> <row> [--rect] | --clear",
                        "select --word <col> <row> | --line <col> <row>"],
             about: ["select a region of the pane (both ends inclusive); it paints the theme's",
                     "selection colours, which `ccc snapshot --color` and `ccc pixel` both read.",
                     "--word and --line are the double- and triple-click's twins: the word or the line",
                     "at one point (a second point drags the grain)."],
             twin: "shift-drag (plain drag when the child is not tracking the mouse), ⌥ for a rectangle",
             group: "pane"),

        Verb(name: "copy",
             synopsis: ["copy [--json]"],
             about: ["the selected text, onto the pasteboard."],
             json: "{ text }",
             twin: "⌘C",
             group: "pane"),

        Verb(name: "links",
             synopsis: ["links [--open N] [--json]"],
             about: ["the URLs on the pane's grid, numbered from 1; --open N opens the Nth."],
             json: "[LinkInfo] — url, row, col",
             twin: "⌘-clicking a link",
             group: "pane"),

        Verb(name: "focus",
             synopsis: ["focus [in|out] [--json]"],
             about: ["what the window last told the child about focus (DEC 1004), or assert it.",
                     "The harness suppresses your phone's push while a terminal reports focus, so",
                     "`out` is what says nobody is here."],
             json: "{ focused }",
             group: "pane"),

        Verb(name: "resize",
             synopsis: ["resize <cols> <rows>"],
             about: ["resize the pane's grid — one ioctl on the PTY master."],
             group: "pane"),

        Verb(name: "peek",
             synopsis: ["peek [out.png]"],
             about: ["PNG of the app window, composited from an offscreen render — no Screen",
                     "Recording permission. It can show a perfect TUI over a pane that is black on",
                     "screen; `ccc capture` is the oracle for what is actually visible."],
             group: "window"),

        Verb(name: "capture",
             synopsis: ["capture [out.png] [--json]"],
             about: ["PNG of the window as it is ON SCREEN, through `screencapture -l` — the",
                     "presentation oracle. Needs Screen Recording permission for whoever runs it,",
                     "which is why it lives in the CLI and never in the app."],
             json: "{ path, width, height }",
             group: "window"),

        Verb(name: "pixel",
             synopsis: ["pixel <png> --cell <c> <r> | --at <x> <y> [--expect #RRGGBB [--tolerance N]] [--json]"],
             about: ["the colour at one pixel; --cell aims at a grid cell through the window's",
                     "geometry, and --expect makes the exit code the answer."],
             json: "{ color, x, y, expected, matched }",
             exit: "1 when --expect did not match",
             group: "window"),

        Verb(name: "geometry",
             synopsis: ["geometry [--json]"],
             about: ["where the window and its pane are, the roster's width, the cell size, and",
                     "whether anyone can see any of it. x and y are the desktop's top-left down —",
                     "what `ccc window move` takes back."],
             json: "{ window {x,y,w,h}, pane, cell, rosterWidth, visible }",
             group: "window"),

        Verb(name: "theme",
             synopsis: ["theme [--json]"],
             about: ["the pane's 16 + 6 colours; --json is the shape CCC_THEME reads."],
             json: "the CCC_THEME object — 16 ANSI colours plus fg, bg, cursor, selection",
             group: "window"),

        Verb(name: "window",
             synopsis: ["window show|hide|close|minimize|zoom|fullscreen|center",
                        "window move X Y | resize W H | frame X Y W H | split W",
                        "window add-host|new-session"],
             about: ["the window's own gestures, one verb each: close is ⌘W, minimize/zoom/fullscreen",
                     "are the three buttons, move and resize are the two drags (frame is both), split",
                     "is the roster's divider. move, resize, frame and split are remembered across a",
                     "relaunch, the same as the drags they stand for.",
                     "add-host and new-session open their sheets, which `ccc peek` composites."],
             group: "window"),

        Verb(name: "stats",
             synopsis: ["stats [--json]"],
             about: ["memory, poll latency, PTY throughput, presented frames, the wake line.",
                     "Bytes in with zero presented frames is the black pane, stated as a number."],
             json: "the stats object — memory, poll, pty, frames, wake { wakes, attempts, gaveUp }",
             group: "build"),

        Verb(name: "replay",
             synopsis: ["replay <bytes-file> [--cols N --rows N --bytes N --core ghostty|swiftterm] [--json] [--color]"],
             about: ["render recorded bytes headlessly — the fixture every renderer change is judged",
                     "against."],
             json: "the same grid `snapshot` answers with",
             group: "build"),

        Verb(name: "bench",
             synopsis: ["bench <bytes-file> [--repeat N --core ghostty|swiftterm] [--json]"],
             about: ["parse + snapshot throughput, per core."],
             json: "{ core, bytes, repeats, parseMs, snapshotMs, mbPerSecond }",
             group: "build"),

        Verb(name: "version",
             synopsis: ["version [--json]"],
             about: ["this build: version, build number, bundle."],
             json: "BuildInfo — version, build, bundle, path",
             group: "build"),

        Verb(name: "install-cli",
             synopsis: ["install-cli [--dir <dir>] [--force] [--json]"],
             about: ["link `ccc` on PATH as a symlink into the installed app bundle."],
             json: "{ path, linked, said }",
             group: "build"),
    ]
}

// MARK: rendering

extension CommandManifest {
    /// A synopsis line as it is printed. **A line that starts with
    /// whitespace is a continuation** of the one above — that is the whole
    /// rule, and it is already how the data reads — so it gets four spaces
    /// where a fresh command gets `ccc `. Without it `ccc hosts discover`
    /// and `ccc spawn`'s wrapped flags render identically, and one of them
    /// is a lie.
    static func synopsisLines(_ verb: Verb, indent: String) -> String {
        verb.synopsis.map { line in
            let continuation = line.first?.isWhitespace == true
            return indent + (continuation ? "    " : "ccc ") + line + "\n"
        }.joined()
    }

    /// The one-screen usage block: `ccc` with no verb, and `ccc --help`.
    public static func usage() -> String {
        var out = "usage: ccc                          open the app\n"
        for verb in verbs {
            out += synopsisLines(verb, indent: "       ")
            for line in verb.about {
                out += "           \(line)\n"
            }
        }
        out += "\n       ccc <verb> --help    one verb in full, with what its --json answers\n"
        out += "       ccc --llms           the whole surface, for an agent\n"
        out += "       ccc --schema [verb]  the manifest as JSON\n"
        return out
    }

    /// One verb in full — what `ccc <verb> --help` prints. The thing that
    /// did not exist: `ccc spawn --help` answered "unknown flag".
    public static func help(for verb: Verb) -> String {
        var out = "ccc \(verb.name)"
        if !verb.aliases.isEmpty { out += " (also: \(verb.aliases.joined(separator: ", ")))" }
        out += "\n\n"
        out += synopsisLines(verb, indent: "  ")
        out += "\n"
        for line in verb.about { out += "  \(line)\n" }
        if let twin = verb.twin { out += "\n  twin of: \(twin)\n" }
        if let json = verb.json { out += "\n  --json:  \(json)\n" }
        else { out += "\n  --json:  not answered by this verb\n" }
        if let exit = verb.exit { out += "  exit:    \(exit)\n" }
        return out
    }

    /// `ccc --llms`: the whole surface as one document meant to be read by
    /// something that will then run the commands. Grouped, every verb with
    /// its JSON shape and exit meaning, and the conventions stated once at
    /// the top so they are not re-derived per verb.
    public static func llms() -> String {
        var out = """
        # ccc — a native client for the Claude Code harness's background sessions

        ccc reads the daemon's roster, spawns through `claude --bg`, and attaches
        through `claude attach`. It never writes to ~/.claude/daemon or ~/.claude/jobs.

        ## Conventions

        - A `<ref>` is `id` (this Mac) or `host:id` for any host in `ccc hosts`.
        - `--json` prints one JSON value on stdout and nothing else; every verb
          listed with a `--json:` line below answers it. Errors go to stderr,
          prefixed `ccc: `, and are never JSON.
        - Exit 0 is success, 1 is a refusal that changed nothing (the reason is in
          `said`), 2 is a bad invocation.
        - A refusal always names its own way out. ccc refuses; it does not forbid.
        - `ccc <verb> --help` is this entry for one verb; `ccc --schema` is the
          same list as JSON.

        """
        for group in groups {
            let inGroup = verbs.filter { $0.group == group }
            guard !inGroup.isEmpty else { continue }
            out += "\n## \(group)\n"
            for verb in inGroup {
                out += "\n### ccc \(verb.name)\n\n"
                out += synopsisLines(verb, indent: "    ")
                out += "\n"
                out += verb.about.joined(separator: " ") + "\n"
                if let twin = verb.twin { out += "\nTwin of: \(twin).\n" }
                if let json = verb.json { out += "\n`--json`: \(json)\n" }
                if let exit = verb.exit { out += "\nExit: \(exit)\n" }
            }
        }
        return out
    }
}
