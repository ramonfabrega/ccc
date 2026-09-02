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
  Sparkle guard for unbundled runs and the `hosts add` probe.
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
  Open for slice 2: whether a session *you* just stopped by hand deserves
  a banner; a per-host mute; the hook for what the roster cannot show.
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
- **v5 — spawn.** `claude --bg` with cwd, model, prompt, agent; drafts via
  `/fork` with no prompt; worktree awareness.
- **later** — peek/reply without attach (experiment 4); RC-free approvals via
  the PermissionRequest hook; the phone, if the Mac app earns it.
