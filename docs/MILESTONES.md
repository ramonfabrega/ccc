# Queue

Each milestone is comparable against `claude agents` on its own. Experiments
(docs/HARNESS.md) gate the feature that needs them, not the milestone before.

- **v0 — the agents view, local.** Roster from `claude agents --json --all`
  (2 s poll, lenient decode, shape-change banner); one pane behind the seam
  (SwiftTerm stand-in); attach / detach; model column from the transcript
  tail; headless mode + `ccc list|attach|snapshot`; one recorded session as
  the fixture; headless render test. Experiments 1 and 3.
- **v1 — the SOTA pane.** libghostty-vt vendored and pinned; the Metal
  renderer; forkpty; the six checks; swap when it wins. **Done 2026-09-02:**
  six of six, swapped, SwiftTerm demoted to `CCC_CORE=swiftterm`.
- **v2 — ssh hosts.** Host picker over the tailnet; one multiplexed ssh
  connection per host; roster, attach, spawn behind the prefix; TERM policy.
  Experiment 2 (single attach across two Macs). Slices, in dependency order:
  1. **Addressing — done 2026-09-02.** `SessionRef` (`host:id`, bare when
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
  2. **Poll fan-out — done 2026-09-02.** One `HostPoller` per host, merged
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
  3. **The model column over ssh — done 2026-09-02.** Settled by
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
  4. **Host picker + TERM policy**, and the shared-size question: the
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
- **Release lane — done 2026-09-02, v0.1.0 cut.** The fleet's mux/disk
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
  length 4509224 both sides). Studio runs it. The other half of §6a's
  proof — air's Sparkle installing this cut — is air's to show.
  **v0.1.10, same night (build 85):** v5 slices 1 and 2 — `ccc spawn`,
  the New Session sheet, the draft reading. Notarized first submission,
  one item, live length 4623978 both sides; GitHub release v0.1.10;
  studio on the cut.
