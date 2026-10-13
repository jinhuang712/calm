# Features

This file states the exact behavior of every feature. [UIUX.md](UIUX.md) has the visual details, [DESIGNS.md](DESIGNS.md) the implementation and [ROADMAP.md](ROADMAP.md) the order of work.

Each feature lists its settings. The budget is at most two per feature ([GOALS.md](GOALS.md) G9). Status: ✅ built and working as described · 🚧 built, with a known gap named in its section · 📝 planned, not built.

## F1 — Terminal core 🚧

A fast, correct terminal on libghostty. **Settings:** none beyond the Ghostty config.

- Calm reads `~/.config/ghostty/config`. Calm-only settings go in `~/.config/calm/terminal.ghostty`, read after it.
- Calm changes the keys below. It loads them before the Ghostty config, so a user keybinding for the same key wins.

| Key | Calm's action |
|---|---|
| ⌘K | Search sessions. Clear screen moves to ⌘⇧K. |
| ⌘, / ⌘⇧T | Open Settings / reopen a closed session. |
| ⌘N | Start the user's agent (F15). Ghostty opens a window. |
| ⌘Z | Undo the last edit of the typed line (sends Ctrl-_). No redo. |
| ⌘⌥ + arrow | Split toward that side. Ghostty moves focus. |
| ⌘↵ | Type Return, or with Send with ⌘ Return on (F5) send an agent's prompt. Never full screen (⌃⌘F is). |

- There is no tab bar. ⌘T opens a shell session and ⌘N one that runs the chosen agent (F15).
- Splits: ⌘⌥ + arrow (⌘D and ⌘⇧D split right and down), ⌘[ and ⌘] move focus, ⌘⌃ + arrow resizes. Drag a card onto a pane to split it in.
- The **split icon** in a pane's corner opens Take Out of Split, Unsplit All, Zoom Pane and Equalize Splits. The unfocused pane dims to a fixed 0.6.
- **Command palette (⌘P)** lists actions that have no key. A row runs once and shows only where it applies. Typing matches letters in order.

| Group | Rows |
|---|---|
| Agent conversation | Fork into New Split / New Tab · Resume · Restart or Don't Restart *Agent* (F12) · Copy Last Reply (Claude Code, Codex, pi) · Copy Session ID · Copy Resume Command · Open Transcript · Restart All *Agent* Sessions · Mark All Done as Seen |
| Session and layout | New *Agent* Session per agent · Rename Session · Keep Scratch Session as Project… · Jump to Waiting Session ⌘⇧A · Unsplit |
| View, folder, look | Show / Hide File Tree ⌘\ · Go to Welcome Page · Fold / Unfold All Groups · Open Folder in Finder · Copy Folder Path · Randomize Theme |
| Calm, terminal | Restart Calm · Agents Settings… · Dump Logs (writes `~/Library/Logs/Calm/calm-diagnostics-<time>.txt`: ids, states and counts only) · Reset Terminal · Toggle Mouse Reporting |

- One text size applies to all sessions. ⌘+ and ⌘− resize them, ⌘0 returns to the config's `font-size`, and Calm keeps it. While a file is open, these keys size the file (F10).
- The window returns as left: size, place, filled or full screen. Known gap: once in six test launches it came back filled, not full screen.
- ⌘V pastes text as text and copied files as escaped paths. Any other image becomes a PNG in the temporary folder and its path is pasted, so Claude Code attaches it.

## F2 — Projects and auto-grouping 🚧

The session is the unit of work: a conversation with a goal, a folder, an agent and a history. Tabs and panes only show a session.

The sidebar groups sessions in this order: Scratch, Projects, Folders. **Settings:** 1, `auto-grouping = false` under `[sidebar]` in `~/.config/calm/config.toml` (Settings → General). Off, sessions stay in their first group. ⌘⇧, reloads it.

