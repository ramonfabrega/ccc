# Queue

What is next, and nothing else. A finished item leaves — its commands and
numbers go to `docs/EVIDENCE.md`, its argument to the lore wiki. Item
numbers are stable addresses: append, never renumber.

An item **inlines its conclusion**. A cold session reads this file and
CLAUDE.md, and must be able to start without opening a third thing; when
an item cites a past measurement it cites it by a string that appears
verbatim in `docs/EVIDENCE.md` (`experiment 2`, `waitUntilDrawn`,
`lidtest`) so the command behind it is one grep away.

## The frontier

**v8 is done** — the theme (8), the attach transition (9) and the colour
oracle (10) all shipped 2026-09-03, and the last of them measured the
first: ccc's pane and iTerm land on bit-identical pixels, so the
colour-management residual v8 assumed does not exist (docs/EVIDENCE.md
"8b: there is no colour-management residual"). Those three items have
left; what survived them is item 12.

**The hop is live.** Remote Login went on for studio 2026-09-03 and
item 3's first two steps shipped the same day: a real `Host` behind a
real `sshd`, a fixture spawned, attached, resized and driven over it, and
DESIGN.md §4c answered by measurement (docs/EVIDENCE.md "v9 slice 1 — the
hop is real"). Doing it found the host list frozen at launch, now fixed.
**The frontier is item 3's last step — the picker — and item 12**, which
is the one thing left of v8 and needs no hop at all.

## Open

### 3. The hop: the picker is what is left

**Shipped 2026-09-03** (docs/EVIDENCE.md "v9 slice 1 — the hop is real"):
`ccc hosts add studio --ssh studio`, `ccc hosts check studio` at 684 ms
against local's 223 ms, and a haiku fixture spawned, attached, resized and
typed into entirely over ssh. Steady state 543 ms mean over ~75 polls, 0
failures, 0 evictions, the model column intact remotely, and the notifier
firing for the remote host. `Host.claude`'s absolute path is load-bearing:
experiment 3's "no claude on PATH" still holds on this Mac.

**The bench was studio→studio**, which carries the real client code and
the real sshd but no latency, so every number is a floor. The air→studio
direction still needs air, and air alone.

**What is left: the picker off `tailscale status --json`.** MagicDNS names
are the ssh destinations (Bonjour never crosses the tailnet); `tailscale
status` already lists `studio 100.81.87.24` and `air 100.122.216.104`
alongside non-Mac peers, so the picker's real work is filtering to hosts
that can answer `claude` and not offering air as a target (CLAUDE.md: one
hop, one way). The host list it writes to is now hot-reloaded, so the
picker's add lands in the running app the way `ccc hosts add` does.

### 4. Debt: the blocking poll read

`ClaudeCLI.run` blocks a pool thread per host for up to its timeout
(`readDataToEndOfFile`). Fine at two or three hosts; wants a nonblocking
read before the host list grows. No forcing function yet.

### 5. Small leftovers

A sort by model. The Session menu's archive/pin items (the context menu
has them). **`ccc stats`' first line says `uptime` next to `pid` and
`memory`, which are the app's, but the number is the attached *pane's* —
`PaneController.handle(.stats)` passes `uptimeSeconds: 0` whenever nothing
is attached, so a week-old app reads "uptime 0s" the moment you detach
(noticed 2026-09-03). Either label it, or make it the app's.** `ccc window
show` when another app holds focus — measured
2026-09-02 with a Wine window in front: `NSApp.activate()` is cooperative
since macOS 14 and the window stayed behind while `open -a` brought it
front, so `show`'s CLI side should activate through `NSWorkspace`.

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
warm master and the 8 s `waitUntilDrawn` timeout has ~7x headroom. On a
loopback hop — a latent one is still untested, and that is air's to run.

What is left is the shape, not the wait: **"drawn" is a shape, not a
certainty.** `waitUntilDrawn` returns on the first stable screen with more
than one painted row. That is enough to reject the attach client's
one-line wake message, which is what it was wrong about before; it is not
proof the TUI finished, and a render that pauses over 250 ms mid-paint can
still swap in early. Not seen in the wild.

### 12. Colour has to cross the seam

The one thing left of v8, and it is a single change wearing three hats.
The core resolves palette indices to RGB before a cell reaches us
(`render.h`: "Bold color handling is not applied"), and `GridBuilder`
carries no colour at all, so:

- **bold-is-bright** cannot be done. iTerm has it on; it promotes bold
  text from colour *n* to *n+8*, and there is no *n* left on our side of
  the seam to add 8 to.
- **selection** is carried by `Theme` and drawn by nobody: `FrameReader`
  always builds rows with `selection: nil`.
- **a replay golden cannot assert RGB.** `ccc capture`/`ccc pixel` judge
  a colour but need a *window*, so the one oracle an agent can run with
  no screen is still text-only.

All three want the palette index carried through `Frame` into `Grid`.
Doing any one alone pays the seam cost without collecting the other two.

Also uncovered, and cheap to state: the colour oracle has only ever run
on one display, one profile, at 1x. `pixel --cell`'s scale arithmetic is
tested at 2x but has never met a Retina panel.

## Later

Peek/reply without attach (experiment 4). RC-free approvals via the
PermissionRequest hook. The phone, if the Mac app earns it.
