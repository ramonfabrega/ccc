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

**v8 — the pane, honestly.** Two complaints the user raised while using
the app, both now shipped. The theme (item 8): the pane wears the user's
own iTerm palette, which turns "does it match" into a diff rather than a
matter of taste. The attach transition (item 9): the incoming session
runs behind the outgoing one and the swap happens once it has drawn, so
the pane never goes blank — and the ← guard, which was off for the whole
of that blank, stays armed. What is left of 8 is the residual, colour
management, which cannot be judged by eye: **item 10 is the frontier**,
because nothing here can capture one window or read a colour out of a
PNG, and 8b cannot be measured until it can.

## Open

### 3. Host picker, and the shared-size question

Off `tailscale status --json` (MagicDNS names are the ssh destinations;
Bonjour never crosses the tailnet). With it, the question deferred in
DESIGN.md §4c: the daemon's PTY is last-resize-wins across viewers, so
decide whether a secondary viewer renders the shared grid as-is instead of
resizing it.

**Not blocked on a toggle — blocked on there being a destination.**
This file said four threads waited on turning Remote Login on for air.
That was wrong, and the user said so 2026-09-03: **air is never an ssh
destination.** It is the Mac you drive *from*, and the reason the whole
release flow is a pull (RELEASES.md's own first paragraph says air cannot
be pushed to). Measured the same day: neither Mac listens on 22, and the
host list holds `local` alone, so every ssh proof to date is `localhost`
wearing a costume — that part stands.

What is actually open is which Mac is ever the far side. The shape the
fleet has is air (roaming client) → studio (always-on, where the agents
run), which would make studio the one thing to enable and air the one
thing to run the proof from — but that is inference, not a decision, and
nothing here should assume it. **Until a real destination exists, this
item is a picker over a host list that can only ever hold one row**, and
§4c, item 6 and the ssh-clipboard question have no way to be answered at
all.

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

### 6. Open measurements that need a real hop

The long sleep: `~/lidtest.py` is running on air appending to
`~/lidtest.log`, and its log is what decides whether the ssh master
eviction ever fires (`ccc stats` → `evictions`) — the file comes off air
by air's own hand, not by an `scp` from here (item 3: nothing ssh's into
air). And the first real sleep for the remote-pane reattach — `sshExit`
within 20 s of wake replays the same argv
(`PaneController.reattachIfSleepKilledIt`), never yet through a real lid.
Both wait on item 3 having a destination.

### 7. Housekeeping

Remote branches `hotfix-gridbuilder`, `worktree-icon`, `worktree-v0`,
`worktree-v1` are merged history; delete when convenient. Verify against
`git branch -a` first — this item has not been re-checked since it was
written.

### 8. The colours: the theme is set, the residual is not

Raised by the user 2026-09-03 ("feel off / opaque'd"). **Half shipped.**
The pane set none of the core's four colour options, so it wore Ghostty's
own defaults — `#000000` on `#FFFFFF` with the Tomorrow Night palette —
against an iTerm that is `#15191F` on `#DCDCDC` with a much more
saturated sixteen. Not a missing palette, a different one; the queue's
old "black on black" reading was the sized-struct bug `FrameReader`
already fixed. `Theme` now installs 16 + 6 at `GhosttyHost.init`, with
`ccc theme` and `CCC_THEME` as the surfaces — docs/EVIDENCE.md "the pane
wore Ghostty's theme".

What is left is cause (b), still unmeasured: `MetalPaneView` sets no
`colorspace` on its `.bgra8Unorm` layer, so the pane is unmanaged while
iTerm is colour-managed. The old premise for it was wrong — studio's
display answers `NSScreen.colorSpace` with its own EDID profile ("Mi
monitor", scale 1.0, no EDR), neither sRGB nor P3 — and the conclusion
survived being wrong, because an unmanaged layer against a non-sRGB
panel moves every value just the same. **Now that the nominal values
agree, the on-screen difference is the colour management**: same content
in both, a real `screencapture` of each, compare the RGB of known cells.
Needs item 10.

Two smaller gaps, both stated in `Theme`'s doc comment: bold-is-bright
(iTerm has it on; the core resolves palette indices to RGB before a cell
reaches us, so the index has to cross the seam before we can add 8 to
it), and the selection colours, which the theme carries and nothing
draws.

### 9. The attach transition: two ends left

Shipped — the incoming session runs behind the outgoing one and the swap
is one `install` once it has drawn, which also closed the ← hole the
blank pane was holding open (docs/EVIDENCE.md "the attach transition, and
the hole in the ← guard"). What is left:

- **It is proved locally only.** Over ssh it is the same code with a much
  longer wait — the case the 8 s `waitUntilDrawn` timeout was written
  for, and the case nothing has ever run. Waits on item 3 the same way
  everything remote does.
- **"Drawn" is a shape, not a certainty.** `waitUntilDrawn` returns on
  the first stable screen with more than one row on it. That is enough to
  reject the attach client's one-line wake message, which is what it was
  wrong about before; it is not proof the TUI finished. A session whose
  render pauses over 250 ms mid-paint can still swap in early. No
  forcing function — it has not been seen.

### 10. The oracle has no command twin — the frontier

Found by a cold read of these docs, 2026-09-03; item 8b waits on it. CLAUDE.md makes a real
`screencapture` the oracle for presentation, and `docs/CHECKS.md` row 5
was re-judged with one — but nothing in the repo can capture one specific
window: `screencapture -l <CGWindowID>` needs an id nothing here produces,
and there is no script for it. Against this project's own rule that every
gesture has a command twin, that is a finding, not a missing doc.

Nothing reads RGB out of a PNG either. There is now a headless colour
oracle of a kind — `ThemeTests` asserts a `Frame`'s resolved cell colours,
which is how item 8's first half was proved — but no *command* twin:
`snapshot --json` serialises a `Grid` and `GridBuilder` carries no colour,
so nothing on the CLI can judge a colour. Whether a replay golden could
ever assert RGB is unanswered.

### 11. A cold session cannot build this

Found the same way. Neither CLAUDE.md nor this file said how to build the
app, run its tests, or initialise the vendored submodule, nor whether `ccc`
on PATH is the installed release or a build of the current branch — so a
cold session could reason correctly about priorities and then measure the
wrong binary. README.md now carries this; keep it true.

## Later

Peek/reply without attach (experiment 4). RC-free approvals via the
PermissionRequest hook. The phone, if the Mac app earns it.
