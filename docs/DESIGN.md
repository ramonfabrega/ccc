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

## 5. Negations held (claims the plan assumes; go in holding the opposite)

- "The daemon's surface is stable." It is `proto: 1`, undocumented past
  "unknown fields preserved". → lenient decoding, a banner on shape change.
- "Two attaches to one session are fine." Documented as refused. → single
  attach; one experiment records the exact behavior across two Macs.
- "More notifications is better." Remote Control push + ntfy + an app notifier
  is three buzzes. → Mac first; RC push stays until the app earns the phone.
- "The agents view's hooks keep firing." `agent_needs_input` and
  `agent_completed` fire only while the agents view is open. → derive both
  from the roster poll.
