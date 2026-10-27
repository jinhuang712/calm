<!-- what-we-build: drafted 2026-10-28 -->

# Designs

Calm is a macOS app that draws a terminal with libghostty, keeps each shell alive in a background process (zmx), and watches the coding agent in the foreground of each shell. It learns an agent's state from the agent's own hooks, plugins and files, shows that state in a sidebar, and interrupts the user only when an agent needs them. This page holds the rules the code is built around and the reasons for choices that would otherwise look strange. It is not a tour of the code: the code, the manifests and `project.yml` show what exists.

Calm is designed around eight principles:

1. **Attention is a state of a session.** The session is the unit, and one of its five states is allowed to interrupt.
2. **Calm is a guest.** It works through the door that an agent or the user left open, and changes nothing it was not asked to change.
3. **A missing fact shows as less, never as a guess.** A card with no recap is better than a card with the wrong one.
4. **What the user made outlives the app.** Quit, crash, update and reboot lose nothing.
5. **Nothing moving costs nothing.** At rest Calm runs no work, and nothing waits on the outside world.
6. **Reuse, and keep the seams narrow.** The engine, the shell keeper and the search index are other people's code behind small doors.
7. **Calm stays on the Mac.** State is plain files, the network is for three things, and one socket is the only door in.
8. **A test never touches the user's machine.** It runs headless, in its own folders, and starts no real agent.

Each principle asks a question of every new requirement, and lists the decisions that follow from it. This page is the design we intend. What is built is in [FEATURES.md](specs/FEATURES.md).

## 1. Attention is a state of a session

The user supervises many agents, so the thing Calm models is not a tab but a conversation with a goal, a folder and an agent. Everything the sidebar shows is a state of such a session, and exactly one state may interrupt (PHILOSOPHY.md → What is calm?). The cost is that Calm owns the vocabulary: an agent whose states do not fit the five must be mapped, and a mapping can be wrong.

**Ask:** "Which session does this belong to, and does it change what the user is told?"

### Every session is one pane, and a split creates a session

- **Instead of:** tabs that hold panes, with sessions inside.
- **Why:** the card, the notification and the state need one owner. Joining, taking out and unsplitting change which sessions share a layout, and touch no session and no shell. Calm has one window, and libghostty's requests for a new window become new sessions.

### A session has one of five states

- **Instead of:** a status string per agent.
- **Why:** `idle`, `working`, `needs you`, `done` and `failed` are what the user needs to tell apart, whatever the agent calls them. Each adapter maps its own words onto them, and the core never sees the agent's.
- **Cycle:** `idle → working → (needs you | done | failed) → idle`, once the user leaves the session. A finished session stays `done` or `failed` while the user reads it.

### Reports are idempotent, and the latest wins

- **Instead of:** a log of events replayed into a state.
- **Why:** hooks arrive late, twice and out of order, and a report that says the same thing twice must change nothing. The manager applies each report to a copy of the workspace and returns an effect: notify for a new `needs you` in a session the user is not looking at, withdraw when it leaves `needs you`.

### A notification waits for a natural pause

- **Instead of:** notifying at once.
- **Why:** an interruption in the middle of a thought costs more than one at its end (PHILOSOPHY.md → What is scarce when agents do the typing?). `AttentionQueue` holds one notification per session until typing stops for a moment, the focus changes or a maximum wait ends. It is never dropped, and it carries no sound by default.

### Leaving is a decision about which app comes forward

- **Instead of:** treating Calm losing the front as leaving (2026-09-30).
- **Why:** a screenshot tool that took the front for a second settled the card the user was reading. Only an application with a Dock icon coming forward counts as leaving, and a menu-bar tool does not.

### Calm never picks a session for the user

- **Instead of:** selecting the next session when one closes.
- **Why:** moving the user's attention is the one thing the tool must not do. Closing the session on screen selects none, and ⌘W never falls through to closing the window. The same rule keeps an agent from moving the user: `calm fork` from an agent always runs in the background.

### Grouping follows the folder, and a project the user made wins

- **Instead of:** grouping by a directory that contains the folder.
- **Why:** containment let a home-folder group swallow every session under `~`. A session that is not pinned goes to the most specific project the user made that contains its folder, else to the group keyed by its git root, or by the folder outside a repository. A group matches its key exactly. Sessions started in a project or a scratch folder are pinned.

