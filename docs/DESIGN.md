# ccc — design narrative

Seeded 2026-09-02 from a three-way conversation (lore session, a dotfiles
session, the user in both windows). The conversation converged in this order;
each step's rejected alternative is recorded because it will be re-proposed.

## 1. Lore or a new app? — New app.

lore is read-only by charter: a deterministic index over transcripts, a server
that exposes no writers, a DB that is a rebuildable artifact. A driver (attach,
spawn, archive) needs a PTY and user-owned state that survives a rebuild.
Putting it in lore would make lore the thing it explicitly is not. lore's part
in ccc is this seed, a wiki page, and — optionally, never a dependency — its
JSON for history and fees per session.

**Rejected: lore as the notification receiver.** Proposed and withdrawn the
same day. The always-on app IS the receiver; a hook can POST to it on
localhost; cross-device is the app's concern. ntfy (dotfiles #49) is banked,
not live.

## 2. What it is — a client, not a harness replacement.

The daemon owns durable sessions with exclusive attach. `claude logs` is a
snapshot, not a stream, so a read-only mirror of a session on another machine
is impossible without forking the harness — which we will not do. That
ceiling closes the axis Superlogical is shipping on (durable sessions,
multi-client screens). Given it, ccc is the agents view with our UX on top,
and the ambition budget goes where the harness leaves room: ssh hosts, the
roster, notifications, spawning.

**Rejected: tmux anywhere.** The daemon is the multiplexer; attach is its
client.

## 3. The embed is the whole decision.

Everything else in the app is a list and a JSON poll. The embed sets the
language and fixes how the app hosts a PTY. Researched 2026-09-02 (five Sonnet
spawns, verified, ledgered in the lore wiki):

- **Rust + GPUI — rejected.** A stack preference, not a merit: GPUI's strength
  is an editor-grade GPU UI and ours is a list; it is pre-1.0 and just split
  (`gpui` vs `gpui-ce`); Zed's `terminal_view` has 28 workspace deps and is
  not liftable; the prior art (`gpui-terminal`, `gpui-ghostty`, paneflow) each
  spent the long tail on glyph atlases or carry GPL/Zig costs. The ssh feel we
  admire in Zed lives in Zed's remote server, not in GPUI.
