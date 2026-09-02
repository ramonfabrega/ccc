# The terminal stack

Three parts, each ours or explicitly borrowed, each behind a seam.

## Core: libghostty-vt (vendored, pinned)

What it is: the VT parser + terminal state Ghostty extracted for embedders
(`include/ghostty/vt.h`). MIT, zero dependencies, no libc, C ABI, built with
Zig, confirmed on macOS/Linux/Windows/WASM. Exposes: SIMD parser; write
bytes; cursor, resize + reflow, row/cell/style/grapheme access; a **Render
State** module (incremental cell/attribute/color deltas for custom
renderers); scrollback with compression; search; selection; snapshot/
restore; OSC/SGR sub-parsers; paste validation; **key event encoding**
(kitty keyboard protocol included); Kitty graphics; tmux control mode.

What it is not: no PTY (libghostty-pty is planned, does not exist), no
rendering, no font shaping, no OS input capture.

Stability: the header says the API is incomplete and will change. The
engine underneath is Ghostty's production one. Pin a stable tag (≥ 1.3 — the
scrollback-prune leak fix), pin the Zig it needs, bump deliberately, absorb
breaks at compile time. Bindings exist for Rust, Node, Go; Swift wrappers
(`Lakr233/libghostty-spm`, `briannadoubt/GhosttyKit`) show the SwiftPM
pattern. Hashimoto announced a pure-Swift Metal renderer + Swift bindings
("coming soon", unshipped as of 2026-09-02) — check `ghostty-org` before
starting the renderer, and again before finishing it.

## Renderer: ours, Swift + Metal

A cell-grid renderer over the render-state deltas: a CoreText glyph atlas,
deltas → GPU buffers, cursor and selection overlays, one `CAMetalLayer` in
an `NSView`. Estimate 800–1,800 lines. Precedents to read, not copy:
`ocnc/spectty` (`TerminalMetalView` + CoreText atlas), `arach/Termini`
(SwiftUI + Metal + forkpty). Paneflow's postmortem is the honest warning:
the glyph atlas and box-drawing coverage are the long tail, not the PTY.

Scrollback policy is ours. Ghostty-the-app's footprint (10 MB per surface
default, cells preallocated at full width, and the ≤1.2.3 leak) is not
inherited by a single pane with its own limits.

## PTY: ours, forkpty over Darwin

`forkpty` opens the master/slave pair, forks, wires the child's stdio to the
slave, returns the master fd. Read the master on a background queue → feed
the core; write user bytes to the master; resize = `ioctl(TIOCSWINSZ)` on the
master, the kernel sends SIGWINCH to the child. A couple hundred lines. The
child is `claude attach <id>` or `ssh -t <host> claude attach <id>` with
`TERM=xterm-256color` until a feature needs `xterm-ghostty` (then install
the terminfo on our own hosts once).

## The seam

```
protocol TerminalHost {
  func feed(_ bytes: Data)          // child → core
  func write(_ bytes: Data)         // user → child
  func resize(cols: Int, rows: Int)
  func snapshot() -> Grid           // text grid; the headless / test surface
  var view: NSView { get }
}
```

Two implementations: `SwiftTermHost` (stock view; v0 stand-in, MIT, pin a
tag — a lifecycle/IO rewrite is in flight ahead of its 2.0) and
`GhosttyHost` (libghostty-vt + our renderer). The six checks that decide the
swap, run against a recorded `claude attach` session: kitty keyboard /
shift-enter, bracketed paste, mouse scroll in the transcript, streaming
throughput on a long response, resize over `ssh -t`, detach keys.

## Headless from day one

The same binary runs without a window: `ccc attach <id> --headless` drives
the PTY and core and prints `snapshot()` as text; a scripted fake PTY replays
a recorded byte stream for tests. Record one real session early; it is the
fixture for every renderer change (native-sdk does exactly this — byte-
identical record/replay).
