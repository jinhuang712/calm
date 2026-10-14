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
| Minimum OS | macOS 14.5 or later, Apple silicon only (`ARCHS: arm64`). Lowered to macOS 14.5 on 2026-10-12 (was 26) |

- Calls newer than macOS 14.5 sit behind `#available`. The macOS 14 fallbacks are `Window/ScrollCompat.swift` and `Window/CaretField.swift`.

**GhosttyKit source.** Calm builds GhosttyKit from upstream Ghostty at the commit pinned in `scripts/ghostty.env`, with the patches in `scripts/ghostty-patches` applied.

- `scripts/ghosttykit.sh` checks out the commit, applies the patches in name order, builds the xcframework and Ghostty's resources, and caches them per commit and patch set in `~/Library/Caches/calm/ghostty/`.
- A patch that does not apply stops the build. Calm uses no prebuilt binaries and no fork as the source.
- Zig is pinned in `mise.toml`. `scripts/ghostty-deps.py` prefetches Ghostty's Zig packages with curl, because Zig's HTTP client fails behind some local proxies (Distribution → CI has its mirror).
- Calm pins a Ghostty `main` commit, not v1.3.1, because v1.3.1 needs Zig 0.15.2, which cannot link against the macOS 26.5 SDK. Move to the next Ghostty release once it supports Zig 0.16.
- Building needs Xcode's Metal Toolchain for Ghostty's shaders.

**Engine patches.** Decided 2026-09-29: smooth scrolling is taken unchanged from `thdxg/ghostty` (a Ghostty fork, MIT), because upstream has only its first piece and the fork's patch carries fixes found by measuring rendered frames.

- `GHOSTTY_COMMIT` is the upstream parent of the fork commit the patches come from (`GHOSTTY_PATCHES_FROM`), so the patches always apply.
- `scripts/ghostty-patches/README.md` says what each patch does in detail and how to move to a newer Ghostty.
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

**What the patches cost.** 17 patches, 7,979 lines.

| Area | Patches | Lines |
|---|---|---|
| Smooth scrolling and its fixes | 0005, 0007, 0008, 0010, 0012, 0015, 0016, 0017 | 7,024 (about 88%) |
| Find | 0018–0021 | 301 |
| Cursor shader | 0006, 0014 | 234 |
| Padding | 0009 | 225 |
| Link over mouse capture | 0011 | 98 |
| Surface size | 0013 | 97 |

- Every Ghostty upgrade re-applies all of them. Most of the smooth-scrolling stack fixes side effects of 0005.
- Exit plan: drop each smooth-scrolling patch once upstream ships smooth scrolling. Upstream has only RenderState overscan (ghostty-org/ghostty#14400).
- Offer the Find patches, 0011 and 0013 upstream.
- Kept on purpose (decided 2026-10-13): smooth scrolling serves "nothing jumps" (PHILOSOPHY.md → Design guidelines).

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

- A `Project` is a sidebar group with a kind: `.project` (the user made it), `.directory` (grouping made it) or `.scratch`.
- A `Session` is one shell. Its id is exported to the shell as `CALM_SESSION_ID`.
- While an agent runs in the foreground, the session holds an `AgentRun`: the agent, its process, its own session id and transcript, the options a resume keeps, and the latest `TranscriptTail`.
- When the agent exits, its `AgentConversation` stays as `lastConversation`, options included, so it can resume as it was started.
- `Workspace` holds `projects`, `sessions` and `layouts`. A `PaneLayout` is one tab: a `SplitTree<Session.ID>` plus the focused session.
- Every session is one pane, so a split creates a session. Calm has one main window, and libghostty's "new window" requests become new sessions.
- `Workspace.join`, `takeOut` and `unsplit` change which sessions share a layout. None of them touches a session or its shell.

## Auto-grouping

Behavior: FEATURES.md → F2.

**Where the folder comes from.** The shell reports its folder through OSC 7. For a shell that never does, `SessionProbe` reads it with `proc_pidinfo`.

- The shell's pid comes from `zmx list` for persistent sessions, else from `ghostty_surface_foreground_pid`.
- `zmx list` runs off the main thread with a time limit (since 2026-10-12), so a stuck zmx cannot freeze the window.

**Refiling.** A session that is not pinned goes to the most specific project the user made that contains its folder. Else it goes to the directory group keyed by its git root, or by the folder outside a repository.

- A directory group matches its key exactly and never contains other folders, because containment let a home-folder group swallow every session under `~`.
- Sessions started in a project or a scratch folder are pinned (`Placement`).
- At launch, `refileAll` files every unpinned session again, so a workspace saved under older rules finds its groups.

**Scratch folders.** They live under `~/.local/share/calm/scratch/`, named by time.

- Not in a temporary folder, because macOS clears it. Not in Application Support, because its space trips tools that do not quote paths.
- The path is fixed, not read from `$XDG_DATA_HOME`, which an app opened from the Dock does not see.
- The root is excluded from Time Machine. The exclusion is set on the root only, because it travels with a moved item, and a folder kept as a project must be backed up.
- Claude Code trusts the root (Agents → Trusted scratch folders).

**First screen.** No session opens at launch. The first launch shows the welcome page (Search → Welcome page). A later launch restores what was open.

**Project marks.** `Identicon` makes a project's mark from its name.

- The hash is FNV-1a, not Swift's `Hasher`, which is seeded per process: a mark must stay the same across launches.
- The hues are fixed steps, because hues taken straight from the hash bunched up.

**Folded groups.** `GroupSummary` turns a group's states into what its folded line draws. `GroupSummaryView` draws it with the cards' own `StateMark`.

**Project order** (since 2026-10-10). The sidebar's order is `Workspace.projects`' own, ranked by kind. `Workspace.moveProject(_:to:)` moves a user project.

- `state.json` keeps the order with no new key.
- Folder groups do not drag: they come and go with their sessions, so an order given to one would be lost.
- The drag is drawn without changing the order until release. `ProjectReorder` holds the geometry and `ProjectDragModel` (`SidebarView+Reorder`) the state.
- `ReorderableSection` is a modifier per section that reads the model, so a drag redraws the sections and not the sidebar's body.

## Agents

Behavior: FEATURES.md → F4, F5.

**Adapters (CalmAgents).** `AgentAdapter` says what an agent is: the process names it runs under, its config folder (present means installed), how it connects (`AgentSetup`), its mark, its resume and fork commands, and the environment and theme file it wants.

- An adapter can also adopt `HookReporting`, `TranscriptReading` and `TranscriptIndexing`. `Agents.adapters` lists them.

**Detection.** `SessionProbe` looks at every session on a tick.

- A job runs when the terminal's foreground process group differs from the shell's. Only when that job changes does Calm read its arguments (`KERN_PROCARGS2`) and ask the adapters.
- Match argv, not the kernel's process name: Claude Code's native binary is named after its version.

**Launch** (since 2026-09-29). The sidebar comes back as it was left. Before, a Restart showed agents idle until their next hook.

- `SessionProbe.settleSavedRuns` runs before the control server and the window. It asks `LaunchPass`, off the main thread, what each saved session runs now.
- It waits up to `LaunchPass.budget`. A pass that misses it shows the rows as loading (UIUX.md → Session states → Restoring), and one past `LaunchPass.deadline` ends every saved run.
- `Workspace.settleSavedRun` decides per session. The run stays only when the same agent process still holds the foreground.
- An agent's own status file (`LiveStatusReading`, Claude Code's `~/.claude/sessions/<pid>.json`) corrects the state when it is newer than the last report. Other agents keep a saved *working* only after a Restart, and correct themselves from their transcripts.
- Quitting while rows load loses nothing: the saved state changes only when the answer applies.

**A shell that went with its agent** (since 2026-10-07, so that a reboot does not leave every agent to restart by hand).

- A run whose shell is gone, with a known conversation, gets `Session.resumesWhenOpened`. The session's first pane types the resume command.
- A failed or late `zmx list` marks nothing, because a resume typed into a running Claude Code would land in its prompt.

**Supported agents, and removing one.** Calm supports Claude Code, Codex, OpenCode and pi. Removed omp on 2026-09-29, because it had little use and was not installed to check against.

- Removing an agent must not cost anyone their sessions. `Session.init(from:)` decodes `agent` and `lastConversation` leniently, because `WorkspaceStore` starts over when anything fails to decode.
- Follow the same rule for the next removal.

**Research (M3.2, 2026-09-27).** Checked against docs, source and local installs. None of these interfaces is a stable public contract, so every use degrades quietly.

| Agent | Detection | Transcripts | Status source |
|---|---|---|---|
| Claude Code | argv[0] `claude`, skipping its helper processes | `~/.claude/projects/<start folder>/<session>.jsonl`, keyed by the folder where the session started, so use the hook's `transcript_path` | Hooks, loaded through a plugin in `CLAUDE_CODE_PLUGIN_DIRS` that writes no settings. An Esc interrupt fires no hook |
| Codex | native `codex`, or the npm package's node script | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, with turn markers. `session_meta.originator` says who started it | Hooks need the user's approval in `/hooks` and run in a shared daemon (Codex hooks, below). Codex's own notifications instead |
| OpenCode | native `opencode`, or the npm wrapper | SQLite `opencode.db` (`session_v2`, `session_message`) | A TUI plugin (OpenCode plugin, below) |
| pi | `pi`, from `process.title` or the package path | `~/.pi/agent/sessions/--<folder>--/*.jsonl` | An extension in `~/.pi/agent/extensions/`, awaited in order, so Calm's returns at once |

**Claude Code hooks.** Calm ships the hooks as a plugin that Claude Code loads only in Calm's shells.

