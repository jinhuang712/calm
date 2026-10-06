# The `calm` command line

Everything `calm` does, command by command. It is how people, scripts and agents reach Calm from a shell. [FEATURES.md](FEATURES.md) → F13 sums it up; how it talks to the app is in [DESIGNS.md](DESIGNS.md) → Control protocol.

Status: ✅ built and working as described · 📝 planned, in the order under *What comes next* · ⏸ parked: specified, waiting for a real need. Where a planned command replaces something built, its section says what.

---

## At a glance

| Command | What it does | Status |
|---|---|---|
| `calm` | Opens Calm | ⏸ (today: prints the help) |
| `calm open file <path>[:line]` | Shows a file in Calm's viewer | ⏸ (today: `calm open <file>`) |
| `calm open session [folder]` | Opens a new session in a folder | ⏸ |
| `calm open project [folder]` | Makes a folder a project | ⏸ (today: `calm open <folder>`) |
| `calm list` | Lists the open sessions | ✅ (⏸ ids, `--json`) |
| `calm status` | Describes this session | ⏸ |
| `calm fork ["<prompt>"]` | Forks this session's conversation into a new session | 📝 |
| `calm search <text>` | Finds past conversations | ✅ (📝 conversation ids, with `show`; ⏸ `--limit`, `--json`) |
| `calm show <conversation>` | Everything Calm knows about one conversation | 📝 |
| `calm notify <message>` | Notifies you about this session | ✅ |
| `calm config` | Reads and changes Calm's settings | ✅ |
| `calm doctor` | Checks that Calm and the agents' hooks work | ✅ |
| `calm trace` | Prints Calm's timeline log | ✅ |
| `calm status <state>`, `calm hook <agent>` | For agents' hooks: report a state | ✅ |
| `calm --help`, `calm --version` | Help, and the CLI's version | ✅ |

## What comes next

Agents' hooks carry almost everything the CLI does: in 12 hours of real use, 866 of the 902 changes to session rows came through `calm hook` and `calm status`, while the author had typed `calm` once in 21,002 commands (2026-09-30). Inside Calm, the sidebar, ⌘K and ⌘O already do what the commands for people would. So the order follows who uses the CLI (decided 2026-10-06):

1. `calm doctor` and `calm trace`: for whoever is working out why a row is wrong, often an agent. Built 2026-10-06.
2. `calm config`, with ⌘N's agent command: a setting you'd ask your agent to change. Built 2026-10-06; ⌘N's own key comes with ⌘N.
3. `calm fork` and `calm show`, then a way for agents to learn them: a plugin, needed, but not yet.

The ⏸ commands wait until a real need shows up (a script, SSH from another device).

## Conventions

- **Exit codes:** 0 done; 1 failed, with the reason on stderr; 64 wrong usage.
- **Output** is plain text, one record per line. Color, bold and state marks only when printing to a terminal. Every command that prints data (`list`, `status`, `search`, `show`, `doctor`) takes `--json`: one JSON document with a `"v": 1` field, so a script can tell when its shape changes.
- **Starting Calm.** `calm`, `open` and `list` start Calm when it isn't running and wait up to 5 seconds for it. The Calm they start is the app the CLI came with (so a copy installed elsewhere, or a Debug build, starts itself), and only for the standard socket: when `CALM_SOCKET` names another one (a self-test's), that Calm can't be started from here, and they say it isn't running. `search`, `show` and `trace` work without it, reading files directly. `doctor` reports that it isn't running. The hook commands and `notify` never start it.
- **Two kinds of id.**
  - A *session id* names a session open in Calm: the first 8 hex digits of its id, the same ones the trace and zmx names use. A full id works too.
  - A *conversation id* names an agent's conversation: the agent's own id, the one **Copy Session ID** gives and the agent's resume command takes.
- **This session** is the one whose shell runs the command (`$CALM_SESSION_ID`); `--session <id>` picks another. Commands about this session fail outside Calm, except the hook commands and `notify`, which do nothing and exit 0.
- Relative paths start from the current folder.

## Opening

### `calm` ⏸

Opens Calm: starts it if it isn't running, and brings its window to the front. In a Calm shell, with Calm already in front, nothing changes.

