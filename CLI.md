# The `calm` command line

This file lists every `calm` command. [FEATURES.md](FEATURES.md) → F13 summarizes it. [DESIGNS.md](DESIGNS.md) → Control protocol describes how the CLI talks to the app.
Status marks: ✅ built and working as described. ⏸ parked: specified, waiting for a real need. A parked command that replaces a built one says what changes.

## At a glance

| Command | What it does | Status |
|---|---|---|
| `calm` | Opens Calm | ⏸ (today: prints the help) |
| `calm open file <path>[:line]` | Shows a file in Calm's viewer | ⏸ (today: `calm open <file>`) |
| `calm open session [folder]` | Opens a new session in a folder | ⏸ |
| `calm open project [folder]` | Makes a folder a project | ⏸ (today: `calm open <folder>`) |
| `calm list` | Lists the open sessions | ✅ (⏸ ids, `--json`) |
| `calm status` | Describes this session | ⏸ |
| `calm fork ["<prompt>"]` | Forks this session's conversation into a new session | ✅ |
| `calm search <text>` | Finds past conversations, each with its id | ✅ (⏸ `--limit`, `--json`) |
| `calm show <conversation>` | Everything Calm knows about one conversation | ✅ |
| `calm notify <message>` | Notifies you about this session | ✅ |
| `calm config` | Reads and changes Calm's settings | ✅ |
| `calm doctor` | Checks that Calm and the agents' hooks work | ✅ |
| `calm trace` | Prints Calm's timeline log | ✅ |
| `calm screenshot [<file>]` | Saves a PNG of Calm's window | ✅ |
| `calm status <state>`, `calm hook <agent>` | For agents' hooks: report a state | ✅ |
| `calm --help`, `calm --version` | Help, and the CLI's version | ✅ |

Agents' hooks send almost all CLI traffic, and people rarely type `calm` (decided 2026-10-06). So `doctor`, `trace`, `config`, `fork` and `show` came first.
Agents learn these commands from Calm's `calm` skill, which all four agents get (since 2026-10-13, DESIGNS.md → Teaching agents about `calm`). Open items: the ⏸ commands, which wait for a real need such as a script or SSH.

## Conventions

- **Exit codes:** 0 done. 1 failed, with the reason on stderr. 64 wrong usage.
- **Output** is plain text, one record per line. Color and marks appear only on a terminal. **`--json`:** one JSON document with `"v": 1`. Built: `show`, `doctor`, `config list`. Parked: `list`, `status`, `search`.
- **Starting Calm:** `calm`, `open` and `list` start the app the CLI came with and wait up to 5 seconds. A Debug build starts itself.
  They start Calm only for the standard socket: with another `CALM_SOCKET`, they say Calm is not running.
  `search`, `show` and `trace` read files and need no Calm. `doctor` reports that Calm is not running. `notify` and the hook commands never start Calm.
- **Session id:** the first 8 hex digits of a session's id (a full id also works). **Conversation id:** the agent's own id. **Copy Session ID** gives it.
- **This session** is the session whose shell runs the command (`$CALM_SESSION_ID`). `--session <id>` picks another. Outside Calm, commands about this session fail. The hook commands and `notify` do nothing and exit 0. Relative paths start from the current folder.

## Opening

### `calm` ⏸

Opens Calm, starting it when needed, and brings its window to the front. *Replaces:* `calm` alone prints the help, which stays at `calm --help`.

### `calm open` ⏸

Alone, or with a path and no branch, it prints the three branches and exits 64. *Replaces:* `calm open <folder|file>`, which guesses from the path. A folder becomes a project and shows its home (with a new session until 2026-10-09). A file opens in the viewer.

#### `calm open file <path>[:line]`

- Shows the file in the viewer, over the session in view. In code, `:line` highlights and centers that line.
- Uses the viewer even with `open-in = "editor"` under `[files]`. When the viewer cannot show the file (unknown kind, over 5 MB), the editor opens it at that line.
- Fails for a missing file, and for a folder: "That's a folder: use `calm open session` or `calm open project`."

#### `calm open session [folder]`

- Opens a fresh shell in the folder (default: the current folder), goes to it and files it like any session started there. It never makes a project.
- Fails for a missing folder, and for a file: "That's a file: use `calm open file`."

#### `calm open project [folder] [--new-session]`

- Makes the folder a project (default: the current folder), as ⌘O does, and shows its home. It starts no session, even for an existing project.
- `--new-session` opens a new session in the project instead. A folder inside another project becomes a project of its own. Fails for a missing folder or a file.

## Sessions

### `calm list [--json]` ✅

- Prints one line per open session, in sidebar order, with tabs between: session id, state, project, title, agent (`-` for none), folder.
  ```
  a1b2c3d4  needs-you   calm    Fix flaky test  Claude Code /Users/me/dev/calm
  ```