- At each launch Calm writes the plugin to `~/Library/Application Support/Calm/agents/claude-code`, and adds that folder to `CLAUDE_CODE_PLUGIN_DIRS` in its shells. Calm writes nothing to `~/.claude`.
- A self-test's Calm writes the plugin to its own support folder (since 2026-10-07: before, every self-test rewrote the real plugin).
- Hooks run synchronously, so reports keep their order. `ClaudeCodeAdapter.hookReport` maps each payload.
- A `Stop` with a `subagent` in flight stays *working*, because the subagent wakes Claude when it ends.
- Decided 2026-09-29: every other background task counts as a shell, and the `Stop` is *done* with the count, because a dev server or watcher never ends.
- The count (`Session.shellsStillRunning`) is saved (since 2026-10-13), so a Calm restart keeps "1 shell running" and the moving mark. It is one Stop's snapshot: a shell that ended while Calm was down shows until Claude's next report, which its wake-up turn sends.

**Esc and the status file.** An Esc interrupt fires no hook, but Claude Code's status file (`~/.claude/sessions/<pid>.json`) turns `idle`.

- `AgentStatusWatcher` keeps one file event source per Claude Code session, attached when the probe sees the agent start or end, never on a timer.
- `Session.turnEnded(accordingTo:)` ends a *working* or *needs you* session whose agent says `idle`. A session at rest costs nothing for this.

**Compaction** (since 2026-10-06, because a card showed the old step through a compaction that takes a minute or two).

- `PreCompact` starts it and `PostCompact` ends it. A `/compact` ends as *done*, and an automatic one stays *working*.
- The sizes come from the transcript (`ClaudeCodeTranscript`), and a cancelled compaction is read from it too.
- `Session.compactionBar(now:)` says what the card draws. The compaction is not saved, so a restart cannot bring back one that ended while Calm was away.
- A new turn drops a compaction that ended before it (since 2026-10-13, because a `/compact`'s bar stayed on the next turn's card and came back when that turn ended). The card reads a bar end that is already past at once, because its clock may not have moved since the compaction ended.

**Live line** (since 2026-10-09). A working card says what the agent does, from hooks Calm already hears: no new hook, process or timer.

- `ClaudeCodeAdapter.activity` turns a tool call into words. `LiveLine` is the line over time.
- `PostToolUseFailure` is subscribed, because `PostToolUse` fires only for a call that worked, and a failed call left its step running.
- Constraint: the line is not in the workspace. A workspace write re-renders the whole sidebar (State machine, below), so per-tool-call state lives in a `LiveLineBox` per session. `SessionManagerReportTests` checks that a tool call leaves the workspace alone.
- A hook asks `SessionProbe.readSoon` to read the transcript sooner, not more often, because a changed tail writes the workspace.
- Open question: whether a subagent's tool calls fire the parent's hooks.

**Teaching agents about `calm`** (since 2026-10-13). An agent does not know that `calm fork`, `calm show`, `calm search` or `calm config` exist (CLI.md has the commands). So all four agents get one Agent Skills file, `CalmSkill.text`, and each adapter delivers it in its own way.

| Agent | How the skill arrives | Where the file is | Seen outside Calm |
|---|---|---|---|
| Claude Code | in Calm's plugin, as `calm:calm` | `<support>/agents/claude-code/skills/calm/` | no |
| pi | Calm's extension returns its folder from `resources_discover` | `<support>/agents/skills/calm/`, written at each launch | no |
| OpenCode | Connect writes it beside the TUI plugin | `~/.config/opencode/skills/calm/` | yes |
| Codex | Connect writes it, Codex's first Connect | `~/.agents/skills/calm/` | yes |

- **Why files for OpenCode and Codex** (checked 2026-10-13): neither reads a skill path from a variable. OpenCode's `OPENCODE_CONFIG_CONTENT` reaches only a service that a Calm shell started, and the Desktop app's service ignores it. Codex reads skills from fixed folders only.
- Outside Calm, `calm search` and `calm show` still work, and the commands about this session fail with "not in a Calm session".
- **pi and `~/.agents/skills`:** pi reads that folder too. The extension leaves its own folder out when Codex's copy is there, or pi warns about two skills with one name. OpenCode silently takes the later one.
- **No new setting.** Claude Code's skill comes and goes with the plugin (`hooks = false`). The others come and go with Connect.
- **What it says:** search and show, fork, list, config and doctor. Run `calm`, and `"$CALM_CLI"` only after `command not found`.
- **What it forbids:** `calm status` and `calm notify`, because Calm already knows the state (CLI.md → *Not planned*).
- **Always `--background`** (2026-10-13): without it, `calm fork` moves the user to the fork, and an agent must not move the user's attention.
- **No `allowed-tools`** (2026-10-13). In Claude Code it makes loading the skill ask (changelog 2.1.19, seen on 2.1.296), and its grant ends with the turn. Codex ignores it, and pi never asks. Each `calm` command asks by the agent's own rules, where "don't ask again" saves a rule.
- **Variables and rules:** no permission rule matches a command that starts with `$CALM_CLI` (Claude Code 2.1.296, Codex 0.162, OpenCode 2.0.12). In a test an agent ran `calm list || "$CALM_CLI" list`, which asked, so the skill says not to join the two.
- **Fork during a turn** (checked 2026-10-13): each agent forks cleanly while its own `calm fork` call still runs, and the original finishes. Claude Code, Codex and pi close the open call as interrupted, aborted or failed. OpenCode copies only finished messages.
- **Codex's commands see their own terminal's variables** (checked 2026-10-13 on the TUI, 0.162.1), not the shared daemon's. So `calm fork` from Codex forks the right session.
- **Checked 2026-10-13:** Claude Code picks the skill for the right requests and no others (14 prompts).
- **A fork's answer** (2026-10-13): `calm show` takes the session id that `calm fork` prints, and `calm list` prints session ids. So when the user asks, an agent shows the fork's state and last reply. The skill says not to wait or poll, so `calm wait` stays out (CLI.md → Not planned).

**Claude Code's pasted images** (since 2026-10-06). Claude Code keeps the image behind `[Image #n]` in a per-session folder under its temporary folder.

- `PastedImageResolving` (CalmAgents) gives an agent's tag pattern and finds the image. The core knows the pattern only from the adapter.
- The pane treats a tag as a link (`LinkHover.isCalmOwned`).
- Known limit: Calm does not know which run drew a row, so an old tag can show the new conversation's image.
- Dropped 2026-10-07: a Claude Code mod that drew the images above the prompt, because ⌘ over the tag was enough and the mod cost every session a poll (git history: `ClaudeCodeMod`).

**Transcript tails.** Each agent has a `TranscriptReading` adapter. `readTail` gives the title, a recap (`MessageText.recap`), the agent's own summary, an interruption, and step and progress.

- `SessionProbe` reads again only when `changeMarkers` show a change, one background read per session. A transcript can hold megabytes, so reading never runs on the main thread.
- What a hook reported wins as the transcript's path. Otherwise the adapters find it through `ProcessFacts` and `TranscriptDiscovery`.
- Two candidates mean unknown: a card with another conversation's recap is worse than one with none.
- `JSONLTail` reads from the end and passes over huge lines unparsed, because tool results reach megabytes.

**Turn phase.** An agent with no hook cannot tell Calm it works, but its transcript says it.

- `TranscriptTail.turn` becomes a report through `TranscriptTail.stateChange` (tested as a table), with terminal rank, so a hook outranks it.
- It never overrides a pending *needs you*. A reading written before the latest report is stale.
- Codex's terminal rollouts are told from the desktop app's and subagents' by `originator` and `thread_source`, not `source` (found 2026-09-29).
- Opt-in tests read real history (`CALM_REAL_*`) and print counts only.

**Settings → Agents.** Each adapter declares its `AgentSetup`: `automatic` (Claude Code's plugin), `notifications` (none since 2026-10-13), `files` (pi's extension, OpenCode's plugin and skill, Codex's skill, written on Connect), or `hint`.

- Files Calm writes carry a marker line. Calm refuses to overwrite, and never removes, a file without it.
- At each launch `AgentSetupFiles.refresh` rewrites the files that carry the marker, so a connection made before an update keeps up.
- It also adds a file this version brings, once one of Calm's files for that agent is there (since 2026-10-13, for the skill). Connect gave the agent Calm's files, and Disconnect takes them all.
- Connect's help says what the agent gains (`connectionPurpose`). Codex gains only the skill.

**pi's extension.** It maps pi's events to states and names the conversation on every report.

- A prompt counts as *needs you* only during a run, because pi reports every `ctx.ui.custom` as a prompt, passive overlays included.
- Reports are spawned detached, because pi awaits handlers.

**Codex hooks** (researched 2026-09-29). Decided 2026-09-29: nothing more, because Codex's notifications and the transcript tails give state, recap and interruption.

- Since 0.157 hooks run in one shared `codex app-server` daemon, with the first launcher's environment. A payload names nothing that ties it to a terminal.
- Every hook needs the user's approval in `/hooks`, stored as an internal hash.
- Rejected: a persistent hook tied by folder, because it edits the user's hooks and is ambiguous with two sessions in one folder.
- Rejected: a `codex` wrapper passing hooks by `-c`, because it is slower to start and invasive.
- Revisit if the daemon changes.
- Connect adds only the `calm` skill (Teaching agents about `calm`, above). Codex still reports through its notifications.

**Agent marks.** Each adapter carries its mark as data (`AgentMarkArt` in `<Agent>+Mark.swift`). `MarkMotion` poses it as a function of time, and `AgentLogo` draws it.

- A `frames` mark plays its agent's own PNG frames. Claude Code's spinner plays this way, because posing it from the spark did not look like it.
- Decided 2026-09-30: a working mark and the working line's light are Core Animation layers (`MotionLayers.swift`), because a SwiftUI timeline re-rendered the whole sidebar on each tick.
- The layers take their `timeOffset` from the wall clock, so cards side by side agree.
- Timelines run only while the window can be seen (`WindowPresence`).

