# ccc

Claude Code Command — a native macOS client for Claude Code's background
sessions. The `claude agents` view, replicated, then made ours: roster,
attached terminal, notifications on every device, ssh hosts as first-class.

Private. `CLAUDE.md` is the thesis and the locked decisions; read it and
`docs/QUEUE.md` and nothing else by default. The rest is reference, opened
when the work touches it:

```
docs/QUEUE.md       what is next — read this
docs/DESIGN.md      decisions + rejected alternatives; read the § an item cites
docs/HARNESS.md     the daemon / attach / hooks surface — when you touch roster, attach or hooks
docs/TERMINAL.md    libghostty-vt + our Metal renderer + our PTY — when you touch core, renderer or PTY
docs/CHECKS.md      the v1 six-check scoreboard; closed, only if reopening the core decision
docs/EVIDENCE.md    what was measured and the command that measured it — do NOT read it, grep it
```

**Status: v0.1.23 (2026-09-04) — v13 (item 17) is the frontier.** One binary, two
faces: `ccc` with no arguments opens the window (roster + attached pane, a
shell pane under it on ⌘T, + menubar item); every gesture has a command
twin over a unix socket. The
pane is libghostty-vt + our Metal renderer, which took all six checks
(`docs/CHECKS.md`) and became the default core; SwiftTerm stays only as the
`CCC_CORE=swiftterm` escape hatch.