### One focus: the first responder and the model are the same pane

- **Instead of:** two sources of focus that usually agree.
- **Why:** a ⌘W on the wrong pane closes the wrong session. A key that reaches a pane moves the model onto it, so the indicators follow the keyboard, never the other way round.

## 2. Calm is a guest

Calm lives in other people's homes: the agents' config folders, the user's Ghostty config, the user's shell. The agents change often and the user's setup is theirs. So Calm uses the doors those homes already have, writes only what the user asked for, and can take it back. The cost is that Calm sees less than a tool that took over would. Codex has no usable hook, so its state is a guess from its files.

**Ask:** "Whose file or setting is this, and does Calm change it without being asked?"

### One adapter per agent

- **Instead of:** special cases for each agent in the core.
- **Why:** an agent's formats change without notice. Everything specific to one agent sits in its adapter, so a change breaks one adapter, and adding an agent never touches the core. Removing omp on 2026-09-29 cost nobody a session, because saved sessions decode an unknown agent leniently.

### Hooks arrive as a plugin that only Calm's shells load

- **Instead of:** writing hooks into `~/.claude/settings.json`.
- **Why:** nothing is left behind outside Calm and nothing needs undoing. The plugin is written to Calm's own support folder at each launch and found through `CLAUDE_CODE_PLUGIN_DIRS`.

### Calm intercepts no key of an agent

- **Instead of:** catching ⌘↵ in the terminal and rewriting it (decided 2026-10-07).
- **Why:** the agent decides what its own keys mean. Calm adds a binding to the agent's own keybindings file, only while the user has the setting on, and removes exactly its own lines when it goes off. A file that Calm cannot edit safely, such as one with comments, stays as it is.

### A file in an agent's folder is written only after Connect, and marked

- **Instead of:** installing files when Calm first sees the agent.
- **Why:** the user can undo what they chose. Every file carries a marker line. Calm refuses to overwrite, and never removes, a file without it, and refreshes its own files at each launch so a connection made before an update keeps up.
- **The one exception** (2026-10-11): Calm marks its scratch folders trusted in `~/.claude.json` without asking, because Claude Code's trust question stopped every ⌘⇧N. It edits the file the way Claude Code does, under its lock, read again once the lock is held, replaced in one rename. A held lock is waited on briefly and never broken.

### Agents' data is read, not owned

- **Instead of:** keeping Calm's own copy of conversations as the truth.
- **Why:** the agents already store them. Calm reads transcripts and databases read-only and indexes a copy of the text. When an agent deletes a transcript, the copy stays, marked `gone` (2026-09-29), because Claude Code deletes old ones and the conversation is still worth finding.

### Codex gets no hook (2026-09-29)

| Option | For | Against |
|---|---|---|
| **Notifications and transcript tails** (chosen) | Touches nothing of the user's | State is a guess from files when no notification came |
| A persistent hook tied by folder | Exact state | Edits the user's hooks, and is ambiguous with two sessions in one folder |
| A `codex` wrapper that passes hooks with `-c` | Exact state | Slower to start, and invasive |

Since version 0.157 Codex runs hooks in one shared daemon with the first launcher's environment, and a payload names nothing that ties it to a terminal. Every hook also needs the user's approval in `/hooks`. Revisit if the daemon changes.

### Each agent learns the `calm` command through its own skill door

- **Instead of:** an MCP server.
- **Why:** the CLI already reaches every agent that can run a command (specs/CLI.md → Not planned). Claude Code gets the skill in Calm's plugin and pi through its extension, both without a file outside Calm. OpenCode and Codex read skills only from fixed folders and take no path from a variable, so Connect writes the file there (checked 2026-10-13).
- **No `allowed-tools`:** in Claude Code it makes loading the skill ask, and its grant ends with the turn. Each `calm` command asks by the agent's own rules, where "don't ask again" saves a rule.

### Calm's theme reaches an agent through the agent's own theme file

