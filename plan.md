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
3. **Install on air.** Nothing has run on air yet. v0.1.0 is cut
   (RELEASES.md): download https://cdn.ramonfabrega.com/ccc/ccc-latest.zip,
   drag to `~/Applications`, launch, symlink the CLI, then
   `ccc hosts add studio` (learns home, `/Users/rf-studio`),
   `ccc hosts check`. Studio already runs the v0.1.0 build (build 47).
   Every later cut reaches both Macs through Sparkle.
4. **Shared size** (§4c) — slice 4. So is the host picker; seed it from
   `tailscale status --json` (MagicDNS names are the ssh destinations;
   Bonjour is link-local and never crosses the tailnet).

`scripts/attach-probe` is the tool for anything attach-shaped: hold, type,
resize, SIGUSR1 to report mid-hold.