- `--json` also gives each session's full id and its agent's conversation id. Starts Calm in the background when needed.
  Built: project, title, state, agent, folder. Parked: the session id first, and `--json`.

### `calm status [--json] [--session <id>]` ⏸

- Describes this session, one field per line. Fails outside Calm: "Not in a Calm session." With a state (`calm status done`), it is the hook command.
  ```
  state         needs-you  Allow Bash: rm -rf build
  agent         Claude Code
  conversation  0f9c2a7e-…
  transcript    ~/.claude/projects/-Users-me-dev-calm/0f9c2a7e-….jsonl
  project       calm
  folder        /Users/me/dev/calm
  ```

### `calm fork ["<prompt>"] [--background] [--in <folder>] [--session <id>]` ✅

- Forks the conversation that runs in this session, or ran here last, into a new session (tab) in the same project and folder.
  It runs the agent's own fork command with the agent's start options (FEATURES.md → F12). The original continues untouched.
- Goes to the fork. With `--background`, the user stays and the fork waits in the sidebar, already running at its display size.
  The words that are not options are the fork's first message: `calm fork try the CRDT approach`.
- Claude Code and Codex take a prompt: `claude <options> --resume <id> --fork-session '<prompt>'` and `codex fork <options> <id> '<prompt>'` (Claude Code 2.1.285, Codex 0.159). pi and OpenCode are not checked, so a prompt for them fails: "pi can't start a fork with a prompt."
- `--in <folder>` runs the fork elsewhere. Claude Code finds the conversation from a git worktree of its repository, not from an unrelated folder
  ("No conversation found with session ID", 2.1.291). The other agents are not checked.
- Prints the new session's full id. Fails outside Calm, for a missing folder, or with no conversation: "No conversation to fork here." Never starts Calm.
  A fork cannot fork: "A fork can't fork: calm fork started this session." So an agent cannot start a chain. Right-click → Fork still works. A relaunch resets the rule.

### `calm notify <message>` ✅

- Notifies the user at the next pause when the user is elsewhere. The title is the session's name, the body the message. It is for people: `./deploy; calm notify "deploy finished"`. It shows a banner even with banners for *done* off (Settings → Agents). Agents report a state instead (`calm status`): a question is *needs you*, an end is *done* or *failed*. Anything else belongs on the card.
  Outside Calm, or with Calm not running, it does nothing and exits 0.

## Past conversations

### `calm search <text> [--limit <n>] [--json]` ✅

- Searches the past conversations of every agent. One result per conversation, best first: last active, agent, project, title, id (for `calm show`), then the match in bold.
- Goes through the running Calm. With no Calm, it updates and reads the index itself. When Calm answers with an error, the command says so and exits 1.
  When Calm has not answered after 15 seconds (a cold index), it says so and reads the index itself. A Calm older than the CLI says to update it.
  Built: the above, with 20 results. Parked: `--limit` and `--json`.

### `calm show <conversation> [--prompts] [--all] [--json]` ✅

Prints one conversation on one screen: what it was for, where it got to, where its work lives, how to go back.

```
Fix the flaky auth test · Claude Code
~/dev/apps/calm · on wt-auth-fix
Started 3 d ago · last active 2 h ago · 14 prompts, 31 replies
Open in session a1b2c3d4 · done

Asked
  The auth test fails about one run in five on CI. Find out why and fix it.

Recent prompts
  12  run it 200 times
  13  looks good, write the PR text
  14  ok ship it

Recap
  Fixed the race in TokenStore; 200 runs passed. Next: open the PR.

Tasks  4/5 · Opening the PR

Last reply
  (the agent's newest reply, whole)

Resume      claude --resume '0f9c2a7e-…'
Fork        claude --resume '0f9c2a7e-…' --fork-session
Transcript  ~/.claude/projects/-Users-me-dev-apps-calm/0f9c2a7e-….jsonl
Id          0f9c2a7e-…
```

| Part | Comes from |
|---|---|
| Title, agent, folder, last active, counts, Last reply | The search index. Asked is the first prompt. Recent prompts are the last three after it |
| Branch, Started | The transcript: Claude Code's newest `gitBranch`, Codex's `session_meta.git.branch` (none for pi and OpenCode). Started is when the transcript file was made (none for OpenCode, whose conversations share one database) |
| Open in session | The running Calm (`list`): the session whose agent is in this conversation, with its state. Left out when Calm is not running or the conversation is closed |
| Recap, Tasks | Claude Code's own recap (transcript tail) and todo progress. Left out otherwise |
| Resume, Fork | The agent's adapter: F12's menu commands with ⌘N's start options. Left out once the transcript is gone |
| Transcript | Its path, marked *(deleted)* when gone. When only the prompt history is left (Claude Code deletes transcripts after 30 days and keeps `history.jsonl`), the prompts show and the replies do not |