- **Instead of:** repainting the agent's output.
- **Why:** OpenCode and pi draw in truecolor and ignore the terminal's palette. A connected agent gets a `calm` theme file that Calm keeps in step, and Calm never touches a file of that name it did not write. pi receives the theme as an object, not by name, because a name is saved to pi's `settings.json` and would carry Calm's theme outside Calm.

### The user's setup loads after Calm's defaults

- **Instead of:** Calm overriding the user's Ghostty config and keybindings.
- **Why:** the user's own choice wins. Options load in this order, each over the one before: Calm's defaults, the user's Ghostty config, Calm's `choices.ghostty` (a theme picked in Calm, glass), then `terminal.ghostty` for Calm-only overrides. Calm writes a picked theme as plain colors into `choices.ghostty`, because Ghostty ranks a theme file below any color set in a config.

### Calm types the user's command into the user's shell

- **Instead of:** starting an agent as a process of its own.
- **Why:** PATH, mise and direnv run first, and the shell stays when the agent exits. ⌘N, Resume, Fork and Restart all type the command, so they behave as if the user typed it.

### Settings writes one line at a time

- **Instead of:** rewriting `config.toml` from a model.
- **Why:** comments and keys Calm does not know stay. Choosing a default removes the key, except the theme, which stays so that it wins over the user's Ghostty colors.

### An agent is quit in the way it quits cleanly

- **Instead of:** one signal for all.
- **Why:** checked against each real agent in a pty (2026-10-06 and 2026-10-07).

| Agent | Calm sends | Why |
|---|---|---|
| Claude Code | SIGTERM | Quits cleanly and resets every terminal mode. ⌃C quits only from an empty prompt |
| Codex | ⌃C, again if still running | Quits cleanly on ⌃C. Dies on signals with terminal modes left on |
| OpenCode | SIGTERM | Quits cleanly |
| pi | SIGTERM | Quits cleanly. Dies untidily on SIGINT |

## 3. A missing fact shows as less, never as a guess

A user who sees a wrong state stops trusting every state (PHILOSOPHY.md → Why do people keep checking a quiet tool?). So when Calm cannot read, match or confirm something, it shows nothing, and the session keeps working. The cost is that cards are sometimes plain where a guess would have been right.

**Ask:** "If this input is missing, late or in a new shape, what does the user see?"

### The most exact source wins, and a guess never overrides it

- **Instead of:** averaging sources, or reading window titles.
- **Why:** a hook report outranks terminal signals, and both outrank a state read from a transcript. Titles are not used, because agents' title formats vary and change. A transcript turn never overrides a pending `needs you`, and a reading written before the latest report is stale.

### Terminal signals are a fallback that reads words, not a feature

- **Instead of:** trusting any notification an agent sends.
- **Why:** with no hook, libghostty's actions become signals that one pure function reads, so the rule is tested as a table. A progress report means working, and its removal means done. A notification reads by its words: permission, approval, allow, confirm or question mean `needs you`, error or failed mean `failed`, and anything else means done. A bell counts only when the agent was working, and only an explicit ask can notify.

### Two possible conversations mean none

- **Instead of:** picking the newest.
- **Why:** a card with another conversation's recap is worse than a card with no recap.

### A report from an agent that is not the session's foreground is ignored

- **Instead of:** trusting every report that carries the session id.
- **Why:** an agent run by another agent's tool inherits the session's variables. On 2026-10-13, 72 `claude -p` runs from Claude Code's Bash tool flipped one card between done and working every second or two, and sent a notification for each answer. A report whose process ancestors include another agent of the same kind is dropped, and a job that is not among the ancestors proves nothing, so that report stands.

### An agent's words are made plain only where a mark clearly wraps them

- **Instead of:** stripping every `*` and `_`.
- **Why:** a first version turned `find -name '*.py'` into `find -name '.py'` (2026-09-29). The same plain text reaches cards, the arrival card and notifications, and it must give the same result when applied twice. A permission request, an error and a command are left exactly as written, because a command must reach the screen unchanged.

### What a reader cannot decode is set aside, never overwritten

- **Instead of:** starting over, or crashing.
- **Why:** saved sessions decode leniently, because the workspace store starts over when anything fails to decode. A state file that Calm cannot read, or that is from a newer Calm, is moved aside as `state.unreadable-<time>.json`, and the next launch says so.