**OpenCode plugin** (since 2026-09-30). OpenCode 2 runs the agent in one shared service, whose environment is the first terminal's. So Calm's plugin is a `tui.ts` only, which loads in each terminal's own TUI process and never in the service.

- `OpenCodeAdapter.pluginSource` reports only the session on its own screen, and names it on every report. So Calm follows `/new` and tells two OpenCodes in one folder apart.
- Every handler is guarded, since the plugin API is young.

**Send with ⌘ Return** (since 2026-10-07). Calm intercepts no key: each agent rebinds its own prompt, and Calm lets ⌘↵ through.

- `CalmDefaults` binds `super+enter` to `text:\r` while the setting is off, and unbinds it while it is on.
- `SendKeys` (one per adapter) names the bindings, and `SendKeysFile` writes them into the agent's own keybindings file.
- Codex has none, because its keymap knows only ctrl, alt and shift.
- Claude Code uses `chat:queueSubmit`, because `chat:submit` did nothing while a `/` or `@` menu was open.
- Plain JSON only. A file with comments stays as it is. Off removes exactly Calm's bindings.
- Calm's zsh startup binds both ⌘↵ sequences to Return (Persistence → Shell integration inside zmx).

**Trusted scratch folders** (since 2026-10-11). Claude Code's trust question stopped every ⌘⇧N. So Calm marks the scratch root trusted, once (`AgentIntegrations.trustScratchFolders`, `ClaudeCodeConfig`).

- One entry covers them: Claude Code checks each folder above the one it starts in, up to the git root.
- Calm edits `~/.claude.json` the way Claude Code does: under its lock, read again once the lock is held, replaced in one rename. A held lock is waited on briefly and never broken.
- Known risk: a second Claude Code save path behind a flag has no known lock. Calm writes once per Mac.

Transcript formats are undocumented and change between versions. Each adapter ships fixture files from real sessions. A parse failure degrades to "no transcript", never a crash.

## Attention

Behavior: FEATURES.md → F5.

**State reporting.** Every shell Calm starts gets `CALM_SESSION_ID`, `CALM_SOCKET` and `CALM_CLI` in its environment.

- A hook reports with `"$CALM_CLI" status <state>`, or hands its payload to `"$CALM_CLI" hook <agent>`. Either sends a `status` request.
- Hooks run in every terminal. So `status`, `notify` and `hook` exit 0 and do nothing outside a Calm session, and never launch Calm.
- A request that names an agent is checked against the session's foreground (`AgentKind.speaksForSession`, since 2026-09-30), because Claude Code's Bash tool running `pi -p` turned the row into pi's.
- A hook report that carries its process ancestors (`calm hook` sends them) is dropped when an agent process of the same kind sits between the hook and the session's foreground job (`AgentKind.isNested`, 2026-10-13). An evaluation that ran 72 `claude -p` from Claude Code's Bash tool flipped the card between done and working every second or two, and sent a notification for each answer. It is traced as `ignored … that the session's … started`. A job that isn't among the ancestors proves nothing, so the report stands.
- Open: `calm status --agent …` (pi, OpenCode) sends no ancestors, so a nested pi or OpenCode of the same kind is still not told apart.

**Fallback signals.** When no hook is installed, signals come from libghostty's actions. `Terminal` translates them into `TerminalSignal`, and one pure function reads them (`TerminalSignal.outcome`). Their source is `terminal`, so hooks still win.

