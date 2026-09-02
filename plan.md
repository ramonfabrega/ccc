# plan.md — ephemeral handoff (v2 slice 2, poll fan-out)

**Status 2026-09-02, after the sync.** Ephemeral: delete when slice 2 lands.
Durable findings are in `docs/DESIGN.md` §4b (real-lid measurement), §4c
(the daemon multiplexes viewers), `docs/HARNESS.md` experiment 2, and
`docs/MILESTONES.md`; read those first. This file carries only what is
*not* settled.

Worktree `.claude/worktrees/v2`, branch `worktree-v2`, 121 tests green.
`master` fast-forwards to it (a merge of master into this branch keeps that
true; do it again after every master sync or the branches re-diverge).

---

## Settled today (do not reopen)

- **The pane over ssh is `ssh -t <host> claude attach <id>` on every Mac.**
  The daemon accepts every attach and mirrors one PTY to all viewers
  (§4c). No ccc-to-ccc stream, no lock, no steal. Server versus client is
  only the host list.
- **A two-minute lid close on the tailnet is clean** (§4b): master
  survives, first poll 2.1 s, then normal. Eviction stays as insurance.
- **Real hosts:** air's user is `rf-air`, studio's is `rf-studio`. The cwd
  `~` bug is now reproducible for real.

## Still open

1. **A long sleep** (thirty minutes, then overnight). `~/lidtest.py` is on
   air and appends to `~/lidtest.log`; the user closes the lid whenever and
   ships the log with `scp ~/lidtest.log studio:~/lidtest-air.log`. This
   decides whether eviction ever fires in practice. Not blocking: the code
   is the same either way, only its importance changes.
2. **The research stretch** in the previous plan (mosh, autossh, Tailscale,
   OpenSSH option set) is mostly moot after the measurement. What survives
   of it: whether Tailscale's stable addressing is *why* the master
   survived, and what a long sleep does to it. Answer with the log, not a
   subagent.
3. **Shared size** (§4c) — slice 4, nice-to-have.

## Then implement, in this order

1. `RosterPoller.State` → per-host slots. One `error` and one `issues`
   cover the whole roster today, and `tick()` returns early on error, so
   one unreachable host blanks everything.
2. N pollers, concurrent ticks, merged at read time; one in-flight tick per
   host, never stacked.
3. Evict a wedged master on a degraded poll (> 3 s and then succeeded:
   unlink the socket, never `ssh -O exit`, which talks to the wedged master
   and pays the same wait), plus `NSWorkspace.didWakeNotification` → drop
   master + immediate re-poll, with a command twin (`ccc hosts reconnect`).
4. Fix the cwd `~` substitution with the far side's real home (learn it at
   `hosts add` / `hosts check`, store it in hosts.json, so it works for a
   host without ccc too).
5. `ccc list` defaults to every host, `--host` filters, per-host errors on
   stderr, exit 0 when at least one host answered.
6. Reattach on wake for a remote pane: the attach ssh may die on a long
   sleep; re-run the same argv, the draft comes back with the session
   (experiment 5).

`scripts/attach-probe` is the tool for anything attach-shaped: hold, type,
resize, SIGUSR1 to report mid-hold.
