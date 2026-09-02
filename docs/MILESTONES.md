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
  2. **Poll fan-out.** One poller per host, merged; per-host error and shape
     issues (one unreachable host must never blank the roster or raise a
     global banner); concurrent ticks so a 5 s timeout on one host cannot
     delay the 149 ms local poll. **Reframed 2026-09-02 (docs/DESIGN.md
     §4b): the thing that sleeps is the client, not the host** — air runs no
     sessions and studio is always up — so the slice's real content is
     reconnect hygiene, and the measured bug to fix is that ssh never evicts
     a wedged master (a 215 ms poll becomes a permanent 5.3 s one; unlinking
     the socket restores it). Carries one known display bug from slice 1:
     both roster faces shorten a cwd by substituting *this* Mac's home path,
     which is wrong for a host whose username differs (invisible against
     `loop`, since it is the same machine; real now — air's user is
     `rf-air`, studio's is `rf-studio`). **Measured with a real lid
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
- **v3 — notifications.** From the poll first (`blocked` / `waitingFor`);
  the Notification hook on localhost only for what the roster cannot show;
  studio ↔ air derive from each other's roster, no forwarding.
- **v4 — the roster, ours.** Archive, pin, group, sort in an overlay keyed by
  session id under Application Support; done vs stopped vs archived.
- **v5 — spawn.** `claude --bg` with cwd, model, prompt, agent; drafts via
  `/fork` with no prompt; worktree awareness.
- **later** — peek/reply without attach (experiment 4); RC-free approvals via
  the PermissionRequest hook; the phone, if the Mac app earns it.
