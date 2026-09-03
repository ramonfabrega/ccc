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

**The frontier is item 3, and it is now one toggle.** Decided by the user
2026-09-03: **studio is always the host, air always joins.** That makes
`ssh studio` the only hop ccc needs, Remote Login on *studio* the only
thing standing in front of it, and items 6, 9 and DESIGN.md §4c
answerable the moment it is on.

## Open

### 3. The hop: one toggle on studio

**Decided 2026-09-03: studio is always the host, air always joins.** Not
symmetric and not meant to be — studio is the always-on Mac where the
agents run, air is the roaming client, and nothing ever ssh's into air
(which is also why the release flow is a pull; RELEASES.md's first
paragraph). Generalising to any-Mac-to-any-Mac is a someday, not a goal.

**Blocked on Sharing ▸ Remote Login on studio.** Measured 2026-09-03:
nothing listens on 22 on either Mac and `ccc hosts` holds `local` alone,
so every ssh proof to date is `localhost` wearing a costume. With it on,
in order: `ccc hosts add studio --ssh studio` from air, prove one real
`ccc attach studio:<id>`, then the picker off `tailscale status --json`
(MagicDNS names are the ssh destinations; Bonjour never crosses the
tailnet) — a picker is a convenience over a host list that has never held
a real remote.

With the hop live, the question deferred in DESIGN.md §4c comes due: the
daemon's PTY is last-resize-wins across viewers, so decide whether a
secondary viewer renders the shared grid as-is instead of resizing it.
Air joining a session studio already has on screen is exactly that case.

### 4. Debt: the blocking poll read

`ClaudeCLI.run` blocks a pool thread per host for up to its timeout
(`readDataToEndOfFile`). Fine at two or three hosts; wants a nonblocking
read before the host list grows. No forcing function yet.

### 5. Small leftovers

A sort by model. The Session menu's archive/pin items (the context menu
has them). `ccc window show` when another app holds focus — measured
2026-09-02 with a Wine window in front: `NSApp.activate()` is cooperative
since macOS 14 and the window stayed behind while `open -a` brought it
front, so `show`'s CLI side should activate through `NSWorkspace`.

### 6. Two measurements that need the hop

Both wait on item 3, and both are lid-driven, so neither can be forced.

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

### 9. The attach transition: two ends left

Shipped (docs/EVIDENCE.md "the attach transition, and the hole in the ←
guard"). What is left:

- **Proved locally only.** Over ssh it is the same code with a much
  longer wait — the case the 8 s `waitUntilDrawn` timeout was written for
  and the case nothing has ever run. Waits on item 3.
- **"Drawn" is a shape, not a certainty.** `waitUntilDrawn` returns on
  the first stable screen with more than one painted row. That is enough
  to reject the attach client's one-line wake message, which is what it
  was wrong about before; it is not proof the TUI finished, and a render
  that pauses over 250 ms mid-paint can still swap in early. Not seen in
  the wild.

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