- **v3 — notifications.** From the poll first (`blocked` / `waitingFor`);
  the Notification hook on localhost only for what the roster cannot show;
  studio ↔ air derive from each other's roster, no forwarding.
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
- **v4 — the roster, ours.** Archive, pin, group, sort in an overlay keyed by
  session id under Application Support; done vs stopped vs archived.
  **Delete is not ours — done 2026-09-02:** `ccc rm <ref>` is the
  harness's `claude rm` behind the host prefix, answer and exit status
  passed through, so the agents view's guard is inherited rather than
  re-decided (docs/HARNESS.md: a dirty worktree is `kept`, exit 1, the
  row stays). Proved on ten sessions: one kept while its worktree held an
  untracked file, removed once it was dropped, nine removed outright.
  The roster's Delete gesture waits for the v4 roster work; archive is
  ours and stays here.
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
- **v5 — spawn.** `claude --bg` with cwd, model, prompt, agent; drafts;
  worktree awareness.
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
- **v6 — worktree awareness.** The row knows its branch and how it stands
  against master, and the context menu lands it.
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
  repository are two different asks. 237 tests. — done 2026-09-02, late.** Noticed by the user on
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
- **v7 — keyboard parity.** What the agents view's keys do, ours do.
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
- **next** (what plan.md carried when it was retired 2026-09-02, late;
  the queue is this file from here on). The sequence agreed the same
  night, one confirmed before the next, comes first:
  1. **Update from master** (v6 slice 6) — **done 2026-09-03, above.**
     As agreed: GitHub's "Update branch" as a
     submenu item enabled while `↓` is above zero — `git merge <base>`
     *inside the worktree*, a merge, never a rewrite; refuses a dirty
     worktree (so it only acts at a commit boundary, which is what makes
     it safe under a running session) and backs out of a conflict. Twin
     `ccc update <ref>`. On a conflict, the refusal offers the one thing
     a menu cannot and a session can: **Ask the session to merge
     master**, which sends "merge master into this branch and resolve
     the conflicts" as a prompt through the pane (`ccc send`'s road).
  2. **Fetch, and Pull master** (v6 slice 7) — **done 2026-09-03,
     above.** As agreed: `⇣N` marks from the
     last-fetched remote refs; Fetch on demand from the submenu, once on
     launch and on wake (a timer only after those are measured), twin
     `ccc fetch <ref>`; Pull master fast-forward only, the mirror of
     Push master, twin `ccc pull <ref>`. Into the worktree branch is
     rebase's problem by another name and stays out.
  Then, in no order:
  3. **Host picker** off `tailscale status --json` (MagicDNS names are
     the ssh destinations; Bonjour never crosses the tailnet). With it,
     the §4c question: whether a secondary viewer renders the shared grid
     as-is instead of resizing it (last-resize-wins today). Needs air.
     **Blocked on one toggle, measured 2026-09-03:** air is up on the
     tailnet (active, direct) but `ssh air` answers *"connect to host air
     port 22: Connection refused"* — no Remote Login, exactly as
     RELEASES.md says — and `ccc hosts` still lists only `local`. So
     every ssh proof to date is `localhost` wearing a costume, and four
     threads (this, §4c, item 6's two measurements, and whether copy over
     ssh lands on the wrong Mac — v7 slice 2) wait on Sharing ▸ Remote
     Login on air. **The order here is backwards and should invert:**
     `ccc hosts add air` by hand and prove the hop first; a picker is a
     convenience over a host list that has never held a real remote.
  4. **Debt:** `ClaudeCLI.run` blocks a pool thread per host for up to
     its timeout (`readDataToEndOfFile`). Fine at two or three hosts; a
     nonblocking read before the host list grows.
  5. **Small leftovers:** a sort by model; the Session menu's archive/pin
     items (the context menu has them); `ccc window show` when another
     app holds focus — measured 2026-09-02 with a Wine window in front:
     `NSApp.activate()` is cooperative since macOS 14 and the window
     stayed behind, while `open -a` brought it front, so the CLI side of
     `show` should activate through `NSWorkspace`.
  6. **Open measurements, on air:** the long sleep (`~/lidtest.py` left
     running on air, appending to `~/lidtest.log`; `scp` it to studio
     when air is up — it decides whether the eviction ever fires,
     `ccc stats` → `evictions`), and the first real sleep for the
     remote-pane reattach (`PaneController.reattachIfSleepKilledIt`).
  7. **Housekeeping:** remote branches `hotfix-gridbuilder`,
     `worktree-icon`, `worktree-v0`, `worktree-v1` are merged history;
     delete when convenient.
  8. **The colours are off** — raised by the user 2026-09-03 ("feel
     off / opaque'd", not what iTerm shows), and **already diagnosed, not
     yet fixed.** Two stacking causes, both found by reading rather than
     guessing. (a) `ghostty_terminal_set` is called with exactly three
     options — userdata, write_pty, scrollback — so
     `GHOSTTY_TERMINAL_OPT_COLOR_{FOREGROUND,BACKGROUND,CURSOR,PALETTE}`
     are **never set** and every colour is the core's default. The
     codebase already knows: `MetalRenderer.readableForeground` logs "the
     palette is unset" and substitutes a fallback so default-coloured text
     is not invisible, with the comment "the real repair belongs wherever
     the frame's palette is filled in" — that repair is this item, and the
     fallback should go with it. (b) `MetalPaneView` uses `.bgra8Unorm`
     with **no `colorspace` on the layer**, so the pane is unmanaged while
     iTerm is colour-managed — on a P3 display that alone moves every
     value. **Do the measurement first:** the same content in iTerm and in
     ccc, a real `screencapture` of both, and compare the RGB of known
     cells. That says which cause is doing the damage before either is
     touched, and it is the house rule (the human's screen is the oracle).
  9. **The attach transition blanks the pane** — raised the same day, and
     diagnosed: `PaneController.switchTo` does `await session.detach()`,
     *then* `attach()`, which builds a brand-new host — a blank grid —
     which the window mounts before the new `claude attach` has drawn.
     Experiment 3 measured the TUI taking up to 12 s to paint over ssh
     (`waitUntilDrawn`'s timeout is 8 s), so the blank is not a flicker,
     it is the wait. The fix is available *because* of experiment 2: the
     daemon accepts concurrent attaches, so the new session can start
     **behind** the old one, reuse the existing `waitUntilDrawn`, and the
     view swap only happens once it has painted — then the old one
     detaches. No blank frame at all. Open question for the doing: which
     pane owns the keyboard during the overlap.
  Dropped 2026-09-02: a "forked from" mark on the row; permission mode,
  effort and worktree as sheet fields (the command has them; nobody has
  missed them in the sheet).
- **later** — peek/reply without attach (experiment 4); RC-free approvals via
  the PermissionRequest hook; the phone, if the Mac app earns it.
