# Evidence

What was measured, with the command that measured it and the number it
answered. One `## ` section per shipped slice, named the way the commit
that shipped it is.

**Do not read this file. Grep it.** Its value is that it exists and is
searchable, not that it is read: a session working the queue needs the
conclusion, which the queue item already carries inlined, and comes here
only for the command behind that conclusion — how a thing was proved, so
the proof can be re-run.

Two rules keep it usable:

- **A queue item inlines its conclusion and never says only "see
  experiment 3".** The queue is the entry point and must stand alone; the
  moment an item delegates its substance here, a cold session has to read
  both files and the split has cost more than it saved.
- **A queue item that cites a past measurement cites it by a string that
  appears verbatim here** — `experiment 2`, `waitUntilDrawn`, `lidtest`,
  a slice name. Those are the grep keys, so they may not be paraphrased on
  either side.

`docs/CHECKS.md` is the shape this file's sections aspire to: a claim, the
command that proved it, the number it returned. Nothing here is a story
about a day's work — that ends up in the lore wiki
(`~/code/personal/lore-wiki/projects/ccc.md`), which keeps the arguments,
the reversals and the user's own words. **It gets there by lore's hand,
never by ours** (CLAUDE.md, References): a session writes the number here
and, if lore should know something, sends it. This file keeps the
milliseconds and the symbol names.

Each milestone is comparable against `claude agents` on its own. Experiments
(docs/HARNESS.md) gate the feature that needs them, not the milestone before.

## v0 — the agents view, local (2026-09-02)

**v0 — the agents view, local.** Roster from `claude agents --json --all`
(2 s poll, lenient decode, shape-change banner); one pane behind the seam
(SwiftTerm stand-in); attach / detach; model column from the transcript
tail; headless mode + `ccc list|attach|snapshot`; one recorded session as
the fixture; headless render test. Experiments 1 and 3.

## v1 — the SOTA pane (2026-09-02)

**v1 — the SOTA pane.** libghostty-vt vendored and pinned; the Metal
renderer; forkpty; the six checks; swap when it wins. **Done 2026-09-02:**
six of six, swapped, SwiftTerm demoted to `CCC_CORE=swiftterm`.

## v2 — ssh hosts

**v2 — ssh hosts.** Host picker over the tailnet; one multiplexed ssh
connection per host; roster, attach, spawn behind the prefix; TERM policy.
Experiment 2 (single attach across two Macs). Slices, in dependency order:

## v2 slice 1 — addressing (2026-09-02)

**Addressing — done 2026-09-02.** `SessionRef` (`host:id`, bare when
local, docs/DESIGN.md §4a), the host list (`ccc hosts` + its `add` /
`remove` / `check` twins, `~/Library/Application Support/ccc/hosts.json`),
and the one ssh prefix in `ClaudeCLI.argv(_:tty:)`. Proved against
`localhost` as a host named `loop` — the tactic experiment 3 opened, so
the hop has evidence before a second Mac exists:
- `ccc hosts check` — local 149 ms / loop 320 ms cold, 257–267 ms warm,
  **17 sessions both ways** (the same roster, once direct and once
  through ssh). `ssh -O check` confirms one shared master
  (`ControlPersist`), socket 0600 in a 0700 dir.
- `ccc list --host loop` — the roster with a host column, and the model
  column correctly blank on remote rows (§4a, "open").
- `ccc attach loop:1622e5f0 --headless` → `ccc snapshot` rendered the
  full Claude Code TUI through the hop into libghostty-vt; `ccc detach`
  answered `detached loop:1622e5f0`, exit 0, and the session was still
  `done · idle` in the roster after. Ctrl+Z crosses the hop.
- `ccc list` with no remote host is unchanged from v1: no host column,
  model column populated.

## v2 slice 2 — poll fan-out (2026-09-02)

**Poll fan-out — done 2026-09-02.** One `HostPoller` per host, merged
at read time (`RosterPoller.State.hosts`); a failed host keeps its last
rows marked stale, its error is one line naming it, and the roster's
own error exists only when *every* host failed. One in-flight tick per
host, ticks concurrent: live, `local 187 ms · loop 216 ms · dead
5013 ms` in one `ccc list` of 5.0 s wall, exit 0 with 20 rows and one
stderr line for `dead`. Eviction of a wedged master on a degraded poll
or a failed hop (`evictions` in `ccc stats`), `NSWorkspace.didWake` →
`PaneController.reconnect()`, and its twin `ccc hosts reconnect
[<name>]` (through the app's socket, or evict-and-check without one;
an older app answering "malformed" falls back the same way). The cwd
`~` bug is fixed by learning the far side's home at `hosts add` /
`check` (`Host.home`, `HostConfig.shortCwd`). `ccc list` now spans
every host, `--host` narrows — and the remote reader asks
`--host local`, or two Macs that list each other would poll forever.
**Found by doing it:** the default control-socket directory under
Application Support has a space, which `-o ControlPath=` rejects
("extra arguments at end of line"); every ssh through the default path
had been failing, hidden by slice 1's `CCC_SSH_CONTROL_DIR` override.
Sockets now live under `~/Library/Caches/ccc/ssh`. Remote-pane
reattach on wake is in (`sshExit` within 20 s of wake → same argv)
but has not been through a real sleep yet. **Reframed 2026-09-02 (docs/DESIGN.md
§4b): the thing that sleeps is the client, not the host** — air runs no
sessions and studio is always up — so the slice's real content is
reconnect hygiene, and the measured bug to fix is that ssh never evicts
a wedged master (a 215 ms poll becomes a permanent 5.3 s one; unlinking
the socket restores it). Carries one known display bug from slice 1:
both roster faces shorten a cwd by substituting *this* Mac's home path,
which is wrong for a host whose username differs (invisible against
`loop`, since it is the same machine; real now — air's user is
`rf-air`, studio's is `rf-studio`; fixed above). **Measured with a real lid
2026-09-02 (docs/DESIGN.md §4b):** a two-minute sleep on the tailnet
is clean — the master survives, first poll 2.1 s, no eviction needed.
Eviction stays as insurance until a long sleep is measured; the
wake-notification re-poll is worth having either way. **Experiment 2
is answered (docs/DESIGN.md §4c):** the daemon accepts every attach
and mirrors one PTY to all viewers, so the pane over ssh is plain
`ssh -t <host> claude attach <id>` on every Mac, with no ccc-to-ccc
dependency — the fork between "each ccc attaches" and "air mirrors
studio's ccc" collapsed.

## v2 slice 3 — the model column over ssh (2026-09-02)

**The model column over ssh — done 2026-09-02.** Settled by
measurement (docs/DESIGN.md §4a): the local join is 9 ms of a 199 ms
poll, so its cadence is left alone; the remote host is read by its own
`ccc list --json` (`Host.ccc`), which joins where the filesystem is and
returns finished rows in the one round trip. Live: `ccc hosts check`
→ `loop ok 213 ms ccc 17 sessions, 15 with a model`; `ccc list --host
loop` shows `fable-5-1` / `opus-5` on remote rows. `ccc stats` grew a
`model join` line (reads / cached / gone / well lookups) so the claim
is re-measurable. Two bugs found and fixed by doing it: the reader
dropped 17 good rows on `ccc list`'s exit 3 ("shape changed" is a
warning, not a failure), and `ccc list --json` reported issues through
the exit code alone — it now writes them to stderr, and they cross the
hop into the local banner.

## v2 slice 4 — host picker, TERM policy, install polish (2026-09-02)

**Host picker + TERM policy**, and the shared-size question: the
daemon's PTY is last-resize-wins across viewers (§4c), so decide
whether a secondary viewer renders the session's grid as-is instead
of resizing it. Nice-to-have; the agents view has the same wart.
**Install polish — done 2026-09-02**, the part of this slice a
second Mac needed first: the app offers to install its command on
first launch when none is on PATH (or the one there dangles), with
`ccc install-cli` and a menu item as its twins; `ccc version` reads
version and build from the bundle the executable actually lives in
(symlinks resolved, so the command on PATH answers for the app);
`ccc stats` carries the socket-holder's build and says "N builds
older, restart it" instead of meeting a malformed request on the
next new verb; `ccc hosts check` asks the far side's `ccc version
--json` on the warm master and prints its build and the skew as a
number — an older ccc there is named as predating the verb. Proved
against `loop`: `ccc 0.1.4 (55)`, skew 0, and the installed v0.1.4
reported as the older one. **Lanes, same day:** the dev bundle is
the one without Sparkle keys (`make-bundle --release` is what
`package` passes), and that absence is read everywhere — `ccc
version` says `dev`, the status item and window title are
`ccc·dev`, the updater item is disabled with the reason, and a dev
build never polls the CDN. Chosen over a separate bundle id: only
one ccc runs (the socket), the release proof lives on air, and a
second identity would split UserDefaults for nothing measured.

## Release lane — v0.1.0 through v0.1.10 (2026-09-02)

**Release lane — done 2026-09-02, v0.1.0 cut.** The fleet's mux/disk
flow (docs/DESIGN.md §6, RELEASES.md): Developer ID + hardened runtime,
notarized (accepted first submission) and stapled, Sparkle appcast on the
CDN under `ccc/`, GitHub Release v0.1.0 with the zip. Every Mac runs the
release build; studio installed it with `scripts/install --dist`, air's
first install is the zip from the CDN. The window reattaches to its last
session after a relaunch, since an update is one. **v0.1.1, same day:**
the macOS 26 floor was the v0 skeleton's, not a need — nothing in the
code is 26-only, it builds clean at macOS 14 (the Observation floor) —
so the minimum is 14.0 and air need not update first. **v0.1.3, same
day:** the Metal pane had been black on screen since v1 — a
`CAMetalLayer` never gets `updateLayer`, and `ccc peek` composites an
offscreen render, so only the human could see it (docs/DESIGN.md §7).
Draws on `render()` now; `ccc stats` counts frames presented. Plus the
Sparkle guard for unbundled runs and the `hosts add` probe. **v0.1.5,
same day (build 61):** install polish, the dev/release lane split,
v3 slice 1, `ccc rm`. Notarized first submission; feed verified
(length 3182607 both sides); master fast-forwarded to the tag. The
first release whose `hosts check` can read the far side's build.
**v0.1.6, same day (build 68):** v4 slices 1 and 2 (the overlay,
archive/pin/Delete, group and sort) and the app icon
(`scripts/make-icon`, from the ccc-site session; the first cut with
anything in `Contents/Resources`). Notarized first submission; feed
verified (length 4494378 both sides), one item. Air's Sparkle update
to it is what gives air the v4 verbs. **v0.1.7, same night:** air's
first hand on v0.1.6 found the banner never clears a notice —
"Install ‘ccc’ Command…" stayed up for good, and every archive/pin
answer from slice 1 would have too. Notices are transient now (8 s,
or a click); the socket-held-elsewhere notice stays, as a condition.
**v0.1.8, same night (build 76): the first cut through `ota`**
(docs/DESIGN.md §6a). The migration landed (typealiases over a
re-export, 174 tests, zero Sparkle in the test bundle), `ota` went on
studio's PATH, and `scripts/package` — now a build plus `ota bundle`
and `ota release` — did the whole lane in one run: signed inside-out,
notarized first submission, stapled, single-item appcast on the
fleet's key, both CDN keys, and its own live check (version 76,
length 4509224 both sides). Studio runs it. **Closed 2026-09-03:** the
other half of §6a — air's Sparkle installing a cut — is not an open
thread and has not been since. The user drives from air and keeps it
current, updating as they go; assume air is on the latest cut rather
than treating its update state as something to prove or ask about.
**v0.1.10, same night (build 85):** v5 slices 1 and 2 — `ccc spawn`,
the New Session sheet, the draft reading. Notarized first submission,
one item, live length 4623978 both sides; GitHub release v0.1.10;
studio on the cut.

## v3 — notifications

**v3 — notifications.** From the poll first (`blocked` / `waitingFor`);
the Notification hook on localhost only for what the roster cannot show;
studio ↔ air derive from each other's roster, no forwarding.

## v3 slice 1 — the transition detector (2026-09-02)

**Slice 1 — done 2026-09-02.** `TransitionDetector` (CCCKit) turns two
roster states into events: became blocked or blocked on something new,
or a live session ended (done / failed / stopped). Dedup is structural
(an event is a change in a session's state + waitingFor pair); each
host's first answer is its silent baseline; a failing host's stale rows
say nothing and its catch-up is one event; a session that leaves is
forgotten. `ccc watch` is the twin: same poll, same detector, one line
or one JSON object per event, no app needed. The window face's
`Notifier` runs the same detector on the poll it already has and posts
one banner per event (request id = the ref, so a newer question
replaces the older banner), click → attach. `ccc stats` grew a
`notifications` line (authorization, posted, last) because a banner
denied at the permission prompt is the black pane again — and it was:
the first proof posted two events to a `denied` app, which stats named.
**Proved live:** spawned sessions crossed `ccc watch` as `✓ done` and
`⏸ blocked`, the banner "ccc-v3-click is waiting — Click to attach"
reached the screen 7 s after the spawn, and pressing it attached the
window to that session (`ccc snapshot` showed its TUI). Found by doing
it (docs/HARNESS.md): a blocked row does not always carry `waitingFor`.

## v3 slice 2 — a per-host mute, and the hook (2026-09-02)

**Slice 2 — done 2026-09-02: a per-host mute, and the hook.** The mute
is a mark in `hosts.json` (`"mute": true` on a host entry; `local` is a
host too): `ccc hosts mute|unmute <name>` and the View menu's "Mute
Notifications From" submenu (checkmarks read off the file each time it
opens; the row's context menu has the same item per host) are the
twins, `ccc hosts list` says `(muted)`, and the notifier re-reads the
file when its mtime moves, so a shell's verb takes on the next tick.
The detector never consults it — what happened is one thing, what to
say is another (`HostConfig.unmuted`) — so the roster row and the
status item's ⏸ count are unchanged, `ccc watch` skips a muted host's
events and says so in its preamble, and `--all` (or `--host <muted>`)
hears them. `ccc stats` lists the muted hosts so a quiet Mac can be
told from a broken one. **The hook** is `ccc hook`: the harness's
`Notification` payload on stdin, one `hook` request over the control
socket, and the app looks the `session_id` up in the roster it already
polls (`HookEvent.notice(in:)`, pure and tested). For what the roster
cannot show — an interactive session's permission prompt, a background
session the roster has not met — it is a fresh banner with a sound,
named by the roster's name else the cwd's last component; for a
background session the roster already shows blocked it *replaces* the
poll's banner under the same request id, quietly, adding the harness's
sentence ("Claude is waiting for your input") that a `waitingFor`-less
AskUserQuestion row could never carry. Localhost only, by the slice-1
decision; exit 0 in every case (no app, an older app, junk on stdin —
one stderr line) because a failing hook is noise inside the user's own
session; `ccc hook --settings` prints the settings.json entry with the
absolute command path and the matcher
`permission_prompt|idle_prompt|elicitation_.*`, and **ccc never writes
settings.json** — that file is the user's and their dotfiles'. **Proved
live** on studio with the dev bundle (build 78; the cut went back after):
`ccc hook` against the running v0.1.8 app said `malformed request` and
exited 0 (the older-server case, as designed); against build 78 a
fabricated `permission_prompt` for an unknown session answered
`posted: proof needs permission`; an `idle_prompt` for the real blocked
`linear cuanto bill project` row (`status: idle`, no `waitingFor`)
answered `updated: … is waiting`; a fresh-id `idle_prompt` put
"second-proof is waiting — Claude is waiting for your input" on a real
`screencapture` one second later; `ccc hosts mute local` then a hook
answered `muted: …`, `ccc stats` read `notifications authorized posted 5
muted local` / `hook events 6 muted 1`, and `unmute` dropped the key
from the file; `ccc watch` with local muted opened with `muted: local
(--all hears them)` and `--all` opened without it. **Not yet seen:** three posts under one request id
(`hook:nope`) before that showed in no capture at 0.1 s or 1.5 s while
the fresh id showed at once — either the first landed during the
relaunch's activation or macOS does not re-present a replaced request;
the numbers said posted either way, which is §7's point. **The real
hook fired the same night**, from v0.1.9 (build 80) with the entry in
the dotfiles' settings.json: a `claude --bg` spawn (`ccc-v3-hook`,
CLAUDE* stripped so it registered) blocked on a Bash permission; the
poll posted "ccc-v3-hook is waiting: permission prompt" first, then
`ccc stats` read `hook events 1 last "ccc-v3-hook needs permission"` —
the harness's `permission_prompt` had arrived and updated that banner,
quietly, as designed. `ccc rm` removed the session after. The View
menu's submenu was clicked by a hand on v0.1.10 and works. Left as
decided: a session stopped by your own hand still banners, until it
annoys.

## v4 — the roster, ours

**v4 — the roster, ours.** Archive, pin, group, sort in an overlay keyed by
session id under Application Support; done vs stopped vs archived.

## v4 — Delete is not ours (2026-09-02)

**Delete is not ours — done 2026-09-02:** `ccc rm <ref>` is the
harness's `claude rm` behind the host prefix, answer and exit status
passed through, so the agents view's guard is inherited rather than
re-decided (docs/HARNESS.md: a dirty worktree is `kept`, exit 1, the
row stays). Proved on ten sessions: one kept while its worktree held an
untracked file, removed once it was dropped, nine removed outright.
The roster's Delete gesture waits for the v4 roster work; archive is
ours and stays here.

## v4 slice 1 — archive, pin, Delete (2026-09-02)

**Slice 1 — done 2026-09-02: archive, pin, Delete.** The overlay is
`~/Library/Application Support/ccc/roster.json` (`RosterOverlay`,
`CCC_ROSTER_OVERLAY` overrides), hand-editable like `hosts.json` and
decoded as leniently: a broken file is one note on the banner and no
marks, never no rows. **It lives with the session's host**
(docs/DESIGN.md §8): each Mac's file marks its own sessions, the marks
ride the far side's `ccc list --json` rows like the model does, and
`ccc archive studio:a1b2` from air is `ccc archive a1b2` on studio
behind the ssh prefix — one answer, both Macs agree. Keyed by the short
id with the session's uuid as the guard against a reused one; a mark
on a session the roster lost is pruned a week later, on a good poll of
the owning host. The rules: pinned rows sort first; an archived row
folds out of the default list **unless it is blocked** ("it's your
turn" beats tidiness), and the notifier never consults the overlay.
`ccc archive|unarchive|pin|unpin <ref>` are the context menu's twins
(`a` and `p` on the selected row in the window; `archive`/`pin` need
the row, `unarchive`/`unpin` only drop a mark); `ccc list` folds
archived rows with a count line, `--archived` shows them, and `--json`
always carries every row with its flags because it is what the far
side reads. The window folds them behind an "N archived" toggle in the
header and re-reads the file when its mtime moves, so a shell's
`ccc archive` shows a tick later. Delete is the context menu's
`Delete…` (⌫ on the selected row): one alert naming the session and
its cwd, then `claude rm` behind the host prefix, and the harness's
sentence — removed, or `kept` — is the banner. **Proved live** on this
Mac: `ccc archive 5df0fa59` / `ccc pin 2d567704` wrote the file with
both uuids, `ccc list` printed the pinned row first with a 📌 and
`(1 archived; --archived shows them)` last, `--archived` showed the row
with `(archived)`, `--json` carried the flags, `ccc archive nope`
answered `no session 'nope' in the roster`, exit 1. The window folded
the row and showed the pin a tick after each shell verb; its header's
"1 archived" toggle is on a real `screencapture` and **absent from
`ccc peek`** — the composite drops SwiftUI buttons the way it drops
materials (§7 again: the screen is the oracle).

## v4 slice 2 — group and sort (2026-09-02)

**Slice 2 — done 2026-09-02: group and sort.** `RosterSort`
(activity — the v0 order and the default — name, started, folder) and
`RosterGroup` (none, host, repo, state), one definition in CCCKit
(`State.sections(group:sort:archived:)`) behind three faces: the View
menu (Group By / Sort By / Show Archived ⇧⌘A, checkmarks read off
UserDefaults), the roster header's own menu (`@AppStorage` on the same
keys, so either face's pick is on screen at once), and
`ccc list --group … --sort …`. Pinned rows lead under every sort.
`repo` folds the harness's worktrees (`<repo>/.claude/worktrees/<n>`)
into their repository, so a project's eight worktree sessions sit under
one heading; sections follow the sort (under activity, the repo with a
blocked row leads), except `host` keeps local first and `state` is
fixed waiting / working / finished / archived. Grouping is
presentation: `--json` is flat, in the requested sort. Proved live on
the CLI (`--group repo` put the blocked ota session's repo first and
ten cuanto rows under one heading; `--group state --sort name` read as
written; `--sort bogus` exited 2 naming the words; `--json --sort
started` came back newest first) and in the window by a real
screencapture: repo headings over the same rows after `defaults write
… roster.group repo` and a relaunch — an external `defaults write`
does not reach a running `@AppStorage`, only the app's own writes do,
which is why the View menu writes through `UserDefaults.standard`
in-process. The menus themselves have not been clicked by a hand.
Open: the main menu's Session items for archive/pin (the context menu
has them).

## v5 — spawn

**v5 — spawn.** `claude --bg` with cwd, model, prompt, agent; drafts;
worktree awareness.

## v5 slice 1 — `ccc spawn` and the New Session sheet (2026-09-02)

**Slice 1 — done 2026-09-02: `ccc spawn` and the New Session sheet.**
One definition in CCCKit (`SpawnRequest` → `ClaudeCLI.spawnArgv` /
`spawn`), two faces. The harness has no `--cwd`, so the cwd is where
the command runs: the child's working directory locally, and `cd <dir>
&& claude --bg …` behind the same ssh prefix remotely, with every word
that could split or glob single-quoted for the far side's shell and a
bare `~/…` left bare so that shell expands it (`ClaudeCLI.remoteWord`).
The child's environment loses `CLAUDE*` (docs/HARNESS.md experiment 1,
amended: `--bg` registers with them, but keeps no transcript). The
answer is parsed off the harness's one line (`parseSpawnAnswer`,
pinned to the two recorded answers, ANSI included); `SpawnResult` says
`spawned <ref>` or `drafted <ref> (idle — attach and send a prompt)`.
`ccc spawn [--host] [--cwd] [--name] [--model] [--agent]
[--permission-mode] [--effort] [--worktree[=name]] [--attach] [<prompt>…
| -]`: the prompt is the remaining words, or stdin for `-` (an agent's
way to keep newlines), none is the draft; `--worktree` is bare or
`=name`, never `--worktree name`, which would eat the prompt's first
word; `--attach` then asks the app, like `ccc attach`. The sheet
(⌘N, Session → New Session…, the roster header's +) has host, folder
(with the roster's recent folders on that host, worktrees folded to
their repo, and Choose… locally), name, model with alias shortcuts,
agent, prompt, and the exact command line it will run, updated as you
type; the button reads Create Draft or Start by the prompt's emptiness;
⌘↩ submits, Esc cancels, a harness error stays in the sheet with the
fields intact; "Attach when started" attaches on success. Permission
mode, effort and worktree are the command's alone for now.
`scripts/spawn-probe` is the experiment tool. **Proved live** on studio:
`ccc spawn --cwd ~/cc-test --name ccc-v5-cli <prompt>` → `spawned
8ab526c3`, `working · busy` then `done`; the draft as `--json` with
`draft: true`; `--bogus` exit 2, `--cwd /nope` exit 1; through `loop`
(localhost as a host, re-added for the proof) `spawned loop:3548ad7e`
with `cd ~/cc-test` expanded on the far side and a prompt carrying `;`
and `'` intact, and a no-cwd remote draft landing in the far side's
home; in the window, the dev bundle (build 82) opened the sheet on a
real ⌘N, a name and prompt typed by System Events flipped the button to
Start and the preview to `--name ccc-v5-sheet 'Reply with…'`, ⌘↩ spawned
`a48c3c5d`, the pane attached and showed the prompt and `pong`. Found by
doing it: an empty submit makes a draft in the default folder at once
(correct, and fast enough to do by accident — ⌘↩ with nothing typed),
and **a fresh draft banners as "is waiting"** through the poll, since it
is `blocked · idle` from its first row (docs/HARNESS.md). Left as is
until it annoys: it *is* waiting, and the sheet's attach puts it on
screen anyway. 199 tests.

## v5 slice 2 — the draft reading (2026-09-02)

**Slice 2 — done 2026-09-02: the draft reading.** A never-prompted
session is `blocked · idle` to the harness, indistinguishable from a
session blocked on an AskUserQuestion (neither carries `waitingFor`),
so the reading is a join where the daemon's files are, like the model
column: `~/.claude/jobs/<id>/state.json` says `needs: "send a prompt to
start"` — the daemon's own phrase, the one `--bg` printed — for a draft
and carries the question for a blocked one (`DraftProbe`, read-only,
lenient; docs/HARNESS.md). Fallback when the file is missing or says
nothing: a session that was never prompted has no transcript, which
the model join already knows. The flag is `SessionRow.draft`, rides the
far side's `ccc list --json` like the model, and is false off an older
ccc. What changes: the row reads `draft · send a prompt to start` in
indigo, not orange; `ccc list` prints `draft` in the state column and
puts it under `── drafts` with `--group state` (waiting / working /
drafts / finished / archived); activity sorts drafts below live work
and above the finished; the header's "N waiting", the status item's
⏸ count and `ccc watch`'s preamble all use `isWaiting`, which a draft
is not; an archived draft folds away (an archived question still does
not); and the detector carries `draft` in its key, so a fresh draft is
no event while a draft that is prompted and then asks a
`waitingFor`-less question still rings — the edge the key exists for,
since both rows are identical to the harness. **Proved live** on
studio: the real draft `59a93d74` read `draft` and sat under `── drafts`
while the real `linear cuanto bill project` question stayed `blocked
idle`; `ccc watch` stayed silent through a `ccc spawn` draft and rang
for a prompted spawn's `done`; the window (build 83) showed the indigo
row and the status item stopped counting it. 208 tests.

## v5 slice 3 — a session from a session (2026-09-02)

**Slice 3 — done 2026-09-02: a session from a session.** The TUI's
`/fork`, from the command line: `claude --bg --resume <session id>
--fork-session [prompt]` (docs/HARNESS.md, measured with
`scripts/spawn-probe -- --resume=… --fork-session`, which now passes
`--flag=value` words to the harness) is a new background session that
opens with the source's transcript, the source untouched; with no
prompt it is a forked draft that already knows the conversation. Found
by doing it: the eight-character job id is accepted and leaves the new
session at the harness's "Resume session" picker for good, so the fork
is by the roster row's full `sessionId`. One definition:
`SpawnRequest.from` (the full id) is `--resume <id> --fork-session`
before the other words; `SpawnResult.from` carries the lineage and the
answer reads `spawned <ref> from <src>` / `drafted <ref> from <src>
(…)`. Command: `ccc spawn --from <ref> [prompt…]` — the fork runs where
its source lives (`--host` may only agree; a disagreement exits 2), in
the source's folder unless `--cwd` says otherwise, and resolves the id
through one roster poll of that host (an unknown ref exits 1). **Proved
live** on studio: `ccc spawn --from 1e7c5066 --json` → `spawned
1d35e897` with `"from": "1e7c5066-…"` and cwd `~/cc-test` inherited,
the fork answered from the source's conversation, `roster.json` showed
`fork: true, restoresTranscript: true`; `ccc spawn --from 1e7c5066`
(no prompt) → `drafted da160378 from 1e7c5066`, reading `draft` in the
roster; the `--host loop` disagreement, an unknown ref and a malformed
ref refused as designed. 211 tests.

## v5 — the fork is a verb, not a surface (2026-09-02)

**Decided the same night: the fork is a verb, not a surface.** The
sheet had gained a From row (title "Fork Session", ⇧⌘N, the row's
"Fork…", `f`), proved by a real ⇧⌘N and ⌘↩ on the dev bundle — and the
user, who has never forked a session, asked what it was for. Honest
answer: fork is branching, not resuming, and a fresh spawn with a
curated `plan.md` handoff is a cheaper fork with the transcript edited
down, while the daemon keeping every session alive removes the reason
to resume at all. So the From row, the title and the three gestures
came out, `ccc spawn --from` stays (no UI cost; an agent that wants to
branch has a way), and the gestures went to how sessions actually get
started here: **New Session Here…** — the same sheet on a row's host
and folder (⇧⌘N for the attached session, the row's context menu, `n`
on the selected row; `ccc spawn --host <h> --cwd <dir>` is the twin).
One thing the fork proof found stays: "Attach when started" now leaves
the attached session first, since attach refused with "busy" while one
was on screen — found by the fork, true of ⇧⌘N either way. Next:
worktree awareness in the sheet, display only.

## v5 — UI pass: the three things a hand noticed (2026-09-02)

**UI pass — done 2026-09-02, late: the three things a hand noticed.**
Measured with a real `screencapture` of the shipped build (v0.1.11)
and synthetic clicks and keys. (1) *The banner under the title bar and
the terminal clipped at its top:* one cause. The window is
`.fullSizeContentView`, so the content view reaches under the title
bar; SwiftUI's roster applied the safe area on its own, while the
AppKit banner and the pane container did not — the notice drew under
the traffic lights and the grid's first row sat behind the title. The
root stack now hangs from the window's content layout guide, and the
mounted pane is inset (8 pt sides, 6 pt top and bottom, the gutter
every terminal leaves) so the first column no longer touches the split
divider. The pane knows nothing of the inset: its view is its bounds,
so `peek`'s composite and the mouse's cell math are unchanged. (2)
*The roster "iffy to click":* a click highlighted the row and then ⏎,
`a`, `p`, `n` all went nowhere, on the shipped build too — the row's
tap gesture takes the mouse before the table can become first
responder, so the list never had keyboard focus after a click. The
double-click is now a simultaneous gesture beside a single tap that
selects the row and sets a `@FocusState` on the list; the click is
what makes the roster the keyboard's target. Proved on the dev bundle:
a click on the row's dot, `p` → the "pinned a18a763f" banner below the
title bar, `p` → unpinned; ⏎ attached; a double-click on the dot
attached. (3) *New Session Here…*, driven end to end: ⇧⌘N over the
attached `lore` session opened the sheet on `~/code/fun/lore`; ⌘↩ with
nothing typed drafted `1c0bf8c7` there, the pane left `lore` for the
draft (title and banner agreed), `ccc rm` took the draft away. Still
owed a hand — a script cannot feel a click — but nothing a script can
see is wrong. Found on the way: `ccc window show` did not bring the
window front while another app held focus (`NSApp.activate()` is
cooperative since macOS 14); `open -a` did. Queued. 211 tests.

## v6 — worktree awareness

**v6 — worktree awareness.** The row knows its branch and how it stands
against master, and the context menu lands it.

## v6 slice 1 — the reading and the three verbs (2026-09-02)