### The sidebar comes back as it was left, checked before the window opens (2026-09-29)

- **Instead of:** showing every agent idle until its next hook.
- **Why:** a restart used to show wrong states for a minute. A launch pass asks what each saved session runs now, and the run stays only when the same agent process still holds the foreground. If the answer is slow, rows show a loading state, and a pass past its deadline ends every saved run. Quitting while rows load loses nothing.

### A resume is typed only when the shell is known to be gone

- **Instead of:** resuming whenever a session looks dead.
- **Why:** a failed or late `zmx list` marks nothing, because a resume typed into a running Claude Code would land in its prompt.

### A command that cannot be done as asked is refused

- **Instead of:** dropping part of it.
- **Why:** an adapter that cannot take a first message returns nothing, so `calm fork` and `calm new` refuse a prompt for it instead of losing the words. A flag that Calm cannot read in a start command adds no option.

## 4. What the user made outlives the app

A session is a conversation, a folder and a running program, and they take hours to rebuild. So quitting, crashing, updating or restarting the Mac must not end them. The cost is a second layer between the terminal and the agent: libghostty cannot see an agent behind zmx, so closing a session must ask.

**Ask:** "If Calm quits, crashes or updates right now, what does the user lose?"

### A background process keeps every shell: zmx

- **Instead of:** Calm owning the pseudo-terminals, or tmux (decided in M2.7).
- **Why:** quitting Calm then detaches a shell and does not kill it. zmx is MIT-licensed, maintained and small. Each session runs `zmx attach calm-<12 hex>` with a Calm-only `ZMX_DIR`, so Calm's sessions stay apart from any other zmx use, and the name stays short because each is a Unix socket.
- **Close and quit differ:** quitting detaches, and closing a session runs `zmx kill`. At launch, `calm-*` sessions that no saved session refers to are killed. Without zmx, sessions fall back to plain shells for the rest of the run.

### A pane starts at its final size (2026-09-30)

- **Instead of:** creating the pane at a placeholder and resizing it.
- **Why:** reattaching hands the program the new client's size, and a full-screen agent redrew garbled at the old one. The window frame is restored before panes are built, and each pane passes its size into the engine (patch 0013).

### A late "child exited" never reaches the next pane

- **Instead of:** trusting the engine to number surfaces once.
- **Why:** libghostty can allocate a new surface where a freed one was, so a late exit could close the wrong pane. Teardown drains the mailbox after the surface is freed, and an exit older than the pane is ignored.

### Restart is a quit plus a relaunch by a helper that waits for the old process to go

- **Instead of:** launching the new Calm from the old one.
- **Why:** two Calms must never attach to the same zmx sessions or write the same state file. The helper opens Calm by path, so a Debug build never wakes the installed one.

### State is one versioned file, written whole and rarely

- **Instead of:** a database, or a write for every change.
- **Why:** the state is small and a user can read it. `state.json` is written atomically and debounced, and a write is skipped when the file already holds the same bytes.

### A session resumes its conversation after the Mac restarts (2026-10-07)

| Option | For | Against |
|---|---|---|
| **When the session is first opened** (chosen) | Costs nothing for sessions the user never opens | The agent is not running until the user looks |
| All at launch | Everything is ready | Starts every agent at once |

### An empty worktree goes with its session, only when git agrees

- **Instead of:** leaving it, or removing it by force (since 2026-10-07).
- **Why:** killing a session ends the agent before it removes the worktree it made. Calm asks the adapters whose lock it is, waits for that process, and removes with `git worktree remove` and `git branch -d`, never `--force`, so git checks once more. A worktree no adapter claims stays.

### Scratch folders live under `~/.local/share/calm/scratch`

- **Instead of:** a temporary folder, or Application Support.
- **Why:** macOS clears temporary folders, and the space in Application Support's path trips tools that do not quote paths. The path is fixed, because an app opened from the Dock does not see `$XDG_DATA_HOME`. The exclusion from Time Machine is set on the root only, because it travels with a moved item and a folder kept as a project must be backed up.

### An install keeps the old app aside while Calm runs from it

