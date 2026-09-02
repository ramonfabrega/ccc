# ccc

Claude Code Command — a native macOS client for Claude Code's background
sessions. The `claude agents` view, replicated, then made ours: roster,
attached terminal, notifications on every device, ssh hosts as first-class.

Private. See `CLAUDE.md` for the thesis and locked decisions, `docs/` for the
design narrative, the harness fact sheet, the terminal stack, and the queue.

```
docs/DESIGN.md      decisions + rejected alternatives
docs/HARNESS.md     the daemon / attach / hooks surface, triaged
docs/TERMINAL.md    libghostty-vt + our Metal renderer + our PTY
docs/MILESTONES.md  the queue, v0 → v5, and the experiments
```

**Status: v0 (2026-09-02) — the agents view, local.** One binary, two
faces: `ccc` with no arguments opens the window (roster + attached pane +
menubar item); every gesture has a command twin over a unix socket.

```
swift build && swift test           # 42 tests: roster decoder, model probe, PTY, replay golden
scripts/install                     # → ~/Applications/ccc.app + `ccc` on PATH (symlink into the bundle)

ccc list [--json]                   # the roster with the model column (no app needed)
ccc attach <id> [--headless]        # attach in the window, or headless: a PTY + the socket, no window
ccc snapshot [--json]               # the pane's grid as text — how an agent sees what you see
ccc send "text" | --key ctrl-z      # type; named keys take SwiftTerm's own key path
ccc detach | resize <c> <r> | stats # detach; resize (headless); memory / poll latency / PTY B/s
ccc peek [out.png]                  # PNG of the window from our view hierarchy (no screen permission)
ccc replay <bytes> [--bytes N]      # render a recording headlessly (the golden-test oracle)
scripts/record-attach <id>          # record a real `claude attach` as the replay fixture
```

Layout: `Sources/CCCKit` (roster, transcript, PTY, terminal seam, control,
stats — everything without a window), `Sources/ccc` (CLI, headless runner,
PaneController, the AppKit/SwiftUI window), `Tests/CCCKitTests` (+ fixtures).
Environment: `CCC_CLAUDE` (path to `claude`), `CCC_CONTROL_SOCKET`,
`CCC_METAL=1` (SwiftTerm's Metal renderer; ~250 MB, see DESIGN.md).
