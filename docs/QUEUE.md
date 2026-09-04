# Queue

What is next, and nothing else. A finished item leaves; its commands and
numbers go to `docs/EVIDENCE.md`, and **its argument stays in the
transcript for lore to mine**. Nothing is owed outside this repo — not
milestone narrative, not a ledger. A message to lore is for the
*perishable* and the *cross-project* only: a correction to something it
banked wrong, a finding another project needs before the next ingest, a
pattern candidate. Item numbers are stable addresses: append, never
renumber.

An item **inlines its conclusion**. A cold session reads this file and
CLAUDE.md, and must be able to start without opening a third thing; when
an item cites a past measurement it cites it by a string that appears
verbatim in `docs/EVIDENCE.md` (`experiment 2`, `waitUntilDrawn`,
`lidtest`) so the command behind it is one grep away.

## The frontier

**There isn't one, and that is the news.** v8 and v9 are done: the theme,
the attach transition, the colour oracle, the hop, colour (item 12), the
hand (item 13) and the picker (item 3) all shipped 2026-09-03/04, and
`docs/EVIDENCE.md` "v9 slice 1" … "v9 slice 7" carries the numbers.

What is left below is not a frontier. **Item 6 is air's** and happens on
its own the next time the lid closes overnight. **Item 14 needs a
terminal with Screen Recording permission** — a sitting, not a session.
Items 4, 5 and 7 are debt, leftovers and housekeeping, none with a
forcing function.

So the next thing is a **direction**, not an item. Whatever it is, the
client is still read-only plus attach (CLAUDE.md's thesis), and the
things that would change that — peek/reply without attach, RC-free
approvals, the phone — are under "Later" and have never been argued.

### 4. Debt: the blocking poll read

`ClaudeCLI.run` blocks a pool thread per host for up to its timeout
(`readDataToEndOfFile`). Fine at two or three hosts; wants a nonblocking
read before the host list grows. No forcing function yet.

### 5. Small leftovers

A sort by model. The Session menu's archive/pin items (the context menu
has them). **Selection autoscroll**, which waits on something larger than
it sounds: the core ships the tick event and reports a direction, but
**ccc has no scrollback viewport at all** — `GhosttyPane.scroll` forwards
every wheel event to the child (or falls back to arrows), so the 2,000
lines the core keeps are unreachable, and a drag that leaves the grid has
nothing to tick. Low value while the pane only ever runs `claude attach`,
which is on the alternate screen and scrolls its own history; stated here
so nobody starts the gesture believing the viewport is nearly there
(re-checked 2026-09-03). **`ccc window show` when another app holds
focus** — measured 2026-09-02 with a Wine window in front:
`NSApp.activate()` is cooperative since macOS 14 and the window stayed
behind while `open -a` brought it front, so `show`'s CLI side should
activate through `NSWorkspace`.

### 6. Two measurements that need the hop

Both are air's to run — the hop is live but these need air's own lid, so
neither can be forced from studio.

- **The ssh master's eviction.** `~/lidtest.py` runs on air appending to
  `~/lidtest.log`; that log decides whether the eviction ever fires
  (`ccc stats` → `evictions`). The file comes off air by air's own hand.
- **The remote pane's reattach across a real sleep.** `sshExit` within
  20 s of wake replays the same argv
  (`PaneController.reattachIfSleepKilledIt`), never yet through a lid.

### 7. Housekeeping: three branches to delete

Re-checked 2026-09-03 against `git branch -a`, which this item asked for:
`hotfix-gridbuilder`, `worktree-v0` and `worktree-v1` are merged into
master and safe to delete on origin. **`worktree-icon` is not merged** —
it was on the old list and does not belong in a bulk delete.

### 9. The attach transition: one end left

Shipped (docs/EVIDENCE.md "the attach transition, and the hole in the ←
guard"), and **proved over ssh 2026-09-03**: six alternating swaps between
two remote fixtures ran 1075–1385 ms against the local path's 1022–1086 ms,
every one answering "attached … (left …)", so the hop costs ~20–50 ms on a
warm master and the 8 s `waitUntilDrawn` timeout has ~7x headroom. That
was a loopback hop, so it carries no latency; a latent one is untested,
and is air's to run.

What is left is the shape, not the wait: **"drawn" is a shape, not a
certainty.** `waitUntilDrawn` returns on the first stable screen with more
than one painted row. That is enough to reject the attach client's
one-line wake message, which is what it was wrong about before; it is not
proof the TUI finished, and a render that pauses over 250 ms mid-paint can
still swap in early. Not seen in the wild.

### 14. The colour oracles have never been compared on a screen

What items 12a, 12b and 12c each left behind, stated once instead of
three times. Every colour ccc has shipped is asserted headlessly and
agrees with **8b's recorded number** (docs/EVIDENCE.md "8b: there is no
colour-management residual") rather than with a `screencapture` taken
beside it: `ccc capture` refused on all three slices for want of Screen
Recording permission, correctly, since that permission belongs to whoever
asks. One sitting from a terminal that has it settles all three — ccc's
pane and iTerm side by side on the same bold, selected, coloured text.

And the oracle has still only ever run on **one display, one profile, at
1x**. `ccc pixel --cell`'s scale arithmetic is tested at 2x, including
against a real offscreen render, but has never met a Retina panel.

### 15. What a second viewer does to the grid

Homeless until now: it was cited as part of item 3, which has left.
CLAUDE.md and `docs/DESIGN.md` §4c both point here.

Measured 2026-09-02: a second `claude attach` is **accepted**, output is
broadcast to every viewer, and input from any viewer goes in — which is
why the pane on any Mac is just `claude attach <id>` and no ccc depends on
another ccc. The shared PTY is **last-resize-wins across viewers**, and
what is still open is whether a secondary viewer should resize it at all
or render the grid as-is at whatever size the first viewer set.

**It comes due the first time air joins a session studio already has up**,
which is the ordinary case the moment the lid opens somewhere else — so
this is the one item below that will announce itself rather than wait to
be picked.

## Later

Peek/reply without attach (experiment 4). RC-free approvals via the
PermissionRequest hook. The phone, if the Mac app earns it.