- **Scratch:** **⌘⇧N** or **New Scratch Session** starts a session in a new empty folder under `~/.local/share/calm/scratch`. It runs ⌘N's agent (F15), or a shell with no agent.
- Only ⌘⇧N makes one: ⌘T or a split from it opens a normal session in the home folder. Calm marks the scratch root as trusted in `~/.claude.json`, so Claude Code does not ask.
- ⌘W closes it. An empty folder is removed. Otherwise Calm asks: **Move to Trash**, **Keep as Project…** or Cancel. The menu offers Keep as Project… at any time.
- **Projects:** make one with **New Project…**, **⌘O**, a folder dropped on the sidebar or `calm open` (F13). Opening one shows its **home** and starts nothing.
- The home shows the project's mark, name, folder and branch, and **⌘N** *your agent* ⌄ and **⌘T** Shell, which start there while it is up.
- **Earlier in *project*** lists the last six closed sessions from its folder. A click, or ↑ ↓ and ↵, resumes one. Esc leaves the home. A click on a project header shows its home, and the chevron folds it. **Drag a header** to reorder projects. ⌘1…9, ⌃Tab and Move to Project follow the order.
- A session started in a project stays in it, also after `cd`, and so do ⌘T and splits from it. Right-click a session: **Move to Project** (not scratch), **Let It Follow Its Folder**. A project's **⋯** has **Remove Project**: sessions stay open and regroup by folder.
- **Folders:** other sessions group by git repository root, or by folder outside git, and move when the shell runs `cd`. A line under the name shows the parent (`~/dev/apps`).
- A session inside a project's folder joins the project. **Make Project** in a group's **⋯** keeps the group. On hover a header shows the **agent's mark**, which starts ⌘N's agent there, and **>_**, which starts a shell.
- **Launch:** Calm starts where the user left off. With nothing open, a welcome page shows with no sidebar. Calm never opens a session nobody asked for.
- The page has Calm's mark, a **search field** over past sessions and projects, **Recent sessions** beside **Projects** (last row **New project…**), and the start line **⌘N** *your agent* ⌄ · **⌘T** Shell · **⌘⇧N** Scratch · **⌘O** New project….
- Typing filters both lists. ↑ ↓ move, ← → change list, ↵ opens, Esc clears, **⌘K** focuses the field. With no project, the page shows "Welcome to Calm" (first launch only) and the rows Start *your agent* ⌘N, Start a shell ⌘T, Try a scratch session ⌘⇧N, Open a project ⌘O. With no agent, ⌘T reads New session.
- **Footer:** **New *Agent* Session ⌘N** (⌄ under the pointer), **New Session ⌘T** (current session's folder), **New Scratch Session ⌘⇧N**, **New Project… ⌘O**, **Show Files ⌘\\**.
- A chevron over the footer hides it, and the sidebar's bottom edge brings it back (`footer = false` under `[sidebar]`, no Settings row).
- **⌘⌃S** hides and shows the sidebar, which peeks in at the left window edge. **⌘1…9** go to a session by place, **⌘⇧[** and **⌘⇧]** up or down, **⌃Tab** cycles over live previews (⌃⇧Tab up).
- **Session card:** name, time since last activity (while working, turn length), state, a two-line plain-text recap of the agent's latest message, a todo line ("3 of 5 · Adding tests") and the git worktree name.
- While working, the card says what the agent does ("Reading SessionCard.swift"), live from Claude Code's hooks. Other agents say "Working".
- Working, needs you and done tint the card blue, amber and sage. Idle cards shrink to name and recap, or the agent's own summary when one exists (Claude Code's "※ recap").
- Every agent gives a recap and Esc detection. Titles: Claude Code its own, OpenCode its title once named, pi its session name, Codex none. Only Claude Code gives step and progress (todos). With two possible conversations in a folder, the card shows no recap.
- A collapsed project is one line of state marks: three working agents are three blue rings, four or more a ring and a number. Waiting tints it amber. Opening a session unfolds its group.
- The folder comes from Ghostty's shell integration (zsh, fish, elvish), else from the shell process every couple of seconds.

