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

**There isn't one again.** v11 is done in four slices, cut as **v0.1.18**:
the window comes back where you left it and every window gesture has a
verb (slices 1 and 2), and the banner is now a title and a sentence —
slices 3 and 4 measured the receipt line out of existence rather than
arguing it away (`docs/EVIDENCE.md` "v11 slice 1" … "v11 slice 4").

Two **questions, not items**, are what those left behind. `suggestedReply`
is on the row and shown nowhere, and using it means answering a session
without attaching — which is under "Later" and has never been argued. And
the receipt's only correct form is the **run-delta**: hold each job's link
count when it enters `working`, draw what appeared since. ~20 lines,
correct every time, and its own measurement says it draws an empty line on
nineteen banners in twenty — a reason to wait for the itch, since the
artifact is in the pane and `ccc links` opens it.

Before it: v8, v9 and v10 are done — the theme, the attach transition, the
colour oracle, the hop, colour (item 12), the hand (item 13), the picker
(item 3), and the daemon's own sentence reaching both the banner and the
roster row. `docs/EVIDENCE.md` "v8 slice 1" … "v10 slice 2" carries the
numbers.

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
read before the host list grows. No forcing function yet — but the lid
night gave it a number: air's studio poll ran **`last 2046 ms  mean
1354 ms`** against a 2 s tick, because the far side's ccc does the
transcript join before answering. The remote poll costs about one whole
tick, so air's roster is always ~2 s stale, the poller never idles, and it
sits ~1 s under `degradedThreshold` (3 s) — close enough that a slower
studio would start self-evicting on a healthy hop.

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

### 6. The remote pane's reattach has still never met a lid

The eviction half is **answered and gone** (docs/EVIDENCE.md "item 6 — the
lid"): a closed lid is 18 dark wakes a night, not one sleep; the master
comes back wedged on 17 of 18; eviction is the main path, not insurance;
and a wake costs 14–22 s that no client-side fix can shorten, because the
tailnet is what is missing. `scripts/lidtest` is the instrument, and
`~/lidtest-studio.log`'s sampler is the server half.

What that night did **not** exercise: `sshExit` within 20 s of wake
replaying the same argv (`PaneController.reattachIfSleepKilledIt`), and
`reconnect`'s case where ssh noticed first (`lastExitStatus == sshExit`).
Nothing was attached, so neither has run.

It needs air's pane attached to a **studio** ref when the lid closes, and
studio's pane on something else or nothing, or it measures item 15 at the
same time. The night now says what to expect: **18 chances per night**, not
one, and each wake gives the reattach a 14–22 s window of failing ssh to
survive — which is longer than the 20 s guard is wide. **That is the thing
to watch**: if the first reattach fires into a dead tailnet and gives up,
the pane stays dead until the user clicks, and the guard wants to be a
retry rather than a single shot.

### 7. Housekeeping: four branches to delete

Re-checked 2026-09-04 against `branch -a --merged origin/master`, which
this item asks for: `hotfix-gridbuilder`, `worktree-v0`, `worktree-v1`
and `worktree-icon` are all merged into master and safe to delete on
origin. **`worktree-icon` joined the list on that re-check** — the entry
carved it out on 2026-09-03 as unmerged, and it had in fact landed at
37cdae5, the merge tagged v0.1.6. `worktree-v2` is the live branch and
stays.

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
