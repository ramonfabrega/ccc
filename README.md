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

**Status: v0.1.18 (2026-09-04) — through v11 slice 4.** One binary, two
faces: `ccc` with no arguments opens the window (roster + attached pane, a
shell pane under it on ⌘T, + menubar item); every gesture has a command
twin over a unix socket. The
pane is libghostty-vt + our Metal renderer, which took all six checks
(`docs/CHECKS.md`) and became the default core; SwiftTerm stays only as the
`CCC_CORE=swiftterm` escape hatch.

```
git submodule update --init         # vendor/ghostty, pinned to one commit; scripts/fetch-zig gets the Zig it needs
swift build && swift test           # 394 tests: roster, hosts/refs, model + job probe, PTY, replay goldens,
                                    # keys/mouse, renderer, theme, ← guard, pixels, worktree verbs, docs guard
scripts/install                     # → ~/Applications/ccc.app + `ccc` on PATH (symlink into the bundle)
                                    # run it UNSANDBOXED: sandboxed it quits the app, half-copies the
                                    # bundle and leaves it dead

# the fleet
ccc hosts [list | check [<name>]]   # the Macs ccc can reach; check runs the real poll on each
ccc hosts add <n> [--ssh <d>] [--claude <p>] [--ccc <p>|--no-ccc] | remove <n>
                                    # a remote host's roster comes from ITS ccc (--ccc <path>), so the
                                    # model column is joined where the transcripts are; --no-ccc opts out
ccc hosts discover [--json]         # Macs on the tailnet, this one included; add probes over ssh
ccc hosts reconnect [<name>]        # drop the ssh master(s) and poll again — the wake-up gesture
ccc hosts mute|unmute <name>        # no banners for that host's sessions (rows and counts stay)

# the roster
ccc list [--host <n>] [--archived] [--group none|host|repo|state] [--sort activity|name|started|folder] [--json]
                                    # the roster with the model column and what each session is doing (no
                                    # app needed); --json is always every row, sorted, never grouped
ccc archive|unarchive|pin|unpin <ref>  # a mark on a session, kept with the session's host
ccc watch [--host <n>] [--interval S] [--all] [--json]
                                    # one line per transition (blocked, done, failed, stopped); muted hosts
                                    # are skipped unless --all or named
ccc hook [--settings]               # the harness's Notification hook: JSON on stdin → a banner from the app;
                                    # --settings prints the settings.json entry (ccc never writes it)
ccc rm <ref> [--json]               # delete a session and its worktree, when the harness says that is safe

# spawning, and the session's repository
ccc spawn [--host <n>] [--cwd <d>] [--name <n>] [--model <m>] [--agent <a>] [--permission-mode <m>]
          [--effort <e>] [--worktree[=<name>]] [--from <ref>] [--attach] [--json] [<prompt>... | -]
                                    # `claude --bg` on a host; no prompt makes a draft that waits for one,
                                    # --from forks off <ref>'s transcript (`--resume … --fork-session`)
ccc merge <ref> [--ff-only|--no-ff|--squash] [--json]
                                    # land the worktree branch on the repo's default branch, where the repo
                                    # is; refuses a dirty or wrong-branch checkout, backs out of a conflict
ccc update <ref> [--ask] [--json]   # merge the default branch into the worktree branch ("Update branch");
                                    # --ask hands the session the merge as a prompt through the pane
ccc fetch <ref> [--json]            # the one network call; every ⇡⇣ mark reads "as of the last fetch"
ccc pull <ref> [--json]             # fast-forward the default branch to origin's, never a merge commit
ccc push <ref> [--base] [--json]    # push the worktree branch (or, with --base, the default branch); never forced
ccc shell <ref> [--repo] | --close  # ⌘T's twin: a shell pane under the session pane, in <ref>'s folder
                                    # (over `ssh -t` when remote); --repo is the main checkout (⌥⌘T), --close is ⇧⌘T

# the pane
ccc attach <ref> [--headless]       # attach in the window, or headless: a PTY + the socket, no window
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
ccc copy                            # ⌘C's twin: the selected text, onto the pasteboard
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
ccc pixel <png> --cell <c> <r> | --at <x> <y> [--expect '#RRGGBB' [--tolerance N]]
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
ccc replay <bytes> [--bytes N] [--core X]  # render a recording headlessly (the golden-test oracle)
ccc bench <bytes> [--repeat N]      # throughput, snapshot cost, footprint delta, grid digest
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
