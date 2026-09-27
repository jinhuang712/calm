# Designs

Technical design of Calm Terminal. What the features do is in [FEATURES.md](FEATURES.md); this document covers how. Items marked **Decision** are open and should be settled before the phase that needs them.

## Tech stack

| Layer | Choice |
|---|---|
| Language | Swift 6, strict concurrency checking on |
| UI | SwiftUI for chrome (sidebar, panels, settings, search); AppKit for windows and the terminal view |
| Terminal engine | libghostty, used through the GhosttyKit framework |
| Storage | JSON for app state (`state.json`); SQLite FTS5 for the search index |
| Build | XcodeGen (`project.yml`) + `mise` tasks |
| Quality | swiftformat, swiftlint, Swift Testing |
| Minimum OS | macOS 26, Apple silicon (decided in M0.1; keeps the codebase free of old-version branches) |

**GhosttyKit source:** built from upstream Ghostty (`ghostty-org/ghostty`) at the commit pinned in `scripts/ghostty.env`, with the Zig version Ghostty requires (pinned in `mise.toml`), locally and in CI. No third-party forks or prebuilt binaries.

- `scripts/ghosttykit.sh` builds `GhosttyKit.xcframework` (native arm64, ReleaseFast, no i18n or Sentry) plus Ghostty's resources (themes, shell integration, terminfo), caches them per commit in `~/Library/Caches/calm/ghostty/<commit>`, and copies them into `Frameworks/` (not tracked).
- `scripts/ghostty-deps.py` prefetches Ghostty's Zig packages with curl into the project-local `zig-pkg/`, because Zig's HTTP client fails behind some local HTTP proxies.
- A Ghostty `main` commit is pinned rather than the v1.3.1 release: v1.3.1 needs Zig 0.15.2, which cannot link against the macOS 26.5 SDK. Move to the next Ghostty release once it supports Zig 0.16.
- Building needs Xcode's Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`) for Ghostty's shaders.

## Project layout

```
project.yml              XcodeGen spec (generates Calm.xcodeproj, not tracked)
mise.toml                toolchain pins and tasks
Calm/                    app target (AppKit + SwiftUI)
  App/                   entry point, app delegate, menus
  Terminal/              the only code that imports GhosttyKit
CalmTests/               app-hosted tests (engine smoke tests)
CLI/                     the `calm` command-line tool
Packages/CalmKit/        UI-free Swift package: CalmModel, CalmControl, CalmAgents; later Search
scripts/                 GhosttyKit build, xcodebuild wrapper
Frameworks/              built GhosttyKit + Ghostty resources (not tracked)
```

Ghostty's resources are copied into `Calm.app/Contents/Resources/{ghostty,terminfo}` at build time, and `GHOSTTY_RESOURCES_DIR` points at them unless already set.

## Module map

```
Calm (app target)
├── App            launch, windows, menus, lifecycle
├── Terminal       GhosttyKit wrapper: app, surfaces, input, clipboard, links
├── Model          Project, Session, Pane, Layout (pure Swift, no UI)
├── Workspace      grouping sessions into projects, split layouts
├── Agents         one adapter per agent (detection, transcripts, commands)
├── Attention      session state machine, notification scheduling
├── Search         transcript indexer and query engine
├── Persistence    session daemon client, app state store
├── Files          file tree column, full-area viewer (Markdown, HTML, PDF, code, images)
├── Theme          theme files, tokens, picker
├── Settings       config file, settings screen
└── Control        local socket server for the `calm` CLI
calm (CLI target)  talks to Control
```

Rules:

- **Model** has no dependency on SwiftUI, AppKit or GhosttyKit, so it is fully unit-testable.
- **Terminal** is the only module that touches GhosttyKit.
- Each **Agents** adapter is self-contained; adding an agent never changes the core.

## Data model

