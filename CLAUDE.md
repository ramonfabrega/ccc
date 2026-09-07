# ccc — Claude Code Command

A native macOS client for the Claude Code harness's background sessions: the
`claude agents` view (the harness calls it *fleet*), replicated, then made
ours. Roster + attached terminal + notifications on every device + ssh hosts
as first-class citizens. Seeded 2026-09-02 out of `~/code/fun/lore`'s well;
the research trail, fact sheets, and spawn ledger live in the lore wiki
(`~/code/personal/lore-wiki/projects/ccc.md`). Decision narrative:
`docs/DESIGN.md`. Harness surface: `docs/HARNESS.md`. Terminal stack:
`docs/TERMINAL.md`. Queue: `docs/QUEUE.md`.

## Thesis

The harness already has the hard part — a daemon that owns durable sessions,
`claude --bg` to dispatch, `claude attach` to drive, a JSON roster to list.
Its TUI is the only part we want to change. **ccc is a client, never a harness
replacement**: it reads the roster, spawns and attaches through the same
commands, and adds what the TUI lacks — notifications on every device, our own
sort/group/archive, the model that is actually serving each session, better
spawning (including sessions that have not started), and ssh hosts that feel
local. Because the client is read-only plus attach, if the harness moves under
it the worst case is going back to the agents view for a week. **It may break;
it should break while being awesome.**

## Locked decisions (2026-09-02; rationale in docs/DESIGN.md)

- **Swift app shell.** AppKit window and terminal view, SwiftUI for the roster
  and chrome, menubar-resident, launch at login. The house stack (scry, wallgen).
- **libghostty-vt is the terminal core** — the embeddable VT parser + screen
  state Ghostty extracted for exactly this, MIT, C ABI, with a render-state API
  for custom renderers and a key encoder (kitty keyboard protocol included).
  Vendored as a git submodule **pinned to one explicit commit** with the Zig
  version it needs pinned alongside (`scripts/fetch-zig`); never tracks a
  branch. Amended 2026-09-02 from "latest stable tag": the terminal, screen,
  render-state and snapshot headers exist only past v1.3.1 — the release
  ships key encoder, OSC/SGR parsers, paste and color alone — so v1 pins
  main commit `3c1ef5b` (2026-09-01, Zig 0.16.0) and moves to a tag when one
  contains `terminal.h`. Its API is pre-1.0 and says so; breaks surface at
  compile time and are absorbed per bump.
- **Our own Metal cell-grid renderer in Swift** (CoreText glyph atlas, render
  state deltas → GPU buffers, cursor/selection overlay). Estimated 800–1,800
  lines. If upstream ships its announced Swift Metal renderer first, evaluate
  it against ours on the six checks below.
- **Our own PTY** via `forkpty` over Darwin: the master fd is what we read and
  write, resize is one ioctl, the child is `claude attach <id>` or
  `ssh -t <host> claude attach <id>`. No libghostty-pty exists.
- **The terminal sits behind a one-page seam** (feed bytes, write bytes,
  resize, snapshot). v0 may fill it with SwiftTerm's stock view to unblock the
  roster work; the libghostty-vt + Metal pane replaces it when it wins on:
  kitty keyboard / shift-enter, bracketed paste, mouse scroll, streaming
  throughput, resize over ssh, detach keys. **Settled 2026-09-02: it won all
  six (docs/CHECKS.md) and is the default; `CCC_CORE=swiftterm` is the
  escape hatch.** The seam stays — it is what made the swap a one-line
  change and what a third core would enter through.
- **PTY is always local; remote is the same command behind `ssh -t`.** Roster
  poll, attach, spawn: one prefix per host, one multiplexed ssh connection per
  host. Folders, git, worktrees fall out as cwd choices. No daemon of our own.
