# Features

Precise behavior of every feature. Visual details live in [UIUX.md](UIUX.md), implementation in [DESIGNS.md](DESIGNS.md), order in [ROADMAP.md](ROADMAP.md).

Each feature lists the settings it adds. The budget is at most one or two per feature (see [GOALS.md](GOALS.md)).

Status: ✅ built and working as described · 🚧 built, with a known gap named in its section · 📝 planned, not built. (ROADMAP.md's marks say whether a milestone is proven in real use.)

---

## F1 — Terminal core 🚧

A fast, correct terminal on libghostty.

- Reads the user's Ghostty config (`~/.config/ghostty/config`) for fonts, keybindings and terminal behavior, so existing setups carry over. Settings for Calm alone go in `~/.config/calm/terminal.ghostty`, in the same format, read after it.
- Calm's own defaults change a few of Ghostty's keys: **⌘K** searches sessions (clear screen moves to ⌘⇧K), **⌘,** opens Settings, **⌘⇧T** reopens a closed session, and **⌘⌥ + an arrow** splits instead of moving focus. They load before the Ghostty config, so a keybinding of your own for any of these keys still wins.
- No tab bar: each ⌘T opens a session in the sidebar (F2). Splits, with keyboard navigation: **⌘⌥ + an arrow key** splits toward that side (left, right, up or down; ⌘D and ⌘⇧D still split right and down), ⌘[ and ⌘] move focus between splits, and ⌘⌃ + an arrow resizes one.
- Command palette (⌘P) listing every action with its shortcut.
- One text size for every session: ⌘+ and ⌘− (or the user's own font-size keybindings) resize all sessions and splits together, new ones start at that size, and it's kept across relaunches. ⌘0 goes back to the config's `font-size`.
- The window comes back the way you left it: its size and place, and also a window left filling the screen (Zoom or Fill from a double-click on the title strip, or a window manager's maximize). Filled again, it still goes back to its earlier size on the next double-click. A window left in full screen opens in full screen, and leaving it goes back to the window it was. Known gap: once in six test launches it came back filled but not in full screen, and the cause isn't known.
- Rectangle selection with ⌥-drag, inline images, true color, ligatures (all from libghostty).
- ⌘V pastes text as text and copied files as their escaped paths. An image with neither (a screenshot, a picture copied from a browser) is saved as a PNG in the temporary folder, and its path is pasted, so agents like Claude Code attach it (`[Image #1]`).

**Settings:** none beyond the Ghostty config.

## F2 — Projects and auto-grouping 🚧

- The sidebar groups sessions three ways, in this order:
  - **Scratch**, on top: sessions started with **⌘⇧N** (or **New Scratch Session** in the sidebar's footer), each in a new empty folder of its own that Calm keeps out of sight (under `~/.local/share/calm/scratch`, left out of Time Machine backups). They're short-lived: close one with ⌘W (or Close Session in its right-click menu) when you're done. Closing one whose folder is empty removes the folder; one that made files asks: **Move to Trash**, **Keep as Project…** (the folder moves where you pick and becomes a project), or Cancel. A scratch session's menu offers Keep as Project… at any time. Only ⌘⇧N makes scratch sessions: ⌘T or a split from one opens a normal session in your home folder.
  - **Projects** you made (**New Project…** or **⌘O**, dropping a folder on the sidebar, or `calm open <folder>`): each opens with a session in it. Each gets a small pixel mark made from its name (renaming a project changes its mark); clicking the mark, a small easter egg, swaps it for another at random, which it keeps. A session started in a project stays in it, even when its shell `cd`s elsewhere; ⌘T and splits from it stay there too. Right-click a session: **Move to Project** (any session but a scratch one), **Let It Follow Its Folder** (a project session goes back to grouping by folder). A project's **⋯** (on hover) or right-click: **Remove Project** undoes it: its sessions stay open and group by their folders again, and nothing on disk changes.
  - **Folders**, for every other session: grouped by the git repository's root, or by the folder outside a repository, and moving when the shell `cd`s. A folder group holds only its own repository or folder, so one for your home folder doesn't swallow everything under it; groups appear and disappear on their own. A session whose folder is inside a project you made joins that project while it's there. A group's **⋯** (on hover) or right-click: **Make Project** keeps it and its sessions; its **+** starts a session there.
- **At launch**, Calm starts where you left off. With nothing open (later launches, or after you close the last session) the window shows a page of its own, with no sidebar until a session opens, so nothing is out of reach behind one that isn't there. It has Calm's mark (animated: it arrives, then waits, its cursor breathing; a click runs one lap), a **search field** over past sessions and your projects together, **Recent sessions** from every agent beside your **Projects**, and one line of the three ways to start: **⌘T New session · ⌘⇧N Scratch · ⌘O New project…**, each a button. Typing filters both lists (a session by what was said in it, a project by its name or folder); ↑ ↓ move through the rows, ← → change list, ↵ opens (goes to a session that's open, resumes one that isn't, starts a session in a project), Esc clears; **⌘K** puts the caret in the field. With no past sessions the projects fill the page, and with no projects the sessions do. With no project made, the page is a welcome instead when it is the very first launch, and when there is no past session either: "Welcome to Calm" (first launch only) and the three ways to start as rows (Start a session ⌘T, Try a scratch session ⌘⇧N, Open a project ⌘O). Make a project and the lists come back, so a project is never out of reach. From there, **⌘T** opens a shell in your home folder. Calm never opens a session nobody asked for.
- The sidebar's footer starts things, one row each: **New Session ⌘T**, **New Scratch Session ⌘⇧N**, **New Project… ⌘O**. ⌘T opens a shell in the folder of the session you're in, or your home folder when none is selected.
- **⌘⌃S** hides the sidebar and brings it back; while it's hidden, it peeks in over the terminal when the pointer reaches the window's left edge. **⌘1…9** go to a session by its place in the sidebar and **⌘⇧[** / **⌘⇧]** to the one above or below; holding **⌃** and pressing **Tab** cycles sessions in sidebar order over small live previews (⌃⇧Tab goes up).
- Each agent session is a **session card** showing: the session name and the time since its last activity, its state and current step, progress when the agent keeps a todo list, a two-line recap of the latest agent message (plain text: its Markdown headings, code blocks and bold are taken out), and the worktree name when the session runs in a git worktree (the one its agent is in: Claude Code can move into a worktree while the shell that started it stays in the main checkout; the header above the terminal shows the same name in a small pill beside the session's name). The card shows the agent's own logo, which moves while the agent works; working, needs you and done each tint the card (soft blue, amber, sage until you move on from it), and an idle card recedes into a shorter card (name and a one-line recap). Plain shells are one compact line.
- The card's content is read from the agent's own conversation file. What each agent gives it:

  | Agent | Recap | Title | Step and progress | Esc noticed |
  |---|---|---|---|---|
  | Claude Code | yes | its own | from its todos | yes |
  | Codex | yes | none (Codex keeps none in its files) | none | yes |
  | OpenCode | yes | its session title, once named | none | yes |
  | pi | yes | its session name | none | yes |

  Calm finds the conversation from the agent's process (from its hooks or extension where it has them). When two conversations of one agent could be the one in a folder and Calm can't tell which, the card shows no recap rather than another conversation's. Known gap: after `/new` in OpenCode, the card stays on the conversation it found first.
- Projects can be collapsed to one line with a short summary (for example "2 sessions · 1 done").
- The folder comes from the shell itself (Ghostty's shell integration for zsh, fish and elvish, also inside persistent sessions); for other shells Calm reads it from the shell process every couple of seconds.

**Settings:** 1 — auto-grouping on/off (default on): `auto-grouping = false` in `~/.config/calm/config.toml` (Settings → General), re-read by Reload Configuration (⌘⇧,). Off, sessions stay in the group they started in.

## F3 — Persistent sessions ✅

- Quitting Calm detaches shells instead of killing them. Relaunching reattaches, with scrollback and running processes intact.
- **Restart Calm** (Calm menu, no shortcut) quits and opens Calm again once the old one has fully exited, so every session comes back as after any relaunch, agents still running. It opens the app from the same place, so a version installed meanwhile (`install.sh`) is the one that starts. When shells aren't being kept alive (zmx missing or failing) and something is running, it asks first, as Quit does.
- Projects, sessions and split layouts are restored.
- The sidebar comes back as it was left: each agent's mark, state and recap, and how long it has been working. Before the window opens Calm checks every saved agent against the running one (Claude Code tells what it is doing in its own status file), so a session that was working still shows working, one that has since finished shows idle, and one whose agent has ended has no mark. If that check takes more than a moment, the rows show a quiet "Restoring sessions…" state instead of a state, and settle together.
- Closing a session ends its shell (⌘⇧T opens a new one in its place; F12). Shells Calm no longer knows about (for example after a crash) are ended at the next launch; other apps' sessions are never touched.

**Settings:** none.

## F4 — Agent detection ✅

- Detects when a session is running **Claude Code, Codex, OpenCode or pi** in the foreground, within a couple of seconds of it starting or exiting, including sessions that aren't on screen.
- Shows the agent's icon on the session and uses the agent's own session title when it sets one.
- Drops the status glyph an agent puts at the start of the terminal title (Claude Code's ✳ and turning ◐◓◑◒, braille spinner dots): the card already shows the state, and a turning glyph would make the title flicker.
- Links the session to the agent's transcript on disk when possible (used by F6, F7 and F12).

**Settings:** none.

## F5 — Agent status and attention ✅

- Each agent session has a state: **working**, **needs you**, **done**, **failed**, or **idle**.
- State comes from each agent's hook or notification system reporting to Calm, with terminal signals (bell, progress reports, desktop notification sequences) as a fallback. The fallback alone already works for Claude Code and Codex, with no setup.
- Codex and OpenCode have no hook to say they are working (their notifications only tell a finished turn or an ask, and only while their terminal isn't focused), so Calm reads it from their own conversation files: a turn that has started and not ended is **working**, and one that ended is **done** (or **failed**, for OpenCode). The card works and settles within a couple of seconds of the agent. This is a guess, so an agent's own hook always outranks it, and it never replaces a pending **needs you**.
- A Claude Code turn that ends with one of Claude's own background agents still running stays **working**: Claude picks up again on its own when the agent finishes.
- Background *shells* don't hold it: a dev server or a monitor never ends and nothing would wake Claude, so the turn is **done** (the next move is yours), and the card adds "· 2 shells running" until you move on from it (2026-09-29, the author's call). Only tasks still running or pending count; a kind of task Calm doesn't know counts as a shell.
- Plain shells get a quiet mark too: a command that ran for 10 seconds or more shows **done** or **failed** until you move on from it.
- State appears in the sidebar as a quiet indicator. Only **needs you** escalates:
  1. The session's row gets a soft highlight.
  2. If the user is not looking at that session, a macOS notification is delivered **at the next natural pause** (not while the user is typing in another pane).
- The notification reads like a note: a mark for the state and the session's name (✋ needs you, ✅ done, ⚠️ failed), then one or two lines of what the agent said, cleaned of Markdown. It doesn't name the project or the agent (UIUX.md → Notifications).
- Clicking the notification jumps to the session. **⌘⇧A** jumps to the session that has waited longest.
- **done** and **failed** notify only if you opt in (Settings → Agents). They show in the sidebar until you've been to the session and moved on: arriving keeps them while you read, and going to another session, or leaving Calm, settles them to idle.
- A **needs you** is never dropped: if delivery is deferred, it waits, and it stays visible in the sidebar until handled.
- The Dock icon shows the whole app's state:
  - **running:** a quiet chase around Calm's mark while any session is working;
  - **done:** the ring closed in sage;
  - **failed:** the ring dimmed to grey with a red cell.

  Done and failed last until you move on from the session. The icon never badges or bounces (UIUX.md → App icon).

- With Claude Code, Calm's hooks are on by default inside Calm (a plugin Claude loads only in Calm's shells; nothing is written to Claude's settings), so *needs you* arrives the moment Claude asks, with what it asks.

- **Calm → Agents…** (Settings → Agents) lists the installed agents and how each connects: Claude Code inside Calm; Codex through its own notifications; pi through a small extension Calm adds only when you click **Connect** (and removes with **Disconnect**; it also tells Calm which conversation it is, and Calm keeps its own file current when it updates); OpenCode through its own attention notifications, which are off until `attention.notifications` is true in `~/.config/opencode/cli.json`: its card offers **Set Up…**, which says so, until it is on, and then reads Connected (there is no plugin, since its background service can't be tied to a terminal yet).

**Settings:** 3, one over the budget. Two in Settings → Agents: which states notify (default: only *needs you*; or also *done* and *failed*) and notification sound on/off (default off), stored in config.toml as `notify` and `sound` under `[agents]`. One in the config file only: `claude-code-hooks = false` under `[agents]` turns Calm's Claude Code hooks off.

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

- **⌘K**, or the **Search sessions** field at the top of the sidebar, opens a search box over every past and present session of Claude Code, Codex and pi. Known gap: OpenCode's history isn't searchable yet.
- Results are sessions, not lines: agent, project, title, last active time and the matching snippet.
- **Enter** jumps to the session if it is open; otherwise it resumes the conversation in a new session in its folder (home if the folder is gone).
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
- A path the terminal ran on into the words after it ("~/dev/apps and then") opens as the path, and so does one that ends a sentence ("open notes/index.html."): the closing full stop, comma or `?` is not part of the name.
- **At rest**, every link on screen that opens (a URL, or a file or folder that's there) has a faint dotted line under it, including one the terminal wrapped onto the next row. Rows that change lose their marks at once and get them back when the text holds still, so marks never trail scrolling or streaming output. Programs that take the mouse (vim, htop, an agent's full-screen view) get none: their screens are redrawn too often for marks to hold still. Known gap: a link a program sets behind other text (OSC 8), and a path a program broke across lines itself, get no mark.
- **Holding ⌘** over a link shows a small tag just under it (above it at the pane's bottom): the file's name and line, its folder, and what a click does ("Open in viewer", "Open in Cursor", "Open in browser", "Open in Finder", or "Not found" before you click). An image's tag shows its thumbnail. The tag goes away when ⌘ or the pointer leaves the link, or on typing, clicking or scrolling.
- **In programs that take the mouse** (vim, htop, Claude Code's full-screen view) a link under ⌘ is still Calm's: the same underline and tag on hover, and a ⌘-click opens it without the program seeing the click (a program can't see ⌘ anyway). Away from a link, ⌘-click reaches the program as before.

**Settings:** 2 — editor (auto-detected: VS Code, Cursor, Trae, Windsurf, Zed, Sublime Text, IntelliJ IDEA, Xcode; or any application, chosen in Settings → General with Choose Application…, or `editor = "…"` in config.toml, a name or an `.app` path; an application that isn't one of those opens the file but not at the line); where paths open (Calm's viewer or editor, default viewer: `open-paths = "editor"` to change it).

## F9 — Copy Cell ✅

- Copies the text of one cell of a table drawn with box characters (`│ ─ ┼` and similar), instead of whole rows.
- Triggered by **⌥-double-click** or right-click → **Copy Cell** (the menu shows only where the program doesn't take the mouse).
- Wrapped lines inside the cell are joined, and padding is trimmed, giving one clean string.
- Falls back to normal word selection when the click is not inside a drawn table.
- Works with box-drawn tables (with or without rules between rows), markdown pipe tables, and Chinese text.

**Settings:** none.

## F10 — Files and viewer ✅

A quick, read-only look at the repository without leaving Calm.

- **Files column:** a column on the left, right of the session sidebar, showing the focused session's project: what changed first, then the whole tree. Hides files ignored by git. Toggled with one shortcut (⌘\\).
  - The header names the project, with its branch and every line the changes add and remove (`calm  main  +128 −41`). The branch shows only when it fits whole.
  - **Changes** lists every changed file (what `git status` shows, staged or not), in path order: its letter (**M** modified, **A** added, **D** deleted, **R** renamed, **U** untracked), its name, the folder it's in when there's room, and the lines it adds and removes against the last commit (`+64 −31`; an untracked file's lines all count as added; binary files have none). The full path is the row's tooltip. With nothing changed, the section isn't there.
  - **Files** is the tree: folders first, then files, each in natural order (`View2` before `View10`). Folders open and close with a click; they all close again for another project. A changed file is brighter and carries its letter; a folder holding changes carries a small dot; dotfiles are quieter.
  - It follows the focused session: switching to a session in another project shows that project. While shown it re-reads every 5 seconds, so an agent's edits appear as they happen.
  - A folder that isn't a git repository is listed directly, skipping hidden folders and build output (`node_modules`, `build`, `DerivedData`, `Pods`, `target`, `dist`), up to 5,000 files. It has no branch and no Changes.
  - **Desktop, Documents and Downloads** in the home folder are listed as closed folders and read when you open one, so macOS asks about a folder when you look inside it, not all three the moment the column opens. A project inside one of them is read whole.
  - Clicking a file opens it in the viewer; the file being viewed is highlighted in Changes and in the tree.
  - A ⌘\\ keybinding in the user's own Ghostty config wins over Calm's, and so does a global shortcut such as 1Password's autofill (⌘\\ by default; see UIUX.md → Keyboard); Toggle Files stays in the View menu.
- **Viewer:** opening a viewable file (Markdown, HTML, PDF, images; code with syntax highlighting) **covers the main area** where the session was. **Esc** returns to the session exactly as it was; the session keeps running underneath. The viewer stays on the main area as the sidebar and files column open and close, and going to another session (a click, ⌘1…9, ⌃Tab, search, a new session) closes it.
- Files open from the tree, from ⌘-click (F8), or from `calm open <file>` (also `file:line`, which highlights that line).
- **Open in Editor** opens the file in the editor, at the line it was opened at.
- No editing, creating, renaming or diffing.

**Settings:** none.

## F11 — Themes ✅

- A theme styles the **whole window**: terminal colors, sidebar, cards, panels, files column, viewer and accent. Glass or solid and the layout are window options beside it (Settings → Appearance).
- A curated set of five themes, each in light and dark, all soft (low contrast and low saturation), and each its own direction rather than a tint of another: **Calm** (the default: a neutral charcoal, neither black nor white), **Ink** (the same neutral, near-black), **Dusk** (deep blue with cream text), **Forest** (a lifted green-gray) and **Plum** (a dim violet-gray).
- A picker in Settings → Appearance (⌘,) shows a small preview of each theme in the current appearance, under a live miniature of the whole window; one click applies it and writes `theme = "Ink"` to `config.toml`. When the user's Ghostty config sets its own colors, a **Your Ghostty** choice comes last, set apart; picking it removes Calm's choice so those colors apply again.
- Themes follow the system light/dark appearance.
- The default gives way to a theme or colors in the user's Ghostty config, so any Ghostty theme can still be used; the chrome then derives its colors from it. A theme picked in Calm wins over the Ghostty config.
- Your own themes go in `~/.config/calm/themes/` as small TOML files (DESIGNS.md → Themes).
- **Window options**, under the picker in Settings → Appearance:
  - **Interface size:** Default, Large, Larger or Largest, shown as chips of Calm's sidebar growing beside a terminal that doesn't; everything Calm draws around the terminal grows together (UIUX.md → Accessibility). The terminal's own text stays the Ghostty font's size.
  - **Background:** solid, or glass (the system's blur behind a translucent terminal and sidebar; panels and the viewer stay solid).
  - **Layout:** edge to edge, or card (the terminal floats as a rounded card on the sidebar's color).
  - **Motion:** full, reduced or off; the system's Reduce Motion always wins. Full motion includes the terminal's own: the cursor glide, and smooth scrolling (scrollback and programs' scrolling move by pixels, so an agent's streaming answer flows instead of jumping; UIUX.md → Motion). `smooth-scroll = false` in `~/.config/calm/terminal.ghostty` turns just the scrolling off.

**Settings:** 5, over the budget of one or two, all in Settings → Appearance and saved to config.toml: `theme`, `ui-size = "larger"`, `background = "glass"` and `layout = "card"` under `[window]`, and `motion = "reduced"`. Choosing a default removes its key, except the theme (F14).

## F12 — Session actions 🚧

- **Where:** right-click a session's card, or the ⋯ button at the right of the title strip above the terminal (for the session you're in): one menu in both places. Rename from the title brings a hidden sidebar back, since the name is edited on its card.
- **Rename** a session: Rename… edits the name in place (return keeps it, esc cancels, an empty name gives the session back its own title). The name wins over the shell's and the agent's titles, in the sidebar, the title strip above the terminal, switcher, arrival card and notifications, and survives relaunch.
- **Resume** an agent conversation: when the agent exits, the session remembers its conversation, and right-click → Resume <agent> Conversation continues it in the same shell. A conversation whose session was closed is resumed from ⌘K search (F7), in its folder.
- **Close** a session with ⌘W (or Close Session in its right-click menu). While an agent runs in it, or a process Ghostty can see, Calm asks first ("Claude Code is running in it. Closing the session ends it."). With Settings, search or a file open, ⌘W closes that instead of the session behind it. One ⌘W closes one session. Closing the one you're in doesn't take you to another: the sidebar stays, the main area is left empty, and you choose (a click, ⌘1…9, ⌃Tab) when you're ready. Closing any other session leaves you where you are, and closing one pane of a split leaves its sibling on screen.
- **Reopen** the session closed last with **⌘⇧T** (Shell → Reopen Closed Session; greyed out until something has been closed), and again for the one before it, up to the last ten. The shell is a new one, since closing ended the old, but everything else comes back: its folder (the project's, or home, if that's gone), its name, its project if it stayed in one, and its place in the sidebar. If an agent was running in it, its conversation resumes with the agent's own command (the table below); one that had already exited isn't started again. Scratch sessions aren't reopened: closing removes their folder. Kept in memory, so a relaunch starts with nothing to reopen. A shell that exits by itself (`exit`, ⌃D) counts as closed.
- **Copy** from the session: Copy Session ID (the agent's own id for the conversation, while it runs or after it ended), Copy Resume Command (e.g. `claude --resume 'id'`), and Copy Folder Path, each with a quiet note by the pointer; Reveal in Finder shows the folder. A scratch session has no folder to copy or reveal. Each item shows only where there is something to give.
- **Fork** an agent conversation into a new split beside it or a new tab (a session of its own), in the same folder, while it runs or after it ended. The fork is a new conversation; the original stays as it was.
- Uses each agent's own commands:

  | Agent | Resume | Fork |
  |---|---|---|
  | Claude Code | `claude --resume <id>` | `claude --resume <id> --fork-session` |
  | Codex | `codex resume <id>` | `codex fork <id>` |
  | pi | `pi --session <file>` | `pi --fork <file>` |
  | OpenCode | not yet | not yet |

  An action shows only where the agent has the command. Known gap: OpenCode conversations can't be resumed or forked yet.

**Settings:** none. The menu offers the destination.

## F13 — `calm` command-line tool ✅

- `calm open <folder|file>` — open a project (and a new session in it), or a file in the viewer (`file:line` highlights that line). With no argument, the current folder.
- `calm list` — list sessions: project, title, state, agent and folder.
- `calm search <text>` — search sessions from any shell: when, agent, project and title, then the matching text.
- `calm status <state> [message]` — report agent state; this is the contract any agent's hooks can call. `--agent <name>`, `--transcript <file>` and `--agent-session <id>` say which agent and which of its conversations this is, for agents that can't send a hook payload (pi's extension does). Safe in any terminal: outside Calm, or with Calm not running, it does nothing.
- `calm hook <agent>` — read an agent's hook payload on stdin and report its state; Calm's Claude Code plugin runs `calm hook claude-code`. Safe in any terminal, like `status`.
- `calm notify <message>` — show a notification for the current session.
- Talks to the running app over a local socket. `open` and `list` start Calm if it isn't running.

**Settings:** none.

## F14 — Settings ✅

- ⌘, turns the whole window into Settings (UIUX.md → Settings screen); ⌘, again or esc goes back to the session exactly as it was. A list of sections stands where the sidebar was: **Appearance, Agents, General, Shortcuts**.
  - **Appearance:** a live miniature of the window, the theme picker and the window options (F11).
  - **Agents:** a card per installed agent with how it connects and what it's doing in Calm now (its sessions, working or needing you), Connect/Disconnect where Calm must add a file; then which states notify, and sound. When macOS blocks Calm's notifications it says so, with a button to System Settings. Calm → Agents… opens it.
  - **General:** the editor paths open in (automatic, one of the editors installed, or any application chosen with Choose Application…), whether viewable files open in Calm or the editor, auto-grouping, and the config files: Calm's config.toml (with any line Calm couldn't read), the Ghostty config (with the font it sets) and the themes folder, each with Open.
  - **Shortcuts:** Calm's shortcuts; keys are changed in the Ghostty config (Open Ghostty Config), where a keybinding wins over Calm's.
- Going to any session leaves Settings. After a hand edit, Calm → Reload Configuration updates the page.
- Everything else lives in the config file, reachable through General → Calm settings → Open.
- Every change is saved to `config.toml` at once, keeping comments and unknown keys. Choosing a default removes its key, except the theme: picking Calm writes `theme = "Calm"`, so it wins over colors in the user's Ghostty config.

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
| Copy attach command | A one-line `ssh … zmx attach …` to reach a session from another device; fits PHILOSOPHY's phone-over-SSH rule |

## Explicitly not planned

In-app browser, computer use, built-in AI chat, file editing, code review views, accounts, cloud sync, own mobile app, a drop-down quick terminal.
