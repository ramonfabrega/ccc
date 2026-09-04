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

### Calling conventions learned the hard way

`docs/vt/surface.txt` proves what exists; this list proves how it is called.
Each line cost a crash or a wrong byte before it was written down.

- `ghostty_terminal_set`: pointer-typed values (userdata, every callback)
  are passed **directly** as `value`; non-pointer values by pointer. The
  doc is on the function, not on the enum. (SIGSEGV, 2026-09-02)
- Render-state getters for pre-allocated handles (`ROW_ITERATOR`,
  `ROW_DATA_CELLS`) take the **address of the handle variable** — the
  generic "out points at a value of the type" rule, where the type is the
  opaque pointer. Passing the handle itself yields an empty grid.
- One render state per terminal: `ghostty_render_state_update` consumes
  the terminal's dirty flags, so a second render state on the same
  terminal sees nothing. The text snapshot reads the renderer's state
  with `consume: false`.
- `GhosttyCell` is a packed `uint64_t`, passed **by value** to
  `ghostty_cell_get`.
- **Sized structs — a library-wide convention, not a gotcha.** Every struct
  with a leading `size_t size` (`GhosttyStyle`, `GhosttyRenderStateColors`,
  `GhosttyPaste`, `GhosttyMouseEncoderSize`, …): set
  `size = MemoryLayout<T>.size` before the call. **A zeroed one succeeds
  and does nothing.** Swift's `T()` zero-initializes `size`. Instances so
  far: default fg drawn black on black (misdiagnosed as a bold-glyph bug
  for an hour); mouse encoder sized 1×1 so every position but (0,0)
  encoded to silence.
- `modes.h`'s `GHOSTTY_MODE_*` are macros over a static inline and do not
  import into Swift; call `ghostty_mode_new(n, false)`.
- `GhosttyKey.rawValue` imports as `Int32`.
- A raw terminal handle held outside its host is a use-after-free under
  ARC; wrappers retain the host.
- Key bytes the core actually emits (protocol named): shift-enter without
  kitty → `ESC[27;2;13~` (modifyOtherKeys CSI 27), not CR; with kitty
  disambiguate → `ESC[13;2u`; backspace → `0x7f` (DECBKM off); home/end →
  `CSI H/F`, following DECCKM; f1 under kitty → `CSI P`; cmd/super has no
  encoding.
- Paste: `ghostty_terminal_paste` wants a `GhosttyPaste` with `size` set,
  one MIME entry and a `GhosttyMimeReader` whose callback streams the
  bytes to the provided writer; the core frames per mode 2004 and writes
  through `WRITE_PTY`. `GHOSTTY_PASTE_SOURCE_CLIPBOARD`, not `_PASTE`.

## Renderer: ours, Swift + Metal

A cell-grid renderer over the render-state deltas: a CoreText glyph atlas,
deltas → GPU buffers, cursor and selection overlays, one `CAMetalLayer` in
an `NSView`. Estimate 800–1,800 lines. Precedents to read, not copy:
`ocnc/spectty` (`TerminalMetalView` + CoreText atlas), `arach/Termini`
(SwiftUI + Metal + forkpty). Paneflow's postmortem is the honest warning:
the glyph atlas and box-drawing coverage are the long tail, not the PTY.

**What Zed does (read 2026-09-02 at zed `97b1e64`, by a Sonnet spawn; take
the technique, not the code).** Core is a Zed fork of `alacritty_terminal`;
`terminal_element.rs` rebuilds the visible cells only when the terminal
mutates, not per frame. Paint: per row, adjacent same-style cells are
greedily merged into one shaped text run (font/fg/bg/underline/strike
equal), so shaping is per run, not per cell; backgrounds are merged into
per-row spans and drawn as quads; the cursor is a quad whose width is
`max(shaped width, cell width)` so wide glyphs are not clipped; wide-char
spacer cells skip text but keep their background; block/sextant glyphs are
drawn as sub-cell quads on an 8×24 subgrid, never shaped. Frame pacing: no
timer — the PTY loop handles the first event immediately for latency, then
coalesces for 4 ms (cap 100 events, repeated wakeups collapsed) into one
update and one repaint. Glyphs: CoreText into an 8-bit alpha atlas
(`A8Unorm`) for monochrome and BGRA for color, 4 subpixel x-variants per
glyph, shaped-line cache two frames deep. Scroll: integer line offset into
the grid; trackpad pixels accumulate and emit whole lines; in the alt
screen wheel becomes arrow keys (alternate-scroll mode) or SGR mouse
reports. Bugs they fixed in the last year, which our renderer inherits as
checks: resize jitter and flicker (twice), pixel-snapping cell rects (merged
and reverted the same day), cursor stretching on wide glyphs, zero-width
combining characters, sextant coverage. GPUI itself is not liftable into a
Swift window — it owns the window and the language — but every item above
maps onto libghostty-vt's render state (dirty rows, per-cell resolved
colors, grapheme UTF-8) plus one `CAMetalLayer`.

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
@MainActor protocol TerminalHost: AnyObject {
  func feed(_ bytes: Data)                       // child → core
  var onOutput: ((Data) -> Void)? { get set }    // core → child (key encodings, query replies, paste framing)
  var keyInterceptor: ((NamedKey) -> Bool)? { get set }  // the one gate on the key path (the ← guard)
  func resize(cols: Int, rows: Int)
  func snapshot(colors: Bool) -> Grid            // the headless / test surface; colors on request
  var view: NSView? { get }                      // nil for a headless host
  var presentation: (frames: Int, lastAt: Date?)? { get }  // what reached the screen
  func press(_ key: NamedKey) -> Bool            // encoded by the core, never hand-rolled
  func paste(_ text: String) -> Bool             // framed as the child negotiated
  func setFocused(_ focused: Bool) -> Bool       // DEC 1004; what tells the harness nobody is here
}
```

(As of 2026-09-04, from `Sources/CCCKit/Terminal/TerminalHost.swift`; the
file is the truth and this block follows it.)

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

**Decided 2026-09-02: Ghostty took all six** (docs/CHECKS.md) and is now the
default core; SwiftTerm is reachable only as `CCC_CORE=swiftterm`. That
demotes the 2.0 break above from "absorb before shipping" to "absorb if we
ever need the hatch again" — and makes deleting `SwiftTermHost` a real
option once v2 stops wanting a second opinion on a rendering bug. Keep it
through v2 for that reason alone; the seam costs nothing to leave in place.

## Headless from day one

The same binary runs without a window: `ccc attach <id> --headless` drives
the PTY and core and prints `snapshot()` as text; a scripted fake PTY replays
a recorded byte stream for tests. Record one real session early; it is the
fixture for every renderer change (native-sdk does exactly this — byte-
identical record/replay).