- **Forking Ghostty (the cmux path) — rejected.** Not months, as first
  estimated (cmux's weight is its remote daemon, not the embed), but the
  surface API is explicitly internal (`include/ghostty.h`: "not designed for
  external use… use libghostty-vt"). A permanent tracking tax for a library
  its author says not to use.
- **SwiftTerm as the final pane — rejected; kept as the v0 stand-in.** MIT,
  one import, a documented `HeadlessTerminal` seam — but **no Metal renderer**
  (a 2022 proposal never built; an earlier report claiming one was wrong),
  CoreText per-cell compositing with a documented perf problem under
  alternating styles, and open mouse-reporting bugs. Right floor, not the
  ceiling.
  **Finding (2026-09-02, from the vendored source, not the web):** the
  "no Metal renderer" claim is wrong for v1.20.0. `Sources/SwiftTerm/Apple/
  Metal/` ships `MetalTerminalRenderer`, a CoreText glyph atlas, and a
  recovery policy that falls back to CoreGraphics on stalls; on macOS the
  toggle is **public API**: `MacTerminalView.setUseMetal(_:) throws`,
  `isUsingMetalRenderer`, `metalRendererStatus`, `drawMetalFrameNow()`
  (lore verified against the pinned checkout, 5d14406). The research spawns
  were Sonnets reading the web (GitHub issue #202, 2022), not the code. This
  does not reopen the decision — the reasons libghostty-vt wins are the core
  (parser, render-state deltas, key encoding), not the paint — but the v0
  stand-in is materially stronger than the canon claimed, and the six checks
  should run against it with Metal on (`CCC_METAL=1`).
  **Measured the same day:** SwiftTerm's Metal path costs ~250 MB of
  phys_footprint in ccc (287 MB attached vs 40 MB with CoreGraphics; 26 MB
  idle), and its `MTKView` is invisible to the cacheDisplay capture behind
  `ccc peek`. So v0 ships Metal **opt-in**, and this number is the first
  entry on the v1 scoreboard: our renderer has to beat 40 MB attached, not
  287.
- **native-sdk.dev — not for us, but a validation.** Vercel Labs' TS+Zig
  desktop toolkit (custom Metal renderer, pre-1.0, four months old) ships a
  `<terminal>` element whose core is libghostty-vt with their own PTY and
  paint: the exact pairing we chose, seen working. (`fx.sh` is unrelated — a
  Zig coding-agent TUI.)
- **libghostty-vt + our own Swift Metal renderer + our own PTY — chosen.** The
  "WebKit of terminals": the core Ghostty extracted for embedders, MIT, zero-
  dep C ABI, SIMD parser, full state, a render-state module for custom
  renderers, key encoding, search/selection/reflow. Neovim has an open issue to
  move onto it from libvterm (archived June 2026); Hashimoto has announced a
  pure-Swift Metal renderer + bindings (unshipped); Swift+Metal precedents
  exist (spectty, Termini). The scry-shaped answer: the good internals,
  our shell.

**On Ghostty's memory reputation:** deserved, and it belongs to the app, not
the core — a real unbounded scrollback-prune leak through 1.2.3 (tens of GB,
Claude Code's output a cited trigger; fixed in 1.3, not backported) plus a
10 MB-per-surface scrollback default with cells preallocated at full width.
A single embedded pane using only the core inherits neither, because the
scrollback policy and the renderer are ours.

## 4. Sequencing — replicate, then add.

v0 is the agents view: roster, one pane, attach, detach, local host. The SOTA
pane is a contained module developed behind the seam and swapped in when it
wins on six checks. Then ssh hosts, notifications, archive/grouping, spawn
and drafts. Each milestone is comparable against the agents view on its own.

## 4a. A session's address is `host:id` (v2, 2026-09-02)

v0 and v1 addressed a session by the harness's short id alone. That only
holds while one daemon is in view: each Mac runs its own, each mints its own
ids, and nothing stops two from minting the same one. From v2 the address is
`SessionRef` — `studio:a1b2`, and bare `a1b2` when the host is `local`, so
everything a v1 hand or script already types keeps meaning what it meant and
a one-Mac roster prints exactly as it did (verified: `ccc list` on this Mac
is byte-identical in shape to v1 — no host column until a second host has
rows).

Three consequences worth naming, because each was a choice:

- **The host lives on `SessionRow`, not `Session`.** `Session` is the
  harness's shape, decoded leniently at the boundary; the daemon has no idea
  other Macs exist. Which daemon answered is ccc's knowledge, so it sits on
  ccc's side of the struct.
- **The wire label stayed `id`.** A case label *is* the JSON key, and a v1
  `ccc` on PATH sends `{"attach":{"id":"a1b2"}}`. `SessionRef` decodes from
  that bare string as the local ref it always meant, so the older side keeps
  working (`ControlWireTests`' rule) without a hand-written decoder for
  eleven cases. `SessionRef` encodes as one string everywhere for the same
  reason it reads well: an agent pastes what `--json` printed straight back
  into `ccc attach`.
- **One `ssh` prefix, one function.** `ClaudeCLI.argv(_:tty:)` is the only
  place a host becomes a command, so the poll, the PTY's argv and the line
  the roster offers to copy cannot drift. `-t` only for attach: a poll with
  a tty would make `claude agents --json` negotiate a terminal and stop
  being a clean pipe.

**The model column over ssh — settled 2026-09-02: ask the far side's own
`ccc`.** `ModelProbe` joins the model by reading
`~/.claude/projects/<mangled cwd>/<id>.jsonl`, which only works where the
daemon and the filesystem are the same machine. The candidates were a batched
remote reader, pushing the mangle to the far side, or giving the model column
a slower cadence than state — and the measurement threw out the last one and
suggested a fourth.

*What the measurement said* (`ccc stats`, 24 ticks over 19 sessions, the
instrumentation added for exactly this question):

```
roster poll  last 387 ms  mean 199 ms  n=24
model join   last  13 ms  mean   9 ms  reads 22  cached 338  gone 0  well lookups 63 (48 unresolved)
```

The join is **9 ms — 4.5% of the poll**, and the 199 ms is the `claude
agents` process spawn, which nothing in the model column can touch. The
`(size, mtime)` cache is why: 338 hits against 22 reads, because a transcript
is only re-read when it actually changed. Even the wasteful path stays
invisible — 48 of 63 well lookups resolve to nothing and re-scan every well
each tick. **So the local cadence is left exactly as it is**; decoupling it
would have bought 9 ms and cost real complexity.

The remote case is different in kind, not degree: the join is cheap locally
*because the filesystem is local and cached*, and over ssh it can never be.
So the answer must remove the round trips rather than make them cheaper —
`Host.ccc` names ccc on the far side, and the poll asks it for
`ccc list --json`. The far side does the join where the filesystem is and
hands back finished rows inside the one round trip we already pay: 17
sessions, 15 with a model, 213–284 ms — no worse than the harness reader
that returns no models at all. There is no remote helper to deploy and no
inline shell blob, because the thing we call is our own command twin. When
`Host.ccc` is unset the reader falls back to `claude agents --json --all`,
which is a correct roster with a blank model column.

Two rules that fell out of building it, both of which cost a live failure
first:

- **`ccc list` exits 3 for "rows are fine, shape changed".** The first
  version of the remote reader treated any non-zero exit as failure and
  dropped 17 good rows over a warning — the "never an empty list" rule,
  broken by us rather than by the daemon. Exit 3 is now a reading *with a
  warning*, and the far side's banner crosses the hop into ours.
- **`ccc list --json` writes its issues to stderr.** Exit 3 alone told a
  caller *that* something changed and never *what*; stdout stays pure JSON.

## 4b. What actually sleeps is the client (v2, 2026-09-02)

The fan-out was first designed for "N hosts, several of them Macs that come
and go", which is the wrong shape for this fleet. **air is a client only —
it never runs sessions.** Every session runs on studio, so from air the host
list is `{local (empty), studio}` and studio is essentially always up
(barring a rare lock/sleep with caffeine off). What sleeps is *the machine
doing the polling*: the lid closes mid-sentence, nothing on studio stops, and
on wake our sockets are stale.

So the everyday failure is not "a host is unreachable" but "our own
connection is wedged", and the two need different answers. Backoff against a
dead host is near-worthless here; **reconnect hygiene is the feature.**

**Measured 2026-09-02** (release, host `loop` = localhost through the ssh
path; a suspended master, `kill -STOP`, is the lid-close shape — socket
present, peer not answering):

| case | how it was made | result |
|---|---|---|
| healthy warm poll | — | **215–364 ms** |
| master died (`kill -9`), stale socket left behind | process gone | **316 ms — recovers by itself.** ssh sees the dead socket and connects fresh; a non-issue |
| unreachable host | `--ssh 192.0.2.1` (RFC 5737 TEST-NET) | **5083 ms, clean failure**, `ssh to dead failed: … Operation timed out`. `ConnectTimeout=5` holds |
| **wedged master** | `kill -STOP` the mux process | **5281 ms and then SUCCEEDS** — and *every* subsequent poll pays it again (5258 ms), forever |
| same, after evicting the socket | `rm loop.sock` | **364 ms** — back to healthy immediately |

Two corrections to what we believed going in:

- **`ConnectTimeout` does bound the mux wait**, not just the initial TCP
  connect. The prediction that a wedged master would hang for minutes was
  wrong; it degrades to `ConnectTimeout` and then falls back to a direct
  connection. Good news, and it means `ServerAliveInterval` is not the
  missing piece it looked like.
- **But ssh never evicts the bad socket.** It re-tries the wedged mux on
  every single invocation, so a 215 ms poll becomes a *permanent* 5.3 s poll
  against a 2 s tick — the poller is then always behind and burns 5 s a
  turn. This is the real bug, and it is ours to fix, not ssh's.

The fix therefore is not timeout tuning: it is **evicting the master when a
poll comes back degraded** (unlink the socket, or `ssh -O exit`), which
restores full speed on the next tick. `NSWorkspace.didWakeNotification` is
the cheap proactive half — on wake, drop the master and re-poll at once
instead of waiting for one 5 s tick to discover it. Open, and worth a
measurement rather than a guess: whether a real lid-close/wake produces the
wedged shape at all, or whether macOS tears the socket down cleanly (in
which case the `kill -9` row above is the true everyday path and there is
almost nothing to do).

**Measured with a real lid 2026-09-02** (air → studio over the tailnet,
`~/lidtest.py` on air: the exact ssh prefix above around
`claude agents --json --all` every 2 s; an attach held through the same
master in a second terminal):

| case | result |
|---|---|
| cold start | 791 ms, then 210–300 ms warm |
| lid closed 1 min 54 s, reopened | **first poll 2136 ms, exit 0; next poll 352 ms; no error, no eviction needed.** The master survived the sleep |
| the attach through the same master | still live after wake; typing continued |

So a short sleep on the tailnet is the *clean* case — better than the
`kill -9` row, since nothing even reconnected. The wedged shape has not been
seen in reality yet. Open: a long sleep (thirty minutes, overnight), which
is the everyday case and the one where the user's plain `ssh studio` does
die. Until that is measured, eviction-on-degraded-poll stays in the slice as
insurance (it is twenty lines and a false eviction costs one handshake), and
the wake notification's immediate re-poll is worth having regardless — it
turns "up to 2 s of tick plus 2.1 s" into 2.1 s.

**Shipped 2026-09-02** as v2 slice 2 (docs/MILESTONES.md): per-host slots
merged at read time, one in-flight tick per host, eviction on a degraded or
failed hop, the wake re-poll and its `ccc hosts reconnect` twin. And one
finding that only the default path could produce: the master socket lived
under `~/Library/Application Support`, whose space `-o ControlPath=`
rejects outright — every ssh through the default location had been failing
since slice 1, invisibly, because every measurement above ran with
`CCC_SSH_CONTROL_DIR` pointed elsewhere. The sockets are under
`~/Library/Caches/ccc/ssh` now, and the argv test pins "no whitespace".
The lesson is the project's usual one: the override that makes an
experiment convenient is also what keeps the default path unmeasured.

## 4c. The daemon multiplexes viewers (v2, 2026-09-02)

The v2 design nearly grew a second layer. With "single attach" taken as
fact, a two-Mac roster forced a choice: either each ccc attaches on its own
and fights for the lock (model A — reattach on wake races sshd reaping the
dead client, and walking to the other Mac means detaching first), or the
always-on studio ccc holds the one attach and air mirrors *studio's ccc*
through a new stream verb on the control socket (model B — the DX of two
`claude agents` views, at the cost of one ccc depending on another). B was
chosen on paper. Then `scripts/attach-probe` measured what the daemon
actually does (docs/HARNESS.md experiment 2):

- A second `claude attach` is **accepted**. Output is broadcast to every
  viewer, input from any viewer goes in, and a viewer whose terminal dies
  is gone within a second with nothing to clean up.
- Every viewer talks to the daemon's `control.sock`; the daemon holds the
  one connection to each session's pty host and proxies the pane. The
  daemon *is* the multiplexer — the CLAUDE.md line meant more than we knew.

So the fork collapses to **A's mechanics with B's semantics, and nothing
of ours in between.** ccc on air runs `ssh -t studio claude attach <id>`;
ccc on studio runs the same words locally; both are viewers of one PTY.
No ccc depends on another ccc, independent focus per Mac is free, and
"server" versus "client" is nothing but the host list: every ccc serves the
sessions its own daemon runs and reads every host it lists. Should studio
die, sessions started on air are air's and a third device lists air.

The one cost the harness hands us is **size**. The shared PTY takes the
last resize from any viewer and never shrinks back, so a laptop and a big
monitor on the same session redraw each other. Two agents views behave
identically today; the user lives with it. Because ccc owns its renderer
it can do better — render the session's grid inside whatever window it has
rather than resizing the PTY from a secondary viewer — and that is slice 4's
question, a nice-to-have, not a blocker.

## 6. Distribution: the fleet's release flow, Sparkle from day one (2026-09-02)

The question was "build from source on air, copy a bundle, or package like
mux and disk?" The answer was decided by two facts. Air refuses ssh, so
nothing can be *pushed* to it: every update is a pull. And an ad-hoc
signature is one Mac's alone — lore's canon from disk and mux is that an
ad-hoc app on another machine churns its identity on every rebuild
(Gatekeeper, TCC, and the login item, which is a locked decision here).

So ccc is the third consumer of the mux release flow (disk's
`scripts/package`, cloned minus the universal build: the fleet is Apple
silicon only, and a universal cut would mean building libghostty-vt for
x86_64 through Zig). Developer ID + hardened runtime, notarized and
stapled, a single-item Sparkle appcast on the CDN under `ccc/`, two stable
keys overwritten per release, the fleet's one EdDSA key. **Every Mac runs
the release build**, studio included (`scripts/install --dist`); the ad-hoc
`scripts/install` is only the dev loop on studio. RELEASES.md is the runbook.

**Sparkle is the second earned dependency** (after SwiftTerm, which is on
its way out). Earned by: air can only pull; the CDN half is already
generalized by the fleet; the app side is one file and three plist keys;
and the alternative is a hand-downloaded zip on every update. What it
costs: a framework re-signed inside-out at package time (its XPC services
must carry our team id under library validation), and one relaunch per
update — which is why the window now remembers its attached session in
UserDefaults and reattaches after a relaunch, the way the agents view keeps
its focus. Lore's note that a third consumer is the extraction threshold
for a shared release package is a fleet chore, recorded, not ccc's.

## 7. The human's screen is the oracle for presentation (2026-09-02)

The Metal pane was black on screen for the whole of v1 and v2, and every
check passed. `ccc peek` composites the pane from `snapshotImage()` — an
offscreen render of the same frame — so the agent saw a perfect TUI while
the human saw black, and the six checks (docs/CHECKS.md) had been judging
the *renderer*, never the *presentation*. The user noticed; the agent
could not have.

Two causes, one lesson.

- **The bug:** the view invalidated (`needsDisplay = true`) and waited for
  AppKit's `updateLayer`, the pattern every layer-backed view uses. A
  `CAMetalLayer` owns its contents: AppKit reports `needsDisplay` false
  right after it is set (measured with a trace), and `updateLayer` never
  comes. The pane now draws the moment a frame arrives, as every Metal view
  does; coalescing stays in `GhosttyPane.scheduleFrame`. (`makeBackingLayer`
  over assigning `layer` was also made right along the way, and was not
  the fix on its own.)
- **The gap:** nothing in the app could say "frames reached the layer".
  `TerminalHost.presentation` now counts drawables presented and when the
  last one was, `ccc stats` prints it, and bytes-in with zero frames is a
  warning line. That is the number both sides can read.

The lesson is the parity rule turned on ourselves: **the agent and the
human must see the same thing, and where they cannot, the agent needs a
number that says so.** `ccc peek` stays as the layout composite (it is
TCC-free and works while unfocused); a real `screencapture` is the oracle
for "is it on screen", and CHECKS.md's window row is re-judged with one.
The same day found `Updater` blocking the main thread in a modal Sparkle
alert when run unbundled — visible only as a control socket that never
answered, diagnosed with `sample`. Same shape: the face the agent uses
(the socket) went quiet, and nothing said why.

## 5. Negations held (claims the plan assumes; go in holding the opposite)

- "The daemon's surface is stable." It is `proto: 1`, undocumented past
  "unknown fields preserved". → lenient decoding, a banner on shape change.
- "Two attaches to one session are fine." Documented as refused. → single
  attach; one experiment records the exact behavior across two Macs.
  **Reversed by measurement 2026-09-02 (§4c):** the daemon accepts every
  attach and mirrors one PTY to all of them. The negation held the wrong
  way round — "refused" was the assumption, and it cost a whole model (B's
  stream verb) before the probe was run.
- "More notifications is better." Remote Control push + ntfy + an app notifier
  is three buzzes. → Mac first; RC push stays until the app earns the phone.
- "The agents view's hooks keep firing." `agent_needs_input` and
  `agent_completed` fire only while the agents view is open. → derive both
  from the roster poll.