| Signal | In an agent session | In a plain shell |
|---|---|---|
| OSC 9;4 progress set / indeterminate | working | working |
| progress removed | done (if it was working) | idle (if it was working) |
| progress error | failed | failed |
| OSC 9 / 777 notification | read by its words: permission, approval, allow, confirm, question → *needs you*. Error, failed → failed. Anything else → done. Only an explicit ask can notify | passed on as a notification (at the next pause, if you're elsewhere) |
| bell | *needs you*, only if the agent was working | ignored |
| command finished (OSC 133) | ignored (the agent run ends when it exits) | done or failed, if it ran long enough |

- Window titles are not used: agents' title formats vary and change.

**State machine.** Per session: `idle → working → (needsYou | done | failed) → idle`, once the user leaves it.

- Reports are idempotent, and the latest wins. Terminal guesses never override a hook report from the same agent run.
- Constraint: a write to the observed `workspace` re-renders the whole sidebar, even when nothing changes. So the manager applies each report to a copy and writes it back only when it changed (`SessionManager.changeWorkspace`). Per-tool-call state lives outside the workspace.
- Applying a report returns an effect: *notify* for a new *needs you* in a session the user is not looking at, and *withdraw* when it leaves *needs you*.
- A finished session stays *done* or *failed* while the user reads it, and settles to idle when the user leaves it.
- Since 2026-09-30, Calm losing the front is not leaving, because a screenshot tool that took the front for a second settled the card being read. `LeavingCalm` decides from the app that comes forward.

**Notification scheduling.** `AttentionQueue` holds one notification per session until a natural pause: a short stop in typing, a focus change, or a maximum wait. It is never dropped.

- `AttentionCenter` delivers through `UNUserNotificationCenter` with no sound and one identifier per session. Visiting the session removes it.
- Self-tests set `CALM_NO_NOTIFICATIONS=1`.

**Permissions at first launch** (decided 2026-10-12, so that no prompt arrives in the middle of work). `FirstLaunchPermissions` runs once.

- It asks for notifications, then reads Documents, Desktop and Downloads one after another. Reading a guarded folder is what makes macOS ask.
- Calm records `askedForPermissions` and never asks again. Tests and headless runs never ask.

**What a notification says** is `NotificationText`: the state mark and the session's title, and a pick from the message that fits its column limit.

**Making an agent's words plain** is `MessageText.recap`, applied where prose enters, so cards, the arrival card and notifications get the same text.

- It drops code, tables and headings, and removes decoration only where a mark clearly wraps words.
- Single `*` and `_` are never touched (since 2026-09-29), because a first version turned `find -name '*.py'` into `find -name '.py'`.
- It must be idempotent: the notification reads a `needsYou` message again.
- Left alone on purpose: permission requests, error text, `calm notify` and `calm status` messages. They quote commands, and a command must reach the screen exactly.

## App icon

**The icon file.** `Calm/Resources/AppIcon.icon` is an Icon Composer document, written by `scripts/app-icon.py`. Xcode compiles it into `Assets.car` with light, dark and tinted renditions.

- To check a change, render it with Icon Composer's `ictool` (inside Xcode), with `--export-image` and `--rendition Default` or `Dark`.

**The dev build's icon and name.** `BuildVariant` is `#if DEBUG`. The Debug configuration uses `AppIconDev` and the name Calm Dev.

- Debug sets `PRODUCT_BUNDLE_IDENTIFIER = com.jinhuang.calm.dev`, so macOS tells the two apps apart: Dock tile, `UserDefaults`, notification and privacy grants.
- `PRODUCT_NAME` stays Calm, because the scripts and tests find the app and its process by that name.
- `DockIconView` picks its dev palette from `BuildVariant.isDev`. Keep it and `AppIconDev` together. `BuildVariantTests` checks they agree.

**Dock states.** `AppIconState.summarizing` reduces the sessions' states to one. `AppIconMotion` turns changes into frames as a function of time. `DockIcon` sets a `DockIconView` while the icon is not idle, and clears it at rest so the Dock shows the real icon.

**Cost.** The icon ticks only while something moves, and draws only frames that changed.

- The Dock takes the chase in whole steps, because at Dock size the ease between places does not show.
- Nothing is drawn while nobody can see the Dock (`DockSight`).
- The tile and its shadow are drawn once into a `CGLayer`, and the chase's pictures are cached. `DockIconViewTests` holds the cached and uncached drawing to the same pixels.

Known limits: the drawn states do not follow the user's icon style (tinted or clear), and the drawn idle frame differs slightly from the system's rendering.

## Search

Behavior: FEATURES.md → F7. The welcome page: FEATURES.md → F2.

**Index.** SQLite FTS5 with `bm25()` ranking, in `~/Library/Application Support/Calm/index.sqlite` (`CALM_INDEX_FILE` overrides it). Only user and agent messages are indexed.

- Decided 2026-09-27 (M4.2): the `trigram` tokenizer, with a `LIKE` scan for queries under three characters. On real history it matched plain substring search for whole words, partial words and Chinese, which unicode61 missed.
- Since 2026-09-30, a term of one or two ASCII letters or digits matches only where a word starts (`SearchMatch`). The scan runs the same Swift rule the panel marks with, so every mark is a match.

**Parsers (M4.1).** `TranscriptIndexing` adapters read complete JSONL records from a byte offset. `JSONLReader` stops at the last newline, so a file being written is read again later.

**Incremental indexing.** Each file's offset, size and date are stored, so only new lines are parsed.

- Decided 2026-09-29: a deleted transcript is kept, marked `gone`, because Claude Code deletes old transcripts.
- A prompt log that outlives its transcripts (`promptHistoryFile`, Claude Code's `history.jsonl`) gives `history` rows for sessions with no transcript.

**Agents' own databases** (2026-09-30). OpenCode 2 keeps every session in one SQLite database. So it has its own protocol, `SessionDatabaseIndexing`, and `SearchIndex.indexDatabase`.

- A session's version is its message count and newest update time, because OpenCode rewrites messages in place for days.
- Text is extracted in SQL, so tool output never reaches Swift.

**Keeping the index.** The index holds sessions that exist nowhere else. So a schema change migrates instead of rebuilding. Only an unknown schema starts over.

**Snippets** are built in Swift, because FTS5's `snippet()` counted trigram tokens and put the match past the visible line.

**Refresh.** The app refreshes the index when ⌘K opens and every few minutes, not through FSEvents, because an update with nothing new is cheap.

**Tables** (`SearchIndex`):

| Table | Holds |
|---|---|
| `files` | A row per transcript, per session in an agent's own database, or per session known only from a prompt history. It holds the agent, the read offset, size and modification time, the session's id, folder, title and first prompt, when it was last active, its `origin` and whether it is `gone` |
| `messages` | The FTS5 table of each message's text, with its file and role |
| `sources` | The read offsets of prompt histories, and the database sizes and times |
| `meta` | The schema version |

**Ranking (M4.4).** `SearchRanking` takes each term's best message per session, then adds boosts for a title match, recency and the current project. Every term must appear somewhere in the session.

**Welcome page.** With no session open, `WelcomePage` shows `WelcomeView` over the whole window. `WelcomeModel` owns a `SearchPanelModel`, the projects and the selection.

- `WelcomeContent.choose` picks between the lists and the first-use welcome.
- The mark is drawn by `DockIconView`, the Dock's own view, so the two cannot drift apart. `WelcomeMarkMotion` animates it until it comes to rest.

**No session chosen.** With sessions open and none selected, `NoSessionPage` shows `NoSessionView` over the main area. `NoSessionContent.choose` decides what it shows.

- Once the user has typed in its search, the lists stay, so a turn ending does not swap the page under their keys.

**Panel (M4.6, grouped 2026-09-30).** ⌘K opens `SearchPanelView` (`MainWindowController+Search`). Opening refreshes the index, and each keystroke queries it, debounced.

- `SearchModel` asks `SearchService.searchPanel` for every match, so each group's count is true.
- `SearchGrouping` groups results by the sidebar's rule. The pure parts are in CalmSearch and unit-tested.
- Enter selects the session a result is open in, or resumes it in a new session.

**Module.** `CalmSearch` holds `SearchIndex` and `SearchRanking`, over `CalmSQLite`.

- `SearchIndex` does all database access on one serial queue, so the control socket can search off the main thread.
- `CalmSQLite` wraps the system SQLite, with no dependency.
- A connection that fails to open is closed in `SQLiteDatabase.init` and never kept (fixed 2026-09-30), because deinit runs even when init throws.

**Performance.** The targets are GOALS.md G3: queries and a no-change update under 50 ms, so ⌘K can refresh before every search. Measured on the author's history (M4.7, Debug build): first full index 12.6 s for 502 files in 1.4 GB, a no-change update 8 ms, queries 0.7–14 ms.

## Find

Behavior: FEATURES.md → F16. Looks: UIUX.md → Find. Plan: ROADMAP.md → M8, M9.

**Ghostty's engine does the searching.** The app hears `START_SEARCH`, `END_SEARCH`, `SEARCH_TOTAL` and `SEARCH_SELECTED`, but only the total and the selected index, not where matches are.

- Matching folds only A to Z, counts overlapping matches, and never crosses a line's end. Calm's own matching must agree, because Ghostty's total is the count shown.

**Keys (M8.1).** Ghostty's own search bindings stay, so a user's Ghostty keybindings keep working. `FindModel` (one per window) turns the four actions into the field's state.

- The actions reach the window a turn of the run loop later (`TerminalEngine`), so its answers are not binding actions run inside libghostty's own call.
- Calm's defaults unbind `escape=end_search`, so esc in the terminal always reaches the program.

**Where the current match is.** Decided 2026-10-07 (M8.2): Calm's own matching, no engine patch, because a patch would need the terminal's lock in a callback that runs without it.

- `FindMatcher` finds the matches on screen. The engine's selected index counts from the newest match, so Calm counts backwards from the newest row.

**Marks (M8.3).** Decided 2026-10-06: Calm draws underlines, because Ghostty's cell fill reads as a selection.

- Calm's defaults make the engine's fill invisible. A search color in the user's config still wins.
- `FindMarksView` draws the marks as layers beside `LinkMarksView`. The current-match pill stays Ghostty's, colored by each theme's Ghostty lines.

**The map needs every match's row**, which Ghostty does not expose. So Calm reads the scrollback itself with one `ghostty_surface_read_text` of the whole screen.

- The read holds the terminal's lock. So Calm scans off the main thread, and reads only when it must.

**The map (M8.4, 2026-10-07).** `FindMap.scan` makes one pass over the scrollback. `FindMapView` draws it.

- It scans whole, not only new lines, because rows can leave the top of a full scrollback.

**Full-screen programs (M8.5).** Engine patch 0018 adds `ghostty_surface_alternate_screen`, because the scroll bar reads the same for the alternate screen. Find then counts "on screen", and `FindNote` offers ⌘K.

**Colors** follow from the theme's background, text and accent (`FindColors`). `FindColorsTests` runs the contrast checks on the built-in themes.

**The viewer (M8.7).** Calm's page has its own find (`calmFind`), PDFs use PDFKit, and HTML uses `WKWebView.find`. The field works over `FindFieldModel`, which both models answer.

**Regular expressions (M9.1).** Ghostty's engine searches plain words only. So with `.*` on, Calm searches with `NSRegularExpression`, line by line through soft wraps.

- The current match stays Ghostty's pill, painted by engine patch 0019.
- Calm's own order picks the current match, because sending the engine the match's text and stepping to it raced (2026-10-07).

**The whole session (M9.2–M9.5).** A full-screen program's screen keeps no history, so Calm keeps what it shows.

- Keeping runs only while a full-screen program draws, because nothing can be had later. Nothing runs at rest or in a plain shell.
- Kept lines are in memory per session, capped, and go when the session closes.
- `ScreenKeeper` decides what scrolled or was replaced. The pane reads (`TerminalSurfaceView+Keep`).
- A read waits for the end of a synchronized update (engine patch 0021), because a half-drawn frame would be kept twice.
- Engine patch 0020 reads the shell's screen behind the program.
- `fullscreen-unseen` in `mise run perf` holds the keeper to its budget. If it cannot meet the budget, it does not ship.
- Known limits: a view that changes only in digits keeps nothing, and a view that moves further than its height between reads loses what passed.
- `SessionPage` puts the kept lines and the shell's output in order, for the viewer's session page.

**At rest** find costs nothing: no timer runs while the field sits open, the map refreshes only when output arrives, and the slides are Core Animation.

## Command palette

Behavior: FEATURES.md → F1.

**Rows are closures (2026-09-30).** `PaletteCommand` is an id, a title, an optional key and a `run`. `MainWindowController+Palette.paletteCommands()` builds the list each time ⌘P opens.

- Decided 2026-09-30: the palette lists what has no key of its own, so it is not a second menu bar.
- Every row is one-shot. What needs a target stays in the right-click menu.

**One list with the card's menu.** The focused session's rows come from `SessionActionSet`, which the card's menu reads too. Decided 2026-10-06: Restart All *Agent* Sessions is in the palette only.

**Every row has a description (2026-10-01).** Calm's rows are cases of `PaletteRow`, whose `help` switches over all of them, so a new row without a description does not compile.

**Ghostty's entries are an allowlist** (`TerminalConfig.paletteActions`), because libghostty's list is dozens of rows of Ghostty's windows and tabs. `PaletteCommandsTests` fails when Ghostty renames one.

**Matching** (`CommandMatcher`). A description matches only as typed, because scattered letters in a sentence matched wrongly. Rows are keyed by id, because position-keyed rows showed stale content after a filter.

**Copy Last Reply** reads the transcript when asked (`TranscriptReading.lastReply(of:)`). The full text is never kept, since the tail is saved in `state.json`.

**Unsplit** is `Workspace.unsplit`. The focused session keeps the layout's id, so what showed it keeps showing it.

**Dump Logs** (`Diagnostics.swift`). `DiagnosticsReport` holds ids, states and agent names only. The trace is this process's only, because another instance would fill it.

## Persistence

Behavior: FEATURES.md → F3.

**Decided (M2.7): zmx** ([zmx.sh](https://zmx.sh), MIT, maintained), pinned in `scripts/zmx.sh` and bundled at `Contents/Resources/bin/zmx`.

- Each session runs `/usr/bin/env -u ZMX_SESSION <zmx> attach calm-<12 hex>`. Unsetting `ZMX_SESSION` keeps an `attach` from taking over the terminal Calm was launched from.
- `ZMX_DIR` keeps Calm's sessions apart from any other zmx use. Names stay short, because each is a Unix socket.
- `ZMX_NO_DETACH_KEY=1` leaves Ctrl-\\ to programs.

**A pane starts at its size** (since 2026-09-30). Reattaching hands the program the new client's size, so that size must be the final one.

- `MainWindowController` restores the frame before building panes. Each pane passes its size and text size in the surface config (engine patch 0013).
- The trace line `pane <id>: attaching at <grid>` shows the grid a pane started with. Check it with a persisting self-test run twice on one state file.

**Closing and quitting.** Quitting detaches. Closing a session runs `zmx kill`.

- Inside zmx, libghostty cannot see the agent. So a close asks whenever the session has an agent run.

**Restart** (`Restart`) is an ordinary quit plus a relaunch by a `/bin/sh` helper that waits for Calm's PID to be gone.

- So two Calms never attach to the same zmx sessions or write the same state.
- The helper strips the self-test drivers from the environment, and opens Calm by path without `-n`. So a Debug build never wakes the installed Calm.
- It also removes an installer's moved-aside copy (Distribution → The moved-aside copy).

**Closing the session on screen selects none.** Calm never picks a session for the user. ⌘W never falls through to closing the window.

**Closing never reaches the next pane.** libghostty can allocate a new surface where a freed one was, so a late "child exited" could close the wrong pane.

- `teardown` drains the mailbox after `ghostty_surface_free`, and a child exit older than the pane is ignored.
- At launch, `calm-*` sessions no saved session refers to are killed.

**Shell integration inside zmx.** libghostty injects its shell integration only when it runs a shell, and here it runs zmx. So `ShellIntegration` sets the variables Ghostty would.

- zsh starts in Calm's own `.zshenv` under Application Support, which sources Ghostty's integration and restores the user's `ZDOTDIR`.
- Calm's file adds the ⌘ Return binding as a self-removing `precmd`, so it binds after the user's `.zshrc`.
- Bash and nushell rely on the process-based folder lookup.

**Without zmx.** Sessions fall back to plain shells for the rest of the run. `CALM_NO_PERSISTENCE=1` forces this.

**App state.** Projects, sessions and layouts live in `~/Library/Application Support/Calm/state.json`.

- A versioned envelope, written atomically and debounced. `WorkspaceStore.save` skips a write when the file already holds the same bytes.
- A file Calm cannot read, or one from a newer Calm, is moved aside as `state.unreadable-<time>.json`, never overwritten. Since 2026-10-12 the next launch says so (`StateAlerts`).

**Text size.** `Workspace.fontSize` is the shared size. Calm watches `CELL_SIZE` and moves the other panes with `set_font_size`, because only the binding action marks the size as the user's.

## Smart links and Copy Cell

Behavior: FEATURES.md → F8, F9.

**Links (M5.1).** libghostty detects URLs and paths. `Link.parse` resolves them against the session's folder, and `EditorLocator` picks the editor (`files.editor`, else the first installed). Xcode is last, because `xed` exists wherever Xcode does.

**Link marks and tag.** libghostty highlights links only while ⌘ is held, and its `link` setting cannot be set yet. So Calm finds links itself.

- `LinkMatcher` is libghostty's own pattern adapted for ICU, tested against Ghostty's cases. `LinkMarksView` draws the marks.
- No resting marks while the mouse is captured, because such a screen is redrawn too often. ⌘ hover and click still work there through patch 0011.
- `MOUSE_OVER_LINK` arrives under the renderer lock, so the pane handles it on the next turn of the main loop.

**Links a program cut across rows.** `HardWrap` joins a line that reaches the edge with the next.

- A joined match is taken only when it resolves, so words that end at the edge do not glue together.
- libghostty knows nothing of these links, so the pane does the pointer work itself.

**Copy Cell (M5.2).** `CopyCell` and `TextGrid` (CalmModel) find a table cell's borders in a text grid, pure and tested with real agent tables. `CellWidth` counts wide characters as two.

**Clicks to cells.** `gridOrigin` works out the top padding, because `tl_px_y` is row 0's baseline, not its top.

**⌥-click and ⌥-drag** (since 2026-09-30). ⌥-click replaced ⌥-double-click, because Claude Code's full-screen view took the first click.

- `TerminalSurfaceView+CopyCell` holds an ⌥-press back from libghostty. A drag becomes Calm's own selection inside the cell, because a terminal's selection runs across whole rows.

## Paste

Behavior: FEATURES.md → F1.

- `TerminalClipboard.plainText` pastes files as their shell-escaped paths, because a terminal cannot carry image data but agents attach an image from its path.
- An image with neither (a screenshot) is saved as a PNG in `$TMPDIR/calm-pasted-images`, so macOS clears old pastes.

## Text input

- `TerminalSurfaceView+Keyboard` is the pane's `NSTextInputClient`: the one door for input methods, dictation and the emoji picker. Committed text goes as typed keys, never as a paste.
- Fixed 2026-09-30: `selectedRange()` never says `{NSNotFound, 0}`, and `insertText` needs no key event in flight. Dictation and voice input did nothing without them. `DictationInputTests` checks both.

## Window

Behavior: FEATURES.md → F1.

**Square corners when filled** (since 2026-10-07). macOS rounds every titled window and has no public API for it.

- `SquareCorners` overrides four private `NSThemeFrame` methods at launch, answering 0 only for a filled `CalmWindow`.
- It checks each method's type encoding and installs all four or none, so a macOS that changes them keeps round corners.
- `CalmWindowTests` reads `_cornerMask`.
- The idea came from m4rkw/macos-corner-fix (MIT). No code was taken.

**Hidden sessions do not render.** `PaneVisibility` keeps two reasons apart: the layout is shown, and the window is visible. A pane draws only when both hold, because one flag for both woke every hidden pane when the window came back into view.

**Size across launches.** `setFrameAutosaveName` does not record a filled window. So `MainWindowController.noteFill` records `Workspace.windowFilled`, and `restoreFrame` reapplies it (`CalmWindow.fillAsLeft`).

- Full screen is kept as `Workspace.windowFullScreen`. Headless runs never enter it.
- Known gap: a launch that should restore full screen sometimes comes back only filled. The cause is not known.

**Narrowest window.** `WindowMinimum` adds the side panels' widths to a minimum and caps it at the screen.

**Title bar double-click.** Calm's content fills the window under a transparent title bar, so AppKit never zooms. `CalmWindow.sendEvent` does what `AppleActionOnDoubleClick` says.

**Session title.** `SessionTitleView` sits in a `SessionTitleHost`, whose `hitTest` answers only over its controls, so dragging and double-clicks reach `CalmWindow`.

- The host sets `safeAreaRegions = []`, because the title bar's safe area pushed the text onto the terminal.
- It reads `Session.titleStrip(agentTitle:)`. The worktree comes from `Session.worktreeName`, shared with the sidebar's card.
- The ⋯ button opens the same menu as a right-click on a card (Session actions).

**Getting into a split and out of one** (UIUX.md → Split panes). The model is `Workspace.join`, `takeOut` and `unsplit` (`Workspace+Splits`). Drop geometry is `SplitTree+Drop`.

- A dragged session uses its own type, `com.jinhuang.calm.session`, which panes never register, so it is never pasted as text.
- `MainWindowController+Splits` keeps the views and the model in step: the pane leaves its old view, then the model changes, then the pane joins its new view.

**Split panes: the dim, the question and the fold** (UIUX.md → Split panes). `PaneDim` holds the values. `TerminalWorkspaceView+Dim` draws veils as views above the panes, because a pane's own layer belongs to libghostty.

- `ClosePrompt` asks before closing a pane in a split. It uses a key monitor, not a first responder, so the pane keeps focus.
- `foldAway` shrinks a `GhostView` of the closed pane while the others take their final frames at once, so the terminal resizes once.

**One focus.** The first responder and the model's `focusedSessionID` must be the same pane.

- A key that reaches a pane moves the model onto it, so the indicators follow the keyboard, never the other way round.
- `traceFocus` writes focus changes to the trace, so a ⌘W on the wrong pane can be read back.

## Arrival card

Behavior: FEATURES.md → F6.

- `ArrivalCard` remembers when the user left each session, in memory only.
- It shows only when the sidebar is hidden (`ArrivalCard.shouldShow`), because beside the sidebar it repeated the card and covered the agent's screen.

## Session actions

Behavior: FEATURES.md → F12, F15.

**The menu Calm draws** (since 2026-10-06). `SessionMenuController`, not a system menu, because a system menu's material takes the wallpaper's tint and cannot follow the theme.

- `SessionMenuContent.make` decides its rows from `SessionActionSet`, so it offers what ⌘P offers.
- Its host sets `safeAreaRegions = []`, as the title strip's does.
- It rebuilds what a system menu gives: arrow keys, type-to-select, a submenu, closing on an outside click, VoiceOver labels.

**Names and conversations (M7).** `Session.customName` is the user's name. `Session.lastConversation` keeps the last `AgentConversation`. Both are optional in the state file.

**Resume and fork commands.** Each adapter builds the agent's own command, shell-quoted.

- OpenCode's CLI has no `--fork`, so its fork goes through `opencode api session.fork`. awk reads the id, since macOS has no `jq` by default.

**Options on resume and fork** (since 2026-10-10). Resume dropped options such as `--dangerously-skip-permissions`, because the argv is gone once the agent exits.

- The probe reads the options when it sees the process (`resumeOptions(commandLine:)`) and saves them in `AgentConversation.options`.
- Everything built from a conversation goes through `resumeCommand(for:)` and `forkCommand(for:prompt:)`.

**⌘N's options where Calm did not see the start** (decided 2026-10-10). ⌘K's resume and `calm show` start from a transcript, which records no options. So they take ⌘N's, which was preferred over resuming bare.

- `ShellWords` splits ⌘N's command and gives nil for anything beyond quotes and backslashes, so a command it cannot read adds no options.
- `ShellWords` is Calm's own, because CalmKit has no dependencies.

**New agent sessions** (⌘N, FEATURES.md → F15). Each adapter declares `launchCommand` and `launchOptions` (`LaunchCommands.swift`).

- Decided 2026-10-07: chips are plain on/off flags that cannot contradict one another, so there are no conflicts to manage.
- Decided 2026-10-06: the settings go over the feature budget: ⌘N's agent and a switch per chip.
- A worktree option comes last, because Claude Code's `-w` would take the next word as its name.
- `CalmDefaults` unbinds Ghostty's `super+n` so ⌘N reaches the menu.

**Empty worktrees** (since 2026-10-07). Killing a session ends the agent before it removes an empty worktree it made. So `WorktreeCleanup.afterClose` removes it.

- It asks the adapters whose lock it is (`AgentAdapter.worktreeOwner(lockReason:)`), waits for that process, and decides with `GitWorktree.isEmpty`.
- It removes with `git worktree remove` (no `--force`) and `git branch -d` (not `-D`), so git checks once more.
- A worktree no adapter claims stays. `WorktreeCleanupTests` runs against real repositories.

**Typing the commands.** Resume types into the session's own shell. Fork splits beside it. Headless self-tests log the command instead, so no test starts a real agent on the user's account.

**Reopen (⌘⇧T).** `ClosedSessions` keeps the last few closed sessions in memory. `Workspace.reopen` restores the name and `createdAt`, so the session lands where it was.

- Ghostty binds ⌘⇧T to `undo`, which takes the key first. So `CalmDefaults` unbinds it.

**Restart** (since 2026-10-06). `SessionManager+Restart` waits for the turn to end, or begins at once.

- It reads the argv first (`ProcessInspector.snapshot`), since it is gone once the process is, and builds `AgentAdapter.restartCommand(arguments:…)`.
- It quits the agent the adapter's way (`AgentQuit`), then types the command into the session's shell.
- ⌃C goes through the pane, so Ghostty encodes it for the agent's keyboard mode.
- `CommandLineOptions` reads a command line the way the agent's own parser does, so a prompt is told from an option's value.

How each agent quits (checked 2026-10-06 and 2026-10-07 against the real agent in a pty):

| Agent | Calm sends | Why |
|---|---|---|
| Claude Code | SIGTERM | Quits cleanly and resets every terminal mode. ⌃C quits only from an empty prompt |
| Codex | ⌃C, again if still running | Quits cleanly on ⌃C. Dies on signals with terminal modes left on |
| OpenCode | SIGTERM | Quits cleanly |
| pi | SIGTERM | Quits cleanly. Dies untidily on SIGINT |

- pi overwrites its argv with `process.title`, so its options are lost and its restart is `pi --session <file>`.

**Updates** (since 2026-10-06, all agents since 2026-10-07). `AgentUpdates.check` reads the version an agent runs and whether a newer one is installed, from how it was installed.

- A native program is updated when its running file is deleted or replaced, or its launcher leads elsewhere.
- A script under node or bun is found from the shell's `_` variable, because its argv can be overwritten. Its version is the nearest package.json's.
- Modification dates are not trusted, because npm dates every file 1985.
- `SessionProbe` runs the check off the main thread, because a version probe can run the program.

## Files and viewer

Behavior: FEATURES.md → F10.

**Listing (M5.3).** `FilesListing` reads the focused session's project folder off the main thread.

- In a repository it uses `git ls-files` and `git status`. Outside one it walks the folder breadth first, so a big first folder cannot use up the file limit.
- `FilesColumn` owns the view and a refresh timer that runs only while the column is shown.

**Changes first** (2026-09-29). Line counts come from `git diff --numstat HEAD`, plus Calm's own count for untracked files (`LineCounts`), bounded because it runs on every refresh.

**Guarded folders are read when opened** (2026-09-29). The first look at the home folder asked for three permissions, and the column stayed empty while it waited.

- `GuardedFolders` names Desktop, Documents and Downloads. `FilesListing.walk` enters one only after the user opens it.
- A root inside a guarded folder is read whole: the user chose it.
- Known gap: a folder macOS refused shows empty, with no word why.

**Big untracked folders** (since 2026-10-11). A project with an unignored `node_modules` showed tens of thousands of rows.

- `status` runs without `-uall`, so git reports such a folder as one entry. `UntrackedFolder` counts its files and collapses it past a limit.

**Finding the column** (decided 2026-09-30 from mockups: the footer row, plus the readout).

- The title strip's readout is `ChangeSummary`, read by `FilesListing.readSummary` without the tree, and never outside a repository.
- An 8 s timer runs only while an agent works. Otherwise the summary refreshes on events.
- The title row's `ViewThatFits` drops the readout before the worktree, and the worktree before the name.

**Layout motion.** `Motion.animateLayout` sets the constraints at once and glides only the layers, so the terminal resizes once, because each resize reaches the program and agents redraw on each.

**Viewer, decided (M5.4): a web view for Markdown, HTML, code and text, PDFKit for PDFs, an image view for images.**

- Agents write GitHub-flavored Markdown, and `AttributedString(markdown:)` does not render tables. HTML needs a web view anyway.
- `Calm/Resources/Viewer/viewer.html` uses markdown-it and highlight.js, pinned with checksums in `scripts/viewer-assets.sh` and committed, so builds stay offline.
- Raw HTML in Markdown shows as text, and HTML comments are hidden as on GitHub (since 2026-10-15). Since 2026-10-12, HTML and SVG files open with page JavaScript off.
- The page may read only its own folder in the app, so a Markdown file's local pictures come through `ViewerImages`, a `calm-image://` scheme that serves image files only (since 2026-10-15). Web pictures load as they are.

**Opening files (M5.5, M5.6).** `ViewableKind` picks the kind by extension. The viewer covers the terminal area and closes when another session shows. `open-in = "editor"` prefers the editor.

**Header and diffs** (since 2026-10-07). Decided 2026-10-07: diffs are for reading what changed, not for staging or review, because review belongs in the editor.

- `ViewerChange.read` runs `git diff` and `git show HEAD:` off the main thread. `FileDiff` parses and pairs the hunks.
- `viewer.html` highlights whole texts once, so a comment across lines keeps its color.

**Size** (since 2026-10-11). The viewer's key monitor takes ⌘+, ⌘− and ⌘0, because they reached the terminal under a viewed file.

- `ViewerZoom` holds the steps. Web views use `pageZoom`, PDFs `scaleFactor`, pictures `magnification`.
- Only a file's page keeps its size (`Workspace.viewerZoom`).
- The page keeps the same text at the top across a zoom, because WebKit keeps the scroll offset instead.

**The size in the row** (decided 2026-10-11 from mockups: a quiet readout at rest, a stepper under the pointer). `ViewerSizeControl` is laid out whole at rest, so the number does not move when the buttons appear.

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

**Reading themes (M6.1).** `CalmTheme` and `ThemeLibrary` read the files with config.toml's reader. A bad color is dropped with a logged problem, and the rest still works.

- Built-in themes come from `Calm/Resources/Themes`. User themes in `~/.config/calm/themes/` replace a built-in of the same name.

**The built-in set.** Five themes, written by `scripts/themes.py` from OKLCH values, which also checks their contrast. A unit test holds the shipped files to it.

- Each theme is a direction of its own, because an earlier set from one generator read as one theme six times.
- The palettes are original, not copied from other themes.

**Not the theme's to change:** colors an app sends as truecolor.

**OpenCode wears the theme** (since 2026-09-30). OpenCode's own themes are truecolor and ignore the terminal's.

- Calm's shells ask for a theme through `OPENCODE_CLI_CONFIG_CONTENT` (the adapter's `shellEnvironment`), unless the user named one.
- While OpenCode is connected, `OpenCodeTheme` writes `~/.config/opencode/themes/calm.json`, because OpenCode's `system` theme arranges the colors its own way.
- The file holds the appearance on screen, because OpenCode picks light or dark from a cached palette, not the terminal.
- `AgentSetupFiles.syncTheme` keeps it, and never touches a `calm.json` Calm did not write.
- The plugin sends OpenCode SIGUSR2 when the file changes, only while OpenCode listens for it, since an unhandled SIGUSR2 ends a process.

**pi wears the theme too** (since 2026-09-30). `PiTheme` writes `~/.pi/agent/themes/calm.json` for a connected pi.

- The extension applies it as an object, not by name, because a name is saved to pi's `settings.json` and would carry Calm's theme outside Calm.
- pi puts its setting's theme back after `/reload` and similar, with no event to wait for. So the extension sets Calm's theme again for a short while, only while pi's own theme is a built-in.

**How a theme reaches the terminal** (`TerminalTheme`). Ghostty ranks a theme file's colors below colors set in any config.

- The default theme is two Ghostty theme files in Calm's defaults, so a theme or colors in the user's Ghostty config win.
- A theme picked in Calm is written as plain colors to `choices.ghostty`, loaded after the user's config, so it wins. Calm rewrites it on an appearance change.

**Chrome (M6.2).** The chrome derives its colors from the terminal's background (`SidebarStyle.derived`), or uses a Calm theme's own colors.

- *Needs you* stays Calm's amber (`SidebarStyle.attention`), because a blue or green accent read as *working* or *done*.

**Picker (M6.3).** `ThemePickerModel` gives each theme's colors. Picking Calm still writes `theme = "Calm"`, so it wins over colors in the user's Ghostty config. Only the Ghostty choice removes the key.

**Window options (M6.4).** `WindowStyle` owns the terminal area's insets and the glass effect view. Glass sets Ghostty's `background-opacity` in `choices.ghostty`, which avoids Ghostty's private-API window blur.

**Adaptive background.** When an app paints the background (OSC 11), the chrome derives from the new color.

**Settings screen (M6.5).** Behavior: FEATURES.md → F14.

- `SettingsPage` covers the window, as `WelcomePage` does. Each section has a small `@Observable` model that saves through `CalmSettings.save`.
- `SettingsComponents` draws its controls in SwiftUI, because AppKit's know only the system accent.
- Ghostty's C API cannot return a repeatable key such as `font-family`, so `GhosttyConfigText.fontFamily` reads the text.

**Accessibility (M6.6).** `AccessibilitySettings` reads Reduce Motion and Increase Contrast. `CalmTheme.Colors.contrasted()` lifts text to 4.5:1.

- Ghostty's `minimum-contrast` was tried and dropped, because it made dim text brighter than normal text.

**Interface size.** `InterfaceScale.shared.factor` multiplies the chrome's sizes, because SwiftUI's Dynamic Type does not reach fixed-size fonts on macOS.

**Session card sizes.** `SessionCardLayout` says what goes under a card's title for a size and a state.

- Constraint: a setting the chrome draws from reaches its view as a stored value. Read from `manager.settings` in a body, it does not update, because the settings are not observed.

**Shrink to fit** (`sidebar.cards-fit`). `SidebarCardFit` asks `SessionCardFit` for the size to draw.

- Stepping down is exact. Stepping up is a guess with a margin, and waits a while after a step down, because working agents change the contents every few seconds and the size flipped at every state change.
- `restoreFrame` runs before `buildLayout`, because the first look otherwise measured the windowed frame.

## Motion in the window

- The window's content view is layer-backed, because AppKit's timer-driven fallback never ran outside event handling and left a new session invisible.
- The layout fade is presentation-only, so a skipped animation cannot leave a session invisible.
- Overlays are removed on a timer, not in an animation's completion, so one never lingers invisibly and takes clicks.
- `Motion` is the one switch: off under Reduce Motion, or when `motion` is `reduced` or `off`.

**Session switcher.** A local event monitor takes ⌃Tab before the terminal does. Previews are snapshots of each session's pane. It cycles in sidebar order (`SessionManager.orderedSessions`).

**Sidebar peek.** A sensor at the left edge slides a second sidebar view in. The sensor is a tracking area only, and never takes clicks.

## Motion in the terminal

**Padding and title strip.** Calm's defaults set `window-padding-color = extend`. libghostty does not expose that color, so `SurfaceEdgeColor` samples the pane's rendered top row.

- When the pane's sides agree with the sample, the app painted its pane in that color, and the strip takes it. Otherwise the strip keeps the theme's background.
- The middle of the pane is never read, because a fallback to the body's shade turned the strip green under a long diff (removed 2026-09-30).
- Engine patch 0009 (since 2026-09-29) extends side padding only for a background painted out to the edge, because pi's reverse-video cursor at column 0 stretched into the padding.
- `scripts/fixtures/edge-cursor.sh` is the padding self-test's fixture.

**Cursor glide.** `Calm/Resources/Shaders/cursor_glide.glsl` is a Ghostty custom shader. `CalmDefaults` writes it into `defaults.ghostty`, which loads before the user's config.

- `custom-shader-animation = cursor` (engine patch 0014, since 2026-09-30) runs the loop only for a second after the cursor moves. Ghostty's `true` redrew a focused pane forever.

**Smooth scrolling** (since 2026-09-29). Upstream Ghostty draws only whole rows. Engine patch 0005 adds the `smooth-scroll` key (Tech stack → Engine patches).

- `CalmDefaults` writes the key with full motion only, and only when the engine knows it (`GhosttyRuntime.hasSmoothScroll`).
- On the alternate screen, a region scroll eases home, which makes Claude Code's streaming view smooth.
- Clicks, selection and the IME position use the rows as drawn.

**0008 and 0012: overlays stay still.** Claude Code redraws its "Jump to bottom" hint after every scroll, so an animated region showed two or three hints.

- A run of cells repainted in place becomes a hole in the region, drawn in place. Plain text never counts, so streaming is unchanged.

**0010 and 0015: scrolls a program draws without scrolling.** pi and OpenCode rewrite rows in place and never scroll, so the terminal had nothing to animate.

- The renderer compares row hashes with the last frame and animates a shift it finds.
- 0015 leaves still columns (a scrollbar, a sidebar) out of the region.
- Constraint: the inference runs under the state mutex and changes no animation itself. `applyRegionScrolls` applies its result under the draw mutex.

**0011: a link under ⌘ in a program with the mouse captured.** Ghostty offers only shift, which is the select gesture. Super has no bit in any mouse protocol, so the program loses nothing.

**0016: frames only as the content moves** (since 2026-09-30). A frame is due once the content has moved a pixel, and the display link stops once frames come further apart than a refresh.

**0017: no timer under vsync** (since 2026-10-06). The animation timer stays off while the display link draws every refresh, because each tick only armed the next.

**Checking it.** `scripts/fixtures/region-scroll.sh` scrolls a region with Claude Code's captured bytes. `MotionProbe` (Debug only) logs how far the content moved in each frame. Compare against the same run with motion off.

- Captures of real agents stay out of the repository, because they hold conversations.

## Configuration

Behavior: FEATURES.md → F14.

- One file: `~/.config/calm/config.toml` (`CALM_CONFIG_FILE` overrides it).
- `CalmSettings` reads the flat subset of TOML Calm needs, with `[sections]` flattened to `section.key`. It reports malformed lines instead of failing.
- Renamed 2026-10-07: each key sits under what it is about (was flat names such as `session-cards`).

| Section | Keys |
|---|---|
| top level | `theme`, `motion`, `ui-size`: the whole window's look |
| `[window]` | `background`, `layout` |
| `[sidebar]` | `cards`, `cards-fit`, `footer`, `auto-grouping` |
| `[files]` | `editor`, `open-in` |
| `[agents]` | `notify`, `sound`, `send-with-cmd-return`, and ⌘N's `new-session`: for every agent |
| `[agents.<agent>]` (`claude-code`, `codex`, `opencode`, `pi`) | Claude Code's `hooks`. ⌘N's `skip-permissions`, `worktree`, `trust-project-files`, `flags` and `command` |
| `[updates]` | `check` |

**Writing.** `CalmSettings.save` writes one line at a time, so comments and unknown keys stay. Choosing a default removes the key, except the theme (Themes → Picker).

**Known keys.** `CalmSettings.keys` lists every key for `calm config`. A key Calm starts reading must go in it too, or `calm config` will not know it.

- The agents' options are added by `Agents.settingsKeys`, since only the adapters know them.

**Ghostty options** load in this order, each winning over the one before:

1. Calm's `defaults.ghostty`: keybindings, padding color, motion, the default theme.
2. The user's Ghostty config.
3. Calm's `choices.ghostty`: a picked theme, glass.
4. `~/.config/calm/terminal.ghostty`, for Calm-only overrides.

## Control protocol

Behavior: FEATURES.md → F13. Every command: CLI.md.

- The socket is at `~/Library/Application Support/Calm/calm.sock` (mode 600). `CALM_SOCKET` overrides it.
- One request per connection: a line of JSON with `v` and `cmd`. The types are in `CalmControl` (`ControlProtocol.swift`).
- A request from a newer `calm` is refused, with a note to update Calm.
- Clients are served one at a time. Since 2026-10-12 a stalled read or write times out, so a silent client cannot hold up every hook.
- Connections set `SO_NOSIGPIPE`, so a caller that hangs up cannot end Calm.

**One Calm per socket, and a socket that heals** (since 2026-09-30). A second copy used to take the socket and leave it dead on quit, and every hook was refused.

- A Calm that starts while another answers on the same socket quits at once, in `main.swift`, before anything is touched (`SingleInstance`).
- A running Calm checks that the path still leads to its listener, and listens again when it does not (`listenAgainIfLost`).

**Commands.**

| Command | What it does |
|---|---|
| `open` | A folder becomes a project with a new session. A file, or `file:line`, opens in the viewer or the editor |
| `list` | Sessions with id, title, project, folder, state, agent, and the agent's id for the conversation running or last run there |
| `status` | A state report, with the agent, its session id, its transcript, the shells still running, a compaction, and the live line's activity |
| `notify` | A notification for the session |
| `search` | Answered off the main thread, since the index has its own queue |
| `info` | The answering Calm's process id, bundle path and version, and the named session's state: what `calm doctor` asks |
| `reload` | Reads config.toml and the Ghostty config again. `calm config` sends it, since config.toml is not watched |
| `fork` | Below |
| `screenshot` | The main window as base64 PNG. The CLI writes the file, so the app never writes where the caller's shell might not be allowed to |

`calm hook <agent>` exists only in the CLI: the adapter (`HookReporting`) turns the payload into a `status` request.

**Starting Calm.** `open` and `list` start Calm when the socket is missing. `status`, `notify` and `hook` never do.

- Decided 2026-09-30: `CalmLaunch` starts the app the CLI sits in, not one found by bundle id, because a Debug build's CLI started the installed Calm.

**Hook input.** `HookInput` reads the payload with a deadline and a size limit, because a hook holds its agent up.

**`calm search`** reads the index itself when Calm is not running or slow to answer. An error from Calm is shown, not searched around (`SearchRoute`), so "update Calm" reaches the user.

**`calm doctor`** (since 2026-10-06). The CLI gathers facts, and `Doctor` (CalmControl) turns them into checks, so every verdict is tested without a running Calm.

**`calm trace`** (since 2026-10-06). It runs `/usr/bin/log show` filtered to the trace and the app the CLI came with. `TraceLog.Printer` formats it, tested on a real trace (`trace.ndjson`).

**`calm fork`** (since 2026-10-06). `ControlServer.fork` builds the adapter's `forkCommand`, and `MainWindowController.forkForCLI` opens it as F12's Fork does.

- An adapter that cannot take a prompt gives nil, so a prompt is refused rather than dropped.
- A background fork's pane is made at once at its shown size, because the placeholder garbles a full-screen program.
- A session it made cannot fork (`forkedByCLI`).

**`calm show`** (since 2026-10-06). `SearchIndex.conversation(id:)` finds a conversation. `ConversationReport` lays it out.

**The CLI binary.** A separate target (module `CalmCLI`), installed at `Contents/Resources/bin/calm`.

- Beside it, `bin` holds a link to each CalmKit resource bundle, because a command-line tool's `Bundle.module` looks beside the executable and stops the process when it is missing (found 2026-10-07). `AppBundleTests` holds the links.

## Testing

- **Unit:** CalmKit's packages (`swift test`), with fixtures from real transcripts. App-hosted tests in `CalmTests` for code that needs AppKit or the engine.
- **Integration:** control socket round trips, the indexer on fixture folders.

**Cost at rest** (`mise run perf`, `scripts/perf-check.py`, not part of `test`). Each scenario is a headless run held to a budget of instructions and wakeups a second.

- The budget counts instructions, not CPU time, because CPU time on a busy Mac varied several-fold between identical runs.
- Scenarios: an idle shell, working agents seen and unseen, compacting, a streaming full-screen program, and the same hidden (Find's keeper). `perf-check.py` holds the budgets.
- After a change to rendering, animation or timers, run `mise run perf`.

**Self-tests** (Debug builds). `scripts/selftest.sh` launches the app and drives it through `Calm/App/SelfTest.swift` and `MainWindowController.performForTesting`. Checks read the log and the snapshot. There are no reference images.

- `CALM_HEADLESS=1` keeps the window invisible and never key, so a run never takes the user's focus (`Headless`).
- A run quits by itself well past its snapshot delay, because an orphan once ran for hours.
- A snapshot draws layers at their model values, not mid-animation.

**Isolation.** Each self-test gets its own state, support folder, config, socket, zmx folder and index, and no Ghostty config, persistence or notifications unless asked. So it never touches the installed Calm.

- Everything Calm copies or pastes goes through `NSPasteboard.calm`, a pasteboard of its own in a headless run. Never save and restore the user's clipboard instead, because that lost an image the user had copied (2026-09-30).
- A real program run inside a test can still write the clipboard itself.
- `UserDefaults` follow the bundle id, so a Debug run never changes the installed Calm's.

**Running the tests.** `mise run test` runs the package's tests, then the app's, even when the first fails.

- Since 2026-10-06, each CI step runs whatever the others did, because a red package test hid two red app tests for three runs.

**Tests that depend on the machine** (2026-10-06). A CI runner's display is 1× and it has system events a Mac at rest does not.

- A new test that draws pixels or reads the current event must say what it assumes about the machine, and its failure message must print it.

**Trace** (since 2026-09-29). `Trace` writes a timeline of what decides a session's row to the unified log (category `trace`, notice level). It was added to find why a Restart was slow to show *working*.

```sh
/usr/bin/log show --last 5m --predicate 'subsystem == "com.jinhuang.calm" AND category == "trace"'
```

- Plain `log` is a zsh builtin, so use the full path.
- Each line is seconds since launch, the event, and the session's first eight hex digits.
- Events: launch milestones, `restore`, `launch pass`, `settle`, `pane`, `probe`, `agent named`, `report`, `ignored`, `transcript` and `control … waited`.
- The trace holds only states, sources, counts and agent names, never text a user or agent wrote.

## Licensing and references

- Calm is licensed under **Apache-2.0** (`LICENSE`, `NOTICE`).
- Ghostty (MIT) can be studied, and small parts adapted, with attribution in the file header and in `NOTICE`.
- Other projects are for ideas only. Calm copies no code from them, with one exception (decided 2026-09-29).
- The exception: engine patches 0005 and 0006 in `scripts/ghostty-patches`, taken unchanged from `thdxg/ghostty` (a Ghostty fork, MIT) and credited in `NOTICE`. Refresh them from the fork, and do not edit them here.
- Calm's own patches beside them (0007 and up) are written here, each as a separate file (Tech stack → Engine patches).
- Agent marks are the agents' own logos, shown only to identify which agent a session runs. Their sources and owners are listed in `NOTICE`. The motions are Calm's own code.

**Notices that ship** (decided 2026-10-08, before the first download). Calm embeds libghostty, so Ghostty's license notice ships with the app, and so do the notices of what the engine builds in:

| Component | Note |
|---|---|
| C and C++ libraries: FreeType, zlib, libpng, Oniguruma, glslang, SPIRV-Cross, simdutf, Highway, Wuffs, stb_image, Dear ImGui | Their own notices |
| GNU libintl | LGPL-2.1, linked statically. Calm's source and build steps let anyone relink it, and `NOTICE` names its source |
| z2d | MPL-2.0, unmodified |
| Ghostty's Zig packages, Zig's standard library | Their own notices |
| Embedded fonts: JetBrains Mono (OFL), Symbols Nerd Font | Their own notices |
| `Resources/ghostty`: the iTerm2-Color-Schemes themes and shell integration scripts | bash's and zsh's scripts are GPL-3.0, each its own source |

- The list comes from the library's object files and the fonts in the built app. harfbuzz, fontconfig, libxml2 and Sentry are not linked on macOS.
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

- `UpdateChecker` (App) does the request and keeps the answer in `UserDefaults`. It is `@Observable`, so the sidebar's `UpdateNotice` redraws when a check finds something.

**No timer** (decided 2026-10-09). A repeating timer would add wakeups at rest. A check runs after launch and when Calm becomes active, only when `UpdateSchedule` says it is due.

**The request.** One GET of GitHub's releases list, with the last ETag.

- Decided 2026-10-09: the list, not `/releases/latest`, because `latest` leaves out pre-releases and answers 404 while every release is one.
- A tag that is not `MAJOR.MINOR.PATCH` is skipped, so `edge` is never offered.
- Calm sends no token, because one check a day is far under the unauthenticated limit.
- `CALM_UPDATE_FEED` points a run at a file. The Debug build and self-tests never check on their own.

**Update and Restart runs get.sh** (decided 2026-10-12), because get.sh already does the checksum, the swap and the quarantine mark, and a copy in Swift would drift from it.

- `UpdateInstaller` runs `CalmUpdates.installArguments`. The version is parsed, and the folder is a script argument, never shell text.
- An installer that runs too long is ended, so "installing" never stays up forever.
- Sparkle waits for a Developer ID, because it needs a signing key, an appcast and a framework, and gains little while the app is ad-hoc signed.

**Copy Update Command.** The command matches how Calm was installed, because get.sh refuses to replace a Calm that Homebrew installed.

## Distribution

**Building from source.** `install.sh` builds a Release Calm into `/Applications` and links `calm` into `~/.local/bin`.

- Since 2026-10-07 it refuses an app whose resource bundles differ from the ones just built, because an incremental build once installed a stale bundle.
- It swaps the app in with two renames, so a failed copy never leaves no Calm.
- It does not quit a running Calm.
- It unregisters and deletes the build it copied from, because macOS can start any registered copy of the bundle id (2026-10-07).

**The moved-aside copy.** The old app is moved aside (`.Calm.app.previous-<time>`), not deleted, while a Calm runs from it.

- Deleting the file a running Calm came from stops macOS showing it the folder picker (2026-10-07).
- The moved copy must go the moment its Calm quits (2026-10-12), because opening `/Applications/Calm.app` started the moved copy again. Why is not known.
- Calm 0.1.2 and later remove it themselves, in the quit helper (`Restart.swift`). It knows the copy by its program file (`proc_pidpath`) and the installers' name.
- For an older Calm, or a crash, `install.sh` and `get.sh` leave a waiter (`remove_once_quit`). `scripts/moved-copy-check.sh` measures it, and `get.yml` checks it.

**Installing under a running Calm** (seen 2026-10-01, cause not proven). Until it restarts, a Calm whose app was replaced can lose its shells' access to Documents, Desktop and Downloads ("Operation not permitted").

- Restarting Calm clears it. Whether keeping the old app aside prevents it is not proven, so the advice to restart stays.
- `install.sh` says so when it finishes, and whoever installs tells the user to restart Calm soon.
- A real fix waits for a stable signature (Signing, below).

**CI.** `.github/workflows/ci.yml` builds GhosttyKit, then lints, builds and tests every push to `main` and every pull request. Each step reports even when another failed (Testing).

- The engine cache is keyed by the pin, the patches and the fetch scripts, and is saved straight after the engine builds, so a later red step does not cost the next run the build.
- `scripts/ghostty-deps.py` first uses copies in `scripts/ghostty-mirror/`, because Codeberg's outage on 2026-09-30 failed CI. Zig checks every package's hash, so a copy cannot change what is built.

**Releases** are tags (`vX.Y.Z`) on `main`, with their notes in CHANGELOG.md.

- The version is written in `project.yml` and `CLI/main.swift`. `VersionTests` fails when they disagree.

To cut a release:

1. Bump the version in both places, and run `xcodegen generate`.
2. Give the version a section in CHANGELOG.md headed `## X.Y.Z — <date>`. Put each paragraph and item on one line, because a release's notes break lines wherever the text does.
3. Land it.
4. Once main's CI is green, push the tag on that commit: `git tag vX.Y.Z <sha>`, `git push origin vX.Y.Z`.

`.github/workflows/release.yml` does the rest. It checks the tag, builds from source with no cache (so a release proves a fresh clone builds), tests, makes and checks a disk image (`scripts/disk-image.sh`), and publishes. Then it starts `homebrew.yml` and `get.yml`, and restarts the edge build.

- Decided 2026-10-08: releases ship a download, not only source, because building needs Xcode 26 and a long engine build.

**Homebrew.** `homebrew.yml` points the cask in Calm's own tap (`jinhuang712/homebrew-tap`) at the release, with a deploy key that can write to the tap only.

- The cask does not take the download mark off, because Homebrew dropped `--no-quarantine`. So the caveats give the `xattr` line, and the official list waits for Developer ID.

**get.sh**, at the repository's root, is the one-line install.

- It installs the newest `vMAJOR.MINOR.PATCH` release, checked against the asset's sha256, the way `install.sh` swaps.
- It runs `/usr/bin/xattr` by path, because Homebrew's python `xattr` has no `-r`.
- It refuses a Calm that Homebrew installed, and a Mac older than macOS 14.5.
- It runs only from `main()` at its end, so a download cut short runs nothing.

**Edge builds** (decided 2026-10-11): the newest `main` for a Mac with no Xcode.

- `.github/workflows/edge.yml` runs when CI ends green on `main`, and publishes one pre-release tagged `edge`.
- The disk image goes up before the tag moves, so a reader never finds a tag with no disk image.
- Decided 2026-10-11: an edge build's version is the last release's plus the commit (`0.1.0-dc970ac`), so one rolling release can still say which build it is.
- `ReleaseVersion(runningBuild:)` counts an edge build as the version it follows, so it is offered the next release.
- Everything that means "the newest release" must skip `edge`, and does.
- The tag moves with each build. A clone that fetched it needs `git fetch --tags --force`.

**Signing: ad hoc** (decided 2026-09-29). An ad-hoc signature's requirement is a hash of one build, so macOS asks for folder access again after each update.

- A self-signed certificate was tried and dropped, because every `codesign` run then asked for the login keychain password. An app that asks for a password over and over looks like malware.
- What keeps prompts few instead: guarded folders are read only when opened (Files and viewer), and the first launch asks once (Attention → Permissions at first launch).

**Later:** Developer ID signing, notarization, Sparkle updates (which install, unlike the notice), and a cask in Homebrew's own list. A Developer ID's requirement stays the same across updates, so a user's grants survive them.