- **Instead of:** deleting it.
- **Why:** deleting the file a running Calm came from stopped macOS showing it the folder picker (2026-10-07). The moved-aside copy goes the moment its Calm quits (2026-10-12), because opening the app path started the moved copy again.

## 5. Nothing moving costs nothing

Calm runs beside ten agents all day, so its own cost counts. It also decides what the user sees, so it must never be the thing that hangs. The cost is that every effect has to prove it can come to rest.

**Ask:** "What runs when the user does nothing, and what happens if the thing this waits on never answers?"

### Motion is Core Animation layers

- **Instead of:** SwiftUI timelines (decided 2026-09-30).
- **Why:** a timeline re-rendered the whole sidebar on every tick. Layers take their `timeOffset` from the wall clock, so cards side by side agree, and they run only while the window can be seen.

### Cost is a budget of instructions and wakeups, checked by a script

- **Instead of:** CPU time, or a promise.
- **Why:** CPU time on a busy Mac varied several-fold between identical runs, and instructions did not. `mise run perf` holds each scenario (an idle shell, working agents seen and unseen, compacting, a streaming full-screen program, and the same hidden) to its budget. A feature that cannot meet the budget does not ship.

### No timer runs at rest

- **Instead of:** polling.
- **Why:** a repeating timer adds wakeups. The update check runs after launch and when Calm becomes active, only when due (decided 2026-10-09). The files column refreshes only while it is shown. Find runs nothing while its field sits open. Agents' status files are watched by one file event source each, attached when the agent starts and detached when it ends. The Dock icon ticks only while something moves, and draws only frames that changed.

### Frames are drawn only when the content has moved

- **Instead of:** a timer that draws on every refresh.
- **Why:** a frame is due once the content has moved a pixel, and the animation timer stays off while the display link draws every refresh, because each tick only armed the next (patches 0016 and 0017, since 2026-09-30 and 2026-10-06).

### Per-tool-call state lives outside the workspace

- **Instead of:** putting the live line in the observed workspace.
- **Why:** a write to the observed workspace re-renders the whole sidebar, even when nothing changed. The manager writes back only what changed, and a `LiveLineBox` per session carries what changes with every tool call. A setting that the chrome draws from reaches its view as a stored value, because a setting read in a view body is not observed.

### A hidden pane does not render

- **Instead of:** one flag for visible.
- **Why:** a pane draws only when its layout is shown and the window is visible. One flag for both woke every hidden pane when the window came back.

### Work on files, git, zmx and agents runs off the main thread, and calls that can hang have a time limit

- **Instead of:** trusting the outside world to answer.
- **Why:** a stuck `zmx list`, a silent control client, a hung installer or a slow launch pass must not freeze the window. A transcript can hold megabytes, so reading one never runs on the main thread, and the tail reader skips huge lines unparsed.

### A layout change resizes the terminal once

- **Instead of:** animating the terminal's size.
- **Why:** every resize reaches the program, and an agent redraws on each. The constraints change at once and only the layers glide.

## 6. Reuse, and keep the seams narrow

Calm is one developer's project and cannot rebuild a terminal engine, a shell keeper or a search index. So it takes the best of each and keeps a small door around it. The cost shows in one place: the engine patches, 17 of them, 7,979 lines.

**Ask:** "Does something that exists already do this, and how much of Calm would know about it?"

### libghostty draws the terminal, built from a pinned upstream plus patches

- **Instead of:** a prebuilt binary, or a fork as the source (decided 2026-09-29).
- **Why:** `scripts/ghosttykit.sh` checks out the pinned commit, applies the patches in name order and caches the result. A patch that does not apply stops the build. Calm pins a Ghostty `main` commit, not v1.3.1, because v1.3.1 needs a Zig that cannot link against the macOS 26.5 SDK. Zig's packages are fetched with curl and checked by hash against mirrored copies, because Zig's own client fails behind some proxies and Codeberg went down on 2026-09-30.

### Only `Terminal` touches the engine, and `CalmKit` has no UI framework

- **Instead of:** engine calls and logic spread through the app.
- **Why:** the logic then runs under `swift test` with no window, and a change in the engine's API lands in one module.

### An engine patch is small, separate and worth offering upstream