```swift
struct Project: Identifiable {
    let id: UUID
    var path: URL             // the folder that defines the project
    var name: String
    var isAutomatic: Bool     // created by auto-grouping, not by the user
}

struct Session: Identifiable {
    let id: UUID              // also exported to the shell as CALM_SESSION_ID
    var projectID: Project.ID
    var title: String
    var workingDirectory: URL
    var isPinned: Bool        // pinned sessions don't move between projects
    var agent: AgentRun?      // present while an agent runs in the foreground
    var state: SessionState
}

struct AgentRun {
    var kind: AgentKind       // .claudeCode, .codex, .openCode, .pi, .omp
    var transcript: URL?      // the agent's session file, when known
    var agentSessionID: String?
    var lastMessage: String?
    var lastActivity: Date
}

enum SessionState { case idle, working, needsYou, done, failed }
```

Panes and tabs are **views of sessions**: a layout tree references session IDs. Closing a pane doesn't delete the session; it detaches it.

As built (M2): `Workspace` holds `projects`, `sessions` and `layouts`. A `PaneLayout` is one tab: a `SplitTree<Session.ID>` plus the focused session. Every session is one pane, so a split creates a session and `⌘T` creates a session with its own layout. Calm has **one main window**; "new window" requests from libghostty become new sessions, since the sidebar replaces windows and tabs as the way to hold many shells.

## Auto-grouping

