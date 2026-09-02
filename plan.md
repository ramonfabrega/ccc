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

## Current: v3 notifications, slice 1

The roster already carries `blocked` / `waitingFor` for every host, so
"it's your turn" on every Mac needs no forwarding. Cut as:

- **Transition detector** in the poller: a session that becomes blocked,
  or whose `waitingFor` changes, is one event; deduped per session and
  prompt so a 2 s poll never repeats. Also: a session that ends. Testable
  headless against two roster snapshots.
- **`ccc watch`** streams the same events as lines or `--json` — the
  command twin, how an agent sees what the notification center shows.
- **One macOS notification per event** (UNUserNotificationCenter, needs
  the bundle id — the dev lane has it), click → attach. The Notification
  hook stays banked; it supplements only what the roster cannot show.

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
