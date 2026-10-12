# Designs

This document holds how Calm is built and why: the design principles, modules, data flow, file formats, and every decision with its reason and date. What each feature does is in [FEATURES.md](FEATURES.md), and the code is the reference for the exact shape of each type named here.

## Design principles

- **Local only.** Calm runs no server and has no account. All state is in files on the Mac. Calm goes online for three things only: the daily update check against GitHub releases, the user's agents doing their own work, and what a viewed file links to.
- **A native Mac app.** Swift on AppKit and SwiftUI, and libghostty draws the terminal. Menus, shortcuts and windows follow macOS conventions. macOS 14.5 or later, Apple silicon only.
- **Reuse before building.** libghostty draws the terminal, zmx keeps shells alive, SQLite FTS5 indexes search, and the user's editor edits.
- **The engine stays behind one door.** Only the `Terminal` module calls GhosttyKit. `CalmKit` holds the logic and imports no UI framework, so the logic is tested without a window.
- **Patch the engine as little as possible.** Each patch is one small file, worth offering upstream. Patches taken from the Ghostty fork stay unchanged.
- **One adapter per agent.** Everything specific to one agent lives in its adapter in `CalmAgents`. The rest of Calm never names an agent.
- **Work through the agent's own door.** Calm changes an agent only through the agent's plugins, hooks and settings, never by intercepting its keys. A file in an agent's config folder is written only after the user connects the agent or turns a setting on, and Calm can undo it. One exception: Calm marks its scratch folders trusted in `~/.claude.json` without asking.
- **Read agents' data, do not own it.** Calm reads transcripts and databases where the agents keep them, read-only, and indexes a copy of the text.
- **Fail quietly.** When Calm cannot read something an agent wrote, it shows less (no recap, no title) and the session keeps working.
- **Never block on the outside world.** Work on files, git, zmx and the agents runs off the main thread. Calls that can hang (zmx, a control client, the update installer, the launch pass) also have a time limit, so a stuck process cannot freeze Calm.
- **Sessions outlive the app.** zmx holds every shell. Quitting Calm detaches it, and launching reattaches with scrollback and running programs.
- **Nothing moving costs nothing.** At rest Calm redraws nothing. Motion runs as Core Animation layers, and every animation comes to rest. `mise run perf` holds this to the budget in GOALS.md G6 and G7.
- **Plain files.** State is `state.json`, settings are `config.toml`, search is `index.sqlite`. Calm keeps keys it does not know when it writes `config.toml`.
- **Logs hold no user text.** Traces record states, sources, counts and agent names, never what a user or agent wrote.

## Tech stack

| Layer | Choice |
|---|---|
| Language | Swift 6, strict concurrency checking on |
| UI | SwiftUI for chrome (sidebar, panels, settings, search). AppKit for windows and the terminal view |
| Terminal engine | libghostty, used through the GhosttyKit framework |
| Storage | JSON for app state (`state.json`). SQLite FTS5 for the search index |
| Build | XcodeGen (`project.yml`) + `mise` tasks |
| Quality | swiftformat, swiftlint, Swift Testing |
| Minimum OS | macOS 14.5 or later, Apple silicon only (`ARCHS: arm64`). Lowered from macOS 26 on 2026-10-12 |

- Calls newer than macOS 14.5 sit behind `#available`. macOS 15 and later keep their own behavior.
- The macOS 14 fallbacks are `Window/ScrollCompat.swift` and `Window/CaretField.swift`.

**GhosttyKit source.** Calm builds GhosttyKit from upstream Ghostty (`ghostty-org/ghostty`) at the commit pinned in `scripts/ghostty.env`, with the patches in `scripts/ghostty-patches` applied.

- Zig is the version Ghostty requires, pinned in `mise.toml`. Local builds and CI build the same way.
- Calm uses no prebuilt binaries and no fork as the source. The patches are reviewable files in this repository.
- `scripts/ghosttykit.sh` checks out the commit and applies the patches in name order. A patch that does not apply stops the build.
- It builds `GhosttyKit.xcframework` (native arm64, ReleaseFast, no i18n, no Sentry) and Ghostty's resources (themes, shell integration, terminfo).
- It caches them per commit and patch set in `~/Library/Caches/calm/ghostty/<commit>-<patches hash>`, then copies them into `Frameworks/` (not tracked).
- `scripts/ghostty-deps.py` prefetches Ghostty's Zig packages with curl into the project-local `zig-pkg/`, because Zig's HTTP client fails behind some local HTTP proxies. Its mirror is under Distribution → CI.
- Calm pins a Ghostty `main` commit, not the v1.3.1 release: v1.3.1 needs Zig 0.15.2, which cannot link against the macOS 26.5 SDK. Move to the next Ghostty release once it supports Zig 0.16.
- Building needs Xcode's Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`) for Ghostty's shaders.

