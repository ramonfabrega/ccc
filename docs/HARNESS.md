# The harness surface ccc builds on

Claude Code 2.1.258, daemon `proto: 1`, transient on this machine (starts on
demand, exits idle). Verified 2026-09-02 against `code.claude.com` docs and
the files on disk; prompt contents redacted, shapes only.

## Documented (build on it)

**`claude agents --json [--all]`** — active sessions as a JSON array
(`--all` adds done/stopped).

| field | when | values |
|---|---|---|
| `cwd`, `kind`, `startedAt` | always | `kind`: `interactive` \| `background` (interactive never observed live — experiment 1) |
| `id` | background | short id for attach/logs/stop |
| `state` | background | `working` \| `blocked` \| `done` \| `failed` \| `stopped` |
| `pid`, `status` | process alive | `status`: `busy` \| `idle` \| `waiting` |
| `waitingFor` | waiting | `permission prompt` \| `input needed` \| `sandbox request` \| `worker request` \| `dialog open` |
| `sessionId`, `name` | when set | full transcript uuid (usable with `--resume`); display name |

Local daemon only; other machines are reached by running the same command
behind `ssh`.

**Findings from the first real capture (17 rows, 2026-09-02; fixture
`Tests/CCCKitTests/Fixtures/roster/agents-2026-09-02.json`):**

- **`state` and `status` are independent axes.** Three rows had
  `state: "done"` *and* a live `pid` with `status: "idle"`: the job is
  finished, the process is still up. Liveness keys off `pid`, never off
  `state`. `pid` and `status` are strictly co-present.
