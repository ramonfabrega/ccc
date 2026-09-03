# plan.md — ephemeral handoff

**Status 2026-09-02, late.** Everything landed is in `docs/MILESTONES.md`
(v0 through v5 slice 3). **v0.1.11 (build 90) is cut and on the feed**
(through ota, live length 4627875; GitHub release v0.1.11); studio runs
it (`--dist`), air takes it through Sparkle when it wakes. Master wants
`git merge --ff-only worktree-v2`. This file carries only what is *not*
settled: the queue, trimmed to what has a measured reason, and what is
owed.

Worktree `.claude/worktrees/v2`, branch `worktree-v2`. `master`
fast-forwards to it; merge master back after any master-side commit or
the branches re-diverge. Dev loop on studio: `scripts/install` (dev
bundle, `ccc·dev`); `scripts/install --dist` puts the cut back. Releases:
RELEASES.md, through `ota` (pinned to its tag v0.1.0).

## Decided 2026-09-02, late

- **The fork is a verb, not a surface.** `ccc spawn --from <ref>` stays;
  the sheet's From row and its gestures came out. The gestures are now
  **New Session Here…** (⇧⌘N for the attached session, the row's context
  menu, `n` on the selected row): the same sheet on that row's host and
  folder, which is how sessions actually get started here.
- **Reach zero, then re-expand.** No new direction is chosen until the
  queue below is what is left and a cut carries the same build to every
  Mac.

## Owed a hand (studio, after the cut)

- **New Session Here…** has not been clicked by a hand: ⇧⌘N over an
  attached session should open the sheet on its folder, and "Attach when
  started" should leave the attached session for the new one (attach
  refused with "busy" until this was fixed; the fix was seen once by a
  script, not a hand). `n` on a selected row and the context menu item
  likewise.
- **The roster's left column** feels iffy to click at times (noted by the
  user 2026-09-02). For the UI pass, with the banner drawing under the
  title bar and the terminal clipping a little at its bounds.

## Queue

1. **UI pass** — the three items above, together, when the pane is the
   subject again.
2. **Worktree awareness**, display only: a row that lives in a worktree
   says so (`state.json` carries `worktreePath`; the harness isolates
   before the first edit on its own, so there is nothing to dispatch).
3. **Host picker** off `tailscale status --json` (MagicDNS names are the
   ssh destinations; Bonjour never crosses the tailnet). With it, the §4c
   question: whether a secondary viewer renders the shared grid as-is
   instead of resizing it (last-resize-wins today).
4. **Debt:** `ClaudeCLI.run` blocks a pool thread per host for up to its
   timeout (`readDataToEndOfFile`). Fine at two or three hosts; a
   nonblocking read before the host list grows.
5. **Small leftovers:** a sort by model; the Session menu's archive/pin
   items (the context menu has them).

Dropped 2026-09-02: a "forked from" mark on the row; permission mode,
effort and worktree as sheet fields (the command has them; nobody has
missed them in the sheet).

## Open measurements

- **The long sleep.** `~/lidtest.py` was left running on air, appending
  to `~/lidtest.log`; air refused ssh all evening 2026-09-02 (asleep), so
  the overnight log is still there — `scp ~/lidtest.log
  studio:~/lidtest-air.log` when it is up (studio's copy holds only the
  two-minute run). Decides whether the eviction ever fires in practice
  (`ccc stats` → `evictions`). Not blocking.
- **Reattach on wake for a remote pane** is written
  (`PaneController.reattachIfSleepKilledIt`) but has not seen a real
  sleep. First real use is on air.

## Housekeeping

- Remote branches `hotfix-gridbuilder`, `worktree-icon`, `worktree-v0`,
  `worktree-v1` are merged history; delete when convenient. The two
  `ota-migration` branches are already gone.

`scripts/attach-probe` is the tool for anything attach-shaped;
`scripts/spawn-probe` for anything `--bg`-shaped (`--` passes
`--flag=value` words to the harness).