**Slice 1 — done 2026-09-02, late: the reading and the three verbs.**
Decided from the nightly `git merge --ff-only worktree-v2` on master,
and the user's ask for a submenu of strategies. The reading
(`WorktreeProbe`) is git's own files, not git: a worktree's `.git` is
a file naming its `gitdir`, whose `commondir` names the repository and
whose `HEAD` names the branch; the base is what `origin/HEAD` names
when that branch exists locally, else `master`, else `main` — *local*,
since the nightly fast-forward is a local act; the two tips are read
from `refs/heads/` or `packed-refs`, and `git rev-list --left-right
--count` runs once per distinct pair of shas. Steady state, twenty
rows, 2 s poll: zero processes (the test counts spawns). The reading is
`SessionRow.worktree` (branch, base, ahead, behind, repo), rides the
far side's `ccc list --json` like the model, nil off an older ccc, and
shows as `⎇ worktree-v2 ↑3 ↓2` — ↑ what the branch holds over master,
↓ in orange what master holds over it, since that is what blocks a
fast-forward — beside the *repository* (a worktree row no longer shows
its worktree path: the branch names it, and the row is 400 pt wide;
the path stays in the tooltip). `ccc list` prints the same. The verb is
`ccc merge <ref> [--ff-only|--no-ff|--squash]`, git's own words so
nothing new is learned; the row's context menu is **Merge <branch>
into <base> ▸** with Fast-forward (enabled only while master has not
moved), Merge (a merge commit; repeatable, the base moves with it),
Squash (one commit carrying every subject; the answer says the branch
is done, since a second squash re-applies the same diff), and the
standing as an inert last line. Rebase is not offered: it rewrites
the branch under a session that may still be committing to it. Every
strategy refuses a main checkout that is dirty or not on the base
branch, and a conflict backs out (`merge --abort`, or `reset --merge`
for a squash) with the files named — conflicts are a terminal's job.
The merge runs where the repository is: git here, the far side's own
`ccc merge` for a remote ref. A refusal exits 1 with the reason and
stays on the banner until read; it is the guard talking. The click
is the user's (plan.md's rule: the command is for parity, not for an
agent to press unasked). Proved: fourteen tests on real temp repos in
the harness's layout (level, ahead, diverged, packed refs, the cache,
each strategy landing, each refusal, a conflict backing out to a clean
checkout); live, `ccc list` read `⎇ worktree-bill-currency-derive ↑7`
on the real roster, `ccc merge b3919c35` on a level branch answered
"nothing to merge" (exit 1), `--rebase` was refused (exit 2), a plain
folder answered "not in a worktree on a branch", and the dev bundle
showed the submenu on the row. Found on the way: `URL(filePath:
relativeTo:)` resolves `../..` against the parent of a base with no
trailing slash — the repo read as `/` and every row was nil until the
directory hint went in. 226 tests. Next, incremental (the user's ask):
the standing against origin — the branch against its upstream, master
against `origin/master` — from the last-fetched remote refs, so it
costs no network and says "as of the last fetch".

## v6 slice 2 — unpushed, and nothing more (2026-09-02)

**Slice 2 — done 2026-09-02, late: unpushed, and nothing more.** The
user's "git status-esque" ask, narrowed the same night to the one
reading that drives an act: `⇡N` on the row when the branch holds
commits no `origin/*` ref reaches (`git rev-list --count <branch>
--not --remotes=origin` — one definition for a branch with an upstream
and one never pushed; the harness keeps such a worktree on `claude
rm`, and the Delete alert now says so before the harness does), and
`⇡N` in orange after the repository when master is ahead of
`origin/master` *by name* — found by the test: after a fast-forward to
a pushed branch every commit is on origin under the branch's name, and
"not on any origin ref" read zero while the other Mac's master still
lacked them. Nil, and no mark, when the repository has no origin. Exact
from local refs as of the last fetch or push; `origin/<branch>` and
`origin/master` are in the cache key, so a push moves the mark with no
process between. The submenu's standing line and the row's tooltip
read "3 ahead, 1 unpushed; master has 2 unpushed". A slice-1 ccc on
the far side sends no such keys and its rows keep their branch
(lenient decode, pinned). Not in scope, and not coming: the other
direction (meaningless without a fetch), a fetch loop, a push verb —
git's job in a terminal. Three tests against a bare origin. 229 tests.

## v6 slice 3 — push (2026-09-02)

**Slice 3 — done 2026-09-02, late: push.** Slice 2's first real
reading was `~/code/fun/ccc ⇡3` — master fast-forwarded here three
times and never pushed — and the user's answer to "only informative?"
turned the earlier "a push verb is a terminal's job" around: the
lifecycle of a session ends with `claude rm`, which the harness
refuses on unpushed work, so the sequence actually run is land, push,
delete, and the row showed the middle step without offering it. The
verb is `ccc push <ref>` for the worktree branch and `ccc push <ref>
--base` for the repository's default branch; the submenu gains, below
a divider, **Push <branch> ⇡N** and **Push <base> ⇡N**, each carrying
its own count and live only while it is above zero. Always `git push
origin <name>` from the main checkout, never forced (`-u` once, so a
later plain `git push` in a shell knows where to go); a moved remote
is git's non-fast-forward refusal passed through as "origin/<name>
has moved; fetch and merge in a terminal, then push again", exit 1,
nothing changed anywhere; no origin is said, not tried. Remote refs
run the far side's own `ccc push`, where the repository and its
credentials are. Not here, and not coming: fetch, pull, force,
rebase. Four tests against a bare origin, including a second clone
that moves origin/master under ours. 233 tests.

## v6 slice 4 — the shell pane (2026-09-02)

**Slice 4 — done 2026-09-02, late: the shell pane.** From the feat2
conversation: the one thing a menu cannot do is what a shell can, and
the user's picture was a pane of our own window, not a handoff to
iTerm2 (drafted, measured as the wrong half, deleted). One shell at a
time, under the session pane on a divider of its own: **Open in
Terminal** on any row, `t` on the selected row, ⌘T for the attached
session (else the selection), ⇧⌘T to close; `ccc shell <ref>` and
`ccc shell --close` are the twins, through the socket like attach.
The same `AttachSession` as a session with a different argv
(`ClaudeCLI.shellArgv`): the login shell (`$SHELL` as launchd hands
it to the app, else zsh) with the PTY's cwd set to the folder; for a
remote row the attach pane's own `ssh -t` prefix — the warm master —
and `cd '<dir>' && exec $SHELL -l` as one remote word, `$SHELL` the far
side's to expand. It stays as your shell while you attach elsewhere;
a second ask focuses it instead of doubling; it closes when its shell
exits or on ⇧⌘T (SIGHUP — never Ctrl+Z, which is the harness's detach
and would only stop a foreground job). Click either pane to type into
it. `ccc peek` composites both; `ccc snapshot` and `ccc send` still
address the session pane, so an agent's view of a session is
unchanged. Proved on the dev bundle: lore attached, `ccc shell
b3919c35` → a shell under it whose `pwd` read the ccc worktree and
whose `git branch --show-current` read `worktree-v2`; a second ask
answered "already open"; `--close` returned the session to full
height; `--close` again exited 1. Found by doing it: the divider set
before the split had laid out landed on the session's minimum, and
the shell took the rest. Not here: tabs, more than one shell.

## v6 slice 4 — one shell follows the click (2026-09-02)

**Same night, the user's question — "should opening one while one is
open replace it?"** Yes, when it is free: one shell follows the click.
The same folder is focused; a different folder replaces a shell
sitting at its prompt and focuses one that is running something,
saying so ("the shell in X is running something; ⇧⌘T closes it").
"At its prompt" is the kernel's word, not a guess: `tcgetpgrp` on the
PTY master equals the shell's pid when nothing is in front of it, and
is a job's own group otherwise (`AttachSession.isAtPrompt`, tested
with `/bin/sh -i` and a `sleep`). A shell per session — always on,
hide and show — was weighed and left: a PTY and a process per row, a
lifecycle tied to rows that come and go, and nothing described needs
it. 237 tests.

## v6 slice 5 — the pane follows the click (2026-09-02)

**Slice 5 — done 2026-09-02, late: the pane follows the click.** The
user's question after the shell pane: attach while attached should
switch, not refuse. It does: the same ref is "already attached",
another ref is left by Ctrl+Z — the harness's own detach, which
keeps the session and its draft — and the new one attached, the
answer "attached b (left a)". `PaneController.switchTo`, behind the
window's ⏎ and double-click and the socket's `.attach`, so `ccc
attach` switches too; ⇧⌘N's attach-when-started no longer detaches by
hand. The "busy" refusal was v0's guard and every gesture that met it
had worked around it. `attach(ref:)` keeps the guard for the wake-up
reattach, which must never switch behind the user's back. **And the
repository shell**, from the user's evening (a fast-forward of lore
and a `scripts/install`, both of which run in the main checkout, not
the worktree): **Open in Terminal at Repository** on a worktree row,
⌥⌘T for the attached session, `ccc shell <ref> --repo` — the same
pane, at git's answer for the repository (the harness's path
convention when the row has no reading). The follow-the-click rule
compares against the folder chosen, so the worktree and its
repository are two different asks. 237 tests.

## v6 — the banner goes: answers float, conditions live in the roster (2026-09-02)

**The banner goes — done 2026-09-02, late.** Noticed by the user on
the first Fast-forward from the row: the banner sat in the window's
vertical stack, so every sentence resized the pane, which resized the
PTY, which reflowed the TUI — the shift was the terminal redrawing.
Mocked three shapes at the window's proportions (Xcode's build HUD,
Mail's "Cannot Get Mail" strip, conditions in the roster) and chose by
kind, since Apple's apps never put both in one bar. **Answers** — what
a click did: pinned, drafted, deleted or kept, merged or refused,
attach refused as busy — float over the pane as `NoticeHUD`, an
`NSVisualEffectView` capsule with a symbol and one sentence; an answer
fades after six seconds, a problem stays until clicked. It overlays the
grid and never changes its size. **Conditions** live where they are
true: a host that is not answering is a line above its rows (in its
section's header when grouped by host, at the top of the list
otherwise) with "last seen N ago" and the error as the tooltip; the
roster's own conditions — fields that did not decode, a marks file
that did not parse — are a footer word each with the detail as the
tooltip; and the one condition about this window, another ccc holding
the control socket, is the pane's empty state. The titlebar strip was
the honest native shape for a condition but keeps the resize, and once
conditions live in the roster nothing is left for it to carry. Proved
on the dev bundle with a real screencapture: `p` on a row → "✓ pinned
a18a763f" over the pane and no row moved; ⏎ on a second row while
attached → "⚠ already attached to a18a763f; detach first" over live
output, still there after seven seconds, gone on a click; a host
named `dead` added for the proof → "dead is down · never answered"
above the rows and `dead down` in the footer, then removed (the
placement in a host section's header is by construction; the window
reads its grouping from its own menu, not from a `defaults write`). Found by doing it: a section header that renders an empty
`VStack` still takes a header's height, so the roster had a gap at the
top until the header became conditional. 226 tests.

## v6 slice 6 — Update from master (2026-09-03)

**Slice 6 — done 2026-09-03: Update from master.** GitHub's "Update
branch" as a verb: `git merge <base>` *inside the worktree* — a merge,
never a rewrite, so a session still committing to its branch sees one
more commit and nothing moved under it. It acts only at a commit
boundary: a worktree with uncommitted changes is refused (untracked
files are not changes), a wrong branch is refused, and a conflict
backs out (`merge --abort`) with the files named — and carries, in
`MergeOutcome.ask`, the one offer a menu cannot make and a session
can: "Merge master into this branch and resolve the conflicts." A
branch with no commits of its own simply moves up to master (a
fast-forward is not a rewrite); one with work gets a merge commit
named `Merge master into <branch> (N commits)`. The submenu gains
**Update from <base> ↓N** below the three strategies, live while ↓ is
above zero (the same number that disables Fast-forward), and the
twin is `ccc update <ref> [--ask]` — exit 0 updated, 1 refused or
backed out, `--json` carrying `ask` on a conflict. The refusal's
notice carries a button, **Ask the session to merge master** (the
HUD grew an optional action, a small rounded button after the
sentence; a plain notice is the capsule it was), which attaches the
pane to the session — the pane follows the click, so a session on
screen is left — waits for the TUI to draw when the attach was fresh
(two snapshots half a second apart agree), types the prompt, and
presses Enter a beat later (a `\r` inside the same read is a paste's
newline to the TUI, not a submit). That is the socket's new `ask`
request, `ccc send`'s road with the attach in front; `--ask` is its
command twin and needs the app. Remote refs run the far side's own
`ccc update --json`, read leniently. **Proved live** on studio (dev
bundle, build 103) against `scripts/worktree-fixture`, the new
experiment tool that makes a throwaway repository in the harness's
worktree layout (master two ahead, the worktree one ahead;
`--conflict` edits `a.txt` on both sides; `--origin` adds a bare
remote for slice 7): `ccc update b3919c35` on this branch answered
"nothing to update", exit 1; a draft spawned in the clean fixture read
`⎇ worktree-t ↑1 ↓2`, `ccc update` → `merged master → worktree-t (2
commits, merge commit 367d199)`, exit 0, the row a tick later `↑2`
and a second update "nothing to update"; `--bogus` exit 2; the
conflict fixture (`↑2 ↓3`) → "conflicts in a.txt; backed out,
worktree-t untouched — ask the session to merge master", exit 1, the
worktree clean, `--json` carrying the prompt; then `ccc update
96be3f4a --ask` → `asked 96be3f4a: Merge master…`, the pane on the
draft with the prompt on its TUI (a real `screencapture` and `ccc
snapshot` agree), the session ran the merge, hit the fixture's
meaningless conflict and *asked which line to keep* — the roster read
`blocked · ⏸ input needed` — `ccc send --key enter` chose, and the row
went `done … ↑3` with a two-parent merge commit in the fixture's log.
Both drafts `ccc rm`'d clean. Not clicked by a hand: the submenu item
and the HUD button (the command road under both is what was
exercised). Found by doing it: `scripts/install` under the job's
sandbox quits the app and then cannot write the bundle — run it
unsandboxed; and fixture sessions should be spawned `--model haiku`
(the user's ask; these two were served by Opus 5). 242 tests.

## v6 slice 7 — fetch, and Pull master (2026-09-03)

**Slice 7 — done 2026-09-03: fetch, and Pull master.** The other
direction, from the last-fetched remote refs and never a network call
of its own: `⇣N` beside the branch when `origin/<branch>` holds
commits the branch lacks (another Mac pushed to it; informative, the
act is a terminal's — into the worktree branch is rebase's problem by
another name), and `⇣N` in orange after the repository when
`origin/master` is ahead of master, since that is what makes Push
master a non-fast-forward. Both mirror ⇡ exactly and ride the far
side's rows the same way (nil off a slice-6 ccc; pinned). One process
now reads master's standing both ways (`rev-list --left-right --count
origin/master...master`), so the second mark costs nothing over the
first; the branch's costs one more per branch sha, and only once
origin has the branch. The verbs: **Fetch origin** on the submenu,
`ccc fetch <ref>` its twin — `git fetch origin` in the main checkout,
refs only, answering with the standing as of now ("fetched origin (101
ms); worktree-t 1 unpushed; master has 1 unpulled"); and **Pull master
⇣N**, `ccc pull <ref>`, the mirror of Push master: `merge --ff-only
origin/master` with the merge verb's guards, a diverged master refused
with the way out named ("push master first, or merge in a terminal"),
never a merge commit on master by a menu. **The app fetches on its
own twice:** once after the first poll and once on wake, every
distinct repository among the local worktree rows, concurrently off
the main actor (remote hosts fetch on their own launch and wake), and
`ccc stats` grew a `fetch` line — rounds, repos, failures, the last
round's wall time and answers — so a timer has to earn its place
against a number. **Measured on studio at launch (build 104):** three
real repositories, 1.3–1.8 s each over the network, **1.8 s wall**
concurrent; one on-demand fetch of the ccc repository 1.5 s. A timer
is not earned by that: at 2 s a fetch is the poll's whole budget, and
what it would find is the other Mac's push, which the wake round
already catches. **Proved live** against `scripts/worktree-fixture
--other` (a bare origin and a second clone that pushed to master after
this repo's last fetch): a haiku draft in the fixture read `⎇
worktree-t ↑1 ↓2 ⇡1` and no ⇣ — stale by construction — `ccc fetch`
answered in 101 ms and the row gained `⇣1` after the repository a
tick later; `ccc pull` → `pulled origin/master → master (1 commit, now
f5421e1)`, exit 0, the row `↓3`; a second pull "nothing to pull …, as
of the last fetch", exit 1; `--bogus` exit 2; on this repository,
`ccc fetch b3919c35` → "fetched origin (1515 ms); level with origin"
and `ccc pull` refused with nothing to pull. The wake round has not
been through a real sleep; it is the launch round's code behind
`didWakeNotification`, after the reconnect. Five tests against a bare
origin and a second clone. 247 tests.

## v7 — keyboard parity

**v7 — keyboard parity.** What the agents view's keys do, ours do.

## v7 slice 1 — ← on an empty prompt goes to the roster (2026-09-03)

**Slice 1 — done 2026-09-03: ← on an empty prompt goes to the
roster.** Spiked from the user's "is this possible?": in the app ←
on an empty prompt landed on a workspace-trust dialog, because the
attach client answers the harness's "← returns to agent view" by
opening the agents view *inside itself*, from the bundle's cwd
(docs/HARNESS.md experiment 6). The harness's own switch
(`leftArrowOpensAgents`) is the user's and fleet-wide, so ccc leaves
it alone and answers the press one layer up: `LeaveGesture` reads the
harness's condition off the grid (cursor visible at column 2 of a row
that starts with the prompt glyph and its U+00A0 — the NBSP cost one
false negative on the first headless run) and the key is never
written to the PTY. The seam grew one member, `keyInterceptor` on
`TerminalHost`, consulted by every core's `press`, so the window's
keyboard and `ccc send --key` meet the same gate; `AttachSession`
installs it only when the owner set `onLeaveGesture`, so a shell pane
sends every ← through. The window hands the keyboard to the roster
with the attached row selected (`RosterFocus`, a request SwiftUI's
`@FocusState` answers); → on the list, or ⏎ on the attached row,
gives it back. Twins: `ccc send --key left` replies "taken" instead
of "sent"; headless says so on stderr. Not replicated: the harness's
editing guard, and ← at the very start of a draft is ours too (the
harness would have refused it with a warning; a placeholder after the
cursor looks the same on the grid). **Proved** headless (taken on
`❯ `, sent inside a draft) and in the window (build 105: the roster
row lit in the focused blue after a socket-sent ←, pane unchanged,
`screencapture`). Nine tests. 256 tests.

## v7 slice 2 — ⌘-click opens a link (2026-09-03)

**Slice 2 — done 2026-09-03: ⌘-click opens a link.** Found by using it,
not by planning it: a CDN URL in the pane could not be clicked. The
slice began by settling who owns copy, since that was the assumed gap —
and it is **not ours**. Measured in an attached session: a drag
highlights the row and the TUI answers "copied 88 chars to clipboard ·
disable auto-copy in /config". Claude Code keeps mouse tracking on, does
its own selection, and — being a local process — writes the local
pasteboard itself; ccc is a conduit. So copy needs nothing here, with
three consequences worth writing down: it is **dead in the shell pane**
(no TUI, tracking off, ccc emits nothing — dragged across a prompt, zero
highlight and the pasteboard untouched), the Edit menu's Copy / Paste /
Select All are all `enabled = false` (⌘V works only because
`performKeyEquivalent` special-cases it before the menu sees it), and
**over ssh the far Mac's Claude would write the far Mac's clipboard** —
untested, and the fix if it bites is `GHOSTTY_TERMINAL_OPT_CLIPBOARD_WRITE`
(OSC 52), which ccc has never wired though `SwiftTermHost` implements it.
What ccc does own is the gesture the child does not want: ⌘-click, taken
in `mouseDown` before the mouse encoder the way ← is taken before the key
encoder, with the release and drag swallowed alongside the press so no
child sees a button-up out of nowhere. `LinkScanner` reads the URL off
the grid — text, not OSC 8, because the URLs that actually appear are
printed by programs that never emitted a hyperlink sequence; `https`,
`http`, `file` only; sentence punctuation and unbalanced brackets
trimmed off the tail. **One row at a time, deliberately:** rejoining a
wrapped URL needs a soft-wrap flag, and the render state ccc reads has
none (`GHOSTTY_ROW_DATA_WRAP` is on the screen API the snapshot path
never touches) — guessing from "the run reached the last column" is
wrong more often than right here, since Claude Code hard-wraps its own
output, and it would hand the browser a URL with prose glued to its
path. Twin: `ccc links` numbers what is on the grid, `ccc links --open N`
opens the Nth through the same `openLink`. **Proved live** (build 108):
`ccc links` on a real pane answered `1 https://cdn.ramonfabrega.com/…png
(row 43, col 6)`, correctly stopping before the trailing ` ok`; a
⌘-click on that text took the frontmost app from `ccc` to `firefox` with
exactly that URL in the bar; `--open 1` did the same and `--open 9`
answered "no link 9; the grid has 1", exit 1. Eleven tests. 267 tests.
Not done: no ⌘-hover affordance (the pane installs no tracking area, so
`mouseMoved` never fires), and SwiftTerm's pane does not have the
gesture — the twin covers both, since it reads `snapshot()`.

## v8 slice 1 — the pane wore Ghostty's theme (2026-09-03)

The complaint was "the colours feel off / opaque'd, not what iTerm
shows". The cause was not a missing palette but an unstated one: ccc
called `ghostty_terminal_set` with three options and never
`GHOSTTY_TERMINAL_OPT_COLOR_{FOREGROUND,BACKGROUND,CURSOR,PALETTE}`, so
every colour was the embeddable core's own fallback, which is not even
what Ghostty the application looks like.

**What the core hands back when the host states nothing.** A probe
(`GhosttyHost` + SGR, read the `Frame`) answered:

    DEFAULT background: #000000        render.zig:132, the render state's own fallback
    DEFAULT foreground: #FFFFFF        render.zig:133
    fg == bg? false
    row 1: X:#1D1F21 X:#CC6666 X:#B5BD68 …    color.zig:438, Tomorrow Night
    row 3: X:#000000 X:#878700 X:#FF00D7 X:#BCBCBC   palette 16, 100, 200, 250

So the palette was fully populated and foreground never equalled
background. `MetalRenderer.readableForeground` — the "the palette is
unset" fallback, and its two tests — was dead code left from the
sized-struct bug `FrameReader.swift:62` already fixed; deleted here.
Ghostty *the application* ships `#282C34` (`Config.zig:607`); the core
ships black because it expects its host to say.

**The other side of the comparison.** From
`~/Library/Preferences/com.googlecode.iterm2.plist`, profile "Default",
`Use Separate Colors for Light and Dark Mode: True`, system appearance
Dark: background `#15191F`, foreground `#DCDCDC`, cursor `#FFFFFF` on
`#000000` text, selection `#B3D7FF` on `#000000`, `Use Bright Bold: True`,
`Minimum Contrast: 0.0`, font MesloLGS-NF-Regular 13. The sixteen are
identical between the light and dark variants; only the specials differ.
The palette is markedly more saturated than Tomorrow Night — `#00C200`
against `#B5BD68` for green, `#2744C7` against `#81A2BE` for blue — which
is the whole of "opaque'd".

**A theme is 22 values, not 256.** Slots 16–255 are the xterm cube
(`n*40+55` per axis) and grey ramp (`(n-232)*10+8`); applications
hardcode them. `GhosttyHost.install` seeds all 256 from the core's own
`ghostty_color_palette_default` and overwrites the first sixteen, so our
cube cannot drift from the core's. Verified live: 16 → `#000000`, 100 →
`#878700`, 200 → `#FF00D7`, 231 → `#FFFFFF`, 250 → `#BCBCBC`.

**Installed as defaults, not overrides.** `terminal.zig:1352` sets
`colors.foreground.default`, and `.color_palette` calls `changeDefault`,
which preserves entries the child changed. Proved by test: after
`OSC 4;1;rgb:00/ff/00`, `SGR 31` resolves to `#00FF00`, not the theme's
red. A program that themes itself is not fighting us.

**The surfaces.** `ccc theme` prints the 16 + 6 with a truecolor swatch
per row; `ccc theme --json` is the file `CCC_THEME` reads back. Verified
end to end: a copy with `#00C200` edited to `#FF00FF` and pointed at by
`CCC_THEME` printed `knob-check … #FF00FF green`; `{"name":"bad"}` fell
back to `iterm-default-dark` with the reason on stderr, because a broken
theme must not be a terminal that will not open.

**Studio's display, for the residual.** `NSScreen.colorSpace` answers
`"Mi monitor"` — the panel's own EDID-derived ICC profile — at
`backingScaleFactor 1.0` with `maximumExtendedDynamicRangeColorComponentValue
1.0`. Neither sRGB nor P3, which retires the queue's "on a P3 display"
premise without retiring the conclusion: iTerm declares its colours sRGB
and is converted into that profile, `MetalPaneView`'s `.bgra8Unorm` layer
sets no `colorspace` and is not. That difference is now the *only*
nominal difference left, which is what makes it measurable.

Nine tests (`ThemeTests`), two deleted with the fallback. 279 tests.
Not done: bold-is-bright (the core resolves palette indices to RGB before
a cell reaches the seam — `render.h`, `..._DATA_FG_COLOR`: "Bold color
handling is not applied"), selection colours (carried by `Theme`, drawn
by nothing — `FrameReader` always builds `selection: nil`), a light
variant, and the `screencapture` comparison itself, which needs item 10.

## v8 slice 2 — the attach transition, and the hole in the ← guard (2026-09-03)

The user raised the blank pane, and then the thing it caused: *"there's a
spot where pressing left arrow will make us show the agents view warning
(the folder one)."* Two symptoms, one cause.

**The cause.** `PaneController.switchTo` detached and then attached, and
`attach` builds a brand-new host — a blank grid — which the window mounted
before the new `claude attach` had drawn. That is item 9. But
`LeaveGesture` is a *read of the grid*, and its `false` means **send the
key**, so across the same window a ← went to the child, which answers it
by detaching the session and opening the agents view inside the attach
client, workspace-trust dialog first. The blank pane was not only ugly, it
was the guard being off.

**How long the pane was blank.** Sampled every 100 ms through a switch
between two local sessions (`ad19c590` → `9f61204a`), counting rows with
anything on them:

    0.1.14 (detach, then attach)   24ms rows=0  190ms rows=0  358ms rows=0
                                   521ms rows=0  689ms rows=34
                                   4 of 5 ticks blank; settled 689 ms

    overlapped swap                20ms rows=34  186ms rows=34  350ms rows=34
                                   510ms rows=34 … 1163ms rows=34
                                   0 of 8 ticks blank; content changed
                                   between 350 ms and 510 ms

Locally the blank is ~0.5 s; experiment 3 measured the TUI taking up to
12 s to paint over ssh, against `waitUntilDrawn`'s 8 s timeout. The two
`ccc peek`s taken 300 ms into the same switch are the picture: 0 painted
rows before, 34 after — the outgoing session, still showing its `❯`.

**The fix.** Experiment 2 measured that the daemon accepts concurrent
attaches and mirrors one PTY to every viewer, so the incoming session runs
*behind* the outgoing one — unmounted, parsing into its own core — and
`install` swaps it in once it has drawn. `MainWindowController.mount`
clears the outgoing view in the same layout pass, so there is no frame
showing neither.

**Which pane owns the keyboard is not a taste call.** The queue called it
one. It is not: the old pane's grid is the one still showing `❯ `, and
that grid is what makes the guard fire. Leaving the keyboard with the
outgoing pane is what closes the hole across the whole overlap.

**The first attach has no pane to overlap with**, so the guard needed a
second half: `LeaveGesture.isUndrawn` takes a bare ← rather than sending
it while the pane has not painted. Measured on the new build:

    first attach, 0 painted rows   left -> sent; ← taken (the roster takes
                                   the keyboard, the key is not sent)
    mid-swap, 34 painted rows      left -> sent; ← taken (…)

**`isUndrawn` counts rows, and the reason is a measurement.** `claude
attach` prints its own one-line wake message — `Waking session ad19c590…`,
peeked from a fresh attach — seconds before the session's screen arrives.
One line is non-blank *and* perfectly stable, so "the grid has something
on it" answered yes on the wrong screen. Both `waitUntilDrawn` (which
would have mounted that) and the guard now read the same shape: at most
one row carries anything **and** there are still empty rows under it.
The second half keeps a small grid honest — a one-row pane is showing
everything it has, and the prompt read decides it.

**Not done.** The swap is proved locally only; over ssh it is the same
code with a longer wait, and item 3 still has no real remote to run it on.
`ccc send --key left`'s reply lost the words "on an empty prompt", which
were no longer true of both cases. 285 tests.

## v8 slice 3 — the oracle gets its twin, and 8b answers "no" (2026-09-03)

Queue item 10: CLAUDE.md makes a real `screencapture` the oracle for
presentation, but nothing in the repo could take one of a single window —
`screencapture -l` wants a `CGWindowID` nothing here produced — and nothing
could read a colour back out of a PNG, so `Grid` (which carries no colour
at all) was the only oracle and it cannot answer a colour question.

**The missing number was already in the app.** `NSWindow.windowNumber` *is*
the `CGWindowID`; it had no way out. `ccc geometry` is that way out, and it
carries what aiming needs besides the id: the window's size, the backing
scale, and the pane's rect and cell size in points.

    window 8864  1280x800pt  @1.0x
    pane   429,38  843x755pt  93x47 cells  cell 9.0x16.0pt

Cell size comes from the renderer's own `CellMetrics`, not from dividing
the pane's width by its columns: the grid is laid from the top-left with
exact metrics and the remainder is slack at the right and bottom, so
dividing drifts a little further off with every column.

**The capture runs in the CLI, not the app.** Screen Recording permission
belongs to whoever asks. Doing it in the app would put ccc behind that
prompt forever, including for `peek`, which needs no permission at all.
The split is the point: `peek` always works, `capture` tells the truth —
and the difference is visible, since a real capture carries the title bar
and the status line that `peek`'s composite of the view hierarchy never
drew.

**`ccc pixel` judges rather than reports.** `--cell <col> <row>` asks the
running app for the geometry and reads the pixel at the cell's *centre* —
a corner sits on a cell boundary and on the edge of a glyph's
antialiasing, where the answer is legitimately ambiguous. `--expect`
makes the exit code the answer:

    ccc pixel shot.png --cell 90 4              #15191F  rgb(21, 25, 31)  at 1243,110
    ccc pixel shot.png --cell 90 4 --expect '#15191F'   matches, exit 0

### 8b: there is no colour-management residual

The open half of item 8 said the on-screen difference "is the colour
management": `MetalPaneView` sets no `colorspace` on its `.bgra8Unorm`
layer, so the pane is unmanaged while iTerm is managed, and an unmanaged
layer against a non-sRGB panel moves every value. **Measured, it does not.**

One `screencapture` of the whole screen with ccc and iTerm both visible —
one composite, one output profile, nothing differing but the app — then
`ccc pixel` on each:

    ccc's pane (Metal, unmanaged)   #15191F at 1250,470
                                    #15191F at 1250,880
                                    #15191F at 700,940
    iTerm2 (colour-managed)         #15191F at 1880,400
                                    #15191F at 1700,300

Bit-identical, and both equal to the theme's nominal `#15191F`. A profile
conversion moves dark values too, so "both unshifted" is a real answer and
not an insensitive probe. The background is the probe rather than any
glyph because text pixels are antialiased and a glyph's centre is not its
nominal colour.

So the premise was wrong twice over — first about *why* (studio's display
answers `NSScreen.colorSpace` with its own EDID profile, which was already
recorded as a correction), and now about *whether*. On this display the
two panes are indistinguishable, and the complaint that opened v8 is
answered in full by the theme alone.

**Not done.** One display, one profile, at 1x — a Retina panel or a
different profile is untested, and `pixel --cell`'s scale arithmetic is
covered by tests but has never run at 2x for real. Whether a replay golden
could assert RGB is still unanswered: `GridBuilder` carries no colour, so
the headless oracle still cannot judge one. 295 tests.

## v9 slice 1 — the hop is real, and the host list was frozen (2026-09-03)

Queue item 3. Every ssh proof before today was `localhost` wearing a
costume: nothing listened on 22 on either Mac, and `ccc hosts` held
`local` alone. Remote Login went on for studio the same afternoon, so
this is the first day a `Host` with an `ssh` destination pointed at a
real `sshd`.

**studio is both ends of this bench, and that is stated, not hidden.**
The client half is the code air will run, byte for byte; the server half
is the sshd air will reach. What a loopback hop cannot carry is latency,
loss, and a second Mac's own config — so every number below is a floor,
and the air→studio numbers will be larger.

### The hop, end to end

    ssh studio 'echo OK; hostname'                    OK / Ramons-Mac-Studio.local
    ccc hosts add studio --ssh studio
      → added studio (ssh studio, claude /Users/rf-studio/.local/bin/claude,
        roster via ccc /opt/homebrew/bin/ccc, home /Users/rf-studio)
    ccc hosts check studio    studio  ok  684 ms  ccc 21 sessions, 18 with a model  ccc 0.1.15 (118)
    ccc hosts check local     local   ok  223 ms  claude 21 sessions

`ccc hosts add` found both paths over the wire rather than being told
them — **experiment 3's finding held**: a non-interactive ssh has no
`claude` on PATH here (`~/.local/bin` is added by `.zshrc`, which even
`zsh -lc` does not source), so the absolute path in `Host.claude` is
load-bearing and `validate()` is right to refuse a host without one.

Then a fixture spawned, attached and driven entirely over the hop
(`--model haiku`, the fixture rule):

    ccc spawn --host studio --model haiku --name ssh-hop-fixture …   736 ms → studio:549594ed
    ccc attach studio:549594ed        attached studio:549594ed
    ccc snapshot                      ▐▛███▛█  Claude Code v2.1.259 / Haiku 4.5 · Claude Max
                                      ❯ Print the numbers 1 through 5 … / ⏺ 1 2 3 4 5
    ccc resize 100 30                 grid cols 100 rows 30
    ccc send "hello over ssh"         lands in the composer
    ccc send --key ctrl-u             clears it ("Ctrl+Y to paste deleted text")

Steady state over ~75 remote polls: `studio last 599 ms mean 543 ms`
against `local last 161 ms mean 171 ms`, 0 failures, **0 evictions**, and
the notifier fired for the remote host (`posted 4, last "ssh-hop-fixture-2
finished"`). The model column works remotely, which is `Host.ccc` earning
its place: 18 of 21 rows carried a model inside the one round trip.

### The attach transition over ssh (item 9's first open end)

`waitUntilDrawn`'s 8 s timeout was written for the long ssh wait and had
never met one. Six alternating swaps between two remote fixtures, timed
end to end, against the same two sessions reached by the local path:

    remote (studio:)   1385, 1075, 1122, 1112, 1102, 1133 ms
    local              1022, 1020, 1086, 1059, 1079, 1084 ms

Every one answered `attached … (left …)`, so the old pane held until the
new one drew — no blank grid, over ssh, ever. **The hop costs ~20–50 ms
on a warm master**; the second is `waitUntilDrawn`'s own floor, which is
two stable 250 ms samples. The 8 s timeout is ~7x the observed worst
case on this bench, and untested against a hop with real latency.

### §4c, answered by measurement: last-resize-wins is visible and heals

With the app's pane on `studio:549594ed` at 100x30, a second viewer —
plain `claude attach 549594ed` on its own PTY at 60x20 — was attached
alongside it (`$CLAUDE_JOB_DIR/tmp/viewer2.py`, 2449 bytes read):

    app pane, alone            grid 100x30, TUI drawn to 100 columns
    app pane, viewer2 up       grid 100x30, TUI drawn to 60x20 — letterboxed
    app pane, viewer2 gone     grid 100x30, TUI back to 100 columns

So ccc's grid geometry is its own and never follows the shared PTY; what
follows is the *content*, because the daemon resizes the one PTY to the
newest viewer and mirrors it to all. The damage is bounded — dead space,
never corruption — and it heals when the other viewer leaves. Nothing has
to change for a secondary viewer to be safe; what is still open is whether
ccc should decline to resize when it is not the only viewer, which would
stop it *causing* this for others but cannot stop it *suffering* it, since
any bare `claude attach` does the same.

### The host list was read once at launch

Found by doing the above: `ccc hosts add studio` succeeded, `ccc hosts
check studio` and `ccc list --host studio` answered from the CLI, and the
app said

    ccc: unknown host 'studio' (known: local); add it with `ccc hosts add`

`PaneController.hosts` was a `let`, loaded in `init`, on the reasoning
that "a host list that changes under a running attach would change what
the pane is talking to". It cannot: an attached pane holds an
`AttachSession` whose argv was built when it started, so a reload moves
what *new* refs resolve against and which hosts are polled, and never the
running child. Meanwhile `Host.swift` already promised "one line adds a
Mac" and `HostConfig.modificationDate` already existed, unused by anyone
but the mute set.

The fix is the rule the overlay has always followed, applied to
hosts.json: one `stat` per 2 s tick, reload when the mtime moves,
`RosterPoller.sync(to:make:)` to add, drop and rebuild pollers. A host
that merely moved in the file keeps its slot and its counters; one whose
`ssh`/`claude`/`ccc` was edited gets a fresh poller, or the roster would
keep reading the command the user just changed.

Proved live against the running app, no relaunch:

    ccc hosts remove studio   → 3 s later: ccc: unknown host 'studio' (known: local)
    ccc hosts add studio …    → 4 s later: the studio rows are back
    ccc attach studio:549594ed → already attached to studio:549594ed

That last line is the safety claim holding: the pane attached over the
removed host stayed alive across its removal and re-addition. 299 tests.

## v9 slice 2 — 12a: colour a golden can assert (2026-09-03)

Queue item 12a. `Grid` was `lines: [String]`, so the one oracle an agent
can run with no screen could not answer a colour question — `ccc capture`
/ `ccc pixel` can, but they need a *window* and Screen Recording
permission, which a headless agent has neither of.