```
git submodule update --init         # vendor/ghostty, pinned to one commit; scripts/fetch-zig gets the Zig it needs
swift build && swift test           # ~420 tests: roster, hosts/refs, model + job probe, PTY, subprocess, replay
                                    # goldens, keys/mouse, renderer, theme, ← guard, pixels, worktree verbs, docs guard
scripts/install                     # → ~/Applications/ccc.app + `ccc` on PATH (symlink into the bundle)
                                    # run it UNSANDBOXED: sandboxed it quits the app, half-copies the
                                    # bundle and leaves it dead

# finding your way around (the surface is data, not prose — `CommandManifest`)
ccc --help | ccc help <verb> | ccc <verb> --help
                                    # the whole list, or one verb in full: its synopsis, what its --json
                                    # answers, which gesture it is the twin of, what a non-zero exit means
ccc --llms                          # the whole surface as one document for an agent: the conventions
                                    # (<ref>, --json, exit codes, "a refusal names its way out") stated
                                    # once, then every verb under its group
ccc --schema [verb]                 # the same list as JSON — the manifest an agent reads once instead
                                    # of guessing flags out of prose

# the fleet
ccc hosts [list | check [<name>]]   # the Macs ccc can reach; check runs the real poll on each
ccc hosts add <n> [--ssh <d>] [--claude <p>] [--ccc <p>|--no-ccc] | remove <n>
                                    # a remote host's roster comes from ITS ccc (--ccc <path>), so the
                                    # model column is joined where the transcripts are; --no-ccc opts out
ccc hosts discover [--json]         # Macs on the tailnet, this one included; add probes over ssh
ccc hosts reconnect [<name>]        # drop the ssh master(s) and poll again — the wake-up gesture
ccc hosts mute|unmute <name>        # no banners for that host's sessions (rows and counts stay)

# the roster
ccc list [--host <n>] [--archived] [--group none|host|repo|state] [--sort activity|name|started|folder] [--fresh] [--json]
                                    # the roster with the model column, the `rc` column (answerable from the
                                    # Claude app) and what each session is doing; --json is always every row,
                                    # sorted, never grouped. Answered by the running app's roster when there
                                    # is one (≤ one tick old, joins warm); --fresh polls once more first, and
                                    # with no app it polls here
ccc archive|unarchive|pin|unpin <ref>  # a mark on a session, kept with the session's host
ccc watch [--host <n>] [--interval S] [--all] [--stall <minutes>] [--json]
                                    # one line per transition (blocked, done, failed, stopped, stalled,
                                    # landed); muted hosts are skipped unless --all or named.
                                    # `stalled` is the non-event: WORKING, and the daemon has not written the
                                    # job's file for N minutes (default 30, CCC_STALL_MINUTES, 0 off). One line
                                    # per stall, re-armed only when the session moves; sessions already still
                                    # when the watch starts are named on the opening line instead.
                                    # `landed` is the one kind git answers rather than the daemon: the branch
                                    # tip moved. Two halves — committed, then pushed — and only pushed draws a
                                    # banner, because a mid-item commit is not worth a phone.
                                    # --json is JSONL: one compact SessionEvent per line, flushed as it
                                    # happens, so `while read -r line` and `head -n1` work as well as `jq`.
                                    # The opening line and host errors go to stderr, never into the stream
ccc hook [--settings]               # the harness's Notification hook: JSON on stdin → a banner from the app;
                                    # --settings prints the settings.json entry (ccc never writes it)
ccc rm <ref> [--json]               # delete a session and its worktree, when the harness says that is safe

# spawning, and the session's repository
ccc spawn [--host <n>] [--cwd <d>] [--name <n>] [--model <m>] [--agent <a>] [--permission-mode <m>] [--rc]
          [--effort <e>] [--worktree[=<name>]] [--base <branch>] [--from <ref>] [--attach] [--json] [<prompt>... | -]
                                    # `claude --bg` on a host; no prompt makes a draft that waits for one,
                                    # --from forks off <ref>'s transcript (`--resume … --fork-session`).
                                    # --permission-mode defaults to auto. --worktree from a folder on the
                                    # default branch is the harness's; from any other branch (or with --base)
                                    # ccc cuts the worktree off that branch and records it as the base.
                                    # A worktree CCC cuts honours .worktreeinclude the way the harness's own
                                    # does: the ignored files it names (a .env, a Rails master.key) are
                                    # copied in, git does the pattern matching, and files inside a directory
                                    # git ignores by name (node_modules/) are left. The answer lists what
                                    # came with it
ccc spawn … [--replace|--allow-duplicate] [--no-space-check]
                                    # a --name a LIVE job already answers to is refused: messages, the roster
                                    # and lore all resolve to whichever started last. --replace stops that one
                                    # first, --allow-duplicate means it. A local spawn under the free-space
                                    # floor is refused too (CCC_SPAWN_FLOOR_GB, default 10; 0 turns it off)
ccc stop <ref> [--json]             # end a running session; its conversation and worktree are kept
                                    # (`ccc attach` resumes it). `ccc rm` is the one that deletes
ccc clear <ref> [--then "<prompt>"] [--json]
                                    # arm a /clear: when the row next goes idle, ccc types /clear into its
                                    # pane, then --then's prompt. THE CALLER IS THE COMMANDER ON ITS OWN REF,
                                    # the last act after an item lands — which is why it arms rather than
                                    # waits (while this call runs, that row is busy because of this call).
                                    # Commit the bank first: a dirty worktree is refused. A person's unsent
                                    # draft in the box stops it. Needs a ccc with a pane on that Mac (the app,
                                    # or `ccc attach --headless`) — arming is refused when none is serving,
                                    # since nothing would fire it. --cancel disarms; no ref lists what this
                                    # Mac has armed and what became of the last few
ccc base <ref> [<branch> | --clear] # what the worktree branch is measured against and lands on: read it,
                                    # record one for a worktree cut by hand, or forget it (`branch.<b>.ccc-base`
                                    # in the repo's config; VS Code's vscode-merge-base is honoured too)
ccc merge <ref> [--ff-only|--no-ff|--squash] [--json]
                                    # land the worktree branch on its base (recorded, else the repo's default
                                    # branch), where the repo is; refuses a dirty or wrong-branch checkout
ccc update <ref> [--ask] [--json]   # merge the base into the worktree branch ("Update branch").
                                    # THE VERB A SESSION USES ON ITS OWN BASE — `git merge` with the guards,
                                    # and it reaches origin/<base> when the local ref is behind it (the ↓
                                    # column counts the same tip; the answer names which). A worker brief
                                    # should say `ccc update`, never `git merge`: the raw merge is what the
                                    # auto-mode permission classifier refuses.
                                    # --ask hands the session the merge as a prompt through the pane
ccc fetch <ref> [--json]            # the one network call; every ⇡⇣ mark reads "as of the last fetch"
ccc pull <ref> [--json]             # fast-forward the base to origin's, never a merge commit — in the MAIN
                                    # checkout, so a base another worktree holds checked out is refused
                                    # (`ccc update` follows origin's tip instead; nobody's tree is written to)
ccc push <ref> [--base] [--json]    # push the worktree branch (or, with --base, its base branch); never forced
ccc shell <ref> [--repo] | --close  # ⌘T's twin: a shell pane under the session pane, in <ref>'s folder
                                    # (over `ssh -t` when remote); --repo is the main checkout (⌥⌘T), --close is ⇧⌘T
                                    # the row's item and `t` flip to Close Terminal while that row's shell is up

# the pane
ccc attach <ref> [--headless [--cols N --rows N]]
                                    # attach in the window, or headless: a PTY + the socket, no window
                                    # <ref> is `id` on this Mac, `host:id` anywhere else
ccc snapshot [--json] [--color]     # the pane's grid as text — how an agent sees what you see
                                    # --color adds the resolved #RRGGBB per run: colour with no screen
ccc send "text" | --key ctrl-z      # type; named keys go through the core's key encoder
ccc send --paste <text>|- | --wheel N  # paste framed as the child negotiated (- reads stdin); scroll
ccc links [--open N] [--json]       # the URLs on the grid, numbered; --open N is ⌘-clicking that link
ccc select <c> <r> <c> <r> [--rect] | --clear
                                    # select a region of the pane (both ends inclusive) in the theme's
                                    # selection colours. The gesture is shift-drag (plain drag when the
                                    # child is not tracking the mouse), ⌥ for a rectangle
ccc select --word <c> <r> | --line <c> <r>
                                    # the double- and triple-click's twins
ccc copy [--json]                   # ⌘C's twin: the selected text, onto the pasteboard
ccc focus [in|out]                  # what the window last told the child about focus (DEC 1004), or assert
                                    # it; the harness suppresses your phone's push while a terminal reports
                                    # focus, so `out` is what says nobody is here
ccc detach | resize <c> <r> | stats # detach; resize (headless); memory / poll + model/job-join cost / PTY B/s

# the window, and judging what it shows
ccc window show|hide|close|minimize|zoom|fullscreen|center
ccc window move <x> <y> | resize <w> <h> | frame <x> <y> <w> <h> | split <w>
                                    # the two drags and the divider — and, like them, remembered across a relaunch
ccc window add-host|new-session     # the two sheets, which `ccc peek` composites
ccc peek [out.png]                  # PNG of the window from our view hierarchy (no screen permission)
ccc capture [out.png] [--json]      # PNG of the window AS IT IS ON SCREEN, via `screencapture -l` — the
                                    # presentation oracle. Screen Recording permission belongs to whoever
                                    # runs it, which is why the app never asks for it and peek always works
ccc pixel <png> --cell <c> <r> | --at <x> <y> [--expect '#RRGGBB' [--tolerance N]] [--json]
                                    # the colour at one pixel; --cell aims through the window's geometry,
                                    # --expect makes the exit code the answer, so a script can judge a colour
ccc geometry [--json]               # the window id screencapture wants, where the window is (top-left
                                    # down, what `ccc window move` takes), whether it is visible, the
                                    # roster's width, the pane's rect, the cell size
ccc theme [--json]                  # the pane's colours: 16 ANSI + 6 specials, with a swatch per row
                                    # --json is the shape CCC_THEME reads; 16-255 are the xterm cube, not a choice

# the build itself
ccc version [--json]                # this build: version, build number, bundle (see below)
ccc install-cli [--dir <d>] [--force]  # link `ccc` on PATH into the installed app
ccc replay <bytes> [--bytes N] [--core X] [--cols N --rows N] [--color]
                                    # render a recording headlessly (the golden-test oracle)
ccc bench <bytes> [--repeat N] [--core ghostty|swiftterm]
                                    # throughput, snapshot cost, footprint delta, grid digest
scripts/release-notes [<tag>]       # a release's notes: this repo's commit subjects + a compare link
                                    # (scripts/package calls it; the twin that normalizes an old Release)
scripts/record-attach <id>          # record a real `claude attach` as the replay fixture
```

