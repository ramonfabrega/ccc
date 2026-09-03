# plan.md — ephemeral handoff

**Status 2026-09-02, late.** Everything landed is in `docs/MILESTONES.md`
(v0 through v6 slice 1). **v0.1.12 is the cut** (the UI pass; on the feed
through ota, GitHub release v0.1.12); air takes it through Sparkle when
it wakes. **Studio runs the dev bundle (v6 slice 1: worktree rows and
the Merge submenu) — `scripts/install --dist` puts the cut back**, or cut
v0.1.13 once a hand has used the submenu. Master wants
`git merge --ff-only worktree-v2` — or, from now on, the **ccc** row's
context menu → Merge worktree-v2 into master → Fast-forward, which is
the same act and the hand proof this slice is owed. This file carries only what is
*not* settled: the queue, trimmed to what has a measured reason, and
what is owed.

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

## Owed a hand (studio)

- **The Merge submenu, by a hand** (v6 slice 1): the `ccc` row reads
  `⎇ worktree-v2 ↑N` once this slice is committed; its context menu's
  Merge ▸ Fast-forward should land master and the row should read
  `level` on the next tick, with the sentence on the banner. Proved by
  script up to the click; the click is the user's by rule.

## Queue

1. **Worktree awareness, slice 2 — the standing against origin** (the
   user's ask 2026-09-02, late, "git status-esque in each tab",
   incremental): beside `↑3 ↓2` against master, the branch against its
   upstream and master against `origin/master`, read from the
   last-fetched remote refs (`refs/remotes/origin/…`, no network — the
   reading says "as of the last fetch"). Display only; pushing is not a
   ccc verb. Slice 1 (the reading, the three strategies, `ccc merge`) is
   in `docs/MILESTONES.md` v6.
2. **Host picker** off `tailscale status --json` (MagicDNS names are the
   ssh destinations; Bonjour never crosses the tailnet). With it, the §4c
   question: whether a secondary viewer renders the shared grid as-is
   instead of resizing it (last-resize-wins today).
3. **Debt:** `ClaudeCLI.run` blocks a pool thread per host for up to its
   timeout (`readDataToEndOfFile`). Fine at two or three hosts; a
   nonblocking read before the host list grows.
4. **Small leftovers:** a sort by model; the Session menu's archive/pin
   items (the context menu has them); `ccc window show` when another app
   holds focus — measured 2026-09-02 with a Wine window in front:
   `NSApp.activate()` is cooperative since macOS 14 and the window stayed
   behind, while `open -a` brought it front, so the CLI side of `show`
   should activate through `NSWorkspace` (the app cannot activate
   itself).

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
