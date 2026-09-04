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

**v12 slice 2 is done, and air is the one that said so:** Add Mac on air
works, on v0.1.22. Before it, Add Mac there showed a
raw `DecodingError` naming the character `T` and nothing about why, because
stderr went to `nullDevice` and `peers(from:)` is handed bytes with no
memory of which binary produced them. The cause, once
the error could carry it: Tailscale's macOS bundle is the GUI and the CLI in
one binary and picks by smelling for a shell — with neither `TERM` nor
`SHLVL` set it decides it was double-clicked and prints "The Tailscale GUI
failed to start: …" on stdout, exit 0. A GUI process has neither, so ccc.app
could not be told apart from a double-click and `ccc hosts discover` in a
terminal could never reproduce it: **the twins disagreed because the
environments did**, which is the one way two surfaces of one definition can
still diverge. `Tailnet.shellish` supplies both variables; the better error
message stays, because it is what will name the next binary that answers
something else (`docs/EVIDENCE.md` "the picker's error names a character, not
a cause").

Both halves were asserted on studio, which was never the Mac that broke, so
the cut was not the delivery of the fix but **the only way to measure it** —
air can only pull. That is the shape to keep: a fix for a bug that lives on
the other Mac is unproved until a release carries it there, however green
the suite is here (`docs/EVIDENCE.md` "Cut as v0.1.22", "air answers").

**So there is no frontier again.** Before slice 2, **v12 slice 1** was the
shell pane's way out, and it came from the user asking whether there was
one. There were three, all unfindable:
the row menu only ever said "Open in Terminal", so the mouse had no close
at all, and ⇧⌘T was named in the two refusals and nowhere else. The row's
item now flips to **Close Terminal** while its shell is up (`t` with it),
and the open sentence names the shortcut (`docs/EVIDENCE.md` "v12 slice 1"). The
count in that entry is the general shape to watch: **a verb with fewer
surfaces than its opposite is a verb that will be reported missing.**

Before it, **there wasn't a frontier.** v11 is done in four slices, cut as **v0.1.18**:
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
its own the next time the lid closes overnight. Items 4, 5 and 16 are debt,
leftovers and one missing twin, none with a forcing function. **Items 7 and
14 have left** — origin carries `master` and `worktree-v2` and nothing else, and the colour oracle was closed
unmeasured on the argument that 8b had already answered it
(`docs/EVIDENCE.md` "the four branches, and the sha is the undo", "item 14
closes unmeasured").

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
tailnet is what is missing. `scripts/lidtest` is the instrument.

**Fixed before the next night, from those numbers:** the reattach window
was 20 s, and the retries land at ~+5, +10, +15 s (each costs
`ConnectTimeout=5`, and `reconnect` awaits its own failing poll first), so
it gave up at +20 — one or two seconds *before* the network returned, on
the three wakes in eighteen that took 21–22 s. Not merely tight, aligned
to fail. Now 60 s, ~3x the measured worst case, guarded by
`WakeWindowTests` which restates the night's numbers as arithmetic and
fails at 20.

**Still unmeasured, and the night decides it.** `ccc stats` grew a `wake`
line — `wakes`, reattach `attempts`, `gaveUp` — because three outcomes
look identical from outside (the pane is not back):

- `attempts == 0` after a night of `wakes`: **the guard never fired**, so
  ssh never noticed the pane died. `ClaudeCLI.sshPrefix` sets no
  `ServerAliveInterval`, and an idle `ssh -t … claude attach` over a dead
  TCP connection may never return — the pane would hang on a frozen grid
  rather than die. That is a different bug from this window, and the
  counter is what tells them apart. **Do not add the keepalive first**:
  the night is what says whether it is needed.
- `gaveUp > 0`: the window is still too narrow.
- `attempts > 0`, `gaveUp == 0`: it works.

Needs air's pane attached to a **studio** ref when the lid closes, studio's
pane on something else or nothing (or it measures item 15 too), and **air
on v0.1.20 or later** — cut and published 2026-09-04, so air takes it from
the feed. 0.1.18 measures the defect, not the fix.

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

### 16. The shell pane has no twins but open and close

Found while looking for a colour fixture: `ccc shell <ref>` opens the pane
and `ccc shell --close` closes it, and that is the whole surface.
Every verb that could read or drive it — `snapshot`, `select`, `send`,
`copy`, `pixel --cell` — addresses the *session* pane. Measured
2026-09-04 with a shell pane up and no session attached: `ccc send …`
answers `ccc: nothing attached` and `ccc snapshot` answers `(nothing
attached)`.

This is the twin rule biting one level up — not a read field without its
write verb, but a whole **pane** with two verbs and no others — and it
matters beyond tidiness, because the shell pane is the
only place ccc can paint **chosen bytes** into a real window — every other
pane shows whatever `claude attach` is drawing. Anything that wants to put
a known sequence on screen and read it back has nowhere else to put it,
which is what made the shell pane look like a fixture in the first place.

## Later

Peek/reply without attach (experiment 4). RC-free approvals via the
PermissionRequest hook. The phone, if the Mac app earns it.

**Argued 2026-09-04, once, so it is not re-derived.** These three are one
thing in the order given, and the order is not preference.

The phone's whole marginal value is **unblocking**. Notifications already
reach every device — the poll is the first notifier — so a phone that only
looks is a banner that already arrives. What it adds is answering the
"your turn", which *is* the two write paths above. They are not the
phone's prerequisites; they are its content, and they are testable on the
Mac through the twins, where a phone client is not.

**Approvals before peek/reply**, on what is known rather than what is
wanted. `PermissionRequest` is a documented surface with a `decision`
object (`docs/HARNESS.md`), and `ccc hook` already receives Notification
over the control socket — the new part is a hook that blocks and answers.
Peek/reply rests on **experiment 4, which has never been run**: whether
the daemon exposes the TUI's reply field outside the TUI is written down
as *unknown*. Run the experiment before building anything on it; it either
opens the path or closes it, and it is a measurement, not a slice.

**The phone breaks exactly one locked decision, and it is not "no daemon
of our own".** It is *"PTY is always local; remote is the same command
behind `ssh -t`"* — a **subprocess**, and iOS has no fork/exec, so the one
mechanism the whole remote story rests on is the one that cannot cross.
Give the phone an in-process ssh client (a library, earned per part) and
`ssh studio claude attach <id>` is the Mac's own path; the daemon decision
survives untouched. So the expensive part is a **dependency** question,
not an architecture one — cheaper than "the phone needs a server" makes it
sound, and worth knowing before that gets re-argued.

**One thing item 14 left here on its way out.** `ccc pixel --cell`'s scale
arithmetic is tested at 2x but has never met a Retina panel, because the
oracle runs on studio and studio is 1x. On a phone everything is 2x or 3x,
so that untested arithmetic stops being a curiosity the moment a port is
real — and not one second before, which is why it lives in this paragraph
and not in an item.

**What is not true yet is "the core is shared."** In principle it is:
roster, hosts, harness, transcript, theme, `Frame`, `RunMerge`,
`GridBuilder` are all portable Swift, and the terminal seam (feed, write,
resize, snapshot) is already the right line. In fact `CCCKit` is **one
module pinned to `.macOS(.v14)`** with `PTY/` (forkpty), SwiftTerm and
Sparkle sitting inside it next to `Roster/` and `Render/`. Splitting the
parts above the seam out of that is Mac-side work, testable on the Mac
today, and it is what makes the port a port instead of a rewrite — so it
belongs *while* the Mac is being landed, not after.
