# The harness surface ccc builds on

Claude Code 2.1.258, daemon `proto: 1`, transient on this machine (starts on
demand, exits idle). Verified 2026-09-02 against `code.claude.com` docs and
the files on disk; prompt contents redacted, shapes only.

## Rules

Read before acting here; each cites the `docs/EVIDENCE.md` heading that
proved it. Convention and bound: `docs/DESIGN.md` §9.

- A roster `↳` is evidence of the last turn that wrote one, never of
  *current* state — stale through a long tool call, and for minutes after
  a clear. ("item 27 — the gate read the wrong field")
- `status` is *something live is attached*, `tempo` is *the turn is
  generating*. "May I type into this pane" reads `tempo`. ("item 27 — the
  gate read the wrong field")
- `inFlight.kinds` discriminates — a shell never counts as a monitor —
  and `drainableMonitors: 0` never means no monitors. ("what a clear does
  to background work")

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
  behind the host prefix — the agents view's Delete is this same check,
  so ccc inherits it rather than re-deciding it — **plus the worktree ccc
  cut itself** (item 24), which the harness never knew about because
  `--base` hands it a plain cwd.
  **"Its worktree" is the one its job file names** (`worktreePath`,
  written for a `--worktree` spawn): `rm` takes that tree and no other. A
  `--cwd` session in an existing tree loses only its row, even when the
  tree is clean and pushed (2026-10-07); a `--worktree` draft that never
  started kept its tree, `locked` by a dead pid (2026-09-06, queue item
  26). `ccc forget` is `rm` refused when that key or `ccc-cut` is present,
  or the row still has a process (`docs/EVIDENCE.md` "forget — what
  `claude rm` takes", "worktrees/started").
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
**A second attach is accepted** — the docs once said refused; experiment 2
below measured a mirror: every viewer sees the output, any viewer's input
goes in. **`claude logs <id>`** prints recent output — a snapshot, not a
stream.

**Peek / queued reply.** In the agents view, Space on a row shows recent
output and a reply field without attaching; a reply that cannot be delivered
is saved and sent as the session's next prompt when its process is reachable.
This is the mechanism behind "text typed on one Mac survived on the other".
Whether the daemon exposes it outside the TUI is unknown (experiment 4).

**Dispatch.** `claude --bg "<prompt>"` with `--name --model --agent
--permission-mode --effort --exec --worktree [name]`, plus the undocumented
variadic `--channels <servers...>` (channel plugins, registered only at
launch; a bare one eats the next word — `docs/EVIDENCE.md`
"`--channels`, the flag a desk can only take at launch"). cwd = the invocation
directory (no `--cwd`; `claude agents --cwd` only filters). Worktree
isolation is automatic before the first edit (`worktree.bgIsolation:
"none"` disables). `claude --resume <id|name>`; `/fork [prompt]` inside a
session creates a new background session. **Measured 2026-09-02 (2.1.259,
`scripts/spawn-probe`), the facts v5 is built on:**
- `claude --bg` **with no prompt is the draft from the command line** — no
  `/fork` needed. The answer says so: `backgrounded · <id> · <name>` then a
  dim `(idle — send a prompt to start)`; with a prompt the parenthesis is
  absent. The id is wrapped in `\e[36m…\e[39m`, the name is only there when
  `--name` was given, and four hint lines follow. Exit 0 in 0.6 s, before
  the session has done anything.
- **A draft is `state: blocked, status: idle` with no `waitingFor`** from its
  first roster row, and stays there — 11 min observed with nothing else
  touching it. So the poll's detector reports a fresh draft as `⏸ blocked`
  and the notifier banners it (v3 slice 1's "blocked without `waitingFor`"
  case, seen again). A prompted spawn is `working · busy` inside a second
  and `done · idle` when finished.
- **The daemon knows a draft even though the roster does not say so:**
  `~/.claude/jobs/<id>/state.json` for one reads `state: "working"`,
  `tempo: "blocked"`, `detail: "(idle — send a prompt to start)"`,
  `needs: "send a prompt to start"`, `intent: ""`, no `tokens`,
  `firstTerminalAt: null`; for a session blocked on an AskUserQuestion
  the same file reads `state: "blocked"`, `needs: <the question>`,
  `tokens: 51937`, `intent: <the first prompt>`. ccc reads `detail`,
  `needs`, `output.result`, `suggestedReply` and `respawnFlags` through
  `JobProbe` (`JobInfo`), never writes the file, and `DraftProbe` is the
  draft predicate over that reading, falling back to "no transcript" when
  the file is unreadable (v5 slice 2, widened in v11 and v13).
  Undocumented; unknown fields preserved is the only promise, so a
  missing `needs` is "no reading", never "not a draft".
- The row is in `claude agents --json --all` by the time `--bg` has exited
  (the probe never had to wait), so `claude attach <id>` straight after is
  safe — that is what "Attach when started" does.
- **A fork from the command line is `claude --bg --resume <session id>
  --fork-session [prompt]`** (measured 2026-09-02, `scripts/spawn-probe --
  --resume=… --fork-session`, the facts v5 slice 3 is built on): a new
  background session that opens with the source's transcript, the source
  untouched, same one-line answer, exit 0 in 0.65 s. The daemon records
  the lineage in `roster.json` — `dispatch.launch{mode: "resume",
  sessionId: <what was passed>, fork: true, restoresTranscript}` — which
  is how these were checked. **The id must be the full session id** (the
  roster row's `sessionId`): the eight-character job id is accepted, exits
  0, and the new session then sits at the TUI's "Resume session" picker
  reading `No sessions match "1e7c5066"` (`state: working, detail:
  "starting…"` forever); a `--name` resolves and the transcript shows, but
  the daemon writes `restoresTranscript: false` for it, so ccc passes the
  uuid. **With no prompt it is a forked draft** — `(idle — send a prompt
  to start)`, `needs` the same phrase, so the draft reading holds — and
  the transcript is restored when the first prompt lands (a forked draft
  showed 37k of context and answered from the source's conversation). A
  fork with no `--name` inherits the source's name.
`claude agents --model/--effort/--agent/...` set fleet-wide dispatch
defaults for the TUI, not per-call overrides.

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
is the sanctioned inbound surface (not investigated). **Amended 2026-09-04
with what it already does for us** (`docs/EVIDENCE.md` "the mobile
survey"): `--rc` / `--remote-control` on a session, or `--rc` in a
`--bg` dispatch's `flagArgs`, puts it on claude.ai/code and in the Claude
mobile app, where it can be **messaged, and its permission prompts and
`AskUserQuestion`s answered**, plus `/model`, `/effort`, `/config
key=value`, `/compact`, `/context`, `/usage`, `/mcp`. The session
registers with the API and polls; no inbound port; the transcript is
stored on Anthropic servers while connected. Push is gated by
`agentPushNotifEnabled` and `inputNeededNotifEnabled`, and suppressed
while `CLAUDE_CLIENT_PRESENCE_FILE` names an existing file — the hook ccc
should own (queue item 17). **ccc reads none of this today.**

**`claude rc` is a different thing that shares the name**, and it cost a
day to find that out, so it is written down here. `claude rc` (long spelling
`claude remote-control`) is not a flag on a session — it is a **persistent
per-directory server**: run it in a folder and it accepts sessions created
from claude.ai/code or the phone, pre-creating one on start and spawning more
on demand up to `--capacity` (32). `--spawn same-dir|worktree|session` picks
what each new one gets. Measured 2026-09-06: it has no usable `--help` from a
script — `claude rc --help` printed the help *and kept running as the server*,
so a session that asks it a question hangs until something kills it (`claude
remote-control -h` is the same command; read the text and expect to kill it).

**The user ran it on 2026-09-04 and dropped it for `ccc spawn` the same day**,
for two reasons that are both about defaults rather than about the feature:
its spawned sessions were **not on `auto`** — it takes `--permission-mode`,
but a worker that inherits the asking default blocks on its first prompt, and
`ccc spawn` has defaulted to `auto` since that day — and `--spawn worktree`
is **not base-correct**: it cuts off the repository's default branch, which is
queue item 18's whole problem, since the trunk on both consumer repos is a
branch that lags nothing.

**ccc uses neither, and the distinction matters for the roster.** `ccc spawn
--rc` passes `--rc` to `claude --bg`, which makes a *background job* that is
also remote-controlled: the daemon owns it, `claude agents` lists it, and
ccc's row reads its `respawnFlags`. A session an `rc` server spawns is not
that, and how much of it reaches the daemon's roster is still **unmeasured**.

**The `ccc spawn --rc` half was looked at on 2026-09-07** (`docs/EVIDENCE.md`
"item 17 — the roster says nothing about `--rc`"), and the answer is that the
row says *nothing*: an rc row and a plain row from the same cwd, prompt and
model are identical in field set and in every value but `id`, `pid`,
`sessionId`, `startedAt` and `name`. `kind` stays `background`;
`bridgeSessionId` and `bridgeOutboundOnly` are present and equal on the plain
session too, so neither discriminates. `respawnFlags` is the only signal in
the job file. Outside it there is one more, in the session's own transcript —
a `{"type":"system","subtype":"bridge_status"}` record whose `url` is
`https://claude.ai/code/session_<bridgeSessionId>`, the deep link the row
does not have.

**The session inbox socket** (`cross-session-messaging`, harness v2.1.224+)
— the sanctioned way for a non-session process to put text into a running
session, which is what "reply without attaching" needed and what
experiment 4 was chasing privately. Every session binds one; the docs name
"a script or hook to post into a session" as a use. Address:
`/tmp/cc-socks/<replPid>.sock`, where `replPid` is the roster field (**not
`pid`**, which is the launcher) — joined nine for nine on 2026-09-04. A
session's own is exported as `CLAUDE_CODE_MESSAGING_SOCKET` with
`CLAUDE_CODE_MESSAGING_TOKEN`; the `{"type":"auth","token":"…"}` first line
is optional on macOS, required on Windows. 0600, per-uid, refused in a
directory it cannot accept. **A message on it is never consent** — it
cannot answer a permission prompt, so approvals remain the
`PermissionRequest` hook's job — and an unverifiable sender asserts no
permission class, so a `bypassPermissions` receiver holds it. The message
line's own shape is **not documented and not yet measured**.

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
   child environment; the experiment script does. **Amended 2026-09-02
   (2.1.259):** a `claude --bg` run from inside a Claude Code session with
   every `CLAUDE*` marker inherited *did* register (it printed
   `backgrounded · 6b7e3fe6` and the roster listed it) — `--bg` registers
   regardless. What the markers still change is the child's own behaviour
   ("transcript saving is off"), which is the model column gone and lore
   blind to it, so `ClaudeCLI.spawn` strips them either way. That
   inherited-env draft also drifted to `done` within a couple of minutes,
   which a clean draft never did (11 min observed at `blocked · idle`);
   one observation each, noted rather than explained.
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
   **Superseded 2026-09-04, not answered** (`docs/EVIDENCE.md` "the mobile
   survey"). The rendezvous channel was located — per-worker UDS at
   `/tmp/cc-daemon-501/<daemon>/rv/<short>.sock`, keyed by `rvAuth` in
   roster.json, vocabulary `subscribe snapshot repaint splice setcwd
   handoff attacher-caps pty-auth-required` recovered from the CLI's
   strings — but its logic is `@bun @bytecode` and the surface is
   undocumented and unpromised. **Stop here**: the need behind the
   experiment (reply without attaching) has a *documented* answer in the
   session inbox socket below, so building on the rendezvous socket would
   be reverse-engineering a private channel when a public one exists.
5. Type in an attached pane, kill the terminal, reattach: does the draft
   survive via the queued-reply path or only via peek?
   **Answered incidentally 2026-09-02:** yes for `Ctrl+Z`. Experiment 3
   typed `hello from exp3` into the prompt over ssh and detached with
   `Ctrl+Z`; the next `claude attach` (local, the fixture recording, 8 min
   later) rendered the prompt as `❯ hello from exp3` before any new input.
   The draft lives with the session, not the client. Killing the terminal
   outright (SIGHUP, no `Ctrl+Z`) is still untested.
6. **← in an attached session.** `claude attach --help` says "← returns to
   agent view". What does a standalone client do with it, and can ccc
   redirect it? **Answered 2026-09-03 (2.1.259), headless from an
   untrusted folder against a `done` session.** One bare ← on the empty
   prompt (`❯` + U+00A0, cursor at column 2) left the session and, in
   the *same* `claude attach` process, opened the agents view — which
   starts with the workspace-trust dialog for the client's cwd
   ("Accessing workspace: … Yes, I trust this folder"). That is the
   "strange perms screen" in the app, whose attach child inherits the
   bundle's cwd. Inside the binary the gesture is gated by
   `leftArrowOpensAgents` (a `~/.claude.json` setting, default on, the
   `/config` "opens agents" row) and refused with a warning when there is
   a draft ("Cannot open agents — you have unsent text"), queued
   commands, or a foregrounded task; an editing guard absorbs a ← that
   lands right after deleting to empty. The status line shows `← 1
   agent` only while the input is empty — the harness's own statement of
   the condition. ccc does not touch the setting (it is the user's, and
   fleet-wide): `LeaveGesture` recognizes the condition off the grid and
   the key is never written to the PTY; the roster takes the keyboard
   instead. Measured through `ccc send --key left`: "taken" on `❯ `, sent
   and the cursor moved inside a draft.

## Probes

`scripts/attach-probe` is the tool for anything attach-shaped;
`scripts/spawn-probe` for anything `--bg`-shaped (`--` passes
`--flag=value` words to the harness). Every "measured" above came from
one of them.