*Replaces:* today `calm` alone prints the help, which stays at `calm --help`.

### `calm open` ⏸

Three branches, one for each thing you open. `calm open` alone, or with a path and no branch, prints the three and exits 64.

*Replaces:* `calm open <folder|file>`, which guessed from the path: a folder became a project with a new session in it, a file opened in the viewer.

#### `calm open file <path>[:line]`

- Shows the file in Calm's viewer, over the session you're looking at. In code, `:line` highlights that line and centers it; Markdown shows rendered, without line numbers.
- Always the viewer, even with `open-paths = "editor"` in config.toml: showing the file in Calm is the point of this command, and your editor has a command of its own.
- A file the viewer can't show (a kind it doesn't know, or over 5 MB) opens in your editor at that line instead.
- Fails for a missing file, and for a folder: "That's a folder: use `calm open session` or `calm open project`."

#### `calm open session [folder]`

- Opens a new session, a fresh shell, in the folder (the current folder if none is given) and takes you to it.
- Files it like any session started there: in the project that holds the folder, if one does, otherwise under its folder. It never makes a project.
- Fails for a missing folder, and for a file: "That's a file: use `calm open file`."

#### `calm open project [folder] [--new-session]`

- Makes the folder a project (the current folder if none is given), the same as ⌘O: it stays in the sidebar with its mark, even with no sessions, until you remove it.
- A new project opens with one session in it, and takes you there.
- A folder that is already a project takes you to its most recent session, opening one only if it has none, so running it twice doesn't pile up shells. `--new-session` opens a new session in it instead.
- A folder inside another project becomes a project of its own, as with ⌘O.
- Fails for a missing folder or a file.

## Sessions

### `calm list [--json]` ✅

- One line per open session, in the sidebar's order, fields separated by tabs: session id, state, project, title, agent (`-` for none) and folder.

  ```
  a1b2c3d4	needs-you	calm	Fix flaky test	Claude Code	/Users/me/dev/calm
  ```

- `--json` also gives each session's full id and its agent's conversation id.
- Starts Calm in the background when it isn't running.
- *Built:* project, title, state, agent and folder. *Parked:* the session id first, and `--json`.

### `calm status [--json] [--session <id>]` ⏸

- Describes this session, one field per line: its state and the message behind it, its agent, the agent's conversation id, the transcript Calm reads, its project and its folder.

  ```
  state         needs-you  Allow Bash: rm -rf build
  agent         Claude Code
  conversation  0f9c2a7e-…
  transcript    ~/.claude/projects/-Users-me-dev-calm/0f9c2a7e-….jsonl
  project       calm
  folder        /Users/me/dev/calm
  ```

- Fails outside a Calm session: "Not in a Calm session."
- With a state after it (`calm status done`), it is the hook command instead (below).

### `calm fork ["<prompt>"] [--background] [--in <folder>] [--session <id>]` 📝

- Forks the agent conversation running in this session, or the one that ran here last. The fork is a new session of its own (a new tab), in the same project and folder, running the agent's own fork command (FEATURES.md → F12). The original goes on untouched.
- Takes you to the fork. With `--background` you stay where you are, and the fork appears in the sidebar.
- The prompt becomes the fork's first message, so it starts working at once. Claude Code and Codex take one (`claude --resume <id> --fork-session "<prompt>"`, `codex fork <id> "<prompt>"`, read from their `--help`, Claude Code 2.1.285 and Codex 0.159). pi and OpenCode aren't checked yet; until they are, a prompt for them fails.
- `--in <folder>` runs the fork in another folder, such as a git worktree made for it.
- Prints the new session's id.
- Fails outside a Calm session, and where there is no conversation to fork: "No conversation to fork here."
- A session started by `calm fork` can't run `calm fork` itself ("A fork can't fork."), so an agent that forks can't set off a chain. Right-click → Fork still works there.
- **Not yet checked:** whether each agent finds the conversation from another folder with `--in` (Claude Code keeps transcripts by the folder a conversation started in); and forking in the middle of a turn, when the conversation ends in a tool call still running, which is exactly the case of an agent running `calm fork` itself.

