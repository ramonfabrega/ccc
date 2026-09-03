# plan.md — ephemeral handoff (v5 in progress)

**Status 2026-09-02, late.** v0 through v5 slice 3 are in
`docs/MILESTONES.md`; **v0.1.10 (build 85) is the cut on air**; studio
runs the **dev bundle (build 88, rebuilt with the attach fix)** with slice 3 so a hand can try the
fork sheet — `scripts/install --dist` puts the cut back. 211 tests. This
file carries only what is *not* settled.

Worktree `.claude/worktrees/v2`, branch `worktree-v2`. `master`
fast-forwards to it; merge master back after any master-side commit or
the branches re-diverge. The dev loop on studio is `scripts/install`
(dev bundle, `ccc·dev`); `--dist` puts the cut back.

## Current: v5, spawn

Slices 1–3 landed 2026-09-02 (docs/MILESTONES.md v5): `ccc spawn` and
the New Session sheet; the draft reading; and **the fork** — `ccc spawn
--from <ref>`, the sheet's From row (⇧⌘N, the row's "Fork…", `f`), one
definition (`SpawnRequest.from` → `--resume <session id>
--fork-session`). Harness facts in docs/HARNESS.md: the fork needs the
*full* session id (the short one parks the new session at a resume
picker), a prompt-less fork is a draft that restores the transcript on
its first prompt, a fork without `--name` inherits the source's name.

**Owed a hand (studio, build 88):** the fork sheet with a typed prompt —
⇧⌘N over an attached session, type, ⌘↩ — and the "Attach when started"
switch from the source to the fork (fixed after the proof found attach
refusing "busy"; not yet seen by a hand). `f` on a selected row and the
context menu's "Fork…" have not been clicked by a hand either. The
`ccc-v5-src` session (`1e7c5066`, `~/cc-test`, haiku) is left in the
roster as a thing to fork from; `ccc rm 1e7c5066` when done.

**Noted by the user 2026-09-02:** clicking the roster's left column
feels iffy at times — for the deep UI pass, with the banner-under-the-
title-bar and the terminal's edge clipping (below).

Next slices: worktree awareness in the sheet (the harness isolates
before the first edit on its own, so this is display more than
dispatch: `state.json` carries `worktreePath`); a "forked from" mark on
the row (`roster.json`'s `dispatch.launch{sessionId, fork}` says it);
permission mode / effort / worktree as sheet fields.

**Next cut** (v0.1.11) carries slice 3 to air; `ota` is pinned to
45f3a63 and its master has 187ec67 ("refuse to release an installed
app" — ccc releases from `.build/dist/ccc.app`, unaffected); take it
with the pin move.

## v4, the roster ours (landed)

Overlay, archive/pin, group/sort, the app icon — all in
docs/MILESTONES.md v4. Left for a later slice: the main menu's Session
items for archive/pin (the context menu has them); a sort by model.

v3 slice 2 (per-host mute, `ccc hook`) is landed and confirmed by a hand
on v0.1.10 on both Macs. Left as decided: a session stopped by your own
hand still banners, until it annoys.

Polish parked until the pane is the subject again: the banner draws under
the title bar (fix when touching the window controller for click-to-attach)
and the terminal clips a little at its bounds.

## Open

1. **The long sleep** (overnight). `~/lidtest.py` was left running on
   air, appending to `~/lidtest.log`; air refused ssh on 2026-09-02
   evening (asleep), so the overnight log is still there — ship it with
   `scp ~/lidtest.log studio:~/lidtest-air.log` (studio's copy holds only
   the two-minute run). Decides whether the eviction ever fires in
   practice (`ccc stats` → `evictions`). Not blocking.
2. **Reattach on wake for a remote pane** is written
   (`PaneController.reattachIfSleepKilledIt`: ssh exit 255 within 20 s of
   `didWake` → same argv again) but has not seen a real sleep. First real
   use is on air.
3. **Shared size** (§4c) — slice 4's remainder. So is the host picker;
   seed it from `tailscale status --json` (MagicDNS names are the ssh
   destinations; Bonjour is link-local and never crosses the tailnet).
4. **Debt:** `ClaudeCLI.run` blocks a pool thread per host for up to its
   timeout (`readDataToEndOfFile`). Fine at two or three hosts; a
   nonblocking read before the host list grows.
5. **ota**: pinned to 45f3a63 until it tags; its master's 187ec67 comes
   with the next pin move. The superseded branches `origin/ota-migration`
   and `origin/ota-migration-v017` can be deleted.

`scripts/attach-probe` is the tool for anything attach-shaped: hold, type,
resize, SIGUSR1 to report mid-hold. `scripts/spawn-probe` is the tool for
anything `--bg`-shaped, `--` passing `--flag=value` words to the harness.
