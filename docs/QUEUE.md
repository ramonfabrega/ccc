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

**ccc is v1, and the swarm is why.** The first real commander swarm ran
2026-09-06 and **every gap it exposed was at the spawner/roster layer,
none in the terminal embed** (`docs/EVIDENCE.md` "the swarm's five
findings"). v13 is done, items 17, 24 and 27 have left, and Remote Control
is `ccc spawn`'s default with `--no-rc` to opt out.

**The frontier is item 25, and it is now code waiting on a live count.**

Two **questions, not items**. `suggestedReply` is on the row and shown
nowhere; using it means answering without attaching (see "Later"). And
**the CLI could be a different language** — already a thin client over the
socket, and a Bun `ccc` on incur would get `--llms` and `--schema` free —
but the price is Bun on every ssh host: argue it before a second host.

Below the frontier: **item 6 is air's** and happens the next time the lid
closes overnight. Items 5 and 16 are leftovers with no forcing function;
item 33 is an afternoon that knows its own ceiling. Item 4's measurement
from air is still owed (`docs/EVIDENCE.md` "item 4 — the far side answers
from the app").

### 5. Small leftovers

A sort by model. The Session menu's archive/pin items (the context menu
has them). **`ccc window show` when another app holds focus**: since
macOS 14 `NSApp.activate()` is cooperative (measured 2026-09-02), so
`show`'s CLI side should go through `NSWorkspace`. **Twin gaps from the
audit** (`docs/EVIDENCE.md` "the audit"): `ccc ask <ref>` (the socket has
it; the CLI reaches it only through `update --ask`), a mouse-button
`send`, `hosts remove|check` in the window, an age column. **From item
18**: the New Session sheet has no worktree or base field, and a remote
`--base` is refused rather than routed to the far side's ccc. **From item
31**: the `asks` mark trusts only a typed asking mode, so a deliberate
`--permission-mode default` is invisible; the transcript's last
`permission-mode` record would see one, at a tail read per tick.

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

**It comes due the first time air joins a session studio already has up**,
so it will announce itself rather than wait to be picked.

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

### 25. The landing detector is built and unproved

`stalled` gates on the *daemon's* `updatedAt`, which keeps ticking under a
dormant session: ten landings, two windows, **zero** stall events, three
quiet finishes, and `loop-284` at `working idle` with its work pushed two
ahead. Built 2026-09-07 as `SessionEvent.landed`, keyed on the branch tip
— a join on the reading the ⇡⇣ marks already pay for (`docs/EVIDENCE.md`
"the stall stream's first run", "the landing detector").

**What is left is the count**, before the phone keeps it: a commander loop
with `ccc watch --json --all`, asking whether `pushed` fired once per
landing and whether `committed` was noise. A worker with no branch moves
no tip, and **that residue is all a peer's "done" ping should cover** — a
typed claim where a commit is evidence.

### 28. The fd rule is prose, and it has already failed once

From lore, 2026-09-07. `DispatchIO` and `DispatchSource` take ownership of
the descriptor handed to them; the caller must not close it. That is a
comment today, and the comment was **inverted** in `Subprocess.drain`
until v0.1.27 — one descriptor, two owners, `EV_VANISHED`, a crash on air
(`docs/EVIDENCE.md` "the vanished descriptor"). Two sites hold fds: that
drain, fixed by giving the channel its own `dup`, and `PTY`, whose
ownership is kept by hand in two booleans (`fdClosed`, `closed`).

Swift here is 6.3, so a `~Copyable` fd wrapper — closed once on `deinit`,
handed over by `consuming` — makes the second owner a compile error and
both booleans structural. The 0.1.27 drain regression is its fixture.
**Argue the ceremony first**: two call sites is a small blast radius, and
the counter is that one of them already cost a release on the other Mac.

### 29. A worker has no parent, and its name is three things at once

From lore, 2026-09-07, at Ramon's ask and **gated on him**. In the
2.1.260 job records `repo` comes from cwd, the item from the branch, the
role from the opener — but the **parent is in no record**, living only in
the spawner's transcript, so "which workers do I have out" is answerable
only from memory. The name is at once the SendMessage address, the roster
label and lore's peer attribution; a collision mis-attributed both halves
of a thread on 09-06. Proposed: a `<repo>-<role>-<item>` default in `ccc
spawn`, refused on a live collision by the guard that exists, and
**parent + role in the per-worktree record** beside the base — the
spawner's bridge id, which survives clears — so `ccc list --tree` and
lore read one record instead of inferring. **Half of it is lore's** and already shipped — `lore jobs` carries
`parent`, read off the spawner's transcript. **The name grammar is the
part only ccc can enforce.**

### 30. `Git.run` costs two threads and blocks on a semaphore

Found 2026-09-07 by `sample`ing a wedged suite (`docs/EVIDENCE.md` "the
suite's own deadlock"). Each call's `Drain` holds a global-queue thread
for the child's whole life while the caller waits on its semaphore, so
one `git status` needs two threads to progress; enough in parallel and
libdispatch's pool is all waiters. Measured: the suite cannot finish
parallel, and is 510 tests in 19 s with `--no-parallel`. **Production is
nowhere near the limit** — the poller probes serially, a verb is one call
— so the cost is a suite nobody can trust on a busy Mac. Fix is one
reader without a per-call thread, or `Subprocess` behind the sync face.

### 32. A dead session's dirty tree looks like every other dead session

From attrition, 2026-09-07, with 406 lines nearly lost to it. Nine
finished worktrees were reaped on the queue's own advice — *"nothing
unmerged, ccc rm"* — and the ninth, `loop-234`, had died mid-item in the
09-04/06 crash window. Every branch check agreed nothing was owed:
`HEAD..loop-234` was 0 commits and ccc's row read `level`. The **working
tree** held the item's whole product, uncommitted; it survived only
because `git worktree remove` refuses a dirty tree and a human stopped to
look.

**ccc's ⇡⇣ is computed on the branch; a session's work lives in the tree
until it commits.** They agree in every ordinary case and disagree in
exactly one — a session that died mid-item — which is where the work is
least recoverable and least likely to be remembered. Reap advice is
phrased against the branch view, so the row quietly answers a different
question than the one asked of it.

Cheap, because the probe exists: `ClearGuard.refusal(cwd:)` already reads
a dirty tree to refuse a clear and nothing puts that on a row. Two halves
— a dirty mark beside the ⇡⇣ ccc already draws, and `ccc rm`'s refusal
naming *what* it would lose ("N modified, M untracked") rather than that
git said no, which turns a refusal into a decision instead of something a
`--force` routes around. **Argue whose it is first**: the harness's
worktree flow has the same seam, and "the tree belongs to whatever
spawned the session" is a real answer.

### 33. `ccc watch`'s only filter is the host

From attrition, 2026-09-07. An agent watching one worker cannot say which,
so it pipes through `grep <name>` — and the state line and the payload
share the stream, so another session's detail text matches; it cost two
landings. `--json` escapes it already (`.ref` and `.name` are fields), so
the footgun is entirely in the text form an agent reaches for first, and
`--name`/`--ref` — the shape `--host` has — closes it. **Ceiling**: of four misses it fixes one class, the others being a filter
built from a *snapshot* of refs (upstream of ccc) and a state that never
moved (item 25). Build it for whoever keys on names, not as anyone's fix.

## Later

**`claude rm` leaves a draft's worktree behind** — the one it cut itself,
for a session that never started (`docs/EVIDENCE.md` "item 24"). A harness
bug, and ccc has no record letting it clean that tree without risking one
the user pointed `--cwd` at. Argue it first.

**Approvals before reply**, because **a peer message can never approve** —
"never counts as your consent" — so these are two features and were one
queue line. `PermissionRequest` is documented with a `decision` object and
`ccc hook` already receives Notification over the socket; the new part is a
hook that blocks and answers.

**Reply has a documented path** (address and caveats: `docs/HARNESS.md`
"The session inbox socket") and **what is left is one probe**: the line's
format is undocumented and in the CLI's bytecode, and a probe from a
session was refused by the auto-mode classifier — correctly, since writing
to an IPC socket reads as injection. Run it as `! python3 …`; `ccc reply
<ref> "<text>"` is a small twin after.

**A ccc phone must earn its place on something other than unblocking** (RC
ships that, with no third-party entry point) and **breaks exactly one
locked decision**: *"PTY is always local"*
— a subprocess, and iOS has no fork/exec. An in-process ssh client
(**`apple/swift-nio-ssh`**) over **libghostty's External termio backend**
(our seam's shape; builds for iOS upstream) keeps the daemon decision, and
**`No tmux, ever` is the edge**: every Ghostty-on-iOS client reaches for
tmux to survive suspension; ccc needs none. Trap: `pixel --cell`'s scale
arithmetic has never met a Retina panel (studio is 1x).

**"The core is shared" is not true yet.** `CCCKit` is one module pinned to
`.macOS(.v14)`, with `PTY/`, SwiftTerm and Sparkle beside `Roster/` and
`Render/`; splitting the parts above the seam out is Mac-side work,
testable today, and what makes a port a port instead of a rewrite.
