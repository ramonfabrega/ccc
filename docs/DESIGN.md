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
  stand-in is materially stronger than the canon claimed: `SwiftTermHost`
  turns Metal on by default, so v0 already has a GPU path while our renderer
  is written, and the six checks run against that baseline.
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
