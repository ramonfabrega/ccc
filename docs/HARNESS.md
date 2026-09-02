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
| `pid`, `status` | process alive | `status`: `busy` \| `idle` |
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
- No row carried `waitingFor`; the `blocked` + `waitingFor` pairing the
  poll-as-notifier plan (v3) depends on has no fixture yet. Capture one
  while a session is actually blocked.
- Non-interactive `ssh localhost` has a minimal PATH and **no `claude` on
  it**; the remote command must be an absolute path (or `zsh -lc`). v2
  fact, learned setting up experiment 3.

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
surface; not v0.

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
   non-interactive ssh has no `claude` on PATH. Detach byte tail:
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