**The colour was never far away.** `GhosttyHost.snapshot()` already read a
colour-complete `Frame` — the same one the renderer paints from — and
dropped every colour to keep `cell.text`. The slice is: stop dropping it
when asked.

    ccc snapshot [--json] [--color]
    ccc replay <bytes-file> … [--color]
    Grid.colors: [[ColorSpan]]?     nil unless asked; ColorSpan = col, len, fg, bg

### Resolution is shared with the renderer; the merge is not

Both go through `RunMerge.resolvedColors`, which applies `inverse` and
substitutes the frame defaults — so a span reports the colour that is
actually **painted**. The merge deliberately differs: the renderer merges
by full `RunStyle` (fg + bold + italic + underline…) because that is what
forces a new shaping call, while a colour oracle merges by colour alone.
Sharing the merge would make one of the two wrong. `ColorSpansTests`
pins the shared half cell by cell (`theOracleResolvesExactlyAsTheRenderer
Does`), which is what stops a future re-implementation drifting the two
oracles apart.

One row of SGR through the real core, `ccc replay --color --json`:

    plain red inverse bluebg
    0+6   #DCDCDC on #15191F     default pair
    6+3   #B43C2A on #15191F     ANSI red, palette resolved
    10+7  #15191F on #DCDCDC     inverse: swapped, not ignored
    18+6  #DCDCDC on #2744C7     background colour
    24+16 #DCDCDC on #15191F     the tail

40 columns become 7 runs, every column covered exactly once and the runs
contiguous (asserted).

### It agrees with the screen oracle by string equality

The headless oracle spells a colour `#RRGGBB` — the same spelling
`ccc pixel` and `ccc theme` print — so the two are comparable with no
arithmetic. `Frame.RGB` is now `Codable` as that one string, and
`rgbIsCodableAsTheHexPixelPrints` pins it against `PixelReader.hex`.

The default background it reports is **`#15191F`**, which is the value
"8b: there is no colour-management residual" measured off a real
`screencapture` and found bit-identical between ccc's pane and iTerm.
**Not re-run today**: `ccc capture` refused for want of Screen Recording
permission on this job's terminal — correctly, since that permission
belongs to whoever asks (v8 slice 3). So the agreement is against 8b's
recorded number, not against a capture taken beside it.

### Live, on a real attached pane

`ccc attach ad19c590` then `ccc snapshot --color --json`: 93x47, **21 of
47 rows carry more than one run** — `#999999` for the dim "Churned for
2m 48s · done 2:55 AM" status line, `#B1B9F9` for highlighted text,
`#DCDCDC` on `#15191F` elsewhere. Real TUI colour, read with no screen.

The real `claude attach` capture is the opposite case and worth stating:
it carries **no SGR colour anywhere**, so all 30 rows are one run of the
default pair. That is now pinned, which says what colour the existing
text goldens were always being drawn in.

**Off by default, deliberately.** `snapshot()` is a hot path —
`waitUntilDrawn` takes one every 250 ms through an attach transition, and
`LeaveGesture` and `LinkScanner` each take one per gesture. None want
colour, and an always-on grid would put ~4,400 cells of RGB through the
control socket on every `ccc snapshot`. `theDefaultSnapshotCarriesNo
Colour` pins that.

The SwiftTerm escape hatch answers `colors: nil` rather than empty runs —
`GridBuilder` reads text alone, and an empty array would read to a golden
as "no colour anywhere" instead of "this core cannot say". 307 tests.

## v9 slice 3 — 12b: a selected cell wears the theme (2026-09-03)

Queue item 12b. `Theme` has carried `selectionBackground` / `selection
Foreground` since v8 and nothing read them; `FrameReader` set every row's
`selection` to nil and inverted selected cells instead (`if selected {
cell.flags.insert(.inverse) }`). Both are gone: the row carries the
range, the theme carries the colours, and `RunMerge.resolvedColors`
joins them.

### The finding that shaped the slice: there was no producer

**Nothing in ccc could make a selection at all.** The core's selection is
set by the host through `GHOSTTY_TERMINAL_OPT_SELECTION` and ccc never
called it, so `..._CELLS_DATA_SELECTED` was false for every cell of every
frame ever read — the inversion above had never once run in the app. The
child owns the mouse (Claude Code keeps tracking on and does its own
drag-selection, v7 slice 2), so a local drag has to be a gesture the
child does not want, the way ⌘-click is, and that is not built. Shipping
the colours alone would have been shipping unreachable code, so the slice
carries the producer with them:

    ccc select <col> <row> <col> <row> [--rect]      both ends inclusive
    ccc select --clear
    GhosttyHost.select(SelectionRegion?) -> Bool     nil clears; false = off the grid

### The rule: selection wins outright

A selected cell paints the theme's two colours whatever the child had
set — not an inversion of them. One sentence a golden can state, and it
resolves in `RunMerge.resolvedColors`, the function the renderer and the
colour oracle already share (12a), so the pane and `ccc snapshot --color`
cannot come apart on it. Live, on a real attached pane (`ad19c590`,
headless on a private `CCC_CONTROL_SOCKET` so the running app was not
touched):

    ccc select 2 3 40 3        → selected 2,3 → 40,3
    ccc snapshot --color       0+2   #DCDCDC on #15191F
                               2+39  #000000 on #B3D7FF     39 cells: both ends inclusive
                               41+49 #DCDCDC on #15191F
    ccc select 5 2 10 4 --rect → rows 2,3,4 each 5+6 on #B3D7FF   a block, not three lines
    ccc select 0 0 200 0       → ccc: 0,0 → 200,0 is not on a 80x21 grid   (exit 1)
    ccc select --clear         → no #B3D7FF run anywhere

### Two things the C API decided for us

