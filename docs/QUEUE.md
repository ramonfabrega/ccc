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

**v13 is the frontier, and it is item 17.** A survey on 2026-09-04 went
looking for the phone and found that **the phone's job is already shipped**:
Remote Control puts five of nine live workers in the Claude app, where they
can already be messaged and their permission prompts answered. So ccc is
not building unblocking — it is building what RC leaves out, starting with
the fact that **ccc cannot see any of it** (`docs/EVIDENCE.md` "the mobile
survey"; the amended argument is under "Later").

**v8 through v12 are done and their numbers are in `docs/EVIDENCE.md`** —
grep "v8 slice 1" … "v12 slice 2". Two shapes from them are rules rather
than stories, so they stay: **a fix for a bug that lives on the other Mac
is unproved until a release carries it there** (air can only pull), and
**a verb with fewer surfaces than its opposite is a verb that will be
reported missing**.

Two **questions, not items**, left over. `suggestedReply` is on the row and
shown nowhere; using it means answering without attaching (see "Later").
And the banner receipt's only correct form is the **run-delta**: hold each
job's link count when it enters `working`, draw what appeared since — ~20
lines, and its own measurement says it draws an empty line 19 in 20.

Below the frontier: **item 6 is air's** and happens the next time the lid
closes overnight. Items 5 and 16 are leftovers and one missing twin, none
with a forcing function. **Items 4, 7 and 14 have left** — item 4 on
2026-09-04 (`docs/EVIDENCE.md` "item 4 — the far side answers from the
app"): the far side's `ccc list` now answers from its running app's
roster, and air's measurement of it is owed from the next lid night.

### 5. Small leftovers

A sort by model. The Session menu's archive/pin items (the context menu
has them). **Selection autoscroll** waits on a scrollback viewport that
does not exist: `GhosttyPane.scroll` forwards every wheel event to the
child, so the 2,000 lines the core keeps are unreachable and a drag that
leaves the grid has nothing to tick — low value while the pane only ever
runs `claude attach`, which scrolls its own history (re-checked
2026-09-03). **`ccc window show` when another app holds focus** — measured
2026-09-02: `NSApp.activate()` is cooperative since macOS 14 and the
window stayed behind while `open -a` brought it front, so `show`'s CLI
side should activate through `NSWorkspace`.

### 6. The remote pane's reattach has still never met a lid

The eviction half is **answered and gone** (docs/EVIDENCE.md "item 6 — the
lid"): a closed lid is 18 dark wakes a night; the master comes back wedged
on 17 of 18; a wake costs 14–22 s that no client-side fix can shorten,
because the tailnet is what is missing. `scripts/lidtest` is the instrument.

**Fixed from those numbers** (`docs/EVIDENCE.md` "v0.1.19 and v0.1.20"):
the reattach window was 20 s and gave up one or two seconds *before* the
network returned on three wakes in eighteen; it is 60 s now, ~3x the
measured worst case, pinned by `WakeWindowTests`.

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

### 15. What a second viewer does to the grid

CLAUDE.md and `docs/DESIGN.md` §4c both point here. Measured 2026-09-02: a second `claude attach` is **accepted**, output is
broadcast to every viewer, and input from any viewer goes in — which is
why the pane on any Mac is just `claude attach <id>` and no ccc depends on
another ccc. The shared PTY is **last-resize-wins across viewers**, and
what is still open is whether a secondary viewer should resize it at all
or render the grid as-is at whatever size the first viewer set.

**It comes due the first time air joins a session studio already has up**
— the ordinary case the moment the lid opens somewhere else — so this is
the one item that will announce itself rather than wait to be picked.

### 16. The shell pane has no twins but open and close

`ccc shell <ref>` opens the pane and `ccc shell --close` closes it, and
that is the whole surface: every verb that could read or drive it —
`snapshot`, `select`, `send`, `copy`, `pixel --cell` — addresses the
*session* pane (measured 2026-09-04 with a shell pane up and nothing
attached: `ccc send …` answers `ccc: nothing attached`).

This is the twin rule biting one level up — a whole **pane** with two verbs
and no others — and it matters beyond tidiness: the shell pane is the only
place ccc can paint **chosen bytes** into a real window, so anything that
wants a known sequence on screen and read back has nowhere else to put it.
`focus` already reaches both panes; a target on the request, not a second
verb set, is the shape to copy.

### 17. ccc is blind to RC, and the phone is already in the pocket

Numbers in `docs/EVIDENCE.md` "the mobile survey". None of this is the
phone; all of it makes the phone the user already has work better.

**Slices 1 and 2 are done** (`docs/EVIDENCE.md` "the mobile survey", "the
pane that could not say it had looked away", "Cut as v0.1.23"). The row
says which sessions are answerable from the phone (`rc`, an `iphone`
badge), read off `respawnFlags` — the CLI roster carries no flag signal
and `bridgeSessionId` is on every job. And the pane now answers DEC 1004:
the harness suppresses the phone's push while a terminal reports focus,
its guard skips the pulse only on an explicit blur, and ccc reported
nothing — so an attached pane could only ever *over*-suppress the phone.
`TerminalHost.setFocused` and `ccc focus [in|out]` fix that; v0.1.23
carries it. **The user's half is unmeasured**: whether the phone now buzzes
for a session ccc holds and nobody is watching.

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
(`docs/EVIDENCE.md` "the mobile survey"): **answering the "your turn" from
a phone is already shipped**, by Anthropic, through Remote Control, to
these very sessions — five of nine live workers carry `--rc`, and the
Claude app messages them, answers their permission prompts and
`AskUserQuestion`s, and sets `/model`. RC is an outbound relay with no
third-party entry point; ccc cannot join it and does not need to. **A ccc
phone must earn its place on something other than unblocking.**

**Approvals before reply**, and the order survives for a new reason.
`PermissionRequest` is documented, with a `decision` object
(`docs/HARNESS.md`), and `ccc hook` already receives Notification over the
control socket; the new part is a hook that blocks and answers. Reply is
the *other* feature now, because **a peer message can never approve** — the
docs are explicit that it "never counts as your consent, so it can't answer
a pending permission prompt". One queue line was two features.

**Reply has a documented path, so experiment 4 is optional.** Every session
binds an inbox socket and the docs sanction posting into it from a script
or hook. The address is a join ccc already makes: **`replPid`** →
`/tmp/cc-socks/<replPid>.sock`, nine for nine (`pid` is the launcher and
matches nothing); a session's own is `CLAUDE_CODE_MESSAGING_SOCKET` with
`CLAUDE_CODE_MESSAGING_TOKEN`, auth optional on macOS. A
`bypassPermissions` receiver holds the message; a prompting one takes it.
**What is left is one probe**: the message line's format is undocumented
and in the CLI's bytecode, and a probe against ccc's own socket was refused
by the auto-mode classifier (writing to a session's IPC socket reads as
injection, correctly). Run it as `! python3 …`; `ccc reply <ref> "<text>"`
is a small twin after it.

**The phone breaks exactly one locked decision**: *"PTY is always local;
remote is the same command behind `ssh -t`"* — a subprocess, and iOS has
no fork/exec. An in-process ssh client (**`apple/swift-nio-ssh`**, what
`daiimus/geistty` ships) over **libghostty's External termio backend**
(our seam's shape; builds for iOS in upstream CI) keeps the daemon
decision untouched, and **`No tmux, ever` is the edge**: every shipping
Ghostty-on-iOS client reaches for tmux control mode to survive suspension,
and ccc needs none. One trap from item 14: `ccc pixel --cell`'s scale
arithmetic has never met a Retina panel (studio is 1x; a phone is 2x–3x).

**"The core is shared" is not true yet.** `CCCKit` is one module pinned to
`.macOS(.v14)` with `PTY/`, SwiftTerm and Sparkle inside it next to
`Roster/` and `Render/`. Splitting the parts above the seam out is
Mac-side work, testable today, and what makes a port a port instead of a
rewrite.
