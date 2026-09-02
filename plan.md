# plan.md — ephemeral handoff (v4 started)

**Status 2026-09-02.** v2 slices 1–3, install polish, the dev/release
lane split, v3 slice 1 and v4 slice 1 are in `docs/MILESTONES.md`; v0.1.5
is on the feed and air runs it. Studio runs the dev lane
(`scripts/install`; `--dist` puts the cut back). This file carries only
what is *not* settled.

Worktree `.claude/worktrees/v2`, branch `worktree-v2`, 173 tests green.
`master` fast-forwards to it (a merge of master into this branch keeps that
true; do it again after every master sync or the branches re-diverge).
**v0.1.6 (build 68) is cut and on the feed** (2026-09-02, tag pushed,
GitHub Release up); **origin master is still at v0.1.5** — the main
checkout wants `git merge --ff-only worktree-v2` on master and a push,
which this session left to a hand (it never pushes master). Studio runs
the cut (`scripts/install --dist`). **Air is on v0.1.5** and will be
offered v0.1.6 by Sparkle; that update is what gives air the v4 verbs
and the icon. Left there: answer the notification permission banner
once, `ccc stats` on air says `authorized` when done; then `ccc hosts
check air` from studio is not possible (no Remote Login), so air's own
`ccc version` is the proof.

## Current: v4, the roster ours

Slice 1 landed (docs/MILESTONES.md v4): the overlay
(`~/Library/Application Support/ccc/roster.json`, lives with the
session's host — docs/DESIGN.md §8), `ccc archive|unarchive|pin|unpin
<ref>`, `ccc list --archived`, the window's fold toggle, `a` / `p` / ⌫ on
the selected row, `Delete…` with its alert. Proved on the CLI face on
studio, and the window's fold and toggle on a real `screencapture`
(`ccc peek` omits SwiftUI buttons) — the context menu, the keys and the
Delete alert have not been clicked by a hand yet. **Air's ccc predates
the verbs** (v0.1.5 has no `archive`), so until a cut lands there:
studio's marks on studio's sessions cross to air's roster (they ride
`ccc list --json`, which air already reads), but `ccc archive studio:x`
from air would exit 2 there — nothing on air can make a mark until air
takes the v0.1.6 update.

Slice 2 landed the same day: group (none/host/repo/state) and sort
(activity/name/started/folder) — View menu, the header's menu, and
`ccc list --group/--sort`. The app icon from the ccc-site session
(`worktree-icon`, `scripts/make-icon`, `Design/AppIcon.icns`) is merged;
`make-bundle` already copies it, so the next cut carries it. Left for a
later slice: the main menu's Session items for archive/pin (the context
menu has them); a sort by model.

v3 slice 2 candidates, none started: a session stopped by your own hand
still banners ("stopped") — decided 2026-09-02 to leave it until it annoys,
then judge; a per-host mute; the Notification hook for what the roster
cannot show.

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
3. **Air's v0.1.6 update** (Sparkle, from the feed) brings the v4 verbs
   and the icon; its command is already linked (`/opt/homebrew/bin/ccc`
   into the bundle), so nothing else is owed there.
4. **Shared size** (§4c) — slice 4's remainder. So is the host picker;
   seed it from `tailscale status --json` (MagicDNS names are the ssh
   destinations; Bonjour is link-local and never crosses the tailnet).
5. **Debt:** `ClaudeCLI.run` blocks a pool thread per host for up to its
   timeout (`readDataToEndOfFile`). Fine at two or three hosts; a
   nonblocking read before the host list grows.
6. **ota** (the release-tooling session, 2026-09-02) proposes replacing
   `scripts/package` + `make-bundle` + `Updater.swift` + half of
   `BuildInfo.swift` with `ota bundle` / `ota release` and an `OTA`
   package. Its seam question — OTA must split so CCCKit never links
   Sparkle — got this session's recommendation (split; `name` on
   OTA.BuildInfo; a patch to review, pinned to a revision until ota tags),
   with the user's word still owed: a new dependency is earned in
   docs/DESIGN.md (CLAUDE.md), and this one replaces the release lane.
   Nothing in ccc changes until the patch lands and is reviewed.

`scripts/attach-probe` is the tool for anything attach-shaped: hold, type,
resize, SIGUSR1 to report mid-hold.