**Engine patches.** Smooth scrolling is taken unchanged from `thdxg/ghostty`, a Ghostty fork (MIT) (decided 2026-09-29). Upstream has only the first piece (RenderState overscan, ghostty-org/ghostty#14400), and the fork's patch carries fixes found by measuring rendered frames.

- The Ghostty pin follows the fork. `GHOSTTY_COMMIT` is the upstream parent of the fork commit the patches come from (`GHOSTTY_PATCHES_FROM`), so the patches always apply.
- `scripts/ghostty-patches/README.md` says what each patch does in detail and how to move to a newer Ghostty.
- Drop a patch once upstream covers it.
- Calm's own patches start at 0007. Each is a separate small file.

| Patch | Source | What it does |
|---|---|---|
| 0005 | fork | The `smooth-scroll` key: pixel scrolling, region scroll animation, the resize remainder (Motion in the terminal) |
| 0006 | fork | A custom shader's `iCursorVisible` is 0 while the cursor is scrolled out of view or blinked off |
| 0007 | Calm | `read_text` reports a row where smooth scrolling draws it, so link marks and cell hit-testing stay on their rows |
| 0008 | Calm | A region scroll leaves an overlay that the program redraws in place (Claude Code's "Jump to bottom" hint) out of the animation |
| 0009 | Calm | The padding beside a row extends only when the row's first or last three cells share a background, or the row above or below has that color at the edge |
| 0010 | Calm | Animates a program that moves its content by repainting rows (pi's full-screen view), by finding the rows that moved |
| 0011 | Calm | A link under ⌘ works while a program has the mouse captured (Claude Code's full-screen view, vim, htop) |
| 0012 | Calm | Pins only an overlay's cells, not its whole row, so the text on that row slides with the rest |
| 0013 | Calm | A surface's command starts at the size and text size Calm passes in, not at an 800×600 placeholder (Persistence) |
| 0014 | Calm | `custom-shader-animation = cursor`: the shader's animation loop runs only for a second after the cursor or the focus changes |
| 0015 | Calm | 0010 moves a pane painted in one color (OpenCode) whole, and leaves a scrollbar or sidebar beside it still |
| 0016 | Calm | Draws a region scroll's frames only when its content has moved another pixel |
| 0017 | Calm | Keeps the renderer thread's animation timer off while the display link draws every refresh |
| 0018 | Calm | `ghostty_surface_alternate_screen` (Find) |
| 0019 | Calm | `ghostty_surface_mark_search_match` (Find → Regular expressions) |
| 0020 | Calm | Reads the primary screen while the alternate screen shows (Find → The whole session) |
| 0021 | Calm | Reports a synchronized update, so a read can wait for its end (Find → The whole session) |

## Project layout

```
project.yml              XcodeGen spec (generates Calm.xcodeproj, not tracked)
mise.toml                toolchain pins and tasks
install.sh               builds a Release Calm and installs it
Calm/                    app target (AppKit + SwiftUI), in the folders of the module map below
CalmTests/               app-hosted tests (code that needs AppKit or the engine)
CLI/                     the `calm` command-line tool
Packages/CalmKit/        UI-free Swift package (see the module map)
scripts/                 GhosttyKit and zmx builds, xcodebuild wrapper, self-tests and their fixtures,
                         theme and app-icon generators, viewer assets, license texts
Frameworks/              built GhosttyKit, Ghostty resources and zmx (not tracked)
.github/workflows/       CI
```

Ghostty's resources are copied into `Calm.app/Contents/Resources/{ghostty,terminfo}` at build time. `GHOSTTY_RESOURCES_DIR` points at them unless it is already set.

## Module map

```
Calm (app target)
├── App          launch, menus, Dock icon, Restart, motion, interface size, self-test hooks
├── Terminal     GhosttyKit wrapper: engine, config and themes, surfaces, input, clipboard, links
├── Sessions     SessionManager, SessionProbe, zmx, shell integration, agent hooks,
│                notifications, search service, sidebar and cards, agent marks
├── Window       main window, title strip, files column and viewer, ⌘K panel, ⌘P palette, switcher, welcome page
├── Settings     the Settings page and its sections
└── Control      local socket server for the `calm` CLI
calm (CLI target, module CalmCLI)   talks to Control through CalmControl
CalmKit (Swift package)
├── CalmModel    workspace and its store, attention, settings, themes, links, Copy Cell, file tree, release feed
├── CalmAgents   one adapter per agent: detection, hooks, transcripts, setup, marks, resume and fork
├── CalmSearch   transcript index and ranking
├── CalmControl  socket protocol and client
└── CalmSQLite   the system SQLite behind a small wrapper (package-internal)
```

Rules:

- **CalmKit** has no dependency on SwiftUI, AppKit or GhosttyKit, so it is fully unit-testable (`swift test`).
- **Terminal** is the only code that touches GhosttyKit, apart from two app-hosted tests.
- Each **CalmAgents** adapter is self-contained. Adding an agent never changes the core.

## Data model

Behavior: FEATURES.md → F2.

In CalmModel (`Workspace.swift`, `AgentRun.swift`, `SessionState.swift`):

- A `Project` is a sidebar group: a folder, a name, and a kind. The user makes a `.project`, grouping makes a `.directory`, and `.scratch` holds scratch sessions.
- A `Session` is one shell. It has its folder and group, whether it stays pinned there, its `SessionState` (idle, working, needs you, done, failed) with the `StatusReport` behind it, the user's name for it, and a scratch session's hidden folder.
- A session's id is exported to the shell as `CALM_SESSION_ID`.
- While an agent runs in the foreground, the session holds an `AgentRun`: the agent, its process, its own session id and transcript, the options a resume keeps, and the latest `TranscriptTail`.
- The options are read from the agent's argv when the probe sees the process. The tail holds the title, recap, step, progress, interruption and the agent's folder.
- When the agent exits, its `AgentConversation` stays as `lastConversation`, options included, so it can resume as it was started.

Panes and tabs are views of sessions: a layout tree references session IDs.

- Closing a pane closes its session and ends its shell (`SessionManager.closeSession`). Quitting Calm detaches shells instead.
- `Workspace` holds `projects`, `sessions` and `layouts` (M2). A `PaneLayout` is one tab: a `SplitTree<Session.ID>` plus the focused session.
- Every session is one pane. So a split creates a session, and ⌘T creates a session with its own layout.
- Calm has one main window. "New window" requests from libghostty become new sessions, since the sidebar replaces windows and tabs as the way to hold many shells.
- Which sessions share a layout is not fixed at creation. `Workspace.join` puts a session beside another in that one's layout, `takeOut` gives a pane a layout of its own, and `unsplit` does that for every pane but the focused one.
- None of these touches a session or its shell.

## Auto-grouping

Behavior: FEATURES.md → F2.

**Where the folder comes from.**

- The shell reports its working directory (OSC 7, through libghostty's pwd action).
- For panes that never send OSC 7, `SessionProbe` reads the shell's folder with `proc_pidinfo(PROC_PIDVNODEPATHINFO)` every 2 seconds.
- The shell's pid comes from `zmx list` for persistent sessions, looked up only when unknown. Otherwise it comes from `ghostty_surface_foreground_pid`.
- `zmx list` runs off the main thread, at most every 5 s, and is ended after 10 s (since 2026-10-12), so a stuck zmx cannot freeze the window. Its answer is used from the next tick.

**Refiling.**

- On a change, Calm refiles a session that is not pinned. It goes to the most specific project the user made that contains the folder.
- Else it goes to the directory group keyed by the git repository's root, or by the folder itself outside a repository. Calm makes the group when needed.
- A directory group matches its key exactly and never contains other folders. Containment let an automatic home-folder project swallow every session under `~`.
- Pinned sessions stay: those started in a project (`Placement.project`, and ⌘T or splits inheriting it) and scratch sessions (`Placement.scratch`, only from ⌘⇧N).
- ⌘T or a split from a scratch session opens a directory session at home, so a scratch folder is never shared by accident.
- Moves animate in the sidebar (`matchedGeometryEffect`, so a row glides between groups). Empty directory groups and an empty scratch group are removed.
- With `auto-grouping = false` under `[sidebar]`, Calm still records the folder, but the session stays where it is.
- At launch, `refileAll` files every unpinned session again, so a workspace saved under older rules finds its groups.
- State files from before kinds (`isAutomatic`) load as `.directory` or `.project`. Both keys are written, for older builds.

**Scratch folders.**

- They live under `~/.local/share/calm/scratch/`, named by time and never shown.
- They are not in a temporary directory, which macOS clears.
- They are not in Application Support: a working folder's path shows in the prompt and reaches every tool, and the space in "Application Support" trips tools that do not quote paths.
- The path is fixed, next to `~/.config/calm`. It is not read from `$XDG_DATA_HOME`, which an app opened from the Dock does not see.
- Folders made before this rule stay where they were. A session keeps its folder's full path, and the files column knows a scratch session by its session, not its path.
- The root is excluded from Time Machine. The exclusion is set on the root only, because it travels with a moved item, and a folder kept as a project must be backed up.
- Self-tests and unit tests keep theirs under their own support folder.
- Closing the last session in a scratch folder removes the folder when empty, or moves it to the Trash after asking.
- Keep as Project… moves the folder where the user picks. The shell stays inside it, and only its path string is stale until it runs `cd`.
- Claude Code trusts the root (Agents → Trusted scratch folders).

**First screen.**

- No session opens at launch. The first launch (no state file yet) shows the welcome page.
- A later launch restores what was open, or the welcome page when nothing was.
- Self-tests start with a home session unless `--welcome`. What the page holds is in Search → Welcome page.

**Project marks.** `Identicon` (CalmModel) makes a project's mark from its name: a 5×5 grid mirrored left to right, in one of eight hues spread around the wheel.

- A hue taken straight from the hash bunched up, so the hues are fixed steps.
- The hash is FNV-1a, not Swift's `Hasher`, which is seeded per process: a mark must stay the same across launches.
- Clicking the mark stores a random `Project.markSeed`, mixed into the hash, so the new mark is kept.
- `GroupMark` and `IdenticonTile` draw it in the sidebar, the title strip and the welcome page.

**Folded groups.** `GroupSummary` (CalmModel, unit-tested) turns a group's session states into what its folded line draws.

- It gives runs, most urgent first. Each run is a mark per session up to `markLimit` (3), or one mark and the count.
- Idle shows only when nothing else is going on.
- A `tally` of every state gives the words for VoiceOver and the header's tooltip.
- `GroupSummaryView` draws the runs with the cards' own `StateMark`. `compact` shrinks done's check to sit with the dots.
- The view is `.fixedSize()` with a layout priority, so the group's name truncates before a mark is cut.
- The header's amber fill is keyed on `GroupSummary.needsYou`.
- Self-tests fold the focused session's group with `fold_group`.

**Project order** (since 2026-10-10). The sidebar's order is `Workspace.projects`' own, ranked by kind (`orderedProjects`). So moving a project is moving it in that array.

- `Workspace.moveProject(_:to:)` (CalmModel, `ProjectReorder.swift`, tested) puts a user project at a place among the projects and leaves the other kinds where they are.
- `state.json` keeps the order with no new key.
- Folder groups do not drag: they appear and go with their sessions, so an order given to one would be lost.

The drag is drawn without changing the order until release.

- `ProjectReorder` (same file, tested) takes the projects' sections as laid out when the drag began.
- It says how far the dragged section is drawn (held to the projects' block), where it would land (its leading edge past a section's middle), and how far each other section steps aside (the dragged one's height and the gap).
- `ProjectDragModel` (`SidebarView+Reorder`, `@Observable`) holds the drag.
- It gets each section's frame in the list's content coordinates from `onGeometryChange`. The modifier sits after the offset, so it reads where the section is laid out, not where it is drawn.
- It gets the scroll offset from `onScrollGeometryChange`. A list scrolled under the pointer adds to the drag, so the section stays under the pointer.
- Agents' cards change height during a drag. So the sections are measured again whenever one moves, and the dragged one is placed from where its top was when the drag began (`ProjectReorder.travel`).
- Near the list's edges, a task scrolls the list a step a frame through a `ScrollPosition` bound to the scroll view. It stops when the pointer leaves the edge, the list ends or the drag ends.
- `ReorderableSection` is a `ViewModifier` per section that reads the model, so a drag redraws the sections and not the sidebar's body.
- The other sections' offsets animate on their own value. The dragged one follows the pointer unanimated.
- Release clears the drag and moves the project in one `Motion.animate`. Each section's offset going to zero and its place changing cancel out. The dragged one glides the rest of the way.
- The header's `DragGesture` has a 4 pt minimum and is followed in the scroll view's coordinate space, since the header moves with it.
- The gesture is a `highPriorityGesture` over the header's button. Once it moves, the button's click fails. A press that does not move is still a click.
- A `@GestureState` ends a cancelled drag, and so does the header disappearing mid-drag.
- The button ignores a click while the project is dragged or settling (`HeaderDrag.isActive`), in case it hears the release.
- The sidebar's model is the window's, so self-tests reach it. Each peek lays out a list of its own and makes a new model, so a scroll position from a peek's drag does not reach the next peek.
- Self-tests: `project_drag:<name>:<points>[:hold]` and `project_order`.

## Agents

Behavior: FEATURES.md → F4, F5.

**Adapters (CalmAgents).** `AgentAdapter` says what an agent is:

- the names, binary prefixes and package paths its process runs under
- its config folder (present means installed)
- how it connects to Calm (`AgentSetup`)
- its mark, and its resume and fork commands
- variables it wants in the shells Calm starts (`shellEnvironment`: OpenCode's theme, see Themes)
- a theme file Calm keeps in step with its own while the agent is connected (`themeFilePath`, `themeFile(for:mode:)`: OpenCode's and pi's `calm` theme)

An adapter can also adopt `HookReporting` (its hooks call `calm hook <name>`), `TranscriptReading` (find and read its transcript for cards) and `TranscriptIndexing` (search). `Agents.adapters` lists them.

**Detection.** `SessionProbe` looks at every session every 2 seconds.

- A persistent session's shell pid comes from `zmx list`.
- `proc_pidinfo(PROC_PIDTBSDINFO)` gives the terminal's foreground process group (`e_tpgid`). When it differs from the shell's own group, a job runs.
- Only when that job changes does Calm read its path and arguments (`sysctl KERN_PROCARGS2`) and ask the adapters.
- Without zmx, Calm uses the pane's foreground process (`ghostty_surface_foreground_pid`).
- Adapters match on executable or script names, per-platform binary prefixes, and package paths for scripts run by node or bun.
- Agent runs saved by an earlier launch are kept and checked before the window opens (Launch, below).

**Launch** (since 2026-09-29). The sidebar comes back as it was left. Before, `restore` cleared each saved run, and a Restart showed agents idle for up to a minute until their next hook.

- `restore` keeps the saved runs. `SessionProbe.settleSavedRuns` runs before the control server and the window.
- It asks `LaunchPass`, off the main thread: `zmx list`, each saved session's shell foreground job (the probe's own syscalls), `Agents.detect` for the saved kind, and the adapter's `LiveStatusReading`.
- It waits for the pass up to `LaunchPass.budget` (250 ms). One session takes about 3 ms, most of it `zmx list`.
- Claude Code's adapter reads `~/.claude/sessions/<pid>.json`: `status` (`busy`, `idle`, `waiting`), `statusUpdatedAt` (ms) and `waitingFor`. The file must name the pid it is read for.
- No other agent keeps such a file, so other agents settle by the last rule below. Codex and OpenCode then correct themselves at the first regular tick, from their transcripts (`TranscriptTail.stateChange`: a turn that started and has not ended is working).

`Workspace.settleSavedRun` (CalmModel, tested) decides per session from what the pass found.

- The run stays only when the same agent still holds the shell's foreground as the same process, or when the run's process was not known. Otherwise the run ends, as an exit does.
- When the agent's status is newer than the last report (within a second), it corrects the state: *working* while it says idle, and idle, done or failed while it says busy. Its `statusUpdatedAt` becomes the state's start.
- *Needs you* and `waiting` stay with the hooks, until each agent's wording is known.
- With no status to ask, a saved *working* stands only when `state.json` was written under 30 s ago (a Restart). An older one becomes idle.
- The pass also seeds the probe's shell list and foreground jobs. So the first tick does not ask zmx again and does not take a confirmed agent for a new one.

**A shell that went with its agent** (since 2026-10-07, so that a reboot does not leave every agent to restart by hand).

- The pass says whether zmx listed the shells (`Answer.shellsListed`: `zmx list` exited 0).
- A dead session lists with `err=ConnectionRefused` and no pid, so it never counts as live.
- A run whose agent is gone because its shell is gone gets `Session.resumesWhenOpened` (saved, nil otherwise), when the run's own conversation was known.
- `SessionManager.pane(for:)` takes the mark as it makes the session's first pane, and types the adapter's resume command (`type(_:into:)`). Headless self-tests log the command instead.
- The menu's Resume takes the mark first, so the command is never typed twice.
- A failed or late listing marks nothing: `claude --resume` typed into a shell where Claude Code still runs would land in its prompt.

**A slow pass.**

- When the pass misses the budget, `SessionManager.confirming` names the rows, and they show as loading (UIUX.md → Session states → Restoring).
- The answer applies, with the state, when it comes. It is held at least 450 ms after the loading began, so a quick answer never flashes.
- A pass with no answer within 2 s (`LaunchPass.deadline`) is given up. Every saved run then ends.
- Quitting while rows load loses nothing: the saved state changes only when the answer applies.
- The transcript tail is saved with the run, so the first frame has its title, recap and todos.
- The first regular tick reads the transcripts again, off the main thread. An unchanged tail changes nothing.
- Test it with `scripts/selftest.sh --persist --state <file>`, launched again and again on one state file. `CALM_LAUNCH_PASS_DELAY_MS` (debug builds) makes the pass slow.

**Supported agents, and removing one.** Calm supports Claude Code, Codex, OpenCode and pi. omp was removed on 2026-09-29: little use, and not installed to check against.

- Removing an agent must not cost anyone their sessions. So an agent Calm does not know reads as no agent wherever it was saved.
- `Session.init(from:)` decodes `agent` and `lastConversation` leniently, because `WorkspaceStore` starts over with an empty workspace when anything fails to decode. A test covers a saved omp run.
- The search index skips rows whose agent it does not know.
- Follow the same rule for the next removal.

**Research (M3.2, 2026-09-27).** Checked against docs, source and local installs (Claude Code 2.1.283, Codex 0.157.1, OpenCode 2.0.18 beta, pi 0.87.1). None of these interfaces is a stable public contract, so every use degrades quietly.

| Agent | Detection | Transcripts | Status source |
|---|---|---|---|
| Claude Code | argv[0] `claude`. The native binary's kernel name is its version file (e.g. `2.1.283`), so match argv, not `p_comm`. Skip the helpers `claude daemon`, `bg-pty-host`, `bg-spare` | `~/.claude/projects/<start folder, non-alphanumerics → ->/<session>.jsonl`: the folder where the session *started*, so use the hook's `transcript_path`. `user`/`assistant` records; titles in `ai-title`/`custom-title`; todos via `TaskCreate`/`TaskUpdate` with state in `~/.claude/tasks/<session>/` | Hooks (stdin JSON: `session_id`, `transcript_path`, `cwd`, `hook_event_name`): `UserPromptSubmit`, `PreToolUse` → working; `PermissionRequest` (immediate), `Notification` `permission_prompt`/`elicitation_dialog` (after ~6 s idle) → needs you; `Stop` (`last_assistant_message`) → done, or working while `background_tasks` holds a running or pending `subagent` (any other running task is counted as a shell: done, with the count); `StopFailure` (`error`) → failed. An Esc interrupt fires no `Stop`. Hooks block unless `"async": true`. **Install:** a plugin loaded with `CLAUDE_CODE_PLUGIN_DIRS` set only in Calm's shells (v2.1.280+) writes no settings; `claude plugin marketplace add` + `install` also works but writes `~/.claude/settings.json`. Without hooks: desktop notifications (OSC 9/777) and OSC 9;4 progress in Ghostty-based terminals, and the window title |
| Codex | native `codex`; the npm package runs `node …/@openai/codex/bin/codex.js`, which spawns `codex` | `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`: `event_msg` `task_started`/`task_complete` (`last_agent_message`)/`turn_aborted`; plan via `update_plan`. Titles in a versioned SQLite file (fragile). Checked 0.158.0 on 184 real rollouts: `turn_aborted` has `reason: "interrupted"` for Esc; no plan records in any recent one; `session_meta.originator` (`codex-tui` for a terminal, `Codex Desktop` for the app) and `thread_source` (`user`, or `subagent` with an object in `source`: 90 of the 184) say who started it, all in the same folders, while `source` doesn't (a terminal under the daemon says `vscode`); a resumed conversation appends to its old rollout; single records reach megabytes | Hooks (`~/.codex/hooks.json`, `[hooks]` in `config.toml`, or a plugin): `UserPromptSubmit` → working, `PermissionRequest` → needs you, `Stop` → done; no turn-failed event. **Every hook must be approved by the user in `/hooks`.** Legacy `notify` only reports turn complete. **Since 0.157 hooks run inside one shared `codex app-server` daemon, not in the terminal's `codex` (see Codex hooks below).** Without hooks: OSC 9 (or BEL) for approval requests and finished turns while the pane is unfocused |
| OpenCode | native `opencode`; npm `opencode-ai` is a node wrapper. v2 may run the agent loop in a shared `opencode serve` process | SQLite `~/.local/share/opencode/opencode.db` (write-ahead log). Checked 2.0.18: version 2 keeps sessions in `session_v2` and `session_message` (`idle` messages carry `outcome`: `succeeded`, `failed`, `interrupted`); the old `session`, `message`, `part` and `todo` tables have not changed since the upgrade, so they are not read | A plugin in `~/.config/opencode/plugins/`. That was 1.x's API (`event` hooks, `session.status`, `question.asked`); 2.0.19 loads only `export default { id, setup }` modules, and a folder's `tui` entry runs in the terminal's own TUI process, its `server` entry in the shared service (see OpenCode plugin, below). Its own OSC 777 notifications are off by default (`attention.notifications` in `~/.config/opencode/cli.json`, read from 2.0.18's code: `?? false`) and are sent only while OpenCode's terminal is unfocused |
| pi | `pi` (node sets `process.title`; Bun builds are named `pi`); package `@earendil-works/pi-coding-agent` | `~/.pi/agent/sessions/--<folder>--/<ts>_<uuid>.jsonl` (`type: "message"`; checked 0.87.1 on 192 real sessions: an assistant message with `stopReason: "aborted"` is an interruption; records reach megabytes) | Extensions in `~/.pi/agent/extensions/*.ts`, **awaited in order** (Calm's must return at once): `agent_start` → working, `agent_settled` → done, `turn_end.outcome` error → failed. No permission prompts in pi itself |

**Claude Code hooks.** Calm ships the hooks as a plugin that Claude Code loads only in Calm's shells.

- At each launch Calm writes the plugin (`.claude-plugin/plugin.json`, `hooks/hooks.json`) to `~/Library/Application Support/Calm/agents/claude-code`.
- It adds that folder to `CLAUDE_CODE_PLUGIN_DIRS` in the shells it starts, and keeps the user's own entries.
- Claude Code loads it as `calm@inline` in those sessions only. Calm writes nothing to `~/.claude`.
- A self-test's or unit test's Calm writes the plugin to its own support folder (`CALM_SUPPORT_DIR`, `CalmDefaults.isolatedDirectory`), and the `calm` in its shells looks there (since 2026-10-07: before, every self-test rewrote the real plugin).
- Every hook runs `[ -n "$CALM_CLI" ] && "$CALM_CLI" hook claude-code || true`.
- Hooks run synchronously, so reports keep their order. `calm hook` gives up on the socket after 1 s.
- `calm hook` reads the payload on stdin. `ClaudeCodeAdapter.hookReport` maps it, and passes on the agent's session id and transcript path for transcript tails.
- Turn the hooks off with `hooks = false` under `[agents.claude-code]`.

| Hook | Report |
|---|---|
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse` | working, with what it means for the live line (below) |
| `PermissionRequest` | needs you, with "Allow Bash: …" |
| `Notification` (permission, elicitation) | needs you |
| `Stop` | done, with a one-line recap of `last_assistant_message`. Working while `background_tasks` lists a `subagent` in flight |
| `StopFailure` | failed |
| `PreCompact`, `PostCompact` | Compaction (below) |

**Background tasks in a Stop.**

- A `subagent` in flight keeps the session working. It wakes Claude when it ends, and that turn's `Stop` reports again.
- Every other task in flight counts as a shell (decided 2026-09-29): a Monitor arrives as `shell`, and a dev server or watcher never ends, so nothing would wake Claude.
- So the `Stop` is done. The count travels as `shells` on the control request and as `StatusReport.backgroundShells`, for the card's "· 2 shells running". It is not saved, since it is one Stop's snapshot.
- Only `running` and `pending` tasks count. A task with no status counts too, since the list is for work still in flight.
- Only `shell` and `subagent` appear in captured payloads.
- A shell that ends wakes Claude, and that turn's `Stop` reports the count again. So the count stays once the card settles to idle (`Session.shellsStillRunning`, done or idle from a hook, since 2026-10-08).
- The count goes with the next report that has none, or when the agent exits.
- A shell stopped from Claude Code's own task list may wake nothing. The count is then stale until the next turn ends.

**Esc and the status file.** An Esc interrupt fires no hook, in any of the 29 hooked events (2.1.296). That holds for a prompt withdrawn before the model answers, and for a permission prompt or dialog. The agent's status file, `~/.claude/sessions/<pid>.json`, does change. Claude Code rewrites it in place, one inode for the whole session.

- `busy` is written 13 ms before `UserPromptSubmit` runs, and `idle` 10 ms after `Stop`.
- `waiting` (`waitingFor: "permission prompt"`) is written as a prompt opens.
- `idle` follows about 0.4 s after an Esc, in all three cases.
- A turn that ends with a background shell running says `shell`. Then it says `busy` and `idle` when the shell's end wakes Claude.

So hooks begin turns and say how they ended (the recap, the live line, the counts), and the file ends what no hook ends.

- `AgentStatusWatcher` (app layer) keeps one `DispatchSource` file event per Claude Code session. It is attached when the probe sees the agent start or end, never on a timer.
- It reads the file when the file changes. `Session.turnEnded(accordingTo:)` ends a *working* or *needs you* session whose agent says `idle` (`SessionManager.agentStatusRead`, an "Interrupted" hook report).
- No timestamps are compared: the file is read at its change, and `idle` after a `Stop` finds the session already *done*.
- A session at rest costs nothing for this. A missing file leaves the hooks alone.
- `LiveStatusReading.statusFile` is the adapter's part. No other agent keeps such a file.
- Hook fixtures are built from the documented payload fields, except the compaction ones, which are captured. Replace the others with captured payloads.

**Compaction** (since 2026-10-06, because a card showed the old step through a compaction that takes a minute or two). Claude Code summarizes a full conversation on its own mid-turn, or on `/compact`. Captured from 2.1.291:

- `/compact` sends `PreCompact` (`trigger: "manual"`), then `SessionStart` (`source: "compact"`) and `PostCompact` (`trigger`, `compact_summary`). No `UserPromptSubmit` comes before and no `Stop` after.
- An automatic compaction comes between a prompt's `UserPromptSubmit` and the turn's `Stop`, with `trigger: "auto"`.
- Esc during either sends nothing, and the `/compact` stays in the input.

How Calm maps it:

- `PreCompact` → working with `CompactionReport.started`.
- `PostCompact` → done ("Conversation compacted.") for `manual`, and working for `auto`, with `.ended`. An unknown trigger reads as `auto`, which never ends a turn.
- `calm hook` passes it as `compaction` on the control request ("start:manual", "end:auto"). `StatusReport.compaction` carries it, not saved.
- `Workspace.report` keeps a `Compaction` on the session (trigger, start, end, the sizes). It is not saved, so a restart cannot bring back a "Compacting" that ended while Calm was away.
- A hook report that is not *working* while a compaction runs ends it.

The sizes come from the transcript (`ClaudeCodeTranscript`).

- `contextTokens` is the newest `assistant` record's usage: input, cache creation, cache read and output. It matches the compaction's own `preTokens` within 1.4%.
- `lastCompaction` is the newest `compact_boundary` record (`compactMetadata.preTokens`, `postTokens`), written within 10 ms of `PostCompact`.
- A record dated before the compaction began (with 2 s of slack, for one first heard of when it ended) belongs to an earlier compaction.
- Esc leaves only a `user` record (a "local command" caveat). A running compaction writes only bookkeeping (`queue-operation`, `pr-link`, `frame-link`), never a message.
- So `newestMessageAt` (the newest `user` or `assistant` record that is not the compaction's summary) more than 0.5 s after the start, with no record of an end, means it was cancelled.
- A cancelled `/compact` goes back to idle. One begun mid-turn is left to the turn's interruption.

`Session.compactionBar(now:)` (CalmModel, tested) says what the card draws.

- `.full` while it runs.
- `.drained` once over, with both sizes: for `CompactionBar.lingers` (5 s) after an automatic one, and for as long as a `/compact`'s *done* card stays *done*.
- With the end heard and no record yet, it holds `.full`. With no record at all, it goes when a drained one would.
- `compactionBarEnds` is when the bar goes by itself. The card's `.task` moves its clock on then, so nothing redraws on a timer.
- The bar (`CompactionBarLine`, UIUX.md → Session cards) takes the todo bar's place.
- Its breathing is `BreathingFill`, a Core Animation opacity animation (`MotionLayers.swift`) over the SwiftUI capsule. The capsule stays hidden under it at full width, so the drain is SwiftUI's own width animation.
- Only Claude Code reports compaction. Codex's hooks have compaction events. pi and OpenCode were not checked.

**Live line** (since 2026-10-09). A working card says what the agent does (UIUX.md → Session cards), from hooks Calm already hears: no new hook, process or timer.

- `ClaudeCodeAdapter.activity` (`ClaudeCodeActivity.swift`) turns a tool call into `AgentActivity` words ("Reading SessionCard.swift"), with a group ("Reading # files") for a burst.
- A Bash call's own `description` becomes the -ing form through `ActivityWords.ongoing`, only when its first word is on a verb list taken from real Bash calls. Otherwise it stays as written.
- `ActivityWords.program` names the command when there is no description.
- Bookkeeping tools give nothing on both halves, so a step running beside one does not count as ended.
- `HookReport.activity` is an `ActivityChange`: `.began(activity)` for `PreToolUse`, `.ended` for `PostToolUse` and `PostToolUseFailure`, `.thinking` for `UserPromptSubmit`.
- `PostToolUse` fires only for a call that worked (Claude Code's hook docs, 2.1.294). So `PostToolUseFailure` is subscribed too: without it, a failed call left its step running for the rest of the turn.
- A failure carries no state (`HookReport.changesState`, sent without `state`, applied by `SessionManager.noteActivity` while working). Claude can go on or stop, and its next hook says which.
- A failure with `is_interrupt` (Esc) sends nothing and leaves the card to the transcript's interruption.
- `PermissionDenied` is not subscribed: an answered *needs you* already clears the count.
- Each `tool_input` field reads as absent unless it is a string, so an MCP tool's odd input cannot lose the hook.
- `calm hook` passes `activity` ("began", "ended", "thinking"), `activityWords` and `activityGroup` on the control request.

`LiveLine` (CalmModel, unit-tested) is the line over time.

- Words hold for `hold` (2 s). The latest waiting words win, and a burst of one group adds up.
- When no step runs (an `.ended` for every `.began`) and `quiet` (15 s) passes, the line says "Thinking".
- An answered *needs you* clears the count, since a denied call never ends.
- `LiveLine.after` applies a report. A turn from rest starts the line over, its end clears it, and an answer resumes it. The change counts only while working.
- The line is not in the workspace. `SessionManager` keeps a `LiveLineBox` per session (`@Observable`, outside observation itself), and each card observes its own.
- The reason: a workspace write renders the whole sidebar (State machine, below), and two writes per tool call would undo the dedupe of repeated reports. `SessionManagerReportTests` checks that a tool call leaves the workspace alone.
- The card shows `words(at:)` and sleeps until `nextChange(after:)` (`.task(id:)`). It wakes only when held words come due or the agent goes quiet.
- `Session.turnStartedAt` (saved) is when the turn began, for the card's corner (`Session.cornerDate`).
- A prompt starts it over even from *needs you* (`report(newTurn:)`), since a question left with Esc sends no hook and is not part of the next turn.
- A hook also has `SessionProbe.readSoon` read the transcript 0.25 s later, at most as often as the tick. The tick skips a transcript read within 1.5 s of another. Reads come sooner, not more often, because a changed tail writes the workspace.
- The 2 s tick stays. It sees an Esc (no hook says so) and agents coming and going. It reads only a transcript whose size or date changed.
- Self-test: `calm.hook_tool:pre:Read:<file>` (also `prompt`, `post`, `pre:Bash:<description>`) sends the real payload through the adapter and the control handler.
- Open question: whether a subagent's own tool calls fire the parent's hooks. If they do, the line shows them, which is still what the session is doing.

**Teaching agents about `calm`** (designed 2026-10-12, not built). Claude Code's plugin only reports state today. An agent does not know that `calm fork`, `calm show`, `calm search` or `calm config` exist, so it cannot act on "fork this and try the other approach" or "start Claude in a worktree on ⌘N" (CLI.md has the commands).

- **One skill, in the plugin that already exists.** `skills/calm/SKILL.md` sits beside `hooks/hooks.json` and is written at each launch with the other plugin files (`ClaudeCodeAdapter.pluginFiles`). Its name joins `pluginFileNames`, so `calm doctor` checks it.
- It is a Swift string, not a resource file, because the CLI once could not read `Bundle.module` (see `pluginFileNames`).
- Claude loads it only inside Calm, like the hooks. Nothing is written to `~/.claude`. It is on whenever the plugin is on, and `hooks = false` turns off both: no new setting.
- **Why a skill:** Claude Code does not load a `CLAUDE.md` at a plugin's root, so a skill is the only way a plugin carries instructions. Its name and description sit in context every session (cut at 1,536 characters), so the description is two or three sentences and the commands go in the body, which loads only when the skill is used.
- **What it says,** short and in the agent's terms: `calm fork "<prompt>"` to try another approach in a parallel session (`--background` to stay put, never in a loop, and a fork cannot fork). `calm search` then `calm show <id>` to find and read a past conversation. `calm config`, `calm list`, `calm doctor`. Use `calm`, or `$CALM_CLI` when `calm` is not on `PATH`.
- **What it forbids:** `calm status` and `calm notify`. The hooks already report state, and an agent that reports its own fights them (CLI.md → *Not planned*).
- **Permissions:** `allowed-tools` grants a tool for the turn the skill runs in, with no prompt. Only the reads are granted: `calm search`, `show`, `list`, `doctor`, `config list|get`. `calm fork` and `calm config set` still ask, because one starts an agent and the other changes the user's settings.
- **Claude Code only.** The skill belongs to its adapter. Codex, pi and OpenCode have nothing equivalent that Calm owns, and the core never special-cases an agent.
- **Check before building:** whether `allowed-tools` takes the `Bash(calm search *)` form (the docs show `Bash(git add *)`), and whether `$CALM_CLI search` matches a rule written for `calm`.
- **Check before building:** `calm fork` run by the agent mid-turn, while its own tool call still runs (CLI.md → `calm fork`).
- **Check before building:** that Claude picks the skill for the right requests and no others, in a real conversation.
- **Open question:** an agent that forks usually wants the answer back. `calm wait` is in CLI.md → *Not planned*. An agent can read the fork's result with `calm show`. Decide when the skill is used for real.

**Claude Code's pasted images** (since 2026-10-06).

- Claude Code keeps the image behind `[Image #n]` at `<tmp>/claude-<uid>/<cwd, non-alphanumerics → ->/<session>/images/<n>.png` from the paste on.
- `<tmp>` is `CLAUDE_CODE_TMPDIR` (which stands in for `/tmp`) or `/tmp`.
- A `/clear` starts a new session id, but the numbers keep counting (2.1.291).
- `PastedImageResolving` (CalmAgents) gives an agent's tag pattern and finds the image behind a tag.
- Claude Code's resolver goes by the session id in `~/.claude/sessions/<pid>.json` for the running process, which a `/clear` changes at once. Else it uses the hooks' id, which sees a `/clear` only at the next prompt. It looks under the cwd's folder, then under any.
- Calm does not know which run drew a row. So a tag in the scrollback from before `claude` started again in the pane can show the new conversation's image, since numbering starts again at 1.
- The pane matches the tag with `LinkMatcher.matches(of:)`. Its hover, underline, click and marks work as for a link a program cut across rows (`LinkHover.isCalmOwned`).
- The core knows the pattern only from the adapter.
- A Claude Code mod that drew the draft's images above the prompt was dropped on 2026-10-07: ⌘ over the tag was enough, and the mod cost every session a 200 ms poll and a dependency on Claude Code's early-access mods API (git history: `ClaudeCodeMod`).

Self-test:

```sh
env CLAUDE_CODE_TMPDIR="$(mktemp -d)" scripts/selftest.sh images --type "$PWD/scripts/fixtures/agent-images.sh" --after "wait,wait,wait,wait,wait,calm.link_marks,calm.link_press:Image #1]"
```

It logs a mark under `[Image #1]`, none under `[Image #9]` (which has no file), and `link tag Image #1 · 1 × 1 · Open in viewer, thumbnail true`.

**Transcript tails.** Claude Code, Codex, OpenCode and pi each have a `TranscriptReading` adapter.

- `transcript(forProcess:)` finds the transcript.
- `readTail` reads it: the title, the latest agent text as a plain-text recap (`MessageText.recap`), the agent's own summary where it writes one, whether the newest turn was interrupted, and step and progress where the agent keeps todos.
- `changeMarkers` names the files whose size or modification time show a change (OpenCode's `-wal` too).
- `SessionProbe` reads again only on a change, one background read per session at a time. A transcript can hold megabytes of tool output, so reading never runs on the main thread.
- An interruption settles *working* to idle, only when the transcript was written after the latest report. A new prompt's hook can arrive before its transcript line.

*Where the transcript is.*

- What a hook or extension reported wins (`calm hook`, or `calm status --transcript`).
- Otherwise the adapter finds it from the process. It tries every 4 s until it works, and every 20 s after, since an agent's `/new` starts another transcript.
- A different answer is adopted. A failed search never drops a known transcript.
- The adapters share `ProcessFacts` and `TranscriptDiscovery`. `ProcessFacts` holds the process's folder, start time, terminal, arguments, and the files open in it and its children, all from plain syscalls.
- The order: the transcript the process has open, else the agent's own rule, else the only transcript that starts in the process's folder and was written since the process started.
- Two candidates mean unknown, and no transcript is chosen: a card with another conversation's recap is worse than one with none.

*Reading a JSONL file.* `JSONLTail` reads from the end, newest record first, a block at a time.

- It stops after 512 KB of records.
- It passes over any line longer than 512 KB unparsed, up to 32 MB in all. Codex's and pi's tool results reach megabytes, and a reader that stopped at the first such line would show nothing.
- Only the block just read can hold newlines, so only that block is searched, with `memchr`.
- A long line's pieces are joined once. Joining each block to the carry again made long lines quadratic, and Claude Code transcripts carry pasted screenshots as such lines (fixed 2026-09-30).
- `JSONLTailEquivalenceTests` holds the scan to the old scan's records on generated files.

*Turn phase, and state from a transcript.* An agent with no hook or extension cannot tell Calm it works. Codex notifies only for a finished turn or an ask, and only while its terminal is unfocused. OpenCode's notifications are off by default. Their transcripts say it.

- A reader can set `TranscriptTail.turn`: `inProgress`, `finished`, `failed`, or nil when unknown or interrupted.
- `SessionManager.transcriptChanged` turns it into a report through `TranscriptTail.stateChange` (tested as a table).
- A turn in progress moves an idle, done or failed session to *working*. A turn that ended moves *working* or *needs you* to *done* or *failed*.
- It has terminal rank, so an agent's own hook report outranks it. Claude Code and pi never reach it.
- It never overrides a pending *needs you*, since an ask is made mid-turn.
- A reading written before the latest report is stale and ignored, as for an interruption. The finished turn's own desktop notification can arrive first.
- A run that ends mid-turn still settles *working* to idle when the agent exits.

*Claude Code.*

- The process's `~/.claude/sessions/<pid>.json` → `sessionId` finds the file.
- Title: `custom-title` over `ai-title`. Recap: the latest assistant text.
- Summary (`TranscriptTail.summary`): Claude's own "※ recap" of the conversation. It is a `system` record with `subtype: "away_summary"`, written about three minutes after a turn ends. Its trailing hint "(disable recaps in /config)" is dropped.
- The summary counts only while no `user` or `assistant` record is newer, so a new turn outdates it.
- `Session.recap` shows the summary on an idle card and the arrival card only: a done card's latest message is the news.
- Interruption: the newest conversation record is a `[Request interrupted…` user record.
- Folder (`TranscriptTail.directory`): the newest record's `cwd`. Every `user`, `assistant`, `attachment` and `system` record has one.
- The folder changes when Claude enters or leaves a git worktree, which `~/.claude/sessions/<pid>.json` does not show.
- Todos: `~/.claude/tasks/<sessionId>/*.json`. They give done of total, and the in-progress task's `activeForm` as the step.

*Codex.*

- Recap: `task_complete.last_agent_message`, else the newest assistant message.
- Turn phase: the newest turn marker. `task_started` is in progress, `task_complete` is finished, and `turn_aborted` with `reason: "interrupted"` is an interruption with no phase.
- No title: Codex keeps it in a versioned SQLite file. No step or progress: recent rollouts hold no plan records.
- Finding it, first: the rollout the process has open. This works only in embedded mode, because under the shared daemon the daemon holds it.
- Then: the id in `codex resume <id>`. A resumed conversation appends to its old rollout. `fork` starts a new one, so a fork's id is not used.
- Then: the folder rule, counting only rollouts a person started from a terminal (`originator` `codex-tui`, and not a subagent's thread). The desktop app's sessions and subagents' threads sit in the same folders and would make a folder look ambiguous.
- `source` cannot tell them apart (found 2026-09-29): under the shared daemon a terminal's rollouts say `vscode`, as the desktop app's do, and before it they said `cli`.

*pi.*

- `message` records. The newest assistant message with `stopReason: "aborted"` is an interruption. Tool results after it do not hide it.
- The title is `session_info.name`. No todos.
- Finding it: the extension names it on every report. Else the folder rule over `~/.pi/agent/sessions`.

*OpenCode.*

- `session_v2` and `session_message` of `opencode.db`, opened read-only through `CalmSQLite`. Calm never creates or writes it, and a schema that is not OpenCode 2's reads as nothing.
- The title is `session_v2.title`, unless it is the placeholder `New session - <time>`.
- The recap is the newest assistant `text` block.
- The newest record decides the turn phase. `idle` ends a turn: `succeeded` finished, `failed` failed, `interrupted` an interruption. A `user` or `assistant` record with no `idle` after it means the turn still runs.
- No todo records appear in recent use.
- Finding it: the only top-level, unarchived session in the process's folder updated since the process started.
- A `/new` inside one OpenCode makes two such sessions, so without the plugin the first one is kept. The plugin names the session on every report (OpenCode plugin, below).

Opt-in tests read real history and print counts only: `CALM_REAL_CLAUDE_TRANSCRIPT`, `CALM_REAL_CODEX_SESSIONS`, `CALM_REAL_PI_SESSIONS`, `CALM_REAL_OPENCODE_DB`. Headless self-tests use stand-in processes (`argv[0]` set to the agent's name) and a scratch home, with no model call.

**Settings → Agents.** Each adapter declares its `configFolder` (present means installed) and its `AgentSetup`.

| `AgentSetup` | Agent | What Calm does |
|---|---|---|
| `automatic` | Claude Code | The plugin above, with no file in Claude's folders |
| `notifications` | Codex | Nothing: Codex's own notifications |
| `files` | pi | Writes `~/.pi/agent/extensions/calm.ts` on Connect |
| `files` | OpenCode | Writes `~/.config/opencode/plugins/calm/tui.ts` on Connect (OpenCode plugin, below) |
| `hint` | none today | Text for an agent Calm cannot set up |

- The row holds the setup as it stands (`AgentAdapter.currentSetup(home:)`, read again each time Settings shows). An agent whose own config already did the work reads as `notifications`, Connected, and the hint goes away.
- Files Calm writes carry a marker line. Calm refuses to overwrite, and never removes, a file without it.
- At each launch (`AgentIntegrations.prepare`), Calm rewrites a file it wrote earlier when this version's contents differ (`AgentSetupFiles.refresh`). It touches only a file that carries the marker and exists, and never adds one. So a pi extension connected before an update keeps up.
- Settings are written into config.toml by editing only the one line (`CalmSettings.setting`), keeping every other line and comment.

**pi's extension.** API checked against pi 0.87.1's type declarations.

- `agent_start` → working. `agent_settled` → done, failed or idle, by the outcome `agent_before_settle` saw.
- `ui_prompt_start` and `ui_prompt_end` → needs you and back, only for a prompt that opens during a run (between `agent_start` and `agent_settled`).
- A prompt's end goes back to working only when the prompt was counted and the run is still on.
- The reason: pi reports every `ctx.ui.custom` as a prompt, a passive overlay included. pi-briefly opens one at `session_start` and never closes it (pi 0.99.1). Outside a run, a prompt is the user's own doing (a slash command's picker) and holds nothing up.
- pi 0.99.1 emits these events only for the outermost open prompt. So while such an overlay stays open, a real ask during a run is not reported. Calm cannot work around this pi limit.
- Every report names the conversation: `--agent pi --transcript <session file> --agent-session <id>`, from `ctx.sessionManager`. It is read each time, because `/new` and `/resume` change it. A missing or throwing accessor sends no flags.
- Reports are spawned detached, because pi awaits handlers.
- The extension also dresses pi in Calm's theme (Themes → pi wears the theme too).

**Codex hooks** (researched 2026-09-29, decided not to build). Sources: the docs, the source at `rust-v0.158.0`, a local install, and a probe of `hooks/list` in an isolated `CODEX_HOME`.

- *The shared daemon.* Since 0.157 the terminal's `codex` attaches to one machine-wide `codex app-server --managed-daemon`.
- The daemon runs the hooks with its own environment, the first launcher's, kept for every later session. It can carry another app's environment and no `CALM_*` variables. A hook's `$PPID` is the daemon's.
- A payload has `session_id`, `transcript_path` (the rollout), `cwd` and the event, but nothing that names the terminal.
- So a persistent hook can be tied to a Calm session only by folder and time, which two Codexes in one folder make ambiguous.
- Embedded mode (hooks in the terminal's own `codex`, with the shell's environment) is forced by `--no-daemon`, `--profile`, `-c` beyond a small allowlist, and a few other flags.
- *Events (0.158).* `SessionStart` (at the first turn, not when the TUI opens), `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `Stop` (`last_assistant_message`), `Interrupt`, and compaction and subagent events.
- `PermissionRequest` fires only when an approval prompt is about to show, so never with `approval_policy = "never"`. There is no event for a failed turn.
- *Trust.* The user must approve every hook in `/hooks`.
- Trust is a `trusted_hash` (sha256 of the hook's canonical JSON) under `[hooks.state."<file>:<event>:<group>:<index>"]` in `config.toml`.
- Editing a hook untrusts it, and inserting a group before it breaks its key. A wrong hash fails safe: the hook is skipped, with a warning.
- Calm could pre-approve by writing the hash, but the format is internal.
- Hooks and their trust can also pass for one launch with `-c 'hooks={…,state={…}}'`. That touches no user file, but forces embedded mode (a cold in-process server on every launch) and needs a wrapper around `codex`.
- *Where hooks live.* `~/.codex/hooks.json`, `[hooks]` in `config.toml`, a project's `.codex/`, or a plugin. Sources add up. hooks.json rejects unknown top-level keys.
- *Decision (2026-09-29): nothing more.* Codex's own notifications and Calm's transcript tails give state, recap and interruption. Hooks would add immediate *needs you* and *done*.
- Codex's notifications never say *working*. Calm reads that from the rollout (Transcript tails → *Turn phase*), which keeps this decision.
- Rejected: a persistent hook that calls `calm hook codex`, tied by folder only when exactly one Calm session runs Codex there. It edits the user's hooks file and its trust, and gives no answer when two sessions share a folder.
- Rejected: a `codex` wrapper in Calm's shells that passes the hooks by `-c`. It is exact, but slower to start and invasive.
- Revisit if the daemon changes.

**Agent marks.** Each adapter carries its mark as data (`AgentMarkArt` in `<Agent>+Mark.swift`): SVG path data in a view box, fill colors for dark and light (or a gradient), a scale, and a motion kind (`frames`, `turnAndRest`, `pulseGrid`, `build`, `gradientTurn`).

- A `frames` mark carries its agent's own animation as transparent PNGs in the CalmAgents package's `Marks` resources, with their order and frame rate.
- Claude Code's spinner plays this way, because posing its changing shapes from the spark did not look like it.
- `SVGPath` reads the path data (moves, lines, curves, closes). Anything else falls back to the agent's letter.
- `MarkMotion` poses a mark as a pure function of time: looping while working, once for finishing up.
- `AgentLogo` renders it in a `TimelineView` capped at 30 frames a second.
- The timeline runs only while the mark moves, and only while `WindowPresence` says the window can be seen (its occlusion state).
- A working `.frames` mark and the working line's light use no timeline (since 2026-09-30). Each tick of a timeline had SwiftUI lay out and render the whole sidebar, about 2% of a core per working card.
- A nested `NSHostingView` for the mark made it 4× worse, because its frames run a layout transaction on its parent's graph. `.drawingGroup()` changed nothing.
- They are Core Animation layers (`MotionLayers.swift`), which play in the render server with no app work between frames.
- `MarkFramesLoop` is a discrete `contents` keyframe animation of the sequence.
- Each image is drawn once onto the whole tile, where the SwiftUI path draws it (`MarkFrameImages`). An image shrunk to its own pixel size and stretched by the layer came out soft.
- `ShimmerBand` is a `CAGradientLayer` whose `transform.translation.x` keyframes follow `ShimmerText.phase`. SwiftUI's `.mask(Text)` around it masks it to the letters.
- Both take their `timeOffset` from the wall clock, as `MarkMotion.frameIndex` and `ShimmerText.phase` do. So cards side by side agree, and the settling after the work (still a timeline) carries on from the loop's frame.
- A card that becomes visible again starts them afresh.
- The other motions (turn, build, grid, gradient) and every settling still pose in a timeline.
- Cost (2026-09-30, three working cards in view, in instructions): timelines 311–331 M a second, layers 9–12 M, the same as plain shells.
- Idle marks are drawn in the grays of their own colors, not through a grayscale filter.
- `MotionLayersTests` compares the loop's frames with SwiftUI's drawing of the same image. `calm.layer_motion` samples the layers' presentation for 2 s.
- `Session.stateSince` records when a report changed the state. The card stopped showing it on 2026-09-30, when the corner time took over the minutes. It stays saved, for whatever needs a state's start next.

**What this means for Calm.**

- Terminal signals alone cover Claude Code and Codex (M3.5), with no setup.
- Hooks add precision: an immediate *needs you* and exact messages.
- Claude Code's plugin is enabled inside Calm without writing anyone's config.
- pi's extension and OpenCode's plugin are files Calm adds to the agent's config folder only when the user clicks Connect.
- Codex keeps its own notifications, since its hooks cannot tell Calm's sessions apart while its shared daemon runs.
- Transcript tails give every agent a recap and an interruption without any of that.

Open questions: whether `AskUserQuestion` and `ExitPlanMode` fire `PermissionRequest` in Claude Code's interactive mode. Which hook, if any, follows a rejected permission.

**OpenCode plugin** (since 2026-09-30). OpenCode 2 runs the agent in one shared background service (`opencode serve --service`). The service's environment is that of the terminal that first started it, so a plugin in the service would send every OpenCode's reports to one Calm session.

- 2.0.19 loads a plugin folder's `tui` entry in each terminal's own TUI process. `plugin/src/host.ts` resolves `server` or `index` for the service and `tui` for the TUI, with `Bun.resolveSync`. So `tui.ts` loads, and a folder with only that file is never loaded by the service.
- `OpenCodeAdapter.pluginSource` is that `tui.ts`. It uses `context.data.on` for the TUI's events, which it hears for every session.
- It reports only those of the session on its own screen: `ui.router.current()`, with its root through `data.session.root`.
- `session.execution.started`, `succeeded`, `failed` and `interrupted` of that session itself (not a subagent's) → working, done, failed (with the error), idle.
- `permission.asked` and `form.created` anywhere under it → needs you ("Allow <action>", or the form's title). Once every ask is answered, back to working.
- Each report is `calm status --agent openCode --agent-session <root> --transcript <opencode.db>`. So Calm follows `/new`, and tells two OpenCodes in one folder apart, which discovery alone cannot.
- Reports are spawned detached, since handlers run inside the TUI's event batch.
- Every handler is guarded, since the plugin API is young.
- `opencode run` and `mini` have no TUI and keep the files fallback.
- Disconnect removes the file and leaves the empty `calm/` folder, which OpenCode skips.
- The plugin keeps a running OpenCode in Calm's theme. It watches `themes/` (two folders up from itself). When `calm.json` changes, it sends its own process SIGUSR2, which makes OpenCode read its themes again. It does this only while OpenCode has a listener for it (Themes → OpenCode wears the theme).
- Tests run the plugin under Bun against a fake context: the events above, a subagent's, another terminal's, `/new`, the home page, and outside Calm.

**Send with ⌘ Return** (since 2026-10-07). ⌘ Return sends an agent's prompt, and Return starts a new line in it. Calm intercepts no key: each agent rebinds its own prompt, and Calm lets ⌘↵ through.

*The key.*

- Calm's Ghostty defaults (`CalmDefaults`) bind `super+enter` to `text:\r` while the setting is off, and unbind it while it is on. It is never Ghostty's full screen.
- Unbound, Ghostty encodes it from the key and ⌘: `ESC[13;9u` for a program that turned on the kitty keyboard protocol (all three agents do), else `ESC[27;9;13~`.
- zmx passes both unchanged. It replays a program's kitty flags (`ESC[=1;1u`) to the client that reattaches after a relaunch (zmx 0.8.1).
- Self-test: `calm.cmd_return` with a program running `stty raw -echo; cat -v`. Off gives `^M`. On gives `^[[27;9;13~`, and `^[[13;9u` after `ESC[>1u`.

*The agents* (`SendKeys`, one per adapter, applied by `SendKeysFile`):

| Agent | File | Calm's bindings |
|---|---|---|
| Claude Code | `~/.claude/keybindings.json` (or under `CLAUDE_CONFIG_DIR`) | Two blocks, first: `Chat` with `enter → chat:newline` and `cmd+enter → chat:queueSubmit`, and `Autocomplete` with `enter → autocomplete:accept` |
| pi | `~/.pi/agent/keybindings.json` (or under `PI_CODING_AGENT_DIR`) | `tui.input.submit = [super+enter, enter, ctrl+s]`, `tui.input.newLine = [enter, shift+enter, ctrl+j]`, `tui.select.confirm = [enter, super+enter]` |
| OpenCode | `cli.json` under `keybinds` (`cliConfigURL`) | `input.submit = super+return`, `input.newline = return,shift+return,ctrl+return,alt+return,ctrl+j` |
| Codex | none | Its keymap knows only ctrl, alt and shift (0.159.0, 0.160.1). A `cmd-` or `super-` key in `config.toml` stops it from starting |

Why each binding is as it is:

- Claude Code: `chat:queueSubmit`, because `chat:submit` did nothing while a `/` or `@` menu was open.
- Claude Code: the `Autocomplete` block, because otherwise Return closed the menu and added a line.
- Claude Code reads the file again within seconds. A later block of the user's for the same key in `Chat` wins, and the row says so.
- While Claude works, a ⌘↵ message is queued and handed to Claude as soon as the running tool call finishes, within the turn, as a Return message always was.
- Claude Code's docs say the same of both `chat:submit` and `chat:queueSubmit`: queued messages reach Claude after the current tool calls, and only slash and `!` commands wait for the turn to end.
- `queueSubmit` never interrupts the turn, unlike `chat:sendNow` (⌃↵). No key holds a message until the turn ends.
- pi: Return stays in `submit`, because the editor checks `newLine` first, while one-line inputs (login, rename) check only `submit`.
- pi: ⌘ Return confirms lists. Otherwise, with the `/` menu open, it sent the half-typed name as a prompt.
- OpenCode: ⌥ Return stays among the newline keys. Otherwise opentui's default for it sends.
- Beyond the prompt, in Claude Code and pi, Return in the `/` menu fills the command in, and ⌘ Return runs it.
- An empty Claude Code prompt takes a blank line. Claude Code's vim NORMAL mode splits the line on Return. pi's multi-line editor dialog (`ctx.ui.editor`) follows the prompt.
- Return is unchanged in the three agents' questions, permission prompts, pickers and menus (checked 2026-10-06 with Claude Code 2.1.291, OpenCode 2.0.20, pi 0.99.1, Codex 0.159.0).

*Writing the files* (`SendKeysFile`).

- Plain JSON only. A file with comments (pi and OpenCode accept them), or one that does not parse, stays as it is, since rewriting would lose them.
- On adds Calm's bindings and nothing else. Off removes exactly those: a block or value that still matches Calm's. A file left with nothing else is deleted.
- pi and OpenCode take an action's value whole. So a value the user set for any of the three (pi) or two (OpenCode) actions keeps that agent as it is.
- Files are rewritten in a fixed layout (`JSONText`: two-space indents, sorted keys, `$schema` and a block's `context` first). A user's own formatting of these files does not survive a change.
- Calm applies it at launch (an agent installed since gets it) and when the switch changes.
- Self-tests and unit tests never write (`CALM_AGENT_FILES=none`).
- The files are the agents' own, so the change holds in every terminal. Where ⌘ never arrives, ⌃X ↵ sends in Claude Code and OpenCode (their defaults), and ⌃S in pi.

*zsh.* A shell that gets an unbound ⌘↵ beeps and types `;9;13~` (zsh 5.9).

- Calm's zsh startup (`ShellIntegration.zshStartup`, Persistence → Shell integration inside zmx) binds both sequences to what Return does there. It binds them at the first prompt, in the emacs, viins and vicmd keymaps.
- Shells started before the update keep running without it (zmx).
- So do bash, fish, and plain shells (persistence off), whose integration libghostty injects itself.

**Trusted scratch folders** (since 2026-10-11). Claude Code asks "Is this a project you trust?" the first time it starts in a folder. Every ⌘⇧N stopped at it, and each answer left an entry in `~/.claude.json`.

- Calm marks the scratch folders' root trusted, once.
- `AgentIntegrations.trustScratchFolders` runs at each new scratch session until it holds, whichever agent starts. It works through `AgentAdapter.trust` (nil for every agent but Claude Code) and `ClaudeCodeConfig`.
- *Why one entry covers them* (2.1.296's code). Claude Code reads `projects["<folder>"].hasTrustDialogAccepted` for the folder it starts in, then for each folder above it. It stops at the folder's git repository root.
- Scratch folders are not repositories, so the root's entry covers them. One that becomes a repository asks again.
- *Writing a file Claude Code owns.* No command sets trust: `claude config` is gone, and `-p` skips the dialog without saving an answer.
- `CLAUDE_CODE_SANDBOXED=1` in the shell would skip it, but for every folder the shell later moves to, and it changes other behavior. So it was ruled out.
- Every running Claude rewrites the whole file now and then. So Calm edits it the way Claude Code does: under its lock (proper-lockfile's directory `~/.claude.json.lock`), reading the file again once the lock is held.
- Calm replaces the file in one rename, with its permissions kept. A linked file's target is replaced, and the link stays.
- A held lock is waited on for up to 200 ms and never broken.
- The entry is the one Claude Code writes when the user accepts (2.1.296's defaults).
- Foundation's JSON keeps every value. The layout and key order change until Claude's next save.
- Known risk: 2.1.296 has a second way of saving its config behind a flag (a storage backend), whose lock was not found. A Calm write and such a save in the same few milliseconds can lose one of the two changes. Calm writes once per Mac.
- *Left alone:* a missing config (Claude Code makes it at first run), one that is not plain JSON, and a `CLAUDE_CONFIG_DIR` set only in shell startup files. Calm reads its own environment, as Send with ⌘ Return does.
- Self-tests and unit tests never write (`CALM_AGENT_FILES=none`).
- Scratch folders trusted one by one before this keep their entries.

Transcript formats are undocumented and change between versions. Each adapter ships fixture files from real sessions and tests against them. A parse failure degrades to "no transcript", never a crash.

## Attention

Behavior: FEATURES.md → F5.

**State reporting.** Every shell Calm starts gets `CALM_SESSION_ID`, `CALM_SOCKET` and `CALM_CLI` (the bundled `calm`) in its environment.

- A hook reports with `"$CALM_CLI" status <state> [message]` (pi's extension), or hands its payload to `"$CALM_CLI" hook <agent>` for the adapter to read (Claude Code's plugin). Either sends a `status` request over the socket.
- States are `working`, `needs-you`, `done`, `failed` and `idle`. Synonyms (`waiting`, `error`, `stop` and others) let hook scripts use their agent's words.
- Hooks run on every turn and in every terminal. So `status`, `notify` and `hook` exit 0 and do nothing outside a Calm session or when Calm is not running. They never launch it.
- They give up on the socket after 1 second (`scripts/cli-hook-check.sh` checks this). `hook` gives up on its stdin after 1 second too (Control protocol).
- What each agent needs is under Agents → Settings → Agents.
- Whatever an agent starts inherits those variables. So a `status` request that names an agent (`agent`) is checked against the session's foreground.
- `SessionProbe.foregroundAgent` reads the process holding the terminal now (`Agents.detect(processID:)`).
- `AgentKind.speaksForSession` drops the whole request, state included, when a different agent is recognised there (since 2026-09-30, after Claude Code's Bash tool running `pi -p` turned the row into pi's).
- With nothing recognised in the foreground, the request stands. The trace notes each dropped request (`ignored`).
- Open: one agent of the same kind starting another (`claude -p` inside Claude Code) is not told apart.

**Fallback signals.** When no hook is installed, signals come from libghostty's actions. `Terminal` translates them into `TerminalSignal`, and one pure function reads them (`TerminalSignal.outcome`). Their source is `terminal`, so hooks still win.

| Signal | In an agent session | In a plain shell |
|---|---|---|
| OSC 9;4 progress set / indeterminate | working | working |
| progress removed | done (if it was working) | idle (if it was working) |
| progress error | failed | failed |
| OSC 9 / 777 notification | read by its words: permission, approval, allow, confirm, question → *needs you*; error, failed → failed; "waiting for (your) input" and anything else → done. Only an explicit ask can notify | passed on as a notification (at the next pause, if you're elsewhere) |
| bell | *needs you*, only if the agent was working | ignored |
| command finished (OSC 133) | ignored (the agent run ends when it exits) | done or failed, if it ran 10 s or longer |

- Window titles are not used: agents' title formats vary and change.
- Calm never plays the system beep for a bell. Ghostty's default is silent too.

**State machine.** Per session: `idle → working → (needsYou | done | failed) → idle`, once the user leaves it.

- Reports are idempotent, and the latest report wins. Terminal guesses never override a hook report from the same agent run. The run ends when the agent exits.
- Most reports repeat themselves. Claude Code's `PreToolUse` and `PostToolUse` say *working* on every tool call and name the session and transcript again.
- So the manager applies each report to a copy of the workspace and writes it back only when it changed (`SessionManager.changeWorkspace`).
- The reason: a mutating call on the observed `workspace` notifies every view that reads it, even when nothing changes. A sidebar render cost 13 to 20 million instructions per report (measured 2026-10-07). A repeat now costs under a million (`SessionManagerReportTests`).
- Each session keeps its last `StatusReport` (state, message, source, time) for cards and the arrival card.
- Applying a report returns an effect: *notify* only for a new *needs you* in a session the user is not looking at, and *withdraw* when a session leaves *needs you*.
- A finished session stays *done* or *failed* while the user reads it, even the one on screen.
- It settles to idle when the user leaves it: another session selected, a new session or split opened, or another app in front.

Calm losing the front is not leaving (since 2026-09-30: a screenshot tool that took the front for a second settled the done card being read). The app that comes to the front decides (`LeavingCalm`, CalmModel, unit-tested, fed by `NSWorkspace.didActivateApplicationNotification` in `AttentionCenter`).

- An app with a Dock icon (activation policy `.regular`) settles the session on screen.
- A menu-bar tool (`.accessory`, for example Snipaste, Maccy, Spotlight) is remembered with what Calm showed. Coming back to Calm forgets it.
- Going on from the tool to a regular app settles that session, when it is still on screen in the same state. A session that finished while the tool was in front was not seen.

**Notification scheduling.**

- Only `needsYou` in an unfocused session produces a notification (configurable).
- A breakpoint detector watches keystrokes and focus changes. A notification goes out when the user has not typed for a short interval, switches focus, or after a maximum wait. It is never dropped.
- Delivered notifications are removed when the session is visited.
- `AttentionQueue` (CalmModel, unit-tested) holds one notification per session (M3.9).
- A pause is 3 s without typing (a local key monitor, so only typing in Calm counts), any focus change (session or app), or 60 s at most.
- `AttentionCenter` delivers through `UNUserNotificationCenter` with no sound and one identifier per session. A newer message replaces the older one, and visiting removes it.
- It skips a notification when the user is looking at the session by then.
- Clicking a notification focuses the session.
- Self-tests set `CALM_NO_NOTIFICATIONS=1` and only log.

**Permissions at first launch** (decided 2026-10-12, so that no prompt arrives in the middle of work). `FirstLaunchPermissions` runs once.

- It asks for notification permission, then reads Documents, Desktop and Downloads one after another. Each step waits for the answer before.
- Reading a guarded folder is what makes macOS ask: there is no call to ask in advance.
- macOS keeps each answer. Calm records `askedForPermissions` in its defaults and never asks again.
- Removable and network volumes, and Full Disk Access, cannot be asked for in advance.
- Tests, self-tests and headless runs never ask.

**What a notification says** is `NotificationText` (CalmModel, unit-tested).

- The title is the state mark + `session.displayTitle`. There is no subtitle. The body is a pick from the message.
- `AttentionQueue.Item` carries the state with the message. The state is nil for `calm notify` and a plain shell's own notification, which get no mark.
- It reads the message as it is. It flattens lines and splits sentences at `. ? !` followed by a space, or at the full-width terminators U+3002, U+FF1F, U+FF01.
- It measures width in columns: East Asian wide characters and emoji count two. The limit is 100.
- *Needs you* takes the last question. Other states take sentences from the start while they fit.
- A single long sentence is cut at a word with "…".
- Self-tests: `report_away:<state>[:<message>]` after `calm.new_session` (a session other than the focused one reports, and `\n` in the message is a line break). Then read `calm-selftest: notification <title> | <body>` from the log.

**Making an agent's words plain** is `MessageText.recap` (CalmModel, unit-tested). Calm applies it where prose enters, so the card, the arrival card, the sidebar tooltip and the notification get the same text. It applies to:

- the Claude Code `Stop` message (`ClaudeCodeAdapter.hookReport`)
- Claude Code's transcript tail (`ClaudeCodeTranscript`)
- an agent's OSC 9/777 notification body (`TerminalSignal.outcome`, which passes `asking` for a *needs you*)

The rules:

- It drops fenced code, rules, tables and headings. A heading is used only when nothing else is left.
- It reads `#`, list and quote marks at the start of a line, and joins list items as "a; b".
- Markdown that arrives flattened (OpenCode sends its answer on one line) is split at ` ##`–` ######` marks. A flat line does not say where a heading ends, so its label stays glued to the first sentence.
- A scanner removes decoration: backticks, `**bold**`, `~~strike~~`, links. It protects code spans, and reads a mark as decoration only where it clearly wraps words. So globs (`**/dist`), `2*3` and `__init__` stay.
- Single `*` and `_` are never touched (since 2026-09-29: a first version turned `find -name '*.py'` into `find -name '.py'` in a permission banner).
- It cuts at 280 columns, at a word.
- It must be idempotent: the notification reads a `needsYou` message again.

Left alone on purpose:

- The `Allow <tool>: <command>` text of a permission request, a `Notification` hook's own text, `StopFailure`'s error, a plain shell's notification, and `calm notify` and `calm status` messages.
- They are Calm's text or quote a command, and a command must reach the screen exactly: hiding the backticks of `` echo `date` `` would hide what runs.
- An ask classified from an OSC body keeps its inline marks for the same reason (`asking`).
- User prompts (search index, resume titles) keep `HookReport.recap`, which only flattens.

## App icon

**The icon file.** `Calm/Resources/AppIcon.icon` is an Icon Composer document, written by `scripts/app-icon.py`.

- It has one flat layer per part (ring, center, cursor, and the light icon's glow). Each layer has a light and a dark color, over a light or dark gradient tile. Liquid Glass is off.
- XcodeGen (2.45.1 and later) adds `.icon` folders as Icon Composer files.
- With `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`, Xcode compiles it (actool) into `Assets.car`, with light, dark and tinted renditions, plus an `AppIcon.icns` for places that want a plain image.

To check a change, render it with Icon Composer's `ictool`, which ships inside Xcode:

```sh
…/Icon Composer.app/Contents/Executables/ictool AppIcon.icon --export-image --output-file out.png --platform macOS --rendition Default|Dark --width 512 --height 512 --scale 1
```

**The dev build's icon and name.**

- `BuildVariant` (`Calm/App/BuildVariant.swift`) is `#if DEBUG`. Debug is what the self-tests and `mise run run` build. `install.sh` builds Release.
- `scripts/app-icon.py` writes a second document, `AppIconDev.icon` (violet on a cool tile).
- `project.yml` gives the Debug configuration `ASSETCATALOG_COMPILER_APPICON_NAME = AppIconDev` and `APP_DISPLAY_NAME = Calm Dev`. Info.plist reads the latter for `CFBundleName` and `CFBundleDisplayName`.
- Only the named icon is compiled, so a Release bundle holds no dev icon.
- `DockIconView` picks its dev palette from `BuildVariant.isDev`. Keep it and `AppIconDev` together.
- `PRODUCT_NAME` stays Calm: the scripts and tests find the app and its process by that name.
- Menus, alerts and the window's fallback title take `BuildVariant.appName`.
- Debug also sets `PRODUCT_BUNDLE_IDENTIFIER = com.jinhuang.calm.dev`, so macOS tells the two apps apart: a pinned Dock tile, `UserDefaults`, notification and privacy grants.
- `BuildVariantTests` checks that the bundle and the Swift agree.
- The state folder and control socket are still shared (UIUX.md → The dev build).

**Dock states.**

- *Model.* `AppIconState.summarizing` reduces the sessions' states to one.
- `AppIconMotion` (CalmModel, unit-tested) turns state changes into frames. It is pure, so a frame is a function of time.
- `AppIconFrame.places` gives each of the ring's twelve places its cell and cursor strength.
- *Drawing.* `DockIcon` (App) follows the workspace through Observation.
- While the icon is not idle, `DockIcon` sets `NSApp.dockTile.contentView` to a `DockIconView`. The view draws the frame with Core Graphics on the 1024-point grid: the tile at 100…924, a superellipse for the continuous corners, in the .icon's geometry and colors.
- At rest it clears the content view, so the Dock shows the real icon.

**Cost.**

- The icon ticks only while something moves, and calls `display()` only for frames that changed.
- During the steady chase it ticks at the next step (`AppIconMotion.nextWholeStep`, 8 times a second). While something eases, it ticks 30 times a second.
- The Dock takes the chase in whole steps (`AppIconMotion.frame(at:wholeSteps:)`): the cursor jumps from place to place. Every frame goes to the Dock as a new picture, and at Dock size the 37 ms ease between places does not show.
- The settle keeps its ease. The welcome page's mark, drawn larger, keeps easing too.
- Nothing is drawn while nobody can see the Dock (`DockSight`, CalmModel, unit-tested): from `screensDidSleep` to `screensDidWake`, and while another user's session is in front (`sessionDidResignActive`, `sessionDidBecomeActive`).
- The next tick after that draws wherever the motion is by then, since frames are a function of time.
- The tile, its shadow and its edge are drawn once per appearance, size and resolution into a `CGLayer`, and stamped under each frame. This is the Dock's view only.
- That cut a frame from 0.58 ms to 0.11 ms, the blurred shadow being most of it (2026-09-30).
- Size the layer in pixels, and measure its shadow in points, as the view does.
- The steady chase is twelve pictures, one per place the cursor holds (`AppIconFrame.chasePlace`). Each is drawn whole into a layer the first time it comes round and stamped after that. They are released once the icon is at rest.
- The settle and the changes between states are drawn as they come.
- The rest of `NSDockTile.display` is AppKit handing the picture to the Dock, which only fewer frames would cut.
- `DockIconViewTests` renders every state with and without the layers and holds them to the same pixels.

**Testing.** Headless self-tests have no Dock. `calm.dock_icon:<folder>` writes the states as PNGs.

Known limits:

- The drawn states do not follow the user's icon style (tinted or clear).
- The drawn idle frame differs slightly from the system's rendering of the icon, which adds its own edge light. It shows only at the moment the drawing hands back.

## Search

Behavior: FEATURES.md → F7. The welcome page: FEATURES.md → F2.

**Index.**

- **Engine:** SQLite FTS5 with `bm25()` ranking, in `~/Library/Application Support/Calm/index.sqlite`. `CALM_INDEX_FILE` overrides the path.
- **Tokenizer, decided (M4.2, 2026-09-27): `trigram`, with a `LIKE` scan for queries under three characters.** On 13,879 real messages, trigram matched plain substring search on every test query: whole words, partial words (`persist`, `notif`) and Chinese words.
- unicode61 missed partial words and most Chinese. The trigram index is 35 MB against 18 MB, built in 0.6 s. Queries take 1 ms or less, a 2-character `LIKE` about 10 ms.
- **Short terms start words (2026-09-30).** A term of one or two ASCII letters or digits matches only where a word starts (`SearchMatch`, CalmSearch).
- The `LIKE` scan adds `calm_word_start(text, term)`, a SQL function that `SQLiteDatabase.addPredicate` registers. It runs the same Swift rule the panel marks with, so every mark is a match.
- Other short terms (Chinese) match anywhere. "d" takes 125–150 ms on a large history.
- **Indexed content:** user and agent messages only. Tool calls, tool output and file dumps are skipped.

**Parsers (M4.1).** `TranscriptIndexing` adapters read complete JSONL records from a byte offset. `JSONLReader` stops at the last newline, so a file being written is read again later from there.

| Agent | Indexed |
|---|---|
| Claude Code | `user` text (string or blocks, not `isMeta`, not tag-wrapped) and `assistant` text blocks. Top-level files only, not `subagents/` |
| Codex | `response_item` messages with role user or assistant. It skips `developer` messages, tag-wrapped context and the injected `# AGENTS.md instructions` block |
| pi | `message` text blocks of user and assistant. No thinking, tool calls or results |

Each parser also gathers the session id, folder, title and first prompt.

**Incremental indexing.**

- Each file's byte offset, size and modification time are stored, so only new lines are parsed.
- A file that shrank is read again from the start.
- A deleted transcript is kept, marked `gone` (M4, 2026-09-29), because Claude Code deletes transcripts older than `cleanupPeriodDays` (30 by default).

**Prompt histories.** An adapter can name a prompt log that outlives its transcripts (`promptHistoryFile`, `historyPrompt(in:)`).

- Claude Code's `~/.claude/history.jsonl` has `{display, pastedContents, timestamp, project, sessionId}` per prompt.
- It is read incrementally, with its offset in `sources`.
- Prompts of sessions with no transcript row become a `history` row: `path` = `<log>#<session id>`, user prompts only, not resumable.
- A transcript that turns up later for that session replaces it.

**Agents' own databases (2026-09-30).** OpenCode 2 keeps every session in one SQLite database, not a file per session. So it has its own adapter protocol, `SessionDatabaseIndexing` (`sessionDatabase`, `indexedSessions(in:)`, `messages(ofSession:in:)`, in `OpenCodeIndexing.swift`), and `SearchIndex` has a pass of its own (`indexDatabase`).

- Each top-level session is a `files` row with `origin` 'database' and `path` `<database>#<session id>`.
- Its `size` and `mtime` hold the session's version: its messages' count and newest `time_updated`. OpenCode rewrites messages in place for days, and `session_v2.time_updated` does not follow them.
- A changed version reads the session again whole: its messages are deleted and inserted again.
- The pass is skipped while the database and its `-wal` are unchanged (their sizes and times, in `sources`).
- A session gone from the database stays searchable, marked `gone`, so it is not offered for resuming.
- Text is extracted in SQL (`json_extract`, `json_each` over `content`), so tool output, most of the bytes, never reaches Swift.
- Subagent sessions (`parent_id`), sessions with no text, and a fork's copied messages (written before the fork's `time_created`) are left out.

**Keeping the index.** The index holds sessions that exist nowhere else. So a schema change migrates (`1` → `2` adds `origin` and `gone`) instead of rebuilding. Only an unknown schema starts over.

**Snippets.** They are built in Swift from the best matching message (by rowid) for the results shown.

- A snippet starts on a word, up to 28 characters before the first term, so a one-line row always shows the match.
- FTS5's `snippet()` counted trigram tokens and often put the match past the visible line.

**Refresh (M4.3, M4.7).** The app refreshes the index when ⌘K opens and every few minutes, not through FSEvents, because an update with nothing new takes about 8 ms.

**Tables** (`SearchIndex`):

| Table | Holds |
|---|---|
| `files` | A row per transcript, per session in an agent's own database, or per session known only from a prompt history. It holds the agent, the read offset, size and modification time, the session's id, folder, title and first prompt, when it was last active, its `origin` and whether it is `gone` |
| `messages` | The FTS5 table of each message's text, with its file and role |
| `sources` | The read offsets of prompt histories, and the database sizes and times |
| `meta` | The schema version |

**Ranking (M4.4).**

- Per term, Calm takes the best `bm25()` message in each session, normalized to 0…1 against the query's best.
- Every term must appear somewhere in the session, not necessarily in one message.
- Then boosts: title match +0.35, recency ×0.3 (1 today, 0.5 after a week), current project +0.2. The project boost beats a few days, not months.
- Terms under three characters use `LIKE` and count as fully relevant.

**Welcome page.** With no session open, `WelcomePage` puts one `NSHostingView` over the whole window (sidebar included) and shows `WelcomeView`. So the search and the projects live on the page the sidebar would have.

- Each showing gets a `WelcomeModel`. It owns a `SearchPanelModel`, the projects the user made, and the selection.
- The `SearchPanelModel` is a flat list. An empty query lists the most recent sessions, opening refreshes the index, and typing queries it, debounced. ⌘K itself uses `SearchModel`.
- The selection is kept as what a row stands for (a transcript path or a project id), so it survives the lists changing under it.
- `ProjectSearch` (CalmModel) filters projects: every word must be in the name or in the folder as shown, ignoring case and accents. The same function gives the ranges the row marks.
- `WelcomeContent.choose` (CalmModel, pure) picks between the lists and the three-row welcome from three facts: first launch, whether the index knows any session, and whether a project exists.
- Whether the index knows a session is `SearchPanelModel.hasHistory`. It is nil until the index answers, and sessions are assumed meanwhile, so the page does not rearrange.
- ⌘K on the page calls `WelcomePage.focusSearch()` instead of opening the panel over it.
- Opening a result is `openSearchResult`, the panel's own.
- The projects end with a New project… row (`Target.newProject`, in the arrow keys' walk, ↵ calls `newProject`). It sits outside the list's scroller, so it stays in view.
- The rows are the panel's (54 pt, agent mark, snippet with marked words) and the sidebar's (`AgentLogo`, `IdenticonTile` at 30 pt, `KeyCaps`), not new drawings.

**The mark on the page.** The welcome page draws Calm's icon with `DockIconView`, the Dock's own view, so the two cannot drift apart.

- `AppIconFrame` has two numbers for it. `arrival` is the seconds since the mark began to draw itself, infinity for every other frame, so the Dock is unchanged. `cursorLevel` is how much of the cursor shows while it breathes.
- `WelcomeMarkMotion` (CalmModel, pure, like `AppIconMotion`) maps time to frames.
- The ring's ten cells fade in one `ringStagger` after another, in typing order. The center follows.
- The cursor appears on place 11 (the ring's last cell) and takes the last step to place 0 over a second, with the ease-out the Dock uses for its settle.
- Then `cursorLevel` follows a cosine between 1 and 0.42 (3.6 s a breath) for eight breaths, then `.still`.
- A click runs `AppIconMotion` for one lap.
- The view is a `TimelineView` that ticks 30 times a second only until the mark comes to rest, so a page left alone stops redrawing. Reduce Motion asks for one frame.
- `WelcomeMarkClock` (owned by the model) keeps the start and the last click, so the animation carries on when the page swaps layouts.

**No session chosen.** With sessions open and none selected, `NoSessionPage` puts one `NSHostingView` over the main area only (the sidebar stays) and shows `NoSessionView`.

- `updateNoSessionPage` shows or hides it wherever the welcome page is updated (a layout shown, the appearance).
- `NoSessionContent.choose` (CalmModel, pure) decides what it shows. It shows the sessions `SessionCardLayout.waitsForALook` marks: needs you, then done and failed, newest report first, at most three, the rest counted, plus how many still work. With none, it shows the lists.
- Once the user has typed in the lists' search, the lists stay, so a turn ending does not swap the page under their keys.
- The view reads `manager.workspace.sessions` and recomputes on every change, so it follows the sidebar.
- The lists are `WelcomeView` with `placement: .mainArea` (its own `WelcomeModel`, `firstUse` false). The mark is smaller, and with nothing to list the mark shows alone.
- It shows no hint line while the sidebar's footer is on screen (`sidebarFooterShown`: the `sidebar.footer` setting and a sidebar that is not hidden). `updateNoSessionPage` reads it. Folding the footer reaches it through `applyAppearance`, and hiding the sidebar through `toggleSidebar`.
- With nothing typed, `WelcomeModel.sessions` leaves out conversations running in an open session (`Session.runs`, the rule ⌘K uses to go to a session instead of resuming it).
- It reads them from the manager on each draw, not from the items, so one closed meanwhile comes back.
- The waiting cards take the keyboard through a focusable SwiftUI view (↑ ↓ through `Waiting.step`, ↵).
- ⌘K focuses the lists' field (`focusSearch`), and otherwise opens the panel.
- Self-tests: `calm.nosession_state`, `calm.nosession_key:down|up|enter`, and the `calm.welcome_*` actions for its lists.

**Panel (M4.6, grouped 2026-09-30).** ⌘K opens `SearchPanelView` over the window (`MainWindowController+Search`).

- Opening refreshes the index in the background. Then each keystroke only queries it, debounced by 70 ms.
- A result counts as open when a Calm session's agent run has the same transcript path or agent session id.
- Enter selects that session, or opens a new session in the result's folder (home when the folder is gone) and types the adapter's resume command into it.

*Model.*

- `SearchModel` asks `SearchService.searchPanel` for every match (limit 5000, so each group's count is true) with `lines: true`. With nothing typed it asks for the 300 most recent.
- `SearchGrouping`, a Sendable snapshot of the user's projects, gives each result its group by the sidebar's rule: scratch folders, then the most specific project, then `GitRoot.find` or the folder.
- It names groups for the index's `groupName`: a term a group's name holds counts as found in all of it.
- The pure parts are in CalmSearch and unit-tested: `SearchGroups.grouped`, `SearchGroups.switcher`, `SearchGroupCounts`, `SearchResult.linesToShow` and `SearchLineFit.parts`.
- `SearchGroups.grouped` puts the current group first and the rest by best match. It shows shares of three and two. "More" adds five, and it never says "1 more".
- `SearchResult.linesToShow` is greedy: the fewest lines that cover the words the title and group name do not show, at most three.
- `SearchLineFit.parts` gives up context before and after each word, in steps, until the line fits. It measures with `NSString.size` in the view's font at the standard size, with 5% to spare for the heavier marks.
- `WrittenTime` (CalmModel) writes the time out.

*Index lines.*

- `SearchResult.lines` carries, per result, the message behind each term's best match, deduplicated.
- Each line is flattened and cut to 240 characters either side of the words (`SearchQuery.excerpt`), with its role and the terms it holds.
- A ⌘K query takes 6–40 ms with its lines, one letter about 150 ms.

*View.*

- A `LazyVStack` with pinned section headers on a solid surface (`LinkTag`'s: the terminal's background lifted 7% toward white in dark, 55% in light), so rows scroll under them cleanly.
- Row frames in the list's own coordinate space give the height that ends on a whole row.
- "More" keeps its row still. The model counts `moreRequest`. The view notes where the row stood before the new rows are laid out, and scrolls by as much as it moved (`ScrollPosition`).
- A title's word counts as shown only when it fits before the time and a ↵ key, measured the same way.
- Self-tests: `calm.search:<text>`, `calm.search_key:down|up|tab|shift_tab|right|left|enter`, `calm.search_state` (groups, counts, rows with their lines, the selection).

**Module.** `CalmSearch` in CalmKit holds `SearchIndex` and `SearchRanking`, over `CalmSQLite`.

- `SearchIndex` does all database access on one serial queue, so the control socket can search off the main thread.
- `CalmSQLite` is a small package-internal wrapper over the system SQLite (`import SQLite3`, no dependency). `CalmAgents` also uses it to read OpenCode's own database, read-only.
- A connection that fails to open is closed in `SQLiteDatabase.init` and never kept. A class's deinit runs even when its init throws, so closing it in both freed it twice (fixed 2026-09-30).

**Performance (M4.7, Debug build).**

- The first full index takes 12.6 s for 502 files and 13,889 messages, mostly JSON parsing of 1.4 GB.
- An update with nothing new takes 8 ms. The index is 30 MB. Queries take 0.7–14 ms.
- Targets: queries under 50 ms while typing, and a no-change update under 50 ms, so ⌘K can refresh before every search.

## Find

Behavior: FEATURES.md → F16. Looks: UIUX.md → Find. Plan: ROADMAP.md → M8, M9.

**Ghostty's engine does the searching** (pinned source, read 2026-10-06 and 2026-10-07).

- The actions `START_SEARCH` (with a needle), `END_SEARCH`, `SEARCH_TOTAL` and `SEARCH_SELECTED` reach the app.
- The search runs on its own thread over the active screen: the normal one with its scrollback, or the alternate one of a full-screen program, which has none.
- `navigate_search` goes newest to oldest and stops at the ends. It scrolls the viewport to the selected match when that match is off screen.
- The search thread sends the matches in the viewport and the selected match's position to the renderer only (`Surface.zig`, `search_viewport_matches`, `search_selected_match`). The app hears only the total and the selected index.
- Matching (`sliding_window.zig`) compares bytes with only A to Z folded (`indexOfIgnoreCase`).
- A match counts at every place one starts, overlapping ones too: after a match, the search looks again one byte past its start. So "aa" is 3 in "aaaa".
- Soft-wrapped rows are joined, and each line ends with a newline, so no match crosses a line's end.
- Ghostty's macOS defaults: ⌘F `start_search`, ⌘G and ⌘⇧G `navigate_search`, ⌘E `search_selection`, ⌘⇧F and esc `end_search`.
- Esc is a performable binding, which takes the key whenever a search is active.

**Keys (M8.1).** Ghostty's own bindings stay, so the user's own Ghostty keybindings for search keep working.

- While a pane has the keyboard, ⌘F (`start_search`), ⌘G and ⌘⇧G (`navigate_search`) and ⌘E (`search_selection`) reach it as terminal bindings.
- While find's field has the keyboard, the Edit menu's Find items run the same binding actions on the focused pane.
- `start_search` only tells the app to show its field. The words go to the engine as `search:<words>`: everything after the colon, colons included. Empty words stop the search.
- `FindModel` (one per window) turns the four actions into the field's state.
- A second `start_search` on the searched pane closes the field. One with words (⌘E) replaces them.
- The first total of a new search sends `navigate_search:next`, so the count reads "1 of N" at the newest match (the engine's index 0).
- Each pane's last words come back when ⌘F opens there again.
- The four actions reach the window a turn of the run loop later (`TerminalEngine`), so its answers are not binding actions run inside libghostty's own call.
- Calm's defaults unbind `escape=end_search`, so esc in the terminal always reaches the program. The field takes esc itself (`onExitCommand`).
- `TerminalSurfaceView.keyDown` reports every key without ⌘ (`surfaceDidType`), which closes find before the key goes on.
- The keyboard moving to another pane, going to another session, or the searched session closing also closes find.
- In the title strip, the change readout steps away while find is open.
- `SessionTitleView.findFieldWidth` sizes the field from the row's width and the title's whole width (measured hidden). The field narrows to 240 pt before the title gives way.
- Only the title changes between `ViewThatFits` children, so the field is never rebuilt and never loses the keyboard.

**Where the current match is** (decided 2026-10-07, M8.2: Calm's own matching, no engine patch). A patch forwarding `search_selected_match`'s position would need the terminal's lock in a callback that runs without it. The map needs Calm's own search of the scrollback anyway.

- The pane finds the matches on screen itself (`FindMatcher`, pure, unit-tested). It uses the engine's folding and overlaps over `viewportRows()`, grouped into lines through soft wraps as the link marks are, with wide characters as two cells.
- The engine's selected index counts from the newest match. So the current match is the screen's matches counted backwards from the newest row.
- At the bottom of the scrollback, that row is the screen's own.
- Scrolled up, Calm reads the text from the screen's top to the newest row once (`GHOSTTY_POINT_SCREEN`'s bottom right) and counts it. It reads again only when the words or the position change.
- The position comes from `GHOSTTY_ACTION_SCROLLBAR` (total rows, offset, visible rows), handled in `ScrollbackPosition`.

**Marks (M8.3).** Ghostty paints a match only as a cell fill, which reads as a text selection (decided 2026-10-06).

- Calm's defaults set `search-background` and `search-foreground` to `cell-background` and `cell-foreground`, which makes the engine's fill invisible. A search color in the user's config still wins.
- `FindMarksView` draws the underlines, the band and the edge bar as Core Animation layers over the panes, beside `LinkMarksView`.
- The pill stays Ghostty's. Every Calm theme's Ghostty lines (`CalmTheme.ghosttyLines`) set `search-selected-background` to the solid accent and `search-selected-foreground` to the background, so the text is recolored where it is drawn.
- For the user's own Ghostty colors, Calm's defaults carry the same two lines from palette color 4 (`TerminalTheme.userFindPillLines`). A change of appearance reloads the config, since the lines are one appearance's.
- The pill is the engine's cell fill, so its ends are square and flush with the letters' cells, not the design's rounded pill 2 pt past them.
- A terminal color has no C value (`c_get.zig` reads only types with `cval`). So the overlay works out the pill's color as the lines were written: from the theme that matches the background, or from palette color 4.
- The pane refreshes its marks 0.05 s after a frame, not on every frame of fast output. It refreshes only when the screen's rows, the current match, the grid's position or the background changed.
- The underline sits under the text's baseline, which libghostty gives with a selection's position (`tl_px_y`).
- libghostty reports -1 for viewport row 0 while the screen is scrolled up into the scrollback, since it counts that row as off screen. So `gridGeometry` reads row 1 and steps back a row. The link marks and ⌥-click's cell use the same geometry.
- Each set of marks steps aside for the other: the link dots lose the cells find marks, and find's underline loses the cells of a link under ⌘.

**The map needs every match's row**, which Ghostty does not expose. So Calm reads the scrollback itself: `ghostty_surface_read_text` with a `GHOSTTY_POINT_SCREEN` selection returns all of it in one call.

- Cost (2026-10-07): 10,007 lines (1.1 MB) read in about 6 ms. 44,184 lines (5 MB, the most that Ghostty's default `scrollback-limit-bytes` of 50 MB kept of 50,000) in about 24 ms.
- One pass that finds the words and each one's line took 2.0 and 8.6 ms, compiled with `-O`.
- The read holds the terminal's lock while it runs. So Calm scans off the main thread, and reads only when it must (The map, below).
- The read joins soft-wrapped lines, so a tick's row counts each line's wraps. The box comes from `GHOSTTY_ACTION_SCROLLBAR`.
- Ghostty's total stays the count shown, so Calm's search must agree with it: the same case folding, and a match across a soft wrap found once.

**The map (M8.4, 2026-10-07).** `FindMap.scan` (CalmModel, unit-tested) makes one pass over the scrollback's bytes. Per line it gives:

- the matches, with the engine's folding and overlaps
- the row: the line's width over the columns. The width is the byte count, unless the line has more than ASCII, then its characters' cells.
- the line's number and text, for the tag

How it runs:

- The pane reads the whole scrollback on the main thread (`TerminalSurfaceView+FindMap`) and scans it in a detached task. A scan the words have moved past is dropped.
- It scans 0.15 s after the words change, and while output arrives at most once a second, whole.
- It scans whole, not only the new lines: rows can also leave the top of a full scrollback, and a cleared screen starts over. A whole scan is about 33 ms at the worst measured (5 MB).
- The engine's index picks the current line from the lines' match counts, newest first.
- A click steps there with `navigate_search` as many times as needed, and the engine scrolls the match into view.
- `FindMapView` is one view per workspace, for the pane being searched, over everything on the panes. It takes the pointer.
- The ticks, track and box are drawn. The current tick is a layer of its own, so it can slide (M8.6). The tag is AppKit, on the ⌘-link tag's surface.
- The map shows only while `showsFindMap`: words, lines with matches, and a scrollback taller than the screen, which a full-screen program's never is.

**Full-screen programs (M8.5).** The scroll bar reads the same for the alternate screen and for a normal one with little output. So engine patch 0018 adds `ghostty_surface_alternate_screen`.

- The pane asks it each time it looks at its matches, and reports a change to find (`FindEvent.fullScreen`).
- Find then counts "on screen", and shows its note when nothing there matches.
- The window fills in the running agent's name for the note (`Session.agent`).
- The note (`FindNote`) is its own view over the terminal, under the field's right end, placed from the field's frame in the strip. The strip's host clips what is drawn past it.
- The note's button closes find and opens ⌘K with the words.

**Colors** follow from the theme's background, text and accent (`FindColors`). `FindColorsTests` runs the contrast checks on the built-in themes.

- The pill and underline use the accent. In light themes the accent moves in OKLab lightness until background-colored text reads at 4.5:1 on it.
- The band is the background with lightness +0.03 and chroma 0.016 toward the accent's hue in dark themes, and −0.03 and 0.008 in light themes.
- A lone tick is the accent over the track at 60% in dark themes, or as strong as 3:1 needs in light themes (80–85%).
- A theme without an accent (the user's Ghostty colors) uses palette color 4.
- The band lies over the text, because the terminal paints its own background. So it is a layer of a stronger tint at the least opacity that still makes the band over the background (`FindColors.bandLayer`, under 12% on every theme). The text on the line keeps nearly all its contrast.

**The viewer (M8.7).** Files and viewer is below.

- Calm's own page (`viewer.html`: Markdown, code and text) has `calmFind`, `calmFindStep` and `calmFindClose`.
- They wrap each match in a `mark` (case-insensitive, not overlapping), keep the current one, put the band on its line in code, draw the map, and return the count.
- A click on the map's tick posts the new count back (`calmFind` script message).
- PDFs use PDFKit's `findString`. The current match is PDFKit's selection. Every other match gets a temporary underline annotation in the accent the light theme takes on a white page, removed on closing.
- HTML and SVG files use `WKWebView.find(_:configuration:)`, which says only whether there is a match.
- The field is the strip's own view over a protocol (`FindFieldModel`) that both models answer.
- In the strip, ↵ goes up to the older match. In a file, ↵ goes down to the next.
- The viewer's key monitor takes ⌘F, ⌘G, ⌘⇧G and ⌘E ahead of the terminal under it. Esc closes find before the viewer.
- The Edit menu's find items reach the viewer too while a file shows (`performViewerAction`).
- The colors are the viewer's background and text with the terminal's accent (`viewerFindColors`).

**Regular expressions (M9.1).** Ghostty's engine searches plain words only. So with `.*` on, Calm searches.

- Calm uses `NSRegularExpression` (ICU), case-insensitive unless `(?-i)`, over each line through soft wraps. It serves the marks (`FindMatcher`), the count and the map (`FindMap`), off the main thread as for words.
- A pattern that does not compile leaves the last marks and says so.
- The current match stays Ghostty's pill, painted by engine patch 0019 (`ghostty_surface_mark_search_match`). The patch hands the renderer a selection as its selected match, through the message the engine's own search sends it.
- Calm brings a match off screen into view first with `scroll_to_row`, a third of the way down.
- Sending the engine the match's own text and stepping to that text raced (2026-10-07): the engine reports its total piece by piece and never says when it is done.
- Calm's own order, newest first, picks the current match, and Calm's count is shown. The engine's search stops in this mode.
- New output's matches are newer. So the current match's number grows with them, and it stays the same match, as the engine keeps its own.
- A match of nothing (`a*` on a line without an a) is skipped.

**The whole session (M9.2–M9.5).** A full-screen program's screen keeps no history, so Calm keeps what it shows, as it is shown.

- Nothing can be had later, so keeping cannot wait for ⌘F. It runs only while a full-screen program draws.
- A perf scenario (a streaming full-screen program) holds it to the budget. If it cannot meet the budget, it does not ship.
- Kept lines are in memory per session, up to 50,000 lines (the oldest go), with the time each part was shown.
- They go when the session closes or Calm quits.
- Lines that pass faster than a read can be missed, the accepted trade.
- Nothing runs at rest or in a plain shell.

*Keeping (M9.2, M9.3).* `ScreenKeeper` (CalmModel) decides. The pane reads (`TerminalSurfaceView+Keep`).

- A shown pane reads 0.2 s after a frame: one `read_text` of the screen.
- A hidden pane draws no frames. So it reads every 0.2 s while its session is *working*, and not otherwise. The session manager tells each pane.
- Between two reads, a run of at least three non-blank rows, moved by one shift, is a scroll. The rows that left its top are kept.
- The shifts tried are only those the changed rows suggest (where each row's text was before). Rows are compared by hash, so a read is a few rows' work.
- Scrolling back moves where the program's view is in the kept lines, so lines that come back and leave again are not kept twice.
- Otherwise, when at least three rows and half the rows with text changed beyond their digits, the view was replaced. The view that went is kept, less any run of two or more of its lines kept already.
- Otherwise nothing is kept: a spinner, a timer, a status bar.
- A new size keeps nothing, since the program draws its view again.
- When the program leaves the alternate screen, its last view is kept, and the next program's lines start a part.
- Each line keeps the time it was first on screen.
- A read waits for the end of a synchronized update (engine patch 0021). The pty's output reaches the terminal a kilobyte at a time (`termio/Exec.zig`), so a big frame is half drawn between pieces. A half-drawn frame read as a new view would be kept twice.
- The shell's screen behind the program is read with engine patch 0020.
- Known limit: a view whose rows differ only in digits (a log viewer jumping between lines alike but for their timestamps) counts as changed in place and keeps nothing. That is the price of not keeping a timer's every tick.
- Known limit: a program that redraws its whole screen with other text all the time (`top` sorting by CPU) is kept view by view.
- Known limit: a view that moves further than its height between two reads loses what passed.
- Cost, held by `mise run perf`. `fullscreen` (in view) is mostly the drawing. `fullscreen-unseen` (hidden in a working session) is the keeper's own: about 22 M instructions a second against 13 without it, about 0.5 ms a read (Debug build, 2026-10-07).

*The switch and the page (M9.4, M9.5).*

- The window sets `FindModel.hasSession` from the pane (the alternate screen, or anything kept) when find opens, and when the pane says which screen it shows.
- In a full-screen program, the window also sets the note's count, from a `SessionPage` made then (one read of the scrollback).
- Session closes the terminal's find and shows `FileViewer.showSession`: the viewer's own page (`viewer.html`, kind `session`) in the terminal's font family and size.
- The page gets its lines with their time marks as `{t, m}`. CSS draws the time, so find never matches it.
- The page scrolls to its end. The current match is the newest at or above the view's bottom.
- The page's find is the viewer's (`ViewerFindModel`, `showsScope`).
- Screen and esc call `onScreen`, which closes the page and opens the terminal's find with the page's words (`FindModel.open`).
- The order: `ScreenKeeper.startProgram(shellLines:)` records how many lines the shell's screen had as a program takes the screen (one read of the scrollback then).
- `SessionPage` puts each program's kept lines after that many of the shell's lines, and the shell's later output after them. While a program runs, its screen now comes last, less runs kept already.
- A scrollback that let go of its top since then puts a program a little late in the shell's output.
- The page is a snapshot: what the program shows after the page opened is not on it until it opens again.
- A page searched before it loaded searches once it has (`didFinish`).

**At rest** find costs nothing: no timer runs while the field sits open, the map refreshes only when output arrives, and the slides are Core Animation (Motion in the window).

- Each frame the pane draws reads the grid's position (`followFindGrid`, one cell's `read_text`), so the marks ride a smooth scroll. It moves the marks only when the position moved.
- The rows are read 0.05 s after a frame, or at once when the screen scrolled.
- A step slides only when the screen held still (`PaneFind.slides`).
- Closing fades each pane's marks as one layer (`Marks.group`), and the map by its layer's opacity.
- New ticks fade in on a shape layer of their own until the drawing takes them over.
- A scrollback full enough to drop its top lines numbers its lines again. So a map whose lines mostly changed appears at once instead of fading.

## Command palette

Behavior: FEATURES.md → F1.

**Rows are closures (2026-09-30).** `PaletteCommand` (`Calm/Window/PaletteCommand.swift`) is an id, a title, an optional line, an optional key and a `run`.

- `MainWindowController+Palette.paletteCommands()` builds the list each time ⌘P opens, in category order: agent conversation, session and layout, view and navigation, folder, look, Calm, terminal.
- A row that does not apply is not there.
- The palette lists what has no key of its own (decided 2026-09-30): a key everyone knows stays out, so the palette is not a second menu bar.
- Every row is one-shot: a palette runs a command, and is not a menu to walk. So there is no second stage, and what needs a target stays in the right-click menu.

**One list with the card's menu.** The focused session's rows come from `SessionActionSet`, which the card's right-click menu reads too. So the two offer the same where they overlap.

- Copy Last Reply, Open Transcript and the global rows are the palette's alone.
- Restart *Agent* is in the menu and the palette. Restart All *Agent* Sessions is in the palette only (decided 2026-10-06).

**Every row has a description (2026-10-01).**

- Calm's rows are cases of `PaletteRow`, whose `help` switches over all of them. So a new row without a description does not compile.
- `PaletteCommandsTests` holds each description to one short line.
- `PaletteCommand(_ row:, title:)` takes the id and the description from the case.
- The view shows the selected row's description under its name. So that row grows by a line, and the rows below it move with each arrow key.
- The selection change animates (`Motion.animate`, 0.12 s), so they glide. This was chosen over a fixed line under the list (2026-10-01).
- Ghostty's two rows bring Ghostty's own wording.

**Ghostty's entries are an allowlist.**

- libghostty's `command-palette-entry` list, even without the entries that have a key, is dozens of rows of Ghostty's windows, tabs and screen dumps.
- `TerminalConfig.paletteActions` names the two that belong: `reset` and `toggle_mouse_reporting`.
- `PaletteCommandsTests` fails when a Ghostty release renames either.

**Matching** (`CommandMatcher`).

- Letters in order in the title, earlier and denser first.
- A description matches only as typed, after every title match. Scattered letters in a long sentence matched "split" to "Toggle Mouse Reporting".
- Rows are keyed by the command's id in the list, not its position. Position-keyed rows showed the previous row's content after a filter.

**Copy Last Reply** reads the transcript when asked.

- `TranscriptReading.lastReply(of:)` returns the agent's newest message with text, in full, for Claude Code, Codex and pi. Their transcripts are JSONL files, and `readsLastReply` says which adapters can.
- `TranscriptTail.lastMessage` is a recap cut to a line, with its Markdown stripped. The full text is never kept, since the tail is saved in `state.json`.
- OpenCode keeps sessions in a database, so it has no such row.

**Unsplit** (`Workspace.unsplit`) replaces a layout by one layout per pane, in the panes' order.

- The focused session keeps the layout's id, so what showed it keeps showing it.
- The controller gives each new layout its workspace view at once, which moves its pane over. A pane in no view would sit loose until chosen. Then it drops the emptied old view.
- Go to Welcome Page is `Workspace.deselect`: no layout chosen, the state that closing the session in front already leaves.

**Dump Logs** (`Diagnostics.swift`).

- `DiagnosticsReport` builds the text from facts and session lines that hold ids, states and agent names only.
- The trace comes from `/usr/bin/log show` for this process (`processID ==`), 30 minutes. A second Calm or a test would fill it with lines about another instance.
- It is written to `~/Library/Logs/Calm`, and Finder opens on it. Headless, it writes to the temporary folder and logs instead of opening Finder.
- `calm trace` prints the same trace from the CLI, for every launch of the app it came with (Control protocol).

## Persistence

Behavior: FEATURES.md → F3.

**Decided (M2.7): zmx** ([zmx.sh](https://zmx.sh), MIT, maintained), pinned in `scripts/zmx.sh` (version and SHA-256) and bundled at `Contents/Resources/bin/zmx`.

- Each session's terminal command is `/usr/bin/env -u ZMX_SESSION <zmx> attach calm-<12 hex>`.
- Attaching creates the zmx session on first use, and reattaches with scrollback after a relaunch. zmx starts the account's login shell.
- `env -u ZMX_SESSION`: inside a zmx session, that variable makes `attach` switch the calling terminal instead of starting a client. That would take over the terminal Calm was launched from.
- `ZMX_DIR=$TMPDIR/calm-zmx` (mode 700) keeps Calm's sessions apart from any other zmx use. Names stay short, because each session is a Unix socket there.
- `ZMX_NO_DETACH_KEY=1` leaves Ctrl-\\ to programs.

**A pane starts at its size** (since 2026-09-30). Reattaching after a relaunch hands the running program a terminal of the new client's size, so that size must be the final one.

- libghostty started every surface at an 800×600 placeholder and the config's text size. The real size came later, as a resize it holds for 25 ms.
- At launch the panes were built before the window had its saved frame, so zmx's client read 41×13, and Claude Code's screen came back with a blank footer.
- Now `MainWindowController` restores the frame before building panes, and `makeWorkspace` lays out the new workspace first.
- Each pane passes its size and the saved text size in the surface config (engine patch 0013), so the command starts with its final grid.
- The trace line `pane <id>: attaching at 145x44` gives the grid a pane started with.
- Splits still start at the placeholder: their shell is new.
- Restoring full screen still resizes once, a turn after launch.

To check it:

1. Run `scripts/selftest.sh` with `--persist --state <one file>`, typing a program that logs its size on start and on SIGWINCH.
2. Run it again with the same state file.
3. In the second run, the trace grid must match `focused pane … grid`, and zmx's `init resize` must match it.
4. The program must see only zmx's same-size SIGWINCH on reattach.

**Closing and quitting.**

- Quitting detaches. Closing a session runs `zmx kill <name> --force`.
- Inside zmx, libghostty's "process running?" check cannot see the agent. So a close asks whenever the session has an agent run.
- Quit asks only when shells will not survive: zmx unavailable, or persistence turned off mid-run after zmx failed, and libghostty sees a running process.

**Restart** (`Restart`) is an ordinary quit plus a relaunch.

- Once the quit cannot be cancelled (`applicationWillTerminate`, after state is saved), Calm starts a `/bin/sh` helper.
- The helper waits for Calm's PID to be gone (an unreaped zombie counts as gone), then runs `open <bundle path>`.
- It gives up after 30 s rather than start a second Calm. It retries `open` for 5 s, in case `install.sh` is mid-swap.
- So two Calms never attach to the same zmx sessions or write the same state.
- `open` hands its own environment to the app it launches. So the helper gets Calm's environment minus the self-test drivers (`CALM_SELFTEST_*`, `CALM_SNAPSHOT*`).
- Shells keep the same `PATH`, and a Debug or test instance keeps its `CALM_*` isolation instead of coming back on the real Calm's state.
- Opening by path starts the copy at that path, even while another copy with the same bundle ID runs. So a Debug build never wakes the installed Calm.
- The helper runs `open` without `-n`, so a Calm the user opened in between comes forward and is not joined.
- The helper also removes an installer's moved-aside copy (Distribution → The moved-aside copy).

**Closing the session on screen selects none.**

- `Workspace.selectedLayout` is nil when `selectedLayoutID` is. `removeSession` clears it when the shown layout goes. So Calm never picks a session for the user.
- The state is saved and restored like any other: a relaunch after it shows the same empty main area.
- `MainWindowController.showNoSession` hides every workspace view and follows no folder.
- With no pane focused, ⌘W and the other pane shortcuts do nothing. ⌘W never falls through to closing the window.
- ⌃Tab from here goes to the first session, and ⌃⇧Tab to the last.
- Closing one pane of a split keeps its layout on screen, with focus on the sibling.
- ⌘⇧T reopens the session and selects it.

**Closing never reaches the next pane.** libghostty queues surface messages by address, and a new surface can be allocated where a freed one was. Killing zmx makes the closed pane's client exit, so its "child exited" could close the pane that replaced it. Persistence was then turned off as failing.

- Close requests from libghostty run after its call returns.
- `teardown` drains the mailbox right after `ghostty_surface_free`.
- A child exit whose runtime is longer than the pane's age is ignored.
- Only a live pane's exit can turn persistence off.
- At launch, `calm-*` sessions in Calm's directory that no saved session refers to are killed.

**Shell integration inside zmx.** libghostty injects Ghostty's shell integration only when the command it runs is a shell, and here it runs zmx.

- `ShellIntegration` sets the variables Ghostty would, and zmx hands them to the shell it starts.
- zsh: `ZDOTDIR` points at the bundled integration, and the user's own value is kept in `GHOSTTY_ZSH_ZDOTDIR`.
- fish and elvish: the integration is prepended to `XDG_DATA_DIRS`.
- `shell-integration = none` in the Ghostty config turns this off.
- Bash and nushell need their command lines rewritten, so they rely on the process-based folder lookup.
- zsh starts one step earlier, in Calm's own `.zshenv`. Calm writes it at each launch, before any shell starts, to `~/Library/Application Support/Calm/zsh`.
- `ZDOTDIR` points there, and `CALM_GHOSTTY_ZSH_DIR` at Ghostty's integration, which Calm's file sources next. Ghostty's file then puts the user's `ZDOTDIR` back and runs their files as before.
- Calm's file adds one thing: the ⌘ Return binding (Agents → Send with ⌘ Return). It is a `precmd` function that removes itself, so it binds after the user's `.zshrc`.

**Without zmx.** When zmx is missing or fails, sessions fall back to plain shells for the rest of the run. `CALM_NO_PERSISTENCE=1` forces this.

**App state.** Projects, sessions and layouts live in `~/Library/Application Support/Calm/state.json`.

- The file is a versioned envelope, written atomically and debounced.
- Nothing is written when the file already holds the same bytes (`WorkspaceStore.save` reads it back first). With agents working, a save came about every 2 s, and two in five changed nothing (2026-09-30).
- A file Calm cannot read, or one from a newer Calm, is moved aside as `state.unreadable-<time>.json`, never overwritten.
- The next launch says so once, with an alert that can show the file (`StateAlerts`, since 2026-10-12).
- A failed save would lose everything since the last good one at quit. So it says so once per run of failures.
- AppKit's autosave keeps the window's windowed frame, but does not record a window left filling the screen. `Workspace.windowFilled` does (Window).

**Text size.** The shared text size (`Workspace.fontSize`, nil at the config's `font-size`) is saved in the state too.

- libghostty sizes each surface on its own. So Calm watches `CELL_SIZE`, which fires on every font change, whatever caused it.
- Calm reads the pane's size back through `ghostty_surface_inherited_config`, and moves the other panes with `set_font_size` or `reset_font_size`. They report the saved size back, which ends the loop.
- New panes get `set_font_size`, not the surface config's `font_size`. Only the binding action marks the size as the user's, so a config reload keeps it.
- With `window-inherit-font-size = false`, libghostty does not report the size, and Calm stops syncing.

## Smart links and Copy Cell

Behavior: FEATURES.md → F8, F9.

**Links (M5.1).** libghostty detects URLs and paths. Calm resolves relative paths against the session's folder, parses `:line[:column]`, and routes to the viewer or the editor (`code -g`, `cursor -g`, `zed`, `xed -l` and others).

- libghostty's own link regex matches URLs and absolute, `./`, `../` and `~/` paths, with their `:line:column`.
- Its `OPEN_URL` action goes to the pane's host, which knows the session.
- `Link.parse` (CalmModel) keeps only known schemes as URLs, so `Package.swift:12` is a path.
- It peels up to two trailing numbers, expands `~`, and resolves relative paths against the session's folder. A missing file is tried against the project's folder too.
- `EditorLocator` takes `files.editor` from config.toml (a name or a path).
- Otherwise it finds the first installed of VS Code, Cursor, Trae, Windsurf, Zed, Sublime Text, IntelliJ IDEA, then Xcode. Xcode is last, because `xed` exists wherever Xcode does.
- It checks known install paths, since a GUI app's PATH is minimal.
- An `.app` path (Settings → General → Choose Application…) is matched by bundle name to a known editor's tool inside it, so a copy in ~/Applications gets the line too.
- Any other app opens the file through NSWorkspace, without the line.
- Headless self-tests log what they would open instead of opening it.

**Link marks and tag.** libghostty highlights links only while ⌘ is held, and its `link` setting cannot be set yet (`Config.zig`: "TODO: This can't currently be set!"). So Calm finds links itself.

- `LinkMatcher` (CalmModel) is libghostty's own pattern (`src/config/url.zig`), adapted for ICU: bounded lookbehind, escaped `[\:`. It is tested against Ghostty's own cases.
- Each pane (`TerminalSurfaceView+Links`) rescans when its layer gets a new frame, at most every 0.1 s. Changed rows drop their marks.
- Once the rows read the same 0.3 s later, the pane matches every line and keeps the links that resolve.
- Resolving uses `LinkOpener.resolveExactly` for each of `Link.candidates`, longest first.
- The pattern lets a path run on across single spaces, and counts a sentence's closing `.` as part of a path. So each try is also tried without trailing `.,;:!?`. The whole text goes first, since a name can end in a dot.
- Rows the terminal soft-wrapped are joined first (a two-row read without a line break), since libghostty's ⌘-click matches across them.
- `LinkMarksView`, one per workspace above its panes, draws a small view per mark, so each can fade on its own.
- There are no resting marks while `ghostty_surface_mouse_captured`: such a screen is redrawn too often.
- ⌘ hover and click still work there, through patch 0011.
- The pane drops the hovered link when its rows change, since libghostty looks again only on the next pointer move or key.
- The tag follows `MOUSE_OVER_LINK`, which arrives while libghostty holds its renderer lock. So the pane handles it on the next turn of the main loop, because reading the screen takes the same lock.
- The action says where the link is, not what cells it covers. So the pane matches the row under the pointer again.
- `LinkTag` (Window) places the tag from the link's cells, and fetches image thumbnails with `QLThumbnailGenerator`.
- Resting marks cannot show OSC 8 links whose label is not a path or URL.

**Links a program cut across rows.** An agent's full-screen view breaks a long URL or path with its own line breaks. `HardWrap` (CalmModel, unit-tested) joins them.

- A soft line whose last text reaches within `edgeSlack` (3) columns of the last column, followed by a line whose first text is at most `maxIndent` (16) columns in, carries on into it.
- `LinkMatcher.matches(in:rows:continuations:)` reads the rows as one, leaving the continuation rows' indent out.
- `HardWrap.Joined.crosses` keeps the matches that run over a cut.
- The pane takes such a match only when a candidate of it resolves (`openable`). So a word that only ends at the edge does not glue onto the next row's word for a path.
- A joined match displaces the per-row pieces that overlap it. Per-row matching is otherwise unchanged.
- libghostty knows nothing of these links, so the pane does the pointer work itself, before libghostty.
- `mouseDown` with ⌘ opens the joined link under the pointer (`openJoinedLink`) and swallows the press and release.
- `refreshJoinedLinkHover` (pointer or ⌘ changed, once per cell) and `updateLinkHover` (libghostty's link changed) set a `LinkHover` with `isJoined`.
- `isJoined` makes the pane show the pointing hand (`currentCursor`), and makes `LinkMarksView` draw the solid underline.
- This works with the mouse captured, since none of it waits on libghostty.
- The cut is a guess: a URL that ends exactly at the edge cannot be told from a cut one.
- A border or gutter in front of the continuation, or a cut before the edge, is not joined.

**Copy Cell (M5.2).** Calm reads the grid text around the click with libghostty's text API.

- It scans left and right for the nearest vertical border characters, and up and down for horizontal border rows.
- Then it joins the cell's lines and trims padding.
- It is a pure function over a text grid (`CopyCell` and `TextGrid` in CalmModel), unit-tested with fixtures of real agent tables.
- The grid uses display widths (`CellWidth`: CJK, fullwidth and emoji take two cells), so columns match the terminal's.
- Borders include box-drawing lines and junctions, `|` and `+`. A rule is a row of rule characters with at least one dash.
- Tables with a rule after every row are delimited by the rules.
- Tables with only a header rule treat each line as a row, except that a line whose first column is empty continues the row above.
- Wrapped lines join with a space, or without one between two wide characters.

**Clicks to cells.**

- The view reads the grid one row at a time: a whole-viewport read joins soft-wrapped lines and shifts the rows.
- It maps the click to a cell from cell (0,0)'s origin and the cell size.
- `ghostty_text_s.tl_px_x` is the left padding. `tl_px_y` is row 0's text baseline, not its top (`Surface.zig`: padding + cell height − the font's baseline, which the API does not expose).
- `ghostty_surface_ime_point` gives the bottom of the cursor's cell (padding + whole cells). So the top padding is the one value a whole number of cells from it and less than a cell above the baseline (`gridOrigin`).
- A small "Cell copied" note fades by the pointer.
- The right-click menu (when the program does not capture the mouse) offers Copy and Paste. Its Copy Cell item was removed on 2026-09-30: ⌥-click and ⌥-drag do it everywhere, in programs that take the mouse too.

**⌥-click and ⌥-drag** (since 2026-09-30). ⌥-click replaced ⌥-double-click, which in Claude Code's full-screen view handed the first click to the program. That program counts clicks itself and selects on a double or triple click.

- `TerminalSurfaceView+CopyCell` holds an ⌥-press over a cell back from libghostty (`cellGesture`).
- Released within 3 pt, it copies the cell, and neither half reaches the program.
- Moved further, it becomes Calm's own selection inside that cell (`CellDrag`, over the screen as the drag began).
- `CopyCell.selection` takes the text from the press to the pointer in reading order, held to the cell. Past the bottom means its end, past the top its start, and beside a line that line's edge.
- The selection joins lines as Copy Cell joins wrapped lines, and the release copies it.
- A terminal's selection runs across whole rows. So passing the drag on to libghostty took the neighbouring cells' text too, which is what Copy Cell avoids.
- `PaneLinks.cellSelection` holds a band per line. `LinkMarksView` draws it in the theme's `selection-background` at 40% over the text. It stays 0.6 s after the release, to show what was copied.
- An ⌥-drag that starts outside a table still goes to libghostty: the rectangle selection, or the program's own.
- After a copy with no capture, a plain press and release is sent too, since libghostty has no action to drop an older selection that would otherwise stay highlighted.
- The outline comes from `CopyCell.cell` (its lines and columns, not only its text).
- The pane keeps the outline in `PaneLinks.cellOutline`, and looks the grid up again only when the pointer enters another cell. `LinkMarksView` draws it (`CellOutlineView`).
- In a program with mouse capture, an ⌥-click or ⌥-drag inside a cell reaches the program as hover only.

## Paste

Behavior: FEATURES.md → F1.

- A terminal cannot carry image data, but agents attach an image from its path.
- So `TerminalClipboard.plainText` pastes files as their shell-escaped paths, and text as text.
- An image with neither (a screenshot) is saved as a PNG in `$TMPDIR/calm-pasted-images`, and its path is pasted. The temporary folder lets macOS clear old pastes.
- A drop onto a pane goes through the same function.

## Text input

- `TerminalSurfaceView+Keyboard` is the pane's `NSTextInputClient`: the one door for input methods, System Dictation, voice input methods and the emoji picker.
- Committed text goes to the program as typed keys, never as a paste.
- Two answers matter to voice input (fixed 2026-09-30, when dictation and Doubao's voice input did nothing).
- `selectedRange()` never says `{NSNotFound, 0}`, which reads as "no insertion point" and stops dictation from starting. With no selection it is the empty range at 0.
- `insertText` does not need a key event in flight. A voice engine commits from its own callback, after the key that started it.
- `DictationInputTests` checks both.
- Headless runs cannot drive real dictation or a voice input method, so check those by hand.

## Window

Behavior: FEATURES.md → F1.

**Square corners when filled** (since 2026-10-07). macOS rounds every titled window (16 pt on macOS 26), so a filled Calm let the desktop show through a sliver at each corner. AppKit has no public API for a window's corners.

- `SquareCorners` overrides four private methods of `NSThemeFrame` once at launch, for every window: `_cornerRadius`, `_getCachedWindowCornerRadius`, `_topCornerSize`, `_bottomCornerSize`.
- They answer 0 for a `CalmWindow` whose `hasSquareCorners` is on, and ask AppKit's own for every other window.
- `windowCornerMaskChanged` has the frame rebuild its shape when that changes.
- `CalmWindow` turns it on while `isFilled` and not in full screen.
- It follows its own resize, move, screen and full-screen notifications, and the app's screen-parameter change. The Dock showing or hiding moves `visibleFrame`.
- The override checks each method's type encoding first, and installs all four or none. So a macOS that drops or changes them keeps round corners.
- It answers only on the main thread.
- `CalmWindowTests` reads `_cornerMask`, the shape the window server is handed: square for the asking window, round for another at the same time, round again after.
- The idea came from m4rkw/macos-corner-fix (MIT), which swaps the same methods for every window of an app. No code was taken.

**Hidden sessions do not render.** Every session keeps its panes alive, but only the layout on screen draws frames.

- `PaneVisibility` (unit-tested) keeps two reasons apart: the pane's layout is the one shown (`restorePaneVisibility`, the session switcher), and the window is visible (`didChangeOcclusionState`).
- The pane draws only when both hold. libghostty hears only when that answer changes.
- With one flag for both, the window coming back into view (another Space, uncovered, unminimized) woke every hidden pane until the next switch: about 2 GB of frame buffers with eight sessions open (2026-09-30).

**Size across launches.** `setFrameAutosaveName` saves the windowed frame, but only frames the user sets. A window left zoomed, filled or maximized keeps the older windowed frame in the defaults.

- `MainWindowController.noteFill` runs from `windowDidResize` and `windowDidMove`.
- It records whether `CalmWindow.isFilled` (the frame covers `screen.visibleFrame`, within a point) in `Workspace.windowFilled`, saved with the rest of the state.
- It ignores full screen and miniaturized windows, whose frames say nothing about the user's choice.
- It must skip full screen: on a notched display that frame is a point taller than `visibleFrame`, which passes `isFilled`.
- It stays off until `restoreFrame` has run, so restoring is not taken for leaving the filled state.
- `restoreFrame` (from `openMainWindow`) applies AppKit's frame, then `CalmWindow.fillAsLeft`.
- `fillAsLeft` uses `zoom` from that frame, which makes AppKit remember it for Zoom, and `frameBeforeFill` for Fill. Without that, a window that opened filled had no size to go back to, and a double-click on the title strip did nothing.
- Full screen is kept the same way, apart from the filled state. `windowDidEnterFullScreen` and `windowDidExitFullScreen` set `Workspace.windowFullScreen`. They cover the menu, the green button and Ghostty's `toggle_fullscreen` alike.
- `windowFilled` stays as it was under full screen, so leaving full screen goes back to the filled window.
- After `showAndFocus`, `restoreFullScreen` calls `toggleFullScreen` on the next turn of the run loop. It works with the app inactive too (a launch with `open -g`), so it does not wait for activation.
- Headless runs never enter full screen, so a test cannot take a Space over on the user's screen. `calm.window_state` logs the frame and whether the window is in full screen.
- Known gap: one of six test launches that should have restored full screen came back filled but not in full screen. The cause is not known. The fallback is the filled or windowed window.
- The defaults key follows the bundle id. The Debug build and its self-tests are `com.jinhuang.calm.dev`, so their frame is their own and never the installed Calm's.
- `windowFilled` lives in the state file, which self-tests keep apart (`CALM_STATE_FILE`).

**Narrowest window.** `WindowMinimum` (unit-tested) adds the sidebar's and the files column's width constraints as they stand (0 when hidden) to 400 pt at the interface size.

- The result is capped at the screen's visible width (`NSScreen.main` before the window has a screen).
- `MainWindowController.updateMinimumSize` sets `window.minSize` from it, and widens a narrower window (`WindowMinimum.widened`, moved left to stay on screen, not in full screen).
- It runs inside the sidebar's and the column's layout animations (`FilesColumn.toggle` takes an `alongside` closure for it), so the window grows as the panel slides in.
- It also runs from `applyAppearance` (the interface size) and `windowDidChangeScreen`.
- 400 pt keeps a 720 pt window with the sidebar, half of a 13-inch MacBook Air's 1440 or 1470 pt. It leaves the title strip room for the find field and the group's mark.

**Title bar double-click.** Calm's content fills the window under a transparent title bar (`fullSizeContentView`). So a double-click at the top reaches Calm's views, not the title bar, and AppKit never zooms.

- `CalmWindow.sendEvent` catches the second click of a double-click in the top strip: 48 points, or the title bar's height if taller. It skips controls such as the traffic lights.
- It does what `AppleActionOnDoubleClick` says: Zoom (`performZoom`, also when unset), Minimize, nothing, or Fill.
- Fill has no public API. So the window takes the screen's visible frame, and the next double-click restores it.

**Session title.** `SessionTitleView` (SwiftUI) sits in a `SessionTitleHost`, pinned over the main area at `titleStripHeight`.

- The host's `hitTest` answers only over its controls: the ⋯ button, the change readout and the back button. Elsewhere it returns nil, so dragging and double-clicks still reach `CalmWindow`.
- The host reports each control's frame. `CalmWindow.isInTitleStrip` treats a hit on a control as not the strip, so a double-click on the button does not zoom.
- The host sets `safeAreaRegions = []`: under the transparent title bar, its safe area would push the text onto the terminal's first row.
- `SidebarView` reserves the same `titleStripHeight` above its search field, so a double-click in the strip never lands on the field.
- It reads `Session.titleStrip(agentTitle:)` (CalmModel, unit-tested): the folder via `WorkspacePath.abbreviated`, and the card's title unless it only repeats the folder.
- Its leading edge follows the main area at high priority and never goes left of the zoom button's end. So with the sidebar hidden, it clears the traffic lights.
- It hands the title (else the folder) to `window.title`. `titleVisibility = .hidden` keeps that off screen, but the system still uses it.
- It shows the session's group with the sidebar's own `GroupMark`. The host takes no clicks there, so the mark's shuffle stays in the sidebar.
- After the folder it shows the worktree, from `Session.worktreeName`: `Session.activeDirectory` (CalmModel: the running agent's `TranscriptTail.directory`, else `workingDirectory`) run through `GitRoot.worktreeName`.
- A folder counts as a linked worktree only when its `.git` file points into `…/worktrees/`. A submodule's points into `modules/`.
- The sidebar's card asks the same property, so the two agree.
- Inside a `ViewThatFits`, the variant with the worktree comes first and the one without second. So the worktree drops out before the name or the folder is cut.
- A session with no worktree skips `ViewThatFits` and draws the text alone, so it never holds an optional child.
- The worktree is a `GitLabel`: the git mark and a name in 12 pt tertiary, the same view as the files column's branch.
- It has its own VoiceOver label ("worktree …"). The name, folder and mark stay hidden from VoiceOver, as the window title carries them.
- The ⋯ button opens the session menu Calm draws (Session actions). A right-click on a card opens the same one, so the two cannot drift.
- What the copy items give comes from `SessionCopy` (CalmAgents, unit-tested). The actions are `MainWindowController.sessionActions`, shared with the sidebar.
- Rename sets `SidebarEditing.renamingSessionID`, and the card's field loads its draft when it appears, so both entry points work. A hidden sidebar comes back first.
- Headless self-tests copy to a pasteboard of their own, and log Reveal instead of opening Finder.

**Getting into a split and out of one** (UIUX.md → Split panes).

- The model is `Workspace.join(_:beside:direction:)`, `takeOut(_:)` and `sessionsInView` (CalmModel, `Workspace+Splits`, unit-tested), with `unsplit(_:)` from `Workspace+Palette`.
- `join` removes the session from its layout. That layout goes when it was the only pane. A split it leaves hands its focus to the pane that took the room (`SplitTree.neighborAfterRemoving`).
- Then `join` splits the session in beside the target, focuses it, selects that layout and opens its sidebar group.
- `takeOut` appends a layout of one.
- `unsplit` replaces a layout by one per pane. The palette's Unsplit, Shell → Unsplit All and the icon's menu call it through `MainWindowController.unsplit()`.
- `SplitTree+Drop` holds what a drop means, as pure functions. `drop(at:_:excluding:)` gives the pane under the pointer and the nearest of its four edges, or nothing in the middle 44%.
- `landingFrame(of:toward:)` gives the half. `parentAxis(of:)` says how the icon's line runs.
- `SplitHandle.isShown` (when a pane shows its icon) and `SplitMenu.rows` (what its menu holds) are in CalmModel, so both rules are tested. `PaneDim.veil` takes `isLeaving`.
- A dragged session is a `SessionDrag` (origin card or pane, and the session's id) under `com.jinhuang.calm.session`, exported in `Info.plist` through `project.yml`.
- The panes register for text and files and never for that type, so a drag of a session is never pasted as text.
- `TerminalWorkspaceView+Handles` holds `HandlesView`, a sibling above the veils whose `hitTest` returns nil except over an icon that shows.
- It also holds `SplitHandleView`, drawn with `NSBezierPath` on a 16 pt grid. The icon starts an `NSDraggingSession` after 4 pt, and is a click otherwise.
- `TerminalWorkspaceView+SessionDrop` holds the `NSDraggingDestination` on the workspace view, and `LandingView`, a `CAShapeLayer` with a dash pattern of `[0.01, 4]` and round caps.
- The pointer's pane comes from a tracking area over the workspace view (`mouseMoved`), which the panes in front do not hide.
- A window-wide local monitor would never hear mouse-moved events: the window sends them to monitors only when it accepts them, and Calm's does not.
- `MainWindowController+Splits` makes the moves in the order that keeps the views and the model in step.
- First the pane leaves its old workspace view (`detach`, which folds a visible one away). Then the model changes. Then the pane is added to its new view (`split`, which grows it in).
- A layout nothing has shown yet is built with the session in it.
- A taken-out pane gets a workspace view of its own at once, hidden like any layout not on screen. So a pane never sits without a window to learn its visibility from.
- The sidebar's cards and rows carry `.onDrag` (`ActiveSessionDrag.provider`, a data representation registered `.ownProcess`). `ActiveSessionDrag.current` backs it up for a drop that cannot read the pasteboard.
- The sidebar takes a `.onDrop` of the type: only a pane's drag takes a pane out.
- Self-tests drive all of it without a pointer: `calm.select:n`, `join:m:n:side`, `take_out:n`, `unsplit`, `drop:m:x:y`, `drag_over:m:x:y`, `pointer:x:y`, `hover:n`, `landing:n:side`, `leaving:n`, `split_menu` and `split_state`.
- `calm.drop` and `calm.drag_over` run the destination with a hand-made `NSDraggingInfo`. `calm.pointer` runs the mouse-moved code. `split_state` logs the layouts, focus, lit rows, and whether the workspace views agree with the model.

**Split panes: the dim, the question and the fold** (UIUX.md → Split panes).

- The engine draws no unfocused-split dim: in Ghostty, the app shell around the engine draws it. Calm reads none of `unfocused-split-*`.
- The values live in `PaneDim` (CalmModel, unit-tested). `veil(isFocused:hasSplits:isAsked:asking:)` says how opaque the veil over one pane is.
- `SplitTree.collapsedFrame(of:)` says where a closing pane folds to.
- `TerminalWorkspaceView+Dim` holds the rest.
- `VeilsView` is a sibling above the panes and their link marks, because a pane's own layer belongs to libghostty. It holds one `VeilView` per pane.
- A `VeilView` is a layer-backed view of the pane's `topEdgeColor` (else its background), whose `alphaValue` is the veil.
- `Motion.fade` moves it: a presentation-only glide that first removes any glide still running. Otherwise the old glide plays out and snaps back.
- Both views return nil from `hitTest`, so a click on a receding pane still reaches it and focuses it.
- `focusedID` is the layout's `focusedSessionID`, set from `MainWindowController.updateDim`.
- `updateDim` runs from `applyAppearance`, which every focus change already reaches, and from `surfaceAppearanceDidChange` for the unfocused panes, whose colors move too.
- A focus that is not among the panes (its pane just closed) dims none.

*The question.* `ClosePrompt` (Window) asks before closing a pane in a split.

- `ClosePromptView` (SwiftUI, its own file) is hosted over the pane like the arrival card, centered on it and sized to its words.
- It uses a local key monitor, not a first responder. So the pane keeps the keyboard focus, and the dim keeps following the layout.
- It has no card. The words stand on `ClearingView`, in the workspace's `VeilsView` above the asked pane's veil.
- `ClearingView` is a radial `CAGradientLayer` in the pane's own color. Its stops and reach are the tested `PaneDim.clearing` and `clearingReach`. A radial gradient reaches as far from its start as the end point is, on each axis.
- It fades in with `Motion.fade` and follows the veil's frame from `refreshVeils`.
- The tile is `AgentLogo` for an agent, and the sidebar's chevron tile for a plain program.
- The keys are drawn, not typed. `KeyGlyph` is a `Shape` on a 16 × 16 grid: Return's arrow with a quad-curved corner, and Escape's circle plus its arrow.
- Escape's circle is sampled every 4° from 251° round to 199°, because an arc in a flipped space is easy to get backwards.
- The glyphs are stroked at 1.5 pt with round caps, inside a `KeyCap` (21 × 18, `style.selection` fill).
- `ClosePrompt.ask` also sets `TerminalWorkspaceView.askedID`, which takes the other veils to 0.22 and the asked pane's to 0.5.
- `MainWindowController.confirmClose` uses the question when `askablePane` finds the pane on screen in a split. Otherwise it uses the window's `NSAlert`.
- The question ends when focus arrives at any pane (`surfaceDidBecomeFocused`). A click that focuses another pane is consumed by that pane's own mouse monitor, which the question's monitor never hears.
- ⌘W again takes the question back: in the monitor, and in `surfaceRequestsClose` for a close that arrives another way.

*The fold.* `TerminalWorkspaceView.detach` first calls `foldAway`.

- A `GhostView` sits above the panes. It is layer-backed, and its picture is the closed pane's layer `contents`: the IOSurface libghostty last drew, set in `updateLayer`.
- Assigning `contents` to a layer AppKit owns, or to a layer-hosting copy of it, showed nothing in `cacheDisplay` snapshots.
- The ghost shrinks and fades with a `CAAnimationGroup` to `collapsedFrame`, and a timer removes it.
- The panes that stay take their final frames at once (`layoutPanes(animated: false)`). The terminal resizes once, and the ghost uncovers it.
- AppKit's `animator().frame` stalled when the close came from a deferred callback. ⌘W arrives through `engineRequestsClose`'s `DispatchQueue.main.async`.
- `closeSession` asks whether the layout still exists before it drops the workspace. A copy of the layout taken before the close named the closed session as focused, which rebuilt the whole view and stopped any animation.
- A snapshot shows the model layers, not a glide in flight.

**One focus.** The first responder gets the keys. The model's `focusedSessionID` is what the sidebar, the dim and the title strip show. The two must be the same pane.

- `resignFirstResponder` calls `syncFocus(resigning: true)`, which turns `focused` off at once. It used to ask while the window still named the pane first responder, so every pane that had had the keyboard believed it still did, and libghostty was told so.
- `performKeyEquivalent` answers only for the window's actual first responder, since AppKit offers a key equivalent to each view in turn.
- A key that reaches a pane (`keyDown`, or a key equivalent) moves the model onto it (`surfaceDidReceiveInput`, `MainWindowController+Focus`). So the indicators follow the keyboard, never the other way round.
- `traceFocus` writes one line to the unified log (category `trace`, as `Trace` does) when focus arrives, when a key reaches a pane the model did not have focused, and when a close is requested.
- Each line names the pane, the first responder and the model's pane by their first eight hex digits. So a ⌘W that lands on the wrong pane can be read back from the running app:

```sh
/usr/bin/log show --last 5m --predicate 'subsystem == "com.jinhuang.calm" AND category == "trace"'
```

Self-tests:

- `calm.click_pane:<n>`: a real click through `NSApp.sendEvent`, so the panes' own monitors see it.
- `calm.real_cmd_w`: ⌘W through `window.sendEvent`, down the view hierarchy. `pressKeyEquivalentForTesting` asks the model's pane directly and cannot show a mismatch.
- `calm.who`: per split, the first responder, `focused` and the model.
- `calm.desync:<n>`: moves only the model.
- `calm.confirm_prompt` and `calm.keep_prompt`: answer the question, since a headless window is never key.
- `calm.focus_next`: moves focus as ⌘] does.

## Arrival card

Behavior: FEATURES.md → F6.

- `ArrivalCard` remembers when the user left each session. It is not saved, so after a relaunch every session counts as unseen.
- Arriving shows the card only when the sidebar is hidden and the session's last activity is newer than that (`ArrivalCard.shouldShow`, tested). The last activity is `lastReport.date`, else the agent's start.
- With the sidebar showing, the card repeated the sidebar's card beside it and covered the top of the agent's screen. So it stays away then.

## Session actions

Behavior: FEATURES.md → F12, F15.

**The menu Calm draws** (since 2026-10-06). The ⋯ button and a right-click open `SessionMenuController`, not a system menu. SwiftUI's `Menu` and `.contextMenu` show only system menus, whose material takes the wallpaper's tint and whose look cannot follow the theme.

- `SessionMenuContent.make` (pure, tested) decides what the menu holds from `SessionActionSet`, the restart phase and the version news. So it offers what ⌘P offers.
- `SessionMenuOverlay` draws it over the whole window, placed with padding, so the frames it reports are where it is.
- Its host sets `safeAreaRegions = []`, as the title strip's does. Without it, the transparent title bar's safe area moved the whole overlay 32 pt down, below the ⋯ button.
- The self-test log prints the menu's frame in the overlay and in the host. They differ when the safe area returns.
- `SessionMenuHost` takes the pointer only on the menu's frames and lets everything else through.
- A local event monitor takes the keys while the menu is up, as `ClosePrompt` does. It closes the menu on a click outside.
- A left click outside is used up, as a system menu's is. A right-click goes on, so it can open another card's menu.
- Rebuilt from what a system menu gives: arrow keys, type-to-select, the projects submenu, closing on a click outside or when the window stops being key, and VoiceOver labels (each tile and row is a button with its full name).
- A right-click comes from `onRightClick`, an overlay whose `hitTest` answers only while the event being delivered is a right-click or a ⌃-click. Clicks, drags and hovering still reach the card.
- Self-tests: `calm.session_menu`, `calm.session_menu_at:<x>:<y>`, `calm.menu_key:<up|down|left|right|enter|esc>`. Each logs the menu: header, tiles, rows by group, the highlight, the projects list.

**Names and conversations (M7).**

- `Session.customName` is the user's name. `displayTitle` and `title(agentTitle:)` put it first.
- `Session.lastConversation` is an `AgentConversation` (agent, session id, transcript, title, options). `endAgentRun` keeps it when the run's id or transcript was known.
- Both are optional in the state file, so older files load.

**Resume and fork commands.** Each adapter's `resumeCommand` and `forkCommand` build the agent's own command, shell-quoted (research of 2026-09-28: Claude Code `--fork-session`, Codex `codex fork`, pi `--fork`).

- OpenCode (2026-09-30): `opencode --session <id>` resumes.
- OpenCode 2.0.19's TUI has fork code, but its command line never passes `--fork` to it: only `mini` and `run` take the flag.
- So the fork goes through OpenCode's API, the `session.fork` operation its own `/fork` dialog uses:

```sh
opencode --session "$(opencode api session.fork --param sessionID=<id> -d '{}' | awk …)"
```

- `opencode api` prints `{"data":{"id":"ses_…",…}}` on one line. awk takes the first `id` that is a session's, since macOS has no `jq` by default.
- It is tested in zsh and bash with a stand-in `opencode`. fish has `$(…)` from 3.4.
- The card menu shows an action only when its command exists.

**Options on resume and fork** (since 2026-10-10). A restart reads the running process's argv, which is gone once the agent has exited. So Resume dropped options such as `--dangerously-skip-permissions`, while a restart kept them.

- `foregroundChanged` reads the options when the probe sees the process, with the adapter's `resumeOptions(commandLine:)`.
- That uses the `CommandLineOptions` a restart uses, on `ProcessSnapshot.commandLine`. The command line starts at a runtime's script, so node's own options and the script path are not taken for the agent's.
- The options are kept as `AgentRun.options`, carried into `AgentConversation.options`, and saved (nil in older state files).
- `startAgentRun` gives them to a run first heard of through hooks. It also gives them to a run saved without them, when the probe sees the same process after a relaunch. So agents already running when Calm updates get them too.
- Each adapter builds one `resumeCommand(options:…)` and one `forkCommand(options:…)`.
- Everything built from a conversation Calm saw run goes through `resumeCommand(for:)` and `forkCommand(for:prompt:)`: Resume, ⌘⇧T, the resume after a reboot, Copy Resume Command, Fork and `calm fork`.
- A restart is `resumeCommand(options:)`, with options read fresh from the argv.
- `codex fork` takes the same options as `codex resume` (0.158's `--help`, `--yolo` included).

**⌘N's options where Calm did not see the start** (decided 2026-10-10). ⌘K's resume and `calm show` start from a transcript, whose command line Calm never saw. Agent history does not record start options, so these take ⌘N's options. This can add ⌘N's Skip permissions to a conversation started without it, which was preferred over resuming bare.

- This applies when `AgentConversation.options` is nil: a conversation from a transcript, or one that ended before options were kept.
- `options(for:settings:)` then takes `newSessionOptions(settings:)`. That is the command ⌘N would type (`launchCommand(settings:inGitRepository:)`: chips, `flags` or the whole `command`), split by `ShellWords` and read by `resumeOptions`.
- A worktree option goes as in a restart.
- A conversation Calm saw run keeps its own options, none included.
- `ShellWords` splits blanks, quotes and backslashes. It gives nil for anything more: a variable, a pipe, `;`, a glob, `~`. So a `command` it cannot read adds no options rather than wrong ones.
- `ShellWords` is a few lines of Calm's own rather than a package, since CalmKit has no dependencies.
- So `resumeCommand(for:settings:)`, `forkCommand(for:settings:prompt:)` and `SessionCopy.text(for:settings:)` take the settings. The app passes `SessionManager.settings`. `calm show` loads config.toml.

**New agent sessions** (⌘N, FEATURES.md → F15).

- Each adapter declares `launchCommand` and `launchOptions` (`LaunchCommands.swift`). The flags were read from each agent's `--help` (2026-10-06).
- An option (`LaunchOption`, CalmModel) is one of the agent's own flags, with its chip's words, and whether it needs a git repository.
- Chips are plain on/off flags that cannot contradict one another (decided 2026-10-07): no pick-one options such as a model or an effort level, so there are no conflicts to manage.
- Codex's `--search` is left out on purpose: web search is on by default (cached results), and `--yolo` already makes it live.
- The settings go over the feature budget (decided 2026-10-06): ⌘N's agent and a switch per chip.
- `launchCommand(settings:inGitRepository:)` builds what ⌘N types.
- When `agents.<agent>.command` is set, it is typed exactly as written. Settings only shows it.
- Otherwise the command is the agent's name, then `agents.<agent>.flags` as written, then the options that are on. A worktree option comes last, because Claude Code's `-w [name]` would take a word after it for the name.
- `Agents.newSessionAgent` picks the agent: config.toml's, else the first installed, which is Claude Code when it is installed.
- `Agents.installed` reads the agents' config folders, as Settings → Agents does.
- `MainWindowController.newAgentSession` opens a session as ⌘T does and types the command into it (`runAgentCommand`). `GitRoot.find` on the session's folder decides the worktree flag.
- ⌘⇧N does the same in its scratch folder.
- ⌘N reaches the menu because `CalmDefaults` unbinds Ghostty's `super+n` (`new_window`).
- The footer, the welcome page and the start line get the agents as a `StartAgents` value, read when they are built. The settings are not observed, so a change in Settings → Agents calls `applyAppearance`, and they redraw.
- Self-tests: `calm.cmd_n`, `calm.new_agent:<agent>` and `calm.scratch` log the command (`would run in …`).

**Empty worktrees** (since 2026-10-07, FEATURES.md → F15). `closeSession` kills the session's zmx session, which ends the agent at once. So Claude Code never ran the exit cleanup that removes an empty worktree it made, and each ⌘N with New worktree left one behind, locked by a process that was gone.

- `WorktreeCleanup.afterClose` (Sessions) runs right after the kill.
- When the session's `activeDirectory` is in a linked worktree (`GitRoot.worktreeName`), and no other open session's folder or agent is in it, `removeIfEmpty` runs off the main thread.
- It reads `git worktree list --porcelain` (`GitWorktree.parse`, CalmModel). The first entry is the main checkout, where the removing is done from.
- It asks the adapters whose lock it is (`AgentAdapter.worktreeOwner(lockReason:)`). Claude Code's reads `claude session <name> (pid N start …)` (from 2.1.292).
- It waits up to five seconds for that pid to be gone.
- Then it decides with `GitWorktree.isEmpty`: a blank `git status --porcelain --untracked-files=all`, and HEAD on some ref besides its own branch (`git branch -a --contains HEAD`).
- Then `git worktree unlock`, `git worktree remove` (no `--force`, so git checks once more) and `git branch -d` (not `-D`).
- A worktree no adapter claims, or no lock at all, stays as it is.
- Every outcome but that one writes a `Trace.note` line.
- `GitCommand` (Sessions) is the plain `git -C` runner the files column uses.
- Tests: the parsing and the decision on fixtures in CalmModelTests and CalmAgentsTests, and `WorktreeCleanupTests` against real repositories in `/tmp`. An empty worktree goes with its branch. An untracked file, a commit, a running owner, or a lock no agent claims keeps it.

**Typing the commands.**

- Resume types the command into the session's own shell.
- Fork splits beside the session (`MainWindowController.split`), or opens a new tab in its folder, and types it there.
- Headless self-tests log the command instead of typing it, so no test starts a real agent on the user's account. ⌘K's resume goes through the same guard.

**Reopen (⌘⇧T).**

- `SessionManager.closeSession` pushes a `ClosedSession` onto `ClosedSessions`, a stack of the last ten in memory. It holds the folder, the name, the project when the session stayed in one, `createdAt`, and the running agent's conversation.
- Scratch sessions are skipped, and so is an agent that had already exited: only what was open comes back.
- `Workspace.reopen` makes a new session through the same `newSession` path, then restores the name and `createdAt`.
- The sidebar sorts a group by `createdAt`, so the session lands where it was.
- `SessionManager.reopenClosedSession` picks the folder: its own, else the project's, else home.
- The window shows the layout and types `MainWindowController.resumeCommand(for:)` for the conversation.
- The menu item is validated through `TerminalMenuTarget`, and greyed out while the stack is empty.
- Ghostty's default binding for ⌘⇧T is `undo`, which takes the key before the menu does. So `CalmDefaults` unbinds it. A user's own `keybind` still wins.
- Self-tests: `calm.cmd_shift_t`, and `calm.agent_run:<agent>:<id>` with `calm.confirm_sheet` to close a session with an agent in it.
- The fake run needs a few seconds after the session opens, since the probe's first pass over a session ends any agent it cannot find.

**Restart** (since 2026-10-06). `SessionManager+Restart`.

- `requestRestart` either waits (`RestartPhase.afterTurn`, while the state is *working* or *needs you*) or begins.
- `runDueRestarts` starts a waiting restart when a report or a probe tick finds the turn over.
- Beginning reads the agent's argv first (`ProcessInspector.snapshot`), since it is gone once the process is. It builds `AgentAdapter.restartCommand(arguments:…)` from it.
- It quits the agent the adapter's way (`AgentQuit`): a signal, or ⌃C.
- ⌃C goes as a key event through the pane (`TerminalSurfaceView.pressControlC`), so Ghostty encodes it for the agent's keyboard mode. Without a pane it goes as the raw byte through `zmx send`. It repeats every 0.5 s while the agent has not quit.
- Calm polls for the process to be gone every 50 ms, and gives up after 5 s with nothing typed.
- Then the command is typed into the session's shell: through its pane, or through `zmx send` for a session not opened since launch. The command runs in a detached session's shell.
- While `.restarting`, `foregroundChanged` does not end the run when the agent leaves the foreground, so the card stays a card.
- The run that starts next takes over the old one's id, transcript and tail.
- A restart whose agent does not come back within 10 s ends the run, as an exit would (`endRestart`).

`CommandLineOptions` reads an agent's command line the way the agent's own parser does.

- For Claude Code that parser is commander. The valued, optional-value and variadic options come from `claude --help` (2.1.291), so a prompt is told from an option's value.
- An option missing from the lists reads as a switch. Its value then goes as the prompt, and Claude Code says the option needs a value.
- The other agents' lists come from `codex resume --help`, `opencode --help` and `pi --help`.
- `CommandLineOptions` also returns positionals, for OpenCode's folder.

How each agent quits (checked 2026-10-06 and 2026-10-07 against the real agent in a pty, at its chat screen):

| Agent | Calm sends | What the agent does |
|---|---|---|
| Claude Code 2.1.291 | SIGTERM | Quits in about 0.3 s with every mode it set reset (alternate screen, mouse, bracketed paste, kitty keys, focus events), and prints its "Resume this session with" line. Two ⌃C quit only from an empty prompt. An unsent prompt does not come back on `--resume` |
| Codex 0.159.0 | ⌃C, again if still running (twice with a draft) | Quits cleanly on ⌃C. Dies on SIGTERM, SIGINT and SIGHUP with the alternate screen, mouse, bracketed paste, kitty keys and focus events left on |
| OpenCode 2.0.20 | SIGTERM | Quits on SIGTERM and SIGHUP. It uses modifyOtherKeys (`ESC[>4;…m`), not kitty keys, and turns it off |
| pi 1.0.4 | SIGTERM | Quits on SIGTERM and SIGHUP. Dies untidily on SIGINT |

- pi sets `process.title`, which overwrites its argv: `KERN_PROCARGS2` reads `pi` and then the environment. So pi's options are lost, and its restart is `pi --session <file>`.
- A pty harness that stops reading blocks Claude Code's exit, because its goodbye fills the buffer. Whatever drives it must keep reading, as a pane does.
- Self-test, headless: `calm.agent:working`, `calm.palette_run:Restart Claude Code`, `calm.hook_stop:0`, with a stand-in `claude` (a C `pause()` loop installed as `bin/claude` → `versions/1.0.0`).
- It waits for the turn, SIGTERMs the stand-in on the Stop, and logs `claude --dangerously-skip-permissions --model opus --resume '…'` for `… --model opus 'fix the login test'`.
- Stand-ins for the other agents are a C program that answers `--version` and otherwise waits, installed each agent's way. pi's stand-in is a node script that sets its title.

**Updates** (since 2026-10-06, all agents since 2026-10-07). `AgentUpdates.check` (CalmAgents) reads, for any agent, the version it runs and whether a newer one is installed, from how it was installed. It returns both (`AgentVersions`). The session menu's header shows the running one.

- *A native program.* The launcher is the path in its argv (`~/.local/bin/claude`), resolved now (`installedProgram`).
- The process's own file is `proc_pidpath` (links resolved, nil once deleted). Its inode comes from `ProcessInspector.executableInode`: the first mapped region with a vnode, which is the program's text.
- An update is a deleted running file, a launcher leading to another file with a newer version in its path, or a new inode at the same path (`fileStatus`).
- The version is the last path component that starts with one (`2.1.291`, `0.160.1-aarch64-apple-darwin`).
- A path that names none (OpenCode's `~/.opencode/bin/opencode`) is asked `--version` (`probedVersion`). It is asked once per file, by path, inode, size and date, for two seconds at most. That is why the check runs off the main thread.
- *A script under node or bun.* Its argv can be overwritten (pi), so the program is the command the shell ran. It comes from the `_` that zsh and bash put in each command's environment (`ProcessSnapshot.commandPath`, read from `KERN_PROCARGS2`'s environment).
- A script's version is the nearest package.json's.
- A script whose status changed after the process started is an update. The status-change time is used, not the modification date, since npm dates every file 1985.
- Modification dates are not trusted for natives either: an unpacked or copied file can carry an old one.
- `SessionProbe` runs the check every fifth tick (10 s) for every agent session, in a detached task.
- `SessionManager.agentUpdates` and `runningVersions` change only when the answer does.
- Opt-in test against a real running agent: `CALM_REAL_AGENT_PID`.
- Live tests leave their stand-in's file alone. A copied `/bin/sleep` was sometimes SIGKILLed by code signing once files under it were deleted or replaced.

## Files and viewer

Behavior: FEATURES.md → F10.

**Listing (M5.3).** `FilesListing` reads the focused session's project folder off the main thread.

- In a repository it runs `git ls-files -z` (tracked), adds the untracked files `status` found (ignored left out), and runs `git status --porcelain=v1 -z` for changes and `git branch --show-current`. Big untracked folders are below.
- Repository-relative paths are re-based with `git rev-parse --show-prefix`, so a project that is a repository's subfolder works.
- Outside a repository it walks the folder breadth first, so a big first folder cannot use up the 5,000-file limit before its siblings show.
- The walk builds paths relative to the folder as it goes, which survives symlinked folders (`/tmp` → `/private/tmp`).
- `GitChange.parse` and `FileNode.tree` (CalmModel, unit-tested) turn the output into the tree.
- `FilesColumn` owns the SwiftUI view, a width constraint between the sidebar and the terminal area, and a 5 s refresh timer that runs only while the column is shown.
- The width is 272 pt at the interface size, updated with the sidebar's in `applyAppearance`.
- Rows are tapped, not selected: a list's selection is the system accent, louder than the sidebar's highlight.

**Changes first** (2026-09-29).

- Line counts come from `git diff --numstat -z --relative HEAD`: staged and unstaged together, as `status` shows them, with paths relative to the folder.
- `LineCounts.parse` keys a rename by its new path and leaves binaries out.
- `git diff` skips untracked files, so Calm counts their lines as git would (`LineCounts.lines`). A last line without a newline counts. A NUL byte in the first 8 KB means binary.
- The count is bounded because it runs every 5 s: files up to 512 KB, 4 MB per read.
- A repository without commits has no HEAD, so git counts nothing, and only untracked files are counted.
- `ChangedFile.list` orders the changes by path.
- `FileNode.rows` flattens the tree through the open folders (`FilesModel.expanded`, emptied for another folder).
- The tree is a `LazyVStack` of buttons, not an outline `List`, so its chevrons, gutter and row heights match the sidebar's.
- `ViewThatFits` drops the branch (a `GitLabel`) and a change's folder when they do not fit whole.
- Self-tests: `files_open:<file>`, `files_expand:<folder>` and `files_state`.

**Guarded folders are read when opened** (2026-09-29). Outside a repository the walk reads every folder it meets. In the home folder that includes Desktop, Documents and Downloads, which macOS guards. So the first look at the home folder asked for three permissions, and the column stayed empty while it waited.

- `GuardedFolders` (CalmModel) names them.
- `FilesListing.walk` does not enter one below the root unless it is in `opened`. It lists it in `Result.unread` instead.
- `FileNode.tree(…, unread:)` shows an unread folder as an empty folder.
- Opening it (`FilesModel.toggle`) adds it to `opened` and reads again. So the prompt comes when the user asks for that folder, and every later 5 s listing reads it.
- A root that is, or lies inside, a guarded folder is read whole: the user chose it.
- No probe for Full Disk Access is needed, since the folders stay visible either way.
- Known gap: a folder the user opened and macOS refused shows empty, with no word why. A quiet note with a link to System Settings → Privacy & Security is the place for it, if it proves confusing.
- iCloud Drive, removable and network volumes are guarded too, but a walk does not reach them by itself. iCloud Drive sits in the hidden `Library`.
- A repository is listed through git, not walked, so none of this applies to it.
- The first launch reads the three folders once to ask for them up front (Attention → Permissions at first launch).

**Big untracked folders** (since 2026-10-11). A project whose `node_modules` or build output was not git-ignored showed tens of thousands of `U` rows. Calm listed, parsed and drew them, and read up to 4 MB of them for line counts, every 5 s.

- `status` runs without `-uall`, so git reports a folder with nothing tracked in it as one `dir/` entry, without reading inside it.
- `UntrackedFolder` (CalmModel, tested) takes each such folder's `git --literal-pathspecs ls-files -o --exclude-standard -z -- <dir>` as bytes (`GitCommand.data`).
- It counts the NULs without decoding, and decodes the files only up to `limit` (500).
- `merge` then swaps the `dir/` entry for its files, each untracked, or for one untracked entry for the folder, returned in `FilesListing.Result.collapsed` with the count.
- `FileNode.tree(collapsed:)` makes it an empty folder with `unlisted`.
- `ChangedFile.list(collapsed:)` makes it a row with `files`.
- `countUntracked` skips it, so it has no lines, and the header's total leaves it out.
- `ChangeSummary(collapsed:)` counts it as its files.
- The views draw it with the count instead of a chevron, dot or lines. It is not a button.
- git still walks the folder for `ls-files -o`. What is saved is Calm's side: parsing, rows, stats and reads.
- The project folder itself, untracked, is always listed (an empty path).
- Self-test: a scratch `CFFIXED_USER_HOME` that is a git repository, with a 620-file untracked folder, a 3-file one and an ignored one.

**Finding the column** (decided 2026-09-30 from mockups: the footer row, plus the readout).

- The sidebar footer's fourth row is `footerRow("Show Files" / "Hide Files", …, on: files.isShown)`.
- `SidebarView` takes the `FilesModel` itself (observed, unlike `manager.settings`), so its `isShown` redraws the row.
- `SidebarActions.toggleFiles` is shared with the title strip.
- The title strip's readout is `ChangeSummary`, drawn by `ChangeReadoutView`. `ChangeSummary` (CalmModel, unit-tested) takes the file count from the same `changes` map as the column's Changes, and the lines via `LineCounts.total`. It is nil when nothing changed.
- `FilesListing.readSummary` runs the same three git reads as `read` (`readChanges`: status, `diff --numstat`, the bounded untracked count) without the tree.
- It returns nil outside a repository, so a plain folder is never walked for it.
- `SessionTitleView` calls `FilesModel.watchSummary(of:working:)` through `.onChange` of the project folder and whether the focused session is `.working`. That covers a new session, a project change, and a turn starting or ending.
- `refreshSummary` also runs when Calm becomes the active app and when the column closes.
- While an agent works, an 8 s timer runs. It is the only timer, and it stops when the agent does.
- The open column keeps `summary` current from its own 5 s listing, and `refreshSummary` does nothing while the column is up (`isShown`).
- A root that is Desktop, Documents or Downloads itself is never read this way, since nothing has asked macOS for it.
- The title row is four explicit `ViewThatFits` children: worktree and readout, worktree, readout, neither. So the readout gives way before the worktree, which gives way before the name or folder.
- The readout is nil while the column is up.
- The readout reports its frame to `SessionTitleHost` keyed by a per-view id (`setReadoutFrame`). So one variant going cannot erase the frame of the one that replaced it.
- Self-test: `CFFIXED_USER_HOME=<a scratch git repo>` makes the test session's project a repository. Add `.gitignore` entries for `Library/` and `.zsh*`, which the app and the shell write into a redirected home.

**Layout motion.** The sidebar and the files column change width through `Motion.animateLayout`.

- It sets the constraints to their final values at once, then glides only the layers (position and bounds, presentation-only).
- The terminal resizes once, not on every frame: each resize reaches the program (SIGWINCH), and agents redraw on each.
- AppKit's `animator()` constraint animation is not used for this. Its timer also stalls outside event handling, which left the layout half-changed.
- Both columns lay out their content at full width and clip it, so they never squeeze while sliding.

**Viewer, decided (M5.4): a web view for Markdown, HTML, code and text, PDFKit for PDFs, an image view for images.**

- Agents write GitHub-flavored Markdown (tables, fenced code). A native path would need a hand-written block renderer, because `AttributedString(markdown:)` does not render tables, plus a separate highlighter.
- HTML needs a web view anyway.
- The page (`Calm/Resources/Viewer/viewer.html`) uses markdown-it 15.0.2 (MIT) and highlight.js 11.12.0 (BSD-3-Clause). They are pinned with checksums in `scripts/viewer-assets.sh` and committed, so builds stay offline.
- Raw HTML in Markdown is off.
- HTML and SVG files open with page JavaScript off (`allowsContentJavaScript`, since 2026-10-12). Calm's own `evaluateJavaScript` calls still run.
- A text file is read as UTF-8, else the encoding macOS detects, else Latin-1, which maps every byte. So a legacy-encoded file still opens.
- Colors come from Calm's palette (`SidebarStyle.viewerColors`), with low-saturation code tones.

**Opening files (M5.5, M5.6).**

- `ViewableKind` picks the kind by extension. A small UTF-8 file without a known extension shows as text. A file over 5 MB opens outside Calm.
- The viewer covers the terminal area, not the sidebar. It is pinned to `mainArea`'s edges by constraints, because a fixed frame was left behind when the files column closed.
- It remembers the session it was opened over. `closeViewer(unlessOver:)` closes it when another session shows (`select` and `showSelectedLayout`).
- For `path:line`, code gets the line highlighted and centered.
- Links in a viewed file open in the browser or, for local files, through the same link opener.
- ⌘-clicked files open in the viewer when it can show them. `open-in = "editor"` under `[files]` in config.toml prefers the editor.
- `calm open <file>[:line]` opens the same way.

**Header and diffs** (since 2026-10-07). Diffs are for reading what changed, not for staging or review (decided 2026-10-07: review belongs in the editor, and Calm stays built for reading).

- The viewer's root is pinned to `mainArea`'s four edges, so it starts under the title strip, which stays `SessionTitleView`. `mainArea` starts 48 pt down, so nothing else had to move.
- The root sits in `container`, not in `mainArea`, where `showSelectedLayout` adds workspaces on top.
- The root takes the terminal's background at full opacity (`showFile` passes `focusedPane.effectiveBackgroundColor`). It copies a card's border, which it would otherwise cover.
- `FileViewer.presence` (`ViewerPresence`, observable) tells the strip a file is open.
- `titleRow` wraps the title block in `TitleBackButton`, which reports its frame through `onControlFrame` like the readout. So `SessionTitleHost` passes its clicks, and the rest of the strip still drags the window.
- The file's row is `ViewerHeader` (its own file), 40 pt.
- Its leading inset is `SessionTitleView.leadingInset + markSide + 10`. The page gets it as `--gutter`, so code starts under the name.
- With the sidebar hidden, the strip moves past the traffic lights, and the two no longer line up. This is accepted.
- `ViewerChange.read` runs off the main thread, a `Task.detached` per open.
- It runs `git diff --no-color --no-ext-diff --no-textconv -U3 HEAD -- <name>` in the file's folder, staged and unstaged together like the column's `--numstat HEAD`. It runs `git show HEAD:./<name>` for the old text.
- A diff of one all-added hunk from 0,0, an untracked file, or an added file with no HEAD is `.new`. Anything else (no repository, ignored, binary) is `.unchanged`.
- `FileDiff` (CalmModel, tested on real `git diff` output) parses the hunks and pairs each run of removed and added lines.
- The first as many added lines as removed count as modified, the rest as added, and extra removed lines as a deletion before the next line. The split rows pair the same way.
- A modified pair's changed words are what lies between their shared start and end. They are kept only when the pair shares a third of the longer line. They are in UTF-16 offsets for the page.
- `pagePayload` hands the page line numbers, not text.
- `viewer.html` highlights the whole old and new texts once each and indexes their lines, so a comment or string across lines keeps its color.
- `splitLines` closes the spans open at each line's end and reopens them on the next. The File view uses it too.
- The page wraps the emphasized offsets through the highlight's spans with a TreeWalker.
- The switch calls `calmSetMode`. Scripts wait in `pendingScripts` until the page has loaded, since git can answer first.
- Opened from Changes (`FilesModel.open(_:fromChanges:)`), a changed file goes to Unified once its diff is read.
- Self-tests: `files_change:<file>`, `viewer_mode:<mode>` and `viewer_state` (the counts, the mode, and how many marks and diff rows the page drew).

**Size** (since 2026-10-11). ⌘+, ⌘− and ⌘0 reached the terminal under a viewed file, which changed size out of sight while the file stayed as it was.

- The viewer's key monitor now takes them: `=` or `+`, `-` and `0` with ⌘, the keypad's too.
- `performViewerAction` takes the View menu's Bigger, Smaller and Actual Size while a file shows.
- `ViewerZoom` (CalmModel, tested) holds the steps: a browser's for a page (0.5–3), wider for a picture (0.5–8).
- From a size between two steps (a pinch leaves one), it steps to the nearer one in that direction.
- `ViewerZoomTarget` (`FileViewer+Zoom`) says what gets sized.
- Any web view (Calm's page, an HTML file, an SVG, the session page) uses `WKWebView.pageZoom`, which scales the whole page as Safari's zoom does.
- A PDF uses `PDFView.scaleFactor` as a multiple of `scaleFactorForSizeToFit`, and `autoScales` again on ⌘0.
- A picture uses `ViewerPictureView`, an `NSScrollView` with `allowsMagnification`.
- Its document is the picture at its fitted size, computed again in `tile` from `contentSize`, which magnification does not change. Its clip view centers a document smaller than it.
- Only a file's page keeps its size: `Workspace.viewerZoom` (nil at 1), written through `changeWorkspace` and saved like `fontSize`.
- An SVG, a PDF, a picture and the session page start at their own size.
- `pageZoom` would scale the viewer's own parts with the file. So `viewer.html` gets `calmSetZoom(z)` and divides by it.
- `--gutter` is the header's inset over z, at least 26 px: the room a diff's − and + take, 22 px left of the text.
- The find map's lengths are `--pt` (1px over z), in its CSS and in `drawMap`'s slots.
- WebKit keeps the scroll offset across a zoom, which then no longer points at the same text.
- So before `pageZoom` changes, a script notes the element at the top of the view (`elementFromPoint`, skipping `main` and the map) and how far into it the view starts. After the change, a script scrolls that element back.
- The two scripts and the zoom reach the web process in order, over one connection.
- Settings opens over a viewed file, so the key monitor stands aside while `isCovered` (Settings showing). Before, esc in Settings closed the file under it.
- Self-tests: `cmd_plus`, `cmd_minus` and `cmd_zero` post the keys. `viewer_scroll:<y>` scrolls. `viewer_zoom` logs the size, the page's scroll, gutter and top line, the saved size and the terminal's text size.
- Headless snapshots draw a PDF's pages blank, zoomed or not, so check a PDF's size by its scale alone.

**The size in the row** (decided 2026-10-11 from mockups: a quiet readout at rest, a stepper under the pointer).

- `ViewerModel.zoom` is what the row shows.
- `FileViewer.noteZoom` sets it after every change, inside `Motion.animate`, so the size fades in and out.
- It reads `webZoom`, or a PDF's `scaleFactor` over `scaleFactorForSizeToFit` (1 while `autoScales`), or a picture's `magnification`.
- A pinch reaches it through `PDFViewScaleChanged` and `NSScrollView.didEndLiveMagnifyNotification` (`zoomObservers`, removed in `stopZoom`).
- `ViewerSizeControl` is laid out whole at rest, with the track and both buttons at opacity 0, so the number does not move when they appear.
- `ViewerModel.zoomHovered`, written by its `onHover`, keeps it in the row at 1 (`ViewerZoom.showsSize`).
- Its clicks go through `ViewerModel.onZoom` to `zoom(bigger:)`.
- The row is `HStack(alignment: .firstTextBaseline)`. Views with no text of their own give their baseline by alignment guide.
- The back button's slot sits at its middle, plus the 14 pt name's half cap height, plus half a point: SF's `chevron.left` draws that far under its frame's middle.
- Find's field sits at its middle, plus the distance from a 12.5 pt line's middle to its baseline, where the buttons' middles are.
- Open in Editor lays out a hidden "Open in Preview" under its label, for its narrowest width.
- Self-tests: `viewer_size_hover:on|off` (a headless window gets no hover) and `viewer_size_click:minus|plus|size`.

## Themes

Behavior: FEATURES.md → F11.

A theme is a small TOML file with a light and a dark variant. Either can be left out, and the other then serves both:

```toml
name = "Forest"

[dark]
background = "#1f2e28"
foreground = "#c8c3af"
cursor = "#…"           # optional
selection = "#…"        # optional
palette = "#…, #…, …"   # optional: the 16 ANSI colors, comma-separated
sidebar = "#…"          # optional: the sidebar's background (else derived)
accent = "#…"           # optional: the chrome accent (else Calm's amber); never a state color

[light]
…
```

**Reading themes (M6.1).** `CalmTheme` and `ThemeLibrary` (CalmModel, unit-tested) read the files with the same flat TOML reader as config.toml.

- A bad color is dropped, and a variant without a background or foreground is left out, each with a logged problem. The rest of the theme still works.
- Built-in themes are bundled from `Calm/Resources/Themes`.
- User themes live in `~/.config/calm/themes/`. One with a built-in's name replaces it.
- `theme = "Name"` in config.toml picks one.

**The built-in set.** Five themes (Calm, Ink, Dusk, Forest, Plum) in light and dark, written by `scripts/themes.py` from OKLCH values per theme and role. The script also checks their contrast.

- Each theme is a direction of its own (a hue, a depth or both), not a tint of another. An earlier set of six came from one generator that changed only the background's tint, and read as one theme six times.
- Calm is Ink's neutral gray, hues and accent, with a lifted background and softer text.
- The palettes are original, not copied from other themes.
- Text is 6.4–8.3:1 against the background.
- The six ANSI hues stay below the text's contrast in dark, and at least 4.3:1 in light.
- Bright white stays within 1.2× the text's contrast, since agents draw emphasis in it, and Claude Code's ANSI themes draw their body text in it.
- A unit test holds the shipped files to these.

**Not the theme's to change:** colors an app sends as truecolor.

- Claude Code's `dark` theme draws its text in pure white, about 14:1 on Calm, whatever the theme.
- Its ANSI themes, or a custom Claude Code theme with `"text": "ansi:whiteBright"` in `~/.claude/themes/`, follow the terminal's colors.

**OpenCode wears the theme** (since 2026-09-30). OpenCode's own themes are truecolor too. The default paints near-white text on near-black with bright orange headings, on every Calm theme.

- The shells Calm starts ask OpenCode for a theme through `OPENCODE_CLI_CONFIG_CONTENT`. It is the OpenCode adapter's `shellEnvironment`, next to Claude Code's plugin folder in `AgentIntegrations.environment`, read at each new session.
- OpenCode 2 merges the variable over `cli.json` without writing it. 1.x does not read it.
- The variable is left out when the user named a theme, or set the variable themselves.
- A named theme is `theme.name` in `cli.json`, found where OpenCode looks: `$OPENCODE_CONFIG_DIR`, `$XDG_CONFIG_HOME/opencode`, `~/.config/opencode`.
- Unconnected, or with the user's own Ghostty colors, the variable asks for `system`.

**Calm's own theme, `calm`, while OpenCode is connected.** OpenCode's `system` theme takes the terminal's colors but arranges them its own way (2.0.19's code). It puts its agent color and message bars in the palette's magenta, its boxes in a lift of its own across the whole width, and its dim text in a fixed gray nearly as bright as the text.

- `OpenCodeTheme` writes `~/.config/opencode/themes/calm.json` in OpenCode 2's theme format. The format comes from its built-in `opencode` theme: `base` gives every role as a reference into hue scales, and a mode gives the scales.
- The theme uses Calm's accent for the agent color, links and the bars, and a dim text clearly dimmer than the text.
- Boxes lift only slightly (5.5% toward the text). Headings and bold use the palette's strongest text, not a color.
- The background is transparent, so the padding and title strip match.
- OpenCode reads theme files only from a folder (its config's `themes/`, or a project's `.opencode/themes/`). So Calm writes one only for a connected OpenCode, with the marker in `$comment`. OpenCode ignores keys it does not know.
- `AgentSetupFiles.syncTheme` writes it while the plugin is there and a Calm theme is on screen. That is `TerminalTheme.onScreen`: a picked theme, or the default unless the user's Ghostty config sets colors.
- It removes the file otherwise (Disconnect, the user's own Ghostty colors), and never touches a `calm.json` Calm did not write.

**One appearance in the file.** For any theme but `system`, OpenCode picks light or dark from the palette it cached the last time `system` ran, not from the terminal. A theme with one mode always shows in that mode.

- So the file holds the appearance on screen.
- Calm rewrites it at launch, on every config reload (a theme picked, Increase Contrast), on an appearance change, and after Connect or Disconnect (`AgentIntegrations.syncThemeFiles`).
- Unchanged colors leave the file alone.

**A running OpenCode follows.** OpenCode reads its theme files again on SIGUSR2 (`subscribeRefresh`).

- Calm's plugin watches `themes/` and sends its own process SIGUSR2 when `calm.json` changes.
- It does this only while OpenCode listens for the signal, since an unhandled SIGUSR2 ends a process.
- Test it in a scratch home: `CFFIXED_USER_HOME` and `--agent-files`, OpenCode pointed at it with `OPENCODE_CONFIG_DIR`, and a real conversation opened with `--session`, with no model call.

**The costs** (2.0.19's code).

- While the variable is set, it outranks `cli.json`. A theme picked in OpenCode's settings is saved but shows from the next session on, which then leaves the variable out.
- A shell keeps the environment it started with, and sessions run under zmx. So a session from before asks for nothing until a new one.
- An OpenCode without the plugin keeps the theme it started with.
- Calm does not soften any app's truecolor in the terminal. The nearest tool, Ghostty's `minimum-contrast`, was dropped (Accessibility), and it would change colors apps chose on purpose.

**pi wears the theme too** (since 2026-09-30). pi's built-in `dark` paints the user's message on a blue-green slab, section titles in orange, and the prompt's frame in a pink that strengthens with the thinking level. Its `system` theme takes the palette but places the colors its own way.

- `PiTheme` writes `~/.pi/agent/themes/calm.json` for a connected pi, in 0.99.1's theme format.
- pi's `theme-schema.json` (a test fixture) allows no key it does not name. So the marker is an unused entry in `vars`.
- The theme uses Calm's accent for the accent and the prompt's frame. A thinking level only strengthens the frame, from gray when off.
- It sets a muted and a dim text, each dimmer, message and tool boxes that barely lift, and headings in the strongest text.
- Every color is written out, and the file holds the appearance on screen, as for OpenCode. The same `AgentSetupFiles.syncTheme` keeps it.
- pi's logo keeps its own colors.

**Applied by the extension, not the settings.** pi has no variable for its theme. `ctx.ui.setTheme` with a name also saves it to `settings.json`, which would carry Calm's theme outside Calm and lose the user's choice.

- So Calm's extension, at `session_start` and inside Calm only, builds pi's theme object from the file and sets that.
- It builds the object with the class of the theme in use (`ctx.ui.theme.constructor`), with the colors split into pi's background roles and the rest.
- An object is not saved. pi's theme controller leaves it alone when the terminal's colors or appearance change (`reapplyForTerminal`).
- pi does not watch an object's file. So the extension watches `themes/` and sets the theme again when Calm rewrites it.
- It closes that watcher at `session_shutdown`, since a reload runs the file again.
- `/reload`, `/new`, `/resume` and `/fork` emit `session_start`, then call `themeController.applyFromSettings()`. That puts the setting's theme back about 10 ms later (pi 0.99.1).
- There is no event to wait for. So for two seconds after each `session_start`, the extension looks every 10 ms and sets Calm's theme again wherever pi's has taken its place.
- It does this only while pi's own theme is a built-in (`system`, `dark` or `light`). A theme the user made stays.

**How a theme reaches the terminal** (`TerminalTheme`). Ghostty ranks a theme file's colors below any color set directly in the config, wherever it is set. `theme =` goes to the last file that sets it.

- The default theme (Calm) is written as two Ghostty theme files and `theme = light:…,dark:…` in Calm's defaults.
- A theme or colors in the user's Ghostty config win over the default, so an existing setup carries over. Ghostty switches light and dark itself.
- A theme picked in Calm is written as plain colors for the current appearance to `choices.ghostty`, with the other terminal-side choices from Calm's settings.
- `choices.ghostty` is loaded after the user's config, so it wins.
- When the system appearance changes, Calm rewrites it and reloads.

**Chrome (M6.2).** The sidebar, cards, panels, files column and viewer derive their colors from the terminal's background (`SidebarStyle.derived`).

- When that background is a Calm theme's, the theme's sidebar color, foreground (for text), accent and red are used instead.
- The accent colors chrome only (`SidebarStyle.accent`).
- *Needs you* stays Calm's amber (`SidebarStyle.attention`), since a blue or green accent read as *working* or *done*.
- With the user's own Ghostty colors in effect, everything stays derived.
- Glass or solid, and card or edge to edge, are window options (M6.4), not part of a theme.

**Picker (M6.3).** `ThemePickerModel` gives each theme's colors for the current appearance: background, text, sidebar, hues, cursor, accent.

- `AppearanceSection` draws them as chips and as `WindowPreview`, a miniature of the window with the picked layout and background.
- A pick saves `theme` with `CalmSettings.save` and reloads the Ghostty config.
- Picking Calm, the default, still writes `theme = "Calm"`, so it wins over colors in the user's Ghostty config. Only the Ghostty choice removes the key.
- The Ghostty choice appears when `TerminalConfig.userColors` finds colors in the user's own config.
- A config resolves `theme = light:…,dark:…` only inside a surface. So the pair is read from the files (`CalmTheme.ghosttyThemePair`), and the probe loads one extra `theme =` line per appearance.
- Colors set directly still win, as in the terminal.

**Window options (M6.4).** `WindowStyle` owns the terminal area's insets and an `NSVisualEffectView` under everything.

- Glass makes the window non-opaque, shows the effect view, and sets Ghostty's `background-opacity` (0.84) in `choices.ghostty`, so it wins over the user's Ghostty config.
- This avoids Ghostty's private-API window blur.
- With glass, the sidebar and files column keep 55% of their color. The viewer and panels stay solid, so nothing reads through them.
- Card insets the terminal area by 8 points (sliding through `Motion.animateLayout`) and rounds it (10 points, continuous corners, a faint border), on a window painted in the sidebar's color.
- The viewer takes the same corners.
- Settings → Appearance saves each option. A default removes its key.
- It reloads the Ghostty config only when the terminal side changes: glass, or motion, which turns the cursor shader on and off.

**Adaptive background.**

- When an app paints the terminal's background (OSC 11, `COLOR_CHANGE`), the pane's override feeds `applyAppearance`.
- The chrome derives from the new color. The theme's tints drop, since its background is no longer on screen.
- The sidebar eases into the new color over 0.35 s.

**Settings screen (M6.5).** Behavior: FEATURES.md → F14.

- `SettingsPage` puts one `NSHostingView` over the whole window, as `WelcomePage` does. It is drawn in the chrome's `SidebarStyle`, restyled when the theme changes.
- Its list is `SidebarView.width` wide and drawn like the sidebar's footer rows, a size up. `SettingsMetrics` holds the page's sizes.
- A local key monitor takes esc while the page is on top.
- An extension of `MainWindowController` opens and closes it, hands focus back to the session, and pauses the sidebar peek meanwhile.
- `select` and the new-session paths close it. A config reload refreshes its models.
- Each section has a small `@Observable` model (`ThemePickerModel`, `WindowOptionsModel`, `AgentsSettingsModel`, `GeneralSettingsModel`) that saves through `CalmSettings.save`. A default removes the key. Comments and unknown keys stay.
- The controls in `SettingsComponents` (segmented, switch, buttons, menus) are drawn in SwiftUI, because AppKit's know only the system accent.
- Ghostty's C API cannot return `font-family`: a repeatable key has no C value. So `GhosttyConfigText.fontFamily` reads it from the config text.
- The size shown is the shared one (⌘+ and ⌘−), or the config's `font-size`.
- Blocked notifications come from `UNUserNotificationCenter.getNotificationSettings`. Self-tests never ask, and `CALM_NOTIFICATIONS_BLOCKED=1` shows the notice.
- The page's scroll view hides its indicators: with them, headless snapshots drew the page blank.
- Self-tests drive it with `settings`, `settings:<section>`, `set:<key>=<value>`, `pick_theme:<id>` and `report:<state>`. They log the files and the System Settings pane it would open.

**Accessibility (M6.6).** `AccessibilitySettings` reads Reduce Motion and Increase Contrast, and reloads the config when either changes. Self-tests force Increase Contrast with `--increase-contrast`.

- With Increase Contrast, `SidebarStyle.contrasted()` strengthens the chrome.
- `CalmTheme.Colors.contrasted()` (CalmModel, tested on every built-in theme) lifts each text color toward white or black until it reaches 4.5:1.
- Ghostty's `minimum-contrast` was tried first and dropped: it swaps short colors to white or black, which made dim text brighter than normal text.

**Interface size.** `InterfaceScale.shared.factor` multiplies the chrome's sizes. It is an `@Observable`, set from `CalmSettings.interfaceSize` whenever the settings change.

- `.calmFont(size:)` scales type. `.scaled` scales lengths: frames, paddings, spacing, corners. 0 and 1 stay, so hairlines stay hairlines.
- Views read it in their bodies, so a change redraws them.
- `applyAppearance` resizes the sidebar's width constraint and its peek.
- SwiftUI's Dynamic Type does not reach fixed-size fonts on macOS, so the chrome scales itself.
- The window miniatures in Settings keep their own proportions, and the session switcher's live previews keep their size.

**Session card sizes.** `SessionCardLayout` (CalmModel, tested) says what goes under a card's title for a size and a state: the recap alone, Full's stacked lines, Compact's merged state and recap (two lines for a state that waits for a look), or nothing.

- `SessionCard` draws it and colors Minimal's time.
- `makeSidebar` passes `settings.sessionCardSize` to `SidebarView` as a value. `applyAppearance` rebuilds the sidebar after `WindowOptionsModel` saves, and the list's `.animation(value:)` eases the heights.
- A setting the chrome draws from reaches its view as a stored value, like `style`. Read from `manager.settings` in the body, it did not update: the settings are not observed, so SwiftUI kept the old cards.
- In self-tests, the probe's workspace writes every 2 s hide that fault. Take a snapshot within a second of a change to see it.
- `AccessibilitySettings.differentiateWithoutColor` brings Minimal's state mark back. Self-tests force it with `CALM_DIFFERENTIATE=1`. The system's display-options notification already reapplies the appearance.
- Self-tests set the size with `--config '[sidebar]\ncards = "compact"\n'` or `set:cards=<size>`.

**Shrink to fit** (`sidebar.cards-fit`). `SidebarView` reports its scroll view's `contentSize` and `containerSize` (`onScrollGeometryChange`) to `SidebarCardFit`, an `@Observable` in the view's state. It asks `SessionCardFit` (CalmModel, tested) for the size to draw.

- Stepping down is exact: the drawn list is taller than its room.
- Stepping up is a guess from `SessionCardLayout.nominalHeight` (the drawn heights, with recaps counted as filling their lines), with a 16 pt margin.
- The guess can be short. A waiting card's merged line guessed at two lines draws one when its message is short. So Compact's cards come out smaller than guessed, and Full's guess from there is too small.
- Working agents change the contents every few seconds. So without the rules below, the size flipped at every state change near the edge.
- The first measurement after a step down, with unchanged contents, records how short the guess for the larger size was (`shortfall`). It is added to later guesses.
- After a step down, growing waits `settle` (30 s). `SidebarCardFit` schedules a look when it ends.
- `drawn` keeps each size's last drawn height, with the contents hash it was drawn with. The hash covers the rows in open groups, what the cards hold, the number of groups and open groups, and the interface size. The room is not in it: the model keeps the room itself.
- A size drawn taller than its room is not tried with those contents until the room is as tall.
- When the room is larger than the one the cards last stepped down in (`steppedDownIn`), growing does not wait. A size drawn with the same contents goes by its drawn height, without the margin.
- In the same room, growing still takes the guess and the margin, because a recap growing a line changes a card without changing the hash.
- `restoreFrame` runs before `buildLayout`. Otherwise the sidebar's first look measured the saved windowed frame instead of the filled screen, and stepped down too far.
- `SidebarCardFit` keeps the whole `SessionCardFit` after every measurement (unobserved), and observes only the drawn size. Keeping it only when the size changed lost what was learned in between.
- Changes in the first second after the sidebar's first layout apply without animation.
- Each change leaves a trace line, for example `cards fit: full → compact, list 551 in 506`.

**Self-tests** leave the user's Ghostty config out unless asked (`--ghostty-config`), and write Calm's generated files to their own folder (`CALM_SUPPORT_DIR`). They can force the appearance with `--appearance light|dark` or `calm.appearance:<mode>`.

## Motion in the window

- The window's content view is layer-backed, so fades and slides run on Core Animation.
- Without layers, AppKit falls back to timer-driven animation, which never ran when started outside event handling (for example from `calm open`). That left a new session's workspace at alpha 0.
- The layout fade is a presentation-only `CABasicAnimation`. The view's own alpha stays 1, so a skipped animation cannot leave a session invisible.
- Overlays (the switcher, the peeking sidebar) are removed on a timer, not in an animation completion handler. So one can never linger invisibly over the terminal and take clicks.
- `Motion` is the one switch: no animation when the system's Reduce Motion is on, or when `motion` is `reduced` or `off` in `config.toml`.

**Session switcher.**

- A local event monitor sees ⌃Tab before the terminal does and consumes it. It also consumes Esc, Return and the arrows while the switcher is open. So Ghostty's own ⌃Tab binding never fires.
- The switcher shows only after about 160 ms of holding ⌃, like ⌘Tab.
- Previews are `cacheDisplay` snapshots of each session's pane, refreshed every 250 ms.
- Panes in hidden layouts are un-occluded while the switcher is open, so their previews stay live. They are occluded again when it closes.
- It cycles in sidebar order (`SessionManager.orderedSessions`, which ⌘1…9 use too).

**Sidebar peek.**

- A 6 pt sensor at the left edge slides a second sidebar view in over the terminal. The sensor is a tracking area only, and never takes clicks.
- The peek slides away 350 ms after the pointer leaves it.

## Motion in the terminal

**Padding and title strip.** Calm's defaults set `window-padding-color = extend`, so the padding takes the nearest cell's color.

- libghostty does not expose that color. So each pane watches its layer's `contents` (the IOSurface libghostty renders into).
- It samples the middle of the top row at most every 0.1 s (`SurfaceEdgeColor`), in the frame's color space (Display P3).
- It compares the sample with the pane's sides: the first and last pixel of 32 rows spread over the height. The padding there takes each row's edge color.
- When at least half of them agree, the app painted its pane in that color (OpenCode, Neovim), and the strip takes it.
- Half, not most, because one side can be a column in its own shade (Neovim's sign column, a file tree).
- When they do not agree, the top row is a band across the top (Claude Code's sticky prompt), and the strip keeps the theme's background.
- The middle of the pane is never read: it is content. A fallback to the body's most common shade turned the strip green under a long diff in Claude Code (removed 2026-09-30). Content almost never runs out to both sides, while an app's background always does.
- The window paints the title strip with the focused pane's sample, edge to edge, on a solid background.
- The sidebar still derives from the theme's background.
- Side-by-side splits share one strip, so the strip follows the focused pane.

Left and right, the padding beside a row takes the edge cell's color only in two cases (engine patch 0009, since 2026-09-29):

- the row's first (or last) three cells share that color
- the row above or below has that color at the edge

The reasons:

- A background painted out to the edge still extends, but a lone cell does not.
- pi draws its cursor as a reverse-video space. At column 0 of an empty prompt, the padding took its color: a block twice a cell's size, running to the pane's edge. The same happened over a wide character and at the last column.
- Three cells is the widest cursor plus one.
- OpenCode paints every cell of its pane and keeps a two-cell margin. Its message panels, scrollbar and prompt box begin the third cell in, so the first three cells of those rows differ. The column beside them is still one color down the whole pane, which the neighbor rule catches.
- The neighbors are looked up through smooth scrolling's shift and region animations, like the edge cell.
- Check with `scripts/selftest.sh padding --type "bash $PWD/scripts/fixtures/edge-cursor.sh"`. The fixture's header says which rows extend.

**Cursor glide.** `Calm/Resources/Shaders/cursor_glide.glsl` is a Ghostty custom shader. It uses the `iCurrentCursor`, `iPreviousCursor` and `iTimeCursorChange` uniforms.

- `CalmDefaults` writes `~/Library/Application Support/Calm/defaults.ghostty` at each launch, with `custom-shader` and `custom-shader-animation = cursor`.
- That file loads before the user's Ghostty config, so the user's settings win.
- The glide is skipped when Reduce Motion is on.
- `cursor` (engine patch 0014) runs the focused pane's animation loop only for a second after its cursor moves or it gains focus. A still pane draws nothing.
- With Ghostty's `true`, the loop redrew every 8 ms for as long as the pane was focused, for a glide that lasts 140 ms. It also kept the display link and the compositor at the display's full rate.
- Since 2026-09-30, an idle focused shell costs 0.3% of a core and 21 wakeups a second, against 5.9% and 940 with `true`.

**Smooth scrolling** (since 2026-09-29). Upstream Ghostty draws only whole rows. Smooth scrolling comes from engine patch `0005-smooth-scroll.patch` (Tech stack → Engine patches), behind its `smooth-scroll` key.

- `CalmDefaults` writes the key with full motion only (the same gate as the cursor glide).
- It writes the key only when the engine knows it (`GhosttyRuntime.hasSmoothScroll`). An unpatched build would report it as unknown.
- A trackpad scroll keeps its sub-row remainder and draws the viewport between rows, momentum included.
- On the alternate screen, a scroll of a region by whole rows is drawn as motion: DECSTBM/DECSLRM with SU/SD, or IND/RI at the margin.
- The region's new content starts where the old content was and eases home (τ = 45 ms). The rows that scrolled out slide away as ghost rows.
- A scroll of the same region mid-ease adds to it.
- This makes Claude Code's full-screen view smooth. As an answer streams, it scrolls its transcript region by about a dozen rows every 100 ms or so, which stock Ghostty draws as a jump each time.
- A resize's leftover height (under a row) is drawn as a pixel offset, so a divider drag slides the content. At rest, part of the scrollback row above the viewport can show at a pane's top.
- Clicks, selection, mouse reports and the IME position all use the rows as drawn.
- 0006 makes a custom shader's `iCursorVisible` 0 while the cursor is scrolled out of view or blinked off, so the glide never smears from a stale spot.

**0008 and 0012: overlays stay still.** Claude Code, scrolled back, redraws its "Jump to bottom" hint on its region's last row after every scroll. Animated with the region, the old copy slid out as a ghost row while the new one slid in, so two or three hints showed at once.

- The renderer compares the region's top and bottom rows before and after each scroll.
- A row with an unchanged run of cells that have a background color and text (the hint's grey box) was repainted in place. Plain text never counts, so streaming is unchanged.
- 0012 pins only those cells, not the whole row (since 2026-09-29). The row also holds the transcript's last line, which must slide with the rest.
- The region animates whole, edge rows included. The run 0008 finds (`repaintedInPlace` returns its columns) is a hole in it, one per edge row (`Overlays`, `region_hole`).
- In the shaders, a cell in a hole belongs to no region, so it is drawn in place, with the hint drawn once.
- Content sliding through the hole is cut off there (the text fragment stage discards it). The hole's own cells are never drawn as content, so neither the old hint (a ghost row) nor the new one (the row sliding in) shows.
- The hit test skips the cells too (`RegionHole`, `RegionShifts.addHoledScroll`), so a click on the hint lands on it while the text beside it slides.
- A ghost of the old bottom row is made without the overlay's columns (`ghostCells`).
- The renderer often takes several scrolls in one frame: Claude Code's come about 5 ms apart under a trackpad flick. Each scroll makes its ghosts from the frame before. Without `ghostCells`, the second scroll's copy of the old bottom row slid down the region as another hint.
- The hole also hides text. The program draws the hint over the middle of its row, so the terminal holds nothing there. Scrolling back, the new bottom row would slide into the hint's row with a hint-shaped blank in it.
- That text is in the frame before, on the row the line slid from. `overlayFills` says which row, from the frame's scrolls of the region added up.
- `columnCells` makes a ghost row of only the overlay's columns, drawn with the content. The shaders look for it where a hole's cells would be drawn as content.
- Scrolling forward needs none, since the new bottom row enters from below the region and only lands under the hint.
- Zig tests: `EdgeRows`, `repaintedInPlace`, `Overlays`, `RegionShifts`, `overlayFills`, `columnCells`, `ghostCells`.

**0010 and 0015: scrolls a program draws without scrolling.** pi's full-screen view rewrites every changed row in place, one synchronized update per streamed line or wheel step, and never scrolls. So the terminal had nothing to animate, and pi moved a row at a time.

- On the alternate screen, when the terminal recorded no scroll, the renderer hashes each row and compares it with the previous frame.
- When at least half of the rows that changed, and at least three, are the old ones moved by the same number of rows, the span they cover is animated as a region scroll.
- The span is widened by the rows that came in, and bounded by rows that stayed the same (a header, the prompt). It gets the same ghost rows and hit testing.
- A redraw that only changes rows in place (a progress display) finds no shift and does not move.

0015 (since 2026-09-30) handles OpenCode, which repaints its rows like pi but paints every cell. Its empty lines are drawn rows that look alike, and so are a table's rules. 0010 took such rows for rows that stayed, and split the transcript into pieces.

- A row now stayed only when it is drawn as before, and the shift would have put something else there, more than a cell or two different (`Shifted.stayed`, `RowCells`).
- A row brought in from beyond the screen cannot have stayed.
- The span is widened by the `lines` rows the scroll brought in, even past a row that seems to have stayed.
- The renderer keeps each cell's hash of the previous frame (`cellHashes`, `CellGrid`, text cells marked in the low bit).
- Rows are compared on their middle first (`still_edge_band`, 8 columns in from each side). They are compared on their whole width only when that finds nothing, and again without the still columns once those are known.
- Still columns are left out of the region (`movingColumns`). This keeps OpenCode's scrollbar (three cells in from the right) and its sidebar on a wide window still while the text moves.
- Still columns run from each side inwards, up to the first column seen moving, never more than half the width.
- Each column is judged by its edges (cells that differ from the one above) across the region and the changed rows next to it.
- A column moved when the shift explains its edges. It stayed when they are where they were, or a row or two off (a thumb moving on its own). In a row brought in, it stayed only when they are exactly where they were.
- A column with no edges either way stays out when the last region left it out.
- It also stays out when it is a bar within 8 columns of the side or of a still column (`isBar`: one background, no text, down all the rows but two, that its neighbours do not have). A scrollbar's thumb changes its glyph as it moves half a cell, so on a scroll's first step its edges match nothing.
- A region found within two rows of the last one takes the rows of both (`joinInferred`). The running animation moves to it, instead of a second one starting over the same rows.
- When frames come late, the content can move further than the inference looks, and no scroll is found.
- A redraw that changes most of the last inferred region with no scroll found ends the animations over it (`mostlyChanged`). The new content is drawn where it is, as with motion off.
- The inference runs in updateFrame under the state mutex. Drawing ticks the animations under the draw mutex, on the main thread too. So the inference changes no animation itself.
- The region of the animation to move goes with the scroll (`PendingScroll.from`), and the region to end goes in `pending_region_end`. `applyRegionScrolls` does both under the draw mutex.
- The thumb stays on OpenCode's own half-cell steps in every frame.
- Zig tests: `inferRows`, `inferScroll`, `joinInferred`, `mostlyChanged`.

**0011: a link under ⌘ in a program with the mouse captured.** Ghostty hands links to the program once it turns on mouse reporting (Claude Code's full-screen view, vim, htop). It offers only shift to take them back, which is the select gesture, not the link gesture.

- Super cannot be reported, since no mouse protocol has a bit for it. So the program loses nothing.
- `SurfaceMouse.linksOverrideCapture` says links refresh while super or an unkept shift is held, at the two places that refresh them: pointer moves and modifier changes.
- A press or release over a link is not reported, so the click that opens the link does not also reach the program as a plain click.
- Claude Code's docs say it detects Ghostty and opens a link on a plain click. So a reported press would have opened the link a second time.
- Away from a link, ⌘-click reaches the program as before.
- Zig test: `-Dtest-filter=linksOverrideCapture`. End to end: `printf '\033[?1000h\033[?1006h'` before a URL in a self-test.

**0016: frames only as the content moves** (since 2026-09-30). The ease slows below a pixel a frame for the second half of its way. 0005 drew a frame at every refresh until the content was under half a pixel from rest.

- A frame is now due once the content has moved a pixel since the last one, or when it comes to rest (`regionAnimStepSeconds`, `regionAnimDueIn`).
- A refresh with nothing due draws nothing.
- The display link stops once frames come further apart than a refresh (`animationWantsVsync`). The renderer thread's animation timer draws the rest.
- A scroll that joins one in flight starts its ease when it comes, not at the last drawn frame, which in the tail can be 50 ms old (`catchUpRegionAnims`).
- 0005's tick rebuilt the region uniforms after every drawn frame, which set `cells_rebuilt` after the draw had cleared it. So the display link never paused while a region animated. 0016 fixes this too. The probe's `presented` count finds such a fault.
- Effect: about 20% fewer instructions while Claude Code's recorded stream plays, with the same visible motion.
- The last pixel can show up to about 25 ms later, since a frame now waits for a whole pixel.
- Scrolls that come faster than an ease settles gain nothing, since every refresh still moves the content by more than a pixel.
- Zig test: `regionAnimStepSeconds`.

**0017: no timer under vsync** (since 2026-10-06). While an animation runs, the display link draws every refresh. The renderer thread also armed its animation timer every 8 ms, and under vsync each tick only armed the next.

- A draw wake is no longer armed while the link runs.
- `drawNowCallback` arms it once a draw stops the link, so a scroll's slow tail (0016) still gets its frames.
- Effect: interrupt wakeups fell from 996 to 204 a second while region scrolls stream, with the same frames presented.

**Checking it.** Run a fixture that scrolls a region the way Claude Code does (its bytes, captured from 2.1.284):

```sh
scripts/selftest.sh <name> --type "bash $PWD/scripts/fixtures/region-scroll.sh" --motion 5
```

- It logs, from the frames libghostty presents (`MotionProbe`, Debug only), how far the content moved in each.
- With full motion, each 3-row step (102 px) shows as a dozen frames of a few pixels each, a frame every 9 ms or so. With `--config 'motion = "off"'` it is one 102 px jump per step.
- `--motion-cells col,row,col,row` watches part of the pane.
- The summary's `frames` are the distinct pictures. `presented` counts every frame libghostty handed over, alike or not, because the swap chain draws each into the next of its surfaces. So a frame that moved the content less than a pixel shows only in `presented`.
- The fixture hides the cursor, as Claude Code does. A visible cursor moves with every step and keeps the cursor glide's loop drawing every frame (0014), which hides the effect of 0016 and costs about 90 M instructions a second more.

| Fixture arguments | What it does |
|---|---|
| `3 12 rest` | Spaces the steps 0.4 s apart, so each ease comes to rest |
| `-2 20 hint` | Scrolls back with a hint in a magenta box, redrawn after every step. `--motion-color ff00ff` counts the pixel rows showing it in each frame: one row's height means one hint |
| `-2 20 hint burst` | Sends steps in pairs 4 ms apart, which the renderer takes in one frame, as Claude Code does. A fault can pass the tidy fixture and fail this one, so try a change against both |
| `3 20 repaint` | Moves the region by rewriting every row, as pi does (0010). Every move is under a row, a frame every 9 ms or so |

- `CALM_SELFTEST_MOTION_FRAMES=<dir>` saves each of the first 240 frames as `frame-NNN.png`. It slows the sampling, so read timing from a run without it.
- Read frames, not only counts: a strip of consecutive frames, against the same replay with `--config 'motion = "off"'` as the reference, finds faults that counting does not.

Against the real Claude Code:

1. Run `claude --resume <a copied old session>` in a pty of the pane's size, with `--settings '{"disableAllHooks": true}' --strict-mcp-config`. No hook then reaches a running Calm, and no prompt is sent.
2. Use Calm's own terminal identity: `TERM=xterm-ghostty`, `TERM_PROGRAM=ghostty`, and `TERMINFO` from the app. Use a long real transcript, the kind the user scrolls.
3. Send SGR wheel events and record the output with timestamps.
4. Replay the recording into a self-test. The capture holds a conversation, so it stays out of the repository.

Against OpenCode (0015):

1. Run `opencode --standalone -s <id>` in a pty of the pane's size, with Calm's terminal identity.
2. Give it a scratch `HOME` holding a copy of `opencode.db` (sqlite `.backup`, read-only on the real one) and the two config files, with no credentials.
3. Answer its startup queries: DA1, XTVERSION, OSC 10/11, DECRQM.
4. Send SGR wheel events, record, and replay into a self-test with `CALM_SELFTEST_MOTION_FRAMES`.

- OpenCode's frames are synchronized updates of changed cells only (no DECSTBM, no SU/SD). Emulating the grid per frame (`pyte`) and running the inference in Python on it shows which rows and columns each frame animates, before any engine rebuild.
- Cost while streaming (2026-09-29): about 7% of a core with full motion, the same as the cursor glide's loop it rides on, and 3% with motion off.

## Configuration

Behavior: FEATURES.md → F14.

- One file: `~/.config/calm/config.toml` (`CALM_CONFIG_FILE` overrides it), read and written by the settings screen.
- `CalmSettings` reads the flat subset of TOML Calm needs: `key = value`, comments, and `[sections]` flattened to `section.key`. It reports malformed lines instead of failing.
- Each key sits under what it is about (renamed 2026-10-07 from flat names such as `session-cards` and `claude-code-hooks`). A key's section is everything before its last dot.

| Section | Keys |
|---|---|
| top level | `theme`, `motion`, `ui-size`: the whole window's look |
| `[window]` | `background`, `layout` |
| `[sidebar]` | `cards`, `cards-fit`, `footer`, `auto-grouping` |
| `[files]` | `editor`, `open-in` |
| `[agents]` | `notify`, `sound`, `send-with-cmd-return`, and ⌘N's `new-session`: for every agent |
| `[agents.<agent>]` (`claude-code`, `codex`, `opencode`, `pi`) | Claude Code's `hooks`. ⌘N's `skip-permissions`, `worktree`, `trust-project-files`, `flags` and `command` |
| `[updates]` | `check` |

**The footer key.**

- `footer` (the sidebar's start rows) is written by their hover handle, not by Settings.
- `SidebarView` gets it as a stored `showsFooter` from `makeSidebar`, like `style`.
- It keeps the handle's own choice in `footerChoice` until the saved value arrives, since a sidebar peek is not rebuilt when the setting is saved.
- Headless self-tests click the handle with `footer:hide` and `footer:show`.

**Writing.**

- Settings are written one line at a time (`CalmSettings.save`), so comments and unknown keys stay.
- A section whose last key goes back to its default goes too, unless a comment is left in it.
- A string is written as a TOML basic string, with `\"` and `\\` escaped, and read back unescaped. An agent's flags can hold quotes.
- Choosing a default removes the key, except the theme (Themes → Picker).

**Known keys.**

- `CalmSettings.keys` lists every key with what it takes, its default and what it does, for `calm config` (CLI.md).
- `calm config` checks a value against it (`CalmSettings.change`) before `save`.
- A key Calm starts reading must go in `CalmSettings.keys` too, or `calm config` will not know it.
- Tests hold the choices and defaults to the typed accessors' enums. They cannot see a key only the app reads: `files.editor`, `files.open-in`, `theme`, `agents.claude-code.hooks`.
- The agents' options are not in `CalmSettings.keys`, since only the adapters know them. `Agents.settingsKeys` adds them, and `calm config` reads that.

**Ghostty options** load in this order, each winning over the one before:

1. Calm's `defaults.ghostty`: keybindings, padding color, motion, the default theme.
2. The user's Ghostty config.
3. Calm's `choices.ghostty`: a picked theme, glass.
4. `~/.config/calm/terminal.ghostty`, for Calm-only overrides.

## Control protocol

Behavior: FEATURES.md → F13. Every command: CLI.md.

- The socket is at `~/Library/Application Support/Calm/calm.sock` (mode 600). `CALM_SOCKET` overrides it.
- One request per connection: a line of JSON with `v` and `cmd`. The answer is `{"ok":true,…}` or `{"ok":false,"error":…}`.
- The types are in `CalmControl` (`ControlProtocol.swift`).
- A request from a newer `calm` (a higher `v`) is refused, with a note to update Calm.
- Clients are served one at a time. A read or write that stalls gives up after 5 s (`SO_RCVTIMEO`, `SO_SNDTIMEO`, since 2026-10-12), so a client that connects and says nothing cannot hold up every later command and hook.
- Accepted connections set `SO_NOSIGPIPE`, so a caller that hangs up before the reply (a hook that timed out) cannot end Calm.

**One Calm per socket, and a socket that heals** (since 2026-09-30). A second copy used to unlink the running Calm's socket and bind its own. When it quit, it left a dead socket file, every hook was refused, and the running Calm's sessions stopped following their agents.

- A Calm that starts while another answers on the same socket quits at once. It does so in `main.swift`, before the engine, the saved state or any shell is touched (`SingleInstance`, a plain connect without a request).
- The Restart helper starts the new Calm only after the old one has exited. Self-tests and Debug runs set `CALM_SOCKET` to their own path. So neither meets this rule.
- A running Calm checks every 5 s that the path still leads to its listener (`listenAgainIfLost`).
- When the file is gone, or is what a dead Calm left, it listens again (trace: `control socket lost; listening again`).
- When a live Calm owns the path, it leaves it alone.

**Commands.**

| Command | What it does |
|---|---|
| `open` | A folder becomes a project with a new session. A file, or `file:line`, opens in the viewer or the editor |
| `list` | Sessions with id, title, project, folder, state, agent, and the agent's id for the conversation running or last run there |
| `status` | A state report, with the agent, its session id, its transcript, the shells still running when the hook knows them, a compaction starting or ending, and what the agent does, for the live line |
| `notify` | A notification for the session |
| `search` | Answered off the main thread, since the index has its own queue. Hits carry the conversation's id (`SearchHit.conversation`) for `calm show` |
| `info` | The answering Calm's process id, bundle path and version, and the named session's state, agent and last report: what `calm doctor` asks. A Calm older than `info` answers "Couldn't read the request.", which doctor reports as too old |
| `reload` | Reads config.toml and the Ghostty config again (`TerminalEngine.reloadConfig(soft: false)`), as Reload Configuration does. `calm config` sends it after a change, since config.toml is not watched |
| `fork` | Below |
| `screenshot` | The main window, drawn by `WindowSnapshot` (the capture the self-tests use), answered as base64 PNG in `ControlResponse.image`. The CLI checks the PNG header and writes the file, so the app never writes where the caller's shell might not be allowed to |

`calm hook <agent>` exists only in the CLI: the adapter (`HookReporting`) turns the payload into a `status` request.

**Starting Calm.**

- `open` and `list` start Calm when the socket is missing, and wait up to 5 s. `status`, `notify` and `hook` never do.
- `CalmLaunch` picks the Calm: the app the CLI sits in (`Calm.app/Contents/Resources/bin/calm`, through the link on `PATH`).
- It picks by bundle id only when the CLI is not in an app. It picks none when `CALM_SOCKET` names a socket other than the standard one.
- The reason (2026-09-30): `open -g -b com.jinhuang.calm` made a Debug build's CLI start the installed Calm. A self-test shell whose Calm had quit would have started one on the standard socket that never answered on the test's.

**Hook input.** `calm hook` reads its payload with a deadline and a size limit (`HookInput`: 1 s, 16 MB), besides the socket's 1 s.

- A hook holds its agent up, and a runner that left stdin open would hold it for good.
- A longer payload is cut and reports nothing.

**`calm search`.**

- It reads the index itself when Calm is not running, or when Calm has not answered after 15 s (a cold index takes more than 10 s). It says so.
- An error from Calm is shown and exits 1, not searched around (`SearchRoute`), so "update Calm" reaches the user.

**`calm doctor`** (since 2026-10-06). The CLI gathers facts, and `Doctor` (CalmControl, unit-tested) turns them into checks. So every verdict is tested without a running Calm. The facts:

- `info` from the socket (2 s).
- The answering process's start time, and the processes running its executable (`ProcessInspector.startDate`, `processes(running:)`: `proc_listallpids` + `proc_pidpath`).
- The app's Info.plist version, and its executable's modification time. `install.sh` builds right before `ditto`, which keeps the time, so it is the install time. The `.app` folder's own date does not move.
- The first `calm` on `PATH`. Paths go through `realpath`, since Foundation's resolving drops `/private` and `proc_pidpath` keeps it.
- Each agent's link as Settings → Agents sees it (`currentSetup`, `AgentSetupFiles.state`, Claude Code's plugin files in `ClaudeCodeAdapter.pluginDirectory`).
- In a Calm shell, whether `CLAUDE_CODE_PLUGIN_DIRS` holds that folder.

**`calm trace`** (since 2026-10-06). It runs `/usr/bin/log show --last <t>` (or `stream` for `--follow`) with `--style ndjson` and a predicate on:

- the trace's subsystem and category
- `processImagePath` of the app the CLI came with: every launch of it, so a restart and a second copy show, and a Debug build or self-test does not
- `eventMessage CONTAINS` the session's 8 hex digits

`TraceLog.Printer` keeps each record's time and `eventMessage`, with a heading when the day or the process changes, and skips the closing `{"count":…}`. It is tested on records from the real trace (fixture `trace.ndjson`).

**`calm fork`** (since 2026-10-06). The `fork` request names the session, the prompt (`message`), the folder (`path`) and `background`.

- `ControlServer.fork` takes the session's conversation (running or last run) and the adapter's `forkCommand(agentSessionID:transcriptPath:prompt:)`.
- Claude Code and Codex append the quoted prompt. The others give nil, so a prompt is refused rather than dropped.
- `MainWindowController.forkForCLI` opens it as F12's Fork does, in the source's project (`placementAndFolder`), selected.
- With `background`, the session is made without selecting it (`Workspace.newSession(selecting: false)`), which leaves the session in front unsettled.
- A background fork's pane is made at once at the main area's size. So the agent starts at its shown size, not at the placeholder that garbles a full-screen program.
- Sessions it made go into `forkedByCLI`, in memory. A `fork` naming one of them is refused.
- `--in`: Claude Code keeps transcripts by folder and knows a repository's worktrees. So it loads a conversation from a git worktree of its repository, and says "No conversation found" from an unrelated folder (2.1.291).

**`calm show`** (since 2026-10-06). `SearchIndex.conversation(id:)` finds one conversation by its agent's id, or by a unique start of it (6 characters or more).

- A transcript's row wins over the prompt history's. The newest of several files with one id wins.
- Its messages come in indexed order.
- The CLI adds the transcript's tail (`readTail`: Claude Code's recap and tasks). A database path `<db>#<id>` is read through the database.
- It adds the branch (`AgentAdapter.branch(of:)`: Claude Code's newest `gitBranch`, Codex's `session_meta.git`).
- It adds the start (the transcript file's creation, not for a database), and, from the running Calm's `list`, the session the conversation is open in.
- `ConversationReport` (CalmControl) lays it out and leaves out what is empty.

**The CLI binary.** The CLI is a small separate target (module `CalmCLI`), installed into the app bundle at `Contents/Resources/bin/calm` and linkable onto `PATH`.

- Beside it, `bin` holds a link to each CalmKit resource bundle (`CalmKit_CalmAgents.bundle → ../CalmKit_CalmAgents.bundle`).
- A command-line tool's `Bundle.module` looks beside the executable, not in `Resources`, and stops the process when the bundle is missing (found 2026-10-07, when `calm doctor` died).
- `AppBundleTests` holds the links in place.

## Testing

- **Unit:** CalmKit's packages (`swift test`), with fixtures from real transcripts. App-hosted tests in `CalmTests` for code that needs AppKit or the engine.
- **Integration:** control socket round trips, the indexer on fixture folders.

**Cost at rest** (`mise run perf`, `scripts/perf-check.py`, about 2 minutes, not part of `test`).

- Each scenario is a headless run of the Debug app, read through the kernel's counters for the process (`proc_pid_rusage`). It measures over 15 s after 10 s to settle, and is held to a budget.
- The budget counts instructions, not CPU time. On a busy Mac identical runs took 3–13% of a core, as the work landed on different cores at different clocks, while their instruction counts stayed within a few percent.

| Scenario | What runs | Budget: M instructions a second, wakeups a second | Measured |
|---|---|---|---|
| `idle` | an idle focused shell | 40, 60 | 10, 22 (2026-09-30) |
| `unseen` | three working stand-in agents (`scripts/fixtures/agent-standin.sh`, a scratch `CFFIXED_USER_HOME`), window out of sight (`calm.window_unseen`) | 40, 80 | 9, 20 |
| `seen` | the same three in view | 40, 80 | 10, 20 |
| `compacting` | the same, the one in front compacting | 40, 80 | 9.9, 17 (2026-10-07) |
| `fullscreen` | `scripts/fixtures/region-scroll.sh` streaming a line every 0.1 s into a full-screen region, in view | 400, 400 | 163, 265 (2026-10-07), almost all of it the drawing |
| `fullscreen-unseen` | the same, hidden in a working session: Find's keeper | 40, 80 | 22, 50, against 12 to 16 M with the keeper off |

- The budget fails the regressions it guards. `custom-shader-animation = true` made the idle run 120 M and 789 wakeups. Marks ticking behind a hidden window made the unseen run 423 M.
- Before the marks and the light were layers, the `seen` run cost 312 M and 142 wakeups (Agents → Agent marks).
- A keeper that read the screen after every frame, instead of every 0.2 s, would add about 360 M in view.
- After a change to rendering, animation or timers, run `mise run perf`.

**Self-tests** (Debug builds). `scripts/selftest.sh` launches the app and drives it through variables read in `Calm/App/SelfTest.swift`: typing, key events, `calm.<action>` hooks in `MainWindowController.performForTesting`, and motion probes. It saves a snapshot, the screen text and a log, and quits.

- `CALM_HEADLESS=1` keeps the window invisible, click-through and never key, so a run never takes the user's focus (`Headless`).
- A headless run holds off App Nap, but not the Mac's idle sleep.
- It quits by itself ten minutes past its snapshot delay (since 2026-09-30). `selftest.sh`'s watchdog stops only the instance it started, and an orphan once ran for three hours at 5% of a core.
- Checks read the log and the snapshot. There are no reference images.
- A snapshot draws Core Animation layers at their model values, not mid-animation. The working mark shows the frame it started on.
- `CALM_SELFTEST_SHIMMER_PHASE=0.5` holds the working line's light at one place, so it can be compared.
- `calm.layer_motion` logs whether the animated layers keep to the wall clock.

**Isolation.** Each self-test gets its own `CALM_STATE_FILE`, `CALM_SUPPORT_DIR`, `CALM_CONFIG_FILE`, `CALM_SOCKET`, `CALM_ZMX_DIR`, `CALM_INDEX_FILE` and `CALM_SEARCH_HOME`. It also gets `CALM_GHOSTTY_CONFIG=none`, `CALM_NO_PERSISTENCE=1` (unless `--persist`) and `CALM_NO_NOTIFICATIONS=1`. So it never touches the installed Calm's state, shells or index.

- Everything Calm copies or pastes goes through `NSPasteboard.calm`, a pasteboard of its own in a headless run (`calm-selftest`). So a test never reads or replaces the user's clipboard.
- Route any new copy through it. Never save and restore the user's clipboard instead: a hook that saved and put back only text lost an image the user had copied (2026-09-30).
- A real program run inside a test can still write the clipboard itself. Claude Code copies a selection through its own `pbcopy` and a native add-on.
- `UserDefaults` follow the bundle id (Window). The Debug build's is `com.jinhuang.calm.dev`, so a test never changes the installed Calm's defaults. Debug runs share them with each other.

**Running the tests.** Swift Testing throughout.

- `mise run test` runs the package's tests (`scripts/xcode.sh test-packages`), then the app's (`test-app`). The second runs even when the first fails.
- On CI they are separate steps. Lint, Build and both test steps each run whatever the others did, after a `Runner` step that prints the cores, memory, OS, Xcode and display scale.
- That rule dates from 2026-10-06: a run used to stop at its first red step, and a package test that failed only on a runner hid two red app tests for three runs.

**Tests that depend on the machine** (2026-10-06). A CI runner's display is 1×, a developer's Mac is 2×, and a runner has system events that a Mac at rest does not.

- `MotionLayersTests` compares the layer mark with SwiftUI's drawing pixel by pixel, tuned at 2×.
- At 1× the 26-pixel tile shrinks about 32×, and the two resamplers disagree about as much as a wrong frame or a one-pixel shift. So below 2× the test only guards what is grossly wrong (mean under 6).
- `DictationInputTests` asks for "no key press in flight" through `keyTextAccumulator` and the type of `NSApp.currentEvent`, not `currentEvent == nil`. The app's last event stays current outside any handler, and on a runner it is a system event.
- A new test that draws pixels or reads the current event must say what it assumes about the machine. Its failure message must print it.

**Trace** (since 2026-09-29). `Trace` writes a timeline of what decides a session's row to the unified log (category `trace`, notice level, so it is kept). Read it with:

```sh
/usr/bin/log show --last 5m --predicate 'subsystem == "com.jinhuang.calm" AND category == "trace"'
```

- Plain `log` is a zsh builtin, so use the full path.
- Each line is `+seconds since launch`, the event, and the session's first eight hex digits (the ids in `state.json` and the zmx names).
- The trace was added to find why a Restart was slow to show *working*.

| Event | Says |
|---|---|
| launch milestones | engine, state restored, control socket listening, probe scheduled, window open |
| `restore` | per session: the saved state and agent |
| `launch pass` | how many saved runs, how long, and whether it finished before the window or the rows showed as loading |
| `settle` | per session: what the pass found, and what the row showed before and after |
| `pane` | a pane attached |
| `probe` | an agent started or ended in the foreground |
| `agent named` | a hook, or the probe finding a transcript, told which agent and transcript |
| `report` | source, state, and what the row showed before and after |
| `ignored` | a report naming an agent other than the one in the foreground, left out. Always written |
| `transcript` | which fields the tail held, and any state change it made |
| `control … waited` | a request waited 100 ms or more for the main thread |

- Every report and hook is written for the first minute after launch. Later, only those that changed something.
- The trace holds only states, sources, counts and agent names, never text a user or agent wrote.
- `SessionProbe`'s own polls are not traced, so a slow transcript read shows as the gap before its `transcript` line.

## Licensing and references

- Calm is licensed under **Apache-2.0** (`LICENSE`, `NOTICE`).
- Ghostty (MIT) can be studied, and small parts adapted, with attribution in the file header and in `NOTICE`.
- Other projects are for ideas only. Calm copies no code from them, with one exception (decided 2026-09-29).
- The exception: engine patches 0005 and 0006 in `scripts/ghostty-patches`, taken unchanged from `thdxg/ghostty` (a Ghostty fork, MIT) and credited in `NOTICE`. Refresh them from the fork, and do not edit them here.
- Calm's own patches beside them (0007 and up) are written here, each as a separate file (Tech stack → Engine patches).
- Agent marks are the agents' own logos, shown only to identify which agent a session runs. Their sources and owners are listed in `NOTICE`. The motions are Calm's own code, written after watching each agent's.

**Notices that ship** (decided 2026-10-08, before the first download). Calm embeds libghostty, so Ghostty's license notice ships with the app, and so do the notices of what the engine builds in:

| Component | Note |
|---|---|
| C and C++ libraries: FreeType, zlib, libpng, Oniguruma, glslang, SPIRV-Cross, simdutf, Highway, Wuffs, stb_image, Dear ImGui | Their own notices |
| GNU libintl | LGPL-2.1, linked statically. Calm's source and build steps let anyone relink it, and `NOTICE` names its source |
| z2d | MPL-2.0, unmodified |
| Ghostty's Zig packages, Zig's standard library | Their own notices |
| Embedded fonts: JetBrains Mono (OFL), Symbols Nerd Font | Their own notices |
| `Resources/ghostty`: the iTerm2-Color-Schemes themes and shell integration scripts | bash's and zsh's scripts are GPL-3.0, each its own source |

- The list comes from the library's object files (`ar -t` on `libghostty-internal.a`) and the fonts found in the built app.
- harfbuzz, fontconfig, libxml2 and Sentry are Ghostty dependencies that the macOS engine does not link.
- `scripts/licenses.sh` copies each text from the engine's source at the pinned versions. Run it again when the pin moves.

## Updates

Behavior: FEATURES.md → F17.

**Where it lives.** UI-free logic is in CalmModel (`ReleaseUpdates.swift`):

| Type | Does |
|---|---|
| `ReleaseVersion` | `MAJOR.MINOR.PATCH`, with or without the tag's `v` |
| `ReleaseFeed.newest(in:)` | GitHub's list → the highest version that is not a draft |
| `UpdateOffer` | Newer than the running one, and not skipped |
| `UpdateSchedule` | Once a day, an hour after a failure |

- `UpdateChecker` (App) does the request and keeps the answer in `UserDefaults` (`update.*`: last check, last attempt, ETag, newest version and page, skipped version).
- `UpdateChecker` is `@Observable`, so the sidebar's `UpdateNotice` redraws when a check finds something.
- `UpdateAlert` (Calm → Check for Updates…) and the Settings row use the same checker.

**No timer** (decided 2026-10-09). A repeating timer would add wakeups to a Calm at rest, which the perf budget counts.

- A check runs 8 s after launch and on `NSApplication.didBecomeActiveNotification`, each time only when `UpdateSchedule` says it is due.
- Calm becomes active as it launches, so activations before those 8 s are ignored (`settle`, `cameForward`).
- Calm lives in the Dock, so it comes forward at least daily.

**The request.** One GET of `api.github.com/repos/jinhuang712/calm/releases`, with the version as User-Agent and the last ETag.

- Calm reads the list, not `/releases/latest` (decided 2026-10-09). `latest` leaves out pre-releases, and answers 404 while every release is one.
- The list is read for its tags. The pre-release flag is ignored. A tag that is not `MAJOR.MINOR.PATCH` is skipped, so a `-beta` tag or `edge` is never offered.
- The test fixture is GitHub's real answer (`Fixtures/releases/calm-releases.json`).
- The ETag saves bytes, not requests (measured 2026-10-09). GitHub answers `If-None-Match` with 304, but an unauthenticated 304 still counts against the 60 an hour per address.
- One check a day is far under that limit, so Calm sends no token.
- A failure is quiet.
- `CALM_UPDATE_FEED` points a run at a file or a local server. The Debug build and self-tests never check on their own.

**Update and Restart runs get.sh** (decided 2026-10-12).

- `UpdateInstaller` (App) runs `/bin/bash` with `CalmUpdates.installArguments`: `curl … get.sh | bash -s -- --version X --dir <the folder Calm runs from>`.
- The version is parsed (digits only), and the folder is a script argument, never shell text.
- get.sh already does what a self-replacing app needs: the checksum, the swap with the old copy moved aside, the quarantine mark, the moved copy's removal. A second copy of that in Swift would drift from it.
- On exit 0, it calls `Restart.request()`, which deletes the moved copy and opens the app at its own path.
- On failure, it shows the last lines of the output.
- An installer that runs over 3 minutes is ended, with "The download took too long" (since 2026-10-12). A download that hangs would leave "installing" up forever.
- Output goes to a temporary file, not a pipe. Nobody reads a pipe until the end, and curl's progress could fill it.
- Sparkle (mature, an EdDSA-signed appcast) waits for a Developer ID. It needs a key in CI, an appcast and an embedded framework, and gains little while the app is ad-hoc signed and every install asks for folder access again.
- The trust is the one the README's one-liner already asks for: get.sh from `main`, and the disk image checked against GitHub's digest.
- The item is hidden for Homebrew installs (get.sh refuses them) and in the Debug build.
- `UpdateInstallerTests` uses a fake run and restart, since a real install would replace the installed Calm.

**Copy Update Command.** Calm does not install on its own. The notice's menu points to the release page and copies the command for how Calm was installed.

- `brew upgrade --cask calm` when Homebrew's Caskroom has a `calm` record, under `/opt/homebrew` or `/usr/local`, the places get.sh looks.
- Else `curl -fsSL …/get.sh | bash`, which swaps the app in, leaves a running Calm working, and takes macOS's download mark off.
- get.sh refuses to replace a Calm that Homebrew installed, so the one-liner must not be offered there.

**Reference.** opencode desktop (Electron, `electron-updater`) checks at launch and every 10 minutes. It shows an "Update 1.2.3" pill in its title bar and a toast, and has Settings rows "Check for updates on startup" and "Check now" plus a menu item. Calm took the menu item, the quiet mark in the chrome and the one setting. It checks daily, has no toast, and installs only when the user chooses.

## Distribution

**Building from source.** `install.sh` builds a Release Calm into `/Applications` and links `calm` into `~/.local/bin`.

- It puts the app together afresh each time (about 4 s, compiling stays incremental).
- It refuses to install an app whose package resource bundles differ from the ones just built (since 2026-10-07, after an incremental build kept a stale copy of CalmAgents' bundle and installed a Calm without the commit's new files).
- It swaps the app in with two renames, so a failed copy never leaves no Calm.
- It does not quit a running Calm. macOS keeps the running binary's pages, and the new app starts at the next launch or Restart Calm.
- The build it was copied from is unregistered from LaunchServices and deleted, and the installed app is registered.
- macOS starts any registered copy of the bundle ID when Calm opens by ID (2026-10-07: a restart came back as a day-old build in an old worktree's `build/DerivedData-Release`, which Restart Calm then kept reopening).
- Worktrees that ran `install.sh` before this rule kept such a build. Delete them, or their `build/`.

**The moved-aside copy.** The old app is moved aside (`.Calm.app.previous-<time>`), not deleted, while a Calm runs from it. `lsof` names each running Calm's program file where it now is.

- Deleting the file a running Calm came from stops macOS letting it show the folder picker (2026-10-07). New Project then did nothing: `SecCodeCopyGuestWithAttributes failed … error 100002` (100000 + ENOENT).
- A program whose file is only moved stays `dynamically valid` and `valid on disk`.
- The moved copy must go the moment its Calm quits (2026-10-12). Otherwise opening `/Applications/Calm.app` can start the moved copy again: it happened twice in a row.
- Finder re-registers the running app at its moved path within 0.1 s of the move, and LaunchServices then preferred that record. The Dock's recent apps and the privacy list in System Settings followed it too.
- Why the new copy loses is not known. A stand-in app put through the same steps always came back new.
- Calm 0.1.2 and later remove the copy themselves. The helper that waits for the quit (`Restart.swift`) runs after any quit, not only a restart, since the Dock and Spotlight lead to the moved copy too. It unregisters and deletes the copy, then opens the app for a restart.
- The helper knows the copy by where its program file is now (`proc_pidpath`), which follows a move, while `Bundle.main` keeps the path it started from.
- It knows the copy only by the installers' name, in the same folder. So a copy someone moved on purpose is left alone.
- For an older Calm, and as a backup when a newer one crashes or is killed, `install.sh` and `get.sh` leave a waiter (`remove_once_quit`).
- The waiter is zsh sleeping in its own `zselect`, starting no process.
- It looks every 20 ms for a Calm before 0.1.2, so the program file is gone before that Calm's restart reopens it (that restart looks every 0.1 s). It looks every second for a newer Calm. `scripts/moved-copy-check.sh` measures it.
- `get.yml` checks that the moved copy goes once the Calm it installed over is killed.

**Installing under a running Calm** (seen 2026-10-01, cause not proven). Until it restarts, a Calm whose app was replaced can lose its shells' access to Documents, Desktop and Downloads ("Operation not permitted").

- sandboxd logged `tcc_server_message_request_authorization(kTCCServiceSystemPolicyDocumentsFolder) failed: … Failed to create Attribution Chain from message`.
- Restarting Calm cleared it, even for a shell the old Calm had started.
- Being out of date is not the whole story: tccd had allowed the same folder to the same out-of-date Calm earlier.
- `Failed to match existing code requirement` and `missing 'auth_value' in reply message` for `kTCCServiceSystemPolicyAllFiles` also fill the log at other times. They look like the routine answer when there is no Full Disk Access entry, not the failure.
- Keeping the old app aside fixed the folder picker. Whether it also keeps the shells' folder access is not proven, so the advice to restart stays.
- What we do: `install.sh` says so when it finishes, and whoever installs tells the user to restart Calm soon.
- A real fix waits for a stable signature (Signing, below).

**CI.** `.github/workflows/ci.yml` (a macOS 26 runner) builds GhosttyKit, then lints, builds and tests every push to `main` and every pull request. Each step reports even when another failed (Testing).

- The engine cache is keyed by the pin, the patches and the fetch scripts, and holds the 39 downloaded packages too.
- It is restored first, and saved straight after the engine builds. So a later red step does not cost the next run the 9-minute build.
- Of those 39 packages, 32 come from Ghostty's own CDN and 5 from GitHub. `translate_c` comes from Codeberg, and `fontconfig` from freedesktop's GitLab.
- Codeberg answered 503 for at least 20 minutes on 2026-09-30, which failed two CI runs and would fail a new user's first build the same way.
- So `scripts/ghostty-deps.py` first uses a copy kept in `scripts/ghostty-mirror/` (`translate_c`, 155 KB, MIT).
- Zig checks every package against its content hash. So a copy cannot change what is built, and a corrupt copy fails the build.
- A package the script cannot download is reported and skipped, not fatal: `zig build` fetches again only what it needs.
- fontconfig is for Linux, and is not mirrored, because its release archive exists only on that host.

**Releases** are tags (`vX.Y.Z`) on `main`, with their notes in CHANGELOG.md.

- The version is written in two places: `project.yml` (`CFBundleShortVersionString`, which Diagnostics and `install.sh` read, and the generated `Calm/Info.plist`) and `CLI/main.swift` (`calm --version`).
- `VersionTests` fails when the two, or the checked-in Info.plist, disagree.
- `CFBundleVersion` stays 1 until something (Sparkle) needs it to climb.

To cut a release:

1. Bump the version in both places, and run `xcodegen generate`.
2. Give the version a section in CHANGELOG.md headed `## X.Y.Z — <date>`. Put each paragraph and item on one line, because a release's notes break lines wherever the text does.
3. Land it.
4. Once main's CI is green, push the tag on that commit: `git tag vX.Y.Z <sha>`, `git push origin vX.Y.Z`.

`.github/workflows/release.yml` does the rest:

- It fails in seconds when the tag does not name the version both files hold, or is not on main.
- It builds as the README tells a new user to, with no GhosttyKit cache: the engine from source and its 39 downloads from their hosts. So a release also proves a fresh clone builds.
- It runs the tests.
- It builds and installs the Release app into a scratch folder, and checks its version and `calm --version`.
- It puts the installed app on a disk image (`Calm-X.Y.Z.dmg`, beside a link to `/Applications`). `scripts/disk-image.sh` makes and checks it, and edge builds use it too.
- It checks the disk image as a download: quarantined as a browser would leave it, copied off, cleared with the README's `xattr` line, `codesign --verify --deep --strict`, its version, and `calm list` starting it and getting an answer.
- Then it publishes a GitHub release with the version's CHANGELOG section as its notes (relative links pointed at the tag's files), marked a pre-release before 1.0, with the disk image attached.
- Run by hand (workflow_dispatch), it is a dry run: everything but the publishing, with the notes in the run's summary and the disk image kept as the run's artifact for a week.
- Last, it starts `homebrew.yml` and `get.yml`, deletes the `edge` release, and starts `edge.yml` again (Edge builds, below).
- Releases ship a download, not only source (decided 2026-10-08): building needs Xcode 26 and an 8-minute engine build, which stops most people who would try a preview. A source-only 0.1.0 was published and withdrawn the same day.

**Homebrew.** `homebrew.yml` points the cask in Calm's own tap (`jinhuang712/homebrew-tap`, `brew install --cask jinhuang712/tap/calm`) at the release: the disk image's version and sha256, as GitHub serves the file.

- It pushes with a deploy key (`HOMEBREW_TAP_KEY`) that can write to the tap and nothing else.
- Run by hand, it does the same again for a version.
- The tap's own workflow installs the cask on a clean runner, checks it as `release.yml` checks the disk image, and uninstalls it.
- The cask does not take the download mark off. Homebrew 7 dropped `--no-quarantine`, warns that the `postflight` block that could run `xattr` is deprecated, and disables casks that fail Gatekeeper in its own list (2026-09-01).
- So the cask's caveats and the README give the `xattr` line, and the official list waits for Developer ID.
- A tap that is not Homebrew's must be trusted (Homebrew 6). Installing by the full name trusts that one cask.

**get.sh**, at the repository's root, is the one-line install (`curl -fsSL …/main/get.sh | bash`).

- It asks GitHub's API for the newest release: only `vMAJOR.MINOR.PATCH` tags, pre-releases included. `--version` picks one.
- It checks the disk image against the asset's sha256.
- It copies the app in as `install.sh` does: beside the old one, swapped with two renames, a running Calm's app kept aside.
- It runs `/usr/bin/xattr -dr com.apple.quarantine` on it, by path. Homebrew's python `xattr`, which can come first on `PATH`, has no `-r`. The README's line says `/usr/bin/xattr` too.
- It registers the app with LaunchServices and links `calm`.
- It refuses a Calm that Homebrew installed, which `brew upgrade` must move.
- It runs only from `main()` at its end, so a download cut short runs nothing.
- It needs `curl`, `jq`, `hdiutil`, `ditto` and bash 3.2.
- It refuses a Mac older than macOS 14.5.
- `get.yml` pipes `get.sh` from GitHub into a clean runner, as the README does, and checks the app. Then it installs over the Calm it started (the old app must stay aside, and get.sh must say to restart), and installs a version into another folder.
- A change to `get.sh` runs `get.yml` on the checkout's copy.

**Edge builds** (decided 2026-10-11): the newest `main` for a Mac with no Xcode. Building Calm needs Xcode 26 and the engine, and a release waits for a tag.

- `.github/workflows/edge.yml` runs when CI (`ci.yml`) ends green on a push to `main` (`workflow_run`).
- It builds the commit CI passed, the way `install.sh` does. The engine comes from CI's cache under the same key as `ci.yml`, and a miss builds it. The tests do not run again.
- It puts the app on a disk image, runs the same `scripts/disk-image.sh check` as a release, and publishes one pre-release tagged `edge` that holds `Calm-edge.dmg`.
- The order: the disk image goes up first, then the notes (with a `commit: <sha>` line that `get.sh` reads), then the tag moves to the commit by force. So a reader never finds a tag with no disk image.
- The first run creates the release.
- Builds run one at a time in the order of the pushes (`concurrency` without cancelling). A build that waits is replaced by the newest. One that has begun is never cut short in the middle of publishing.
- Last, the run installs what it published with `get.sh --edge` (this checkout's copy) into a scratch folder, and checks the app. `get.sh` compares the download with GitHub's checksum, which proves the upload is the build.
- Run by hand on a branch, it is a dry run, and keeps the disk image for a week. It publishes only from `main`.
- `get.sh --edge` installs the edge build as it installs a release, and says `edge build <short sha>`.
- An edge build's version is the last release's, with the commit it was built from: `0.1.0-dc970ac` (decided 2026-10-11). So a Mac running one can say which build it is, with one rolling release, not a release per build.
- The run writes that version into `project.yml` and `CLI/main.swift` on its own copy, before the build. So the app is signed once, as built, `calm --version` agrees, and a mismatch between the two files fails the run.
- `VersionTests` ran on the commit as it is. `project.yml` keeps the last release's version between releases, because a release bumps it.
- The update notice reads the running version through `ReleaseVersion(runningBuild:)`. It accepts a suffix of 7 to 40 lowercase hex digits and counts the build as the version it follows. So an edge build is offered the next release, not the one it is past.
- When a release is published, `release.yml` deletes the `edge` release and its tag, and starts `edge.yml` on `main` again. So no build of an older version stays, and the next one follows the new release.
- The tag moves with each build. A clone that already fetched it gets a "would clobber existing tag" rejection (exit 1) from `git fetch --tags`. A plain `git fetch` is fine.
- `git fetch --tags --force` or `git tag -d edge` clears it. A tag that never moves would make the release's source links point at a stale commit.
- Everything that means "the newest release" must skip `edge`, and does. The update notice reads only `vMAJOR.MINOR.PATCH` tags. `get.sh`'s default selects only such tags. `get.yml` checks that the default install names the release, not `edge`. `homebrew.yml` works from a version it is given.
- The pre-release is on the public Releases page, and the app is ad-hoc signed as a release is. So the same `xattr` line and folder prompts apply.

**Signing: ad hoc** (decided 2026-09-29). macOS keeps a privacy grant (Desktop, Documents, Downloads, Full Disk Access and others) against the app's designated requirement. An ad-hoc signature's requirement is `cdhash H"…"`, a hash of that one build. So each rebuild or `./install.sh` is a new app, and macOS asks again.

- A self-signed certificate gives a requirement that survives rebuilds (`identifier "com.jinhuang.calm" and certificate leaf = H"…"`). It was tried and dropped.
- `codesign` refuses an untrusted identity, so trusting it takes a system password dialog.
- Then every `codesign` run asks for the login keychain password, and a build signs many binaries. A run nobody answers fails with `errSecInternalComponent`. Avoiding that means a script that types the login password to set the key's partition list.
- An app or its tooling that asks for a password over and over looks like malware, so Calm asks for none. The certificate, its script and the `Config/Signing.xcconfig` hook were removed.
- An xcconfig include also cannot name a path under `$(HOME)`, so a per-checkout file would need copying into every worktree.
- What keeps prompts few instead: guarded folders are read only when opened (Files and viewer), and the first launch asks once (Attention → Permissions at first launch).
- A user takes the download mark off with the README's `xattr` line before macOS opens the app, and answers the folder prompts again after each update.

**Later:** Developer ID signing, notarization, Sparkle updates (which install, unlike the notice), and a cask in Homebrew's own list.

- A Developer ID identity has a requirement that stays the same across updates, so a user's grants survive them.
- It asks the user for nothing beyond macOS's own folder prompts.
- It is the real answer to repeated prompts for users.
