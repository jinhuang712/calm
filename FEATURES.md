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
- Rectangle selection with ⌥-drag, inline images, true color, ligatures (all from libghostty).
- A drop-down quick terminal on a global hotkey.

**Settings:** none beyond the Ghostty config.

## F2 — Projects and auto-grouping 🚧

- A **project** is a folder. The sidebar lists projects, each with its sessions underneath.
- Each agent session is a **session card** (Claude Code today; other agents' transcripts follow) showing: the session name, its state and current step, progress when the agent keeps a todo list, a two-line recap of the latest agent message, and the worktree name with its diff size when the session runs in a git worktree. Plain shells are one compact line.
- Projects can be collapsed to one line with a short summary (for example "2 sessions · 1 done").
- A session files itself under the project whose folder contains its current working directory, choosing the most specific match. When the shell `cd`s into another project, the session moves there. The folder comes from the shell itself (Ghostty's shell integration for zsh, fish and elvish, also inside persistent sessions); for other shells Calm reads it from the shell process every couple of seconds.
- If no project contains the folder, the session goes under an automatic project for its git repository root, or its folder if there is no repository.
- Users can pin a session to a project so it stops moving.
- Adding a project: **+ New Project**, dropping a folder on the sidebar, or `calm open <folder>`.

**Settings:** 1 — auto-grouping on/off (default on): `auto-grouping = false` in `~/.config/calm/config.toml`, re-read by Reload Configuration (⌘⇧,).

## F3 — Persistent sessions 🚧

- Quitting Calm detaches shells instead of killing them. Relaunching reattaches, with scrollback and running processes intact.
- Projects, sessions and split layouts are restored.
- Closing a session ends its shell. Shells Calm no longer knows about (for example after a crash) are ended at the next launch; other apps' sessions are never touched.
- Each session can show a one-line attach command so it can be reached from another device over SSH.

**Settings:** none.

## F4 — Agent detection 🚧

- Detects when a session is running **Claude Code, Codex, OpenCode, pi or omp** in the foreground, within a couple of seconds of it starting or exiting, including sessions that aren't on screen.
- Shows the agent's icon on the session and uses the agent's own session title when it sets one.
- Links the session to the agent's transcript on disk when possible (used by F6, F7 and F12).

**Settings:** none.

## F5 — Agent status and attention 🚧

- Each agent session has a state: **working**, **needs you**, **done**, **failed**, or **idle**.
- State comes from each agent's hook or notification system reporting to Calm, with terminal signals (bell, progress reports, desktop notification sequences) as a fallback. The fallback alone already works for Claude Code, Codex and omp, with no setup.
- Plain shells get a quiet mark too: a command that ran for 10 seconds or more shows **done** or **failed** until the session is visited.
- State appears in the sidebar as a quiet indicator. Only **needs you** escalates:
  1. The session's row gets a soft highlight.
  2. If the user is not looking at that session, a macOS notification is delivered **at the next natural pause** (not while the user is typing in another pane).
- Clicking the notification jumps to the session. **⌘⇧A** jumps to the session that has waited longest.
- **done** and **failed** never interrupt; they show in the sidebar until the session is visited.
- A **needs you** is never dropped: if delivery is deferred, it waits, and it stays visible in the sidebar until handled.

- With Claude Code, Calm's hooks are on by default inside Calm (a plugin Claude loads only in Calm's shells; nothing is written to Claude's settings), so *needs you* arrives the moment Claude asks, with what it asks.

- **Calm → Agents…** (also shown once at first launch) lists the installed agents and how each connects: Claude Code inside Calm; Codex and omp through their own notifications; pi through a small extension Calm adds only when you click **Connect** (and removes with **Disconnect**); OpenCode with a hint, since its background service can't be tied to a terminal yet.

**Settings:** 2, in the Agents panel — which states notify (default: only *needs you*; or also *done* and *failed*); notification sound on/off (default off). They're stored in config.toml as `notify` and `sound` under `[agents]`. In the config file only: `claude-code-hooks = false` under `[agents]`.

## F6 — Arrival card ✅

- When the user switches into an agent session, a small strip at the top of the pane shows:
  - the session title;
  - its state;
  - the last thing the agent said or asked, in one or two lines;
  - how long ago that was.
- It uses titles and messages the agent already wrote. Nothing is generated.
- It fades as soon as the user types or after a few seconds (five), and can be recalled with **⌘⇧I**. Clicking it dismisses it.

**Settings:** none.

## F7 — Search all sessions 🚧

- **⌘K** opens a search box over every past and present session, across all agents.
- Results are sessions, not lines: agent, project, title, last active time and the matching snippet.
- **Enter** jumps to the session if it is open; otherwise it offers to resume it in its project folder.
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

- **File tree:** a column on the left, right of the session sidebar, showing the focused session's project. Hides files ignored by git and marks changed files. Toggled with one shortcut (⌘⇧E).
  - The header names the project, with the branch and how many files changed (`main · 3 Δ`).
  - Folders come first, then files, each in natural order (`View2` before `View10`). A changed file carries a quiet letter: **M** modified, **A** added, **D** deleted (in the failure tone), **R** renamed, **U** untracked. A folder holding changes carries a small dot.
  - It follows the focused session: switching to a session in another project shows that project. While shown it re-reads every 5 seconds, so an agent's edits appear as they happen.
  - A folder that isn't a git repository is listed directly, skipping hidden folders and build output (`node_modules`, `build`, `DerivedData`, `Pods`, `target`, `dist`), up to 5,000 files.
  - Clicking a file opens it in the viewer; the file being viewed is highlighted in the tree.
  - A ⌘⇧E keybinding in the user's own Ghostty config wins over Calm's (see UIUX.md → Keyboard); Toggle Files stays in the View menu.
- **Viewer:** opening a viewable file (Markdown, HTML, PDF, images; code with syntax highlighting) **covers the main area** where the session was. **Esc** returns to the session exactly as it was; the session keeps running underneath.
- Files open from the tree, from ⌘-click (F8), or from `calm open <file>` (also `file:line`, which highlights that line).
- One action opens the file in the editor at the current line.
- No editing, creating, renaming or diffing.

**Settings:** none.

## F11 — Themes 🚧

- A theme styles the **whole window**: terminal colors, sidebar, cards, panels, files column, viewer and accent. Glass or solid and the layout are window options beside it (Settings → Appearance).
- A curated set of twelve themes, six light and dark pairs, all soft (low contrast and low saturation): **Calm** (the default), **Sage**, **Dune**, **Harbor**, **Heather** and **Ink**.
- A picker in Settings shows live previews; one click applies instantly. Until it lands, `theme = "Sage"` in `config.toml` picks one.
- Themes follow the system light/dark appearance.
- The default gives way to a theme or colors in the user's Ghostty config, so any Ghostty theme can still be used; the chrome then derives its colors from it. A theme picked in Calm wins over the Ghostty config.
- Your own themes go in `~/.config/calm/themes/` as small TOML files (DESIGNS.md → Themes).

**Settings:** the picker itself.

## F12 — Session actions 📝

- **Rename** a session.
- **Resume** a closed agent session in its project folder.
- **Fork** an agent conversation into a new split or tab, where the agent supports it.
- Uses each agent's own commands (for example Claude Code's resume and fork options).

**Settings:** none. The right-click menu offers the destination.

## F13 — `calm` command-line tool 🚧

- `calm open <folder|file>` — open a project (and a new session in it), or a file in the viewer (`file:line` highlights that line). Starts Calm if it isn't running.
- `calm list` — list sessions: project, title, state and folder.
- `calm search <text>` — search sessions from any shell: when, agent, project and title, then the matching text.
- `calm status <state> [message]` — report agent state; this is the contract agents' hooks call. Safe in any terminal: outside Calm, or with Calm not running, it does nothing.
- `calm notify <message>` — show a notification for the current session.
- Talks to the running app over a local socket.

**Settings:** none.

## F14 — Settings 📝

- Five sections: **Appearance, General, Agents, Keys, Advanced** (collapsed).
- Everything else lives in the config file, reachable through Advanced → Open Config File.

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