### `calm notify <message>` ✅

- Notifies you about this session, at the next pause if you're elsewhere: a notification with the session's name as its title and the message as its body.
- It is for people: a banner for this one command, even with banners for *done* off (Settings → Agents), as in `./deploy; calm notify "deploy finished"`. A plain shell with shell integration already marks a command of 10 seconds or more done or failed on its card; `notify` adds the banner.
- Agents report a state instead (`calm status`). Every case looked for fits one of the five: a question is *needs you*, an end is *done* or *failed*, and anything else belongs on the card, not in a banner.
- Outside Calm, or with Calm not running, it does nothing and exits 0, so it is safe in any terminal.

## Past conversations

### `calm search <text> [--limit <n>] [--json]` ✅

- Searches every agent's past conversations. One result per conversation, best first: when it was last active, its agent, project and title, then the matching text on the next line, indented, with the matches in bold.
- Goes through the running Calm, or reads the index itself when Calm isn't running (bringing it up to date first).
- When Calm answers with an error, it says so and exits 1, rather than search the index behind its back: a Calm older than the CLI says to update it.
- When Calm is running but hasn't answered after 15 seconds (a cold index can take it that long), it says so and reads the index itself.
- *Built:* the above, 20 results. *Planned with `calm show`:* each result's conversation id. *Parked:* `--limit` and `--json`.

### `calm show <conversation> [--prompts] [--all] [--json]` 📝

Everything Calm knows about one conversation, on one screen: what it was for, where it got to, where its work lives, and how to go back to it.

```
Fix the flaky auth test                                        Claude Code
calm · ~/dev/apps/calm · wt-auth-fix
Started 3 days ago · last active 2h ago · 14 prompts, 31 replies
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

Resume      claude --resume 0f9c2a7e-…
Fork        claude --resume 0f9c2a7e-… --fork-session
Transcript  ~/.claude/projects/-Users-me-dev-apps-calm/0f9c2a7e-….jsonl
```