**Once per row, not once per cell.** `render.h` says it outright about
`..._CELLS_DATA_SELECTED` ("prefer querying `..._ROW_DATA_SELECTION` once
per row"), and v1 was doing the per-cell read: one C call per cell per
frame — ~4,400 on a full pane — to answer a question the row already
knew. The row-local range is one call and is what `Frame.Row.selection`
now holds.

**And the bench cannot see it, which is stated rather than dressed up.**
`ccc bench Fixtures/attach/attach.bin --repeat 300`, release, A/B by
putting the per-cell read back and rebuilding: row-local 0.180 ms best of
8 runs (0.18–0.28), per-cell 0.201 ms best of 4 (0.20–0.22). The best
runs lean the right way by ~10% and the distributions overlap completely
— studio had three other agents on it. So the claim here is structural
(a call per row instead of a call per cell, on the API's own advice), not
a measured win; a quiet machine could resolve it.

**Selecting does not dirty the terminal.** `Screen.select` (vendored
`src/terminal/Screen.zig:2879`) tracks pins and marks nothing dirty — the
embedder's renderer is expected to know it changed. Nothing is written to
the terminal either, so the render state's dirty level stays `false` and
`MetalRenderer.shouldDraw` would skip the frame: the pane would keep
showing an unselected grid until the child next printed. `GhosttyHost`
marks the *next* frame full instead (`needsFullRedraw`), on the
renderer's path only, so `snapshot()` still consumes nothing.
`selectingForcesTheNextFrameToRedraw` pins both halves — full once, clean
after.

### Down to pixels

`aSelectedCellIsBlueInTheRenderedPixels` renders a selected frame through
the real Metal renderer into an offscreen texture and reads the image
back: the selected blank cell's centre is `#B3D7FF`, an unselected blank
is `#15191F`, and across the whole of a selected *glyph* cell no pixel is
the default background while some are neither ground nor default — the
glyph, drawn on the selection. Sampled at cell centres, the way
`WindowGeometry.pixel` aims `ccc pixel --cell`, and spelled `#RRGGBB` so
a future `ccc capture` of the same thing is comparable by string
equality. **Not run through a real `screencapture`**: that permission
still belongs to whoever asks, and this job's terminal does not have it
(the same gap 12a recorded).

Ten tests (`SelectionTests`) plus one wire test — `select` carries a
region or a nil that means clear, and the two must stay distinguishable
or `ccc select 0 0 4 0` becomes a clear on an older far side. 318 tests.
Not done, and now unblocked rather than blocked: the drag gesture itself
(which modifier, and what ⌘C copies — the core has
`ghostty_terminal_selection_format_buf` for the text).

## v9 slice 4 — 13: the drag, and what a boundary means (2026-09-03)

Queue item 13. 12b built the whole selection path and stopped at the
hand; this is the hand. The core ships the state machine —
`ghostty_selection_gesture_event` with typed press/drag/release events,
a click sequence it counts itself, and the cell/word/line behaviour
table — so `GhosttySelectGesture` is a lifetime wrapper and a coordinate
conversion, and holds **no selection logic at all**. Same rule as keys
(CLAUDE.md): word boundaries and reversed drags are Ghostty's to get
right.

### The three open questions, answered

**Which modifier: shift.** Not ⌥, not ⌘. The child owns the mouse, so
ours has to be a gesture it does not want — and xterm, iTerm2, kitty and
Ghostty all make shift the override that bypasses mouse reporting, so no
child has ever seen a shift-drag in any terminal and none can miss it
here. ⌘ was already taken by links (v7 slice 2). ⌥ makes the drag a
rectangle, which is where a terminal puts it and what
`GhosttySelection.rectangle` already took. And when nothing is tracking,
the plain drag is ours: the encoder emitted nothing for it anyway.

**What ⌘C copies:** `ghostty_terminal_selection_format_buf`, plain,
`unwrap` and `trim` both true — the header names that combination as the
one matching Ghostty's own `Screen.selectionString()`. Unwrap is the one
that earns its place: a soft-wrapped path copied with the wrap in it is a
path that will not paste (`copyingUndoesASoftWrap`: ten columns, twelve
characters, one string). **The pane keeps no clipboard of its own** — the
copy *is* `NSPasteboard.general`, because a second store would only be a
thing to keep in sync. ⌘C with nothing selected is not taken, so the menu
keeps the key.

**What clears a selection:** one line, `clearSelection()` at the top of
`beginSelection`. A press takes the old selection away *before* the core
is asked for a new one, so a plain click is a clear by construction, a
double-click replaces it with a word, and a drag replaces it as it moves.
Typing clears too (⌘C and ⌘V never reach `keyDown` — `performKeyEquivalent`
answers first, so a copy cannot clear what it is about to copy).

### The measurement: a drag runs between boundaries, not cells

Probed against the real core, anchor at column 6, pointer at column 10,
cell 8 px wide, varying only the pointer's x within its cell:

    x = 80 81 82 83 84  → 6..<10      left half: the boundary before cell 10
    x = 85 86 87        → 6..<11      right half: the boundary after it
    no position at all  → 6..<10      offset 0, so the left half

The anchor obeys the same rule (pressing in the right half of the "w"
starts the selection *after* it), and it is direction-free: pressing past
the "d" and dragging back to the "w" is the same five cells. So the
pointer's sub-cell x is load-bearing and the pane passes the true
position, not the cell's centre — which is what makes "drag past the
middle of the character to take it" true here as everywhere else.
`theHalfCellRule` pins both sides one pixel apart.

### The twins

The gesture's command twins, since a double-click is a gesture too:

    ccc select --word <col> <row>     the double-click; a second point drags the grain
    ccc select --line <col> <row>     the triple-click
    ccc copy                          ⌘C: the text, and onto the pasteboard

`grain` rides inside `SelectionRegion` rather than becoming a second
verb, and is optional on the wire for the `send`/`paste` reason: a v9
`ccc select` sends no `grain` key and an older server must read that as
the cell selection it always was (`aSelectWithoutAGrainStillDecodes`).
`--word` is `ghostty_terminal_select_word_between`, which the header
names as the double-click-and-drag primitive; `--line` is
`select_line`, twice, unioned in viewport order, because no
`select_line_between` exists.

Live, on a real haiku fixture (`6ee7ca93`, headless on a private
`CCC_CONTROL_SOCKET` so the running app was not touched), against the
line the fixture printed:

    ccc select --word 4 9   → the          ccc select --word 10 9 → quick
    ccc select --line 4 9   → ⏺ the quick brown fox jumps over the lazy dog.
    ccc select 2 9 12 9     → the quick b  and `pbpaste` says the same
    ccc select 2 8 12 10 --rect → the quick b     three rows, eleven columns
    ccc select 40 8 12 10       → the whole line   the same corners, linear
    ccc select --word 70 12 → ccc: no word at 70,12                    (exit 1)
    ccc select --word 5 99  → ccc: 5,99 → 5,99 is not on a 71x25 grid  (exit 1)
    ccc copy (nothing selected) → ccc: nothing selected                (exit 1)
    ccc snapshot --color, row 9  6+5 #000000 on #B3D7FF   the theme's pair

That last line is the whole chain in one reading: a word grain → the
core's word rule → an installed selection → 12b's colours → the text on
the pasteboard.

### The routing is tested as the window will run it

`PaneSelectionRoutingTests` drives real `NSEvent`s through the real
`PaneInputView`, because the half that can break silently is not the
selection but **who gets the press**: a wrong modifier leaves the pane
looking right while the TUI stops answering the mouse. With DEC 1002 on,
a plain drag puts bytes on the wire and selects nothing; a shift-drag
sends the child *nothing at all* — not a press, not a release, since a
child that saw no button-down must never get a button-up — and selects.
With tracking off the plain drag selects. No assertion there depends on
where a synthesized event lands in the grid: an event with no window is
converted without the flip, so the y axis is upside down, and the tests
fill every row with text instead of pinning a row.

21 tests over two suites, plus the wire test; 340 total.
Not done: **autoscroll**. The core ships an autoscroll tick event and
reports a direction, and the pane has no scrollback UI to tick against —
a drag that leaves the grid stops at the edge. Nor a deep-press, nor
⌘A for select-all (`ghostty_terminal_select_all` exists).

## v9 slice 5 — 12c: bold is bright, and the index that was never lost (2026-09-03)

Queue item 12c, the last of item 12. **A bold cell wearing ANSI colour
0–7 paints colour n+8** — iTerm's "Use Bright Bold", on in the profile
ccc's sixteen were read out of, so the pane had been one policy short of
the terminal it was measured against since v8 slice 1.

### The blocker did not exist

The item, and `Theme.swift`'s own comment, recorded this as needing work
across the seam first: the core resolves palette indices to RGB before a
cell reaches us (`render.h`, `..._DATA_FG_COLOR`: "Bold color handling is
not applied"), so there is no *n* left to add 8 to, and the fix was
either "carry the index across the seam or resolve the palette ourselves".

Both halves of that were wrong, and one probe against the real core said
so. `..._DATA_FG_COLOR` is flattened, yes — but `GhosttyStyle.fg_color`
is a **tagged union** (`style.h`), and `FrameReader` was already reading
that struct every cell, for `bold` itself, and throwing the colour half
on the floor. Four SGR runs, read out of the style rather than the
resolved colour:

    [1;31m           bold=true   tag=1 PALETTE  slot=1     resolvedFg=204,102,102
    [31m             bold=false  tag=1 PALETTE  slot=1     resolvedFg=204,102,102
    [1;38;2;10;20;30m bold=true  tag=2 RGB                 resolvedFg=10,20,30
    [1m              bold=true   tag=0 NONE                resolvedFg=none

The index survives, and it distinguishes itself from truecolor and from
the default foreground — which is exactly the three-way answer the policy
needs. Nothing new crosses the seam; the reader stopped discarding it
(`Frame.Cell.fgPalette`, one `if` in a call already being made).

The second half — "or resolve the palette ourselves" — is unnecessary
too. Only slots 0–7 promote, and 8–15 are `theme.ansi[n+8]`, which ccc
already owns and already seeded the core with (`GhosttyHost.install`).
The core's 256-entry palette never has to cross anything, and the theme
and the core cannot disagree about the eight because one made the other.

### Resolved where selection is, for selection's reason

The promotion is a **policy**, not a colour, so `Frame` still carries only
what the core said — the unpromoted colour *and* the slot — and
`RunMerge.resolvedColors` turns the two into one answer, the same shared
function the renderer and the colour oracle both go through (12a's rule).
`ccc pixel` and `ccc snapshot --color` therefore cannot come apart on it.

Three rules, each a `nil` rather than a special case: a cell with no slot
keeps its colour (truecolor, and the default foreground — inventing an
*n* there would mean deciding "bold" means "white", a second policy
wearing this one's name); slots 8–15 are already bright; slots 16–255 are
the xterm cube, where +8 is a different colour rather than a brighter one.
And the promotion applies **before** `inverse` — it decides what the cell
is wearing, inversion decides which side wears it.

`Theme.boldIsBright` is the knob, default true, `decodeIfPresent ?? true`
so a `CCC_THEME` file written before today keeps rendering as it did.
`ccc theme` says it in words, because it is the only theme value that is
a policy and otherwise an unexplained difference between that table and
the screen.

### Measured

Through the shipped CLI, `ccc replay --color --json` on `[31mplain[0m
[1;31mbold[0m`:

    0+5   #B43C2A on #15191F     ANSI red, slot 1
    6+4   #DD7975 on #15191F     the same SGR, bold — slot 9

And through the **real Metal renderer** into an offscreen texture, read
back as pixels the way `ccc pixel --cell` aims: two cells identical but
for the `1`, under `inverse` so the promoted colour lands as a solid quad
rather than antialiased glyph ink, centre-sampled at 2x —
`#DD7975` and `#B43C2A`. SGR bytes to GPU pixels, spelled the way
`ccc pixel --expect` takes them.

`allEightSlotsPromoteToTheirOwnBright` walks all eight rather than
trusting red: an off-by-one in the slot arithmetic passes for red and
fails for six of the eight. 12 tests in the suite, 352 total.

**Not re-run today, again**: `ccc capture` still refuses for want of
Screen Recording permission on this job's terminal (v8 slice 3, and 12a
and 12b before it). The offscreen render is the closest available stand-in
and it is not the same oracle. Comparing ccc's bold red against iTerm's
side by side, from a terminal that has the permission, is still owed —
now for three slices rather than two.

### And one leftover, since it was one line away

`ccc stats`' first line is the app's — `pid`, `memory`, `uptime` — and the
third was the attached **pane's** age, `AttachSession.startedAt`, with
`PaneController` passing a literal `0` whenever nothing was attached. A
week-old app read "uptime 0s" the moment you detached (queue item 5,
noticed 2026-09-03). It reads `ri_proc_start_abstime` off the process now,
in both branches — a number the process cannot be wrong about, from the
same `proc_pid_rusage` call `footprint` was already making. Nil rather
than zero for a pid we cannot see, the roster's rule.

## v9 slice 6 — item 3: the tailnet is a list you can pick from (2026-09-04)

Queue item 3's last step, the data half. `hosts.json` is hand-editable and
one line adds a Mac; this is the other half — not looking up an address.

    ccc hosts discover [--json]
    Tailnet.scan() -> [Peer]        name, dnsName, hostName, online, lastSeen, isSelf

Six nodes on the tailnet, two offered:

    air     air.bengal-barb.ts.net     Ramon's MacBook Air
    studio  studio.bengal-barb.ts.net  Ramon's Mac Studio  this Mac  (added)

### It enumerates; the probe still decides

**The tailnet cannot say who runs an sshd.** `tailscale status --json`
carries `HostName`, `DNSName`, `OS`, `Online`, `LastSeen`, `Expired` — and
no host keys, no "offers SSH", nothing about port 22. A Mac with Remote
Login off is indistinguishable from one with it on. So `discover` lists
*candidates*, never *servers*, and `ccc hosts add` stays the gate: it
probes over the real ssh for `claude`, `ccc` and `$HOME` and refuses what
does not answer. Any filter cleverer than "is it a live Mac" would be a
guess wearing a filter's clothes.

Dropped, each for a reason a machine can check: the iPhone and two
`tag:k8s` Linux boxes (not macOS), and `mbp` — whose **node key expired
2025-07-26**, so it goes for `Expired` rather than for looking old, which
would have been a threshold someone has to pick.

### Two things the capture corrected

**The name is the first label of `DNSName`, not `HostName`.** The Macs
call themselves "Ramon's Mac Studio" and "Ramon's MacBook Air" — spaces
and a smart apostrophe, so not legal host names — and the iPhone calls
itself `localhost`. The MagicDNS label is the only field that is both a
legal `Host.name` and an ssh destination.

**And the *short* label is the destination, not the full name** — the
opposite of what it looks like, found by trying it:

    ccc hosts add studio --ssh studio.bengal-barb.ts.net
    → ssh to studio failed: Host key verification failed.
    ccc hosts add studio --ssh studio
    → added studio (claude ~/.local/bin/claude, roster via ccc, home /Users/rf-studio)

`known_hosts` and `~/.ssh/config` are keyed on what a human types; the
full name is a different host to ssh, with no key on file and no `User`
line. `--ssh` already defaults to the name, so the hint is `ccc hosts add
<name>` with no flag at all.

That failure is also the **first** add from any new Mac, and it was
reported as "no claude found" — the search path was never reached. It now
names the one command that fixes it: run `ssh <dest>` once to accept the
key, then add.

### The loopback, registered and proved

`ccc hosts add studio` then `ccc hosts check`:

    local   ok  157 ms  claude 20 sessions
    studio  ok  648 ms  ccc 20 sessions, 18 with a model  ccc 0.1.16 (131)  home /Users/rf-studio

Which is the shape the picker is for: register this Mac and it appears
beside `local`; register nothing and the list is `local` alone. 648 ms
against 157 ms is in line with v9 slice 1's 684 ms.

**Not built here: the app's picker UI.** This is the data and the command
twin; the menu that shows it is next, and it has nothing left to work out.
Driven from a real capture (`Fixtures/tailnet/status-2026-09-04.json`,
trimmed to the fields we read). 7 tests, 361 total.

## v9 slice 7 — item 3: the picker, and sheets become visible (2026-09-04)

Queue item 3's last step. Two ways in, one sheet, and it does no work of
its own: the list is `Tailnet.scan()` and the button is `HostSetup.add`,
both shared with `ccc hosts discover` and `ccc hosts add`.

    App menu ▸ Add Mac…                     one-time setup, next to Install 'ccc' Command…
    New Session ▸ Host ▸ Add Mac…           where a host is actually being chosen
    ccc window add-host | new-session       the twins that open them

### Where, and why not elsewhere

`NewSessionView` hid the Host row entirely below two hosts, so a Mac that
had only ever seen `local` had **no host UI at all** — exactly the Mac
that wants to add one. The row is now always shown, with the picker sized
to its content rather than a fixed 200pt, which had left the link
floating a long way from the control it belongs to.

Not the status item: clicking it shows the window, and turning a
one-click gesture into a menu costs more than it gives. Not the View
menu, which is display preferences.

### Adding a host was about to have two implementations

`HostSetup.add` is new and is the reason the picker is safe to have: the
probe, the flag overrides, the validation and the save were inline in
`ccc hosts add`, and the picker would have been a second copy that
eventually learned something the first did not. The CLI now reads flags
and prints; it decides nothing (CLAUDE.md: one definition, many surfaces).

### `peek` could not see a sheet — and never could

A sheet is its own `NSWindow`, so it was absent from the view hierarchy
`peek` walks, and **every sheet this app has ever shown was invisible to
the headless oracle**. `peek` now composites `window.sheets` in their real
places, the same way it already composites the Metal pane. That is what
made the two screenshots above possible with no Screen Recording
permission; the material backdrop still renders transparent, which is
`peek`'s documented limitation and not a rendering bug.

### What the loopback looks like, which is why the sheet says so

Registering this Mac and peeking the roster: **every session appears
twice**, under `local` and under `studio` — they are the same daemon. That
is exactly what makes it useful for testing the remote path, and exactly
what would baffle someone who clicked Add without knowing, so the row for
this Mac says it in the sheet before you click.

`hosts.json` was left as it was found (`local` alone); the loopback was
added, measured, and removed.

### Measured

`ccc hosts add studio` then `ccc hosts check`: local 157 ms, studio
648 ms with the model column intact. The picker's Add is that same call.

6 tests on `HostSetup` — the refusals and what gets written, which is the
half that needs no reachable Mac. 367 total.

## v10 slice 1 — the banner had one word of payload (2026-09-04)

The roster is thin by design and the notification inherited that
thinness. What ccc posted for a blocked session was
`"<name> is waiting"` over `"on studio"` over `"Click to attach"`:
**three constants and a name.** Everything that notifies is waiting,
there is one hop so the host has one value, and the click has attached
since v3. Strip what never varies and the whole banner is the session's
name.

### What the daemon already had

`~/.claude/jobs/<id>/state.json` — the file `DraftProbe` has been opening
since v5 for one boolean. Counted across the 20 jobs on studio:

- `detail` in **20 of 20**, and its meaning shifts with the state:
  `working` → the live activity, `blocked` → the question, `done` → the
  result. Watched live, one session read `"PR #50 ready to merge;
  awaiting go-ahead"`, then `"Reading the MIME table"` ten minutes later.
- `output.result` on every finished job, 20–460 chars, **equal to
  `detail` in 12 of 15** and longer in the other 3 (a stale progress
  line left behind), which is why the result wins for `done`.
- `children` in 14 of 20 — pull requests and published artifacts, with
  kind and title.
- `needs` and `suggestedReply` on the blocked one.

The finding that settles it: the single session the roster showed as
`blocked` carried **no `waitingFor` at all**, while its job file held
both the question and a proposed answer. `waitingFor` is documented, and
absent exactly when it is wanted.

### The join

`JobProbe` + `JobInfo`, the same shape as the model and worktree joins:
local rows only, cached on the file's (size, mtime), carried across the
hop on the row so an older ccc on the far side simply sends no `job`
key. It **subsumes** the read `DraftProbe` was making for itself, so
`state.json` is opened once per row rather than twice.

`ccc list --json` on studio: **19 of 19 rows carry a job.**

### What it costs, measured before it was believed

28 job directories (19 with a readable file, 9 without). Cold, every
file read: **5.19 ms**. Warm, one `stat` per row: **0.218 ms** mean over
50 passes. Against the running build's `roster poll mean 201 ms` and
`model join mean 20 ms` over 2,490 ticks, the steady state is **~0.1% of
a tick**, and the worst case — every job file changing at once — is
bounded at the cold number. Reported by `ccc stats` as `job join` with
its cached share, because a join that runs for every local row on every
tick has to be a number and not an intuition.

The join has no wall time of its own: `model join`'s `lastMs` already
times the whole detached block, this included. The counters are what it
adds.

### The shape that won

Mocked at true banner width over four real sessions before any of it was
written (the artifact is spent; the argument is here). Three candidates:
name-then-payload, payload-as-title, and typed-by-state. Payload-as-title
lost on a fact — a 460-char result has no natural 44-character headline,
so *we* would have to cut it, and macOS clamps to two lines and gives the
rest back on hover for free. So: **put the whole string in the body and
let macOS truncate.**

Typed-by-state lost as a *shape* and won as a *line*: the receipt
(`#4916 · #4917 · Life After Carto`) changes what you do next, so it is
a subtitle that appears when `children` is non-empty, not a second code
path.

The branch was considered and cut. It does not move the decision a
banner asks you to make, it is present in 11 of 20, and about half of
those repeat what the name already said (`cdn` →
`worktree-cdn-global-purge`). It belongs in the roster row, where it
already is.

### Two details that only show up at real width

The **host goes last**. A macOS title clips near 36 characters and
`✋ studio · linear cuanto bill project` is 37 — leading with the host
feeds the ellipsis the one token that identifies the session. It is also
drawn only when more than one host is answering, which the poller knows.

The **fragment gets an ellipsis**. The daemon's extraction is ragged: the
live blocked question began `"prod), and do you want fake captures…"`.
`looksClipped` is structural — a first character that cannot open a
sentence — and prefixes `…` so it reads as deliberate. Shown as written,
never parsed (the boundary rule).

### Measured

15 tests on `JobProbe`, the composition, and the wire, including the
lenient cases (a wrong type is a dropped field, a numeric PR id, a file
with nothing usable is no reading at all) and that the draft reading
**agrees with its older self** now that it rides the parsed file. 382
total, from 367.

`ccc watch` gained the same payload and now prints `event.mark`, so the
banner and the log line cannot disagree about a symbol — its blocked
mark moves from `⏸` to `✋`, which is the roster header's own vocabulary.

## v10 slice 2 — the row says what the session is doing (2026-09-04)

Slice 1 put the daemon's sentence on every local row and spent it on the
banner. The field with the most in it never reached a banner at all:
`detail` narrates a **working** session, and working is the one state
ccc never notifies on. So the roster row is its only home, and the row
had been naming everything about a session except what it was doing.

`SessionRow.say` is the join's reading for whatever state the roster
reports — the same string the banner carries, so a row and its
notification cannot disagree. A third line under the name in the window;
an indented `↳` line under the columns in `ccc list`, because the row
above is a grid and a 460-character sentence would destroy it. A
**draft** says nothing: its `needs` is the harness's own "send a prompt
to start", which the row already tells you by being a draft.

Live, on this Mac:

```
  f229e968  blocked  wait  ccc-blocked-fixture  haiku-4-5  ~/code/fun/ccc ⎇ worktree-v2 ↑1
            ↳ answer: Should the banner show the branch? (Yes, show it · No, keep it in the roster)
  3369359f  working  busy  linear cuanto bill   opus-5     ~/code/work/cuanto ⎇ ramon/carto-basemaps-key
            ↳ implementing Basemap config; removing maps-sandbox; typechecking
```

### Two things a real session caught that a mock could not

Both found by spawning a haiku fixture that blocks on `AskUserQuestion`
and reading what `ccc watch --json` actually emitted.

**`waitingFor` is sometimes a placeholder, and slice 1 preferred it.**
The fixture answered `waitingFor: "input needed"` while its job file
held `"answer: Should the banner show the branch? (Yes, show it · No,
keep it in the roster)"`. The rule was "the roster's own word wins";
it now reads the other way — the job file wins, `waitingFor` is the
fallback for a session with no job file. Nothing at the boundary
distinguishes a `waitingFor` sentence from a `waitingFor` placeholder,
so it cannot be trusted first. Same reason both the row and `ccc list`
now suppress `⏸ input needed` when a real sentence follows it: printing
a placeholder directly above the question is the redundancy this whole
version deletes.

**`looksClipped` was a lowercase test, and lowercase is the normal
register.** It fired on the fixture's `"answer: Should…"`, and would
have fired on most honest `detail` lines — `"wiki: TCC identity fix
scoped"`, `"detour arithmetic verified; awaiting capture"`. Replaced
with the structural signal: **a closing bracket with no opener**, which
is exactly what a lost prefix leaves behind (`"prod), and do you
want…"`). Only an unmatched *closer* counts — an unmatched opener means
the tail was cut, which is macOS's job — and only over the first 80
characters, so a stray bracket deep in a long result cannot trip it.

The general lesson, which is why this is written down: the mock proved
the *shape* and could not have found either of these, because both are
facts about what the daemon emits rather than about what fits on a line.

### Measured

384 tests, from 382. The fixtures (`ccc-banner-fixture`,
`ccc-blocked-fixture`) were haiku, per the standing rule that a fixture
session for a proof is not worth a frontier model, and were stopped
after they answered.

A `done` fixture that finished inside one poll interval produced **no**
event, correctly: a new row that arrives already terminal is history,
not news (`TransitionDetector`'s own rule). Proving the banner needs a
session that *stays* in the state — which is what the blocked one does.

### Cut

**v0.1.17, build 139**, notarized and published to the feed the same day:
`spctl` accepted as Notarized Developer ID, one `<item>` in the appcast,
and the live check agreed with the zip at 5,068,153 bytes. Studio was
moved onto the released bytes with `scripts/install --dist`, and the
first ticks of the new join reported themselves:

```
model join   last 8 ms  mean 107 ms  reads 19  cached 32  gone 0
job join     reads 20  cached 37  none 0  65% cached
```

65% is three ticks in, not the steady state — the cached share climbs as
terminal sessions stop changing, which is the whole reason the cache is
keyed on (size, mtime).

## v11 slice 1 — the window comes back where you left it (2026-09-04)

Every launch — cold, ⌘Q and back, a Sparkle update — put the window at
the screen's bottom-left corner at 1280×800. `MainWindowController` had
called `setFrameAutosaveName("ccc.main")` since v0 and the defaults
domain had never held the key:

```
$ defaults read com.ramonfabrega.ccc | grep -c 'NSWindow Frame'
0
```

**`NSWindowController(window:)` clears `frameAutosaveName`.** Probed
directly, app-less, before touching the app:

```
set ok: true name: t.probe
after controller:  cascade: true ctrlName:
```

The name was set on line 36 and erased on line 39, so nothing ever
saved and the restored frame was the `contentRect` literal — origin
(0,0), which AppKit measures up from the bottom.

The order is the whole fix: hand the window to the controller first,
then turn cascading off, restore, and register the save. `setFrameUsingName`
is not optional — the autosave name registers the *write*, it does not
read — and its `false` is what says "first launch", which is the only
time the window is centred. Both orders, run twice each against a
scratch defaults domain, with a drag between the runs:

```
old run 1: name=(none)    frame=(300, 200, 1000, 600)  saved=(nothing)
old run 2: name=(none)    frame=(0, 0, 1280, 832)      saved=(nothing)
new run 1: name=probe.new frame=(300, 200, 1000, 600)  saved=300 200 1000 600 0 0 1920 1050
new run 2: name=probe.new frame=(300, 200, 1000, 600)  saved=300 200 1000 600 0 0 1920 1050
```

The saved string carries the screen it was saved on, which is why the
restore is AppKit's and not ours: a frame saved on a display that is
gone comes back constrained to a display that is here.

### The twin

`ccc geometry` reported the window's size and not where it was, so the
one question this slice answers had no command that could ask it.
`WindowGeometry` now carries `x`/`y`, top-left down in the global space
`screencapture -R` takes — the space the pane rect was already in, not
AppKit's bottom-left up:

```
window 8864  120,64  1280x800pt  @2.0x
```

Quit, relaunch, run it again, compare: that is the check, and it needs
no screen and no permission.

### Measured

384 tests, unchanged in count — `geometryCrossesTheWire` grew the origin
assertion rather than gaining a neighbour, since the wire either carries
the frame or does not.

## v11 slice 2 — every window gesture has a verb (2026-09-04)

Slice 1 gave `ccc geometry` an x and a y so the restored frame could be
checked. That exposed the real gap: **the window was the one surface where
the parity rule had been half-kept.** The title bar had seven gestures and
the socket had three verbs, so the gesture whose persistence slice 1 fixed
— the drag — was one an agent could not perform.

| gesture | verb |
| --- | --- |
| drag the title bar | `ccc window move X Y` |
| drag the corner | `ccc window resize W H` |
| both at once | `ccc window frame X Y W H` |
| the yellow button | `ccc window minimize` |
| the green button | `ccc window zoom` |
| its other reading | `ccc window fullscreen` |
| drag the roster's divider | `ccc window split W` |
| — | `ccc window center` |

`center` is the one that ran the other way: the command wanted to exist —
it is the way back from a window restored onto a display that is gone —
so the **menu** gained it, along with Zoom and Enter Full Screen, which
were commands with no menu item. The rule reads in both directions.

### The verb list was in three places, so it became a type

`WindowAction` in CCCKit is now the only definition: the CLI parses with
it, the socket carries its `text`, the window switches over it
**exhaustively** — a new gesture stops compiling until the window answers
it — and the refusal an unknown verb gets is generated from its grammar.
Adding a case adds the verb, its arity, its usage line and its error, in
one edit. Seven of the twelve tests in `WindowActionTests` exist because
`move 100` must be a typo rather than a shorter gesture.

Coordinates are the one thing the two faces could disagree about, so the
flip lives in `WindowGeometry` (`topLeftY`/`appKitY`) with a test that
composes them: AppKit measures up from the primary screen's bottom-left,
everything on this socket measures down from its top-left. A `geometry`
read pastes straight into a `move`.

### What the numbers would not say

`ccc geometry` answered with a frame for a window nobody could see. It
now carries `visible`, `minimized`, `zoomed`, `fullScreen` and the
roster's width, and the text form prints the state only when it is not
the ordinary one:

```
window 9141  320,93  1280x800pt  @1.0x  hidden minimized
window 9141  0,30  1920x1050pt  @1.0x  zoomed
window 9141  0,0  1920x1080pt  @1.0x  full screen
roster 480pt wide
```

### A squeeze is not a preference

The roster's divider was set to 420 on every launch, so a drag on it
survived exactly as long as the process. Remembering it took one line and
then took three tries, because the obvious hook is wrong:

- `splitViewDidResizeSubviews` fires for a **window** resize too.
  `ccc window resize 900 600` pins the roster at its 320pt minimum, and
  saving that made one narrow window permanent — measured, it wrote 320,
  then 351.
- `NSSplitViewDividerIndex` in the notification's user info does not
  separate them: since macOS 12 it is there for resize and layout passes
  as well (AppKit's own header says so).
- Comparing the split's own width across passes does not either: a
  resize posts several, and one of them has the width the pass before it
  settled on.

`splitView(_:constrainSplitPosition:ofSubviewAt:)` is called **only while
a divider is being dragged**, so it does not have to separate anything.
It is also on the path `setPosition` takes — instrumented, the launch's
restore and `ccc window split 500` both came through it — which is what
made the drag hook verifiable without a hand on the mouse, and what made
one more flag necessary: restoring is not choosing, or the first launch
would write the default back as a preference and a later default would
reach nobody.

### Measured

391 tests, from 384. Driven against a real window the whole way: a second
instance on its own socket (`CCC_CONTROL_SOCKET`), which an unbundled
binary keeps out of the installed app's defaults domain by having none of
its own — the dev domain is plain `ccc`.

```
first launch  window 9141  320,93  1280x800pt   roster 420pt   (centred; nothing saved)
              window frame 200 120 1100 700 → window split 480 → window move 250 150
quit          "NSWindow Frame ccc.main" = "250 230 1100 700 0 0 1920 1050"
              "ccc.rosterWidth" = 480
relaunch      window 9204  250,150  1100x700pt  roster 480pt
```

The window resize between them left `ccc.rosterWidth` at 480 while the
roster was on screen at 351: the preference outlived the squeeze, which
is the whole point of the third try.

## v11 slice 3 — the PR half of the receipt (2026-09-04)

v10 slice 1 gave the banner a receipt line: what came out of the session,
drawn from the job file's `children`. Two nights later a real banner read

```
✓ lore · studio
#1 · #2 · #3 · #73 +43
proposal logged as dated subsection under Proposals from lore; …
```

and the question was whether those four PRs were open. **None of them
were.** lore#1 and lore#2 merged on 2026-07-17, lore#3 was *closed
unmerged*, mux#73 merged the same day — seven weeks before the banner drew
them.

### `children` is an archive, not a receipt

The daemon appends to `children` for the life of the **job**, never
prunes, and stamps nothing. That `lore` job was created 2026-07-17 and
carried 47 entries across five repositories. `JobInfo.receipt` took
`prefix(4)` — the *oldest* four.

### The PR half, measured

Every PR ccc has ever had available to draw: 171 unique, across the 11
jobs whose `children` carry one, resolved in one GraphQL round trip and
replayed against each job file's mtime, which is when its banner fired.

```
$ python3 collect.py                     # 171 PRs out of ~/.claude/jobs/*/state.json
$ gh api graphql -F query=@q.graphql      # number, state, createdAt, mergedAt, closedAt
$ python3 refine.py
prefix4 (shipped)    open when drawn  7/28 (25%)   median age  11.2d   max  87.7d
suffix4 (proposed)   open when drawn  6/28 (21%)   median age   2.0d   max  15.2d

all 171:  MERGED 143 (84%)   CLOSED 14 (8%)   OPEN 14 (8%)
```

**Recency was not the fix**, which is the number that settled it. Taking
the newest four instead of the oldest four moves the age (11.2d → 2.0d)
and leaves the point untouched: three quarters of the slots still name
something already landed. The cause is structural — a background session
usually finishes *by* landing the thing, so `done` fires after the merge,
not before. The best case in the set proves it rather than escaping it:
`debug cuanto` drew `#4916 · #4917`, merged 25 and 4 minutes earlier.

### And the token was never an address

`children` spans repositories, so the number alone does not identify a PR.

```
centaur cuanto   drew  #1 · #1 · #2 · #3   — 4 PRs in 3 repos
lore             drew  #1 · #2 · #3 · #73  — spans lore, mux, disk, dotfiles, osrs
```

### Where a PR is the deliverable, the sentence already names it

Of the 11 jobs, 5 name a PR in the daemon's own line — and those 5 are
exactly the ones where the PR *was* the work. The other 6 are stopped
sessions, a docs proposal, a diagnosis. The sentence carries the context
the number cannot:

```
YES annotate    PR #4899 reshaped from 183 to 62 files — position move reverted…
YES sentry      Sentry stack delivered as 3 stacked draft PRs — #4876 params scrub…
no  lore        proposal logged as dated subsection under Proposals from lore…
```

So the number goes and the line below keeps it. `ccc watch` made the same
case on its own: its test is named `theWatchLineSaysEachThingOnce` and its
expectation had been

```
debug cuanto finished — …shipped as PRs #4917 and #4916.  [#4916 · #4917 · Life After Carto]
```

### What is left is the artifact

A title, not a number: it never merges, never closes, and reads without a
lookup. 20 of the 191 children are frames. Over the live job files:

```
lore          was  #1 · #2 · #3 · #73 +43
              now  Panamá — Mapa de Fuentes de Gasto Público · RuneLite Recon · lore · … +10
debug cuanto  was  #4916 · #4917 · Life After Carto
              now  Life After Carto
annotate      was  #4899
              now  (no receipt line at all)
```

Six of ten banners keep a receipt; four lose the line entirely, which is
CLAUDE.md's rule about a line carrying payload or not being drawn.

### Left open

**The frame half has the same lifetime problem, minus the harm.** `lore`'s
new line is four artifacts from July under a sentence about tonight's wiki
proposal, and `+10` is still a lifetime count. An artifact link never goes
stale the way a PR does — it stays openable and stays true — so this is
width and relevance, not correctness. `suffix(4)` is the one-word answer
whenever it is worth taking; it was not folded in here because dropping a
kind and re-ordering the rest are two decisions, and only the first was
asked for. **Closed the same night by slice 4, which measured how often
*any* of it is this run's work and deleted the line.**

### Measured

393 tests, from 391. The 171-PR resolution ran once, out of band, and
**nothing in ccc calls `gh`**: liveness was considered and rejected — a
network call per notification, and 8% of the corpus is open, so even a
correct liveness check would draw nothing three times in four.

## v11 slice 4 — a banner is a title and a sentence (2026-09-04)

Slice 3 dropped the PR numbers and left the artifacts, on the reasoning
that a title never merges and never closes. It does not — but it does
something the PR number also did, which slice 3 measured for one kind and
not the other: **it stays on the banner long after the run that made it.**

The receipt only changes when the job publishes something new. Every
banner between one artifact and the next repeats the last one. So the
question is not "is this title accurate" but "how often is it *this run's
work*", and the index can count the denominator.

### Fresh at most 6%

`lore jobs --json` gives sessions per job; the job file gives artifacts.

```
job         sessions   artifacts   fresh
attrition        202           1      0%
ccc               24           3     12%
lore              68          14     21%
total            294          18     ≤6%
```

`attrition` is the pure case: one artifact, 202 sessions, so "Attrition
Atlas" would ride on effectively every banner that job ever posts. And 6%
is an **upper** bound — a session blocks and finishes several times, and
each posts a banner, so the true rate is lower still.

### The slot was wrong too

The receipt went to `content.subtitle`, which macOS gives **one hard-
truncated line**; `content.body` gets two and the rest back on hover.
Half the receipt lines overran it, and `suffix(4)` did not help:

```
lore        90 chars  CUT      storefront  60 chars  CUT
ccc         57 chars  CUT      migrate     55 chars  CUT
polish      21 chars  fits     attrition   15 chars  fits
```

Naming only the newest fixed the width — all eight titles fit, longest 39
— and moved the freshness number not at all, which is what settled it.

### The one argument for keeping it, and why it loses

Unlike the PR number, the sentence does *not* already carry the artifact:
of 8 jobs with one, only `polish` names it ("Published a verification
board artifact (https://…)"). So deleting the line does lose something
real — on 6% of banners, a name you cannot click.

The fix that would work is the run-delta: hold each job's link count when
it enters `working`, draw only what appeared since. It is ~20 lines and
correct every time. It is **not built**, because its own measurement says
it would draw an empty line on nineteen banners in twenty. That is a
reason to wait for the itch, not to pre-empt it: the artifact is in the
pane, `ccc links` and ⌘-click open it, and the banner simply stops being
where it is announced.

### What is left

`blocked` banners never had a receipt — v10 ruled that mid-question is
not the moment to list what came out. Slice 4 deletes the exception
rather than the rule, so every banner is now the same two lines:

```
✋ ccc · studio
delete the receipt line, or implement run-delta tracking?
```

`children` left the type entirely rather than sitting decoded and unread;
`state.json` is on disk and one `JSONSerialization` away if the delta
ever earns itself. `ccc watch` lost the same bracket in the same commit —
one definition, many surfaces — and its test had been the tell all along,
`theWatchLineSaysEachThingOnce` expecting a line that said #4916 twice.

### Measured

388 tests, from 393: the five that went were the receipt's own.

### Cut

**v0.1.18, build 145**, notarized and published the same night: `spctl`
accepted as Notarized Developer ID, one `<item>` in the appcast, and the
live check agreed with the zip at 5,070,405 bytes. Studio moved onto the
released bytes with `scripts/install --dist` — `ccc 0.1.18 (145)`, no
`dev` marker — and `ota verify --feed ccc` answered `ok`.

The job join, on the cut that removed its only remaining reader:

```
roster poll  last 230 ms  mean 186 ms  n=14
model join   last 9 ms  mean 19 ms  reads 23  cached 201  gone 0
job join     reads 19  cached 233  none 0  92% cached
```

**92%, against the 65% recorded at the v0.1.17 cut** — which is the claim
that entry made ("65% is three ticks in, not the steady state; the cached
share climbs as terminal sessions stop changing") arriving as a
measurement one release later. The join now costs one `stat` nine ticks
in ten, which is the whole reason it is keyed on (size, mtime).

The join itself stays, and is not now doing nothing: `detail`, `needs`,
`output.result` and `suggestedReply` are what the banner and the roster
row say. Only `children` left.

## item 6 — the lid: there is no overnight sleep (2026-09-04)

`scripts/lidtest` on air, its own ControlPath, 2 s interval, lid closed
from 03:32 to 10:03 (air's clock). **2,112 polls, 18 wakes, 38 non-zero.**
`ccc stats` on air for the other half, and a 60 s sampler on studio
(`~/lidtest-studio.log`) counting what air left behind.

### The premise was wrong: a closed lid is not a sleep

The item asked what an overnight sleep does to the master. **Air never
slept overnight.** It woke 18 times, and eleven of the gaps sit between
14m59s and 16m53s:

```
9m19s  15m00s  14m59s  15m00s  15m00s  15m49s   4m15s  10m01s    25s
16m47s 15m04s  16m42s   2m02s  15m31s  15m10s  10m45s  16m53s   4m45s
```

That is macOS dark wake on a ~15 minute cadence. **The longest sleep the
master ever has to survive is about fifteen minutes**, and the eight-hour
case being designed around does not exist. Every question below is
therefore asked 18 times a night, not once.

### The wedged shape is the everyday wake

§4b closed with "the wedged shape has not been seen in reality yet."
**It is now the normal case.** Seventeen of the eighteen wakes open with
the identical three lines:

```
2026-09-04T07:04:17    5048ms  rc=255  muxclient: master hello exchange failed
2026-09-04T07:04:24    5022ms  rc=255  ssh: connect to host studio port 22: Operation timed out
2026-09-04T07:04:31    3648ms  rc=0
2026-09-04T07:04:37     680ms  rc=0
```

The first failure is the wedged master: socket present, process present,
handshake dead. It cost **5041–5613 ms** on all seventeen — `ConnectTimeout`
bounding it, as §4b found.

**The prediction going in was wrong, and wrong in both directions.**
`ControlPersist=60` was expected to reap an idle master long before
morning, making the wake look like §4b's `kill -9` row (a fresh master,
~316 ms). It reaps nothing: ControlPersist is a **client**-side timer and
the client is frozen, so the socket outlives the connection it names and
comes back wedged rather than either surviving or dying.

### What eviction can and cannot buy

The second failure is the one that matters for the fix. After the wedged
master fails, ssh falls back to a **direct** connection — and that times
out too, `Operation timed out`, another 5 s, twice on three of the wakes.
That is not the master's fault and no eviction can prevent it: **the
tailnet has not come back yet.**

```
first rc=0 after wake   14–22 s        (two failures, sometimes three)
that poll               1706–4239 ms
the next poll           429–908 ms     healthy
```

So eviction-on-degraded-poll is **not the insurance §4b called it** — it is
the main path, and `ccc stats` counted `evictions 23` across the 18 wakes.
But it buys the second 5 s and not the first: a wake costs ~10 s of dead
network no matter how clean the client is. **A wake is 14–22 s of "no" and
then it is fine.**

### The one that survived, and where the boundary is

The 25-second gap is the exception that places the edge:

```
2026-09-04T06:28:52  WOKE   gap 25s
2026-09-04T06:28:52    8569ms  rc=0        ← alive, slow, never failed
```

No `rc=255` at all — the master survived and paid 8.6 s. §4b's **1 min 54 s**
lid survived the same way. The shortest gap that came back *wedged* was
**4m15s**. So the master is alive-but-slow under ~2 minutes and wedged past
~4, and the everyday 15-minute cadence is entirely on the wedged side.

### One poll that nothing bounded

```
2026-09-04T05:23:23   30008ms  rc=-1  timed out after 30 s
```

§4b's correction was that `ConnectTimeout` **does** bound the mux wait.
Once in 2,112 polls it did not, and lidtest's own 30 s cap is what ended
it. One in two thousand, recorded rather than explained.

### The eviction storm drains; it does not leak

Watching from studio the night began at **11 established connections from
air**, created inside a ~60 s window as the lid closed — one orphaned
master per evicted tick, since `evictControlMaster()` unlinks the socket
and deliberately never runs `ssh -O exit`. That looked like a nightly leak
onto the always-on Mac. **It is not.** They drained on the following
wakes and were back to one within ~35 minutes, and one is the steady state
for the rest of the night:

```
03:32  established=11      04:07  established=1
03:36  established=7       04:25  established=0
03:52  established=3       (1 for the next three hours)
```

The zombies are half-open sockets that only the far side can retire, and
air waking is what retires them.

### air's poll is saturated, and the clocks disagree

Two things the night showed that it was not asked:

```
studio  last 2046 ms  mean 1354 ms  n=2662  rows 18  evictions 23
```

**The remote poll costs about one whole tick.** Against a 2 s interval and
lidtest's 429–908 ms for the raw `claude agents` call, air's poll is the
far side's ccc doing the transcript join as well — so air's roster is
always ~2 s stale and the poller never idles. It sits under
`degradedThreshold` (3 s) and so never self-evicts on that basis, with
about a second of headroom.

And air's clock reads **one hour ahead of studio's**, so the two logs of
the same night do not line up until one is shifted. `scripts/lidtest`
stamps local time with no offset, which is what made it invisible; the
correlation above is with air −1h.

## v0.1.19 and v0.1.20 — the wake window, cut twice (2026-09-04)

**v0.1.19, build 151**, notarized and published: `spctl` accepted as
Notarized Developer ID, one `<item>` in the appcast, the live check agreed
with the zip at 5,075,312 bytes. It carried the widened reattach window
(20 s → 60) and `ccc stats`' `wake` line.

**And it was wrong on the line it existed for.** Run on studio with
nothing attached, one `ccc hosts reconnect` produced

```
wake    1 wakes  reattach attempts 0  ⚠ no reattach ever fired — ssh did not notice a pane die across a wake
```

`attempts == 0` is true of every wake on a Mac with no pane, which is the
everyday case — so the warning fired at the absence of a bug. Caught by
running the thing rather than by reading it, on a build already published.

**v0.1.20, build 152**, same night, 5,076,486 bytes, feed `ok`. The gate is
`withRemotePane`, counted at the wake: only a wake with a remote ref in
play could have produced a reattach, so only those make silence a finding.
Verified on the failing case — `ccc hosts reconnect`, nothing attached,
`wake 1 wakes  reattach attempts 0`, no warning.

The field is optional for a reason that is not the usual convention:
**v0.1.19 is published and sends `WakeStats` without this key**, so a
0.1.20 `ccc stats` meets a 0.1.19 server that has every other field and not
this one. Non-optional would fail the whole `StatsInfo` decode rather than
one field. `wakeStatsFromV0119StillDecode` pins it by name.

Studio moved onto the released bytes with `scripts/install --dist` —
`ccc 0.1.20 (152)`, no `dev` marker.

### The release notes have drifted, and the flow is prose

Surveyed at the same time, since two cuts in one night made it visible.
RELEASES.md step 4 names one command — `gh release create <tag> <zip>
--generate-notes` — which titles the release with the bare tag and writes
a compare link as the body. **14 of 16 releases match it. Two do not:**
`v0.1.11` and `v0.1.19` carry a hand-written `ccc vX.Y.Z` title and prose
notes, each written by a session that had the doc open.

That is the same failure `DocsGuardTests` was built for and says out loud:
*a rule that is only prose is a rule a tired afternoon defeats.* Step 4 was
prose, and it had been defeated twice.

**Fixed the same day.** `scripts/release-notes <tag>` prints this repo's
commit subjects for the range plus a compare link, and `scripts/package`
creates the Release itself as its last act — so the flow is one command and
the seam that drifted is gone. `--generate-notes` went with it on its
merits, not only for consistency: it builds from merged pull requests, and
a repo where everything lands by fast-forward has none, so it wrote a
compare link and nothing else sixteen times. Skipped for `--ad-hoc` and
`--no-publish`, which are not releases; re-runnable, since a cut that fails
after the upload should not need the Release deleted by hand.

All 20 existing Releases were normalized through the same command
(`gh release edit <tag> --title <tag> --notes "$(scripts/release-notes
<tag>)"`), which is the point of it being a command: one definition, and
the back-fill and the next cut cannot disagree.

## v12 slice 1 — the shell pane says how to close it (2026-09-04)

The question was "how does one close the integrated terminal? currently
there's no way to close it after it's open, right?" — asked by the person
who has been driving this app all week. It had three ways: ⇧⌘T, `exit` in
the shell, and `ccc shell --close`. **A verb that the daily driver cannot
find is a verb that is not there**, so the gap was never the mechanism.

Counted, the surfaces were lopsided:

| | open | close |
| --- | --- | --- |
| row's context menu | Open in Terminal (+ at Repository) | — |
| the row's key | `t` | — |
| menu bar | ⌘T, ⌥⌘T | ⇧⌘T |
| the shell itself | — | `exit` |
| socket | `ccc shell <ref> [--repo]` | `ccc shell --close` |

Three of the five ways in, and one of them, are on the row. The one way
out that a mouse can reach was in a menu the mouse never opens for this —
and ⇧⌘T's only appearance in any sentence was inside the two **refusals**
("the shell in X is running something; ⇧⌘T closes it"). The shortcut was
advertised exactly when something had gone wrong and never on the open
that raises the question.

### The row's item is a toggle

`PaneController.shellIsOpen(ref, atRepo:)` is `openShell`'s own
"already open" test — same host, same folder, one `shellFolder` rule
shared by both so the item and the sentence cannot drift. When it answers
true the row's item reads **Close Terminal**; `t` follows it, because `t`
*is* that item's key. The menu bar keeps the two verbs apart: ⌘T opens or
focuses, ⇧⌘T closes from anywhere — including from inside the shell,
which is the case the row cannot serve.

One shell at a time makes this exclusive across the whole roster: at most
one row, and at most one of its two items, is ever the close. The
repository item defers to the plain one when a session was opened *in* its
main checkout and the two name the same path, so the close is offered once.

The item is built when the menu opens — the same lazy evaluation the mute
mark four lines below it has relied on since v3 slice 2, which is why no
observable object was needed for this.

### And the open now names the way out

```
$ ccc shell d079be9f
shell in ~/code/work/cuanto/.claude/worktrees/pending-auths-search — ⇧⌘T closes it
$ ccc shell d079be9f
the shell pane is already open, in ~/code/work/cuanto/.claude/worktrees/pending-auths-search
$ ccc shell --close
shell closed
$ ccc shell --close
ccc: no shell pane is open
```

One sentence, both faces: the window's notice and the socket's reply are
the same string, so the CLI transcript above is the notice's text.

**Not photographed.** The notice HUD and the flipped menu item were not
captured on screen: `ccc capture` refused again for want of Screen
Recording ("could not create image from window; window 9316"), and System
Events timed out for want of Accessibility — the same two permissions the
queue already records as missing from these sessions. `ccc peek` needs
neither and confirmed the shell pane mounts and unmounts, but it composites
the window alone: a context menu is its own window, and the socket path
never raises the HUD (that is `MainWindowController.openShell`, the
window's gesture). The strings are shared with the CLI, which is what the
transcript above stands in for.

### Cut as v0.1.21

Build 156, 5,079,362 bytes, notarized and published to both CDN keys; the
live feed's `length=` matched the zip's real content-length, which is what
`scripts/package` exits non-zero on. First cut whose GitHub Release is that
script's own last act rather than a step in prose. `scripts/install --dist`
put it on studio, and the released bytes answer with the new sentence:

```
$ ccc version
ccc 0.1.21 (156)  /Users/rf-studio/Applications/ccc.app
$ ccc shell d079be9f
shell in ~/code/work/cuanto/.claude/worktrees/pending-auths-search — ⇧⌘T closes it
```

## the picker's error names a character, not a cause (2026-09-04)

Reported from air, on v0.1.21: **Add Mac** opened and showed, in place of
the tailnet,

```
dataCorrupted(Swift.DecodingError.Context(codingPath: [], debugDescription:
"The given data was not valid JSON.", underlyingError: Optional(Error
Domain=NSCocoaErrorDomain Code=3840 "Unexpected character 'T' around line 1,
column 1." …)))
```

Nothing was being added and nothing was saved — the sheet never got as far
as a list. The scan is what failed: `AddHostModel.scan` shows `"\(error)"`
whole, and the error came from `Tailnet.scan` handing a decoder something
that is not JSON. So the sentence is honest about *where* it broke and says
nothing about *why*, which is the bug.

**Why the cause could not be recovered from that string.** Two throws away:

- `standardError = FileHandle.nullDevice` — a binary that will not answer
  usually explains itself on stderr, and ccc sent that to `/dev/null`.
- `peers(from:)` takes `Data`, so by the time decoding fails there is no
  binary path and no memory of the bytes; `DecodingError` describes the
  parser's position and nothing else.

What is known from the string alone: whichever of the three `candidates`
air has, it **exited 0** (`scan` throws `Unreachable` otherwise) and wrote
something starting with `T` at column 1 — a sentence, on stdout, in place
of a status. Studio's `/usr/local/bin/tailscale` is a two-line shim onto
`/Applications/Tailscale.app/Contents/MacOS/Tailscale` and answers JSON;
air's is a different install, and which one is exactly what the old message
could not say.

**The fix is the diagnostic.** `Tailnet.Unreadable` carries the binary and
the first line it printed, stderr is read instead of discarded, and a
non-zero exit quotes its reason too:

```
`/Applications/Tailscale.app/Contents/MacOS/Tailscale status --json` answered
something that is not JSON: Tailscale is stopped.
```

One definition, two surfaces: `ccc hosts discover` prints `ccc: \(error)`
and the sheet shows the same string, so the CLI on air now reports the same
sentence the picker does.

**Run, not described.** `Tailnet.scan(binary:)` is the same read against a
named path, so three tests drive real subprocesses: a stub that prints a
sentence and exits 0 (air's shape) must surface the sentence; a stub that
exits 1 talking on stderr must surface *that* line and `exited 1`; and a
stub that `cat`s the captured `status --json` must still return the two
Macs. 399 tests pass. Studio's real binary, through the twin, is unchanged:

```
$ ccc hosts discover
air     air.bengal-barb.ts.net  Ramon’s MacBook Air
studio  studio.bengal-barb.ts.net  Ramon’s Mac Studio  this Mac
```

### The cause: the binary asks whether a shell launched it

Air answered the open question, and it was not the install:

```
air ❯ which tailscale
/opt/homebrew/bin/tailscale
air ❯ ls -l /usr/local/bin/tailscale
ls: /usr/local/bin/tailscale: No such file or directory
air ❯ /Applications/Tailscale.app/Contents/MacOS/Tailscale status --json | head -c 60
{
  "Version": "1.98.9-t4fb758c39-g200941d74",
```

The same binary, byte-for-byte the one studio has (9,826,288 bytes), and it
answers JSON. So the failure was not tailscale's state and not the install —
it was **who was asking**. Bisected on studio, against the same binary:

```
$ env -i        …/Tailscale status --json   →  The Tailscale GUI failed to start: …  exit 0
$ env -i TERM=dumb  …                       →  {"Version": …
$ env -i SHLVL=0    …                       →  {"Version": …
$ env -i TERM=      …                       →  The Tailscale GUI failed to start: …
$ env -i FOO=bar    …                       →  The Tailscale GUI failed to start: …
$ env -i HOME=… USER=… LOGNAME=… SHELL=… PATH=… TMPDIR=…  →  The GUI line
$ env -i HOME=… USER=… PATH=… TERM=xterm    →  {"Version": …
```

The macOS bundle is the GUI **and** the CLI in one binary, and it decides
which one it is by smelling for a shell: with neither `TERM` nor `SHLVL` set
it concludes it was double-clicked, tries to raise the GUI, and reports the
failure as *"The Tailscale GUI failed to start: The operation couldn't be
completed. (Tailscale.CLIError error 3.)"* — **on stdout, exit 0**. Either
variable alone flips it back; an empty `TERM=` reads as absent; six plausible
shell variables together do nothing. That sentence is the `T` at column 1.

**Why only air, and why only the app.** A GUI process has no `TERM` and no
`SHLVL`, so `ccc hosts discover` in a terminal could never reproduce what
ccc.app hit — the twins disagreed because the environments did, which is the
one way two surfaces of one definition can still diverge. And studio was
immune by accident: it has `/usr/local/bin/tailscale`, the two-line
`#!/bin/sh exec …` shim Tailscale's *Install CLI* writes, and `sh` exports
`SHLVL` on its way through. Air never ran that installer, so ccc reached the
bundle directly. The candidate list's first entry was a shell script, and
that is the whole reason this looked like an air-only bug.

**The fix:** `Tailnet.shellish` supplies both variables — `TERM` from
CLAUDE.md's `xterm-256color`, never `dumb` (the one value a program is
entitled to read as *there is no terminal*), and `SHLVL=1` — inheriting the
rest of the environment whole and never overwriting a real terminal's answer.
Both, not the one heuristic that happened to be measured. `env -i
TERM=xterm-256color SHLVL=1 …/Tailscale status --json` answers `{"Version":`,
and a stub that behaves the way the bundle does — JSON for a shell, the GUI
sentence for anyone else — drives `Tailnet.scan` in the tests. 401 pass.

The better error message stays: it is what turned "Unexpected character 'T'"
into a sentence a human could act on in one round trip, and it is what will
name the next binary that answers something else.

### Cut as v0.1.22

Build 160, 5,083,957 bytes, notarized (`Accepted`), stapled, `spctl` says
`source=Notarized Developer ID`, and published to both CDN keys; the live
feed's `length=` matched the zip's real content-length, which is what
`scripts/package` exits non-zero on. `scripts/package --ad-hoc` ran first
against the same tree and cut a clean bundle (5,035,980 bytes, unsigned by
Developer ID and unnotarized — the difference is the signature and the
staple), so the notarization was spent on a bundle already known good.
`scripts/install --dist` put the release on studio:

```
$ ccc version
ccc 0.1.22 (160)  /Users/rf-studio/Applications/ccc.app
$ ccc hosts discover
air     air.bengal-barb.ts.net  Ramon’s MacBook Air
studio  studio.bengal-barb.ts.net  Ramon’s Mac Studio  this Mac
```

Studio's answer is the control, not the measurement: it was never the Mac
that broke, and `shellish` must leave it unchanged. **The measurement is
air's, and it is one sentence** — Add Mac on air lists the tailnet instead
of naming a character — which cannot be taken until air pulls this cut.

### air answers

Reported from air on v0.1.22: **Add Mac works.** The sheet lists the tailnet
where it used to show `Unexpected character 'T' around line 1, column 1`.

That is the whole measurement, and it could only be taken there. The
bisect that found the cause ran on studio, against a byte-identical copy of
the binary, using `env -i` to *simulate* the environment a GUI process has —
`Tailnet.shellish` was correct against a simulation and a stub. Air is where
the real `ccc.app` runs the real `/Applications/Tailscale.app/Contents/
MacOS/Tailscale` with no `TERM` and no `SHLVL` of its own, and it agrees.

**What the slice is worth keeping for.** The suite was green on studio
through the entire bug: 401 tests, and `ccc hosts discover` answering
correctly the whole time, because studio's `/usr/local/bin/tailscale` shim
made it immune by accident. Green here says nothing about a bug that lives
on the other Mac — the release is not the delivery of such a fix, it is the
only instrument that can measure it.

## the four branches, and the sha is the undo (2026-09-04)

Item 7 closed. `origin` now carries `master` and `worktree-v2` and nothing
else. What was deleted, verified merged the way the item asked —
`git merge-base origin/master origin/<b>` equal to the branch's own tip, so
master already contains every commit:

```
9f57ca4  hotfix-gridbuilder
9e977d7  worktree-v0
11eeb4a  worktree-v1
7d535e6  worktree-icon
```

Recorded because **a deleted branch is a name, not a loss**: each sha is
still reachable from master, and `git branch <name> <sha>` puts any of them
back. That is the whole reason the shas were taken before the push rather
than after.

`worktree-icon` is the one the item got wrong once: carved out on
2026-09-03 as unmerged, it had in fact landed at 37cdae5, the merge tagged
v0.1.6. The 2026-09-04 re-check is what found it, which is why the item
asked for `--merged origin/master` every time rather than trusting its own
earlier list.

ccc could not run the delete itself — `git push origin --delete` is refused
by the auto-mode classifier, both for four branches at once and narrowed to
one. The user ran it. Worth knowing before a session plans around doing it.

## item 14 closes unmeasured (2026-09-04)

The colour oracles were never compared on a screen, and the item is gone
anyway. Recorded because closing an item without its measurement needs a
reason a cold session can check.

**The question that created it was already answered.** 8b took a real
`screencapture` with ccc's pane and iTerm both visible — one composite, one
output profile — and found them **bit-identical** at `#15191F` (see "8b:
there is no colour-management residual"). The suspicion that opened v8, an
unmanaged Metal layer shifting values against a non-sRGB panel, died there
by measurement. What 14 proposed to add was confirmation of two more
colours — 12b's `#B3D7FF` selection and 12c's bold-is-bright `#DD7975` —
through a pipeline already shown not to move one.

**What it would still have caught, stated so it is not lost.** `ccc
snapshot --color` and the Metal renderer resolve colour through the *same*
`RunMerge.resolvedColors`, deliberately (12a). So the headless oracle is
not independent of the renderer: if that function is wrong, both agree and
every colour test still passes. A `screencapture` is the only check outside
it. That blind spot is real and now uncovered on purpose — the bet is that
8b's bit-identical background already exercised the whole path from
`resolvedColors` to photons, and only the input differs.

**What it cost to try.** `ccc capture` is refused from a Claude Code
session's shell, and the cause is not ccc's: macOS keys the CLI's TCC grant
to the resolved binary path, `~/.local/share/claude/versions/<version>`, so
every auto-update starts ungranted and Privacy & Security accumulates a row
per version, all named "claude". `CGRequestScreenCaptureAccess()` returns
false **without prompting**, and `tccutil` cannot target a path
(`No such bundle identifier`; resetting the app bundle's
`com.anthropic.claude-code` succeeds and changes nothing). With the rows
showing enabled, `screencapture -x` still answered `could not create image
from display`. The way that works is a plain terminal tab outside Claude
Code, where the terminal's own stable bundle id is what TCC checks.

`ccc capture` and `ccc pixel` stay — they are correct, they are tested, and
they are what the next session runs if a colour is ever doubted again. What
left is the standing obligation to run them.

## the mobile survey: RC is already the phone (2026-09-04)

Opened as "explore mobile", widened on the user's ask to *what does the
Claude mobile app actually do, how does RC work, can Ghostty run on a
phone, and what are the unknown unknowns*. No code shipped. What it
returned falsifies one leg of the phone argument written into
`docs/QUEUE.md` "Later" earlier the same day, so the argument is amended
rather than repeated.

**`--rc` is already on most of the fleet, and ccc never put it there.**
Read straight out of the live roster:

```
python3 -c 'import json,os; d=json.load(open(os.path.expanduser("~/.claude/daemon/roster.json")));
[print(k, (v["dispatch"]["launch"].get("flagArgs") or [])) for k,v in d["workers"].items()]'
```

Five of nine workers carry `--rc` in `flagArgs`/`respawnFlags` — including
`b3919c35`, the `ccc` job this survey ran in. `grep -rn -- "--rc\|remote-control\|
remoteControl\|PRESENCE\|MESSAGING_SOCKET" Sources/` returns **nothing**:
ccc neither sets the flag, reads it, nor shows it. The flag is the user's
own spawn habit, and ccc is blind to it.

**RC is an outbound cloud relay, not a LAN thing** (`code.claude.com/docs/en/
remote-control`). The local session makes outbound HTTPS only, never opens
an inbound port, registers with the Anthropic API and polls; the phone
talks to Anthropic and Anthropic routes to the Mac. Execution and files
stay local, but **the transcript is stored on Anthropic servers while
connected** — that is what keeps the surfaces in sync and what survives a
network drop. There is no third-party entry point to that relay: the client
on the other end is the Claude app or claude.ai/code, and nothing else.

**What the phone can already do, today, to these sessions.** Send messages;
answer permission prompts and `AskUserQuestion`; `/model`, `/effort`,
`/config key=value`, `/compact`, `/context`, `/usage`, `/mcp`. Push is
already on here — `~/.claude/settings.json` carries `agentPushNotifEnabled:
true` and `inputNeededNotifEnabled: true`, and `~/.claude.json` carries
`hasUsedRemoteControl: true` with `remoteControlSurfacesSeen: ["mobile",
"desktop"]`.

So **the phone's whole argued marginal value is already shipped.** The
queue's "Later" said the phone's value is unblocking, and that unblocking
*is* the two write paths (approvals, peek/reply) — so build those first.
The first half stands; the second is wrong. Anthropic already built both,
for every `--rc` session, on a surface ccc cannot enter and does not need
to. A ccc phone must earn its place on something else.

**Experiment 4 is not answered, and no longer blocks anything.** Its literal
question — how the agents-view peek/reply reaches the daemon — was pursued
into the CLI binary (`strings` over
`~/.local/share/claude/versions/2.1.260`, a bun standalone whose logic is
`@bun @bytecode` so only literals and export maps survive). The rendezvous
channel is per-worker: `/tmp/cc-daemon-501/<daemon>/rv/<short>.sock`, keyed
by `rvAuth` in roster.json, vocabulary `subscribe snapshot repaint splice
setcwd handoff attacher-caps pty-auth-required`. Undocumented, unpromised,
and now unnecessary, because the **need** has a documented answer.

**The documented write path is the session's inbox socket**
(`code.claude.com/docs/en/cross-session-messaging`). Every session binds
one, and the docs sanction exactly our use: *"Read this section when a
session you expect isn't in the agent list, when you want a script or hook
to post into a session"*. Measured here:

```
env | grep CLAUDE_CODE_MESSAGING
  CLAUDE_CODE_MESSAGING_SOCKET=/tmp/cc-socks/54334.sock
  CLAUDE_CODE_MESSAGING_TOKEN=22bc88ad82387f90c224c44bb36ad335
```

**The address is a join ccc can already make: roster `replPid` →
`/tmp/cc-socks/<replPid>.sock`, nine for nine** (`join.py`; `pid` is the
launcher and matches nothing — it is `replPid`, the REPL process, and
getting that wrong addresses no one). On macOS the auth line is optional;
a script sends `{"type":"auth","token":"<token>"}` as the first line only
where it must. The socket is 0600 and per-uid.

Two limits, both load-bearing:

- **A peer message can never approve anything.** The docs are explicit: a
  message from another session "never counts as your consent, so it can't
  answer a pending permission prompt on your behalf". So the inbox socket
  is *reply* without attaching, and **never** *approve* without attaching.
  Those two were one line in the queue and are now measurably two features.
- **ccc is not a session, so it asserts no permission class.** An
  unverifiable sender is treated as asserting none, which means a receiving
  session in `bypassPermissions` holds the message for approval rather than
  delivering it. Receivers that prompt (including `--permission-mode auto`,
  which lore runs) take it.

**The one thing not measured: the message line's wire format.** Only the
auth line is documented, and the literals live in the bytecode chunk. A
four-shape probe against ccc's *own* socket (own-child messages are
verified and delivered, so blast radius is one conversation) was **refused
by the auto-mode classifier** — writing to a session's IPC socket reads as
injection. Not routed around. It is one `Bash` permission rule or one
`! python3 …` away, and it is the last thing between here and a `ccc
reply` twin.

**Ghostty on a phone: answered, and it is not a research question.**
Upstream has no iOS app and no plan for one, but keeps **libghostty
building for iOS in CI** and invites the community to it. Several apps
ship on that: `daiimus/geistty` (libghostty's **External termio backend** —
terminal data from an external source instead of a local process — plus
`swift-nio-ssh` for transport, Metal at 120fps, iOS Keychain for
credentials), plus gterm, VVTerm, Hoshi, AgenTTY, Clauntty, Claudette Echo,
Echo, CodeAgents Mobile. Several of those are **purpose-built for driving
Claude Code TUIs from a phone**. The category exists and is competitive.

Three consequences for ccc, in descending order of how much they change:

- **The seam already points at iOS.** libghostty's External termio backend
  is the same shape as ccc's one-page seam (feed bytes, write bytes,
  resize, snapshot), which is what geistty drives from SSH instead of a
  PTY. The seam was designed for swapping cores and turns out to be the
  port line too.
- **The subprocess problem has a named answer.** `docs/QUEUE.md` "Later"
  called the in-process ssh client "a dependency question, not an
  architecture one" and it was right: `apple/swift-nio-ssh` is the answer
  geistty shipped (forked only for RSA; Ed25519 works upstream), with
  `gaetanzanella/swift-ssh-client` as a higher-level wrapper. Pure Swift,
  no fork/exec, on iOS today.
- **`No tmux, ever` is the edge, not the tax.** Every shipping
  Ghostty-on-iOS client reaches for tmux control mode to survive app
  suspension — geistty names it, AgenTTY sells it. ccc needs none of it:
  the daemon is already the multiplexer, so resume is `claude attach <id>`
  and the session was never the app's to hold. The house rule that reads
  as an ascetic constraint on the Mac is the thing that would make ccc's
  phone *cheaper* than the ones already in the store.

**And one Mac-side finding that needs no phone.**
`CLAUDE_CLIENT_PRESENCE_FILE` (v2.1.181+) suppresses mobile push while a
marker file exists; the docs say to "configure a screen-lock listener or
similar tool" to write it on unlock and remove it on lock. **ccc is that
tool** — it is a menubar-resident app that already knows window focus — and
today it does not know the variable exists. That is a twin-shaped feature
against a documented surface, on the Mac, with the phone already in the
user's pocket.

## the pane that could not say it had looked away (2026-09-04)

Item 17 slice 2, and it started as a user report — missing phone pushes,
guessed to be focus suppression. It is, and the cause was ours.

**Three measurements, in the order that makes the fourth follow.**

Every session the harness runs turns **DEC 1004 focus reporting** on:

```
python3 -c 'import json,os; d=json.load(open(os.path.expanduser("~/.claude/daemon/roster.json")));
[print(k, v.get("decModes")) for k,v in d["workers"].items()]'
```

`1004` is in `decModes` for **8 of 8** workers, alongside 1000/1002/1003
(mouse), 1006 (SGR), 2004 (bracketed paste) and 2031. The harness is asking
the terminal to tell it when the human looks away.

**ccc never answered.** `grep -rn "1004\|focusIn\|focusOut\|windowDidBecomeKey\|
resignKey" Sources/` returned **nothing** — no focus reporting of any kind,
in either core, in the window or headless.

**And an unanswered question is read as "yes".** The presence module ships
as readable JS in the CLI (`strings` over
`~/.local/share/claude/versions/2.1.260`, chunk at offset 179545366 — this
one is not bytecode). It POSTs
`/v1/code/sessions/<id>/client/presence` with `client_id` and
`connected_at` every 5 s while the user is at the terminal, and the phone's
push is suppressed while that is live. The guard is one line:

```js
h=()=>{if(EQ()===!1){t(`${r} pulse skipped (terminal blurred)`);return}…}
```

`EQ()` is the focus state and is `undefined` when nothing has reported.
The skip fires **only on an explicit `false`**. So a terminal that reports
nothing is treated as present, forever, and `teardown` is the only thing
that ever clears it.

**Which makes the conclusion arithmetic rather than a theory:** an attached
ccc pane could only ever *over*-suppress the user's phone. Not sometimes —
structurally, because ccc owned the one signal that turns suppression off
and never sent it.

**The fix, and why it is in the seam.** `TerminalHost.setFocused` is the
sixth member, `GhosttyHost` writes `CSI I` / `CSI O`, and the window feeds
it from `NSWindow.didBecomeKeyNotification` scoped to the window.
Two decisions worth keeping:

- **The desire is held, not dropped.** A pane mounts *before* its child
  exists, so the first report cannot be written — and that is exactly the
  case that matters, since a session attached while the window is not key
  must be able to say nobody is watching. `flushFocus` retries after every
  chunk the child writes, so the report lands on the same read that
  negotiates the mode. No timer.
- **The signal is the window being key, not first responder.** A stricter
  reading would call the session pane blurred while the user works in the
  shell pane under it. Two panes in one window are not two windows, and the
  question the mode is really being asked is whether to buzz a phone.

`CSI I` / `CSI O` are hand-written, which CLAUDE.md forbids for keys. The
exemption is narrow and stated at the call site: mode 1004 has no encoder
in libghostty-vt at the pinned commit (`modes.h` defines
`GHOSTTY_MODE_FOCUS_EVENT` and nothing writes it), and unlike a key these
carry no state — no modifiers, no kitty variant, no application-cursor
form. Two sequences are the whole protocol.

**Proved against a live `claude attach`**, not only in tests. A haiku
fixture (`ccc spawn --name ccc-focus-fixture --model haiku`), attached
headless on its own socket so the running app kept ours
(`CCC_CONTROL_SOCKET=…`, which is how a second server is possible at all):

```
read:  focus out        ← the attach declared itself unwatched on install
in:    focus in         ← reached the real TUI, so 1004 really is on
again: focus in (already)
out:   focus out
```

The first line is the whole fix in one word: before this, ccc said nothing
there and the harness assumed a person. Headless reports too, deliberately
— it builds the same `GhosttyPane` off-screen, nobody is looking at it, and
it now says so.

`ccc focus [in|out]` is the twin, and it exists because **the state is
invisible on this Mac and visible on a phone**: asserting it from a script
and reading the bytes on the other side of the PTY is the only way to prove
ccc reports blur at all. `FocusReportTests` drives the real core for the
six cases, the attach case included.

**One wording bug, caught live and worth the line.** The refusal for a
repeat first read "(not reported — no attached pane has DEC 1004 on)",
which sends the reader hunting a mode that is in fact on. Three outcomes,
three sentences: sent, `(already)`, and the mode-off one.

**Not measured here, and it is the user's to close:** whether the phone
now buzzes for a session ccc holds and nobody is watching. That needs the
phone, a blocked session and a walk away from the Mac.

## Cut as v0.1.23 (2026-09-04)

Item 17's two slices, released the same day they were built, because the
second one is a **bug fix whose damage was ongoing**: until the app on
studio carried it, every session ccc held was still telling the harness
someone was watching, and still suppressing the user's phone
(`docs/EVIDENCE.md` "the pane that could not say it had looked away").

The four steps, unchanged (`RELEASES.md`): `VERSION` → tag → `scripts/package`
→ `scripts/install --dist`. Notarization `Accepted`, staple validated,
`spctl` accepted as `Notarized Developer ID`, one `<item>` asserted, both
CDN keys overwritten zip-first, and the live feed's `length=` matched the
zip's real `content-length`:

```
live: https://cdn.ramonfabrega.com/ccc/ccc-latest.zip version 170 length 5091967
cut ccc v0.1.23 (5091967 bytes), published
ota verify --feed ccc  →  ok: … version 170 length 5091967
```

Verified on studio against the **released** build, not the dev one:

```
ccc version  →  ccc 0.1.23 (170)  /Users/rf-studio/Applications/ccc.app
ccc stats    →  ccc 0.1.23 (170)  pid 21093 …
ccc list     →  the `rc` column, marking lore, attrition and ccc
```

**Air is where this one is measured**, and by the rule v12 left behind: a
fix for a bug that lives on the other Mac is unproved until a release
carries it there. Air pulls this from the feed. The half nobody can assert
from a terminal is the phone — whether a push now arrives for a session ccc
holds while nobody is at the Mac.

One thing to know when reading `ccc focus` right after a cut:
`scripts/install --dist` relaunches the app, which makes its window key, so
the first reading is `focus in` and that is correct rather than stuck. It
flips on the next key change.

## item 4 — the far side answers from the app (2026-09-04)

The queue held item 4 as debt with a number attached: air's studio poll
ran `mean 1354 ms` against a 2 s tick on the lid night, "because the far
side's ccc does the transcript join before answering". The first
measurement said the join was not the cost.

### The cold process was the cost

On studio, with 22 rows, three readers of the same roster:

```
claude agents --json --all                real 0.14  0.14
ccc list --json --host local (0.1.23)     real 0.67  0.59  0.45
ccc stats  →  roster poll  last 188 ms  mean 192 ms   model join  last 9 ms  mean 11 ms
```

The app's own tick is 190 ms and its join 10 ms. A fresh `ccc list`
process is 450–670 ms because it is *cold*: a new `claude agents` spawn,
an empty `ModelProbe`, an empty `JobProbe`, every transcript path
re-found (a miss stats ~100 wells), and `git rev-list` for every moved
worktree. That cold process is exactly what the hop runs on every poll,
so the far side redid, cold, what its own window had warm two seconds
earlier.

### The fix: `ccc list` asks the app

`ControlRequest.roster(fresh:)` answers with every host's `HostPoll` —
rows, issues, notes, the last error, when it was polled — as the app
holds it; `ccc list` tries that first and prints it through the same
`RosterPoller.State` its own tick would have built. `--fresh` asks the
app to tick once more first. No app on the socket, an older app that
answers "malformed request", or a host the app does not know: the CLI
polls itself, as it always did. `HostPoll` decodes field by field with
its defaults, so a CLI newer than the app reads the app's answer.

Measured against a headless `ccc attach --headless` of this build on a
private socket (`CCC_CONTROL_SOCKET`), attached to a haiku fixture, same
22 rows:

```
ccc list --json --host local   served     real 0.01  0.01  0.00  0.00  0.00
ccc list --json --host local   --fresh    real 0.18  0.17  0.18
```

And across an ssh hop, studio → studio over loopback, which is the shape
air's poll has minus the latency:

```
ssh localhost echo ok                                   real 0.08  0.08  0.08
ssh localhost /opt/homebrew/bin/ccc list … (0.1.23)     real 0.66  0.99  0.73  0.93  0.80
ssh localhost <new> list …            (served)          real 0.10  0.10  0.09  0.09  0.10
ssh localhost <new> list … --fresh    (one warm tick)   real 0.28  0.28  0.27
```

Same rows both ways: 22716 bytes against 22715, the one byte being the
fixture's `attached` flag, true on the headless server that held it.
**The far side's answer is now the hop plus ~20 ms**, where it was the
hop plus 600–900 ms. Air's own number is owed from air (its poll includes
the tailnet's latency, which loopback does not carry), and the lid
instrument already prints it.

### The blocking read left with it

`ClaudeCLI.run` now goes through `Subprocess.run`: both pipes drained by
`DispatchIO`, the exit awaited through `terminationHandler`, cancellation
terminating the child. `SubprocessTests` pins the three things the
blocking version could not be trusted to do — no deadlock on a child
that fills both pipes past 64 KiB, no thread parked per child (32
concurrent 300 ms sleeps finish in 313 ms), and a cancelled task ends its
child. `Git.run` and `Tailnet.scan` keep the blocking shape; they are
synchronous by signature and run off the main actor.

### One trap for the next measurement

`ssh localhost "ccc list …"` exits **127**: the bare name is not on a
non-login shell's PATH. The host config stores absolute paths, so the real
poll never hits this — but a timing that forgets it measures a failed
exec in 80 ms and reports the wrong win.

## item 9 leaves (2026-09-04)

The attach transition shipped ("the attach transition, and the hole in the
← guard") and was proved over ssh 2026-09-03: six alternating swaps
between two remote fixtures ran 1075–1385 ms against the local path's
1022–1086 ms, every one answering "attached … (left …)", so the hop costs
~20–50 ms on a warm master and the 8 s `waitUntilDrawn` timeout has ~7x
headroom. That was a loopback hop; a latent one is air's to run.

What the item held open was a shape, not a wait: **"drawn" is a shape,
not a certainty.** `waitUntilDrawn` returns on the first stable screen
with more than one painted row — enough to reject the attach client's
one-line wake message, not proof the TUI finished; a render that pauses
over 250 ms mid-paint can still swap in early. Never seen in the wild,
which is why it leaves the queue: it is a known edge with no forcing
function, recorded here so the next person who sees an early swap has
its name.

## the audit (2026-09-04)

Run while the user was away from every Mac, on tokens: four Opus
reviewers (correctness over roster/harness, correctness over
terminal/render/app, a twin audit, a docs-drift check), then five Opus
verifiers told to *kill* each finding. The rule was that nothing is
touched until a verifier confirms it with a reproduction or a traced path.

### What the reviewers said and what survived

| finding | verdict | fix |
|---|---|---|
| overlay mark: load before the roster read, save after — two marks lose one | **confirmed**, reproduced with a 400 ms stub (one of two archives gone, both exit 0) | load after the read, under `RosterOverlay.locked`; poller prune under the same lock; `twoMarksAtOnceBothSurvive` |
| remote roster decodes strictly; one bad row freezes the host | **confirmed** — the trigger is a newer far side's enum word (`Status.waiting` arrived exactly this way) | lenient `Session.init(from:)`, `LenientElement`; `aWordFromANewerCCCDoesNotCostTheHost` |
| `sorted` vs `rows(sortedBy:)` rank drafts differently | downgraded (consumers are the legacy `.list`, `recentFolders`) | one comparator; `sortedIsTheActivitySort` |
| `reconnect` joins the in-flight poll on the evicted master | downgraded (reattach reads pane state, not the poll; costs one tick) | `tick(fresh:)` cancels it; `aFreshTickEndsThePollInFlight` |
| `Git.run`/`Tailnet.scan` read pipes sequentially | downgraded — hangs at 66,000 B of stderr (measured), no git verb here says that much | `Git.Drain`; `aLoudStderrDoesNotHangTheScan` |
| `stop()` leaves the poll in flight | downgraded (one bounded straggler) | cancelled, recorded as nothing |
| `bases` cache never invalidated | downgraded (merge verbs build a fresh probe; the poller's does not) | trusted while it resolves, name in the key; `aRenamedDefaultBranchIsFoundAgain` |
| control client read has no deadline | **confirmed** via `.roster(fresh:)` behind a wedged poll | 60 s idle timeout, `timedOut`; `aSilentServerTimesOutInsteadOfHanging` |
| `presentedFrames` counts calls | downgraded (zero still means black; nonzero inflated) | counts encodes; `presentedFramesCountEncodesNotCalls` |
| `ccc resize 0 0` | **confirmed** for the CLI; the window clamps | refused at the verb and the socket |
| `capture` waits before reading stderr | downgraded (latent) | `Subprocess.run` |
| glyph atlas written while frames in flight | **killed** — writes only ever land in fresh space, no eviction, `.shared` storage | `atlasRectsNeverOverlap` as the tripwire |

Two things the verifiers said that the reviewers did not: the skew
direction of "is the remote ccc older" was backwards (studio runs the
dev loop, so the far side learns a word first), and the sequential-read
comment in `Tailnet.scan` stated the rule the code violated.

### The twin audit

The CLI verb list is strings in two places (`CLI.run`'s switch and the
hand-written usage) and no test can reach either, because the `ccc`
target has no test target; `WindowAction` is the one grammar that is a
type with a generated usage and a round-trip test. Gaps ranked worth
closing, recorded on queue item 5: `ccc ask`, a mouse-button `send`,
`hosts remove|check` in the window, an age column. `ccc list --fresh`
is ⌘R's twin since item 4.

### The docs drift

Twelve items, one of them a red test (the queue at 277 lines against
its 200 bound); all fixed in "The docs said v0.1.18 and five members".

## Cut as v0.1.24 (2026-09-04)

**v0.1.24, build 176**, cut from `worktree-v2` at `ab01daf` on the user's
word from a phone. Notarization `Accepted`, staple validated, `spctl`
accepted as `Notarized Developer ID`, one `<item>`, both CDN keys
overwritten zip-first, the live feed's `length=` equal to the zip:

```
live: https://cdn.ramonfabrega.com/ccc/ccc-latest.zip version 176 length 5124962
cut ccc v0.1.24 (5124962 bytes), published
ota verify --feed ccc  →  ok: … version 176 length 5124962
gh release view v0.1.24  →  ccc-v0.1.24.zip 5124962
```

Installed on studio with `scripts/install --dist` and verified against
the **released** build, which is the first one whose app answers
`ControlRequest.roster`:

```
ccc version                              →  ccc 0.1.24 (176)  ~/Applications/ccc.app
ccc list --json --host local (served)    →  real 0.02  0.03  0.02
ccc list --json --host local --fresh     →  real 0.41
```

Over the loopback hop the picture is the same shape as the headless
measurement under "item 4 — the far side answers from the app", with one
honest difference: studio was busy (the relaunch's fetch rounds, six
working sessions), so the hop *itself* read 0.31–0.39 s for
`ssh localhost true` where it read 0.08 s an hour earlier. `ccc list`
over that hop read 0.19–0.34 s — **no more than the bare hop** — and
`ccc stats`, a one-line socket round trip, the same. The claim that
survives load is the one that matters: the far side's answer costs the
hop and nothing else. Air's number, with the tailnet's latency in it, is
the lid instrument's to print.

One number to read carefully after a relaunch: `ccc stats` said
`roster poll  mean 2913 ms  n=3` at 14 s of uptime and `mean 919 ms
n=18` a minute later. The first ticks compete with the launch fetch and
cold probes; the mean carries them for a while. The `last` is the tick.

## item 18 — the base is recorded (2026-09-04)

Two consumers in one day could not use `ccc spawn --worktree`: attrition
(trunk `worktree-replan-pdb`, main eight behind) and storefront-launch
(trunk `storefront`, 590 ahead of master). The harness cuts its worktrees
off the default branch and every verb in the family measured against it,
so storefront's rows read `base: master, behind: 24` — a wrong number on
screen, against a branch nobody lands on. Every repository root in the
fleet is on `master`/`main` (checked: ccc, attrition, cuanto, lore), so
"the root's branch" is not the signal; the base has to be per worktree.

### The rule

A worktree branch's base is, in order: `branch.<b>.ccc-base` in the
repo's own config; VS Code's `branch.<b>.vscode-merge-base` (`origin/x`
→ `x`, honoured because it means the same thing and cuanto's config
already carries a dozen); else the default branch. Either is trusted only
while it resolves. The config is parsed by hand, re-read on mtime, one
`stat` per row per tick otherwise; `WorktreeInfo.baseRecorded` says which
it was, nil off an older ccc.

`ccc spawn --worktree` cuts the worktree itself — `.claude/worktrees/<n>`
on `worktree-<n>`, the harness's own layout — when `--base` is named or
the asking folder is on a non-default branch (the spawning session's own
worktree, which was every reporter's case), records the base, and hands
the harness a plain cwd. From a folder on the default branch with no base
the harness cuts it as before, so `claude rm` keeps its cleanup. Remote
`--base` is refused with the way out named. `ccc base <ref> [<branch> |
--clear]` is the read and the write by hand, for the worktrees already
cut. `BaseTests` (seven) pin the parse, the precedence, the cut, the
refusals and the spawn's choice.

### And, at the user's word, spawns are auto

Lore relayed it: none of the seven jobs then running carried a
`--permission-mode`, so each stopped at its first prompt, unanswerable
from a phone. `SpawnRequest` now defaults the mode to `auto`; an explicit
one wins, `default` included. `JobInfo.permissionMode` reads the launch
mode off `respawnFlags`, `asksForPermission` names the ones that stop,
and `ccc list` shows `asks` (the window a badge) for a background job
launched that way. `ccc spawn --rc` exists; no default.

## Cut as v0.1.25 (2026-09-04)

**v0.1.25, build 180**, cut from `worktree-v2` at `63457e7`, an hour after
v0.1.24, because two things in it change what the commanders get the
moment they next spawn. Notarization `Accepted`, one `<item>`, both CDN
keys, the live feed equal to the zip, the GitHub Release with the zip:

```
live: https://cdn.ramonfabrega.com/ccc/ccc-latest.zip version 180 length 5155931
ota verify --feed ccc  →  ok: … version 180 length 5155931
```

Installed with `scripts/install --dist` and verified against the released
build. The `asks` column on the live roster, first reading:

```
  97c4731d  working  busy           beta-fb-polish       ~/code/work/cuanto ⎇ beta-fb-polish ↑591 ↓24 ⇡1
  58023208  working  busy  rc asks  storefront-launch    ~/code/work/cuanto ⎇ worktree-storefront-standby ↑590 ↓24
  7f476e34  working  busy  rc asks  att-capture          ~/code/fun/attrition ⎇ lane-capture ↑22
  3c382923  working  busy  rc asks  attrition            ~/code/fun/attrition ⎇ worktree-replan-pdb ↑25
  b3919c35  working  busy  rc asks  ccc                  ~/code/fun/ccc ⎇ worktree-v2 ↑21
```

The four commanders launched without a mode read `asks`; the lanes
attrition spawned after lore's interim instruction (`--permission-mode
auto` by hand) do not — the column discriminates exactly the population
lore described, from the files it described.

And the base, on the row that reported the wrong number:

```
ccc base 58023208
  worktree-storefront-standby is measured against master (default); … ↑590 ↓24
ccc base 58023208 storefront
  worktree-storefront-standby is measured against storefront (recorded); … level
ccc list | grep 58023208   (one tick later)
  58023208  working  busy  rc asks  storefront-launch  ~/code/work/cuanto ⎇ worktree-storefront-standby level
```

`↑590 ↓24 ⇣1` became `level`, and the `⇣1` on the repository went with
it — that was `origin/master` ahead of `master`, a number about a branch
this worktree never lands on. The record is one line in cuanto's
`.git/config`; `--clear` takes it back.

## the swarm's five findings (2026-09-06)

The first real commander swarm — three commanders, seven workers, and a
machine that locked mid-run on 09-04 at 23:13Z — held. **Every gap it
exposed was at the spawner/roster layer and none in the terminal embed**,
which is the sentence that made ccc v1. What follows is what each one
measured, in the order they were worked.

### master was 22 commits behind its own frontier

`e904087` was not a descendant of `4df8f55` (ingest #23's audit point):
twelve commits, five tags (v0.1.21–v0.1.25) and the live queue existed
only on `worktree-v2`. `git merge-base --is-ancestor master worktree-v2`
was true and the reflog showed 20+ consecutive fast-forwards before it, so
this was a break in cadence and not a divergence. Landed with ccc's own
verbs, which is the note worth keeping — the session ref is the whole
address:

```
ccc merge b87b7169 --ff-only --json
  fast-forwarded worktree-v2 → master (22 commits, now 1575db7)
ccc push b87b7169 --base --json
  pushed master → origin (22 commits)
```

The merge read the base off the row (`master`, inferred, `baseRecorded:
false`) and refused nothing. All five tags were already on origin.

### two jobs answered to one name

On 09-06 two jobs named `att-capture` existed for twenty minutes in one
`lane-capture` worktree: the daemon still held Friday's, and the attrition
commander respawned the lane with the same name and cwd. By-name routing —
`SendMessage`, the lore thread, the roster — goes to the newest, so both
halves mis-attributed and neither was addressable. Credit: the attrition
commander, which reported it against itself.

**The predicate is the name alone, not name+cwd.** The report named the
conjunction, but the harm it describes needs only the name, and a namesake
in a second folder mis-routes exactly as badly. The converse does *not*
hold: the same roster carried six live rows under `~/code/work/cuanto`,
and a second session where the work is is the commonest thing anyone does,
so cwd alone is reported and never decisive. Live means not
done/failed/stopped — that roster held two `beta-fb-polish` and two
`beta-fb-metadata` in ended states, and re-using a finished lane's name is
what a commander does every loop.

Proved on owned fixtures (`--model haiku` drafts, removed after):

```
ccc spawn --name ccc-guard-fixture --model haiku --cwd …   →  af9223e5 (draft)
ccc spawn --name ccc-guard-fixture …                       →  exit 1, nothing dispatched
  'ccc-guard-fixture' is already blocked as af9223e5 in that same folder —
  messages, the roster and lore would all resolve to whichever started last.
  Stop it first (`ccc stop af9223e5`), spawn with --replace to do that here,
  or --allow-duplicate to mean it.
ccc spawn … --replace                →  stopped af9223e5, spawned cfc77fb8
ccc spawn … --allow-duplicate        →  89ae69e5, beside it
```

**The first attempt at this proof spawned a real session.** The name it
tested (`att-loop-march`) had gone dead six minutes earlier — the attrition
commander merged `origin/loop-219` at 19:33:43 and cleaned up its worker —
so the guard correctly saw no live namesake and dispatched. Nothing was
lost, and the lesson is the fixture: **test a guard against a name you own
and can watch, never against a live fleet's row you read a minute ago.**

`--replace` needed `ccc stop <ref>`, which did not exist: `stopped` has
been a state on every row since v1 with no verb to produce one — the twin
rule biting from the read side. `claude stop` keeps the conversation and
the worktree; `rm` is the one that deletes.

### the disk had no floor

Friday 23:13Z the Mac locked when an attrition worker's release suite
reached 27.6 GB with 53 GB of swap full, on a disk crowded by six Rust
`target/` trees (1–18 GB each) and 25 Next `.next/` trees. Nothing in ccc
noticed because nothing looked.

**The floor is a constant and the claim it makes is deliberately small.**
No spawn-time number predicts a 27.6 GB suite an hour later — Friday's
worker would have cleared any floor. 10 GB is where macOS stops being able
to grow swap, which is the failure that actually happened: it refuses the
spawn that starts on an already-doomed disk and says nothing about the one
that dooms it. Measured live at 158.3 GB free, so the guard is silent here
until it is not.

### `ccc update` was the verb, and could not be found

A worker's `git merge --no-edit origin/worktree-replan-pdb` was refused by
the auto-mode permission classifier and handed back to its commander — the
right failure, and it happened while a verb that does exactly that, with
guards the raw merge has not, sat one word away. **Two things made it
unfindable**, and neither was the worker's fault:

- the CLI help said "merge the repo's default branch" a release after
  v0.1.25 taught `update` the *recorded* base, so a worker reading it
  would correctly conclude the verb was not for it;
- it merged `refs/heads/<base>` while the worker asked for
  `origin/<base>`. On a lone repository those are one ref in two costumes.
  Not here, because of a shape a lone repository never makes: **the base
  branch is checked out in another session's worktree.** attrition's
  commander holds `worktree-replan-pdb` while every worker branches off
  it, and `ccc pull` cannot advance that ref — it fast-forwards in the
  main checkout and refuses unless `HEAD == base`, and the main checkout
  is on `main`. On drift there was no ccc path at all.

Measured on the live fleet before the change — `att-loop-mem` (997ecc90),
base `worktree-replan-pdb`:

```
rev-list --left-right --count refs/heads/worktree-replan-pdb...refs/heads/loop-235   20  1
rev-list --left-right --count refs/remotes/origin/…            ...refs/heads/loop-235   20  1
rev-list --left-right --count refs/remotes/origin/…            ...refs/heads/worktree-replan-pdb   0  0
```

Local and origin agreed, so `ccc update 997ecc90` would have worked that
minute — **only because the commander pushes promptly.** The gap was one
unpushed commit away the whole time. `WorktreeInfo.baseTip` now follows
`origin/<base>` when origin strictly holds every local commit and more,
`↓N` counts against the same tip the verb merges, and the answer names
which it used. A *diverged* base stays local: that is a human's call. No
worker writes into the commander's tree.

### a session that stops moving

cuanto's Lane B was contracted to report at each landing point, sent zero
messages, and sat with two unpushed commits for two days. `ccc watch` was
silent and right to be: `blocked`/`done`/`failed`/`stopped` are the only
things that ever happen to a row, and it was `working` throughout. **A
stall is a non-event, and a non-event needs a clock.**

`updatedAt` in the daemon's job file is the only clock ccc has for a
working session — `startedAt` says when it began and nothing else says
when it last moved. Read live 2026-09-06 against a session eight seconds
into a tool call, so it tracks turns rather than sessions.

30 minutes is a constant, not a measurement: nothing at this boundary
distinguishes a wedged session from one twenty minutes into a release
suite. **What makes it safe to ship at a guess is the shape** — one event
per stall, re-armed only by real movement, so a long legitimate step costs
one line and never a stream. Forced to a 12-second window against the live
fleet, two rows fired once each with the daemon's own sentence:

```
20:10:22  ⏳ stalled  3c382923  attrition has not moved in 0m — Checking how the commander was opened before
20:10:22  ⏳ stalled  b87b7169  ccc has not moved in 0m — item 3 verdict: ccc update bug…
```

That run found the one bad string: a sub-minute stall spelled `0m`, which
reads as a bug rather than as a small number. It says seconds now. The
cadence-relative version — each session against its own median gap — is
the next one, and **the thing to do before building it is count how often
the fixed one was useful.**

### the verb list was a string nothing read

`ccc spawn --help` answered "unknown flag '--help' for spawn" — the worst
kind of gap, because it reads as a typo rather than as a missing feature.
The flag was the symptom: the whole description of every verb was one
126-line string literal inside `usage()` that no test could reach, which
is *how* `update`'s entry above went a release stale. `CommandManifest` is
the 35 verbs as data, and `--help`, `ccc <verb> --help`, `--llms` and
`--schema` all render from it. The drift guards — every dispatched verb in
the manifest, every manifest verb dispatched — found two on their first
run: `focus` and `install-cli` both answer `--json` (it is stripped
globally in `CLI.run`, so every verb accepts it) and neither synopsis said
so.

**Two incur conventions were deliberately not borrowed**, recorded so
nobody re-derives them: `--format toon` pays for itself over thousands of
homogeneous rows and ccc's largest answer is a roster of about thirty; a
`--token-limit` that trims a roster answers a different question than the
one asked, when `--host` and `--archived` are the honest narrowings and
exist. Both earn their place the day an answer here is genuinely large.

### the secrets did not follow a worktree ccc cut

Asked as a doc question — which path honours `.worktreeinclude` — and the
measurement made it a defect. Across cuanto's 22 worktrees, whose
`.worktreeinclude` names `api/config/master.key`: **all 3 that ccc cut
lacked it; 16 of the 19 others had it.** Nothing in the roster, the row or
the spawn's answer distinguished them, so it could only surface as a worker
whose API would not boot.

git does the matching (`ls-files --others --ignored --exclude-from`), so
no pattern language here can drift from gitignore's. One subtraction: a
candidate inside a directory git ignores **by name**. The harness copied
`ts-monorepo/apps/slackbot/.env` and not `…/node_modules/psl/.env`, which
a bare `.env` matches equally. `check-ignore` on each candidate's
ancestors is the exact question; **`ls-files --directory` is not, and was
tried first** — it collapses any wholly-untracked directory, so in a
fixture where `apps/web/.env` was the only thing under `apps/` it reported
`apps/` as ignored and dropped the file the test existed to carry.

Verified against the real repository — a ccc-cut worktree in cuanto, off
`storefront`, removed after:

```
"carried" : [ ".claude/settings.local.json", "api/.env",
              "api/config/master.key", "ts-monorepo/apps/slackbot/.env",
              "ts-monorepo/apps/slackbot/worker-configuration.d.ts" ]
```

Exactly the five the harness puts in its own, and not the node_modules
one. **One thing that probe found and did not fix**: `ccc rm` removed the
session and left the worktree on disk, because ccc cut it and handed the
harness a plain cwd, so the daemon never knew it was a worktree. Cleaning
it took `git worktree remove` and `git branch -D` by hand. That is queue
item 24.

### `claude rc --help` is not a question you can ask from a script

It printed its help and then kept running as the server; the call had to
be killed. `claude rc` is a persistent per-directory server that spawns
sessions from claude.ai/code and the phone — not a flag on a session, and
not what `ccc spawn --rc` does. HARNESS.md carries the paragraph, the two
reasons the user dropped it on 09-04 (not `auto`, and `--spawn worktree`
cuts off the default branch, which is item 18's problem), and an explicit
**unmeasured** on what an rc-spawned session shows in the daemon's roster.

## Cut as v0.1.26 (2026-09-06)

**v0.1.26, build 188**, cut from `worktree-v2` at `f1560dd` — the swarm's
seven findings, at the user's explicit word for the release step.
Notarization `Accepted`, one `<item>`, both CDN keys, the live feed equal
to the zip, the GitHub Release with the zip:

```
live: https://cdn.ramonfabrega.com/ccc/ccc-latest.zip version 188 length 5211774
ota verify --feed ccc  →  ok: … version 188 length 5211774
```

**Step 4 found a defect in step 4.** `scripts/install --dist` answered
`ccc would not quit` while the app was already down. The test was `pgrep -x
ccc`, and every long-running CLI verb carries that process name — what it
found was a `ccc watch --interval 30 --all` belonging to **a different
agent's session**, which the script would have killed had the AppleScript
quit not succeeded first. And the quit *had* succeeded, so the abort left
no app and no new bundle, and would have done so on every retry. Nothing
was half-copied: the guard fires before the `cp`, so this cost a relaunch
and not a repair. It matches the bundle's executable path now, plus "no
argument after it", since a CLI verb runs from the PATH symlink into that
same binary. The other session's watcher survived the second run untouched.

The installed build, and the new surfaces on it:

```
ccc version --json   →  0.1.26, build 188, dev: false
ccc spawn --help     →  ccc spawn (also: new)          [was: unknown flag '--help' for spawn]
ccc --schema         →  35 verbs in the manifest
```

## item 24 — a ccc-cut worktree is ccc's to clean (2026-09-06)

`ccc rm` passed `claude rm` through and the harness deleted the worktree
*it* made. It did not make the ones ccc cuts: `--base` cuts the tree here
and hands the harness a plain cwd, so the daemon never learns there is a
worktree. Measured 2026-09-06 while proving item 23 — `ccc rm 0f7b8c26`
answered `removed`, exit 0, and left the tree, the branch and the
`ccc-base` record on disk. Every ccc-cut worktree on the fleet was in
that state and the count only grew.

**The mark is the whole ownership test.** `createWorktree` now writes
`branch.<b>.ccc-cut = <path>` beside the base it already recorded, and
nothing else writes that key. It is deliberately *not* `ccc-base`:
`ccc base <ref> <branch>` exists to record a base for a worktree cut **by
hand**, and reading that as ownership would let `ccc rm` delete a tree
ccc never made. The record names the path, so a branch whose tree was
replaced under it is no longer ours either. One config parser reads both
keys, and VS Code's `vscode-merge-base` through it.

The cwd is read from the roster **before** the session goes — afterwards
there is no row to ask — and the cleanup runs only when the harness
actually removed the session.

### `git branch -d` asks the wrong question in a worktree fleet

The first real fixture caught it. A tree cut off `trunk` with `master`
checked out, on a branch with **no commits of its own**:

```
said: removed the worktree …/item24; kept the branch worktree-item24:
      error: the branch 'worktree-item24' is not fully merged
```

`-d` measures against the current HEAD, which in this fleet is whatever
the main checkout happens to be sitting on — and item 18's whole point is
that the base is usually *not* the default branch. So the ref the work is
measured against is the recorded base, and the question is git's own
`merge-base --is-ancestor`. A branch fully pushed to `origin/<branch>`
passes too: that is the harness's second word ("unpushed") taken
literally. `-D` then executes what git already answered.

Re-cut off `trunk` and removed, same repository:

```
removed 515329f9; removed the worktree …/item24 and its branch worktree-item24
worktrees: 1   branches: master trunk   on disk: no   records: none
```

And the guard, with one untracked file in the tree — git's sentence, not
ccc's judgment, and the tree still standing afterwards:

```
removed 2f92f0dd; kept …/worktrees/dirty: fatal: '…/dirty' contains
modified or untracked files, use --force to delete it
on disk: yes
```

ccc adds no `--force` anywhere. A kept tree keeps its `ccc-cut` record;
a branch that outlives its tree keeps its `ccc-base` and loses only the
`ccc-cut` that named the tree.

### What the harness does with its own, measured the same hour

Two spawns into the same fixture repo from its default branch, so the
**harness** cut both worktrees:

- **started** (a haiku prompt, run to `done`): `ccc rm` →
  `removed a3a7ddeb\n  worktree: …/worktrees/started`, and the tree was
  gone. The harness names it and cleans it.
- **a draft** (no prompt, `--worktree=draft2`): the harness cut the tree,
  `ccc rm` answered `removed c6a2d081` naming no worktree, **and the tree
  was still there** — twice, and still `locked` by a `claude session`
  lock whose pid was already dead.

So "the harness deletes the worktree it made" holds for a session that
ran and not for one that never started. ccc leaves both alone: without a
record it cannot tell a tree the harness cut for this session from one
the user pointed `--cwd` at by hand. That is queue item 26.

### Across the hop, studio → studio

A ccc-cut tree only exists on the host that cut it (`prepareWorktree`
refuses `--base` for a remote spawn), so a remote `ccc rm` goes through
the far side's own `ccc rm --json` — the shape `fetch` and `pull` already
use — and falls back to the `claude rm` passthrough where a host has no
ccc. Proved on a `selftest` host (`ssh localhost`), a fixture cut off
`trunk`, removed by its remote ref:

```
ccc rm selftest:c50a2d86 --json
  said: removed c50a2d86; removed the worktree …/hoprepo/.claude/worktrees/hop
        and its branch worktree-hop
  worktree: { removed: true, branchDeleted: true }
on disk: no   branches: master trunk
```

An id the far side does not know comes back as its sentence and its
status, not ours: `{"removed": "false", "said": "No job matching
'deadbeef'"}`, exit 1. The host was removed after.

## the vanished descriptor (2026-09-06)

ccc crashed on **air**, v0.1.26 build 188, macOS 15.6.1, at 21:00:56.
Ramon hit Reopen rather than Report and asked whether anything was left
to look at; the `.ips` is written either way, and it named the bug.

```
exception:  EXC_BREAKPOINT (SIGTRAP)
asi:        BUG IN CLIENT OF LIBDISPATCH: Unexpected EV_VANISHED
            (do not destroy random mach ports or file descriptors)
thread 4:   com.apple.libdispatch-io.streamq   << faulting
            _dispatch_source_merge_evt.cold.1 → _dispatch_kq_drain → …
thread 0:   RosterView.menu(for:) → HostConfig.defaultPath.getter
```

**No ccc frame in the crashing thread**, which is the shape of this bug:
the trap fires where a descriptor vanished, never where it was closed.
Thread 0 says what the user was doing — opening a roster row's context
menu — and thread 4 says what actually died.

`EV_VANISHED` means a descriptor a dispatch channel owned was closed by
someone else. ccc creates exactly one `DispatchIO`, in `Subprocess.drain`,
and it was handed the `Pipe`'s own descriptor — with the belief written
down in the comment above it: *"The handle stays open: the `Pipe` owns the
descriptor and closes it."* That is the documented contract inverted.
`DispatchIO` takes ownership of the fd it is given and registers a kqueue
filter on it; the caller must not close it until the cleanup handler runs.
`Pipe`'s `FileHandle` believes the same thing about the same descriptor
and closes it when the `Pipe` deallocates — the moment `Subprocess.run`
returns.

### The window is not rare; the trap is

A pipe drained exactly the way `Subprocess.drain` drains a child's
stdout, asking one question — had the channel run its cleanup handler by
the time the read finished?

```
count: 300 drains, channel still held the fd at resume in 257
```

**86%.** Every one of those closes a descriptor the channel still owns.
What decides whether it traps is the kqueue's state at that instant, and
a close landing while a read is still armed is the case that does:

```
./pending old 40   →  exit 133 (SIGTRAP), 4 runs out of 4
```

whose crash report carries air's diagnostic byte for byte —
`BUG IN CLIENT OF LIBDISPATCH: Unexpected EV_VANISHED`, EXC_BREAKPOINT,
`libdispatch-io.streamq`. This reproduces the **mechanism**; the exact
scheduling that armed the knote on air is not pinned down, and does not
need to be, because the contract violation is the bug either way.

### The fix, and what it must not change

`dup` the descriptor for the channel and close the copy in the cleanup
handler. The channel owns its copy, the `Pipe` owns the original, and
neither can close the other's out from under it.

```
./pending dup 40   →  survived, 3 runs out of 3
```

A copy of a pipe read end sees the same stream and the same EOF, and
`theDupSeesTheWholeStreamAndItsEnd` holds that: 200 concurrent children,
100 KB each on stdout and a distinct stderr, all byte-exact. Nothing here
can catch the crash itself — a trap inside libdispatch takes the test
runner with it — so what the suite holds is the behaviour the `dup` must
not cost.

**Why air and not studio.** Nothing about air is special except its work:
it polls a remote host over ssh, so every tick is a subprocess with two
of these channels, and `stop()` and `tick(fresh:)` both cancel polls
mid-flight. Studio polls locally. The same code was on both.

## Cut as v0.1.27 (2026-09-06)

**v0.1.27, build 194**, cut from `worktree-v2` at `19abf5e`, at the
user's word — **a crash fix for air, so the cut is the instrument and not
the delivery**. The ad-hoc pass first (it caught nothing, which is the
point of running it before burning a notarization), then notarization
`Accepted`, one `<item>`, both CDN keys, the live feed equal to the zip,
and the GitHub Release with the zip attached:

```
spctl -a --type execute  →  accepted, Notarized Developer ID
live: https://cdn.ramonfabrega.com/ccc/ccc-latest.zip version 194 length 5236205
ota verify --feed ccc    →  ok: … version 194 length 5236205
gh release view v0.1.27  →  {"assets":["ccc-v0.1.27.zip"], "tag":"v0.1.27"}
```

Studio on the released bytes, and the fixed drain under its own load —
every one of those polls is two `DispatchIO` channels on descriptors that
are now the channels' own:

```
ccc version --json  →  0.1.27, build 194, dev: false
ccc stats           →  roster poll  last 168 ms  mean 197 ms  n=10
```

**What air must report, and until it does this is unproved.** The bug was
air's and studio was immune by accident (studio polls locally; air polls a
remote host over ssh, so it runs two of these channels per tick and
cancels polls mid-flight). The sentence air owes is: **on build 194, no
new `ccc-*.ips` carrying `EV_VANISHED` in
`~/Library/Logs/DiagnosticReports`** after ordinary use — roster open,
context menus, a lid night. Studio's clean run above is the **control**,
not the measurement.

This cut also carries item 24 (`ccc rm` cleans the worktrees ccc cut),
which studio has already proved on its own fixtures.

## item 27 — a commander clears its own context (2026-09-06)

The two boots the item asked for, on a `--model haiku` fixture spawned
for them (`clear-boot`, `7d6dd493`, in a throwaway folder), driven the
way the verb drives: `ccc attach … --headless` on a private socket
(`CCC_CONTROL_SOCKET`) so the app's pane on screen was never touched,
then `ccc send` and `ccc snapshot`.

### A typed `/clear` on an idle background session is a real clear

`ccc send "/clear"` opens the slash menu (`/clear` is its first row,
`Start a new session with empty context`), and `ccc send --key enter`
runs it: the transcript went blank and the footer's context meter — `40k
(4%)` — disappeared entirely. A prompt typed after it lands and runs with
nothing behind it:

```
❯ Without using any tool …: what codeword string did you write into marker.txt earlier?
⏺ This is the start of our conversation — I haven't written anything to marker.txt in this session.
```

### The box's contents are prefixed onto what we type

The finding that shaped the verb. With `ZZ` sitting unsent in the prompt
box, `ccc send "/clear"` + enter submitted **`ZZ/clear` as a prompt**.
There was no clear — the context meter went *up*, 34k → 40k — and the
model answered "Conversation cleared. Ready for new tasks.", a false
clear that reads exactly like a real one at a glance.

So anything that types has to know whether the box is anybody's. It
cannot be read from the text: the harness draws a history hint there
(`❯ cat marker.txt` appeared twice unprompted) and `LeaveGesture` already
records that "the grid cannot tell [a placeholder] from a draft". **The
cursor tells them apart.** Measured on the same pane:

| box | `end` then cursor | `ctrl-u` | first character typed |
|---|---|---|---|
| hint `cat marker.txt` | stays at col 2 | no effect | replaces the whole hint |
| draft `hello` | moves to col 7 | empties the box | appends |

That is `PromptBox.read`, and it is why `end` is pressed before the read.
`ask` (`ccc update --ask`) had the same hazard and now goes through the
same guard.

### A mid-turn `/clear` discards the running turn

Typed while the fixture was generating (`state: blocked`, `tempo:
active`), the clear took effect at once: the transcript emptied, the
context meter went, and the turn's output never arrived. No error, no
trace. That is what the idle gate is for — not politeness.

`tempo: idle` is not "the turn ended" in general: a session that
backgrounds a shell (`sleep 40`) reads `working` / `idle` with the shell
still running. It is the right gate for typing anyway — the box is free —
but nothing else should read that word as "finished".

### What the row shows across a clear

`~/.claude/jobs/7d6dd493/state.json` and `ccc list --json`, before → after:

| field | across the clear |
|---|---|
| roster `session.sessionId` | **changes** (`7d6dd493-…` → `f26b6dcf-…`, and again on the next clear) |
| state.json `sessionId` | stays at the original |
| state.json `resumeSessionId`, `linkScanPath` | follow the new one |
| `id` / `daemonShort`, `pid`, `name`, `nameSource` | unchanged |
| `respawnFlags` | unchanged (`--name clear-boot --model haiku --permission-mode default`) |
| `bridgeSessionId` | unchanged — messaging and lore key on the job, so a clear is invisible to them |
| `state`, `tempo` | unchanged (`done` / `idle`) |
| `detail`, `result` | **stale** — they still describe the pre-clear work until the next turn overwrites them |

The last row is the one that costs something: for a few minutes after a
clear the roster's `↳` line is a lie, and a stall detector reading it
sees a session that "has not moved".

The uuid change is what the overlay's mark guard already handles: a
pending clear records the uuid the row had when it was armed, so it can
never fire on the session that follows the one it was armed on.

### The verb, end to end

`ccc clear <ref> [--then "<prompt>"]` arms; the pane fires it. Proved on
the same fixture with the dev build owning the pane
(`ccc attach 7d6dd493 --headless`, private socket and overlay), armed
**while the row was busy** — the commander's own case:

```
ccc clear 7d6dd493 --then "…what did you just write into ledger.txt? …"
  → armed a clear on 7d6dd493; it fires when the row is idle, then: …
ccc list        → 7d6dd493  working  busy    (nothing fires)
ccc list        → 7d6dd493  blocked  wait    (a permission prompt; still nothing)
  … the prompt answered, the turn ends …
ccc: cleared 7d6dd493, then: In one short line: what did you just write …
```

and the pane afterwards, which is the whole item in six lines:

```
 ▐▛███▛█   Claude Code v2.1.260
❯ /clear
❯ In one short line: what did you just write into ledger.txt? …
⏺ NO MEMORY.
```

The `blocked` tick is the gate earning its place: a session holding a
permission question up has a dialog under the cursor, not a prompt box.

**A person's unsent draft stops it.** With `half a thought I have not
sent` left in the box and a clear armed:

```
ccc: the clear on 7d6dd493 did not fire: 7d6dd493 has unsent text in its
     prompt box ("half a thought I have not sent"); typing would submit it with ours
```

— the box untouched, the mark dropped rather than left waiting for the
person to walk away and come back. Twice during these runs the harness
drew a history hint in the box (`cat marker.txt`, `read ledger.txt`) and
the same guard typed straight through it, which is the whole reason the
reading is the cursor's and not the text's.

Across the two clears the row held everything but its uuid: `id`
7d6dd493 and `pid` 12442 unchanged, `sessionId` 1062c451 → 07820e10.

## Cut as v0.1.28 (2026-09-06)

Item 27's verb, released the night it was built. `spctl` accepted, one
`<item>`, both CDN keys, the live feed equal to the zip, and the GitHub
Release with the zip attached:

```
spctl -a --type execute  →  accepted, Notarized Developer ID
live: https://cdn.ramonfabrega.com/ccc/ccc-latest.zip version 197 length 5287578
ota verify --feed ccc    →  ok: … version 197 length 5287578
gh release view v0.1.28  →  {"assets":["ccc-v0.1.28.zip"], "tag":"v0.1.28"}
```

Studio on the released bytes, and the verb answering from them:

```
ccc version --json  →  0.1.28, build 197, dev: false
ccc stats           →  roster poll  last 173 ms  mean 211 ms  n=4
ccc help clear      →  ccc clear <ref> [--then "<prompt>"] [--json]
```

**The app fires it, not only the dev binary.** The build proof ran
against a headless `ccc attach` holding the pane; a released bundle has a
window and its own launch path, so the same fixture was run once more
with nothing but the installed app up — spawn a haiku session, arm a
clear on it from the shell, and watch:

```
ccc clear 6c3fe676 --then "…what were you asked to say when this session started? …"
ccc clear   →  6c3fe676  armed 0s ago · then: …
  … the app's own tick fires it; the mark is gone from the overlay …
❯ /clear
❯ In one line: what were you asked to say when this session started? …
⏺ NO MEMORY.
```

Nothing here is owed to air: `clear` is a studio-side verb — it types
into a pane on the Mac the session lives on — and air's copy of it will
be exercised the first time air arms one across the hop, which is the
remote road (`ssh … ccc clear <id>`) and is **unmeasured**.

## item 27 — the gate read the wrong field (2026-09-06)

`ccc clear` shipped in v0.1.28 reading the roster's `status` for "is this
row idle". Within the hour the first real user armed one and it never
fired. attrition's commander, and lore's beside it as the control — same
Remote Control, everything else alike:

```
attrition 3c382923   roster: state=done    status=busy   rc=true
                     job:    tempo=idle    inFlight={tasks:3, kinds:[monitor, local_bash]}
lore      a18a763f   roster: state=working status=idle   rc=true
                     job:    tempo=idle    inFlight={tasks:0, kinds:[]}
```

The difference is `inFlight`, and `busy` there is **true, not stale**. The
two words answer different questions: the daemon's `status` is *something
live is attached to this session*, background tasks included; `tempo` is
*the model's turn is generating*. A commander holding a persistent
Monitor is `busy` for as long as it holds it — which is forever, by
design — so the gate as shipped made the verb **useless to exactly the
loop it was built for**, and not late: never.

The three in-flight tasks were `ccc watch --json --all`, the 60 s `ccc
list --json` sampler and a `--stall 10` watch: the item 25 capture asked
for an hour earlier in the same conversation. **The advice armed the
trap.** attrition could not have found it from their side — they read the
non-firing as "the tick never sampled the row idle because the user kept
typing", which is plausible and would have survived several attempts.

So `JobProbe` carries `tempo` as a seventh field out of a file it already
opens every tick, and `ClearWindow` prefers it, falling back to `status`
where a reading has none — a row from a ccc across the hop that predates
the field, which then behaves as it did before: never firing early, only
waiting too long. `blocked` still comes from the roster, which is the
right source for both its shapes (a permission dialog, and a session that
ended its turn by asking something, which has not finished).

### Why there is no `--after-tasks`, in the first user's words

Firing with background work live is deliberate. Asked whether a clear
should wait for `inFlight.tasks == 0`, attrition argued against building
the flag at all, and the argument is better than the question:

> Not all background tasks are equal: my Monitor and samplers are
> **ambient**, but a `run_in_background` `cargo test --release` gate is
> **load-bearing** … A clear firing mid-gate would hand the fresh context
> a bare "exit code 0" for a merge it has no memory of making. That is
> genuinely bad. But it is bad in a way **only the caller can prevent**,
> because you cannot tell them apart: both surface as `local_bash`.

Their own clear-boundary rule — *arm only when the gate is green and
pushed* — leaves nothing but ambient tasks live at arm time by
construction. The discipline belongs where the knowledge is; a flag out
here could not see the difference, and "a flag that exists gets used" to
paper over arming at the wrong moment. If a second user needs it,
opt-in is the shape.

### What v0.1.28 cost its first user, stated plainly

> On 0.1.28 there is no configuration under which I can both run your
> data streams and use the verb.

The two things shipped that evening were mutually exclusive for the one
user they were both built for. That is the cost of a gate read from the
nearest field rather than the right one.

## Cut as v0.1.29 (2026-09-06)

The gate fix, an hour behind the verb it fixes. `spctl` accepted, both
CDN keys, the live feed equal to the zip, the Release with the zip:

```
live: https://cdn.ramonfabrega.com/ccc/ccc-latest.zip version 200 length 5289296
ota verify --feed ccc    →  ok: … version 200 length 5289296
gh release view v0.1.29  →  {"assets":["ccc-v0.1.29.zip"], "tag":"v0.1.29"}
ccc version              →  ccc 0.1.29 (200)
```

`tempo` reaches the row, on the two live sessions the bug was found on:

```
attrition roster: state=working  status=busy    job: tempo=active
lore      roster: state=working  status=idle    job: tempo=idle
```

**And the shape that was unclearable is clearable.** attrition was
genuinely generating by then, so the regression was rebuilt on a fixture
instead: a haiku session told to start `sleep 600` in the background and
stop, which parks it in exactly the state v0.1.28 could never clear —

```
roster: state=done status=busy   job: tempo=idle
inFlight = {'tasks': 1, 'kinds': ['local_bash']}
```

Armed at 23:08:49, **fired at 23:08:54** — one poll tick, where the old
build would have waited on `status` until the `sleep` ended ten minutes
later, and forever for a Monitor:

```
❯ /clear
❯ In one line: what command did you start in the background? …
⏺ NO MEMORY
```

The background task is still in flight afterwards (`inFlight` unchanged),
which is the deliberate half: the turn was over, the box was free, and
the `sleep` outlives the context that started it.

## what a clear does to background work (2026-09-07)

Half of it is settled and the open half is item 25's problem, so both
halves are here and the queue carries only the question.

**A `local_bash` task survives a clear.** v0.1.29's fixture held a
backgrounded `sleep 600`; its job file read `inFlight = {tasks: 1, kinds:
['local_bash']}` before the clear and the same after, and the `pid` holds
either side (12442 across both of the boots' clears). A clear resets the
conversation, not the process.

**And so does a Monitor**, which was the half that mattered — item 25's
evidence stream is one, owned by a commander that will clear itself. The
measurement arrived by accident, from a clear the commander's user typed
by hand: current transcript's first record **04:02:27Z**, against
04:02:02Z for the pre-clear one's last, and the Monitor's output file
`watch.jsonl` carrying an mtime of **04:10:17Z** — eight minutes on the
far side. Tracked *and* writing, which is the distinction a `sleep` that
writes nothing could never have shown.

Confirmed a second time the same night, with byte deltas rather than one
mtime — a steering clear at 06:08:17Z → 06:10:56Z, all three streams
growing across it and `inFlight` identical on both sides (`tasks: 3`,
`kinds: ['monitor', 'local_bash']`, `drainableMonitors: 0`):

```
list.jsonl           3,244,251 → 3,303,290
watch.jsonl (Monitor)   17,957 →    18,373
watch-stall10.jsonl     20,261 →    20,677
```

Both readings are the **hand-typed** clear. What that leaves is free
rather than open: the same reading under `ccc clear`'s keystrokes rather
than a human's. The two are the same operation
by construction — the verb presses `end`, reads the box, types `/clear`
and presses enter, and there is no other path into that TUI — so the
prior is "survives", not "unmeasured".

**The instrument has a control in it, unplanned.** Both `ccc watch`
streams there are the same command shape under different task kinds —
one a Monitor writing `watch.jsonl`, one a background shell writing
`watch-stall10.jsonl` — the residue of wiring the streams up three times.
So if `watch.jsonl` alone goes quiet across the next armed fire while the
other two keep growing, that is the monitor dying and nothing else, with
no inference in between.

### `kinds` discriminates, and `drainableMonitors` is a state

Both fell out of two live rows sitting next to each other, 2026-09-07,
when a peer read `kinds: ['monitor', 'local_bash']` on a session it
believed held only background shells and reasonably doubted the field —
either it is a union that outlives its last member, or the harness files
a shell as a monitor:

```
ccc        tasks=4  kinds=['local_bash']              drainable=0
attrition  tasks=3  kinds=['monitor', 'local_bash']   drainable=0
```

Four background Bash jobs and no Monitor tool call in that session's
life, against three tasks carrying a `monitor`. So **`kinds`
discriminates rather than accumulates** — a union that outlived anything
would have shown one on the four-shell row — and a shell never counts as
a monitor. The v0.1.29 fixture agrees at n=1: one backgrounded sleep,
`['local_bash']` alone.

And `drainableMonitors: 0` sat beside that live monitor, so it counts
**monitors with output waiting to be drained**, not monitors. Zero is
never "no monitors". Two fields, two questions, separable only because
two rows were readable side by side.

The consequence is that the open question above is live rather than
hypothetical: the commander that will clear itself really is holding a
Monitor.

## a guard a commander leans on gets a manifest and a fixture (2026-09-07)

From lore, generalising two wrong-tool incidents in one week across two
repos. Both were **bash guards with no fixture**.

Ours: `scripts/install`'s `pgrep -x ccc`, which matched another job's
`ccc watch` and quit a peer's process — the app and the CLI are one
binary, so a process name is not app identity, and the fix was to match
the bundle path. attrition's: a 2 s RSS poll with `kill -9` and zero
tests, which its commander leans on hardest of anything it owns.

The pattern, stated so it is checkable rather than felt: **a guard a
commander depends on gets a manifest — `--json`, and an exit 1 refusal
naming its way out — and a fixture it is run against, never a live row.**
The manifest is what makes the guard's answer readable by the agent that
depends on it; the fixture is what keeps the guard honest when the thing
it matches changes shape. `ccc`'s own verbs have had both since item 22
(`CommandManifest`) and the fan-out rules; its *scripts* have neither,
and `scripts/install` is the one a commander touches.

Related and already recorded: a spawner test must own its fixture rather
than race a live roster row (`prove-guards-on-owned-fixtures`).

## the suite's own deadlock (2026-09-07)

The suite wedged four times in one evening and every diagnosis before the
last one was wrong: machine load, then concurrent `swift test` runs
(which was real and mine, and hid this), then a hanging shell test (which
passes alone in 0.06 s). `sample` on the parked process named it in one
read:

```
Git.Drain.data.getter  (in cccPackageTests)  Worktree.swift:1128
  semaphore_wait_trap  (in libsystem_kernel.dylib)
```

— on **nine** threads at once, across `ClearTests`, `BaseTests`,
`BaseTipTests` and `CutWorktreeTests`.

**The mechanism.** Every `Git.run` builds a `Drain` per pipe, and each
`Drain` occupies a `DispatchQueue.global(qos: .utility)` thread for the
whole life of the child while its caller blocks on the drain's semaphore.
So one `git status` costs two threads that cannot make progress without a
third. swift-testing runs suites in parallel; enough concurrent
`Git.run`s and libdispatch's global pool is exhausted by the waiters,
and nothing can ever signal.

Measured: `swift test --no-parallel` runs **510 tests in 20.7 s** on the
same loaded machine that could not finish the parallel run at all.

**Two fixes, and only one of them landed.** Mine first: `ClearTests` was
the suite's only *async* test calling synchronous `Git.run` inline, which
parks a thread of the cooperative pool rather than a plain one — strictly
worse, and new that night. It goes through `Task.detached` now, the way
the production callers already did. The same audit found the same shape
in shipped code: `PaneController.fireArmedClears` ran the fire-time
`git status` on the `@MainActor`, where `merge`, `push`, `update` and
`fetch` all use `Task.detached`. Fixed with them.

**And the wall time says not to split the suite.** Measured at lore's
ask: 20.05 s serial for 510 tests, with 432 of them under 50 ms summing
to 0.95 s and 78 fixture tests taking 95% of the rest — no long pole (the
slowest single test is 1.33 s), just process-spawning tests that earn
their cost. A fast lane would save 19 s and buy a second command to
remember and a "it passed the fast lane" class of mistake, which is the
shape of the wrong-tool incidents above. The suite is not slow; its
*default* mode cannot finish, which is a different complaint.

Neither is the root, which is `Git.Drain`'s two-threads-per-call shape.
That is queue item 30, and production is nowhere near the limit — the
poller probes serially and a verb is one call — so the cost today is a
suite that cannot be trusted on a loaded Mac, which is a guard nobody
has rather than a bug anybody sees.

## the stall stream's first run (2026-09-07)

Item 25 was gated on a count — this fleet's rule: measure how often the
fixed window was *useful* before replacing it. attrition ran the capture
through a full commander loop (ten landings, two workers at width two, a
~256 s release gate, sessions living 5–40 minutes) with three streams:
`ccc watch --json --all` as a Monitor, a second watch at `--stall 10` as
a shell, and a 60 s `ccc list --json` sampler.

**Zero `stalled` events in the whole run**, at either window. And in the
same run **three sessions finished quietly** — `loop-239`, `loop-249`,
`loop-252` — every one found by the user eyeballing the roster, none by a
watch.

So the constant was never the problem. **A timer cannot catch a finished
session at any duration**: it is not stalled, it is done and mislabelled,
which is a different detector, not a longer timeout. The cadence-relative
window item 25 proposed would have measured the same nothing more
precisely.

**The two signals fail together, which is the worst shape.** `loop-252`'s
row read *"shutdown assertions failing; 5 tests need fix"* — a mid-work
note — while the job had finished, gated green and pushed. State and `↳`
went stale in the same direction, so the pair agreed with each other and
a reader had no contradiction to notice.

What answered was the **branch tip**: `.git/worktrees/<name>/HEAD`, and
`HEAD..origin/<branch>` for whether anything was unmerged. ccc already
reads exactly that every tick — it is where the ⇡⇣ marks come from — so
the detector is a join it can already make and does not draw.

Reported by attrition on its way into a Fable steering pass, with the
verdicts in its own `verdicts.txt`. Its other note from the same run:
0.1.29's gate held all night across four landings driven by `ccc update`
and `ccc rm`.

## item 17 — the roster says nothing about `--rc`, and the wrong thing about `auto` (2026-09-07)

The open half of item 17's title: *what an `--rc`-spawned session actually
shows in the daemon's roster versus a plain one*. Eight fixtures in a
throwaway cwd (`$CLAUDE_JOB_DIR/tmp/rcfix`, 2.1.260, ccc 0.1.29), all
`--model haiku` except where the point was to omit it, all removed with
`claude stop` + `claude rm` — `claude agents --json --all | grep -c rcfix`
answered `0`.

### The row is identical, and `respawnFlags` really is the only signal

`ccc-rcfix-c1` (plain) and `ccc-rcfix-c2` (`--rc`), same cwd, same prompt,
same model, both `done`:

```
KEYS EQUAL: True
DIFFERING KEYS: ['id', 'name', 'pid', 'sessionId', 'startedAt']
```

Nine keys — `cwd id kind name pid sessionId startedAt state status` — and
every one that is not identity is equal. `kind` is `background` for both;
there is no `remote`, no `bridge`, no flag. The same held for the `blocked`
row and for `state.json`'s key set, which is character-for-character the
same list on both sides.

So `JobProbe.remoteControl` reading `respawnFlags` is not a choice among
sources, it is **the only source**, and that is now measured rather than
assumed. Two near-misses ruled out by the same pair: `bridgeSessionId` is
present on the plain session too (`cse_01QTSRrzsRTkHB2dd3dNyDG3`), and
`bridgeOutboundOnly` is `false` on both — neither discriminates, and a
future reader reaching for the obviously-named field would be wrong.

**One signal exists outside `respawnFlags`, and ccc does not read it.** The
RC session's transcript carries a record the plain one does not:

```json
{"type":"system","subtype":"bridge_status",
 "content":"/remote-control is active · Continue here, on your phone, or at https://claude.ai/code/session_01DtyjcMERthj8PVH2HX2bi8",
 "url":"https://claude.ai/code/session_01DtyjcMERthj8PVH2HX2bi8"}
```

It carries payload the row does not have — the **deep link** — and it is
the far side's own word rather than an inference from a launch flag. It is
not a reason to move the badge (a transcript tail read per tick is a cost
the job file is not), but a "open on claude.ai" item on a row that already
knows it is `rc` is one join away, and `bridgeSessionId` in `state.json` is
the same id without the read.

### `ccc spawn --rc "<prompt>"` silently loses the prompt

Found by looking at the fixture rather than at the code. The `--rc` spawn
came back a **draft**:

```
backgrounded · 22f6d203 · ccc-rcfix-rc (idle — send a prompt to start)
```

`state.json` says `intent: ""`, `state: working`, `tempo: blocked`, `needs:
"send a prompt to start"`; the roster says `blocked`; `ccc list` draws it
`draft`. The prompt is not in the job file, not in the transcript, and not
in `respawnFlags` — it is gone with no error.

The cause is in `claude --help`:

```
--remote-control [name]    Start an interactive session with Remote
                           Control enabled (optionally named)
```

**An optional value.** `Spawn.claudeArguments` emits `--rc` as the last
flag, immediately before the positional prompt, so the prompt is parsed as
the RC session name and the session starts with nothing to do. The control
is `ccc-rcfix-c2`, the same command with `--rc` moved one flag earlier:

```
claude --bg --name ccc-rcfix-c2 --model haiku --rc --permission-mode auto '…'
→ state done, intent = the prompt, output.result = "ok", bridge_status present
```

RC still activates in both cases; only the prompt is lost. So the box item
17 says exists has never carried a prompt, and "whether `--rc` should be
the default" was a question about a flag that made every spawn a draft.

### `respawnFlags` is resolved, not echoed — and it writes `auto` as `default`

Six fixtures, typed order on the left, what `state.json` recorded on the
right:

| typed | `respawnFlags` | transcript `permission-mode` |
| --- | --- | --- |
| `--name c1 --model haiku --permission-mode auto` | `--name c1 --model haiku --permission-mode default` | `auto` |
| `--name c2 --model haiku --rc --permission-mode auto` | `--name c2 --rc --model haiku --permission-mode default` | `auto` |
| `--name c3 --model haiku --permission-mode acceptEdits` | `--name c3 --permission-mode acceptEdits --model haiku` | `acceptEdits` |
| `--name c4 --permission-mode auto --model haiku` | `--name c4 --model haiku --permission-mode default` | `auto` |
| `--name c5 --permission-mode auto` *(no model)* | `--name c5 --permission-mode auto --model opus[1m]` | `auto` |
| `ccc spawn --name c7` *(no model)* | `--name c7 --permission-mode auto --model opus[1m]` | `auto` |

Three things at once. The **order is reconstructed** (c4 typed the mode
before the model and got it back after). The **model is filled in** when
none was passed (`opus[1m]`, the ambient default). And `auto` came back as
`default` in all four spawns that named a model, while surviving in both
that did not — `acceptEdits` was never touched, so it is the value `auto`
that is rewritten, not the field.

**That reading of the condition was wrong, and lore caught it the same
night.** Building a fixture for its harness corpus, lore could not
reproduce the rewrite on any of the 20 live jobs on 2.1.260 that name a
`--model` — every one still carried the typed `auto`. It is not "a model
was named"; it is **which** model, and every fixture above was `--model
haiku` because this fleet's rule is that test spawns run on haiku:

| `--model` | `respawnFlags` permission-mode |
| --- | --- |
| `haiku` | `default` |
| `claude-haiku-4-5-20251001` | `default` |
| `sonnet` | `auto` |
| `opus` | `auto` |

So `auto` is downgraded to `default` on **Haiku 4.5 and nowhere else** —
consistent with `auto` being a mode Haiku does not serve, resolved at
init. The correction matters in both directions: it makes the rewrite
almost invisible in production, since real workers run opus or fable, and
it means the fleet's own test-spawn convention is what made it look
universal. Four fixtures either way; the matrix is the claim, and
`default` is not even one of `--permission-mode`'s own documented
choices.

The transcript is the truth and says so plainly:

```json
{"type":"permission-mode","permissionMode":"auto","sessionId":"e4143163-…"}
```

**What it costs ccc.** `JobProbe.asksForPermission` is `permissionMode not
in {auto, bypassPermissions}`, so any spawn whose `auto` was rewritten —
every haiku one, which is every fixture this fleet makes — reports "this
one will stop at its first prompt" about a session on `auto`. That
is the `asks` column in `ccc list` and the ❓ badge in the window, whose
tooltip reads *"Launched --permission-mode default … `ccc spawn` defaults
to auto"*: it contradicts itself in one line.

**The rate, per the house rule.** Against the live roster (18 rows, this
session's fixtures excluded), comparing the badge's answer to the last
`permission-mode` record in each session's transcript:

```
live rows compared: 18; `asks` drawn but session is on auto/bypass: 12
```

Twelve wrong, **zero right**, one unjudgeable (`attrition`, no such record
in the current transcript), five correctly silent. And the twelve fail for
a *second* independent reason, and it is the one that actually carries the
count: none of them carries `--permission-mode` in
`respawnFlags` at all — they were not spawned by ccc — and `permissionMode`
returning `nil` reads as "asks" while all twelve transcripts say `auto`. So
the mark has two causes to be wrong and, on this roster, no case where it
is right. By the v11 rule (every line carries payload or is not drawn) it
is worse than absent: it is drawn on most rows and says the opposite of
what is true.

**Fixed the same night, at the user's word that the fleet runs `auto`
always.** `asksForPermission` now marks only `plan`, `manual` and
`acceptEdits` — the values `respawnFlags` cannot have rewritten into place
— and says nothing about `default` or about a missing flag. The haiku
correction narrows one of its two reasons and removes neither: the twelve
wrong rows were wrong because **absent** does not mean asks, which no
model condition touches. That takes the
count to 0 wrong, and its price is that a deliberate `--permission-mode
default` is now invisible: the source that would see one is the
transcript's last `permission-mode` record, which is a tail read per tick
and stays a leftover in queue item 5 until a non-`auto` worker is ordinary
here.

**When the rewrite happens**, from the one fixture that never got that
far: `ccc spawn --worktree "<prompt>"` failed `exit 1 before init`, and
*its* `respawnFlags` kept the `--permission-mode auto` ccc typed, in the
order ccc typed it, with no `--model` invented. So `respawnFlags` is
written at dispatch as given and **rewritten once the session
initializes** — which is also why a job that has been respawned since an
older CLI still carries the older array.

### The fix, and the fixture that proves it

`Spawn.claudeArguments` now emits `--rc` and `--worktree` before
`--permission-mode`, which is always present and always carries a value,
so no optional-value flag can ever be the last word before the prompt.
`SpawnRequest.optionalValueFlags` names the two, and
`anOptionalValueFlagNeverStandsBeforeThePrompt` walks the 24 combinations
of `rc × worktree × effort × model`; on the shipped order it fails **12**
of them.

End to end on the built binary, same shape as the fixture that failed:

```
.build/debug/ccc spawn --name ccc-rcfix-fixed --model haiku --rc 'Reply with … ok …'
→ draft: false; state done, intent = the prompt, output.result = "ok",
  respawnFlags ["--name","ccc-rcfix-fixed","--rc","--model","haiku",…],
  bridge_status present
```

Every fixture in this section was removed with `claude stop` + `claude rm`
and its cwd deleted; `claude agents --json --all | grep -c rcfix` answers
`0`.

## item 17 — the phone buzzes for everything, ccc's pane included (2026-09-07)

The user's half, run the same night as the roster half and answered by the
user watching his phone. Four `--rc` haiku fixtures in a throwaway cwd,
each given one job — *use `AskUserQuestion` to ask red or blue and wait* —
so each lands in `blocked` with a real "your turn".

Round 1, the baseline: two of them, **neither attached**, blocked within
seconds of each other. Round 2, the variable: one spawned as an `--rc`
**draft**, `ccc attach`ed *first* so ccc held it before it ever ran, then
started through the pane with `ccc send` + `--key enter`; the second
spawned with the prompt inline and never attached. Both blocked at
01:38:11, one with `attached: true` and one with `attached: false`,
otherwise identical.

**All four buzzed** — the user's words, unprompted: *"yeah im getting all
of em!!"*. So a ccc pane holding a session does not suppress its push, and
the ordering was controlled for: `ccc-push-held2` was attached before its
first turn, not after it blocked.

**That closes the slice-2 worry and inverts slice 3's premise.** Nothing
is being over-suppressed any more; the complaint available now is the
opposite one — the phone buzzes for a session the user is *watching on the
Mac*, which is exactly what `CLAUDE_CLIENT_PRESENCE_FILE` exists to stop.
The gate on slice 3 was "only if slice 2 was not enough", and the measured
answer is that it was enough for the direction it fixed and leaves the
other direction wide open. Whether that is a bug or the right default is
the user's call, and the "idle time, not the lock" note still holds: on an
always-on studio, "unlocked" would suppress push all day.

Fixtures removed with `claude stop` + `claude rm`, the throwaway cwd
deleted, and the pane put back on the session it was holding before
(`ccc attach a18a763f`, which `attach` had left on the way in).

## Cut as v0.1.30 (2026-09-07)

Item 17's two fixes, the night they were measured. `spctl` accepted, both
CDN keys, the live feed equal to the zip, the Release with the zip:

```
live: https://cdn.ramonfabrega.com/ccc/ccc-latest.zip version 212 length 5293918
ota verify --feed ccc    →  ok: … version 212 length 5293918
gh release view v0.1.30  →  {"assets":["ccc-v0.1.30.zip"], "tag":"v0.1.30"}
ccc version              →  ccc 0.1.30 (212)
ccc stats                →  ccc 0.1.30 (212)  pid 39758
```

**Both fixes proved on the released bytes, not the debug build** — the
house rule that studio green is the control, applied to studio itself.
One `--rc` fixture through the installed binary:

```
ccc spawn --name ccc-release-check --model haiku --rc 'Reply with … ok …'
→ draft: false; state done, intent = the prompt, output.result = "ok"
ccc list → 4bb68e68  done  idle  rc       ccc-release-check  haiku-4-5-
```

`rc` on the row and **no `asks`** beside it: the prompt survives the flag
that used to eat it, and the mark that was wrong on twelve of eighteen
rows is silent on a roster that is entirely `auto`. Fixture removed.

## item 17 closes: two decisions, and the flag whose default flipped (2026-09-07)

Both unmeasured halves answered the same night, so what was left was the
user's to decide, and he did — in the same message that asked whether
anything else was owed.

**Remote Control is on by default.** `ccc spawn` passes `--rc` unless
`--no-rc` refuses it, so every worker is answerable from the Claude app
rather than only from the Mac it runs on. The question had been open since
the box was built and was **never really askable**: until that morning the
flag ate the prompt and made every spawn it touched a draft, so nobody had
used it enough to have an opinion. The default lives on `SpawnRequest`
beside `defaultPermissionMode`, which is what gives the New Session sheet
the same behaviour without a control — the sheet leaves `rc` nil the way
it leaves the mode nil, and its own contract already says the flags it
omits are the command's alone. `remoteControlIsOnUnlessRefused` pins it in
both directions.

The `rc` column inverts with it: on a roster where every ccc-spawned row
carries the mark, the row **without** one is the row that carries news, so
`ccc list`'s help now says that rather than describing the mark. The cost
is stated where it belongs — an RC session registers with the API and its
transcript lives on Anthropic servers while connected — and `--no-rc` is
the opt-out that makes it a choice.

**Slice 3 is dropped, not deferred.** `CLAUDE_CLIENT_PRESENCE_FILE` existed
to stop the phone buzzing for a session the user is watching on the Mac,
and the measurement that made that case buildable is the one that killed
it: the user's answer to *"is that a bug or the right default"* was that
the buzz is fine. So item 17 leaves the queue whole rather than keeping a
gated slice, and v13's frontier moves to item 25.

## the ref that was only an id (2026-09-07)

Reported by lore, measured on itself at ~06:21Z: `ccc clear lore` answered

```
ccc: no session 'lore' in the roster
```

in the same second `ccc list --json` drew the row (`a18a763f`, name
`lore`, state `working`), while `ccc clear a18a763f` armed and fired.

**The split is not `clear`'s, it is the verb list's.** Every lookup ccc
performs itself matched `$0.id == id` — `clear`, `archive`/`pin`,
`merge`, `base`, `push`, `update`, `localWorktree`, and `rm`'s cwd read,
eight sites — while `stop`, `send` and `attach` hand the ref to `claude`
and got name resolution from the harness for free. Half the verb list took
a name and half did not, and the manifest's own `<ref> is …` convention
described the half that worked. That is `docs/DESIGN.md` §9's rule
arriving as a defect for the second time: *a verb with fewer surfaces than
its opposite will be reported missing* — and it was, by a peer, not by the
user.

One resolver now answers all eight (`Collection<Session>.session(matching:)`).
**The id wins over the name**, always: an id is minted unique and a name is
not, so a name shaped like another row's id can never shadow the row it
names. **An ambiguous name is named, not guessed at** — `ccc spawn`
refuses a duplicate live name but `--allow-duplicate` means it, so two
rows under one name is a real state, and picking one would clear, archive
or merge the wrong session:

```
'worker' is the name of 2 live sessions (a1b2c3d4, e5f6a7b8); use an id
```

The three now-unreachable `noSuchSession` cases went with it — the same
sentence had been written four times, and a string with no reader is a
string nothing keeps true. `RefLookupTests` is five tests on fixtures,
never on a live row.

## Cut as v0.1.31 (2026-09-07)

The two decisions and lore's defect, an hour behind the night that found
them. `spctl` accepted, both CDN keys, the live feed equal to the zip, the
Release with the zip:

```
live: https://cdn.ramonfabrega.com/ccc/ccc-latest.zip version 215 length 5294991
ota verify --feed ccc    →  ok: … version 215 length 5294991
gh release view v0.1.31  →  {"assets":["ccc-v0.1.31.zip"], "tag":"v0.1.31"}
ccc version              →  ccc 0.1.31 (215)
ccc stats                →  ccc 0.1.31 (215)  pid 50278
```

**Remote Control is the default, proved by its absence.** One fixture
through the installed binary with **no `--rc` typed at all**:

```
ccc spawn --name ccc-v31-check --model haiku 'Reply with … ok …'
→ respawnFlags ["--name","ccc-v31-check","--rc","--model","haiku","--permission-mode","default"]
   state done, intent = the prompt, output.result = "ok"
ccc list → 3fd7a8d2  done  idle  rc       ccc-v31-check  haiku-4-5-
```

The `--rc` in `respawnFlags` was never typed, and the row draws `rc`
without `asks` — a haiku spawn, so its recorded mode is the rewritten
`default`, which is exactly the case the mark now stays silent on. Both
of the night's fixes visible in one row.

**And a name is a ref.** The same fixture, addressed by name through a
verb ccc resolves itself:

```
ccc archive ccc-v31-check    →  archived ccc-v31-check
ccc unarchive ccc-v31-check  →  unarchived ccc-v31-check
ccc archive ghost-session    →  ccc: no session 'ghost-session' in the roster
```

Before this cut the first two were `no session 'ccc-v31-check' in the
roster`, which is the sentence lore was given for a session that was on
screen. Fixture removed.

## Cut as v0.1.32 (2026-09-07)

`--repo` on `pull` and `fetch`, and `ff` as `pull`'s alias. `spctl`
accepted, both CDN keys, the live feed equal to the zip, the Release with
the zip:

```
live: https://cdn.ramonfabrega.com/ccc/ccc-latest.zip version 218 length 5298142
ota verify --feed ccc    →  ok: … version 218 length 5298142
gh release view v0.1.32  →  {"assets":["ccc-v0.1.32.zip"], "tag":"v0.1.32"}
ccc version              →  ccc 0.1.32 (218)
```

**Proved on the installed binary**, against a throwaway origin — the
released bytes moving a real default branch, not the build tree's:

```
/opt/homebrew/bin/ccc fetch --repo=<fixture> --json
→ {"fetched":"true","repo":"…/fix/repo","said":"fetched origin (111 ms); master has 1 unpulled"}
/opt/homebrew/bin/ccc ff --repo <fixture> --json
→ {"pulled":"true","repo":"…/fix/repo","said":"pulled origin/master → master (1 commit, now d02273d)"}
git log --oneline -1  →  d02273d second
```

`ccc pull --help` on the installed binary now prints `(also: ff)` and both
synopsis lines; before this cut it printed one, which is the whole reason
the version caveat went to lore's relay — air answered `unknown flag` to a
verb studio's branch already had.

**The verb was never the gap; the addressing was.** lore proposed a new
`ccc ff` and `ccc pull <ref>` had shipped in v6 slice 7, refusal for
refusal. What it could not do is run at the END of a reap: it resolves
through a live roster row and that row's cwd, so `git worktree remove` and
`ccc rm` each remove one of its two inputs. `--repo` is the same
`GitPull.perform` reached a second way — the on-base, clean and
ff-possible guards are the same code, which is what keeps ccc doing git on
a session's behalf legal at all.

A path inside a worktree answers for its ROOT rather than being refused,
against the original spec: `pull <ref>` already takes a session's worktree
cwd and pulls the root, so refusing the same path would be one verb
disagreeing with itself about one input.

Suite note, the second sighting of item 30: a full parallel `swift test`
sat **70 minutes with zero bytes of output**, and `sample` put 2401 of
2401 samples in `Git.Drain.data` → `semaphore_wait_trap`. `--no-parallel`
is 523 tests in 63 suites in 22 s. Zero output is indistinguishable from
progress, which is what made it cost an hour rather than a minute.

## the landing detector (2026-09-07)

Item 25's product, built the day after "the stall stream's first run"
measured that no timer could ever be its product. The defect in one
sentence: `TransitionDetector.stallEvent` gates on `row.job?.updatedAt`,
the *daemon's* clock, and the daemon keeps timestamping a dormant
session — so a finished-and-mislabelled session is still, by that clock,
moving. Ten landings, two windows, zero `stalled` events.

**What it is.** `SessionEvent.Kind.landed`, produced by
`TransitionDetector.landingEvent` from `SessionRow.worktree` — the
`WorktreeInfo` that `WorktreeProbe` already computes once per row per
tick for the `↑↓ ⇡⇣` marks, and that the far side already ships across
the hop in `ccc list --json`. **No new probe and no new git call on any
host**: the detector is a join on a reading that was already paid for,
which is the only reason a per-tick git-keyed notifier is affordable.

Rules, each with a test in `Tests/CCCKitTests/LandingTests.swift`:

- **Two halves.** `committed` (`ahead` grew) and `pushed` (`ahead > 0`
  and `unpushed` fell to 0). A worker commits and pushes seconds apart —
  one 2 s poll — so when both cross a single tick the **stronger** is
  reported, else the coincidence would silently cost the event its
  banner.
- **Only `pushed` draws a banner** (`SessionEvent.drawsBanner`, read by
  `Notifier`; every other kind draws). A mid-item commit is not worth a
  phone; work reaching origin is the moment a merge decision exists on
  the other Mac. Both halves reach `ccc watch`, which is where a
  commander is already looking.
- **A terminal event in the same tick swallows it.** When the daemon
  does say `done`, that is the better half of the same news and the row
  already draws `↑N`.
- **The tip is not part of the change key.** A commit landing while a
  session is `blocked` must not re-fire the question it is blocked on.
- **A first reading is a baseline**, so a branch that is already ahead
  when ccc starts is history, not five banners at launch — the rule
  `blocked`, `done` and `stalled` all follow here.
- **No worktree, no opinion.** A research or review worker moves no tip,
  and this detector never claims one it cannot see.

The headline carries git's numbers and the body carries the daemon's
sentence, deliberately: `loop-252` read *"shutdown assertions failing; 5
tests need fix"* while its work was merged and pushed, and the pair of
stale signals agreed with each other. `loop-252 pushed — 3 commits ahead
of master, all on origin — shutdown assertions failing` is that
contradiction drawn, and it is the suite's second fixture.

```
swift test --no-parallel --filter LandingTests   # 12 tests, 1 suite
```

**It fired live the day it was built**, on studio, from this session's
own commit and push — the honest fixture, because a session that is still
`working` while its branch moves is exactly item 25's case and this
session was one:

```
.build/debug/ccc watch --all --json --interval 2   # 1 host, 21 sessions
git commit …                                       # then, 5 s later:
  landed ccc -> committed  ahead 16  unpushed 1
git push  …                                        # 36 s after the commit:
  landed ccc -> pushed     ahead 16  unpushed 0
```

Two halves, in order, with the row's `state` never leaving `working` —
the daemon said nothing at any point, which is the whole defect, and the
tip said it twice. The `job` payload rode along on both.

**Still unmeasured: the rate.** One session is not a night. The shape to
run is attrition's own — a commander loop, two workers, `ccc watch --json
--all` as a Monitor — counting whether `pushed` fired once per landing
and whether `committed` was noise, before the phone keeps it.

## the landing rate, from history rather than a night (2026-09-07)

Item 25's open question is the rate, and attrition — the only fleet with a
commander loop — cannot run it until a release carries `landed` to its
installed `ccc` (0.1.32 (218) has no `landed` in `watch --help`; it
declined to `swift build` another session's worktree, correctly). Its
*prediction* was that `pushed` fires once per landing while `committed`
fires several times, mid-item commits being routine.

That is answerable now, because both halves are functions of git history
and the history exists. Read-only, in `~/code/fun/attrition`:

```
git for-each-ref --format='%(refname:short)' refs/remotes/origin   # 21 worker branches
git reflog show <ref> | grep -c "update by push"                   # pushes: the `pushed` half
git rev-list --count $(git merge-base main <ref>)..<ref>           # commits: the `committed` half
```

**24 pushes across 21 worker branches** — 18 branches pushed once, three
twice (`lane-272`, `lane-run88`, `loop-280`; `loop-280`'s two were 42 s
apart). Every reflog entry reads `update by push`, so these are the
worker's own pushes and not fetches.

The commit column is only meaningful for the **four branches not yet
merged** (`git branch -r --no-merged main`): merging moves `merge-base` to
the branch tip, so the other 17 read 0 and measure nothing.

```
lane-272   6 commits  2 pushes
loop-276   8 commits  1 push
loop-280   3 commits  2 pushes
loop-284  15 commits  1 push
```

**32 commits, 6 pushes.** So the banner half would have drawn ~1.1 times
per landing and the CLI half up to 8 times — an upper bound, since commits
inside one 2 s poll collapse into one `ahead` increase.

The prediction holds, and with it the split: `committed` is not noise, it
is **progress rather than completion**, and it is why only `pushed` draws
a banner (`SessionEvent.drawsBanner`). What this does *not* answer is
whether `pushed` fires once per *landing* as against once per *push* —
`loop-280` pushed twice 42 s apart and would have drawn twice. A live run
with attrition's merge log as independent ground truth is still owed.

**Resolved the same day, by the only party who could.** Reflogs show that
a branch pushed twice; they cannot show *why*. attrition read the three
double-pushes at cause and **all three were one landing each, none a
mid-item checkpoint**: `loop-280`'s 42 s pair is `fb371df` (the item) then
`6de474e`, a follow-up correcting its own paperwork; `lane-run88` is the
capture and then a memcap measurement **the commander asked for after the
first push**; `lane-272` is the same shape.

So `pushed` fires **once per push, at ~1.14 pushes per landing**, and the
excess is a commander asking for one more thing — a normal event in that
loop, which will keep happening. Its own verdict is to ship at that rate
and not suppress the follow-ups: the cost is a second look at a branch it
was about to merge anyway, against the error it made all day, which was
not looking at all.

**What `pushed` means, stated so nothing overstates it later**: not "this
worker is done" — nothing keyed on refs can know that, and neither can the
worker — but *the branch changed and is now publishable*. **The merge is
the only event that means "landing", and only the commander can emit it**,
being a judgement: gate green, paperwork booked, successors taken. No
detector should try to infer it, which is also why the kind's manifest
line says "the branch tip moved" and claims nothing further.

What is still owed from a live run is narrower than the rate: whether the
detector fires reliably under real concurrency, two workers wide. One
session cannot answer that.

## `--json` on a stream promised JSONL and shipped eleven lines (2026-09-07)

The first consumer to wire `ccc watch --json` into something that was not
`jq` found the shape wrong. attrition's Monitor read the stream with
`while read` / `head`-style consumers; `ccc watch --help` promises *"one
SessionEvent per line"*; the emitter was `CLI.printJSON`, the CLI's
one-shot pretty-printer:

```
{
  "at" : "2026-09-07T20:34:14Z",
  "job" : {
    "detail" : "Committing the decision and the CI finding",
…
```

895 bytes, stdout only, eleven lines for one event.

**Why a night of watching never caught it.** Every consumer this fleet had
written was `jq`, and `jq` parses concatenated objects whether or not they
are newline-delimited — the same stream is valid input either way. The
breakage is invisible until someone takes the help line at its word, and
then it is silent: `head -n1` returns `{`, `grep` matches half an event,
`while read -r line` decodes a fragment and reports nothing. It cost
attrition a diagnosis, not a run.

**The fix is the wire form, not the encoder.** `SessionEvent.jsonLine()`
is `printJSON`'s encoder with `prettyPrinted` dropped — same `sortedKeys`,
same ISO-8601 dates — so no field moved and no reader that already worked
stops working. A compact object cannot contain a literal newline (JSON
escapes them inside strings), so the line survives a `detail` a worker
wrote across lines; the test asserts exactly that, with a two-line
`detail` and a `landing` in the payload. The one-shot answers stay pretty:
`ccc list --json` is read by a person as often as a program, and nothing
splits it on newlines.

The help now says **JSONL**, and a test reads that word — this fleet's
standing rule (`CLAUDE.md`, "Rules earned": a string no test reads is a
string nothing keeps true), which is what the original "one per line"
sentence broke by being true of the intent and false of the bytes.

**Not a bug, reported alongside it and worth recording so nobody
re-investigates**: attrition first saw `jq: parse error: Invalid numeric
literal at line 1, column 4` and suspected the opening line
(`ccc: watching 1 host, …`) was going to stdout. It is not — that line and
every host error go to stderr. The `2>&1` in the pipeline was the
watcher's own. Verified: `ccc watch --json --all 2>/dev/null` emits zero
bytes of preamble.

**Confirmed live, by the consumer that was broken.** A 15-minute
`ccc watch --json --all --interval 2` piped through the shape the help
line invites —

```sh
while IFS= read -r line; do printf '%s' "$line" | jq -c '[.kind,.ref,.name]'; done
```

— and the events it caught were this fix's own commit and push:

```
345 bytes -> ["landed","b87b7169","ccc"]
342 bytes -> ["landed","b87b7169","ccc"]
```

Two `landed` halves, **one line each, 345 and 342 bytes**, each one a
whole event to `jq` after a single `read`. Before the change that same
loop's first `read` returned `{`. The detector reporting the commit that
fixed the stream it reports on is the second time it has been its own
fixture (`efdbb44`), and it is the cheapest one available: the run that
proves the emitter is the run that produces the event.

## Cut as v0.1.34 (2026-09-07)

`v0.1.34`, build **227**, 5,308,285 bytes, notarized and published to both
CDN keys; the live feed's `length=` matches the zip's real
`content-length`, and `scripts/install --dist` put the released bytes on
studio. Two commits since `v0.1.33`, both the JSONL fix.

**This cut is the fix, not a sync.** The premise that studio was already
carrying it was wrong, and the wrongness is worth keeping: every
`ccc watch --json` running on studio at the time — attrition's Monitor
among them — was `/opt/homebrew/bin/ccc` → `~/Applications/ccc.app`,
**0.1.33 (224)**, whose `--help` still printed the old promise. The fix
existed only in one worktree's `.build/debug/ccc`, which is why the live
proof had to name that path explicitly. A dev binary that fixes nobody's
stream is the same shape as studio-green-proves-nothing (`CLAUDE.md`,
"Rules earned"): **the consumers were on the released build, so the
release was the fix reaching them.**

The installed 0.1.34 now says it:

```
--json:  JSONL: one compact SessionEvent per line, flushed as it happens — kind, ref, …
```

**Proved on the released bytes, not the dev build.** The naive consumer
again — `ccc` off PATH this time, 0.1.34 (227) — and again the events it
caught were this section's own commit and push:

```
355 bytes -> ["landed","b87b7169","ccc","committed"]
352 bytes -> ["landed","b87b7169","ccc","pushed"]
```

Both halves, one line each, whole to `jq` after a single `read`.

**And a release does not reach a consumer that is already running.**
`scripts/install --dist` quits and relaunches the *app*; the long-lived
`ccc watch` CLIs on studio keep the image they started with. Three were
up at the cut — started 13:48, 15:23 and 15:33 against a binary replaced
at 15:49 — so all three kept pretty-printing after the fix was installed,
and would have gone on doing it for as long as their Monitors lived. The
neighbouring rule (`CLAUDE.md`, "Rules earned") says a fix is unproved
until a release carries it to the other Mac; this is the next step of the
same thought — **a release carried to a Mac still has not reached the
process that was already running there.** The watcher has to be
restarted, and only its owner can do that.

**And the restart has to be measured, not remembered.** The owner of one
of those three did restart, promptly and accurately — confirmed
`0.1.34 (227)` on the installed path, stopped its Monitor, started a
fresh one at 15:51:44 — and reported that nothing on its side was still
on the old image. One process short: a second `ccc watch --json --all`
it had left running against a file since 15:33:31 was still up, and that
file's last object, written at 15:55:56 — six minutes after the swap —
was eleven lines. So the check is **`ps -o lstart` against the binary's
mtime**, not the recollection of having restarted. A fleet of one is
still a fleet to enumerate.

## one landing, one banner — and the refs beat the ping (2026-09-07)

The live run the rate section said it was owed, from attrition, with its
own merge log as independent ground truth. One landing end to end,
`lane-286` (ref `eb192e45`), off the released detector:

```
20:28:42  committed  ahead 1  unpushed 1   "Committing predictions before the run"
20:52:06  committed  ahead 3  unpushed 3   "Verifying merge clean and guards pass"
20:52:27  pushed     ahead 3  unpushed 0   "245 tests pass (11GB peak)"
20:52:3x  the worker's own SendMessage ping arrives
then      fetch, `git log base..branch` non-empty, merge
```

**Three commits, two `committed` events, one `pushed`.** The merge
confirms the three: `9aa6747` (the predictions stanza), `db8c72e` (the
item), `4c796ea` (its `ccc update` merge of the base) — exactly the
`ahead 3` claimed.

**The banner rate was 1.0, not the 1.14 history predicted**, and the gap
is fully explained: all three double-pushes in the reflog history were
follow-ups the commander caused by asking for one more thing *after* a
worker had already pushed. So the honest statement is **`pushed` fires
once per landing unless the commander reopens the item**, and no detector
can see that difference, because it is a conversation and not a ref.
`drawsBanner` needs no change and gets none.

**The 1 → 3 jump is the collapse case, observed live.** Two commits
inside one 2 s poll produced a single event, exactly as the upper-bound
caveat predicted. The consequence is worth stating plainly for anyone
who reads these events: **`ahead` is the count, the event stream is
not.** A consumer that tallies `committed` events under-counts commits
by design.

**The ordering was the surprise, and it inverts an assumption.** `pushed`
landed at 20:52:27, *before* the worker's own completion ping seconds
later — the detector polls refs while the worker is still finishing its
turn and composing a message. On a git-shaped landing the refs are not
merely the evidence behind a ping, they are the **earlier** wake. The
ping keeps its unconditional place for the two cases refs cannot see —
a worker whose product is a log outside the repo, one whose product is a
document section — plus a human-legible summary; what it has lost is the
claim to being first.

`committed`'s two firings were both informative here — the first caught
the worker committing its predictions *before* running the capture, which
is the discipline its brief demanded. Progress, not noise, and still not
worth a phone.

## `--channels`, the flag a desk can only take at launch (2026-09-08)

Asked for by the hail session: hail's Slack desk is a permanent side
session that registers its channel *only* at launch, and `spawnArgv` was
a fixed list, so the desk could not be spawned the fleet's way at all.
The three things measured before it was written:

**The flag exists in 2.1.260 and takes a tagged entry**, though
`claude --help` prints nothing about it:

```
$ LC_ALL=C grep -a -o -- "--channels[^\"']\{0,80\}" ~/.local/share/claude/versions/2.1.260 | head -4
--channels <servers...>
--channels to run a list of approved channels.
$ claude --channels plugin:hail@hail --version
2.1.260 (Claude Code)
```

**It is variadic, and a bare one eats the next word** — the same class of
hazard `--rc` and `--worktree` were caught on (item 17), one step
greedier, because it swallows *every* word up to the next flag rather
than one:

```
$ claude --channels --version
--channels entries must be tagged: --version
```

`--version` was consumed as a channel entry. So `claudeArguments` places
`--channels` immediately before `--permission-mode`, which is always
emitted and always carries its own value: a flag, never the prompt, is
what ends its run. `SpawnRequest.variadicValueFlags` + the structural case
in `anOptionalValueFlagNeverStandsBeforeThePrompt` keep that true as
flags are added.

**The words ccc actually hands the harness**, with a recording `claude`
under `CCC_CLAUDE` (`ccc spawn --model haiku --name fake-desk --channels
plugin:hail@hail "hold the desk"`):

```
--bg --name fake-desk --model haiku --rc --channels plugin:hail@hail
--permission-mode auto "hold the desk"
```

The prompt arrived as one argument and the entry as one word — `:` and
`@` are both in `remoteWord`'s bare set, so the far side's shell hands the
harness the same word across the hop. **Not measured: a live desk.** The
allowlist entry that admits `plugin:hail@hail` was being applied as this
shipped, and a throwaway session registering the desk's channel would
have raced the real one for Slack messages.

## Cut as v0.1.35 (2026-09-08)

`v0.1.35`, build **234**, 5,308,423 bytes, notarized and published to both
CDN keys; the live feed's `length=` matches the zip's real
`content-length` (`ota verify --feed ccc`: `ok … version 234 length
5308423`), and `scripts/install --dist` put the released bytes on studio.
Six commits since `v0.1.34` — the JSONL fix reaching running watchers, the
landing detector's one banner, `ahead` as a count, the restart measured
rather than remembered, and `--channels`.

**Proved on the released bytes.** `--channels` is the feature this cut
exists for, and hail spawns its desk through whatever `ccc` is on PATH, so
the dev binary proving it was never the measurement (`CLAUDE.md`, "Rules
earned"). Off `/opt/homebrew/bin/ccc`, 0.1.35 (234), with a recording
`claude` under `CCC_CLAUDE`:

```
$ ccc spawn --model haiku --name fake-desk --channels plugin:hail@hail "hold the desk"
--bg --name fake-desk --model haiku --rc --channels plugin:hail@hail --permission-mode auto hold the desk
```

and `ccc help spawn` names the flag in its synopsis and its prose. The
desk can now be spawned the fleet's way.

## the name that resolved for the read and not for the write (2026-09-08)

Reported by hail, measured twice on a live headless `--bg` probe with the
app running throughout: `ccc clear hail-probe --then "…"` answered

```
{"armed": true, "cancelled": false, "ref": "hail-probe", "said": "armed a clear on hail-probe…"}
```

the bare `ccc clear` list went **empty within ~3 s**, and the session was
never cleared — no `/clear` in the transcript, no `--then` prompt, no new
session uuid, and asked directly the probe answered `CONTEXT INTACT`. The
arm succeeded, the arm disappeared, nothing happened, twice.

**It is v0.1.31's fix, half-applied.** "The ref that was only an id"
taught eight verbs to resolve a `<ref>` by name as well as by id — and
every one of those eight resolves for its *reads*. `clear` then wrote the
mark under **the caller's word**:

```swift
overlay.arm(pending, id: id, sessionId: row.sessionId)   // id is what was typed
```

while the poller joins marks on the row's short id alone
(`marks.mark(for: rows[i].session.id, …)`). So a clear armed by name is
filed where no row can read it, `PaneController.fireArmedClears` builds
`SessionRef(id: "hail-probe")`, finds no row, and — this Mac having
polled — calls it `.gone` and drops it on the very next tick. The ~3 s
was one hosts-watch pass. `ccc archive <name>` and `ccc pin <name>` had
the same shape and the same silence: exit 0, `archived desk`, row
unarchived forever.

The key is now the **row's** id everywhere a mark is written, and so is
the `ref` the verb answers with. Cancel and the undo half (`unarchive`,
`unpin`) resolve a name too, but only when the word is not already a key
— they must keep working on a row the roster has forgotten, which is what
they exist for.

**hail's hypothesis was that a `--bg` session has no pane to type into.
It is refuted:** `performClear` calls `switchTo(ref:)`, which attaches on
demand, so nothing needs to be attached to the target beforehand. What an
arm needs is a ccc *with a pane* running on that Mac — the app or
`ccc attach … --headless` — and nothing else.

**Which is now enforced rather than assumed.** An arm is a promise that
something types minutes from now; with no ccc serving the control socket
the mark would sit in the file until it was pruned and the caller would
never learn that. `armed: true` has to mean it can fire:

```
$ ccc clear clearfix-two --then "x"          # with no server on the socket
ccc: nothing would fire it: no ccc is serving …/ccc.sock — open ccc.app or
run `ccc attach <ref> --headless` there, then arm it again
exit=1
```

**And the outcome is written back where a reader can find it.** The one
who arms a clear is a background session that cannot see the window's
notice or the headless log — and after a clear that worked it does not
remember arming — so every outcome (fired, refused, dropped) now lands on
the mark as `fired: {at, said, fired}` and `ccc clear` with no ref shows
it. Bare `clear --json` is `{ armed[], recent[] }`; it was a bare array.
An arm that vanishes saying nothing is the shape that let this bug
survive two probes.

**Measured end to end on two real haiku `--bg` fixtures**, a private
headless ccc of the new build on its own socket and overlay (so the
user's app could neither see nor fire these marks):

```
$ ccc clear clearfix-probe --then "Reply with exactly the word BRAVO…" --json
{"armed": true, "ref": "908f42ca", …}          # the NAME resolved to the ROW's id
$ cat overlay        →  "marks": { "908f42ca": { "clear": {…} } }
FIRED (3 s later):   {"at": "…18:30:42Z", "fired": true,
                      "said": "cleared 908f42ca, then: Reply with exactly the word BRAVO…"}
```

and the session itself, which is the only proof that counts: a new
transcript `df22eff1…` minted by the `/clear`, **zero** mentions of the
pre-clear word `ALPHA` in it, two of `BRAVO`, and the job's own
`detail: replied with BRAVO as requested`.

The second fixture answers lore's question exactly. The headless ccc was
attached to `908f42ca` and had **never touched** `648f0454`; armed by
name, that clear fired the same way (`cleared 648f0454, then: …`), minted
`56620908…`, and the job read `detail: replied with DELTA as requested`.
A clear needs a ccc on the Mac, not a pane on the session.

## Cut as v0.1.36 (2026-09-08)

`v0.1.36`, build **237**, 5,327,873 bytes, notarized and published to both
CDN keys; the live feed's `length=` matches the zip's real
`content-length` (`ota verify --feed ccc`: `ok … version 237 length
5327873`), and `scripts/install --dist` put the released bytes on studio
(`ccc 0.1.36 (237)`). Two commits since `v0.1.35`: the mark key and the
version bump.

**Proved on the released bytes**, which for this fix is the only
measurement that counts — hail's desk arms its clears through whatever
`ccc` is on PATH, and that symlink points at the installed bundle, so the
dev binary that found the bug could never prove the fix (`CLAUDE.md`,
"Rules earned"). Off `/opt/homebrew/bin/ccc`, 0.1.36 (237), with the
installed app as the firer and the real overlay underneath — a haiku
`--bg` fixture the app had never attached to, armed **by name**:

```
$ ccc clear release-probe --then "Reply with exactly the word FOXTROT…" --json
{"armed": true, "ref": "baed3fe7", …}                    # the name resolved to the row's id
FIRED (3 s later): {"ref": "baed3fe7", "fired": "true",
                    "said": "cleared baed3fe7, then: Reply with exactly the word FOXTROT…"}
$ ccc clear
baed3fe7  3s ago · cleared baed3fe7, then: Reply with exactly the word FOXTROT…
```

and the session itself: a new transcript `2559d33b…` minted by the
`/clear`, with the job's own `detail: replied with FOXTROT as requested`.
The desk can clear itself now.

## the base branch lives in a worktree (2026-09-17)

**Reported from outside**, which is new: attrition's commander session —
using ccc 0.1.36 as the whole orchestration layer for its worker loop —
said `merge`, `push --base` and `pull` assume the base branch is checked
out in the **main** checkout, and refuse when it lives in a worktree
instead. It had hand-rolled `git merge --no-ff` four times that day before
noticing, and the residue was real: its hand reap left a merged worker
branch dangling where `ccc rm` deletes session, worktree and branch in one
call.

The shape is not exotic. attrition's integration branch
`worktree-replan-pdb` is permanently checked out in
`.claude/worktrees/replan-pdb` — every landing goes there — and the main
checkout stays on `main`, which only ever gets fast-forwarded by hand, by
the user. **So the main checkout is never on the branch work lands on, by
design.** `ccc spawn --worktree --base`, `update` and `rm` all handle it
already; the three verbs that *write to the base* did not, because each
ran `git -C <main checkout>` and refused unless HEAD was the base.

Reproduced here on a fixture repo of that shape (a bare origin, `main` in
the main checkout, `worktree-integration` in `.claude/worktrees/integration`,
a ccc-cut worker worktree off it with the base recorded), with a real
draft session as the row — the installed release as the control:

```
$ ccc merge e9008b6a --no-ff --json          # 0.1.36 (237), installed
{ "merged": "false", "said": "…/fix is on main, not worktree-integration; refusing to merge" }
```

word for word the commander's sentence. The fix is to act **where the base
is checked out** — `git worktree list --porcelain` answers it in one
process (`WorktreeProbe.checkoutHolding`), and only `merge` and `pull` ever
ask, so the 2 s poll still spawns nothing. Every guard stays: the tree must
be on the base and clean, a fast-forward must be possible when that is what
was asked, a conflict backs out. Same fixture, same row, this build:

```
$ ccc merge e9008b6a --no-ff --json
{ "merged": "true", "said": "merged worktree-probe → worktree-integration
                             in .claude/worktrees/integration (1 commit, merge commit ee02fdc)" }
$ ccc pull e9008b6a --json
{ "pulled": "true", "said": "pulled origin/worktree-integration → worktree-integration
                             in .claude/worktrees/integration (1 commit, now 6a9d97c)" }
$ ccc merge e9008b6a --no-ff --json          # with that tree dirty
{ "merged": "false", "said": "…/.claude/worktrees/integration has 1 uncommitted change;
                              refusing to merge" }
```

`main` never moved through any of it, and the refusal now names the tree it
would have run in — the commander's third suggestion, which the fix makes
free rather than a consolation.

**It does write into a tree a live session may be sitting in.** That is not
new and it is why the clean-tree rule exists: `ccc update` has merged into
a *worker's* worktree since v6 slice 6 under exactly that guard. What the
earlier decision refused (`WorktreeInfo.baseTip`, 2026-09-06) was ccc
picking a side in a divergence and advancing a ref nobody asked it to; a
commander asking `ccc merge` for its own integration branch is asking.

**And one of the three reports was about a string, not the code.**
`push --base` has pushed `WorktreeInfo.base` — the *recorded* base — since
bases could be recorded (2026-09-04), with a full refspec, so it needs no
checkout anywhere and was right for this loop all along. The manifest said
"the repo's default branch", written 2026-09-06 and carried through eleven
releases, and a careful reader believed the string over the behaviour and
reported ccc as pushing the wrong ref. Proved live (`pushed
worktree-integration → origin (2 commits)`, `origin/main` untouched) and
now pinned by a test that reads the help text, which is the rule this repo
already earned the hard way: **a string no test reads is a string nothing
keeps true** — it cost a worker its merge in v11 and a peer twenty minutes
here.

`BaseInAWorktreeTests` is that repository's shape as nine tests over real
git processes: the holder found (and nil for a branch no tree has), all
three strategies landing there, the dirty refusal naming it, a conflict
backing out of *that* tree and leaving it clean, pull fast-forwarding it,
`push --base` sending the recorded base, and an ordinary base still landing
in the main checkout with nothing said about location.

### the reporter closed two of the three (2026-09-17)

The commander tested `push --base` on its live loop against installed
0.1.36 and withdrew that third of its report:

```
$ ccc push 6bf1cd8b --base --json
{ "pushed": "false", "target": "base",
  "said": "nothing to push: origin/worktree-replan-pdb already has every commit of worktree-replan-pdb" }
```

`worktree-replan-pdb`, not `main` — so the verb was right and only the
string was wrong, and **a fix to the push would have been the regression.**
It is adopting `ccc push <ref> --base` today, with no release needed. The
lesson runs both ways: the string cost a reader an hour and would have
cost the code a working verb if the report had been believed instead of
run.

**The repo-addressed pull of a non-default base is declined, by the only
caller who would have had it.** Asked whether `pull --repo <path>` should
mean the base a worktree holds rather than the root's default branch, the
commander said don't build it: its integration branch is checked out in
its *own* worktree, so bringing origin into it is a fast-forward in the
tree it is already working in, `ccc update <ref>` covers a worker coming
the other way, and what it had been reaching for at the end of a reap was
the merge, not a pull. Adding a second meaning to `--repo` would cost
every reader of the flag to serve one call site. So `--repo` keeps meaning
the root checkout's default branch, and this paragraph exists so the next
session does not re-open it on a hypothetical.

**And `rm`'s branch rule was a string nobody had written.** The behaviour
is eleven tests old — the branch goes only when its commits are in its
*recorded* base or on origin, so a non-default base counts — and the help
said none of it, which is why the same commander hand-rolled the reap that
left `worktree-loop-295`'s predecessor dangling: "it's the difference
between `rm` being safe to reach for and being a thing you check first".
Now in the manifest, in README, and read by a test. Third report of the
day whose fix was words.

## Cut as v0.1.37 (2026-09-17)

`v0.1.37`, build **241**, 5,329,908 bytes, notarized and published to both
CDN keys; the live feed's `length=` matches the zip's real
`content-length` (`ota verify --feed ccc`: `ok … version 241 length
5329908`), and `scripts/install --dist` put the released bytes on studio
(`ccc 0.1.37 (241)`). Three commits since `v0.1.36`: the worktree-held
base, the strings, the version bump.

**Proved on the released bytes**, off `/opt/homebrew/bin/ccc`, on the same
attrition-shaped fixture with a fresh haiku draft as the row:

```
$ ccc spawn --cwd … --worktree=release-probe --base worktree-integration … → 269a9873
$ ccc merge 269a9873 --no-ff --json
{ "merged": "true", "said": "merged worktree-release-probe → worktree-integration
                             in .claude/worktrees/integration (1 commit, merge commit ef5ca4f)" }
$ ccc rm 269a9873
removed 269a9873; removed the worktree …/release-probe and its branch worktree-release-probe
```

`main` never moved, and `rm` retired the branch this time — the same call
that kept `worktree-probe` an hour earlier, when the merge before it had
been refused. The two halves of the day's report, on one row: the verb
that could not reach a base in a worktree now does, and the guard that
decides a branch's fate reads the recorded base either way.

The reporter is the test from here: it lands items continuously against a
non-default base held in a worktree, with two lanes live at the cut, so
`merge` and `pull` meet real conflicts on a real loop within minutes of
its update — which is the measurement a fixture cannot make.

## The first live merge, and what the next refusal will have to say (2026-09-17)

The reporter landed a worker on the released 0.1.37 bytes, on its own
loop, into an integration branch held in a worktree a live commander
session is sitting in:

```
$ ccc merge a6aa3418 --no-ff --json
{ "merged": "true",
  "said": "merged worktree-loop-302 → worktree-replan-pdb in .claude/worktrees/replan-pdb (1 commit, merge commit e8f8b18)",
  "strategy": "no-ff" }
```

Then, in that tree: `git status --short` empty, `log --oneline -1` the
merge commit, `HEAD` still `worktree-replan-pdb`. It replaced a
`git merge --no-ff` that would have been typed by hand, with none of the
guards. No conflict — the journal was uncontended — so the back-out had
nothing to do; the measurement is that a clean `--no-ff` landing on a
live loop is now a thing that has happened rather than a fixture.

**The path half of the sentence is confirmed from the call site**, not
from taste: at the moment that line was read there were three live
worktrees whose directory names deliberately are not their branch names,
and the question was which tree had just been written into. The branch is
in the sentence twice; `in .claude/worktrees/replan-pdb` is the half that
answers. That argument is now the comment above the code that builds it.

**What the report cost in code was the dirty refusal.** The reporter
named it as the guard it expects to meet first in anger, for a reason the
count could not answer: that commander runs a 130-second test gate *in
the same tree it merges into*, so when the refusal says "2 uncommitted
changes" the only question is whether the dirt is its own gate. The
refusal now names the files — four then a count, the way a conflict names
its files, the new path for a rename:

```
…/.claude/worktrees/integration has 1 uncommitted change (b.txt); refusing to merge
…/ccc has 5 uncommitted changes (e.txt, f.txt, g.txt, h.txt (+1)); refusing to merge
```

One helper (`Git.dirty`) behind all three verbs that carry that sentence
— `merge`, `update`, `pull` — because a payload on one of three identical
refusals is the next report. Worth saying out loud to whoever meets it:
the status read is `--untracked-files=no`, so a test run's *new* files
have never been able to trip this; what it lists is tracked work.

Still outstanding, and still only a live loop can close it: the conflict.
`loop-301` appends to the same append-only journal and was cut before two
other items landed, so the collision is live rather than theoretical. The
fixtures already prove the shape on this exact layout — a conflict backs
out of the tree that holds the base, names the files, leaves that tree
clean, and the worker keeps its commits (`BaseInAWorktreeTests`,
`WorktreeTests`) — which is why the live report is a confirmation and not
the design.

## The prediction was wrong, the payload stands, and the fourth check was missing (2026-09-17)

Three corrections to the entry above, all of them from the reporter or
from reading our own tests after making a promise about them.

**1. The dirty refusal will not fire the way it was built for.** The
reporter withdrew its own prediction: it braced for a refusal mid-gate,
because its 130-second release run writes scratch files into the tree it
merges into — but the status read is `--untracked-files=no`, so new files
have never been able to trip it and that case cannot happen. Its words:
"a guess dressed as a prediction", the second of the day, after reporting
`push --base` from the docs instead of from a run. So the entry above
records a payload built against a case that does not exist, and the honest
argument for keeping it is the narrower one: *when* it does fire, the dirt
is tracked work, "is that mine" is the only live question, and a count
cannot answer it. Nothing rolled back — a guard's sentence being right for
a different reason than the one that prompted it is still right — but the
reasoning on the record is now the one that holds.

The reusable half is about guards, not about this guard: **a guard's reach
is in its flags, not in its sentence.** Both of the day's bad predictions
were made by reading what a verb *says* instead of what it *runs*; one
`--untracked-files=no` in the call answered both. Not promoted to a rule
in CLAUDE.md — two instances in one day, one reporter, and the rule would
be ours to keep rather than theirs.

**2. No release for it.** The reporter explicitly declined the cut: the
fact it needed was the flag, not the payload, and the payload can ride
whatever next justifies a notarize. Recorded because a declined release
is evidence about what a fix was worth, and a fix that nobody needed
shipped today is a fix that was not urgent.

**3. The four expectations were three.** Told the reporter what the
fixtures prove about a conflicted back-out — backs out of the tree holding
the base, names the files, leaves that tree clean, and *the worker keeps
its commits* — then read the tests and found the fourth one unasserted in
both of them. It was true in fact (nothing in the failure path touches the
worker's side) and unread by any test, which by this repo's own rule means
nothing was keeping it true. Both conflict tests now capture the worker's
head and its `status --porcelain` and check them after the back-out
(`WorktreeTests.aConflictBacksOutCleanly`,
`BaseInAWorktreeTests.aConflictBacksOutOfThatTreeToo`). The promise came
before the test; the test now exists because the promise was made to a
live loop that is about to check it.

**Second clean landing on the live loop**, same released 0.1.37 bytes:
`ccc merge a6aa3418 --no-ff` into the worktree-held base, clean, tree
empty afterwards, HEAD `e8f8b18`, branch still `worktree-replan-pdb` —
then `ccc rm a6aa3418` retired session, worktree and branch in one call.
So the whole merge→reap path is doing real work on that loop in place of
a hand-rolled `git merge --no-ff` plus three manual cleanups. Still zero
conflicts: two landings, both uncontended. `loop-301` has been running
ninety-five minutes, was cut before two other items merged, and appends to
the same end of `docs/JOURNAL.md` as both of them — the collision is that
one, and the four checks above are what it will answer.

## update's back-out, in the shape that will meet it first (2026-09-17)

The reporter flagged the gap before its loop could: two of its lanes are
behind the base by different amounts (3 and 1) and append to the same end
of the same append-only file, so **`ccc update` can collide before
`ccc merge` ever does** — a different verb's back-out, in the *worker's*
tree rather than the base's. Its words: "your fixtures cover merge's
back-out and I don't know that they cover update's."

Read rather than assumed. `update`'s conflict back-out was covered where
the base is the main checkout's branch (`anUpdateConflictBacksOutAndOffers
TheSession`: head unchanged, tree clean, file still the worker's, no
`MERGE_HEAD`, `ask` carried) and **not covered at all in the shape that
loop has** — `BaseInAWorktreeTests` had no `GitUpdate` test. Three now:

- `anUpdateTakesTheBaseFromTheTreeThatHoldsIt` — a commit made in the
  base's own worktree reaches the worker, and that tree is not a party
  to it.
- `anUpdateConflictBacksOutInTheWorkersTreeAndLeavesTheBasesAlone` — the
  journal collision made small, with the asymmetry stated: the worker's
  branch keeps its commits, its tree is clean, no `MERGE_HEAD`, its file
  is still its own, `ask` names `worktree-integration` — and the tree
  holding the base is untouched in either direction, branch and worktree
  both.
- `anUpdateFollowsTheBaseToOriginWhenTheLocalBranchIsBehindIt` — when the
  tree holding the base has not pulled, the tip is
  `origin/worktree-integration`, that is what the worker merges and what
  the sentence names, and the local base branch does not move for a
  worker's update.

All three passed on the first run: **the verb was already right; nothing
was holding it right.** Same finding as the fourth back-out check an hour
earlier, from the other direction — coverage is the thing that was
missing, not behavior — which is the second time today the honest report
is "the code was correct and the test did not exist." Also mirrored on the
ordinary shape: update's back-out now asserts the base never moved, the
way merge's asserts the worker keeps its commits.

Left for the live loop, unchanged: whichever verb collides first. If it is
`update`, these three are what it checks; if it is `merge`, the four from
the entry above. The reporter will name the verb either way.

## The cut in the back-out's own sentence, and one helper for it (2026-09-17)

The reporter's mechanism is more specific than "whichever verb updates
first": `loop-301` is behind the base by 3, **two of those three appended
to the end of `docs/JOURNAL.md`** (295's and 302's landings), and 301 has
its own entry in progress at that same end — so its `ccc update` meets two
foreign entries in its own tree. `loop-303` is behind by 1 and that commit
is paperwork with no journal line, so 303 is clean now and becomes a
candidate the moment 301 lands. 301 is the first datum, and it is
`update`'s back-out, in the worker's tree.

What that reading found here, before the loop did: every conflict
assertion in the suite was the **single-file** case (`conflicts in a.txt`,
four of them). The `prefix(4)` + `(+N)` cut in the back-out's own sentence
was read by nothing — and it lived in **two identical private copies**,
one per verb that backs out. A collision wider than one file was about to
be the first thing to exercise it, live.

Now one `Git.conflicted` helper behind both verbs, beside `Git.dirty`, and
a test that reads the cut through both of them: six files conflicting,
`conflicts in a.txt, p.txt, q.txt, r.txt (+2)` from `merge` and from
`update`, both trees back where they started and neither mid-merge. 301's
real sentence will name one file, not six — but the cut is what a wide
collision would have hit first with nothing holding it.

**Third instance today of one failure.** The fourth back-out check, the
missing `GitUpdate` suite for this shape, and now this cut: all three were
correct code that no test read, and all three were found by reading our own
tests after making a claim about them to someone who was about to check
it. No new rule — `docs/DESIGN.md` §9 and CLAUDE.md already say a string no
test reads is a string nothing keeps true. What today adds is the second
half of it: **believing a behaviour because you wrote the code that
produces it is the same error as reporting from the docs instead of from a
run** — the reporter's own retraction, pointed inward, and worth the same
treatment.

## The update-direction collision may be rare by construction (2026-09-17)

`loop-301` took all three commits it was behind — including the two that
appended journal entries — and reported no conflict. From the tree holding
the base: `merge-base` is the base tip and
`rev-list --count loop-301..worktree-replan-pdb` is 0. The reporter asked
the worker directly rather than reading silence as success, which is the
right instinct: a worker may resolve something and not say so.

**The reporter's argument for why it was clean is structural, not lucky.**
A worker writes its journal entry near the *end* of its item — the
definition of done puts paperwork after the implementation and the gate —
and 301 updated while still restructuring `astar_path`, so it had nothing
of its own at the contested end of the file. If that holds, an
update-direction journal collision only happens to a worker that has
already written its paperwork, and workers do paperwork last **by
construction**. The direction with the offered prompt is the direction
whose conflicts are structurally rare; the direction with no offer —
`ccc merge`, in the base's tree, with a live commander sitting in it — is
where the first real collision is now expected. That asymmetry is recorded
here rather than in the queue — see the entry below for why — with "argue
whose conflict it is" first: the worker knows the change, the commander
owns the base, and a wrong offer is worse than none.

Also worth keeping, because it is a distinction our own entries have
blurred before: **"the predicted event did not occur" is not "the
predicted string was wrong."** The back-out sentence for a merge collision
is still unread off a live one; two live landings have both been clean.
The fixtures hold it; nothing has met it.

What the reporter's next case will exercise, in its words rather than
ours: both live lanes write `docs/JOURNAL.md` *and* `docs/QUEUE.md`'s
scoreboard, so a two-file collision is the ordinary case the moment they
land close together — which is the cut the entry above put a test under,
now with a named mechanism rather than "a matter of when".

## The first real collision: update's back-out, five for five (2026-09-17)

`loop-301` updated twice. The first, before it had written its journal
entry, was clean — `merged worktree-replan-pdb → worktree-loop-301
(4 commits, merge commit a000d71)`. The second, with its entry written,
collided. One line, exit 1, verbatim from the loop:

```
merge worktree-replan-pdb → worktree-loop-301 conflicts in docs/JOURNAL.md; backed out, worktree-loop-301 untouched — ask the session to merge worktree-replan-pdb
```

**Pre-registered before the datum**, in a message to the reporter, with
the fixture's names: identical, clause for clause, no drift. The base half
read the local branch rather than `origin/…`, which is right — local was
level with origin at that moment, so `baseTip` was nil.

The five checks, each answered separately rather than inferred from one:

1. the sentence, above, exact;
2. `git status --porcelain` in the worker's tree afterwards — empty;
3. its commits survived (`9c29ca8`, `75e13a4`, `aab94de` unchanged) — the
   fourth back-out check, the one that was resting on nothing this morning;
4. no `MERGE_HEAD` — `rev-parse -q --verify` failed;
5. the base's side untouched, **verified from the tree holding it by the
   commander sitting in it**, not from the worker's report: status empty,
   HEAD `1a8a51c`, branch still `worktree-replan-pdb`.

Resolved by hand afterwards: `git merge --no-ff`, one hunk, 302's entry
against its own, both `## 2026-09-17`, kept in landing order; guards and
gate green.

**What the fixtures gained.** The live line is now the assertion: all four
back-out tests compare the **whole sentence** instead of a substring, in
both shapes and both verbs. The `— ask the session to merge <tip>` clause
had been read by no test at all, and it is half of what the HUD's button
promises. The merge-direction lines are pinned the same way, so when the
reporter sends the first real one it will be compared against a test
rather than against anyone's memory of what the sentence says.

**And the structural argument was amended by the side that made it.**
Update-direction collisions are not rare by construction: a worker does
write its paperwork last, but what decides the collision is whether it
updates *again after* writing it — which happens whenever a commander
sends it back, as 301's did to re-measure a stale baseline. So the offered
prompt is pointed at the right verb after all, the premise is weaker than
when it was written, and the reporter, who would have argued for moving
the offer to `merge`, argues now for leaving it alone.

**The queue refused the item, and that is the guard working.** It went in
as item 34 and `DocsGuardTests.theQueueIsBounded` failed at 272 lines
against a bound of 230 — the queue was already at 229, so an item can only
enter when a finished one leaves, and nothing finished today. Golfing it
to fifteen lines still failed, which is the bound saying the right thing:
a parked design question whose own proposer now argues against it does not
earn one of 230 lines that every session reads whole. So `docs/QUEUE.md`
is back untouched and the finding lives here, where the file is unbounded
because it is addressed by heading and never read whole. The full shape,
if it is ever picked up: `MergeOutcome.ask` is a wire field,
`WorktreeProbe.checkoutHolding` names the tree, roster rows carry `cwd`,
`ccc ask <ref>` is the parked twin — and whose conflict it is gets argued
before any of that is built.

Merge's back-out sentence remains unread off a live collision. Two
landings, both clean; the one real conflict went the other way.

## Both paperwork guards refused both of us, on the same day (2026-09-17)

The reporter's handoff bound (32 lines) refused a 44-line draft and took
three trims; its item cap (18) fired at 20 and pushed two of three new
items into a parked file. Ours refused item 34 at 272 lines against 230,
and still refused it golfed to fifteen. **Both sides concluded
independently that the guard was right**, and both had a shortening they
would have made instead if the guard had merely asked. That convergence is
worth more than either finding, and it is the same rule this file already
carries from another surface: *a rule that is only prose is a rule a tired
afternoon defeats* — the reporter's phrasing is that a rule which could be
a guard and is only prose will be broken within the week, and it names its
own scar, a red paperwork guard that reached a commit on that loop's first
night with the lesson written down and broken later by the session that
wrote it.

**Our instance of that scar, today, named precisely.** A commit went out
with `DocsGuardTests.theQueueIsBounded` red, and the cause was not the
item's length — it was that a **docs-only change was verified with a
filtered test run**, and the docs guards live in the suite that filter
excluded (`ManifestTests|WorktreeTests|BaseInAWorktreeTests`). The rule
that would have caught it is "verify a docs change by running the suite,
not the part of it you were just editing", which is prose, which is the
category their rule says gets broken.

The guard-shaped version would be a gate command that runs the whole suite
unfiltered and is what "green" means — there is no such script and no git
hook in this repo today (`scripts/` has build, install, package, probes;
`core.hooksPath` is unset), so "green" is currently whatever the session
last typed. **Not built here**: it changes the dev loop and the release
flow's step 1, which is the user's to decide, and this session's evidence
for it is one slip of its own. Offered, and left as an offer.

Disclosure is the cheap half and was done in the same message as the fix.
The expensive version is the one nobody mentions and a later session
inherits as green.

## Two armed clears lost to an unreadable box, and what a clear does to a notification (2026-10-01)

**The loss was the fire path's, not the caller's.** attrition's commander
(job 3c382923) armed `ccc clear 3c382923 --then continue` at 01:29:30Z and
02:43:22Z, and its brief blamed its own `--cancel`, run later as a status
check, for consuming both. Both cancels printed "no clear was armed". The
real overlay held the answer for the second one: `02:43:31Z — the clear on
3c382923 did not fire: 3c382923's prompt box cannot be read; nothing was
typed`. The commander's transcript has its turn ending at 02:43:25.7Z
(`turn_duration` 02:43:27Z), with nothing after it until 02:57Z. So the
gate fired on a genuinely idle row, four seconds after the turn ended, and
the single read it took came back `.unreadable`. The first arm left no
record (the second one overwrote it), but the transcript is just as quiet
for 35 minutes after its turn ended (01:29:38Z → 02:04Z), and its cancel
found nothing.

**Not reproduced.** On a private headless ccc (own socket, own overlay):
a small haiku fixture with the pane already on it, the same with the pane
on another session (a fresh attach), and a draft fork of a 10 MB ccc
transcript attached fresh. All of them read the box at once, cursor
visible at (2, 36), with focus reported out. A draft reads `blocked`
(waiting for its first prompt), so the gate correctly never fires on one.
The app keeps no log, so the commander's grid at 02:43:31Z is gone.

So two changes, neither of which needs the cause. The fire **re-reads the
box for up to ten seconds** before typing; that is reads only, with no
key pressed. And a refusal now **says what it saw**:
`PromptBox.whyUnreadable` gives undrawn, hidden cursor, cursor off the
grid, or the cursor's position and the row it sat on, and that sentence
lands in the overlay record that `ccc clear <ref> --status` prints. The
next loss names its shape.

**What a clear does to a notification, measured once on sonnet**
(fixture eec7ffce, auto mode, `--no-rc`). The session started `sleep 60;
echo …` with `run_in_background` and ended its turn. ccc fired the armed
clear at 07:21:08Z, 64 s before the task would exit. The new transcript
(9c08635a) reads `/clear`, then the `--then` prompt at 07:21:08Z, then a
cross-session message sent after the clear (enqueued/dequeued 07:21:17Z),
then the task's own `<task-notification>` at 07:22:03Z, also enqueued and
dequeued. **The clear did not kill the background task, and the
notification of a task started before the clear is delivered to the
cleared session, after the `--then` turn.** Nothing went to the old
transcript after its own turn ended. One model, one run: the queue is
the harness's, which makes it unlikely to vary by model, but a harness
fact measured on one model gets re-run on a second before it is
generalized (the haiku-only `--permission-mode` rewrite of 2026-09-07 is
why).

## Cut as v0.1.38 (2026-10-01)

`v0.1.38`, build **255**, 5,348,403 bytes, notarized and published to both
CDN keys. The live feed's `length=` matches the zip's real
`content-length` (`ota verify --feed ccc`: `ok … version 255 length
5348403`), and `scripts/install --dist` put the released bytes on studio
(`ccc 0.1.38 (255)`). This time master was fast-forwarded to the bump
before the tag, so the tag, master and the branch all named `5e1bf5b` at
the cut. This note follows the tag, as every cut's note does.

What it carries for attrition's commander and lanes: `ccc clear <ref>
--status`, `ccc update <ref> --keep-conflicts` (exit 3), the fire path's
ten-second re-read, and a refusal that names what it saw. Fourteen
commits since `v0.1.37`: those three, the bump, and ten of the
2026-09-17 merge and update work that had not been cut yet.

**Read on the released bytes**, off `/opt/homebrew/bin/ccc`: `ccc clear
3c382923 --status` prints `no clear is armed on 3c382923; last: 4h49m ago
· the clear on 3c382923 did not fire: 3c382923's prompt box cannot be
read; nothing was typed`. That is the 02:43:31Z record above, now visible
to the session it was about. The next refusal of that kind will carry the
cursor and the row it saw.

## forget — what `claude rm` takes, and a clear from another session (2026-10-07)

Asked by attrition's steer: its `spawn --replace` hand-offs left a stopped
row per hand-off on `worktree-replan-pdb`, a worktree several sessions
share (21 GB target), and `ccc rm` read as the verb that takes the tree.

**`claude rm` takes a worktree only when the job file names one.** Owned
fixtures, harness 2.1.285, haiku, `~/cc-test/rmfx` (a repo with a bare
remote; `worktree-shared` clean and pushed, the worst case):

- two sessions `ccc spawn --cwd …/worktrees/shared`; `claude stop` one,
  `claude rm` each → `removed <id>`, exit 0, **no `worktree:` line**;
  `git worktree list` still shows `shared` and the branch after both,
  including the last one standing in it. Their `state.json` carries no
  `worktree*` key.
- one `ccc spawn --cwd <repo> --worktree=fxcut` → its `state.json` carries
  `worktreePath` and `worktreeBranch`; `claude rm` → `removed <id>` then
  `worktree: “…/fxcut”`, and the tree is gone.

So the six replan-pdb rows (no `worktreePath`, `respawnFlags` without
`--worktree`, no `ccc-cut` in attrition's config) were row-only for `ccc
rm`; steer ran it on the four archived ones and the tree, branch and target
stayed.

**`status` and `pid` arrive together, only while a process is attached.**
`claude agents --json --all`, 15 background rows: `working` 7/7 with both;
`done` 7 with neither and 1 with both — the live steer, `done/busy`. So
`done` ends a turn, not a session, and `ForgetGuard` refuses either field.

**`ccc forget`, live on the debug build** (same fixture repo): a session
still up → `… is blocked; forget drops finished rows — ccc stop … first`,
exit 1; a stopped `--worktree=fgcut` session → `… owns the worktree
…/fgcut — the harness cut it …`, exit 1, nothing removed; a stopped `--cwd`
session in `shared` → `{forgotten: true, said: "removed 268c2be7"}`, exit
0, `shared` intact, the row off the roster.

**A cross-session clear fires.** Fixture `3259b487` (haiku, `~/cc-test`),
a private headless ccc on its own socket and overlay
(`private-headless-ccc` shape); *this* session ran `ccc clear fx-clear-x
--then "Reply with exactly: CROSS-CLEAR-FIRED"` → `armed: true`; within
seconds `--status` read `last: 3s ago · cleared 3259b487, then: …` and the
snapshot showed `❯ /clear`, the prompt, and `⏺ CROSS-CLEAR-FIRED`. Nothing
in the arm or fire path reads the caller; the help's "the caller is
normally the commander on its own ref" described the first user and now
says so.
