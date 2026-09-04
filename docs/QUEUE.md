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

**v13 is the frontier, and it is item 17.** A survey on 2026-09-04 went
looking for the phone and found that **the phone's job is already shipped**:
Remote Control puts five of nine live workers in the Claude app, where they
can already be messaged and their permission prompts answered. So ccc is
not building unblocking — it is building what RC leaves out, starting with
the fact that **ccc cannot see any of it** (`docs/EVIDENCE.md` "the mobile
survey"; the amended argument is under "Later").

Slice 1 is landed: the roster row now says which sessions are answerable
from the phone, read off `respawnFlags` in the job file `JobProbe` already
opens — the CLI roster carries no flag signal at all, and `bridgeSessionId`
is on every job and discriminates nothing. Slices 2 and 3 are the presence
file and the measurement under item 17.

**v8 through v12 are done and their numbers are in `docs/EVIDENCE.md`** —
grep "v8 slice 1" … "v12 slice 2". Two shapes from them are rules rather
than stories, so they stay: **a fix for a bug that lives on the other Mac
is unproved until a release carries it there** (air can only pull), and
**a verb with fewer surfaces than its opposite is a verb that will be
reported missing**.

Two **questions, not items**, left over. `suggestedReply` is on the row and
shown nowhere, and using it means answering a session without attaching —
which now has a documented path (see "Later"). And the banner receipt's only
correct form is the **run-delta**: hold each job's link count when it enters
`working`, draw what appeared since. ~20 lines, correct every time, and its
own measurement says it draws an empty line nineteen banners in twenty.

Below the frontier: **item 6 is air's** and happens the next time the lid
closes overnight. Items 5 and 16 are leftovers and one missing twin, none
with a forcing function. **Items 4, 7 and 14 have left** — item 4 on
2026-09-04 (`docs/EVIDENCE.md` "item 4 — the far side answers from the
app"): the far side's `ccc list` now answers from its running app's
roster, and air's measurement of it is owed from the next lid night.

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

### 17. ccc is blind to RC, and the phone is already in the pocket

Numbers in `docs/EVIDENCE.md` "the mobile survey". None of this is the
phone; all of it makes the phone the user already has work better, and all
of it is testable on the Mac through the twins.

**Slice 1 is done.** The row says which sessions are answerable from the
phone: `rc` in `ccc list`, an `iphone` badge in the window, read off
`respawnFlags` in the job file `JobProbe` already opens. The two nearer
candidates are wrong and were measured before building — `claude agents
--json --all` carries nine keys and **no flag signal at all**, and
`bridgeSessionId` is on **every** job (it is the claude.ai session id, not
a mark of RC). Drawn only when true, per the v11 rule.

**Slice 2 is done, and it was a bug of ours.** The harness turns **DEC 1004
focus reporting** on for every session (8 of 8 workers' `decModes`), and
ccc answered it with nothing — while the harness's presence guard skips its
"the user is here" pulse **only on an explicit blur**. An unanswered
question reads as "yes", so an attached ccc pane could only ever
*over*-suppress the user's phone, structurally. `TerminalHost.setFocused`
is the seam's sixth member, `ccc focus [in|out]` the twin, proved against a
live `claude attach` (`docs/EVIDENCE.md` "the pane that could not say it
had looked away"). **Cut as v0.1.23 the same day** — the damage was ongoing,
so it did not wait for a batch — and air pulls it from the feed
(`docs/EVIDENCE.md` "Cut as v0.1.23"). **The user's half is unmeasured**:
whether the phone now buzzes for a session ccc holds and nobody is watching.

**Slice 3: `CLAUDE_CLIENT_PRESENCE_FILE`** (harness v2.1.181+) suppresses
push while a marker file exists, and the harness docs say to "configure a
screen-lock listener or similar tool" to write it on unlock and delete it
on lock. **ccc is that tool.** Twin: `ccc presence on|off|status` plus
`ccc presence --settings`, printing the settings.json `env` entry and never
writing it (`HookSettings`' rule). **The obvious signal is wrong**: studio
is always-on, so "screen unlocked" would suppress push all day while nobody
is there. Idle time is the signal — unlocked *and* recently touched.
**Do slice 3 only if slice 2 was not enough**: it adds a second suppressor,
and the bug just fixed was too much suppression.

**Not a slice, a box.** ccc's spawn never offers `--rc`. Whether it should
default to it is the user's call, but the box should exist.

## Later

Reply without attach — **not** experiment 4; the session inbox socket, one
probe away. RC-free approvals via the `PermissionRequest` hook, now the
*only* write path the phone in the user's pocket does not already have.
The phone, if the Mac app earns it.

**Argued 2026-09-04 and amended the same day, by measurement**
(`docs/EVIDENCE.md` "the mobile survey"). The argument was that the phone's
whole value is unblocking, and that unblocking *is* the two write paths
above, so build them first. Half of that is false and the false half is the
useful one: **answering the "your turn" from a phone is already shipped**,
by Anthropic, through Remote Control, to these very sessions. Five of nine
live workers carry `--rc`; the Claude app already messages them, answers
their permission prompts and `AskUserQuestion`s, and sets `/model` and
`/config`; push for both is enabled here. RC is an outbound relay to the
Anthropic API with no third-party entry point — ccc cannot join it and does
not need to. **A ccc phone must earn its place on something other than
unblocking**, and reading `--rc` is what ccc owes first (item 17).

**Approvals before reply**, and the order survives for a new reason.
`PermissionRequest` is documented, with a `decision` object
(`docs/HARNESS.md`), and `ccc hook` already receives Notification over the
control socket; the new part is a hook that blocks and answers. Reply is
the *other* feature now, because **a peer message can never approve** — the
docs are explicit that it "never counts as your consent, so it can't answer
a pending permission prompt". One queue line was two features.

**Reply has a documented path, so experiment 4 is optional.** Every session
binds an inbox socket and the docs sanction the use — *"when you want a
script or hook to post into a session"*. The address is a join ccc already
makes: **`replPid`** → `/tmp/cc-socks/<replPid>.sock`, nine for nine
(`pid` is the launcher and matches nothing). A session's own is
`CLAUDE_CODE_MESSAGING_SOCKET` with `CLAUDE_CODE_MESSAGING_TOKEN`; the auth
line is optional on macOS. ccc asserts no permission class, so a
`bypassPermissions` receiver holds its message and a prompting one
(`--permission-mode auto` included) takes it. **What is left is one probe,
one permission rule wide**: the message line's format is undocumented and
in the CLI's bytecode, and a probe against ccc's own socket was refused by
the auto-mode classifier — writing to a session's IPC socket reads as
injection, which is the correct read. Run it as `! python3 …` and
`ccc reply <ref> "<text>"` is a small twin after it.

**The phone breaks exactly one locked decision, and it is not "no daemon of
our own".** It is *"PTY is always local; remote is the same command behind
`ssh -t`"* — a **subprocess**, and iOS has no fork/exec. Give the phone an
in-process ssh client and `ssh studio claude attach <id>` is the Mac's own
path; the daemon decision survives untouched. The survey named the parts,
so none of this is research any more: **`apple/swift-nio-ssh`** is the
library (pure Swift, what `daiimus/geistty` ships), **libghostty's External
termio backend** takes terminal bytes from an external source instead of a
local process — the same shape as our seam, and it builds for iOS in
upstream CI — and **`No tmux, ever` is the edge, not the tax**: every
shipping Ghostty-on-iOS client reaches for tmux control mode to survive app
suspension, and ccc needs none, because the daemon is the multiplexer.
That is the only argument for building one that survived the survey. Item
14 left one trap here too: `ccc pixel --cell`'s scale arithmetic is tested
at 2x and has never met a Retina panel, because studio is 1x. On a phone
everything is 2x or 3x.

**"The core is shared" is not true yet.** In principle it is: roster,
hosts, harness, transcript, theme, `Frame`, `RunMerge`, `GridBuilder` are
portable Swift and the terminal seam is the right line. In fact `CCCKit` is
**one module pinned to `.macOS(.v14)`** with `PTY/`, SwiftTerm and Sparkle
inside it next to `Roster/` and `Render/`. Splitting the parts above the
seam out is Mac-side work, testable today, and is what makes a port a port
instead of a rewrite — so it belongs *while* the Mac is being landed.
