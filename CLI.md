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

## What comes next

Agents' hooks carry almost everything the CLI does: in 12 hours of real use, 866 of the 902 changes to session rows came through `calm hook` and `calm status`, while the author had typed `calm` once in 21,002 commands (2026-09-30). Inside Calm, the sidebar, ⌘K and ⌘O already do what the commands for people would. So the order follows who uses the CLI (decided 2026-10-06):

1. `calm doctor` and `calm trace`: for whoever is working out why a row is wrong, often an agent. Built 2026-10-06.
2. `calm config`, with ⌘N's agent command: a setting you'd ask your agent to change. Built 2026-10-06; ⌘N's keys came with ⌘N the same day.
3. `calm fork` and `calm show`: built 2026-10-06. Next, a way for agents to learn them: a plugin, needed, but not yet.

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

*Replaces:* `calm open <folder|file>`, which guesses from the path: a folder becomes a project and shows its home (until 2026-10-09, with a new session in it), a file opens in the viewer.

#### `calm open file <path>[:line]`

- Shows the file in Calm's viewer, over the session you're looking at. In code, `:line` highlights that line and centers it; Markdown shows rendered, without line numbers.
- Always the viewer, even with `open-in = "editor"` under `[files]` in config.toml: showing the file in Calm is the point of this command, and your editor has a command of its own.
- A file the viewer can't show (a kind it doesn't know, or over 5 MB) opens in your editor at that line instead.
- Fails for a missing file, and for a folder: "That's a folder: use `calm open session` or `calm open project`."

#### `calm open session [folder]`

- Opens a new session, a fresh shell, in the folder (the current folder if none is given) and takes you to it.
- Files it like any session started there: in the project that holds the folder, if one does, otherwise under its folder. It never makes a project.
- Fails for a missing folder, and for a file: "That's a file: use `calm open file`."

#### `calm open project [folder] [--new-session]`

- Makes the folder a project (the current folder if none is given), the same as ⌘O: it stays in the sidebar with its mark, even with no sessions, until you remove it.
- Shows the project's home, as ⌘O does, and starts nothing, a folder that is already a project included, so running it twice doesn't pile up shells. `--new-session` opens a new session in it instead.
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

### `calm fork ["<prompt>"] [--background] [--in <folder>] [--session <id>]` ✅

- Forks the agent conversation running in this session, or the one that ran here last. The fork is a new session of its own (a new tab), in the same project and folder, running the agent's own fork command (FEATURES.md → F12). The original goes on untouched.
- Takes you to the fork. With `--background` you stay where you are: the fork waits in the sidebar, already running (its pane is made at the terminal area's size, so its agent starts the size it will be shown at).
- The words that aren't options are the prompt, the fork's first message, so it starts working at once: `calm fork try the CRDT approach`. Claude Code and Codex take one (`claude --resume <id> --fork-session '<prompt>'`, `codex fork <id> '<prompt>'`, from their `--help`, Claude Code 2.1.285 and Codex 0.159). pi and OpenCode aren't checked; a prompt for them fails: "pi can't start a fork with a prompt."
- `--in <folder>` runs the fork in another folder. Claude Code finds the conversation from a git worktree of its own repository, but not from an unrelated folder ("No conversation found with session ID"; checked with 2.1.291 in a scratch home, no model call). The other agents aren't checked.
- Prints the new session's full id (what `--session` takes).
- Fails outside a Calm session, for a missing folder, and where there is no conversation to fork: "No conversation to fork here." It never starts Calm.
- A session started by `calm fork` can't run `calm fork` itself ("A fork can't fork: calm fork started this session."), so an agent that forks can't set off a chain. Right-click → Fork still works there. Calm keeps this in memory, so a relaunch forgets it.
- **Not yet checked:** forking in the middle of a turn, when the conversation ends in a tool call still running: the case of an agent running `calm fork` itself, which waits for the plugin that teaches agents (*What comes next*).

### `calm notify <message>` ✅

- Notifies you about this session, at the next pause if you're elsewhere: a notification with the session's name as its title and the message as its body.
- It is for people: a banner for this one command, even with banners for *done* off (Settings → Agents), as in `./deploy; calm notify "deploy finished"`. A plain shell with shell integration already marks a command of 10 seconds or more done or failed on its card; `notify` adds the banner.
- Agents report a state instead (`calm status`). Every case looked for fits one of the five: a question is *needs you*, an end is *done* or *failed*, and anything else belongs on the card, not in a banner.
- Outside Calm, or with Calm not running, it does nothing and exits 0, so it is safe in any terminal.

## Past conversations

### `calm search <text> [--limit <n>] [--json]` ✅

- Searches every agent's past conversations. One result per conversation, best first: when it was last active, its agent, project, title and its id (for `calm show`), then the matching text on the next line, indented, with the matches in bold.
- Goes through the running Calm, or reads the index itself when Calm isn't running (bringing it up to date first).
- When Calm answers with an error, it says so and exits 1, rather than search the index behind its back: a Calm older than the CLI says to update it.
- When Calm is running but hasn't answered after 15 seconds (a cold index can take it that long), it says so and reads the index itself.
- *Built:* the above, 20 results. *Parked:* `--limit` and `--json`.

### `calm show <conversation> [--prompts] [--all] [--json]` ✅

Everything Calm knows about one conversation, on one screen: what it was for, where it got to, where its work lives, and how to go back to it.

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
| Title, agent, folder, last active | The search index |
| Branch | The transcript: Claude Code's newest `gitBranch`, Codex's `session_meta.git.branch` (both seen in real transcripts); none for pi and OpenCode |
| Started | When the transcript file was made; none for OpenCode, whose conversations share one database |
| Prompts and replies | Counted in the index |
| Open in session | The running Calm (`list`): the session whose agent is in this conversation, with its state. Left out when Calm isn't running or the conversation isn't open; never starts Calm |
| Asked | The first prompt |
| Recent prompts | The last three after the first, one line each, cut to the terminal's width |
| Recap | The agent's own summary (Claude Code's recap), from the transcript's tail. Left out otherwise: the start of the last reply would only repeat it |
| Tasks | The todo list's progress and the task in progress (Claude Code) |
| Last reply | The index: the agent's newest reply, whole |
| Resume, Fork | The agent's adapter, the commands of F12's menu; left out once the transcript is gone |
| Transcript | Its path, marked *(deleted)* when the agent deleted it. Known only from the prompt history (Claude Code deletes transcripts after 30 days and keeps `history.jsonl`), it says so: its prompts are there, its replies aren't |