- A part with nothing in it is left out. `--prompts` lists every prompt, numbered, in place of the last three. `--json` gives every part and message.
  `--all` prints every prompt (under "You") and reply (under the agent's name) in order, without tool calls, tool output or thinking.
- Takes a conversation id from `calm search` or `calm status`, or the start of one (6 characters or more) that only one conversation has. For several matches, it lists them.
  Needs no Calm, except for *Open in session*, and never starts it. For an id the index does not know, it updates the index once, then fails.

## Settings

### `calm config [list [--json] | get <key> | set <key> <value…> | unset <key>]` ✅

- `calm config` (or `list`) prints every setting: its value in force, `(default)` when config.toml does not set it, and what it takes.
  Keys Calm does not read, and lines it cannot read, follow on stderr. `--json` adds default, whether it is set, and what it does.
  ```
  theme                    = Forest                a theme's name; unset, the Ghostty config's colors, else Calm
  motion                   = full       (default)  full, reduced or off
  agents.sound             = true                  true or false
  ```
- `help` (or `--help`, `-h`) prints the usage and exits 0. `get <key>` prints the value alone, for scripts (an unset theme prints an empty line).
- `set <key> <value…>` takes the rest of the line, so a command needs no quotes (`calm config set agents.claude-code.command claude -w`). A value with quotes needs quotes as a whole.
- `set` checks the value: a theme must exist, and true/false also take yes/no, on/off, 1/0. It writes one line as Settings does, so comments stay.
  A default removes the line, except for the theme. It prints what it wrote: `theme = Forest`. `unset <key>` removes the line.
- Then Calm reads config.toml and the Ghostty config again (⌘⇧,). The command never starts Calm. With none running, the change waits for the next launch, and the command says so.
- Keys: DESIGNS.md → Configuration (`Agents.settingsKeys`). A wrong key or value exits 64: `motion can't be 'fast': it takes full, reduced or off`.
  ⌘N's keys (FEATURES.md → F15): `agents.new-session`, each agent's options (`agents.claude-code.skip-permissions`, `agents.claude-code.worktree`, …),
  `agents.<agent>.flags` and `agents.<agent>.command`, the whole command ⌘N types, which only `calm config` and config.toml set.
  Added 2026-10-06 so the user can ask an agent to change them, after `calm config` was left out on 2026-09-30.

## Diagnosis

### `calm doctor [--json]` ✅

One line per check: ✓ fine, ✗ a problem with the action under it, · worth knowing (an unconnected agent is a choice). It only reads, never starts Calm, and exits 1 on a problem.

```
✓ Calm 0.1.0 answers on its socket (process 14094, running since 22:33).
✗ A newer Calm was installed at 22:44, after this one started.
    Calm → Restart Calm: until then its shells can lose access to Documents, Desktop and Downloads.
✓ This calm (0.1.0) belongs to the Calm answering.
✓ The calm on PATH is this Calm's.
✓ Claude Code: reports through Calm's plugin, in Calm's shells.
· Codex: not connected (Settings → Agents).
✓ pi: connected.
✓ This session (bcf9f1b1): working, Claude Code, last reported by a hook 4 s ago.
```

| Check | What it catches |
|---|---|
| Calm answers `info` on its socket. One process runs that Calm's executable | Calm not running, a dead or stuck socket, a Calm too old to know `info`. A second copy that holds the socket leaves rows gray or stuck on working |
| The running Calm is the build on disk (executable not newer than the process, same version) | An install that waits for Calm → Restart Calm |
| This `calm` and the `calm` on `PATH` belong to the Calm answering | A Debug `calm` that talks to the installed Calm, or a stale link. Nothing on `PATH` is a note (shells have `$CALM_CLI`) |
| Each agent whose config folder exists, as Settings → Agents sees it | Claude Code's plugin missing, or a file Calm did not write in the way. pi or OpenCode unconnected or outdated is a note |
| In a session: Calm knows it, its state, who reported it last, and whether the shell loads the Claude Code plugin | A shell that outlived its session. Hooks that never arrive |

### `calm trace [--last <duration>] [--session <id>] [--follow]` ✅

- Prints Calm's trace (DESIGNS.md → Trace) from the unified log: each event's time and the trace's own words. A heading names the day and the Calm process.
  ```
  — 2026-10-06, Calm, process 14094 —
  22:52:26.691  +1116.52 report fe7faaaa from hook says working: done → working
  ```
- Prints the last 5 minutes unless `--last` says otherwise (`30s`, `10m`, `2h`, `1d`). `--session` keeps one session's lines. `--follow` prints new lines as they come.
- Shows only the Calm this `calm` came with, every launch of it (both sides of a restart, any second copy), not a Debug build or a self-test. A `calm` outside an app shows every Calm.
  Works with or without Calm. When no line matches, it says so on stderr. Dump Logs (⌘P) writes the last 30 minutes to a file.

### `calm screenshot [<file>]` ✅

- Saves a PNG of Calm's window, title bar included, at the screen's pixel density, and prints its absolute path. The default name is `calm-<yyyyMMdd-HHmmss>.png` in the current folder.
- For an agent that checks its own change, or a bug report. It is the self-tests' capture (`WindowSnapshot`): it needs no Screen Recording permission and works under other windows.
- Calm sends the PNG over the socket, so the caller's permissions write the file. It shows whatever the sessions show, and any Calm shell, an agent included, can capture it. It never moves or focuses a window.
  Never starts Calm. Exits 1 with Calm not running or no window, and 64 for more than one file name. A Calm older than the CLI says to restart it. Only the main window is captured.

## For agents' hooks ✅

`calm --help` lists these apart. Both never fail the agent: outside Calm, or with Calm not running, they do nothing and exit 0, and they never start Calm.
They give up on the socket after 1 second (`scripts/cli-hook-check.sh`). `hook` also gives up on stdin after 1 second, and reports nothing for a payload over 16 MB.

### `calm status <state> [message] [--agent <name>] [--agent-session <id>] [--transcript <file>] [--session <id>]`

- Reports `working`, `needs-you`, `done`, `failed` or `idle`. Hook scripts can use their agent's words: `busy`, `running`, `thinking`; `waiting`, `input`, `permission`, `attention`; `finished`, `complete`, `completed`, `stop`, `stopped`; `error`, `failure`.
- The message shows on the card and in the notification. `--agent` (`claudeCode`, `codex`, `openCode`, `pi`), `--agent-session` and `--transcript` name the agent and conversation, for agents that cannot send a hook payload (pi, OpenCode).
- Calm ignores a report that names an agent other than the foreground one, because an agent run by another agent's tool inherits the session's variables.

### `calm hook <agent>`

Reads an agent's hook payload on stdin and reports what it means. Calm's Claude Code plugin runs `calm hook claude-code` for every hook. An unknown agent does nothing.

## Connecting your own agent or script

Any program can tell Calm its state. A long script, for example:

```sh
[ -n "$CALM_CLI" ] && "$CALM_CLI" status working "Running migrations" || true
./migrate
[ -n "$CALM_CLI" ] && "$CALM_CLI" status done "Migrated" || true
```

Use `$CALM_CLI`, not `calm`: Calm sets it in every Calm shell, even when `calm` is not on `PATH`, and it is the CLI of the Calm that started the shell.
Escape sequences work without the CLI as a fallback that a CLI report overrides: OSC 9;4 progress and OSC 9 or 777 notifications. DESIGNS.md → Attention → Fallback signals has the table.

## Environment

Every shell Calm starts, and every program in it, has these variables.

| Variable | Means |
|---|---|
| `CALM_SESSION_ID` | This session's full id |
| `CALM_SOCKET` | The control socket. `calm` uses it too (default `~/Library/Application Support/Calm/calm.sock`) |
| `CALM_CLI` | The path of the bundled `calm` |

## Where it's installed

The app bundles the CLI at `Calm.app/Contents/Resources/bin/calm`. `./install.sh` links it as `~/.local/bin/calm`. `--bin-dir <folder>` moves the link. `--no-cli` makes none.

## Later

Reaching Calm over SSH from another device (ROADMAP.md → Later): `calm attach <session>` joins a session's shell through zmx. `calm watch [--json]` prints one line per state change. Not checked: what a second client of another size does to Calm's pane.

## Not planned

Left out (decided 2026-09-30). Do not propose again without new facts.

- **`calm resume`, `calm new`.** ⌘K and each agent's "continue" (`claude -c`, `codex resume --last`) resume. `calm open session` opens a session in a folder.
- **`calm next`, `calm go <session>`.** The sidebar, ⌘⇧A and a notification's click already take people to a session. An agent must not move the user's attention. Only *needs you* may.
- **`calm status --step 3/5`.** The task line comes from Claude Code's todo list. Others put progress in the message (`calm status working "Running migrations (3/5)"`).
- **`calm wait <session>`.** The card tells people when a session is done. Open case: an agent that waits for a fork's answer. Decide it once agents use `calm fork` for real (DESIGNS.md → Teaching agents about `calm`).
- **`calm send <session> <text>`.** Text one agent reads could steer another with wider permissions. `zmx send` exists for whoever wants it.
- **`calm theme`.** `calm config set theme …` does it. **`calm copy`, `calm paste`.** `pbcopy` and `pbpaste` exist. **An MCP server.** The CLI already reaches every agent that can run a command.
