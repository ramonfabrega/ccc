# plan.md — ephemeral handoff (v4 started)

**Status 2026-09-02.** v2 slices 1–3, install polish, the dev/release
lane split, v3 slice 1 and v4 slice 1 are in `docs/MILESTONES.md`; v0.1.5
is on the feed and air runs it. Studio runs the dev lane
(`scripts/install`; `--dist` puts the cut back). This file carries only
what is *not* settled.

Worktree `.claude/worktrees/v2`, branch `worktree-v2`, 173 tests green.
`master` fast-forwards to it (a merge of master into this branch keeps that
true; do it again after every master sync or the branches re-diverge).
**v0.1.7 is cut and on the feed** (2026-09-02 night: v0.1.6 carried v4
and the icon, v0.1.7 the banner fix air found within the hour). Origin
master was level at v0.1.6's docs commit; it wants another
`git merge --ff-only worktree-v2` for v0.1.7. Studio runs the cut
(`scripts/install --dist`). **Air took v0.1.6 by hand** and linked its
command from the menu; v0.1.7 reaches it through Sparkle. Left there:
answer the notification permission banner once, `ccc stats` on air says
`authorized` when done.

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
3. **Air's v0.1.7 update** (Sparkle, from the feed) is the first update
   air takes on a build with the v4 verbs; its command is linked
   (`/opt/homebrew/bin/ccc` into the bundle), so nothing else is owed
   there. The banner fix has not been seen by a hand on air yet.
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
   Sparkle — was split as asked, and the patch is **reviewed and ready:
   `origin/ota-migration-v017` (9d7ce79), one commit directly on v0.1.7,
   a fast-forward for `worktree-v2`.** Reviewed 2026-09-02: merges clean,
   174 tests, zero Sparkle in the test bundle, ota pinned to a GitHub
   revision, typealiases instead of `@_exported`. Two things gate the
   landing, both the user's: install `ota` on studio (`~/code/fun/ota`,
   its `scripts/install`; the branch's scripts refuse without it), and
   §6a's proof — a real `scripts/package` through `ota release` that
   air's Sparkle installs — before the old lane retires. The superseded
   `origin/ota-migration` (d475fb8) can be deleted.

`scripts/attach-probe` is the tool for anything attach-shaped: hold, type,
resize, SIGUSR1 to report mid-hold.
