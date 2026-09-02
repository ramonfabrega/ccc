# plan.md — ephemeral handoff (v2, after slice 2)

**Status 2026-09-02.** Slice 2 (poll fan-out + reconnect hygiene) landed;
see `docs/MILESTONES.md` v2.2 and `docs/DESIGN.md` §4b/§4c for what was
measured and built. This file carries only what is *not* settled.

Worktree `.claude/worktrees/v2`, branch `worktree-v2`, 132 tests green.
`master` fast-forwards to it (a merge of master into this branch keeps that
true; do it again after every master sync or the branches re-diverge).

## Open

1. **The long sleep** (overnight, tonight). `~/lidtest.py` is still running
   on air, appending to `~/lidtest.log`; ship it with
   `scp ~/lidtest.log studio:~/lidtest-air.log`. Decides whether the
   eviction ever fires in practice (`ccc stats` → `evictions`). Not
   blocking; the code is the same either way.
2. **Reattach on wake for a remote pane** is written
   (`PaneController.reattachIfSleepKilledIt`: ssh exit 255 within 20 s of
   `didWake` → same argv again) but has not seen a real sleep. First real
   use is on air, once ccc is installed there.
3. **Air runs v0.1.1** (installed by hand 2026-09-02; studio is its host,
   `ccc hosts check` → 315 ms, 21 sessions, 18 with a model). Its first
   "Check for Updates…" was refused: v0.1.3's binary was built for
   macOS 26 (a bisect leftover). v0.1.4 (build 53, macOS ≥ 14.0, verified
   on the live feed) is on the CDN; air's update to it is the end-to-end
   proof. Studio runs v0.1.4 and renders on screen (real screenshot).
   Queue: the `SUFeedURL` gate belongs in the fleet's Updater template
   (lore), and scry has the same bare-binary dev lane.
4. **Shared size** (§4c) — slice 4. So is the host picker; seed it from
   `tailscale status --json` (MagicDNS names are the ssh destinations;
   Bonjour is link-local and never crosses the tailnet).

`scripts/attach-probe` is the tool for anything attach-shaped: hold, type,
resize, SIGUSR1 to report mid-hold.