- **Instead of:** a private fork of the engine.
- **Why:** every Ghostty upgrade re-applies all of them. Patches 0005 and 0006 come unchanged from the `thdxg/ghostty` fork (MIT), credited in `NOTICE`, and are refreshed from it and never edited here. Calm's own start at 0007, one file each. The Find patches, 0011 and 0013 are the ones to offer upstream. Smooth scrolling and its fixes are 88% of the lines, and each of them goes when upstream ships smooth scrolling. Kept on purpose (decided 2026-10-13), because a screen that jumps is the kind of noise that calm removes (PHILOSOPHY.md → What is calm?).

### Calm adds to the engine only what it cannot do from outside

- **Instead of:** patching for convenience.
- **Why:** Find uses Calm's own matching and no patch for the current match (decided 2026-10-07), because a patch would need the terminal's lock in a callback that runs without it. Patches 0018 to 0021 exist only to read what the engine alone can see: the alternate screen, the primary screen behind it, and the end of a synchronized update.

### Search is SQLite FTS5 with the trigram tokenizer (decided 2026-09-27)

| Option | For | Against |
|---|---|---|
| **trigram, with a `LIKE` scan under three characters** (chosen) | Matched plain substring search on real history, whole words, partial words and Chinese | Larger index |
| unicode61 | Smaller | Missed partial words and Chinese |

### The viewer is a web view for text formats, PDFKit for PDFs, an image view for images (decided in M5.4)

- **Instead of:** `AttributedString(markdown:)`.
- **Why:** agents write GitHub-flavored Markdown, which that API does not render with tables, and HTML needs a web view anyway. markdown-it and highlight.js are pinned with checksums and committed, so builds stay offline. HTML and SVG open with page JavaScript off, and the page reads only its own folder.

### Ghostty's own commands enter the palette through an allowlist

- **Instead of:** listing everything libghostty offers.
- **Why:** its list is dozens of rows about Ghostty's windows and tabs, which Calm does not have. A test fails when Ghostty renames an entry.

### Other projects are for ideas only

- **Instead of:** copying their code.
- **Why:** Calm is Apache-2.0. It may study Ghostty (MIT) and adapt small parts, with attribution in the file header and in `NOTICE`. The one exception is the two fork patches above. The notices of everything the engine builds in ship with the app.

## 7. Calm stays on the Mac

