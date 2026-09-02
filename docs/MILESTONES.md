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
  Experiment 2 (single attach across two Macs).
- **v3 — notifications.** From the poll first (`blocked` / `waitingFor`);
  the Notification hook on localhost only for what the roster cannot show;
  studio ↔ air derive from each other's roster, no forwarding.
- **v4 — the roster, ours.** Archive, pin, group, sort in an overlay keyed by
  session id under Application Support; done vs stopped vs archived.
- **v5 — spawn.** `claude --bg` with cwd, model, prompt, agent; drafts via
  `/fork` with no prompt; worktree awareness.
- **later** — peek/reply without attach (experiment 4); RC-free approvals via
  the PermissionRequest hook; the phone, if the Mac app earns it.
