# Queue

What is next, and nothing else. A finished item leaves — its commands and
numbers go to `docs/EVIDENCE.md`, its argument to the lore wiki. Item
numbers are stable addresses: append, never renumber.

An item **inlines its conclusion**. A cold session reads this file and
CLAUDE.md, and must be able to start without opening a third thing; when
an item cites a past measurement it cites it by a string that appears
verbatim in `docs/EVIDENCE.md` (`experiment 2`, `waitUntilDrawn`,
`lidtest`) so the command behind it is one grep away.

## The frontier

**v8 — the pane, honestly.** Two complaints the user raised while using
the app, both diagnosed by reading the code, neither fixed, both local
and unblocked: the colours are wrong (item 8) and the attach transition
blanks the pane (item 9). Do 8 first, and **do its measurement before
either fix** — the house rule is that the screen is the oracle, and the
measurement is what says which of the two causes is doing the damage.
Item 8 is blocked on one answer only a human has: *what should the
colours be* — Ghostty's defaults, the user's iTerm profile, or a theme of
our own — since the fix hardcodes 256 RGB values from somewhere. The
measurement does not need that answer; the fix does.

Before the measurement can be honest, item 10 has to exist: there is no
way to capture one window from a command today, and no headless colour
oracle at all. That is one small slice in front of item 8, not a detour.

## Open

### 3. Host picker, and the shared-size question

Off `tailscale status --json` (MagicDNS names are the ssh destinations;
Bonjour never crosses the tailnet). With it, the question deferred in
DESIGN.md §4c: the daemon's PTY is last-resize-wins across viewers, so
decide whether a secondary viewer renders the shared grid as-is instead of
resizing it.

**Blocked on one toggle, measured 2026-09-03.** Air is up on the tailnet
(active, direct) but `ssh air` answers "connect to host air port 22:
Connection refused" — no Remote Login, as RELEASES.md says. Every ssh
proof to date is `localhost` wearing a costume. Four threads wait on
Sharing ▸ Remote Login on air: this, §4c above, item 6, and whether copy
over ssh lands on the wrong Mac's clipboard. **The order inverts:** `ccc
hosts add air` by hand and prove the hop first — a picker is a
convenience over a host list that has never held a real remote.

### 4. Debt: the blocking poll read

`ClaudeCLI.run` blocks a pool thread per host for up to its timeout
(`readDataToEndOfFile`). Fine at two or three hosts; wants a nonblocking
read before the host list grows. No forcing function yet.

### 5. Small leftovers

A sort by model. The Session menu's archive/pin items (the context menu
has them). `ccc window show` when another app holds focus — measured
2026-09-02 with a Wine window in front: `NSApp.activate()` is cooperative
since macOS 14 and the window stayed behind while `open -a` brought it
front, so `show`'s CLI side should activate through `NSWorkspace`.

### 6. Open measurements, on air

The long sleep: `~/lidtest.py` is running on air appending to
`~/lidtest.log`; `scp` it to studio when air is up. It decides whether the
ssh master eviction ever fires (`ccc stats` → `evictions`). And the first
real sleep for the remote-pane reattach — `sshExit` within 20 s of wake
replays the same argv (`PaneController.reattachIfSleepKilledIt`), never
yet through a real lid. Both blocked with item 3.

### 7. Housekeeping

Remote branches `hotfix-gridbuilder`, `worktree-icon`, `worktree-v0`,
`worktree-v1` are merged history; delete when convenient. Verify against
`git branch -a` first — this item has not been re-checked since it was
written.

### 8. The colours are off

Raised by the user 2026-09-03 ("feel off / opaque'd", not what iTerm
shows). **Diagnosed, not fixed.** Two stacking causes, both confirmed by
reading:

- `ghostty_terminal_set` is called with exactly three options — userdata,
  write_pty, scrollback (`GhosttyHost.swift:39-57`) — so
  `GHOSTTY_TERMINAL_OPT_COLOR_{FOREGROUND,BACKGROUND,CURSOR,PALETTE}` are
  never set and every colour is the core's default. The four options do
  exist at the pinned commit (11, 12, 13, 14, taking `GhosttyColorRgb*`
  and `GhosttyColorRgb[256]*`), so this is actionable rather than a hope
  about upstream. The codebase already knows: `MetalRenderer`'s
  `readableForeground` logs "the palette is unset" and substitutes a
  fallback, commented "the real repair belongs wherever the frame's
  palette is filled in" — that repair is this item, and the fallback goes
  with it.
- `MetalPaneView` uses `.bgra8Unorm` with **no `colorspace` on the layer**
  (line 49), so the pane is unmanaged while iTerm is colour-managed. On a
  P3 display that alone moves every value.

**Do the measurement first** — the same content in both, a real
`screencapture` of each, compare the RGB of known cells. It says which
cause is doing the damage before either is touched. Needs item 10, and
needs studio's actual display profile recorded, since cause (b)'s whole
premise is "on a P3 display" and nothing states whether the monitor is P3
or sRGB.

**Open question for a human, before the fix and not before the
measurement:** what should the colours *be*? Matching iTerm makes its
current profile the spec and that profile is recorded nowhere.

### 9. The attach transition blanks the pane

Raised 2026-09-03, diagnosed. `PaneController.switchTo` does `await
session.detach()` then `attach()`, which builds a brand-new host — a blank
grid — and the window mounts it before the new `claude attach` has drawn.
Experiment 3 measured the TUI taking up to 12 s to paint over ssh, and
`waitUntilDrawn`'s timeout is 8 s, so the blank is not a flicker, it is
the wait.

The fix is available *because* experiment 2 answered that the daemon
accepts concurrent attaches and mirrors one PTY to every viewer: start the
new session **behind** the old one, reuse `waitUntilDrawn`, swap the view
only once it has painted, then detach the old. No blank frame at all.

Open question for the doing: which pane owns the keyboard during the
overlap. Leaving it with the old pane until the swap is the obvious
answer — nothing typed at an unpainted TUI means anything — but it is a
taste call and has not been made.

### 10. The oracle has no command twin

Found by a cold read of these docs, 2026-09-03. CLAUDE.md makes a real
`screencapture` the oracle for presentation, and `docs/CHECKS.md` row 5
was re-judged with one — but nothing in the repo can capture one specific
window: `screencapture -l <CGWindowID>` needs an id nothing here produces,
and there is no script for it. Against this project's own rule that every
gesture has a command twin, that is a finding, not a missing doc.

Nothing reads RGB out of a PNG either, and there is no headless colour
oracle at all: `snapshot --json` serialises a `Grid` and `GridBuilder`
carries no colour, so the text grid cannot judge colour today — which is
what makes item 8's screencapture the honest first move rather than a lazy
one. Whether a replay golden could ever assert RGB is unanswered.

### 11. A cold session cannot build this

Found the same way. Neither CLAUDE.md nor this file said how to build the
app, run its tests, or initialise the vendored submodule, nor whether `ccc`
on PATH is the installed release or a build of the current branch — so a
cold session could reason correctly about priorities and then measure the
wrong binary. README.md now carries this; keep it true.

## Later

Peek/reply without attach (experiment 4). RC-free approvals via the
PermissionRequest hook. The phone, if the Mac app earns it.
