# Features

Precise behavior of every feature. Visual details live in [UIUX.md](UIUX.md), implementation in [DESIGNS.md](DESIGNS.md), order in [ROADMAP.md](ROADMAP.md).

Each feature lists the settings it adds. The budget is at most one or two per feature (see [PHILOSOPHY.md](PHILOSOPHY.md)).

Status: 📝 planned · 🚧 in progress · ✅ shipped

---

## F1 — Terminal core 🚧

A fast, correct terminal on libghostty.

- Reads the user's Ghostty config (`~/.config/ghostty/config`) for fonts, keybindings and terminal behavior, so existing setups carry over.
- Tabs and splits (horizontal and vertical), with keyboard navigation.
- Command palette (⌘P) listing every action with its shortcut.
- One text size for every session: ⌘+ and ⌘− (or the user's own font-size keybindings) resize all sessions and splits together, new ones start at that size, and it's kept across relaunches. ⌘0 goes back to the config's `font-size`.
- Rectangle selection with ⌥-drag, inline images, true color, ligatures (all from libghostty).
- ⌘V pastes text as text and copied files as their escaped paths. An image with neither (a screenshot, a picture copied from a browser) is saved as a PNG in the temporary folder, and its path is pasted, so agents like Claude Code attach it (`[Image #1]`). Dropping such an image works the same way.
- A drop-down quick terminal on a global hotkey.

**Settings:** none beyond the Ghostty config.

## F2 — Projects and auto-grouping 🚧

- The sidebar groups sessions three ways, in this order:
  - **Scratch**, on top: sessions started with **⌘⇧N** (or the dashed button at the bottom of the sidebar), each in a new empty folder of its own that Calm keeps out of sight (under `~/.local/share/calm/scratch`, left out of Time Machine backups). They're short-lived: a row's **×** closes one when you're done. Closing one whose folder is empty removes the folder; one that made files asks: **Move to Trash**, **Keep as Project…** (the folder moves where you pick and becomes a project), or Cancel. Only ⌘⇧N makes scratch sessions: ⌘T or a split from one opens a normal session in your home folder.
  - **Projects** you made (+ New Project or **⌘O**, dropping a folder on the sidebar, or `calm open <folder>`): each opens with a session in it. Each gets a small pixel mark made from its name (renaming a project changes its mark); clicking the mark, a small easter egg, swaps it for another at random, which it keeps. A session started in a project stays in it, even when its shell `cd`s elsewhere; ⌘T and splits from it stay there too. Right-click a session: **Move to Project** (any session), **Let It Follow Its Folder** (a project session goes back to grouping by folder). A project's **⋯** (on hover) or right-click: **Remove Project** undoes it: its sessions stay open and group by their folders again, and nothing on disk changes.
  - **Folders**, for every other session: grouped by the git repository's root, or by the folder outside a repository, and moving when the shell `cd`s. A folder group holds only its own repository or folder, so one for your home folder doesn't swallow everything under it; groups appear and disappear on their own. A session whose folder is inside a project you made joins that project while it's there. A group's **⋯** (on hover) or right-click: **Make Project** keeps it and its sessions; its **+** starts a session there.
- **At launch**, Calm starts where you left off. The very first launch shows a welcome page (New Session ⌘T, New Scratch Session ⌘⇧N, New Project… ⌘O, and the agents Calm works with: Claude Code, Codex, OpenCode, pi and omp, with a way to set them up); with nothing open later, the same quiet page says so. It fills the whole window, with no sidebar until a session opens. Calm never opens a session nobody asked for.
- The sidebar's footer starts things, one row each: **New Session ⌘T**, **New Scratch Session ⌘⇧N**, **New Project… ⌘O**.
- Each agent session is a **session card** (Claude Code today; other agents' transcripts follow) showing: the session name, its state and current step, progress when the agent keeps a todo list, a two-line recap of the latest agent message, and the worktree name with its diff size when the session runs in a git worktree. The card shows the agent's own logo, which moves while the agent works; working, needs you and done each tint the card (soft blue, amber, sage until you move on from it), and an idle card recedes into a shorter card (name and a one-line recap). Plain shells are one compact line.
- Projects can be collapsed to one line with a short summary (for example "2 sessions · 1 done").
- The folder comes from the shell itself (Ghostty's shell integration for zsh, fish and elvish, also inside persistent sessions); for other shells Calm reads it from the shell process every couple of seconds.

**Settings:** 1 — auto-grouping on/off (default on): `auto-grouping = false` in `~/.config/calm/config.toml` (Settings → General), re-read by Reload Configuration (⌘⇧,). Off, sessions stay in the group they started in.

## F3 — Persistent sessions 🚧

- Quitting Calm detaches shells instead of killing them. Relaunching reattaches, with scrollback and running processes intact.
- **Restart Calm** (Calm menu, no shortcut) quits and opens Calm again once the old one has fully exited, so every session comes back as after any relaunch, agents still running. It opens the app from the same place, so a version installed meanwhile (`install.sh`) is the one that starts. When shells aren't being kept alive (zmx missing or failing) and something is running, it asks first, as Quit does.
- Projects, sessions and split layouts are restored.
- Closing a session ends its shell (⌘⇧T opens a new one in its place; F12). Shells Calm no longer knows about (for example after a crash) are ended at the next launch; other apps' sessions are never touched.
- Each session can show a one-line attach command so it can be reached from another device over SSH.

**Settings:** none.

## F4 — Agent detection 🚧

- Detects when a session is running **Claude Code, Codex, OpenCode, pi or omp** in the foreground, within a couple of seconds of it starting or exiting, including sessions that aren't on screen.
- Shows the agent's icon on the session and uses the agent's own session title when it sets one.
- Drops the status glyph an agent puts at the start of the terminal title (Claude Code's ✳ and turning ◐◓◑◒, braille spinner dots): the card already shows the state, and a turning glyph would make the title flicker.
- Links the session to the agent's transcript on disk when possible (used by F6, F7 and F12).

**Settings:** none.

## F5 — Agent status and attention 🚧

- Each agent session has a state: **working**, **needs you**, **done**, **failed**, or **idle**.
- State comes from each agent's hook or notification system reporting to Calm, with terminal signals (bell, progress reports, desktop notification sequences) as a fallback. The fallback alone already works for Claude Code, Codex and omp, with no setup.
- A Claude Code turn that ends with background work still running (a shell, subagent or monitor) stays **working**: Claude picks up again on its own when that work finishes.
- Plain shells get a quiet mark too: a command that ran for 10 seconds or more shows **done** or **failed** until the session is visited.
- State appears in the sidebar as a quiet indicator. Only **needs you** escalates:
  1. The session's row gets a soft highlight.
  2. If the user is not looking at that session, a macOS notification is delivered **at the next natural pause** (not while the user is typing in another pane).
- Clicking the notification jumps to the session. **⌘⇧A** jumps to the session that has waited longest.
- **done** and **failed** never interrupt; they show in the sidebar until the session is visited.
- A **needs you** is never dropped: if delivery is deferred, it waits, and it stays visible in the sidebar until handled.

- With Claude Code, Calm's hooks are on by default inside Calm (a plugin Claude loads only in Calm's shells; nothing is written to Claude's settings), so *needs you* arrives the moment Claude asks, with what it asks.

- **Calm → Agents…** (Settings → Agents; the welcome page links to it) lists the installed agents and how each connects: Claude Code inside Calm; Codex and omp through their own notifications; pi through a small extension Calm adds only when you click **Connect** (and removes with **Disconnect**); OpenCode with a hint, since its background service can't be tied to a terminal yet.

**Settings:** 2, in Settings → Agents — which states notify (default: only *needs you*; or also *done* and *failed*); notification sound on/off (default off). They're stored in config.toml as `notify` and `sound` under `[agents]`. In the config file only: `claude-code-hooks = false` under `[agents]`.

## F6 — Arrival card ✅

- When the user switches into an agent session while the sidebar is hidden, and something happened there since they last left it, a small strip at the top of the pane shows:
  - the session title;
  - its state;
  - the last thing the agent said or asked, in one or two lines;
  - how long ago that was.
- It uses titles and messages the agent already wrote. Nothing is generated.
- It fades as soon as the user types or after a few seconds (five), and can be recalled with **⌘⇧I**. Clicking it dismisses it.
- With the sidebar showing it stays away: the session's card there already shows the same title, state and recap. Switching back and forth between sessions with nothing new doesn't show it either.

**Settings:** none.

## F7 — Search all sessions 🚧

- Opened with **⌘K**, or the **Search sessions** field at the top of the sidebar.
- **⌘K** opens a search box over every past and present session, across all agents.
- Results are sessions, not lines: agent, project, title, last active time and the matching snippet.
- **Enter** jumps to the session if it is open; otherwise it offers to resume it in its project folder.
- History outlives the agents' cleanup: a conversation stays searchable after its agent deletes the transcript (Claude Code does after 30 days). Claude Code conversations deleted before Calm indexed them are found through the prompts in `~/.claude/history.jsonl`. These can't be resumed; Enter opens a new session in their folder.
- Searches what the user and agents wrote; skips tool output and file dumps.
- Works for English and Chinese text.
- Ranking: text relevance (BM25), then recency, title matches and the current project.
- Also available from the command line: `calm search <text>` (through the running app, or straight from the index when Calm isn't running).

**Settings:** none. Agents are detected automatically.

## F8 — Smart links 🚧

- **⌘-click** a URL to open it in the default browser.
- **⌘-click** a file path, including relative paths, resolved against the session's current folder.
- `path:line` and `path:line:column` open at that position.
- File paths open in Calm's viewer (F10) or in the user's editor at the line.

- A path that isn't there relative to the session's folder is tried against its project's folder (agents often print repository-relative paths); if it's nowhere, a small note says so.

**Settings:** 2 — editor (auto-detected: VS Code, Cursor, Trae, Windsurf, Zed, Sublime Text, IntelliJ IDEA, Xcode; overridable with `editor = "…"` in config.toml); where paths open (Calm's viewer or editor, default viewer: `open-paths = "editor"` to change it).

## F9 — Copy Cell ✅

- Copies the text of one cell of a table drawn with box characters (`│ ─ ┼` and similar), instead of whole rows.
- Triggered by **⌥-double-click** or right-click → **Copy Cell**.
- Wrapped lines inside the cell are joined, and padding is trimmed, giving one clean string.
- Falls back to normal word selection when the click is not inside a drawn table.
- Works with box-drawn tables (with or without rules between rows), markdown pipe tables, and Chinese text.

**Settings:** none.

## F10 — Files and viewer ✅

A quick, read-only look at the repository without leaving Calm.

- **File tree:** a column on the left, right of the session sidebar, showing the focused session's project. Hides files ignored by git and marks changed files. Toggled with one shortcut (⌘\\).
  - The header names the project, with the branch and how many files changed (`main · 3 Δ`).
  - Folders come first, then files, each in natural order (`View2` before `View10`). A changed file carries a quiet letter: **M** modified, **A** added, **D** deleted (in the failure tone), **R** renamed, **U** untracked. A folder holding changes carries a small dot.
  - It follows the focused session: switching to a session in another project shows that project. While shown it re-reads every 5 seconds, so an agent's edits appear as they happen.
  - A folder that isn't a git repository is listed directly, skipping hidden folders and build output (`node_modules`, `build`, `DerivedData`, `Pods`, `target`, `dist`), up to 5,000 files.
  - Clicking a file opens it in the viewer; the file being viewed is highlighted in the tree.
  - A ⌘\\ keybinding in the user's own Ghostty config wins over Calm's, and so does a global shortcut such as 1Password's autofill (⌘\\ by default; see UIUX.md → Keyboard); Toggle Files stays in the View menu.
- **Viewer:** opening a viewable file (Markdown, HTML, PDF, images; code with syntax highlighting) **covers the main area** where the session was. **Esc** returns to the session exactly as it was; the session keeps running underneath.
- Files open from the tree, from ⌘-click (F8), or from `calm open <file>` (also `file:line`, which highlights that line).
- One action opens the file in the editor at the current line.
- No editing, creating, renaming or diffing.

**Settings:** none.

## F11 — Themes 🚧

- A theme styles the **whole window**: terminal colors, sidebar, cards, panels, files column, viewer and accent. Glass or solid and the layout are window options beside it (Settings → Appearance).
- A curated set of twelve themes, six light and dark pairs, all soft (low contrast and low saturation): **Calm** (the default), **Sage**, **Dune**, **Harbor**, **Heather** and **Ink**.
- A picker in Settings → Appearance (⌘,) shows a small preview of each theme in the current appearance, under a live miniature of the whole window; one click applies it and writes `theme = "Sage"` to `config.toml`. When the user's Ghostty config sets its own colors, a **Your Ghostty** choice comes last, set apart; picking it removes Calm's choice so those colors apply again.
- Themes follow the system light/dark appearance.
- The default gives way to a theme or colors in the user's Ghostty config, so any Ghostty theme can still be used; the chrome then derives its colors from it. A theme picked in Calm wins over the Ghostty config.
- Your own themes go in `~/.config/calm/themes/` as small TOML files (DESIGNS.md → Themes).
- **Window options**, under the picker in Settings → Appearance:
  - **Background:** solid, or glass (the system's blur behind a translucent terminal and sidebar; panels and the viewer stay solid).
  - **Layout:** edge to edge, or card (the terminal floats as a rounded card on the sidebar's color).
  - **Motion:** full, reduced or off; the system's Reduce Motion always wins.
  - In config.toml: `[window] background = "glass"`, `layout = "card"`, and `motion`. Choosing a default removes the key.

**Settings:** the picker itself.

## F12 — Session actions ✅

- **Where:** right-click a session's card, or the ⋯ button at the right of the title strip above the terminal (for the session you're in): one menu in both places. Rename from the title brings a hidden sidebar back, since the name is edited on its card.
- **Rename** a session: Rename… edits the name in place (return keeps it, esc cancels, an empty name gives the session back its own title). The name wins over the shell's and the agent's titles, in the sidebar, the title strip above the terminal, switcher, arrival card and notifications, and survives relaunch.
- **Resume** an agent conversation: when the agent exits, the session remembers its conversation, and right-click → Resume <agent> Conversation continues it in the same shell. A conversation whose session was closed is resumed from ⌘K search (F7), in its project folder.
- **Close** a session with ⌘W (or the row's ×). While an agent runs in it, or a process Ghostty can see, Calm asks first ("Claude Code is running in it. Closing the session ends it."). With Settings, search or a file open, ⌘W closes that instead of the session behind it. One ⌘W closes one session.
- **Reopen** the session closed last with **⌘⇧T** (Shell → Reopen Closed Session; greyed out until something has been closed), and again for the one before it, up to the last ten. The shell is a new one, since closing ended the old, but everything else comes back: its folder (the project's, or home, if that's gone), its name, its project if it stayed in one, and its place in the sidebar. If an agent was running in it, its conversation resumes with the agent's own command (the table below); one that had already exited isn't started again. Scratch sessions aren't reopened: closing removes their folder. Kept in memory, so a relaunch starts with nothing to reopen. A shell that exits by itself (`exit`, ⌃D) counts as closed.
- **Copy** from the session: Copy Session ID (the agent's own id for the conversation, while it runs or after it ended), Copy Resume Command (e.g. `claude --resume 'id'`), and Copy Folder Path, each with a quiet note by the pointer; Reveal in Finder shows the folder. A scratch session has no folder to copy or reveal. Each item shows only where there is something to give.
- **Fork** an agent conversation into a new split beside it or a new tab, in the same folder, while it runs or after it ended. The fork is a new conversation; the original stays as it was.
- Uses each agent's own commands:

  | Agent | Resume | Fork |
  |---|---|---|
  | Claude Code | `claude --resume <id>` | `claude --resume <id> --fork-session` |
  | Codex | `codex resume <id>` | `codex fork <id>` |
  | pi | `pi --session <file>` | `pi --fork <file>` |
  | omp | `omp --resume <id>` | `omp --fork <id>` |
  | OpenCode | not yet | not yet |

  An action shows only where the agent has the command.

**Settings:** none. The menu offers the destination.

## F13 — `calm` command-line tool 🚧

- `calm open <folder|file>` — open a project (and a new session in it), or a file in the viewer (`file:line` highlights that line). Starts Calm if it isn't running.
- `calm list` — list sessions: project, title, state and folder.
- `calm search <text>` — search sessions from any shell: when, agent, project and title, then the matching text.
- `calm status <state> [message]` — report agent state; this is the contract agents' hooks call. Safe in any terminal: outside Calm, or with Calm not running, it does nothing.
- `calm notify <message>` — show a notification for the current session.
- Talks to the running app over a local socket.

**Settings:** none.

## F14 — Settings 🚧

- ⌘, turns the whole window into Settings (UIUX.md → Settings screen); ⌘, again or esc goes back to the session exactly as it was. A list of sections stands where the sidebar was: **Appearance, Agents, General, Shortcuts**.
  - **Appearance:** a live miniature of the window, the theme picker and the window options (F11).
  - **Agents:** how each installed agent connects, with Connect/Disconnect where Calm must add a file, which states notify, and sound. When macOS blocks Calm's notifications it says so, with a button to System Settings. Calm → Agents… opens it.
  - **General:** the editor paths open in (automatic, or one of the editors installed), whether viewable files open in Calm or the editor, auto-grouping, and the config files: Calm's config.toml (with any line Calm couldn't read), the Ghostty config (with the font it sets) and the themes folder, each with Open.
  - **Shortcuts:** Calm's shortcuts; keys are changed in the Ghostty config (Open Ghostty Config), where a keybinding wins over Calm's.
- Going to any session leaves Settings. After a hand edit, Calm → Reload Configuration updates the page.
- Everything else lives in the config file, reachable through General → Calm settings → Open.
- Every change is saved to `config.toml` at once, keeping comments and unknown keys; choosing a default removes the key.

---

## Later, if needed

| Idea | Note |
|---|---|
| Changed-file diffs | Click an M/A file in the files column to see its read-only diff in the viewer; esc returns. Agent-neutral (Claude Code has its own diff panel, other agents may not). Small and informative. |
| Spotlight integration | Publish sessions to Spotlight; semantic indexing on macOS 27+ |
| Scrollback search across open sessions | Complements F7 |
| Paste history | Small and handy |
| Triggers on output patterns | Overlaps F5 |
| Keyboard copy mode | For long scrollback |

## Explicitly not planned

In-app browser, computer use, built-in AI chat, file editing, code review views, accounts, cloud sync, own mobile app.