## F3 — Persistent sessions ✅

Quitting Calm detaches shells and does not kill them. **Settings:** none.

- Relaunch reattaches with scrollback and running processes, at the old terminal size. Calm restores projects, sessions, splits and each agent's mark, state and recap.
- **Restart Calm** (Calm menu) quits, then opens Calm from the same place, so a version that `install.sh` or `get.sh` installed meanwhile starts. Calm deletes the app moved aside by the installer (DESIGNS.md → Distribution). With zmx missing and something running, it asks first, as Quit does.
- **After the Mac restarts** every shell is gone. Each session returns with a new shell in its folder. A session that had an agent resumes its conversation when first opened (F12). A quit agent stays quit.
- Closing a session ends its shell. At the next launch Calm ends shells it no longer knows, and never touches other apps' sessions.

## F4 — Agent detection ✅

**Settings:** none. Calm detects **Claude Code, Codex, OpenCode or pi** in a session's foreground within a couple of seconds, also off screen.

- It shows the agent's icon, uses the agent's session title, and links the session to the agent's transcript on disk (F6, F7, F12). It drops the status glyph at the start of the terminal title (Claude Code's ✳, ◐◓◑◒), because the card shows state.

## F5 — Agent status and attention ✅

Each agent session has one state: **working**, **needs you**, **done**, **failed** or **idle**.

- State comes from each agent's hooks or notifications. Terminal signals (bell, progress, desktop notifications) are the fallback, and alone work for Claude Code and Codex. Only the foreground agent speaks for a session.
- Codex, and OpenCode until connected, have no working hook. Calm reads their conversation files: an open turn is **working**, an ended one **done** (**failed** for OpenCode). An agent's hook outranks this guess.
- A Claude Code turn that ends with its own background agent running stays **working**. Background *shells* do not hold the state: the turn is **done** and the card adds "· 2 shells running".
- While Claude Code **compacts**, the session stays **working** and the card says "Compacting", then a bar shows what was kept ("968k → 13k"). A typed `/compact` ends as **done**. A plain shell command that ran 10 seconds or more shows **done** or **failed** until the user moves on.
- Only **needs you** escalates: the row highlights, and when the user is not looking, a macOS notification arrives at the next natural pause. A **needs you** is never dropped.
- A notification shows a state mark and the session name (✋ needs you, ✅ done, ⚠️ failed), then one or two Markdown-free lines of the agent's words. A click jumps to the session. **⌘⇧A** jumps to the one that has waited longest.
- **The first launch asks for every permission once:** notifications, then Documents, Desktop and Downloads. Removable and network volumes and Full Disk Access cannot be asked in advance.
- **done** and **failed** notify only when the user opts in (Settings → Agents). They stay in the sidebar until the user goes to another session or leaves Calm (another app with a Dock icon), then settle to idle.
- **Settings → Agents** (**Calm → Agents…**) shows how each agent connects. Claude Code uses hooks, on by default, as a plugin loaded only in Calm's shells. Calm writes nothing to Claude's settings. Codex uses its own notifications.
- pi and OpenCode connect through an extension or plugin that **Connect** adds and **Disconnect** removes. It reports needs you, turn events and the conversation, and applies Calm's theme (F11). Unconnected, OpenCode settles from its files.
- Every agent also learns the `calm` command from Calm's skill (F13). Claude Code's comes with the plugin. Connect brings it to pi, OpenCode and Codex, for which Connect adds only the skill.
- **Send with ⌘ Return** (Settings → Agents → Keys, off by default): ⌘ Return sends and Return starts a new line, in Claude Code, OpenCode and pi. Return still answers questions, allows permissions and chooses in pickers.
- Calm intercepts no key. It adds its bindings to `~/.claude/keybindings.json`, `~/.pi/agent/keybindings.json` and OpenCode's `cli.json`, and removes only those when the setting goes off. Claude Code switches at once, OpenCode and pi on restart. Calm leaves alone a file it cannot edit safely and the user's own keys, and the row says so.
- In other terminals ⌃X ↵ sends in Claude Code and OpenCode, ⌃S in pi. Codex keeps Return, since its keymap has no ⌘.