**Which binary you are measuring.** `ccc` on PATH is a symlink into
`~/Applications/ccc.app`, which is whatever `scripts/install` last put
there — the installed release on a normal day, not a build of the branch
you are on. `ccc version` reads version and build from the bundle the
executable actually lives in, and says `dev` for a bundle without Sparkle
keys. Check it before trusting a measurement of the app: `swift build`
alone changes nothing that `ccc` runs.

Layout: `Sources/CCCKit` (roster, transcript, hosts, harness — spawn and
worktree — PTY, terminal seam, renderer, control, stats: everything without
a window), `Sources/ccc` (CLI, headless runner, PaneController, the
AppKit/SwiftUI window), `Tests/CCCKitTests` (+ fixtures). Environment:
`CCC_CLAUDE` (path to `claude`), `CCC_CONTROL_SOCKET`, `CCC_HOSTS` (the
host list, default `~/Library/Application Support/ccc/hosts.json`),
`CCC_ROSTER_OVERLAY` (our marks — archive, pin — default
`~/Library/Application Support/ccc/roster.json`),
`CCC_SSH_CONTROL_DIR` (where
the per-host ssh master sockets live), `CCC_THEME` (a JSON theme file in `ccc theme --json`'s shape; unset, or unparseable,
means the built-in read from the user's iTerm profile), `CCC_CORE=ghostty|swiftterm` (the pane's core;
ghostty is the default), `CCC_METAL=1` (SwiftTerm's own Metal renderer, only
under the escape hatch; ~250 MB, see DESIGN.md).