| Part | Comes from |
|---|---|
| Title, agent, folder, last active | The search index |
| Project | The project that holds the folder, while Calm runs; else the folder's name |
| Branch | The transcript: Claude Code's `gitBranch`, Codex's `session_meta` (both seen in real transcripts); pi and OpenCode not checked |
| Started | The transcript's first record |
| Prompts and replies | Counted in the index |
| Open in session | The running Calm: the session whose agent is in this conversation, with its state. Left out when Calm isn't running or the conversation isn't open |
| Asked | The index's first prompt |
| Recent prompts | The index: your last three, one line each, cut to fit |
| Recap | The transcript's tail: the agent's own summary (Claude Code's recap), else the start of its last reply |
| Tasks | The transcript's tail: the todo list's progress and the task in progress (Claude Code only) |
| Last reply | The index: the agent's newest reply |
| Resume, Fork | The agent's adapter, the same commands as F12's menu |
| Transcript | The index, marked *deleted* when the file is gone (Claude Code deletes transcripts after 30 days; its prompts outlive them in `history.jsonl`) |

- A part with nothing in it is left out, not printed empty.
- `--prompts` lists every prompt you wrote, numbered, in place of the last three.
- `--all` prints the whole conversation as text instead: every prompt and reply in order, without tool calls, tool output or thinking (what search indexes). For reading it through, or handing it to another agent.
- `--json` gives every part, with the full lists.
- Takes a conversation id, from `calm search` or `calm status`.
- Works without Calm, except for *Open in session* and the project: the CLI reads the index and the transcript itself.
- Fails for an id the index doesn't know.

## Settings

### `calm config [list [--json] | get <key> | set <key> <value> | unset <key>]` ✅

- `calm config` (or `list`) prints every setting: its value in force, `(default)` when config.toml doesn't set it, and what it takes. Keys config.toml has that Calm doesn't read, and lines it can't read, follow on stderr. `--json` gives each one's value, default, whether it is set, what it takes and what it does.

  ```
  theme                    = Forest                a theme's name; unset, the Ghostty config's colors, else Calm
  motion                   = full       (default)  full, reduced or off
  agents.sound             = true                  true or false
  ```

- `get <key>` prints the value in force alone, for scripts (an unset theme prints an empty line).
- `set <key> <value>` checks the value (a theme must be one there is; true/false also take yes/no, on/off, 1/0), writes the line as Settings does, one line at a time, so comments and other keys stay, and a default removes the line, as Settings does (except the theme, whose default is no value). It prints what it wrote: `theme = Forest`.
- `unset <key>` removes the line: the default applies again.
- After a change it asks the running Calm to read config.toml and the Ghostty config again, as Reload Configuration (⌘⇧,) does, so the change shows at once. It never starts Calm: when Calm isn't running, the change waits for its next launch, and it says so.
- The keys are those of DESIGNS.md → Settings (`CalmSettings.keys`); a wrong key or value exits 64 and says what it takes: `motion can't be 'fast': it takes full, reduced or off`.
- Wanted first for ⌘N's agent command, a setting you'd ask your agent to change (its key comes with ⌘N). Decided 2026-10-06, after `calm config` had been left out on 2026-09-30; built the same day.

## Diagnosis

### `calm doctor [--json]` ✅

Checks that Calm works and reaches you, one line per check: ✓ fine, ✗ a problem with what to do under it, · worth knowing (an agent left unconnected is a choice, not a fault). It only reads, never starts Calm, and exits 1 when a check finds a problem. `--json` gives the checks with `"v": 1`.

```
✓ Calm 0.1.0 answers on its socket (process 14094, running since 22:33).
✗ A newer Calm was installed at 22:44, after this one started.
    Calm → Restart Calm: until then its shells can lose access to Documents, Desktop and Downloads.
✓ This calm (0.1.0) belongs to the Calm answering.
✓ The calm on PATH is this Calm's.
✓ Claude Code: reports through Calm's plugin, in Calm's shells.
· Codex: reports through its own notifications and transcript; no hooks, by design.
✓ pi: connected.
✓ This session (bcf9f1b1): working, Claude Code, last reported by a hook 4 s ago.
```

| Check | What it catches |
|---|---|
| Calm answers `info` on its socket | Calm not running, a dead or stuck socket, or a Calm too old to know `info` |
| One process runs that Calm's executable | A second copy holding the socket, which leaves rows gray or stuck on working (2026-09-29) |
| The running Calm is the build on disk: its executable wasn't written after the process started, and the versions match | An install waiting for Calm → Restart Calm |
| This `calm` comes with the Calm answering, at its version | A Debug build's `calm` talking to the installed Calm, or the reverse |
| The `calm` on `PATH` is that Calm's | A stale link (nothing on `PATH` is only a note: Calm's shells have `$CALM_CLI`) |
| Each agent whose config folder is there, as Settings → Agents sees it | Claude Code's plugin missing, a file Calm didn't write in the way; pi or OpenCode not connected, or connected with an older file, is a note |
| In a Calm session: Calm knows it, its state and who last reported it, and whether this shell loads Calm's Claude Code plugin | A shell that outlived its session; hooks that never arrive |

### `calm trace [--last <duration>] [--session <id>] [--follow]` ✅

- Prints Calm's trace, the timeline of what decides each session's row (DESIGNS.md → Trace), from the unified log: each event's time and the trace's own words, under a heading for the day and the Calm process, so a restart starts a new heading.

  ```
  — 2026-10-06, Calm, process 14094 —
  22:52:26.691  +1116.52 report fe7faaaa from hook says working: done → working
  ```

- The last 5 minutes unless `--last` says otherwise (`30s`, `10m`, `2h`, `1d`). `--session` keeps one session's lines (its id, or the first 8 hex digits the trace uses); `--follow` prints new ones as they come.
- Only the Calm this `calm` came with: every launch of that app, so both sides of a restart and any second copy, but not a Debug build's or a self-test's. A `calm` outside an app shows every Calm's.
- Works whether or not Calm is running. When nothing matches, it says so on stderr. Dump Logs (⌘P) puts the last 30 minutes of the running Calm's trace in a file.

## For agents' hooks ✅

