# The six checks — the v1 scoreboard

The pane swap (docs/TERMINAL.md "The seam") happens when `GhosttyHost` + our
renderer beats `SwiftTermHost` on these, judged against the same recorded
session and the same live `claude attach`. Each row names how it is measured
so a number here is reproducible, and the SwiftTerm column is the v0
baseline (CoreGraphics; Metal on is a second column when it matters).

| # | check | how measured | SwiftTerm (CG) | SwiftTerm (Metal) | Ghostty + ours |
|---|---|---|---|---|---|
| 0 | correctness | `ccc replay --core X` on every phase of `Fixtures/attach` equals the goldens | 4/4 (defines them) | same | **4/4** (300f8df) |
| 1 | kitty keyboard / shift-enter | with the child's kitty flags pushed, `ccc send --key shift-enter` reaches the child as `CSI 13;2u`; without, distinguishable from enter | via NSEvent → SwiftTerm (untested) | same | **✔** `GhosttyKeysTests`: kitty → `ESC[13;2u`; legacy → `ESC[27;2;13~` (modifyOtherKeys), enter stays `\r` |
| 2 | bracketed paste | `ccc send` of multi-line text arrives wrapped in `ESC[200~ … ESC[201~` when mode 2004 is on, raw when off | pending | pending | pending |
| 3 | mouse scroll in the transcript | wheel over the pane scrolls Claude's transcript (alt-screen: arrows or SGR mouse per negotiated mode); no jumps | pending | pending | pending |
| 4 | streaming throughput | `ccc bench Fixtures/attach/attach.bin --repeat 300`, release build, real chunking | 22.6 MB/s, 0.14 ms/snapshot | — | **285.7 MB/s**, 0.13 ms/snapshot (12.6×) |
| 5 | resize over ssh | `ssh -t localhost claude attach`, window resize → redraw within 1 frame at the new size, no torn rows (exp 3 for the harness side) | pending | pending | pending |
| 6 | detach keys | `ccc send --key ctrl-z` detaches cleanly (alt screen left, kitty popped, child exit 0) | ✔ (v0, socket) | ✔ | pending |
| M | memory attached | `ccc stats` footprint with one 100×30 pane attached | 40 MB | 287 MB | pending (bar: < 40) |
| M | idle footprint | `ccc stats`, no pane | 26 MB | — | pending |

Rules: numbers come from `ccc stats` / `ccc bench` / the tests, never from
Activity Monitor screenshots; a check is ✔ only with the command that
proved it in the cell; regressions in the SwiftTerm column are findings
about SwiftTerm and go to TERMINAL.md, not silently updated.
