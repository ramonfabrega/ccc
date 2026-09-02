# plan.md — ephemeral handoff (v2 slice 2, poll fan-out)

**Status 2026-09-02.** Ephemeral: delete when slice 2 lands. Durable findings
belong in `docs/DESIGN.md` §4a/§4b and `docs/MILESTONES.md`, which are
already updated — read those first, this file only carries what is *not*
settled.

Worktree `.claude/worktrees/v2`, branch `worktree-v2`, 121 tests green.
`master` fast-forwards to it (a merge of master into this branch keeps that
true; do it again after every master sync or the branches re-diverge).

---

## The question for the research stretch

**Prior art on keeping one long-lived ssh connection healthy across a laptop
suspend/resume, and what to steal.** Bounded, verifiable, and independent of
the local experiments — which is exactly why it is the half worth handing
off. Do NOT redesign the fan-out from first principles here; the binding
facts are empirical and already measured in §4b.

Specifically:

1. **mosh** — it exists because ssh handles roaming badly. What is its
   actual model (UDP + SSP, server-side state), and is any part of it
   applicable to a *control* channel we only use for short command
   invocations, or is it strictly a terminal-session answer? We attach a PTY
   over ssh too, so this may cut both ways: the roster poll and the attached
   pane have different needs.
2. **autossh** — what does it actually monitor, and does its approach (echo
   port heartbeats, restart on failure) beat "notice a slow poll, unlink the
   master socket" for our case? Its assumptions predate `ControlPersist`.
3. **Tailscale** — the fleet is on a tailnet. Does it already paper over
   roaming (stable addresses, connection re-establishment) such that the
   wedged-master case is rarer on the tailnet than the localhost experiment
   suggests? This one could invalidate a chunk of the slice — worth knowing
   early.
4. **OpenSSH option set** — is there a documented, recommended combination
   for laptop-suspend clients? We currently run `ControlMaster=auto`,
   `ControlPersist=60`, `ConnectTimeout=5`, `BatchMode=yes`. §4b showed
   `ServerAliveInterval` is *not* the missing piece we assumed (ConnectTimeout
   already bounds the wedged-mux wait), so the question is what else is real
   versus cargo-culted from pre-`ControlPersist` blog posts.

Deliverable: findings appended to `docs/DESIGN.md` §4b under a clear
"prior art" heading, with the claim and its source, and an explicit
recommendation on the option set. Cite what was actually read; do not assert
ssh behaviour that was not either read in the man page or measured here —
this project has twice today had a confident prediction reversed by a
measurement, including in this exact area.

## The one experiment that is still open

Whether a **real lid-close/wake** produces the wedged-master shape at all, or
whether macOS tears the socket down cleanly. §4b measures a *simulated* wedge
(`kill -STOP`); the simulation may be harsher than reality. If reality is the
clean teardown, the `kill -9` row applies (recovers by itself in 316 ms) and
most of the reconnect work evaporates.

Cheapest protocol: leave a poll loop running against studio, close the lid,
reopen after a few minutes, and read the first poll's latency and whether the
socket survived. Needs the human and a real lid; it cannot be simulated.

## Then implement (not before the above)

Order matters — the failure model decides the design:

1. `RosterPoller.State` → per-host slots. Today one `error: String?` and one
   `issues` array cover the whole roster, and `tick()` returns early on
   error, so one unreachable host blanks everything.
2. N pollers, concurrent ticks, merged at read time (not a shared row array
   written from N tasks).
3. Evict a wedged master on a degraded poll (§4b's measured fix), plus
   `NSWorkspace.didWakeNotification` → drop master + immediate re-poll.
4. Fix the cwd `~` substitution: both roster faces use *this* Mac's home
   path, wrong for a host with a different username (invisible against
   `loop`, which is the same machine).
5. Stale-row rendering with an age, once (3) says how often a row can
   actually go stale.
