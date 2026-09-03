# plan.md — ephemeral handoff (v5 in progress)

**Status 2026-09-02, end of night.** v0 through v5 slice 2 are in
`docs/MILESTONES.md`; **v0.1.10 (build 85) is the cut on every Mac** —
studio by `scripts/install --dist`, air through Sparkle — and master was
fast-forwarded to the branch by the user. 208 tests. This file carries
only what is *not* settled.

Worktree `.claude/worktrees/v2`, branch `worktree-v2`. `master`
fast-forwards to it; merge master back after any master-side commit or
the branches re-diverge. The dev loop on studio is `scripts/install`
(dev bundle, `ccc·dev`); `--dist` puts the cut back. **Confirmed by a
hand on v0.1.10, both Macs:** the New Session sheet, the mute submenu,
and the draft reading. Left on air: nothing owed.

## Current: v5, spawn

Slice 1 landed 2026-09-02 (docs/MILESTONES.md v5): `ccc spawn` and the
New Session sheet (⌘N, Session menu, the roster header's +), one
definition (`SpawnRequest`, `ClaudeCLI.spawn`) behind both; drafts are
`claude --bg` with no prompt (docs/HARNESS.md, measured — no `/fork`
needed). 199 tests. Proved on studio's CLI face, through `loop`
(localhost as a host, added for the proof and removed after), and in
the window by a real ⌘N, typed fields and ⌘↩ on the dev bundle (build
82). Slice 2, the same night: the draft reading (`DraftProbe` off the
daemon's `state.json`, `SessionRow.draft`, `isWaiting` everywhere "your
turn" is counted, `── drafts` under the state grouping, the detector's
key) — a fresh draft no longer banners, and the window's row is indigo
`draft · send a prompt to start`. 208 tests, proved on the CLI, `ccc
watch` and the window (build 83). **Confirmed by a hand 2026-09-02:**
the New Session sheet ("works flawless") and the View menu's mute
submenu ("working perfectly"), both on the v0.1.10 cut. Next slices: drafts *from* a session
(`/fork`), worktree awareness in the sheet (the harness isolates before
the first edit on its own, so this is display more than dispatch).
**v0.1.10 (build 85) is cut and on the feed** (2026-09-02 night, through
ota: notarized, one item, live length 4623978; GitHub release v0.1.10);
studio runs it (`scripts/install --dist`), air takes it through Sparkle
— that update is what puts ⌘N and the draft reading on air, and the
draft reading was confirmed on air the same night. Master is level.

## v4, the roster ours (landed)

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

v3 slice 2 landed 2026-09-02 (docs/MILESTONES.md v3): the per-host mute
(`ccc hosts mute|unmute`, `"mute": true` in hosts.json, View menu → Mute
Notifications From, the row's context menu) and `ccc hook`, the
Notification hook's receiver (`ccc hook --settings` prints the
settings.json entry; ccc never writes that file). 187 tests. Proved on
studio's CLI face and one real screencapture; the cut (0.1.8/76) went
back on studio afterwards. The settings entry is in the dotfiles'
settings.json (symlinked) and **the real hook has fired** on studio
from v0.1.9: `hook events 1 last "ccc-v3-hook needs permission"`. On
air the same entry is live the moment Sparkle lands 0.1.9 there (until
then air's 0.1.8 answers the hook with usage, exit 2 — a stderr line,
not a block). The View menu's submenu was clicked by a hand on the v0.1.10 cut and works. Left
as decided: a session stopped by your own hand still banners, until it
annoys. **v0.1.9 (build 80) is cut and on the feed** (2026-09-02, the
second cut through ota, verified live: version 80, length 4541512;
GitHub release v0.1.9); studio runs it, air takes it through Sparkle.
Master wants `git merge --ff-only worktree-v2` again.

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
   Sparkle — was split as asked, reviewed, and **landed** (9d7ce79 on
   master, merged back into worktree-v2 as 0e73a69). `ota` is on
   studio's PATH and v0.1.8 went through it end to end. What remains of
   §6a's proof is air installing v0.1.8 from the feed; ota is pinned to
   revision 45f3a63 until it tags. ota's own `verify --feed ccc` agreed
   with the cut (version 76, length 4509224). **Next bump:** ota master
   gained 187ec67, "refuse to release an installed app" — a path under
   /Applications or ~/Applications is refused; ccc releases from
   `.build/dist/ccc.app`, so nothing changes, but take it with the next
   pin move. The superseded branches
   `origin/ota-migration` and `origin/ota-migration-v017` can be deleted.

`scripts/attach-probe` is the tool for anything attach-shaped: hold, type,
resize, SIGUSR1 to report mid-hold.