Calm has no server and no account. It holds the user's conversations, folders and settings, so what it keeps and sends is part of the design. The cost is that Calm offers no sync and no remote access of its own. SSH and the agents' own features cover those (PROPOSAL.md → What we don't want).

**Ask:** "Does this send, store or log something a person wrote, and who else can reach it?"

### The network is for three things

- **Instead of:** telemetry, or a service.
- **Why:** Calm goes online for the daily update check, the user's agents doing their own work, and what a viewed file links to. The check is one GET of GitHub's releases list with the last ETag and no token. The list is used, not `/releases/latest`, because `latest` leaves out pre-releases and answers 404 while every release is one (2026-10-09).

### State is plain files

- **Instead of:** a hidden store.
- **Why:** `state.json`, `config.toml` and `index.sqlite` can be read, copied and deleted by their owner. The search index holds sessions that exist nowhere else, so a schema change migrates and only an unknown schema starts over.

### Logs hold no user text

- **Instead of:** logs that help by quoting.
- **Why:** the trace records states, sources, counts and agent names, never what a user or agent wrote. Dump Logs holds ids, states and counts only, so a user can attach it to an issue.

### One socket is the only door in, and one Calm owns it

- **Instead of:** a port, or a second channel for hooks.
- **Why:** the socket sits in Calm's support folder with mode 600. A request is one line of JSON with a version, and a request from a newer `calm` is refused with a note to update. A Calm that starts while another answers on the same socket quits at once (since 2026-09-30), because a second copy took the socket and left it dead on quit, and every hook was refused. A running Calm checks that the path still leads to its listener.

### A hook never fails the agent, and never starts Calm

- **Instead of:** reporting errors to the agent.
- **Why:** hooks run in every terminal, and an agent must not break because Calm is closed. `status`, `notify` and `hook` exit 0 and do nothing outside a Calm session. They give up on the socket after one second and on their input after one second, and `calm hook` reports nothing for a payload over 16 MB. A stalled client times out, so a silent client cannot hold up every hook.

### The app never writes where the caller's shell might not be allowed

- **Instead of:** writing the caller's file from the app.
- **Why:** macOS gives each process its own folder permissions. `calm screenshot` returns the PNG over the socket and the CLI writes the file.

### The first launch asks for every permission once

- **Instead of:** asking when a feature first needs one (decided 2026-10-12).
- **Why:** no prompt then arrives in the middle of work. Reading a guarded folder is what makes macOS ask, so Calm reads Documents, Desktop and Downloads one after another and records that it asked. Afterwards guarded folders are read only when the user opens them.

### The update installer is the install script

- **Instead of:** Sparkle, or a copy of the logic in Swift (decided 2026-10-12).
- **Why:** `get.sh` already checks the hash, swaps the app and removes the quarantine mark, and a Swift copy would drift. Sparkle needs a signing key, an appcast and a framework, and gains little while the app is signed ad hoc. Calm never installs on its own.

### The signature is ad hoc, and Calm asks for no password

- **Instead of:** a self-signed certificate (decided 2026-09-29).
- **Why:** every `codesign` run then asked for the login keychain password, and an app that asks for a password again and again looks like malware. The cost is that macOS asks for folder access again after each update, until a Developer ID build exists.

## 8. A test never touches the user's machine

Calm runs on the machine of the person who builds it, next to their real sessions, clipboard and agents. A test that touches those once can lose their work. The cost is a layer of test hooks inside the app.

**Ask:** "If this runs on the author's Mac while they work, what can it change?"

### Self-tests run headless, in their own folders

- **Instead of:** a visible window and the real state.
- **Why:** a run never takes the user's focus and never reads their sessions. Each gets its own state file, support folder, config, socket, zmx folder and index, and no Ghostty config, persistence or notifications unless asked. A run quits by itself well past its snapshot delay, because an orphan once ran for hours. The Debug build has its own bundle id, so its defaults, Dock pin and privacy grants are separate from the installed Calm's.

### Everything Calm copies goes through a pasteboard of its own

- **Instead of:** saving and restoring the user's clipboard (2026-09-30).
- **Why:** doing so lost an image the user had copied. In a headless run `NSPasteboard.calm` is private. A real program run in a test can still write the clipboard itself.

### A test starts no real agent

- **Instead of:** typing the command into a real shell.
- **Why:** a headless run logs the resume or fork command, so no test starts an agent on the user's account. Files that agents own are not written unless a test is given scratch folders for them.

### Parsers are tested on real data

- **Instead of:** invented examples.
- **Why:** transcript formats change without notice, so each adapter ships fixture files from real sessions. Captures of real agents stay out of the repository, because they hold conversations.

### A test that depends on the machine says what it assumes

- **Instead of:** a bare assertion.
- **Why:** a CI runner's display is 1× and has system events that a Mac at rest does not. A test that draws pixels or reads the current event states its assumption, and its failure message prints it. A package test that is red must not hide an app test that is red, so each CI step runs whatever the others did (2026-10-06).

### A snapshot draws the model, not an animation in flight

- **Instead of:** reference images.
- **Why:** checks read the log and the snapshot, and a snapshot draws layers at their model values, so a run is repeatable.

## When principles collide

1. **No wrong word.** A state the user cannot believe makes every other feature worthless, so when a guess and silence compete, silence wins (principle 3).
2. **No lost work.** A session outlives the app even when that costs a second process layer (principle 4).
3. **Attention comes with a pause.** The one interrupting state waits for a natural pause rather than breaking a thought, and is never dropped (principle 1).
4. **A test never reaches the user's machine,** even when a real run would be easier (principle 8).
5. **Calm is a guest.** When an agent's door is closed, Calm shows less. The one exception, the trusted scratch folder, was chosen because the question stopped every scratch session (principle 2).
6. **Stays on the Mac.** A convenience that sends text out loses (principle 7).
7. **Cost at rest.** A feature meets its budget or does not ship, which is why Find's whole-session keeper has its own scenario (principle 5).
8. **Reuse.** Calm builds its own only when the existing code cannot do the job, and says why (principle 6).
