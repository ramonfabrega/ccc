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
  Next: `/fork`-style drafts *from* a session; worktree awareness in the
  sheet.
- **later** — peek/reply without attach (experiment 4); RC-free approvals via
  the PermissionRequest hook; the phone, if the Mac app earns it.