**Settings:** 3 in Settings → Agents, under `[agents]`: `notify` (only *needs you*, or also *done* and *failed*), `sound` (off) and `send-with-cmd-return` (off). `hooks = false` under `[agents.claude-code]` turns the hooks off. It is config-only, so the budget omits it.

## F6 — Arrival card ✅

A strip at the top of the pane shows when the user switches into an agent session with the sidebar hidden and something happened since. **Settings:** none.

- It shows the title, state, the last thing the agent said or asked (an idle session shows its summary) and how long ago. Calm generates nothing.
- It fades when the user types or after five seconds. **⌘⇧I** recalls it, a click dismisses it. It stays away with the sidebar showing, and when nothing is new.

## F7 — Search all sessions ✅

**⌘K**, or the **Search sessions** field at the sidebar's top, searches every past and present session of Claude Code, Codex, OpenCode and pi. **Settings:** none.

- Results are sessions, grouped as the sidebar groups them: the current group first, the others by best match. Each result marks every typed word, in the title, group name or up to three message lines.
- One or two letters match at a word's start ("d" finds *Draft*). Three or more match anywhere, and Chinese too. A word can name a group: "calm scroll".
- Each group shows a few results (three of the user's, two of others). **"13 more in calm"** shows five more, **Show less** folds it. With nothing typed, the panel lists sessions to pick back up.
- **Enter** jumps to an open session, or resumes in a new session in its folder (home if gone) with ⌘N's options (F12). ↑ ↓ move, ⇥ and ⇧⇥ jump between groups, → and ← choose more or Show less, Esc closes.
- A conversation stays searchable after its agent deletes the transcript (Claude Code does after 30 days). Older ones are found through `~/.claude/history.jsonl`, cannot resume, and Enter opens a new session in their folder.
- Search skips tool output. Ranking favors the best match, then recency, title matches and the current project. `calm search` runs it from a shell (F13).

## F8 — Smart links 🚧

- **⌘-click** opens a URL in the browser, or a file path in Calm's viewer (F10) or the user's editor. Relative paths resolve against the session's folder, then the project's. `path:line` and `path:line:column` open at that position.
- A path ending a sentence opens without the final full stop, comma or `?`. A path that is nowhere gives a small note.
- **At rest** every openable link has a faint dotted line, also a wrapped one. Changing rows lose marks until the text holds still. Programs that take the mouse (vim, htop, agent full-screen views) get none.
- **A link cut across lines** by a full-screen agent view opens whole. Calm joins a row that reaches the right edge to the next, indented row, only when the joined text leads somewhere. Cuts at `-` or `/`, or after a border (`│`, `⎿`), are not joined.
- **Holding ⌘** over a link shows a tag: file name and line, folder and what a click does ("Open in viewer", "Open in Cursor", "Open in browser", "Open in Finder", "Not found"). In programs that take the mouse, the link is still Calm's.
- **Pasted images in Claude Code** show as `[Image #4]`. **⌘** over the tag shows the image large, and **⌘-click** opens the viewer.
- Known gaps: OSC 8 links get no mark. A tag from before `/clear` shows nothing. After `claude` restarts in a session, an old tag can show the new conversation's image.

**Settings:** 2. Editor: auto-detected (VS Code, Cursor, Trae, Windsurf, Zed, Sublime Text, IntelliJ IDEA, Xcode), or Settings → General → Choose Application…, or `editor = "…"` under `[files]`. Another application opens the file but not at the line. Where paths open: viewer (default) or `open-in = "editor"` under `[files]`.

## F9 — Copy Cell ✅

Copy Cell copies one cell of a table drawn with box characters (`│ ─ ┼`), not whole rows. **Settings:** none.

- **Hold ⌥** over a table to outline the cell under the pointer. **⌥-click** copies it ("Cell copied"), also in programs that take the mouse, which do not see the click.
- **⌥-drag** that starts in a cell selects inside it only, across its wrapped lines, and copies on release. Outside a table, ⌥-drag is a rectangle selection and ⌥-click is ordinary. Calm joins wrapped lines and trims padding. It works for box tables, Markdown pipe tables and Chinese text.

## F10 — Files and viewer ✅

A quick, read-only look at the repository without leaving Calm. **Settings:** none.

- The **files column** sits right of the sidebar and shows the focused session's project: changes, then the tree, without git-ignored files. **⌘\\** toggles it. A user ⌘\\ keybinding or a global shortcut (1Password) wins (UIUX.md → Keyboard).
- The header shows the project, the branch when it fits, and added and removed lines (`calm  main  +128 −41`). The column follows the focused session and re-reads every 5 seconds.
- **Changes** lists changed files, staged or not, in path order: letter, name, folder if room and `+64 −31` against the last commit. Letters: **M** modified, **A** added, **D** deleted, **R** renamed, **U** untracked.
- **An untracked folder over 500 files** is one unread row (`620 files`, **U**). The header total leaves it out, but the title strip's `N changed` counts it.
- **Files** is the tree: folders first, natural order (`View2` before `View10`). A folder outside git is listed directly, skipping hidden folders and build output (`node_modules`, `build`, `DerivedData`, `Pods`, `target`, `dist`), up to 5,000 files, with no branch or Changes. Desktop, Documents and Downloads in the home folder list closed and are read when opened, so macOS asks once per folder.
- **Finding the column:** the footer row **Show Files ⌘\\**, and while the project has uncommitted changes, the title strip readout `3 changed +58 −6`, which becomes `Show Files ⌘\` under the pointer.
- **Viewer:** a viewable file (Markdown, HTML, PDF, images, highlighted code) **covers the main area** under the title strip. **Esc** or a click on the session's name returns to the session, still running. Going to another session closes it.
- The file's row shows a `‹` back button, name, folder, type (`PNG · 2000 × 302 · 84 KB`, `PDF · 6 pages`), size and **Open in Editor** (**Open in Preview** for pictures and PDFs). Files open from the tree, ⌘-click (F8) or `calm open` (F13).
- **Size:** ⌘+, ⌘− and ⌘0 size the open file. Text formats step 50% to 300% and keep it across relaunches. Pictures and PDFs step 50% to 800% from fit. Off 100%, the row shows `125%` with − and + under the pointer.
- **Changed files** add `+3 −3` and a switch **File | Unified | Split**. File, the default, marks changed lines with a bar. Unified and Split diff against the last commit with three context lines. A file opened from Changes starts on Unified.
- A file not in the last commit says **New**. Pictures, PDFs and HTML show no changes. No editing, staging or review.

## F11 — Themes ✅

A theme styles the **whole window**: terminal colors, sidebar, cards, panels, files column, viewer and accent. Window options sit beside it.

- Five soft themes, each light and dark: **Calm** (default, neutral charcoal), **Ink** (near-black), **Dusk** (deep blue), **Forest** (green-gray), **Plum** (violet-gray). They follow the system appearance.
- Settings → Appearance (⌘,) previews each and writes `theme = "Ink"`. With its own colors in the Ghostty config, **Your Ghostty** comes last. A theme picked in Calm wins over those colors. Custom themes are TOML files in `~/.config/calm/themes/` (DESIGNS.md → Themes).
- A connected OpenCode or pi gets Calm's `calm` theme, kept in step. An unconnected OpenCode gets `system`, and a theme in its `cli.json` wins.

| Option | Values |
|---|---|
| Interface size | Default, Large, Larger, Largest. The terminal text keeps the Ghostty font's size. |
| Session cards | Full, Compact, Minimal. **Shrink cards to fit** (off) steps down when sessions overflow, never past the chosen size. |
| Background, layout | Solid or glass. Edge to edge, or card. |
| Motion | Full, reduced, off. System Reduce Motion wins. `smooth-scroll = false` in `terminal.ghostty` stops only scrolling. |

**Settings:** 7, over the budget, in Settings → Appearance: `theme`, `ui-size = "larger"`, `cards = "compact"`, `cards-fit = true` (`[sidebar]`), `background = "glass"`, `layout = "card"` (`[window]`), `motion = "reduced"`. A default removes its key, except the theme (F14).

## F12 — Session actions ✅

**Settings:** none. Right-click a card, or use ⋯ at the title strip's right, for one menu with agent actions as tiles (UIUX.md → The session menu).

- **Rename…** edits in place (return keeps, esc cancels, empty restores the title). The name wins everywhere and survives relaunch. **Resume:** after the agent exits, Resume *Agent* Conversation continues it in the same shell with its start options. A closed session resumes from ⌘K with ⌘N's options.
- **Restart** a running agent on its conversation: Restart *Agent* in the menu and ⌘P, Restart All *Agent* Sessions in ⌘P only, or a click on the update hint. While the agent works or waits, it reads Restart After This Turn, then Don't Restart. Calm quits the agent cleanly and types the start command with the same options, without the prompt.

| Agent | Quit | Restart and Resume | Fork |
|---|---|---|---|
| Claude Code | SIGTERM | `claude <options> --resume <id>` (drops `-c`, `-r`, `--session-id`, `--fork-session`, `-w`, `--tmux`) | adds `--fork-session` |
| Codex | ⌃C, again if still running (twice with a draft) | `codex resume <options> <id>` (drops subcommand, prompt, `-i`, `--last`, `--worktree`) | `codex fork <options> <id>` |
| OpenCode | SIGTERM | `opencode <options> --session <id> [<folder>]`. No restart from `mini` or `run`. | `opencode api session.fork`, then `--session` |
| pi | SIGTERM | `pi --session <file>`. pi hides its options, so none carry over. | `pi --fork <file>` |

- An action shows only where the agent has the command. `<options>` are those the agent started with. For a conversation Calm did not see run, they are ⌘N's chips and `flags` (or `command`), less a new worktree. When the agent runs an older version than installed, the title strip shows the **update hint** ("↑ Claude Code 2.1.291") and a click restarts it.
- **Close:** ⌘W or Close Session. While an agent or process runs, Calm asks first. With Settings, search or a file open, ⌘W closes that instead. Closing the current session shows what waits, or search.
- In a split the question sits on the pane: Return closes, any other key keeps. An empty agent-made worktree goes with the session (F15).
- **Reopen:** **⌘⇧T** reopens the last closed session, up to ten, with a new shell and the old folder, name, project and place. A running agent resumes. Scratch sessions do not reopen.
- **Copy** has Session ID, Resume Command, Folder Path and Open in Finder. **Fork** starts a conversation copy in a new split or tab with the original's options.

## F13 — `calm` command-line tool ✅

The `calm` command reaches Calm from a shell. It opens a folder or file, lists the sessions, searches and shows past conversations, forks the current one, changes settings and checks that Calm works. Agents' hooks report through it too. [CLI.md](CLI.md) specifies every command. **Settings:** none.

- **Agents know it.** All four agents get one skill, `calm`, which teaches them the commands people ask for and keeps them from reporting state themselves. Claude Code's comes with Calm's plugin, the others' with Connect (F5).
- An agent forks only when asked, and in the background, so the user stays where they are and the fork waits in the sidebar. Later it can tell how the fork went. Each command asks by the agent's own permission rules (DESIGNS.md → Teaching agents about `calm`).

## F14 — Settings ✅

⌘, turns the window into Settings (UIUX.md → Settings screen). ⌘, again, esc or going to a session leaves it. Sections: **Appearance** (window miniature, themes, window options, F11), **Agents**, **General**, **Shortcuts**.

- **Agents:** **⌘N starts**, a row per installed agent (mark, name, a chip per start option, Connect / Set Up… / Disconnect), which states notify, and sound.
- **General:** editor and where paths open (F8), auto-grouping (F2), update checks (F17), config files with Open. **Shortcuts:** Calm's shortcuts. Change keys in the Ghostty config, where a keybinding wins.
- After a hand edit, Calm → Reload Configuration updates the page. Every change saves to `config.toml` at once, keeping comments and unknown keys. A default removes its key, except the theme, which stays so it wins over the user's Ghostty colors.

## F15 — New agent sessions ✅

- **⌘N** starts the agent chosen in Settings → Agents in a new session where ⌘T would open one: the current folder or project, or the home folder from the welcome page and scratch sessions. **⌘T** stays a shell.
- **⌘⇧N** starts the same agent in a new scratch folder (F2). Calm never asks which agent. Unset means Claude Code, else the first installed, else ⌘N opens a shell.
- Calm types the command into the new shell, as Resume and Fork do (F12), so PATH, mise and direnv run first and the shell stays when the agent exits.
- **How it starts:** a chip under each agent's name per flag. Chips are plain on/off flags that cannot conflict. There is no pick-one option such as a model.

| Agent | Chips | Flags |
|---|---|---|
| Claude Code | Skip permissions, New worktree | `--dangerously-skip-permissions`, `-w` |
| Codex | Skip approvals and sandbox, New worktree | `--yolo`, `--worktree` |
| OpenCode | Auto-approve | `--auto` |
| pi | Trust project files | `--approve` |

- **New worktree** shows only when the session's folder is in a git repository. Other flags go in `flags` in the agent's section (`[agents.claude-code]`, `flags = "--model opus"`).
- **The whole command:** an agent's `command` key makes ⌘N type exactly that, for example `claude -w`. Without the key, the chips decide again. **An empty worktree goes with its session.** Calm removes the worktree Claude Code made (`claude -w`) with `git worktree remove` and `git branch -d`, without force, only when Claude Code has exited, no other session is in it, and it has no change, untracked file or branch-only commit. Other worktrees stay.
- **Another agent:** the ⌄ beside ⌘N's rows lists other agents and Choose What ⌘N Starts…. ⌘P has New *Agent* Session per agent. An agent can change these keys with `calm config` (F13), which it learns from Calm's `calm` skill.
- A new agent version can rename a flag. The agent then refuses to start and says why, and the adapter changes the flag.

**Settings:** over the budget: ⌘N's agent (`new-session` under `[agents]`) and a switch per chip (`skip-permissions`, `worktree`, `trust-project-files` in each agent's section). `flags` and `command` per agent are config-only.

## F16 — Find in a session (⌘F) 🚧

Looks: UIUX.md → Find. Engine: DESIGNS.md → Find. Plan: ROADMAP.md → M8, M9. **Settings:** none.

- **⌘F** opens find for the current session or split pane, each with its own search, in the title strip's right. The last search returns selected. **⌘E** finds the selected text. **⌘F again closes it.** The Edit menu has Find…, Find Next ⌘G, Find Previous ⌘⇧G.
- Matches mark as the user types. Case does not matter for A to Z. **`.*`** (click or ⌥⌘R) makes the words a regular expression: `(error|warn)\w*`. `(?-i)` first makes case matter. A half-typed pattern says "Incomplete pattern".
- **Newest first:** "1 of 11" is the match nearest the bottom. ↵ or ⌘G goes older, ⇧↵ or ⌘⇧G newer. It stops at the ends. Matches are underlined in the accent. The current one is a pill on a band, with a bar at the pane edge. Find's line wins under a link's dots, but while ⌘ is held the link's underline and tag win.
- **Map:** with more log than the screen, a strip at the pane's right edge has a tick per matching line and a box for the screen. A click selects that match.
- ⌘F, esc in the field, or typing into the session closes find. Esc in the terminal always goes to the program. Another session or pane closes it.
- **Full-screen programs** (Claude Code's view, vim, less, htop) keep no scrollback, so find sees the screen: "2 of 3 on screen". No map. With no match, an agent offers **Search all of it ⌘K**. **The whole session** (M9): **Screen | Session** shows in a full-screen program. Session searches shell output and every line the program showed, except in-place changes of spinners and status bars, as a page over the terminal. Esc returns to the live program. Calm keeps up to 50,000 lines per session in memory.
- **A viewed file** (F10): ⌘F finds in it, with the field in the file's row. Esc closes find before the viewer. A PDF or web page has no `.*`, and a picture has nothing to find.
- A narrow strip shrinks the field from 340 to 240 pt first (UIUX.md → Find). ⌘K searches conversations (F7).

## F17 — Updates ✅

**Settings:** 1, Settings → General → **Check for updates** (`updates.check`, default on). Off, Calm never asks on its own and Check for Updates… still works.

- A newer release shows as `↑ 0.2.0` at the sidebar's top right (UIUX.md → The update notice). No dialog, sound or badge. A click opens a menu: **Update and Restart** (not in Homebrew or Debug builds), **Release Notes**, **Copy Update Command** and **Skip 0.2.0**.
- Copy Update Command gives `brew upgrade --cask calm` for Homebrew, else the README's one-line install. **Update and Restart** runs `get.sh` into the folder Calm runs from, then restarts like Calm → Restart Calm. Calm never installs on its own. **When:** a few seconds after launch and when Calm comes forward, only when due: daily, or an hour after a failure. No timer runs. It sends one request to GitHub's releases list (DESIGNS.md → Updates). A failure is quiet.
- **Newer** means the highest `vMAJOR.MINOR.PATCH` among non-draft releases. The pre-release flag and other tags such as `edge` are ignored (DESIGNS.md → Distribution). An edge build reads `0.1.0-dc970ac` and counts as the release it follows.
- **Calm → Check for Updates…** asks now and answers in a dialog. A skipped release is offered again. The Dev build and self-tests never look on their own.

## Later, if needed

| Idea | Note |
|---|---|
| Spotlight integration | Publish sessions to Spotlight; semantic indexing on macOS 27+ |
| Scrollback search across open sessions | Complements F7 |
| Paste history | Small and handy |
| Triggers on output patterns | Overlaps F5 |
| Keyboard copy mode | For long scrollback |
| Copy attach command | A one-line `ssh … zmx attach …` to reach a session from another device; remote access goes through SSH (below) |
| A download that opens with a double-click | Needs Developer ID signing and notarization, which need an Apple Developer Program account |
| Sparkle updates | Only if it earns its place over `get.sh` |
| A cask in Homebrew's own list | Homebrew takes only apps that pass Gatekeeper. Calm's own tap has the cask. |

## Explicitly not planned

| Not planned | Why |
|---|---|
| Built-in AI chat or model calls | Agents bring their own interfaces. Calm stays a terminal. |
| File editing, code review views | They belong in the user's editor. |
| In-app browser, computer use | Playwright and browser tools already do this. |
| Accounts, cloud sync, relays, cloud VMs, own mobile app | The agents' own remote features and SSH cover remote access. |
| Windows or Linux | Calm is a native macOS app. |
| Replacing tmux on remote servers | SSH into a remote tmux works inside Calm. |
| A drop-down quick terminal on a global hotkey | Daily agent work does not need it. |
| Configurability for its own sake | Choice overload works against calm. |