Listed apart at the end of `calm --help`, since people rarely type them. Both never fail the agent: outside a Calm session or with Calm not running they do nothing and exit 0, they never start Calm, and they give up on the socket after 1 second (`scripts/cli-hook-check.sh` checks this). `hook` also gives up on its input after 1 second, so a hook runner that leaves stdin open can't hold the agent, and reports nothing for a payload over 16 MB.

### `calm status <state> [message] [--agent <name>] [--agent-session <id>] [--transcript <file>] [--session <id>]`

- Reports this session's state: `working`, `needs-you`, `done`, `failed` or `idle`. Hook scripts can use their agent's words: `busy`, `running`, `thinking`; `waiting`, `input`, `permission`, `attention`; `finished`, `complete`, `completed`, `stop`, `stopped`; `error`, `failure`.
- The message shows on the session's card and in its notification.
- `--agent` (`claudeCode`, `codex`, `openCode`, `pi`), `--agent-session` and `--transcript` say which agent and which of its conversations this is, for agents that can't send a hook payload (pi's extension and OpenCode's plugin use them).
- A report naming an agent other than the one in the session's foreground is ignored: an agent run by another agent's tool inherits the session's variables, and mustn't speak for it.

### `calm hook <agent>`

- Reads an agent's hook payload on stdin and reports what it means. Calm's Claude Code plugin runs `calm hook claude-code` for every hook. An agent it doesn't know does nothing.

## Connecting your own agent or script

Any program can tell Calm its state, not only the agents Calm knows. A long script, for example:

```sh
[ -n "$CALM_CLI" ] && "$CALM_CLI" status working "Running migrations" || true
./migrate
[ -n "$CALM_CLI" ] && "$CALM_CLI" status done "Migrated" || true
```

Use `$CALM_CLI`, not `calm`: it is set in every Calm shell even when `calm` isn't on `PATH`, and it is the CLI of the Calm that started the shell.

Without the CLI, escape sequences work too, as a fallback that a report through the CLI overrides: OSC 9;4 progress (working, then done or failed) and OSC 9 or 777 desktop notifications, read by their words. DESIGNS.md → Attention → Fallback signals has the full table.

## Environment

Every shell Calm starts has these, and so does everything it runs, an agent included.

| Variable | Means |
|---|---|
| `CALM_SESSION_ID` | This session's full id |
| `CALM_SOCKET` | The control socket; `calm` uses it too (default `~/Library/Application Support/Calm/calm.sock`) |
| `CALM_CLI` | The path of the bundled `calm` |

## Where it's installed

- Bundled in the app at `Calm.app/Contents/Resources/bin/calm`.
- `./install.sh` links it as `~/.local/bin/calm`; `--bin-dir <folder>` puts the link elsewhere, and `--no-cli` makes none.

## Later

- Reaching Calm over SSH from another device (ROADMAP.md → Later): `calm attach <session>` to join a session's shell through zmx, and `calm watch [--json]` for one line per state change. Not checked: what a second client of another size does to Calm's pane.

## Not planned

Considered and left out, so they aren't proposed again without new facts (2026-09-30):

- **`calm resume`, `calm new`.** ⌘K and each agent's own "continue" (`claude -c`, `codex resume --last`) resume a conversation; a session in a folder is `calm open session`.
- **`calm next`, `calm go <session>`.** People have the sidebar, ⌘⇧A and a notification's click, which already take them to a session. An agent shouldn't move your attention at all: only *needs you* may, and it has its own way.
- **`calm status --step 3/5`.** A card's task line comes from Claude Code's todo list; for any other agent or script, the message carries progress well enough (`calm status working "Running migrations (3/5)"`).
- **`calm wait <session>`.** People have the card, which says when a session is done. What is left is an agent waiting for a fork's answer; decide that along with how agents learn `calm fork`.
- **`calm send <session> <text>`.** If any process could type into any session, text one agent reads could steer another agent with wider permissions. `zmx send` exists for whoever wants it.
- **`calm theme`.** `calm config set theme …` does it, and settings are rare.
- **`calm copy`, `calm paste`.** `pbcopy` and `pbpaste` exist.
- **An MCP server.** The CLI already reaches every agent that can run a command.
