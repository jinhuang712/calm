# Features

Precise behavior of every feature. Visual details live in [UIUX.md](UIUX.md), implementation in [DESIGNS.md](DESIGNS.md), order in [ROADMAP.md](ROADMAP.md).

Each feature lists the settings it adds. The budget is at most one or two per feature (see [GOALS.md](GOALS.md)).

Status: ✅ built and working as described · 🚧 built, with a known gap named in its section · 📝 planned, not built. (ROADMAP.md's marks say whether a milestone is proven in real use.)

---

## F1 — Terminal core 🚧

A fast, correct terminal on libghostty.

- Reads the user's Ghostty config (`~/.config/ghostty/config`) for fonts, keybindings and terminal behavior, so existing setups carry over. Settings for Calm alone go in `~/.config/calm/terminal.ghostty`, in the same format, read after it.
- Calm's own defaults change a few of Ghostty's keys: **⌘K** searches sessions (clear screen moves to ⌘⇧K), **⌘,** opens Settings, **⌘⇧T** reopens a closed session, **⌘Z** undoes the last edit of the line you're typing (a paste, a ⌘⌫; it sends Ctrl-_ to the shell or agent, so what it undoes is theirs to decide, and there is no redo), and **⌘⌥ + an arrow** splits instead of moving focus. They load before the Ghostty config, so a keybinding of your own for any of these keys still wins.
- No tab bar: each ⌘T opens a session in the sidebar (F2). Splits, with keyboard navigation: **⌘⌥ + an arrow key** splits toward that side (left, right, up or down; ⌘D and ⌘⇧D still split right and down), ⌘[ and ⌘] move focus between splits, and ⌘⌃ + an arrow resizes one. A session can be put into a split by dragging its card from the sidebar onto a pane (a dotted outline shows where it lands), and a pane can leave one without ending its session: the **split icon** in a pane's corner opens a menu (Take Out of Split, Unsplit All, Zoom Pane, Equalize Splits) and can be dragged onto the sidebar, and Shell → Take Pane Out of Split and Unsplit All do the same. The sessions shown together are lifted in the sidebar. In a split, the pane you're in is the bright one and the others recede (a dim of Calm's own, fixed at 0.6: it doesn't read Ghostty's `unfocused-split-opacity`, which only apps that draw that dim themselves honor).
- **Command palette (⌘P)** lists what Calm does that has no key of its own (decided 2026-09-30: a key everyone knows stays out, so it isn't a second menu bar). In this order:
  Every row is one-shot: choosing it runs it and closes the palette, with no second list, picker or submenu (what needs a target, like moving a session to a project, stays in the right-click menu). A row shows only where it applies. The rows, in the categories they are kept in:
  - **Agent conversation**, for the session in front: Fork Conversation into New Split / New Tab, Resume *Agent* Conversation (after the agent exited), Restart *Agent* (or Don't Restart *Agent* while one waits for the turn to end; F12), Copy Last Reply (the agent's newest message as it wrote it, Markdown and all, not the card's one-line recap; for Claude Code, Codex and pi, whose transcripts are files), Copy Session ID, Copy Resume Command, Open Transcript (the file, in the editor chosen in Settings); for every session: Restart All *Agent* Sessions, per agent running somewhere (not when it would only repeat the session in front's own Restart); and Mark All Done as Seen, which settles every finished session you haven't opened (not the one you're in, and not a failed one), while one is waiting;
  - **Session and layout:** Rename Session (edits in place on the card); Keep Scratch Session as Project… (a scratch session); Jump to Waiting Session ⌘⇧A (while one waits, shown with its key); Unsplit (in a split: every pane becomes a session of its own in the sidebar, nothing closes);
  - **View and navigation:** Show / Hide File Tree ⌘\ (the files column); Go to Welcome Page (chooses no session, so the main area shows what waits, or search; every session keeps running); Fold All Groups / Unfold All Groups (whichever applies);
  - **Folder:** Open Folder in Finder (shows what is in it, like `open .`; not for a scratch session), Copy Folder Path;
  - **Look:** Randomize Theme (a Calm theme other than the one in force, never the user's own Ghostty colors; a quiet note says which). The themes themselves, and sizes, stay in Settings;
  - **Calm:** Restart Calm, Agents Settings…, Dump Logs (writes a text file, `~/Library/Logs/Calm/calm-diagnostics-<time>.txt`, and opens Finder on it: Calm's version and settings, each session's state and agent, and this Calm's trace from the last 30 minutes; only ids, states and counts, never a folder, a title or a word anyone wrote);
  - **Terminal:** two of Ghostty's own entries, Reset Terminal and Toggle Mouse Reporting. The rest of its list is its windows, tabs and screen dumps (dozens of rows, even without the ones that have a key), so it's an allowlist (`TerminalConfig.paletteActions`).
  Left out because they have a key everyone knows, or a button on screen: new session and project, reopen closed, split, close, copy, paste, font size, clear screen, search, Settings, sidebar, New Scratch Session (the sidebar's footer shows it) and Show Arrival Card (⌘⇧I). The selected row says in one short line what it does, under its name ("Copy the agent's latest message, Markdown and all."). Typing finds a row by its letters in order in its name, or by the words of its description as typed (scattered letters would find almost any sentence); ↑ ↓ choose, ↵ runs, esc closes.
- One text size for every session: ⌘+ and ⌘− (or the user's own font-size keybindings) resize all sessions and splits together, new ones start at that size, and it's kept across relaunches. ⌘0 goes back to the config's `font-size`.
- The window comes back the way you left it: its size and place, and also a window left filling the screen (Zoom or Fill from a double-click on the title strip, or a window manager's maximize). Filled again, it still goes back to its earlier size on the next double-click. A window left in full screen opens in full screen, and leaving it goes back to the window it was. Known gap: once in six test launches it came back filled but not in full screen, and the cause isn't known.
- Input methods, System Dictation and voice input methods type into a pane like the keyboard does: what they commit goes to the program as typed keys, never as a paste.
- Rectangle selection with ⌥-drag, inline images, true color, ligatures (all from libghostty).
- ⌘V pastes text as text and copied files as their escaped paths. An image with neither (a screenshot, a picture copied from a browser) is saved as a PNG in the temporary folder, and its path is pasted, so agents like Claude Code attach it (`[Image #1]`).

**Settings:** none beyond the Ghostty config.

## F2 — Projects and auto-grouping 🚧

- The sidebar groups sessions three ways, in this order:
  - **Scratch**, on top: sessions started with **⌘⇧N** (or **New Scratch Session** in the sidebar's footer), each in a new empty folder of its own that Calm keeps out of sight (under `~/.local/share/calm/scratch`, left out of Time Machine backups). They're short-lived: close one with ⌘W (or Close Session in its right-click menu) when you're done. Closing one whose folder is empty removes the folder; one that made files asks: **Move to Trash**, **Keep as Project…** (the folder moves where you pick and becomes a project), or Cancel. A scratch session's menu offers Keep as Project… at any time. Only ⌘⇧N makes scratch sessions: ⌘T or a split from one opens a normal session in your home folder.
  - **Projects** you made (**New Project…** or **⌘O**, dropping a folder on the sidebar, or `calm open <folder>`): each opens with a session in it. Each gets a small pixel mark made from its name (renaming a project changes its mark); clicking the mark, a small easter egg, swaps it for another at random, which it keeps. A session started in a project stays in it, even when its shell `cd`s elsewhere; ⌘T and splits from it stay there too. Right-click a session: **Move to Project** (any session but a scratch one), **Let It Follow Its Folder** (a project session goes back to grouping by folder). A project's **⋯** (on hover) or right-click: **Remove Project** undoes it: its sessions stay open and group by their folders again, and nothing on disk changes.
  - **Folders**, for every other session: grouped by the git repository's root, or by the folder outside a repository, and moving when the shell `cd`s. A folder group holds only its own repository or folder, so one for your home folder doesn't swallow everything under it; groups appear and disappear on their own. Under its name a folder group says where the folder is, its parent with the home folder as `~` (`~/dev/apps`), so two folders with the same name can be told apart; the home folder's own group has no such line. A session whose folder is inside a project you made joins that project while it's there. A group's **⋯** (on hover) or right-click: **Make Project** keeps it and its sessions; its **+** starts a session there.
- **At launch**, Calm starts where you left off. With nothing open (later launches, or after you close the last session) the window shows a page of its own, with no sidebar until a session opens, so nothing is out of reach behind one that isn't there. It has Calm's mark (animated: it arrives, then waits, its cursor breathing; a click runs one lap), a **search field** over past sessions and your projects together, **Recent sessions** from every agent beside your **Projects** (the last row, **New project…**, makes one), and one line of the three ways to start: **⌘T New session · ⌘⇧N Scratch · ⌘O New project…**, each a button. Typing filters both lists (a session by what was said in it, a project by its name or folder); ↑ ↓ move through the rows, ← → change list, ↵ opens (goes to a session that's open, resumes one that isn't, starts a session in a project), Esc clears; **⌘K** puts the caret in the field. With no past sessions the projects fill the page, and with no projects the sessions do. With no project made, the page is a welcome instead when it is the very first launch, and when there is no past session either: "Welcome to Calm" (first launch only) and the three ways to start as rows (Start a session ⌘T, Try a scratch session ⌘⇧N, Open a project ⌘O). Make a project and the lists come back, so a project is never out of reach. From there, **⌘T** opens a shell in your home folder. Calm never opens a session nobody asked for.
- The sidebar's footer starts things, one row each: **New Session ⌘T**, **New Scratch Session ⌘⇧N**, **New Project… ⌘O**. ⌘T opens a shell in the folder of the session you're in, or your home folder when none is selected. Once you know the shortcuts, the footer can go: with the pointer over it, a small chevron shows just above its line, and a click hides the three rows, so the session list runs to the bottom edge. The shortcuts, the menus and the welcome page's start line still work. To bring it back, point at the bottom edge of the sidebar: the same chevron shows there, and a click restores the rows. The choice is kept (`footer = false` under `[sidebar]` in config.toml, removed when the footer shows again). It has no row in Settings, so it doesn't count against the settings budget.
- **⌘⌃S** hides the sidebar and brings it back; while it's hidden, it peeks in over the terminal when the pointer reaches the window's left edge. **⌘1…9** go to a session by its place in the sidebar and **⌘⇧[** / **⌘⇧]** to the one above or below; holding **⌃** and pressing **Tab** cycles sessions in sidebar order over small live previews (⌃⇧Tab goes up).
- Each agent session is a **session card** showing: the session name and the time since its last activity, its state and current step, progress when the agent keeps a todo list, a two-line recap of the latest agent message (plain text: its Markdown headings, code blocks and bold are taken out), and the worktree name when the session runs in a git worktree (the one its agent is in: Claude Code can move into a worktree while the shell that started it stays in the main checkout; the header above the terminal shows the same name on the folder line under the session's name). The card shows the agent's own logo, which moves while the agent works; working, needs you and done each tint the card (soft blue, amber, sage until you move on from it), and an idle card recedes into a shorter card (name and a one-line recap). Once you've read a session and it sits idle, its recap is the agent's own summary of where things stand, if the agent wrote one after its last message (Claude Code's "※ recap", about three minutes after a turn ends), in place of the tail end of its last answer; the next turn brings back its latest message. Plain shells are one compact line. Settings → Appearance → Session cards makes every agent card smaller (Compact, Minimal; F11), keeping a line for anything that waits for you.
- The card's content is read from the agent's own conversation file. What each agent gives it:

  | Agent | Recap | Title | Step and progress | Esc noticed |
  |---|---|---|---|---|
  | Claude Code | yes, and its own summary once idle | its own | from its todos | yes |
  | Codex | yes | none (Codex keeps none in its files) | none | yes |
  | OpenCode | yes | its session title, once named | none | yes |
  | pi | yes | its session name | none | yes |

  Calm finds the conversation from the agent's process (from its hooks or extension where it has them). When two conversations of one agent could be the one in a folder and Calm can't tell which, the card shows no recap rather than another conversation's. Without its hooks or extension (OpenCode not connected), a `/new` leaves the card on the conversation it found first.
- Projects can be collapsed to one line that shows what's going on inside in the cards' state marks: three working agents are three blue rings, four or more a ring and the number; idle sessions show only when nothing else is going on, and a session that needs you tints the line amber (UIUX.md → Session cards). Opening a session opens its group if it was collapsed, so the session you're in is never out of sight: a click, ⌘1…9, ⌃Tab, ⌘K, a notification, `calm`, a new session, a split, a reopened one, or a click into another pane of a split. Collapsing the group you're in works and stays until you move to a session in it again.
- The folder comes from the shell itself (Ghostty's shell integration for zsh, fish and elvish, also inside persistent sessions); for other shells Calm reads it from the shell process every couple of seconds.

**Settings:** 1 — auto-grouping on/off (default on): `auto-grouping = false` in `~/.config/calm/config.toml` (Settings → General), re-read by Reload Configuration (⌘⇧,). Off, sessions stay in the group they started in.

## F3 — Persistent sessions ✅

- Quitting Calm detaches shells instead of killing them. Relaunching reattaches, with scrollback and running processes intact. A running program gets its terminal back at the size it had (the window's and the text's), not a small placeholder first, so a program that draws its own screen, such as Claude Code, redraws once and its screen comes back whole.
- **Restart Calm** (Calm menu, no shortcut) quits and opens Calm again once the old one has fully exited, so every session comes back as after any relaunch, agents still running. It opens the app from the same place, so a version installed meanwhile (`install.sh`) is the one that starts. When shells aren't being kept alive (zmx missing or failing) and something is running, it asks first, as Quit does.
- Projects, sessions and split layouts are restored.
- The sidebar comes back as it was left: each agent's mark, state and recap, and the time since its last activity. Before the window opens Calm checks every saved agent against the running one (Claude Code tells what it is doing in its own status file), so a session that was working still shows working, one that has since finished shows idle, and one whose agent has ended has no mark. If that check takes more than a moment, the rows show a quiet "Restoring sessions…" state instead of a state, and settle together.
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
- Only the agent in the session's foreground speaks for it. An agent that another one starts (Claude Code running `pi -p` in its Bash tool) inherits the session and reports too, but its reports are left out, so the card keeps the foreground agent's mark and state.
- Codex, and OpenCode until it is connected, have no hook to say they are working (their notifications only tell a finished turn or an ask, and only while their terminal isn't focused), so Calm reads it from their own conversation files: a turn that has started and not ended is **working**, and one that ended is **done** (or **failed**, for OpenCode). The card works and settles within a couple of seconds of the agent. This is a guess, so an agent's own hook always outranks it, and it never replaces a pending **needs you**.
- A Claude Code turn that ends with one of Claude's own background agents still running stays **working**: Claude picks up again on its own when the agent finishes.
- Background *shells* don't hold it: a dev server or a monitor never ends and nothing would wake Claude, so the turn is **done** (the next move is yours), and the card adds "· 2 shells running" until you move on from it (2026-09-29, the author's call). Only tasks still running or pending count; a kind of task Calm doesn't know counts as a shell.
- Plain shells get a quiet mark too: a command that ran for 10 seconds or more shows **done** or **failed** until you move on from it.
- State appears in the sidebar as a quiet indicator. Only **needs you** escalates:
  1. The session's row gets a soft highlight.
  2. If the user is not looking at that session, a macOS notification is delivered **at the next natural pause** (not while the user is typing in another pane).
- The notification reads like a note: a mark for the state and the session's name (✋ needs you, ✅ done, ⚠️ failed), then one or two lines of what the agent said, cleaned of Markdown. It doesn't name the project or the agent (UIUX.md → Notifications).
- Clicking the notification jumps to the session. **⌘⇧A** jumps to the session that has waited longest.
- **done** and **failed** notify only if you opt in (Settings → Agents). They show in the sidebar until you've been to the session and moved on: arriving keeps them while you read, and going to another session, or leaving Calm, settles them to idle. Leaving Calm means going to another app, one with a Dock icon: a menu-bar tool that takes the front for a moment (a screenshot tool such as Snipaste, a clipboard manager, Spotlight) is used over Calm, so coming back from it leaves the card as it was; going on from it to another app counts.
- A **needs you** is never dropped: if delivery is deferred, it waits, and it stays visible in the sidebar until handled.
- The Dock icon shows the whole app's state:
  - **running:** a quiet chase around Calm's mark while any session is working;
  - **done:** the ring closed in sage;
  - **failed:** the ring dimmed to grey with a red cell.

  Done and failed last until you move on from the session. The icon never badges or bounces (UIUX.md → App icon).

- With Claude Code, Calm's hooks are on by default inside Calm (a plugin Claude loads only in Calm's shells; nothing is written to Claude's settings), so *needs you* arrives the moment Claude asks, with what it asks.

- **Calm → Agents…** (Settings → Agents) lists the installed agents and how each connects: Claude Code inside Calm; Codex through its own notifications; pi through a small extension Calm adds only when you click **Connect** (and removes with **Disconnect**; it also tells Calm which conversation it is, dresses pi in Calm's theme (F11), and Calm keeps its own file current when it updates); OpenCode, like pi, through a small plugin Calm adds only when you click **Connect** (and removes with **Disconnect**): it says at once when OpenCode needs you (a permission or a question, a subagent's too), when a turn starts, finishes, fails or is interrupted, and which conversation it is, so a `/new` and two OpenCodes in one folder are followed exactly; connected, OpenCode also wears Calm's theme (F11). Unconnected, OpenCode still works and settles from its own files (above), and its own attention notifications, when turned on in `~/.config/opencode/cli.json`, still reach Calm.

**Settings:** 2, in Settings → Agents, plus one switch in the config file that the budget doesn't count, since it never appears on the Settings screen. In Settings → Agents: which states notify (default: only *needs you*; or also *done* and *failed*) and notification sound on/off (default off), stored in config.toml as `notify` and `sound` under `[agents]`. One in the config file only: `claude-code-hooks = false` under `[agents]` turns Calm's Claude Code hooks off.

## F6 — Arrival card ✅

- When the user switches into an agent session while the sidebar is hidden, and something happened there since they last left it, a small strip at the top of the pane shows:
  - the session title;
  - its state;
  - the last thing the agent said or asked, in one or two lines (for an idle session, the agent's own summary when it wrote one, as on its card);
  - how long ago that was.
- It uses titles and messages the agent already wrote. Nothing is generated.
- It fades as soon as the user types or after a few seconds (five), and can be recalled with **⌘⇧I**. Clicking it dismisses it.
- With the sidebar showing it stays away: the session's card there already shows the same title, state and recap. Switching back and forth between sessions with nothing new doesn't show it either.

**Settings:** none.

## F7 — Search all sessions ✅

- **⌘K**, or the **Search sessions** field at the top of the sidebar, opens a search box over every past and present session of Claude Code, Codex, OpenCode and pi.
- Results are sessions, not lines, grouped the way the sidebar groups them (a project you made, Scratch, or the folder's repository), the group you're in first and the others in the order of their best match. Every project is searched: the one you're in only comes first.
- **Every word you typed is shown and marked** in every result: in the title, in the group's name, or in the lines under the title, which are the fewest messages (three at most) that hold the words, each cut to a line around them, with the stretch between two far-apart words left out. A line you wrote starts with the prompt's chevron; the agent's have none.
- **One or two letters match where a word starts** ("d" finds *Draft*, not the d in *hardware*); from three on, anywhere. Chinese matches anywhere at any length. A word can also name a group: "calm scroll" finds what was said about scrolling in calm.
- With results in more than one group, each shows a few (three of yours, two of the others) and the rest wait behind **"13 more in calm"**, which shows five more at a time and stays where it is; once a group is open, **Show less** folds it back (so does the chevron on its header). A group just one over its share shows it.
- A group's header counts what it holds, in three numbers at most: open in Calm and doing something, open and idle, and past (on the project's own tile). A session open in Calm shows its state's mark where a past one says how long ago ("4 minutes ago", "yesterday", then the date).
- With nothing typed, the panel is a switcher: the sessions you could pick back up (open ones are in the sidebar already), four of your group's and two of each other's, most recent first.
- **Enter** jumps to the session if it is open; otherwise it resumes the conversation in a new session in its folder (home if the folder is gone). ↑ ↓ move, ⇥ and ⇧⇥ jump between groups, → and ← choose between a group's more and Show less, Esc closes.
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
- **At rest**, every link on screen that opens (a URL, or a file or folder that's there) has a faint dotted line under it, including one the terminal wrapped onto the next row. Rows that change lose their marks at once and get them back when the text holds still, so marks never trail scrolling or streaming output. Programs that take the mouse (vim, htop, an agent's full-screen view) get none: their screens are redrawn too often for marks to hold still. Known gap: a link a program sets behind other text (OSC 8) gets no mark.
- **A link a program cut across lines** opens whole. An agent's full-screen view lays its text out to its own width and breaks a long URL or path with a line break of its own, indenting the rest, so the terminal sees two unrelated rows. ⌘-click on any part of such a link opens all of it (and the program never sees the click); its tag and underline cover all of it, and it has its mark at rest, like a link the terminal wrapped. Calm reads a row as cut when its text runs to within three columns of the right edge (a scrollbar or margin takes a column or two) and the next row starts a word after an indent of at most 16 columns. That is a guess, so the joined text counts only when it leads somewhere (a file that's there, a URL); a word that merely ends at the edge is not glued to the next row's word when the result names no file. Known gaps: a URL that ends at the edge and is followed by a word on the next row is read as one link; a program that cuts before the edge (at a `-` or `/`), or draws a border or gutter in front of the continuation (`│`, `⎿`), isn't joined.
- **Holding ⌘** over a link shows a small tag just under it (above it at the pane's bottom): the file's name and line, its folder, and what a click does ("Open in viewer", "Open in Cursor", "Open in browser", "Open in Finder", or "Not found" before you click). An image's tag shows its thumbnail. The tag goes away when ⌘ or the pointer leaves the link, or on typing, clicking or scrolling.
- **In programs that take the mouse** (vim, htop, Claude Code's full-screen view) a link under ⌘ is still Calm's: the same underline and tag on hover, and a ⌘-click opens it without the program seeing the click (a program can't see ⌘ anyway). Away from a link, ⌘-click reaches the program as before.

**Settings:** 2 — editor (auto-detected: VS Code, Cursor, Trae, Windsurf, Zed, Sublime Text, IntelliJ IDEA, Xcode; or any application, chosen in Settings → General with Choose Application…, or `editor = "…"` in config.toml, a name or an `.app` path; an application that isn't one of those opens the file but not at the line); where paths open (Calm's viewer or editor, default viewer: `open-paths = "editor"` to change it).

## F9 — Copy Cell ✅

- Copies the text of one cell of a table drawn with box characters (`│ ─ ┼` and similar), instead of whole rows.
- **Hold ⌥** over a table: a faint dotted outline marks the cell under the pointer. **⌥-click** copies that cell, and a small "Cell copied" note shows by the pointer. It works in programs that take the mouse too (Claude Code's full-screen view): Calm keeps that click, so the program never sees it.
- **⌥-drag** that starts in a cell selects inside that cell only, and copies what it selected when you let go ("Copied"): part of a long cell, across its wrapped lines, never picking up the cells beside it. Past the cell's lines it stays inside (beside a line, to that line's edge; below the cell, to its end). The selection shows for a moment after the copy. Programs that take the mouse never see the drag. An ⌥-drag that starts outside a table is the terminal's rectangle selection as before (or the program's own selection).
- Wrapped lines inside the cell are joined, and padding is trimmed, giving one clean string.
- Outside a drawn table, an ⌥-click is an ordinary click. Claude Code prints a table too wide for the pane as `Name: value` lines instead of a box, and those aren't a table to copy from.
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
  - **Finding it:** nothing else in the window names the column, so two things do. The sidebar's footer has a fourth row beside the ways to start, **Show Files ⌘\\** (**Hide Files** while the column is up), which teaches the key in the place Calm already teaches keys. And while the project has uncommitted changes, the title strip says so at its right, in plain text: `3 changed +58 −6`. Under the pointer the words become `Show Files ⌘\` in the same place, and a click opens the column. The readout goes while the column is up (its header and Changes show the same numbers) and is absent for a clean project, a folder that isn't a git repository, and a session sitting in Desktop, Documents or Downloads themselves (macOS would ask). It looks again when you come to a session, when an agent starts or stops working in it, when Calm comes forward, and every 8 seconds while an agent works. Picked by the author from local mockups (2026-09-30): the footer row, plus B's readout.
  - A ⌘\\ keybinding in the user's own Ghostty config wins over Calm's, and so does a global shortcut such as 1Password's autofill (⌘\\ by default; see UIUX.md → Keyboard); Toggle Files stays in the View menu.
- **Viewer:** opening a viewable file (Markdown, HTML, PDF, images; code with syntax highlighting) **covers the main area** where the session was. **Esc** returns to the session exactly as it was; the session keeps running underneath. The viewer stays on the main area as the sidebar and files column open and close, and going to another session (a click, ⌘1…9, ⌃Tab, search, a new session) closes it.
- Files open from the tree, from ⌘-click (F8), or from `calm open <file>` (also `file:line`, which highlights that line in code).
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
- Colors an app picks for itself (truecolor) aren't the theme's. OpenCode's own themes are like that, so in the shells Calm starts OpenCode is asked for a theme that follows Calm's: once OpenCode is connected (Settings → Agents), Calm's own `calm` theme (the theme's accent, its dim text, quiet boxes), which Calm writes to OpenCode's `themes/calm.json` and keeps in step with the theme and the appearance, a running OpenCode included; unconnected, OpenCode's `system` theme. A theme named in OpenCode's `cli.json` wins, from the next session on for one picked inside OpenCode. A session's shell keeps what it started with, so a session opened before Calm asked still shows OpenCode's default until a new one.
- pi's own themes are the same, and a connected pi wears Calm's `calm` theme too: Calm writes it to pi's `themes/calm.json` and Calm's extension sets it inside Calm, over pi's built-in themes (`system`, `dark`, `light`) only, and without saving it to pi's settings, so pi outside Calm keeps its own. It follows the theme and the appearance, a running pi included.
- **Window options**, under the picker in Settings → Appearance:
  - **Interface size:** Default, Large, Larger or Largest, shown as chips of Calm's sidebar growing beside a terminal that doesn't; everything Calm draws around the terminal grows together (UIUX.md → Accessibility). The terminal's own text stays the Ghostty font's size.
  - **Session cards:** Full, Compact or Minimal, shown as chips of the sidebar's cards at each size: every line; the state and the recap on one line under the title; or the title and a time in the state's color. At the smaller sizes a card that waits for you (needs you, done, failed) grows a line for its message until it's answered or seen (UIUX.md → Session cards). Asked for by the author, to fit more sessions in view. Under the chips, **Shrink cards to fit** (off by default) makes the chosen size the largest: when the sessions don't fit the sidebar the cards step down (Full → Compact → Minimal), and they step back up when there's room again, never past the chosen size. A line in its row says it; with Minimal chosen it says there's nothing to step down to, and the switch rests.
  - **Background:** solid, or glass (the system's blur behind a translucent terminal and sidebar; panels and the viewer stay solid).
  - **Layout:** edge to edge, or card (the terminal floats as a rounded card on the sidebar's color).
  - **Motion:** full, reduced or off; the system's Reduce Motion always wins. Full motion includes the terminal's own: the cursor glide, and smooth scrolling (scrollback and programs' scrolling move by pixels, so an agent's streaming answer flows instead of jumping; UIUX.md → Motion). `smooth-scroll = false` in `~/.config/calm/terminal.ghostty` turns just the scrolling off.

**Settings:** 7, over the budget of one or two, all in Settings → Appearance and saved to config.toml: `theme`, `ui-size = "larger"`, `session-cards = "compact"`, `session-cards-fit = true`, `background = "glass"` and `layout = "card"` under `[window]`, and `motion = "reduced"`. Choosing a default removes its key, except the theme (F14).

## F12 — Session actions ✅

- **Where:** right-click a session's card, or the ⋯ button at the right of the title strip above the terminal (for the session you're in): one menu in both places. Rename from the title brings a hidden sidebar back, since the name is edited on its card.
- **Rename** a session: Rename… edits the name in place (return keeps it, esc cancels, an empty name gives the session back its own title). The name wins over the shell's and the agent's titles, in the sidebar, the title strip above the terminal, switcher, arrival card and notifications, and survives relaunch.
- **Resume** an agent conversation: when the agent exits, the session remembers its conversation, and right-click → Resume <agent> Conversation continues it in the same shell. A conversation whose session was closed is resumed from ⌘K search (F7), in its folder.
- **Restart** a running agent on its conversation, mostly after updating it: ⌘P → Restart *Agent* for the session in front, Restart All *Agent* Sessions for every one, or a click on the title strip's update hint (decided 2026-10-06: not in the right-click menu, since it isn't an everyday action). Calm asks the agent to quit, then types the command that starts it again in the same shell with the options it was started with and `--resume <id>`: `claude --dangerously-skip-permissions --resume 'id'`. The prompt it was started with isn't sent again, and options that pick or make the conversation or its place (`-c`, `-r`, `--session-id`, `-w`, `--tmux`) are left out. An agent that is working or waiting on you restarts when its turn ends ("restarts after this turn" on its card, Don't Restart takes it back), so a turn is never cut off. A prompt typed but not sent is lost, as when quitting the agent yourself. The card keeps its title and recap throughout. Only Claude Code for now: it quits on SIGTERM and leaves the terminal as it found it (checked 2026-10-06 on 2.1.291); the other agents' ways to quit haven't been checked, so they get the hint but no restart. Background shells the turn left running end with the agent.
- **The update hint:** when the agent in front runs an older version than the one installed, the title strip says so at its right ("↑ Claude Code 2.1.291", UIUX.md → Title bar), and a click restarts it. Calm tells from the files, for any agent: the command the agent was started with now leads to a newer version, or the file it runs was deleted by the update. A script run by node or bun says nothing about the agent's version, so pi gets no hint. Checked every 10 s.
- **Close** a session with ⌘W (or Close Session in its right-click menu). While an agent runs in it, or a process Ghostty can see, Calm asks first ("Claude Code is running in it. Closing the session ends it."). With Settings, search or a file open, ⌘W closes that instead of the session behind it. One ⌘W closes one session. Closing the one you're in doesn't take you to another: the sidebar stays, and the main area shows the sessions waiting for you, each with all it last said (↵ opens the first, ↑ ↓ choose another), or with none waiting, search over past sessions and your projects, as on the welcome page. You choose (a click, ↵, ⌘1…9, ⌃Tab) when you're ready. Closing any other session leaves you where you are, and closing one pane of a split leaves its sibling on screen. In a split the question sits on the pane it is about, not in a sheet: "Claude Code is running here / Closing the session ends it", in the middle of that pane, with the other panes almost gone; Return closes, Esc keeps, and any other key, ⌘W again, a click elsewhere or moving to another pane keeps too. A pane that closes folds toward the pane that takes its room.
- **Reopen** the session closed last with **⌘⇧T** (Shell → Reopen Closed Session; greyed out until something has been closed), and again for the one before it, up to the last ten. The shell is a new one, since closing ended the old, but everything else comes back: its folder (the project's, or home, if that's gone), its name, its project if it stayed in one, and its place in the sidebar. If an agent was running in it, its conversation resumes with the agent's own command (the table below); one that had already exited isn't started again. Scratch sessions aren't reopened: closing removes their folder. Kept in memory, so a relaunch starts with nothing to reopen. A shell that exits by itself (`exit`, ⌃D) counts as closed.
- **Copy** from the session: Copy Session ID (the agent's own id for the conversation, while it runs or after it ended), Copy Resume Command (e.g. `claude --resume 'id'`), and Copy Folder Path, each with a quiet note by the pointer; Open in Finder opens the folder (its contents, like `open .`). A scratch session has no folder to copy or open. Each item shows only where there is something to give.
- **Fork** an agent conversation into a new split beside it or a new tab (a session of its own), in the same folder, while it runs or after it ended. The fork is a new conversation; the original stays as it was.
- Uses each agent's own commands:

  | Agent | Resume | Fork |
  |---|---|---|
  | Claude Code | `claude --resume <id>` | `claude --resume <id> --fork-session` |
  | Codex | `codex resume <id>` | `codex fork <id>` |
  | pi | `pi --session <file>` | `pi --fork <file>` |
  | OpenCode | `opencode --session <id>` | forked through its own API (`opencode api session.fork`), then opened with `--session`: 2.0.19's interface has no `--fork` |

  An action shows only where the agent has the command. A conversation the agent no longer has isn't offered for resuming (OpenCode would start a new, empty one under its id).

**Settings:** none. The menu offers the destination.

## F13 — `calm` command-line tool ✅

What is built, below. Every command in full, with the planned ones: [CLI.md](CLI.md).

- `calm open <folder|file>` — open a project (and a new session in it), or a file in the viewer (`file:line` highlights that line in code). With no argument, the current folder.
- `calm list` — list sessions: project, title, state, agent and folder.
- `calm search <text>` — search sessions from any shell: when, agent, project and title, then the matching text.
- `calm status <state> [message]` — report agent state; this is the contract any agent's hooks can call. `--agent <name>`, `--transcript <file>` and `--agent-session <id>` say which agent and which of its conversations this is, for agents that can't send a hook payload (pi's extension does). Safe in any terminal: outside Calm, or with Calm not running, it does nothing.
- `calm hook <agent>` — read an agent's hook payload on stdin and report its state; Calm's Claude Code plugin runs `calm hook claude-code`. Safe in any terminal, like `status`.
- `calm notify <message>` — show a notification for the current session.
- `calm doctor` — check that Calm, this `calm` and the agents' hooks work: which Calm answers, a second copy, an install waiting for a restart, the `calm` on `PATH`, each agent's link, and this session's last report. Reads only; exits 1 on a problem.
- `calm trace` — print Calm's trace (what decided each session's row) from the unified log: `--last 10m`, `--session <id>`, `--follow`.
- `calm config` — list Calm's settings (each value, its default, what it takes); `get`, `set` and `unset` one, written to config.toml as Settings writes it and applied by the running Calm at once.
- Talks to the running app over a local socket. `open` and `list` start Calm if it isn't running: the Calm the CLI came with.

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