1. The shell reports its working directory (OSC 7 through libghostty's pwd action). For panes that never send OSC 7, `WorkingDirectoryProbe` reads the shell's folder with `proc_pidinfo(PROC_PIDVNODEPATHINFO)` every 2 seconds: the shell's pid comes from `zmx list` for persistent sessions (looked up only when unknown) and from `ghostty_surface_foreground_pid` otherwise.
2. On change, find the project whose `path` is the longest prefix of the directory.
3. If none, find the git repository root and create an automatic project for it, or use the folder itself.
4. Move the session unless it is pinned. Moves are animated in the sidebar (`matchedGeometryEffect`, so a row glides from one project to the other).
5. With `auto-grouping = false`, the folder is still recorded but the session stays where it is.

## Agents

```swift
protocol AgentAdapter {
    var kind: AgentKind { get }
    func matches(process: ProcessInfoSnapshot) -> Bool
    func transcripts() -> [TranscriptLocation]
    func parse(_ transcript: URL, from offset: UInt64) throws -> [TranscriptMessage]
    func resumeCommand(for id: String) -> [String]?
    func forkCommand(for id: String) -> [String]?
}
```

**Detection (as built, M3.1).** `SessionProbe` looks at every session every 2 seconds. A persistent session's shell pid comes from `zmx list`; `proc_pidinfo(PROC_PIDTBSDINFO)` gives the terminal's foreground process group (`e_tpgid`), and when it differs from the shell's own group a job is running. Only when that job changes does Calm read its path and arguments (`sysctl KERN_PROCARGS2`) and ask the adapters. Without zmx, the pane's foreground process (`ghostty_surface_foreground_pid`) is used. Adapters in `CalmAgents` match on executable or script names, per-platform binary prefixes, and package paths for scripts run by node or bun. Agent runs saved by an earlier launch are cleared at launch and re-detected.

**Research (M3.2, 2026-09-27).** Checked against docs, source and local installs (Claude Code 2.1.283, Codex 0.157.1, OpenCode 2.0.18 beta, pi 0.87.1; omp from its repo only). None of these interfaces is a stable public contract, so every use degrades quietly.

| Agent | Detection | Transcripts | Status source |
|---|---|---|---|
| Claude Code | argv[0] `claude`. The native binary's kernel name is its version file (e.g. `2.1.283`), so match argv, not `p_comm`. Skip the helpers `claude daemon`, `bg-pty-host`, `bg-spare` | `~/.claude/projects/<start folder, non-alphanumerics → ->/<session>.jsonl`: the folder where the session *started*, so use the hook's `transcript_path`. `user`/`assistant` records; titles in `ai-title`/`custom-title`; todos via `TaskCreate`/`TaskUpdate` with state in `~/.claude/tasks/<session>/` | Hooks (stdin JSON: `session_id`, `transcript_path`, `cwd`, `hook_event_name`): `UserPromptSubmit`, `PreToolUse` → working; `PermissionRequest` (immediate), `Notification` `permission_prompt`/`elicitation_dialog` (after ~6 s idle) → needs you; `Stop` (`last_assistant_message`) → done; `StopFailure` (`error`) → failed. An Esc interrupt fires no `Stop`. Hooks block unless `"async": true`. **Install:** a plugin loaded with `CLAUDE_CODE_PLUGIN_DIRS` set only in Calm's shells (v2.1.280+) writes no settings; `claude plugin marketplace add` + `install` also works but writes `~/.claude/settings.json`. Without hooks: desktop notifications (OSC 9/777) and OSC 9;4 progress in Ghostty-based terminals, and the window title |
| Codex | native `codex`; the npm package runs `node …/@openai/codex/bin/codex.js`, which spawns `codex` | `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`: `event_msg` `task_started`/`task_complete` (`last_agent_message`)/`turn_aborted`; plan via `update_plan`. Titles in a versioned SQLite file (fragile) | Hooks (`~/.codex/hooks.json`, `[hooks]` in `config.toml`, or a plugin): `UserPromptSubmit` → working, `PermissionRequest` → needs you, `Stop` → done; no turn-failed event. **Every hook must be approved by the user in `/hooks`.** Legacy `notify` only reports turn complete. Without hooks: OSC 9 (or BEL) for approval requests and finished turns while the pane is unfocused |
| OpenCode | native `opencode`; npm `opencode-ai` is a node wrapper. v2 may run the agent loop in a shared `opencode serve` process | SQLite `~/.local/share/opencode/opencode.db` (`session`, `message`, `part`, `todo`) | A plugin file in `~/.config/opencode/plugins/`: `session.status` busy → working, idle → done; `permission.asked`/`question.asked` → needs you; `session.error` → failed. `event` handlers don't block. Its own OSC notifications are off by default |
| pi | `pi` (node sets `process.title`; Bun builds are named `pi`); package `@earendil-works/pi-coding-agent` | `~/.pi/agent/sessions/--<folder>--/<ts>_<uuid>.jsonl` (`type: "message"`) | Extensions in `~/.pi/agent/extensions/*.ts`, **awaited in order** (Calm's must return at once): `agent_start` → working, `agent_settled` → done, `turn_end.outcome` error → failed. No permission prompts in pi itself |
| omp | `omp` binary, or bun running it | `~/.omp/agent/sessions/<folder>/<ts>_<id>.jsonl`; `~/.omp/agent/terminal-sessions/<tty>` maps a terminal to its session file | Sends its own OSC 9 notifications in Ghostty ("Complete", "Waiting for input", "Stopped with error"). Extensions as in pi (`tool_approval_requested` → needs you; approvals are off by default) |

**Claude Code hooks (as built, M3.4).** At each launch Calm writes a plugin (`.claude-plugin/plugin.json`, `hooks/hooks.json`) to `~/Library/Application Support/Calm/agents/claude-code` and adds that folder to `CLAUDE_CODE_PLUGIN_DIRS` (keeping the user's own entries) in the shells it starts. Claude loads it as `calm@inline` in those sessions only; nothing is written to `~/.claude`. Every hook runs `[ -n "$CALM_CLI" ] && "$CALM_CLI" hook claude-code || true`, synchronously so reports keep their order (`calm hook` gives up on the socket after 1 s). `calm hook` reads the payload on stdin; `ClaudeCodeAdapter.hookReport` maps it (UserPromptSubmit/PreToolUse/PostToolUse → working, PermissionRequest → needs you with "Allow Bash: …", Notification permission/elicitation → needs you, Stop → done with a one-line recap of `last_assistant_message`, StopFailure → failed) and passes on the agent's session id and transcript path for transcript tails. Opt out with `claude-code-hooks = false` under `[agents]`. Known gap: an Esc interrupt fires no `Stop`, so the card stays *working* until the next prompt (M3.7 can read the interruption from the transcript). Fixtures are built from the documented payload fields and should be replaced with captured payloads while dogfooding.

**What this means for Calm.** Terminal signals alone already cover Claude Code, Codex and omp (M3.5), with no setup. Hooks add precision (immediate *needs you*, exact messages): Claude Code's plugin can be enabled inside Calm without writing anyone's config; Codex, OpenCode and pi need files in their config folders and the user's consent (and, for Codex, approval in `/hooks`).

Open questions: whether `AskUserQuestion`/`ExitPlanMode` fire `PermissionRequest` in Claude Code's interactive mode; which hook, if any, follows a rejected permission; whether Codex's `notify` blocks; how OpenCode v2's TUI attaches to its shared service.

Transcript formats are undocumented and change between versions. Each adapter ships fixture files from real sessions and tests against them; a parse failure degrades to "no transcript", never a crash.

## Attention

**State reporting.** Every shell Calm starts gets `CALM_SESSION_ID`, `CALM_SOCKET` and `CALM_CLI` (the bundled `calm`) in its environment. Agent hooks call `"$CALM_CLI" status <state> [message]`, which sends `{session, state, message}` over the socket. States are `working`, `needs-you`, `done`, `failed` and `idle`, with a few synonyms (`waiting`, `error`, `stop`…) so hook scripts can use their agent's words. Hooks run on every turn and in every terminal, so `status` and `notify` are silent no-ops that exit 0 outside a Calm session or when Calm isn't running (they never launch it), and the socket gives up after 2 seconds (`scripts/cli-hook-check.sh` checks this). Setting up hooks for each agent is offered once, with the user's consent, and written to the agent's own config.

**Fallback signals** when no hook is installed come from libghostty's actions, translated in `Terminal` into `TerminalSignal` and read by one pure function (`TerminalSignal.outcome`), with source `terminal` so hooks still win:

| Signal | In an agent session | In a plain shell |
|---|---|---|
| OSC 9;4 progress set / indeterminate | working | working |
| progress removed | done (if it was working) | idle (if it was working) |
| progress error | failed | failed |
| OSC 9 / 777 notification | read by its words: permission, approval, allow, confirm, question → *needs you*; error, failed → failed; "waiting for (your) input" and anything else → done. Only an explicit ask can notify | passed on as a notification (at the next pause, if you're elsewhere) |
| bell | *needs you*, only if the agent was working | ignored |
| command finished (OSC 133) | ignored (the agent run ends when it exits) | done or failed, if it ran 10 s or longer |

Window titles aren't used: agents' title formats vary and change. Calm never plays the system beep for a bell (Ghostty's default is silent too).

**State machine.** Per session: `idle → working → (needsYou | done | failed) → idle` (on visit). Reports are idempotent; the latest report wins, except that terminal guesses never override a hook report from the same agent run (the run ends when the agent exits). Each session keeps its last `StatusReport` (state, message, source, time) for cards and the arrival card. Applying a report returns an effect: *notify* only for a new *needs you* in a session the user isn't looking at, *withdraw* when a session leaves *needs you*. A session the user is looking at doesn't collect *done* or *failed*.

**Notification scheduling.**

- Only `needsYou` in an unfocused session produces a notification (configurable).
- A **breakpoint detector** watches keystrokes and focus changes. A notification is delivered when the user has not typed for a short interval, switches focus, or after a maximum wait. It is never dropped.
- Delivered notifications are removed when the session is visited.
- As built (M3.9): `AttentionQueue` (CalmModel, unit-tested) holds one notification per session; a pause is 3 s without typing (a local key monitor, so only typing in Calm counts), any focus change (session or app), or 60 s at most. `AttentionCenter` delivers through `UNUserNotificationCenter` with no sound, one identifier per session (a newer message replaces the older; visiting removes it), and skips a notification if the user is looking at the session by then. macOS asks for permission the first time one is delivered. Clicking focuses the session. Self-tests set `CALM_NO_NOTIFICATIONS=1` and only log.

## Search

- **Engine:** SQLite FTS5 with `bm25()` ranking, in `~/Library/Application Support/Calm/index.sqlite`.
- **Tokenizer — Decision:** `trigram` handles Chinese and partial words but makes the index larger and can't match one- or two-character queries; `unicode61` is smaller but cannot segment Chinese. Benchmark both on real transcripts before choosing; a hybrid of two tables is possible.
- **Indexed content:** user and agent messages only; tool calls, tool output and file dumps are skipped.
- **Incremental indexing:** FSEvents watches the agents' transcript folders; each file's byte offset is stored so only new lines are parsed.
- **Schema sketch:**

```sql
CREATE TABLE sessions (id TEXT PRIMARY KEY, agent TEXT, project TEXT,
                       title TEXT, transcript TEXT, last_active INTEGER);
CREATE VIRTUAL TABLE messages USING fts5(session_id UNINDEXED, role UNINDEXED,
                       text, tokenize = 'trigram');
CREATE TABLE file_offsets (path TEXT PRIMARY KEY, offset INTEGER, mtime INTEGER);
```

- **Ranking:** `bm25()` score, then boosts for title matches, recency and the current project.

## Persistence

- **Decided (M2.7): zmx** ([zmx.sh](https://zmx.sh), MIT, actively maintained), pinned in `scripts/zmx.sh` (version and SHA-256) and bundled at `Contents/Resources/bin/zmx`.
- Each session's terminal command is `/usr/bin/env -u ZMX_SESSION <zmx> attach calm-<12 hex>`: attaching creates the zmx session on first use and reattaches, with scrollback, after a relaunch. zmx starts the account's login shell.
  - `env -u ZMX_SESSION`: inside a zmx session that variable makes `attach` switch the *calling* terminal instead of starting a client, which would hijack the terminal Calm was launched from.
  - `ZMX_DIR=$TMPDIR/calm-zmx` (mode 700) keeps Calm's sessions apart from any other zmx use; names stay short because each session is a Unix socket there. `ZMX_NO_DETACH_KEY=1` leaves Ctrl-\\ to programs.
- Quitting detaches; closing a session runs `zmx kill <name> --force`. At launch, `calm-*` sessions in Calm's directory that no saved session refers to are killed.
- **Shell integration inside zmx.** libghostty injects Ghostty's shell integration only when the command it runs is a shell, and here it runs zmx. `ShellIntegration` sets the same variables Ghostty would (zsh: `ZDOTDIR` pointing at the bundled integration, keeping the user's in `GHOSTTY_ZSH_ZDOTDIR`; fish and elvish: the integration prepended to `XDG_DATA_DIRS`), and zmx hands them to the shell it starts. `shell-integration = none` in the Ghostty config turns this off. Bash and nushell need their command lines rewritten, so they rely on the process-based folder lookup.
- If zmx is missing or fails, sessions fall back to plain shells for the rest of the run (`CALM_NO_PERSISTENCE=1` forces this).
- App state (projects, sessions, layouts) lives in `~/Library/Application Support/Calm/state.json`: a versioned envelope, written atomically and debounced. A file Calm can't read, or one from a newer Calm, is moved aside as `state.unreadable-<time>.json` instead of being overwritten. The window frame is kept by AppKit's autosave.

## Smart links and Copy Cell

- **Links:** libghostty detects URLs and paths. Calm resolves relative paths against the session's working directory, parses `:line[:column]`, and routes to the viewer or the editor (`code -g`, `cursor -g`, `zed`, `xed -l` and so on).
- **Copy Cell:** read the grid text around the click with libghostty's text API, scan left and right for the nearest vertical border characters and up and down for horizontal border rows, then join the cell's lines and trim padding. Pure function over a text grid, so it is unit-tested with fixtures of real agent tables.

## Files and viewer

- File tree from the project folder, filtered by `git check-ignore`, changed files from `git status --porcelain`.
- **Decision — viewer rendering:** native (Apple's swift-markdown to AttributedString, a syntax highlighter for code) or a single WKWebView with a bundled renderer. Native feels better; a web view is faster to build and handles Markdown edge cases.

## Themes

A theme is a small TOML file:

```toml
[meta]
name = "Teerb Soft"
mode = "dark"

[terminal]
theme = "Teerb"            # any Ghostty theme name, or inline colors

[chrome]
sidebar = "#222222"
accent = "#8a9a8a"
radius = 8
material = "solid"        # or "glass"
layout = "edge"           # or "card"
```

Built-in themes are bundled; user themes live in `~/.config/calm/themes/`.

## Motion in the window

- The window's content view is layer-backed, so fades and slides run on Core Animation. Without layers AppKit falls back to timer-driven animation, which never ran when started outside event handling (for example from `calm open`), leaving a new session's workspace at alpha 0. The layout fade is a presentation-only `CABasicAnimation`: the view's own alpha stays 1, so a skipped animation can't leave a session invisible. Overlays (the switcher, the peeking sidebar) are removed on a timer rather than in an animation completion handler, so one can never linger invisibly over the terminal and take clicks.
- `Motion` is the one switch: no animation when the system's Reduce Motion is on or `motion` is `reduced`/`off` in `config.toml`.
- **Session switcher:** a local event monitor sees ⌃Tab before the terminal does and consumes it (and Esc, Return and the arrows while the switcher is open), so Ghostty's own ⌃Tab binding never fires. The switcher shows only after ~160 ms of holding ⌃, like ⌘Tab. Previews are `cacheDisplay` snapshots of each session's pane, refreshed every 250 ms; panes in hidden layouts are un-occluded while the switcher is open so their previews stay live, and occluded again when it closes. Recent order is kept in memory, not saved.
- **Sidebar peek:** a 6 pt sensor at the left edge (tracking area only, it never takes clicks) slides a second sidebar view in over the terminal; it slides away 350 ms after the pointer leaves it.

## Motion in the terminal

- **Cursor glide:** `Calm/Resources/Shaders/cursor_glide.glsl`, a Ghostty custom shader using the `iCurrentCursor`/`iPreviousCursor`/`iTimeCursorChange` uniforms. `CalmDefaults` writes `~/Library/Application Support/Calm/defaults.ghostty` on each launch with `custom-shader` and `custom-shader-animation = true`, and loads it **before** the user's Ghostty config, so the user's settings win. It is skipped when Reduce Motion is on. Cost: while a custom shader is active, the focused pane runs an animation loop (Ghostty's docs estimate under 10% CPU).
- **Smooth scrolling:** not possible with upstream Ghostty today. The renderer only draws whole rows; sub-row offsets need an engine change. **Decision (later):** propose it upstream, or carry a small patch in `scripts/ghosttykit.sh`. Until then Calm scrolls like Ghostty.

## Configuration

- One file: `~/.config/calm/config.toml`. The settings screen reads and writes it. Until then it holds `auto-grouping` and `motion`; `CalmSettings` reads the flat subset of TOML Calm needs (`key = value`, comments, `[sections]` flattened to `section.key`) and reports malformed lines instead of failing.
- Ghostty options continue to come from the user's Ghostty config, then `~/.config/calm/terminal.ghostty` for Calm-only overrides.
- Unknown keys are preserved when the settings screen writes the file.

## Control protocol

- Unix socket at `~/Library/Application Support/Calm/calm.sock`, newline-delimited JSON requests and responses.
- Commands: `open`, `search`, `status`, `notify`, `list`. Versioned with a `v` field.
- As built (M2.9): one request per connection, `{"v":1,"cmd":"open","path":…}` → `{"ok":true}` or `{"ok":false,"error":…}`; `list` returns `sessions` with id, title, project, folder and state. The socket is mode 600 and `CALM_SOCKET` overrides its path. `open` and `list` work; `status` and `notify` answer "not available yet" until M3.
- The CLI is a small separate target installed into the app bundle and linkable onto `PATH`.

## Testing

- **Unit:** Model, auto-grouping, attention state machine, Copy Cell parsing, search ranking, transcript parsers with fixtures.
- **Integration:** control socket round trips, indexer on fixture folders.
- **UI:** a few smoke tests; no pixel tests.
- Swift Testing throughout; `mise run test` runs everything.

## Licensing and references

- Calm is licensed under **Apache-2.0** (`LICENSE`, `NOTICE`).
- Ghostty (MIT) may be studied and small parts adapted, with attribution in the file header and in `NOTICE`. Ghostty's license notice ships with the app because Calm embeds libghostty.
- Other projects are for ideas only; no code is copied from them.

## Distribution

- Early: local builds only.
- Later: Developer ID signing, notarization, Sparkle updates, a Homebrew cask.
