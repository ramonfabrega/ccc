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
engine underneath is Ghostty's production one. Pin one commit, pin the Zig
it needs, bump deliberately, absorb breaks at compile time.
**Vendored 2026-09-02 (v1 start):** the latest stable tag, v1.3.1, ships
only `key`, `osc`, `sgr`, `paste`, `color` in `include/ghostty/vt/` — no
terminal state at all. `terminal.h`, `screen.h`, `render.h`, `snapshot.h`,
`selection.h`, `search.h`, `grid_ref.h`, `modes.h`, `mouse.h` (~30 headers)
exist only on main, which needs Zig 0.16.0 (a real release, 2026-04-13). So
`vendor/ghostty` is pinned at main `3c1ef5b` (2026-09-01) and `.zig/` at
0.16.0 via `scripts/fetch-zig` (sha-pinned tarball, no Homebrew). main also
builds a static `libghostty-vt`, which is what SwiftPM links. Bindings exist for Rust, Node, Go; Swift wrappers
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

**Built 2026-09-02 (v0, pulled forward from v1 by the user).** 436 lines
with doc comments, not "a couple hundred": the cost was never `forkpty`
but two semantics the tests caught. (1) Reads and writes share one serial
queue; a write larger than the master's buffer deadlocked because the
child echoes, the master fills, the child stops reading, the writer spins
on EAGAIN — fixed by draining the read side while waiting for `POLLOUT`.
(2) EIO on the master does not prove the child exited (it may close its
tty fds and live on), so reaping is `WNOHANG` + a 2 s grace + SIGKILL, never
a blocking `waitpid` on the read queue. Also: `execve` over prebuilt PATH
candidates instead of `execvp` (Swift's Darwin overlay exposes `environ`
get-only), and the child resets signal dispositions before exec (a parent
that ignores SIGHUP would otherwise make the child immune to `terminate`).

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
tag — a lifecycle/IO rewrite is in flight ahead of its 2.0; **checked
2026-09-02: no 2.x tag exists, `v1.20.0` is the latest release, 2.0 lives on
`main` with commits two days old. Its migration guide removes
`TerminalView.getTerminal()`, which `SwiftTermHost` uses for the grid
snapshot and dims; the replacements are `terminalDimensions` and
`getBufferAsData(kind:encoding:)`, and `HeadlessTerminal.terminal` stays
public so the replay host is unaffected. That is the one break to absorb
when 2.0.0 tags — inside `SwiftTermHost`, nothing above the seam moves**) and
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