- No row carried `waitingFor` in that first capture, so the `blocked` +
  `waitingFor` pairing the poll-as-notifier plan (v3) depends on was an
  assumption. **Captured 2026-09-02**
  (`Fixtures/roster/agents-blocked-2026-09-02.json`, 17 rows): a genuinely
  blocked session comes back as
  `{state: "blocked", waitingFor: "input needed", status: "waiting", pid}`
  — state, reason and liveness together, which is v3's notification with no
  hook. It also brought a **third `status` value, `waiting`**, which no doc
  lists; the lenient decoder flagged it as an unknown value and the banner
  is how we learned about it, exactly as designed. Only the blocked row
  carries it. **The reason is per prompt kind (2026-09-02, v3's proof):**
  a permission prompt is `{state: "blocked", status: "waiting",
  waitingFor: "permission prompt"}`, but eight sessions blocked on
  `AskUserQuestion` came back `{state: "blocked", status: "idle"}` with
  **no `waitingFor`** — so the transition detector keys on `state` with
  `waitingFor` as detail, never as the trigger.
- **`claude rm <id>`** deletes a background session and its worktree
  "when that is safe", and works on exited sessions (`stop` does not).
  The guard is the harness's: against a worktree with an untracked file
  it answered `kept <id> — worktree has uncommitted changes`, kept the
  worktree, exit 1, and the row stayed in the roster (measured
  2026-09-02). No `--force`; resolving means commit/push or removing the
  worktree by hand, then `rm` again. `ccc rm <ref>` is that command
  behind the host prefix and nothing more — the agents view's Delete is
  this same check, so ccc inherits it rather than re-deciding it.
- Non-interactive `ssh localhost` has a minimal PATH and **no `claude` on
  it**; the remote command must be an absolute path (or `zsh -lc`). v2
  fact, learned setting up experiment 3.
- **Done sessions leave the roster when their worker is recycled, never by
  time.** `roster.json` is `workers` keyed by worker id (pid, procStart,
  the sessionId currently bound). The daemon keeps spare worker
  processes; `bg claimed-spare <id>` in daemon.log hands a spare to a new
  session and spawns a replacement. A done session's row survives until
  its worker is claimed by a *new* background session, at which point the
  row is overwritten. Observed 2026-09-02 (lore, from the store's shape and
  daemon.log): `1b1140d9` (settled 08:12:51Z) vanished at 09:08:23Z when
  its worker pid 85972 was claimed by `78bb5bd1`; `78bb5bd1` then survived
  a further spawn (it claimed the replenishment spare) and was still
  listed 73 minutes after settling. Five mechanisms were proposed and
  falsified first — process exit, daemon restart, attach/detach, drop on
  rewrite, an age threshold — the last one built on a rounded timestamp
  ("gone by 04:05"; the overwrite was 04:08:23). Two rules from that:
  record a rounded time as an interval, and read the data structure before
  theorising about its behaviour. Consequences for ccc: roster memory is
  bounded by dispatch churn (seconds on a busy fleet, hours on an idle
  one); a target seen last tick may be gone this tick; `claude attach` on
  a forgotten id prints "No job matching" and exits, which the pane shows
  as its first row; and the roster's `id`/`sessionId` are the stable
  handles — worker identity is not.

**`claude attach <id>`** — no flags. Fullscreen TUI. Detach: `←` on an empty
prompt, `/exit`, `Ctrl+Z` (back to where you started), double `Ctrl+C` or
`Ctrl+D` on an empty prompt. None stop the session; `/stop` inside does.
**A second attach is refused**: "this session is running in another
terminal". **`claude logs <id>`** prints recent output — a snapshot, not a
stream.

**Peek / queued reply.** In the agents view, Space on a row shows recent
output and a reply field without attaching; a reply that cannot be delivered
is saved and sent as the session's next prompt when its process is reachable.
This is the mechanism behind "text typed on one Mac survived on the other".
Whether the daemon exposes it outside the TUI is unknown (experiment 4).

**Dispatch.** `claude --bg "<prompt>"` with `--name --model --agent
--permission-mode --effort --exec`. cwd = the invocation directory (no
`--cwd`; `claude agents --cwd` only filters). Worktree isolation is automatic
before the first edit (`worktree.bgIsolation: "none"` disables). `claude
--resume <id|name>`; `/fork [prompt]` inside a session creates a new
background session — **with no prompt it sits idle awaiting its first
instruction: the "not started" draft.** `claude agents --model/--effort/
--agent/...` set fleet-wide dispatch defaults for the TUI, not per-call
overrides.

**Hooks.** `Notification` (matcher = `notification_type`): `permission_prompt`
(~6 s idle), `idle_prompt` (~60 s), `elicitation_*`, `auth_success`,
`quota_auto_resume_*`, and **`agent_needs_input` / `agent_completed`, which
fire only while the agents view is open in a terminal.** Payload: common
fields (`session_id`, `prompt_id`, `transcript_path`, `cwd`,
`permission_mode`, `hook_event_name`) + `message`, optional `title`,
`notification_type`. `PermissionRequest`: input `tool_name`, `tool_input`,
optional `permission_suggestions[]`; **decision via a `decision` object**
(`behavior: allow|deny`, `updatedInput`, `updatedPermissions`, `message`,
`interrupt`) — exit code 2 is not honored. RC-free approvals are a documented
surface; not v0. **`ccc hook` is the Notification receiver (v3 slice 2):**
the payload on stdin, decoded leniently (`HookEvent.decode` — every field
optional, wrong types dropped), relayed to the app over the control socket;
`ccc hook --settings` prints the settings.json entry. **Fired for real
2026-09-02** (2.1.x, v0.1.9): a background session blocked on a Bash
permission produced one `permission_prompt` event about 6 s after the
roster's `blocked` row, with a `session_id` that matched the row's
`sessionId` — so the hook and the poll name the same session, and the
hook's reason lands under the poll's banner.

**Remote Control.** Outbound-only HTTPS from the session to Anthropic; the
phone push is native and undocumented; no third-party channel. `Channels`
is the sanctioned inbound surface (not investigated).

## Undocumented but observable (lenient decoding, banner on change)

- `~/.claude/daemon/roster.json`: `{proto, supervisorPid, updatedAt,
  workers{<id>: {pid, procStart, sessionId, rendezvousSock, ptySock,
  cliVersion, startedAt, attempt, cwd, dispatch{…launch{mode, sessionId,
  transcriptPath, fork, flagArgs[], restoresTranscript}…, cols, rows},
  decModes[], firedInteractiveMarks[], rvAuth, ptyAuth, replPid, …}}}`.
- `~/.claude/jobs/<id>/state.json`: `state, detail, tempo (idle|active),
  inFlight{tasks, queued, kinds[], drainableMonitors}, fan[]{id, kind:
  shell|agent, label, startedAt}, tokens, output{result}, children[]{id,
  href, kind: pr|frame}, template (bg|claude|argent-driver), name,
  nameSource (user|auto), sessionId, resumeSessionId, cwd, worktreePath,
  worktreeBranch, originCwd, bridgeSessionId, backend (daemon), createdAt,
  updatedAt, firstTerminalAt, lastTerminalAt, …`.
- `~/.claude/jobs/<id>/timeline.jsonl` (`{at, state, detail, text}` per
  change), `~/.claude/jobs/pins.json` (array of pinned ids),
  `~/.claude/daemon/attach-journal/<gesture>.json` (`surface: "fleet"`).
- The only promise: an older CLI updating `state.json` preserves fields it
  does not recognize; `roster.json` follows the same rule.

## Experiments (resolve before the feature that needs them)

1. Open a plain foreground `claude` and run `claude agents --json --all`: does
   `kind: interactive` ever appear, with which fields? (Decides whether the
   poll covers interactive sessions or the hook must.)
   **Answered 2026-09-02 (2.1.258): yes, in both `--json` and `--json --all`.**
   A foreground `claude` in `~/cc-test`, idle at its first prompt, appeared
   within 20 s as `{pid, cwd, kind: "interactive", startedAt, sessionId,
   name: "cc-test-f7", status: "idle"}` — an auto-generated `name`, **no
   `id` and no `state`**. So the poll covers interactive sessions for
   presence and busy/idle, but they cannot be attached (no short id) and
   have no lifecycle state; `waitingFor` on an interactive row is untested.
   Caveat that cost one false negative: a `claude` launched from inside
   another Claude Code session inherits `CLAUDE_CODE_CHILD_SESSION` (and
   friends), runs with "transcript saving is off", and **never registers
   with the daemon**. ccc's own spawns (v5) must strip `CLAUDE*` from the
   child environment; the experiment script does.
2. **[state-changing]** `claude attach <same-id>` from studio and from air
   simultaneously; record the refusal text and what the first client sees.
   **Answered 2026-09-02 (2.1.258), `scripts/attach-probe` against an idle
   session, both clients on studio (a second Mac changes nothing: every
   attach lands on the same daemon).** There is no refusal. The second
   attach is accepted and receives the full screen; a client typing `xyz`
   sees the echo and so does the client that was already attached — the
   daemon broadcasts one PTY to every viewer and merges their input. No
   client ever touches the session's `ptySock`: `lsof` shows exactly one
   connection per pty host, the daemon's, and each viewer holds a second
   connection to `control.sock` through which the daemon proxies the pane.
   Killing a viewer's terminal (`SIGKILL` the pty owner) ends its
   `claude attach` child within a second and the daemon's connection count
   drops at once — nothing to reap. **Size is last-writer-wins:** a
   140-column client joining a 100-column holder resized the shared PTY,
   the holder was redrawn at 140, and when the wide client left the PTY
   stayed at 140. That is how two `claude agents` views already behave
   (docs/DESIGN.md §4c).
3. **[state-changing]** `ssh -t localhost claude attach <id>`: fullscreen,
   resize, and `Ctrl+Z` semantics through a PTY hop.
   **Answered 2026-09-02 (2.1.258) against session `1b1140d9`, driven from
   a Python pty at 100×30.** All three work. Startup: alt screen
   (`?1049h`), kitty keyboard push (`CSI >`), bracketed paste (`?2004h`),
   SGR mouse (`?1006h`) all negotiated through the hop; the TUI rendered the
   transcript, the `ccc-exp3` name bar, and the status line within 12 s.
   Resize: `TIOCSWINSZ` on our master → ssh forwards SIGWINCH → a full
   redraw at 140 columns arrived within 5 s (separator rules grew from
   100 to 140 cells). Typing echoed. **`Ctrl+Z` detaches cleanly**: alt
   screen left (`?1049l`), kitty keyboard popped (`CSI <u`), "Connection to
   localhost closed", ssh exit status 0, session still alive in the roster.
   Remote command must be the absolute path (`~/.local/bin/claude`);
   non-interactive ssh has no `claude` on PATH — now enforced by
   `Host.validate`, which refuses a remote host without one and says this.
   **Mechanized 2026-09-02 (v2 slice 1):** `ccc hosts check <name>` runs the
   real poll command on a host and reports what came back, so the hop is a
   command anyone can re-run instead of a one-off Python pty script. Detach byte tail:
   `ESC 7 ESC 8 ESC [<u ESC [>4m`.
4. Find how the TUI's peek/reply reaches the daemon (`rendezvousSock` /
   `ptySock` in the roster) — a v2 exploration, not a v0 dependency.
5. Type in an attached pane, kill the terminal, reattach: does the draft
   survive via the queued-reply path or only via peek?
   **Answered incidentally 2026-09-02:** yes for `Ctrl+Z`. Experiment 3
   typed `hello from exp3` into the prompt over ssh and detached with
   `Ctrl+Z`; the next `claude attach` (local, the fixture recording, 8 min
   later) rendered the prompt as `❯ hello from exp3` before any new input.
   The draft lives with the session, not the client. Killing the terminal
   outright (SIGHUP, no `Ctrl+Z`) is still untested.
