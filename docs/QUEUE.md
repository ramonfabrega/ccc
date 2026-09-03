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

**v8 is done.** Both complaints the user raised while using the app are
answered, and the second one is answered *with a number*. The theme (8):
the pane wears the user's own iTerm palette. The attach transition (9):
the incoming session runs behind the outgoing one, so the pane never goes
blank and the ← guard — off for the whole of that blank — stays armed.
The oracle (10): `ccc capture` and `ccc pixel` mean a colour can be
judged from the command line, and the first thing they judged closed 8b —
ccc's pane and iTerm land on **bit-identical** pixels in one composite,
so the colour-management residual the item assumed does not exist
(docs/EVIDENCE.md "8b: there is no colour-management residual").

**The frontier is now item 3**, and it is a question only the user can
answer: which Mac is ever the far side of an ssh hop. Everything remote —
§4c, item 6, the ssh-clipboard question, item 9's over-ssh half — is
behind it, and nothing else on this board is blocked at all.

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

### 8. The colours: two gaps left, both named

Raised by the user 2026-09-03 ("feel off / opaque'd"). **Answered.** The
pane set none of the core's four colour options, so it wore Ghostty's own
defaults against an iTerm that is `#15191F` on `#DCDCDC`; `Theme` now
installs 16 + 6 at `GhosttyHost.init` (docs/EVIDENCE.md "the pane wore
Ghostty's theme"). And 8b — the colour-management residual this item
assumed was left over — was measured with item 10's new verbs and **is
not there**: ccc and iTerm land on bit-identical pixels in one composite
(docs/EVIDENCE.md "8b: there is no colour-management residual").

Two gaps remain, both stated in `Theme`'s doc comment and neither
affecting whether the pane matches:

- **bold-is-bright.** iTerm has it on; it promotes bold text from colour
  *n* to *n+8*. It cannot be done from a `Frame` — the core resolves
  palette indices to RGB before a cell reaches us (`render.h`: "Bold
  color handling is not applied"), so the *index* has to cross the seam
  before anything here can add 8 to it.
- **selection.** The theme carries both colours and nothing draws them:
  `FrameReader` always builds rows with `selection: nil`.

Also untested: one display, one profile, at 1x. A Retina panel or a
different display profile could still move the answer, and `pixel
--cell`'s scale arithmetic has never run at 2x outside a test.

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

### 10. The oracle's twin: one question left

Shipped. `ccc geometry` hands out the `CGWindowID` that was always in the
app and never left it, `ccc capture` points `screencapture -l` at it, and
`ccc pixel --cell … --expect` makes the exit code the answer, so a script
can judge a colour. Their first real use closed 8b (docs/EVIDENCE.md "the
oracle gets its twin").

**Still unanswered: whether a replay golden could ever assert RGB.**
`GridBuilder` carries no colour, so `snapshot --json` and every headless
golden remain colour-blind — the new verbs need a *window*, which means
the one oracle an agent can run with no screen is still text-only. Fixing
it means carrying colour across the seam into `Grid`, which is the same
change bold-is-bright needs (item 8), so the two want doing together or
not at all.

### 11. A cold session cannot build this

Found the same way. Neither CLAUDE.md nor this file said how to build the
app, run its tests, or initialise the vendored submodule, nor whether `ccc`
on PATH is the installed release or a build of the current branch — so a
cold session could reason correctly about priorities and then measure the
wrong binary. README.md now carries this; keep it true.

## Later

Peek/reply without attach (experiment 4). RC-free approvals via the
PermissionRequest hook. The phone, if the Mac app earns it.
