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

**Status: v0.1.14 (2026-09-03) — through v7 slice 2.** One binary, two
faces: `ccc` with no arguments opens the window (roster + attached pane +
menubar item); every gesture has a command twin over a unix socket. The
pane is libghostty-vt + our Metal renderer, which took all six checks
(`docs/CHECKS.md`) and became the default core; SwiftTerm stays only as the
`CCC_CORE=swiftterm` escape hatch.

```
git submodule update --init         # vendor/ghostty, pinned to one commit; scripts/fetch-zig gets the Zig it needs
swift build && swift test           # 272 tests: roster, hosts/refs, model probe, PTY, replay goldens, keys/mouse, renderer, docs guard
scripts/install                     # → ~/Applications/ccc.app + `ccc` on PATH (symlink into the bundle)
                                    # run it UNSANDBOXED: sandboxed it quits the app, half-copies the
                                    # bundle and leaves it dead

ccc hosts [add <n> --ssh <d>|remove <n>|check]  # the Macs ccc can reach; check runs the real poll on each
                                    # a remote host's roster comes from ITS ccc (--ccc <path>), so the
                                    # model column is joined where the transcripts are; --no-ccc opts out
ccc list [--host <name>] [--json]   # the roster with the model column (no app needed)
ccc attach <ref> [--headless]       # attach in the window, or headless: a PTY + the socket, no window
                                    # <ref> is `id` on this Mac, `host:id` anywhere else
ccc snapshot [--json]               # the pane's grid as text — how an agent sees what you see
ccc send "text" | --key ctrl-z      # type; named keys go through the core's key encoder
ccc send --paste <text>|- | --wheel N  # paste framed as the child negotiated (- reads stdin); scroll
ccc detach | resize <c> <r> | stats # detach; resize (headless); memory / poll + model-join cost / PTY B/s
ccc peek [out.png]                  # PNG of the window from our view hierarchy (no screen permission)
ccc window show|hide|close|resize <c> <r>
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

Layout: `Sources/CCCKit` (roster, transcript, PTY, terminal seam, renderer,
control, stats — everything without a window), `Sources/ccc` (CLI, headless
runner, PaneController, the AppKit/SwiftUI window), `Tests/CCCKitTests`
(+ fixtures). Environment: `CCC_CLAUDE` (path to `claude`),
`CCC_CONTROL_SOCKET`, `CCC_HOSTS` (the host list, default
`~/Library/Application Support/ccc/hosts.json`), `CCC_SSH_CONTROL_DIR` (where
the per-host ssh master sockets live), `CCC_CORE=ghostty|swiftterm` (the pane's core;
ghostty is the default), `CCC_METAL=1` (SwiftTerm's own Metal renderer, only
under the escape hatch; ~250 MB, see DESIGN.md).