- **The fleet has one hop, and it points one way: air → studio.** Decided
  2026-09-03; Remote Login went on for studio the same day and the hop is
  live. Studio is always the host — the always-on Mac the agents run on;
  air is the roaming client that joins, which is also why every update is a
  pull (RELEASES.md). Any-Mac-to-any-Mac is a someday, not a goal.
  **This needs no enforcing and no mention.** Air is never
  remote-advertised and runs no sshd, so it cannot be a target and cannot
  appear as a candidate: there is nothing to filter, exclude by name, gate,
  or ask about. Test the remote path **studio → studio**. Written this way
  because the earlier phrasing ("nothing ever ssh's into air") read as a
  live constraint and sent two sessions designing around a noop.
- **TERM starts as `xterm-256color`.** Upgrade to `xterm-ghostty` (install the
  terminfo on our own hosts) only when a feature needs it.
- **Keys are the core's job.** AppKit key events → libghostty-vt's encoder.
  Never hand-roll escape sequences.
- **Boundary parsing, lenient.** The daemon's roster and `state.json` are
  undocumented past "unknown fields are preserved". Decode leniently, keep
  unknown fields, and when a required field goes missing show a "roster shape
  changed" banner — never an empty list, never a crash.
- **The poll is the first notifier.** `claude agents --json --all` carries
  `state: blocked` and `waitingFor`; a 2 s poll on every host is
  "it's your turn" on every Mac with no hook. The Notification hook reaches
  the app through `ccc hook` (v3 slice 2; `--settings` prints the entry, ccc
  never writes settings.json) and supplements only what the roster cannot
  show. A host can be muted (`ccc hosts mute`); the detector never is.
  **What it says comes from the daemon's job file**, amended 2026-09-04:
  the poll says *that* it is your turn, and `waitingFor` is absent exactly
  when it is wanted (measured: the one blocked session carried none). So
  `JobProbe` reads `detail`, `needs`, `output.result`, `suggestedReply`
  and `respawnFlags` (the `rc` mark, v13) out of
  `~/.claude/jobs/<id>/state.json` — five fields where v5 read one —
  joined on the local row like the model and carried across the hop. Still
  read-only, still lenient: a field that moves costs the banner its payload
  and nothing else. **Every line of a notification carries payload or is
  not drawn** — "is waiting", "on studio" and "Click to attach" were three
  constants and a name, and `children` (the job's PRs and artifacts) left
  the type when it measured as one too: ≤6% of banners drew this run's own
  work (docs/EVIDENCE.md "v11 slice 3", "v11 slice 4").
- **Every viewer attaches; the daemon mirrors.** Amended 2026-09-02 from
  "single attach, refused": measured (docs/DESIGN.md §4c), a second
  `claude attach` is accepted, output is broadcast to every viewer and input
  from any viewer goes in. So the pane on any Mac is `claude attach <id>`,
  behind `ssh -t` when remote, and no ccc ever depends on another ccc. The
  draft lives with the session. The shared PTY is last-resize-wins across
  viewers; whether a secondary viewer renders the grid as-is instead of
  resizing it is still open (docs/DESIGN.md §4c, docs/QUEUE.md item 15) and
  comes due the first time air joins a session studio already has up.
- **No tmux, ever.** The daemon is the multiplexer.
- **Every Mac runs the release build.** Developer ID + notarized + Sparkle
  over the CDN (`scripts/package`, RELEASES.md, docs/DESIGN.md §6) — the
  fleet's mux/disk flow. Air can only pull, and an ad-hoc app never leaves
  the Mac that signed it; `scripts/install` is the dev loop on studio only.

## Parity: the human and the agent are first-class over everything

- The same binary runs **headless**: no window, drives the roster and a PTY,
  prints the rendered grid as text. That is how an agent sees what the user
  sees.
- **Every gesture has a command twin** — list, attach, detach, resize, send
  keys, snapshot, spawn, archive. What can be scripted can be clicked and the
  reverse (lore's one-definition-many-surfaces rule).
- **Recorded sessions are fixtures.** One real `claude attach` capture is the
  replay every renderer change is judged against; headless render tests exist
  from day one. Pixels (argent screenshots) judge feel; the text grid judges
  correctness.
- **The human's screen is the oracle for presentation.** `ccc peek` composites
  the pane from an offscreen render, so it can show a perfect TUI over a pane
  that is black on screen — it did, for a day (docs/DESIGN.md §7). Judge "is it
  visible" with a real `screencapture`, and read `ccc stats`' presented-frame
  count: bytes in with zero frames is the black pane, stated as a number.
  Since 2026-09-03 that oracle has its twin: **`ccc capture`** shoots the
  window through `screencapture -l` and **`ccc pixel --cell … --expect`**
  makes the exit code the answer, so a colour is judged rather than looked at.
  The capture runs in the CLI and never in the app — Screen Recording
  permission belongs to whoever asks, and `peek` must stay permission-free.

## Hard constraints

- Never fork or patch the harness; never write to `~/.claude/daemon/*` or
  `~/.claude/jobs/*`. Read, spawn, attach — nothing else.
- Subscription OAuth only (fleet constraint inherited from lore). Never an API
  key; nothing here designs around API billing.
- Private repo. Nothing here ships to anyone else.
- One language per part: Swift for shell, renderer, PTY; **Zig only as the
  build step for the vendored core**. Nothing else earns a place in v0.
- Dependencies are earned per part, in `docs/DESIGN.md`, never assumed.

## Rules earned (each cost a release or a worker's merge)

Cross-surface: breakable from anywhere, which is why they are here rather
than in a surface doc (`docs/DESIGN.md` §9). Evidence in
`docs/EVIDENCE.md`.

- **A fix for a bug on the other Mac is unproved until a release carries
  it there.** Studio green is the control, never the measurement.
- **A verb with fewer surfaces than its opposite will be reported
  missing** — twin both directions, and make the verb list a type.
- **A string no test reads is a string nothing keeps true.** `ccc
  update`'s help went a release stale that way and cost a worker its
  merge.

## Fan-out rules (violations are findings, not workarounds)

- Ad-hoc spawns of generic agent types MUST pass an explicit model; omission
  inherits the main loop's model. Defined agents pin theirs in frontmatter.
- VERIFY the served model from the spawn's JSONL, never from the spawn
  parameter or completion notification. `lore spawns` mechanizes this post-hoc
  and flags requested-vs-served drift.
- Leave the fan-out legible to `lore index`, which is what actually builds the
  ledger (`lore spawns`: agentType, verified model, tokens, duration, per
  spawn). An explicit model and a real agent type are the whole obligation.
  **ccc never writes the ledger, or anything else, into the lore wiki** — see
  References.
- Prompts that drive CLIs pin the invocation (`claude`, `lore`, `ccc` on PATH —
  never a source path "from the current directory").

## References

- `docs/DESIGN.md` — decisions and rejected alternatives (GPUI, forking
  Ghostty, SwiftTerm as the final pane, native-sdk, paneflow/cmux, lore as the
  notification receiver).
- `docs/HARNESS.md` — the daemon/attach/hooks surface, triaged stable vs
  undocumented vs unknown, with the experiments that resolve the unknowns.
- `docs/TERMINAL.md` — the embed research and the core/renderer/PTY plan.
- lore wiki `projects/ccc.md` — origin conversation, spawn ledger, open
  threads. **Read-only from here, and not ccc's to maintain.** That page is
  produced by lore, either by an ingest that mines this repo and its wells or
  by a relay lore banks from a message — its own frontmatter records each
  section's provenance (`ingest #N — 1 miner + 1 canon auditor`), so a
  hand-written section both skips that pass and makes the provenance false.
  A ccc session with something lore should know sends it (`SendMessage` to
  `lore`) and stops there. Established 2026-09-03, after a session wrote a
  milestone section by hand and had to revert it.
- Prior art, read not copied: `arthjean/paneflow` (GPUI + alacritty core, GPL,
  built for parallel agents), `manaflow-ai/cmux` (forked Ghostty + remote
  daemon), `vercel-labs/native` (`<terminal>` over libghostty-vt with its own
  PTY and canvas), `ocnc/spectty` and `arach/Termini` (Swift + Metal over
  Ghostty's core). Superlogical (Hashimoto) is the durable-session multiplexer
  to watch; if it ships what the daemon lacks, ccc's session layer may move.
- The user operates suggest-first — challenge premises, propose alternatives.
