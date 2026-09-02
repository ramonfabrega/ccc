# plan.md — ephemeral handoff (v2, after install polish)

**Status 2026-09-02.** Slices 1–3 of v2 and the release lane are in
`docs/MILESTONES.md`; v0.1.4 is on the feed and air's Sparkle update to it
is confirmed (the end-to-end proof). Install polish landed (MILESTONES v2
slice 4). This file carries only what is *not* settled.

Worktree `.claude/worktrees/v2`, branch `worktree-v2`, 143 tests green.
`master` fast-forwards to it (a merge of master into this branch keeps that
true; do it again after every master sync or the branches re-diverge).

## Open

1. **The long sleep** (overnight). `~/lidtest.py` is still running on air,
   appending to `~/lidtest.log`; ship it with
   `scp ~/lidtest.log studio:~/lidtest-air.log`. Decides whether the
   eviction ever fires in practice (`ccc stats` → `evictions`). Not
   blocking; the code is the same either way. The two-minute run
   (2026-09-02 15:03–15:05) was clean: first poll 2.1 s, no eviction.
2. **Reattach on wake for a remote pane** is written
   (`PaneController.reattachIfSleepKilledIt`: ssh exit 255 within 20 s of
   `didWake` → same argv again) but has not seen a real sleep. First real
   use is on air.
3. **Cut v0.1.5** so air gets install polish: `ccc install-cli` there
   makes `/opt/homebrew/bin/ccc`, which is where `ccc hosts add` looks,
   and `hosts check` from studio will then read air's build.
4. **Shared size** (§4c) — slice 4's remainder. So is the host picker;
   seed it from `tailscale status --json` (MagicDNS names are the ssh
   destinations; Bonjour is link-local and never crosses the tailnet).
5. **Debt:** `ClaudeCLI.run` blocks a pool thread per host for up to its
   timeout (`readDataToEndOfFile`). Fine at two or three hosts; a
   nonblocking read before the host list grows.

`scripts/attach-probe` is the tool for anything attach-shaped: hold, type,
resize, SIGUSR1 to report mid-hold.
