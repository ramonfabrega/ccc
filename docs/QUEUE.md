# Queue

What is next, and nothing else. A finished item leaves; its commands and
numbers go to `docs/EVIDENCE.md`, and **its argument stays in the
transcript for lore to mine**. Nothing is owed outside this repo; a message
to lore is for the *perishable* and the *cross-project* only. Item numbers
are stable addresses: append, never renumber.

An item **inlines its conclusion**. A cold session reads this file and
CLAUDE.md, and must be able to start without opening a third thing; when
an item cites a past measurement it cites it by a string that appears
verbatim in `docs/EVIDENCE.md` (`experiment 2`, `waitUntilDrawn`,
`lidtest`) so the command behind it is one grep away.

## The frontier

**ccc is v1, and the swarm is why.** The first real commander swarm ran on
2026-09-06 — three commanders, seven workers, a machine that locked
mid-run — and **every gap it exposed was at the spawner/roster layer and
none in the terminal embed**. Seven landed that night and left without
entering here (`docs/EVIDENCE.md` "the swarm's five findings"): the name
guard and `ccc stop`, the free-space floor, `ccc update`'s tip, the stall
transition, the command manifest, `.worktreeinclude`, `claude rc`'s
paragraph. They left items 24 and 25 and one question; **24 has left
too**, and so has **27** — `ccc clear <ref> [--then …]`, the loop's
"clear and continue" step as a verb, armed by the commander on its own
ref and fired by the pane when the row goes idle (`docs/EVIDENCE.md`
"item 27"). It left one thing behind it: **after a clear the row's `↳`
detail is stale** until the next turn writes over it, which is a lie a
stall detector will read (item 25's instrument sees it too).

**v13 is the frontier, and it is item 17.** A survey on 2026-09-04 found
that **the phone's job is already shipped** — Remote Control puts most
live workers in the Claude app, where they are messaged and answered — so
ccc builds what RC leaves out, starting with the fact that **ccc cannot
see any of it** (`docs/EVIDENCE.md` "the mobile survey").

**v8 through v12 are done.** Three rules from them and from the swarm
stay: **a fix for a bug on the other Mac is unproved until a release
carries it there**; **a verb with fewer surfaces than its opposite will be
reported missing**; and **a string no test reads is a string nothing keeps
true** — which is how `ccc update`'s help went a release stale and cost a
worker its merge.

Three **questions, not items**. `suggestedReply` is on the row and shown
nowhere; using it means answering without attaching (see "Later"). The
banner receipt's only correct form is the **run-delta** — hold each job's
link count when it enters `working`, draw what appeared since — and its
own measurement says it draws an empty line 19 in 20. And **the CLI could
be a different language now**: since v0.1.24 it answers from the running
app over the socket, so it is already a thin client, and superterminal
ships its CLI as a separate crate over exactly that seam. A Bun `ccc` on
incur would get `--llms`, `--schema` and `--format toon` for free instead
of the hand-written `CommandManifest`. **The price is Bun on every ssh
host** — and the hop's design is that a remote roster comes from the far
side's own `ccc`, so it trades one binary to install for two. Argue it
before a second host is added.

Below the frontier: **item 6 is air's** and happens the next time the lid
closes overnight. Items 5 and 16 are leftovers and one missing twin, none
with a forcing function. **Items 4, 7 and 14 have left** — item 4 on
2026-09-04 (`docs/EVIDENCE.md` "item 4 — the far side answers from the
app"), and air's measurement of it is owed from the next lid night.

### 5. Small leftovers

A sort by model. The Session menu's archive/pin items (the context menu
has them). **`ccc window show` when another app holds
focus**: `NSApp.activate()` is cooperative since macOS 14 (measured
2026-09-02), so `show`'s CLI side should go through `NSWorkspace`.
**Twin gaps from the audit**
(`docs/EVIDENCE.md` "the audit"): `ccc ask <ref>` (the socket has it; the
CLI reaches it only through `update --ask`), a mouse-button `send`, `hosts
remove|check` in the window, an age column.

### 6. The remote pane's reattach has still never met a lid

The eviction half is **answered and gone** (docs/EVIDENCE.md "item 6 — the
lid"): a wake costs 14–22 s that no client-side fix can shorten, because
the tailnet is what is missing. `scripts/lidtest` is the instrument, and
the 20 s reattach window is 60 s now, pinned by `WakeWindowTests`.

**Still unmeasured, and the night decides it.** `ccc stats` grew a `wake`
line — `wakes`, reattach `attempts`, `gaveUp` — because three outcomes
look identical from outside (the pane is not back):

- `attempts == 0` after a night of `wakes`: **the guard never fired** —
  `ClaudeCLI.sshPrefix` sets no `ServerAliveInterval`, so an idle attach
  over a dead TCP connection may never return and the pane hangs on a
  frozen grid rather than dying. A different bug from this window.
  **Do not add the keepalive first**: the night says whether it is needed.
- `gaveUp > 0`: the window is still too narrow.
- `attempts > 0`, `gaveUp == 0`: it works.

Needs air's pane attached to a **studio** ref when the lid closes, studio's
pane elsewhere or on nothing (or it measures item 15 too), and **air on
v0.1.20 or later** from the feed; 0.1.18 measures the defect, not the fix.

### 15. What a second viewer does to the grid

CLAUDE.md and `docs/DESIGN.md` §4c both point here. Measured 2026-09-02: a
second `claude attach` is **accepted** and every viewer sees and drives it,
which is why no ccc depends on another ccc. The shared PTY is
**last-resize-wins**, and what is open is whether a secondary viewer should
resize it at all or render the grid at whatever size the first one set.

**It comes due the first time air joins a session studio already has up**
— the ordinary case the moment the lid opens somewhere else — so this is
the one item that will announce itself rather than wait to be picked.

### 16. The shell pane has no twins but open and close

`ccc shell <ref>` opens it and `--close` closes it, and that is the whole
surface: every verb that could read or drive it — `snapshot`, `select`,
`send`, `copy`, `pixel --cell` — addresses the *session* pane (measured
2026-09-04: with a shell pane up and nothing attached, `ccc send …`
answers `ccc: nothing attached`).

The twin rule biting one level up — a whole **pane** with two verbs — and
it matters beyond tidiness: the shell pane is the only place ccc can paint
**chosen bytes** into a real window. `focus` already reaches both panes; a
target on the request, not a second verb set, is the shape to copy.

### 17. ccc is blind to RC, and the phone is already in the pocket

None of this is the phone; all of it makes the phone the user already has
work better (`docs/EVIDENCE.md` "the mobile survey").

**Slices 1 and 2 are done** and their argument is in `docs/EVIDENCE.md`
("the mobile survey", "the pane that could not say it had looked away",
"Cut as v0.1.23"): the row says which sessions the phone can answer, and
the pane answers DEC 1004 so it can stop over-suppressing push. **The
user's half is unmeasured** — whether the phone now buzzes for a session
ccc holds and nobody is watching.

**Slice 3: `CLAUDE_CLIENT_PRESENCE_FILE`** (harness v2.1.181+) suppresses
push while a marker file exists; the harness docs want "a screen-lock
listener or similar tool" to write it on unlock and delete it on lock.
**ccc is that tool**: `ccc presence on|off|status`, plus `--settings`
printing the settings.json `env` entry and never writing it. **The obvious
signal is wrong**: studio is always-on, so "unlocked" would suppress push
all day; idle time is the signal — unlocked *and* recently touched. **Only
if slice 2 was not enough**: the bug just fixed was too much suppression.

**The box exists** (`ccc spawn --rc`); whether it should be the default is
still the user's call. **`claude rc` is not this box** and the difference
cost a day — docs/HARNESS.md carries the paragraph, including what an
rc-spawned session shows in the daemon's roster, which is **unmeasured**
and is the rest of this item's title.

**Item 18 left on 2026-09-04** (`docs/EVIDENCE.md` "item 18 — the base is
recorded"). Left open there: the sheet has no worktree or base field, and
a remote `--base` is refused rather than routed to the far side's ccc.

### 25. The stall window is a guess, and the next one is not

30 minutes is a constant (`StallWindow`), and nothing at that boundary
distinguishes a wedged session from one twenty minutes into a release
suite. The honest next version is **cadence-relative**: each session
against its own median gap between job-file writes, which is a number the
poll already sees every tick.

**Do not build it on the argument that a constant is crude.** Build it
when the constant has been noisy, and say so with a count — this fleet's
own rule (`docs/EVIDENCE.md` "the swarm's five findings"): count how often
the fixed window was useful before replacing it. The instrument is `ccc
watch --json`, whose `stalled` lines carry `stillFor`; a week of them is
the whole measurement. Until then the shape is what makes it safe — one
event per stall, re-armed only by movement.

## Later

**`claude rm` leaves a draft's worktree behind** — the one it cut itself,
for a session that never started (`docs/EVIDENCE.md` "item 24"). A harness
bug, and ccc has no record letting it clean that tree without risking one
the user pointed `--cwd` at. Argue it first.

Reply without attach — the session inbox socket, one probe away. RC-free
approvals via the `PermissionRequest` hook, the *only* write path the
phone in the pocket does not already have. The phone, if the Mac earns it.

**Answering the "your turn" from a phone is already shipped**, through
Remote Control (`docs/EVIDENCE.md` "the mobile survey"). RC has no
third-party entry point, so **a ccc phone must earn its place on something
other than unblocking.**

**Approvals before reply**, because **a peer message can never approve** —
"never counts as your consent" — so these are two features and were one
queue line. `PermissionRequest` is documented with a `decision` object and
`ccc hook` already receives Notification over the socket; the new part is a
hook that blocks and answers.

**Reply has a documented path** (address and caveats: `docs/HARNESS.md`
"The session inbox socket"). **What is left is one probe**: the line's
format is undocumented and in the CLI's bytecode, and a probe from a
session was refused by the auto-mode classifier — correctly, since writing
to an IPC socket reads as injection. Run it as `! python3 …`; `ccc reply
<ref> "<text>"` is a small twin after it.

**The phone breaks exactly one locked decision**: *"PTY is always local"*
— a subprocess, and iOS has no fork/exec. An in-process ssh client
(**`apple/swift-nio-ssh`**) over **libghostty's External termio backend**
(our seam's shape; builds for iOS upstream) keeps the daemon decision, and
**`No tmux, ever` is the edge**: every Ghostty-on-iOS client reaches for
tmux to survive suspension; ccc needs none. Trap: `ccc pixel --cell`'s
scale arithmetic has never met a Retina panel (studio is 1x).

**"The core is shared" is not true yet.** `CCCKit` is one module pinned
to `.macOS(.v14)` with `PTY/`, SwiftTerm and Sparkle beside `Roster/` and
`Render/`. Splitting the parts above the seam out is Mac-side work, testable
today, and what makes a port a port instead of a rewrite.
