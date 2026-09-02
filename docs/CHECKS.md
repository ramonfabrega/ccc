# The six checks — the v1 scoreboard

The pane swap (docs/TERMINAL.md "The seam") happens when `GhosttyHost` + our
renderer beats `SwiftTermHost` on these, judged against the same recorded
session and the same live `claude attach`. Each row names how it is measured
so a number here is reproducible, and the SwiftTerm column is the v0
baseline (CoreGraphics; Metal on is a second column when it matters).

| # | check | how measured | SwiftTerm (CG) | SwiftTerm (Metal) | Ghostty + ours |
|---|---|---|---|---|---|
| 0 | correctness | `ccc replay --core X` on every phase of `Fixtures/attach` equals the goldens | 4/4 (defines them) | same | **4/4** (300f8df) |
| 1 | kitty keyboard / shift-enter | with the child's kitty flags pushed, `ccc send --key shift-enter` reaches the child as `CSI 13;2u`; without, distinguishable from enter | via NSEvent → SwiftTerm (untested) | same | **✔** `GhosttyKeysTests`: kitty → `ESC[13;2u`; legacy → `ESC[27;2;13~` (modifyOtherKeys), enter stays `\r`. Live (window pane, socket `send --key shift-enter`): Claude's prompt grew a line instead of submitting |
| 2 | bracketed paste | `host.paste` of multi-line text arrives wrapped in `ESC[200~ … ESC[201~` when mode 2004 is on; unbracketed, LF becomes CR | no programmatic paste API (SwiftTerm frames only its own `paste:` responder) | same | **✔** `GhosttyReplayTests.pasteIsBracketed…` (core frames; `ccc send` twin pending) |
| 3 | mouse scroll in the transcript | wheel over the pane scrolls Claude's transcript (alt-screen: arrows or SGR mouse per negotiated mode); no jumps | pending | pending | pending |
| 4 | streaming throughput | `ccc bench Fixtures/attach/attach.bin --repeat 300`, release build, real chunking; equal-work columns: same grid digest, scrollback rows, Δfootprint | 13.6–22.9 MB/s (two runs; noisy), 0.14 ms/snapshot, Δ0.7 MB | — | **286–296 MB/s**, 0.13–0.19 ms/snapshot, Δ0.8 MB, **same grid digest** (12–21×). Caveat: the fixture is alt-screen, scrollback 0 on both, so reflow/scrollback cost is not yet compared — needs a primary-screen recording |
| R | renderer frame time | `RenderTests/offscreenFrameTiming`, 120×40 mixed styles, offscreen, waits for completion | n/a (SwiftTerm draws its own) | — | 7.9 ms debug / **1.10 ms release** per frame; atlas A8 2048² = 4 MB eager, BGRA 1024² lazy |
| 5 | resize | `ccc window resize W H` → grid, PTY and child follow; redraw at the new size, no torn rows. (The ssh hop is v2; exp 3 proved SIGWINCH crosses it) | pending | — | **✔** window path: 95×50 → 64×31 → 104×56, last non-blank row = rows−1 each time, status line intact, peek clean |
| 6 | detach keys | `ccc detach` (Ctrl+Z through the host's encoder) ends the attach client, session stays alive | ✔ (v0, socket) | ✔ | **✔** live via the window pane: `detached 78bb5bd1`, session `done · idle` in the roster after |
| M | memory attached | `ccc stats` footprint with one pane attached (window). **All three columns are debug builds** (`swift build`, 2026-09-02): the v0 baseline was never measured in release, so this row compares debug to debug until the release row below exists | 40 MB (debug, 105×50) | 287 MB (debug) | 39.9 MB (debug, 95×50, 4 MB A8 atlas inside); 3 attach/detach cycles: 48.7 MB after the first detach, then steady at 42.8 MB after every attach and detach — retention, not a leak |
| M′ | memory attached, release | `swift build -c release` (b64bbc7), window, same session `45988a93`, `ccc stats` idle → attached → detach → re-attached | idle 28.3 MB; attached **42.2 MB**; re-attached 42.5 MB | — | idle 28.5 MB; attached **32.1 MB**; re-attached 32.3 MB (10 MB under SwiftTerm CG, atlas included) |
| M | idle footprint | `ccc stats`, no pane, debug | 26 MB | — | 30.4 MB (renderer/atlas not yet allocated; the delta is the core library) |

Rules: numbers come from `ccc stats` / `ccc bench` / the tests, never from
Activity Monitor screenshots; a check is ✔ only with the command that
proved it in the cell; regressions in the SwiftTerm column are findings
about SwiftTerm and go to TERMINAL.md, not silently updated.