- A part with nothing in it is left out, not printed empty.
- `--prompts` lists every prompt you wrote, numbered, in place of the last three.
- `--all` prints the whole conversation instead: every prompt (under "You") and reply (under the agent's name) in order, without tool calls, tool output or thinking (what search indexes). For reading it through, or handing it to another agent.
- `--json` gives every part, with every message.
- Takes a conversation id, from `calm search` (each result ends with it) or `calm status`, or the start of one, 6 characters or more, that only one conversation's id begins with; several say which.
- Works without Calm, except for *Open in session*: the CLI reads the index and the transcript itself, bringing the index up to date once when it doesn't know the id.
- Fails for an id the index doesn't know.
- Checked on the author's real conversations of all four agents (fields only, on a copy of the index) and end to end in a headless self-test, where it named the session the conversation was open in.

## Settings

### `calm config [list [--json] | get <key> | set <key> <value…> | unset <key>]` ✅

- `calm config` (or `list`) prints every setting: its value in force, `(default)` when config.toml doesn't set it, and what it takes. Keys config.toml has that Calm doesn't read, and lines it can't read, follow on stderr. `--json` gives each one's value, default, whether it is set, what it takes and what it does.

  ```
  theme                    = Forest                a theme's name; unset, the Ghostty config's colors, else Calm
  motion                   = full       (default)  full, reduced or off
  agents.sound             = true                  true or false
  ```

- `help` (or `--help`, `-h`) prints the usage and exits 0.
- The list is in sections, as config.toml is: Calm's own keys, then each agent's together (`agents.claude-code.hooks`, its options, `flags`, `command`). A key that takes text says what for (`flags typed after the agent's name`, `a whole command, typed as written`).
- `get <key>` prints the value in force alone, for scripts (an unset theme prints an empty line).
- `set <key> <value…>` takes the rest of the line as the value, so a command needs no quotes (`calm config set agents.claude-code.command claude -w`; a value holding quotes still needs quoting as a whole, since the shell takes them off). It checks the value (a theme must be one there is; true/false also take yes/no, on/off, 1/0), writes the line as Settings does, one line at a time, so comments and other keys stay, and a default removes the line, as Settings does (except the theme, whose default is no value). It prints what it wrote: `theme = Forest`.
- `unset <key>` removes the line: the default applies again.
- After a change it prints what it wrote first, then asks the running Calm to read config.toml and the Ghostty config again, as Reload Configuration (⌘⇧,) does, so the change shows at once. It never starts Calm: when Calm isn't running, the change waits for its next launch, and it says so.
- The keys are those of DESIGNS.md → Settings (`Agents.settingsKeys`: `CalmSettings.keys` and the options the agents' adapters declare); a wrong key or value exits 64 and says what it takes: `motion can't be 'fast': it takes full, reduced or off`.
- Wanted first for ⌘N's agent, a setting you'd ask your agent to change. Decided 2026-10-06, after `calm config` had been left out on 2026-09-30; built the same day. ⌘N's keys (FEATURES.md → F15): `agents.new-session`, each agent's options (`agents.claude-code.skip-permissions`, `agents.claude-code.worktree`, …), `agents.<agent>.flags`, and `agents.<agent>.command`, the whole command ⌘N types, which only `calm config` and config.toml set.

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

### `calm screenshot [<file>]` ✅

- Saves a PNG of Calm's window, title bar included, at the screen's pixel density, and prints the file's absolute path. With no `<file>` it is `calm-<yyyyMMdd-HHmmss>.png` in the current folder, so two shots never overwrite each other. A relative name starts from the current folder, and `~` is the home folder.
- For whoever must see what Calm shows: an agent checking its own change, or a bug report. It is the same capture the self-tests use (`WindowSnapshot`): the window's own views drawn into a bitmap, so it needs no Screen Recording permission, shows only Calm (not what is in front of it) and works while Calm is covered by other windows.
- Calm draws it and sends the PNG back over the socket, so the file is written by the caller's own permissions. Whatever is on screen is in the picture, so it shows what the sessions show, to anyone who can run `calm` in a Calm shell, an agent included. It is read-only: it never opens, moves or focuses a window.
- Never starts Calm: with Calm not running, it says so and exits 1. Exits 1 too when Calm has no window, and 64 for more than one file name. A Calm older than the CLI can't read the request and says to restart it.
- Only the main window; a Settings window or a panel isn't captured.

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
