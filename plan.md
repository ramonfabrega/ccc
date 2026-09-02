# plan.md — ephemeral handoff (v3 started)

**Status 2026-09-02.** v2 slices 1–3, install polish, and the dev/release
lane split are in `docs/MILESTONES.md`; v0.1.4 is on the feed and air's
Sparkle update to it is confirmed. Studio runs the dev lane
(`scripts/install`; `--dist` puts the cut back). This file carries only
what is *not* settled.

Worktree `.claude/worktrees/v2`, branch `worktree-v2`, 144 tests green.
`master` fast-forwards to it (a merge of master into this branch keeps that
true; do it again after every master sync or the branches re-diverge).
No release is owed yet; cadence is "actionable only".

## Current: v3 notifications

Slice 1 landed (docs/MILESTONES.md v3): detector, `ccc watch`, banners
with click-to-attach, `notifications` in `ccc stats`. Studio's app is
**authorized** (System Settings → Notifications → Claude Code Command; the
first automated answer to the permission banner hit "Don't Allow", and
`ccc stats` is how that was seen). Air will get the permission banner on
its first launch of a build ≥ 58.

Slice 2 candidates, none started: a session stopped by your own hand
still banners ("stopped") — decided 2026-09-02 to leave it until it annoys,
then judge; a per-host mute; the Notification hook for
what the roster cannot show. `ccc rm <ref>` exists (the harness's guard,
inherited); the proof sessions are gone through it. The roster's Delete
gesture and archive are v4.

Polish parked until the pane is the subject again: the banner draws under
the title bar (fix when touching the window controller for click-to-attach)
and the terminal clips a little at its bounds.

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
3. **When a cut is next owed**, air gets install polish with it:
   `ccc install-cli` there makes `/opt/homebrew/bin/ccc`, which is where
   `ccc hosts add` looks, and `hosts check` from studio then reads air's
   build.
4. **Shared size** (§4c) — slice 4's remainder. So is the host picker;
   seed it from `tailscale status --json` (MagicDNS names are the ssh
   destinations; Bonjour is link-local and never crosses the tailnet).
5. **Debt:** `ClaudeCLI.run` blocks a pool thread per host for up to its
   timeout (`readDataToEndOfFile`). Fine at two or three hosts; a
   nonblocking read before the host list grows.

`scripts/attach-probe` is the tool for anything attach-shaped: hold, type,
resize, SIGUSR1 to report mid-hold.
