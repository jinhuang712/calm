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
Packages/CalmKit/        UI-free Swift package: CalmModel, later Agents, Attention, Search
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

| Agent | Detection | Transcripts | Status source |
|---|---|---|---|
| Claude Code | foreground process `claude` | `~/.claude/projects/**/*.jsonl` | hooks: prompt submitted → working, notification → needs you, stop → done |
| Codex | `codex` | `~/.codex/sessions/**` | `notify` program on turn complete → done; approval requests: to research |
| OpenCode | `opencode` | `~/.local/share/opencode/storage` | plugin events: to research |
| pi | `pi`, `pi-coding-agent` | `~/.pi/agent/sessions/` | extension API: to research |
| omp | `omp` | to research | to research |

Transcript formats are undocumented and change between versions. Each adapter ships fixture files from real sessions and tests against them; a parse failure degrades to "no transcript", never a crash.

## Attention

**State reporting.** Every shell Calm starts gets `CALM_SESSION_ID` and `CALM_SOCKET` in its environment. Agent hooks call `calm status <state> [message]`, which sends `{session, state, message}` over the socket. Setting up hooks for each agent is offered once, with the user's consent, and written to the agent's own config.

**Fallback signals** when no hook is installed: bell, OSC 9;4 progress, OSC 9/777 desktop notifications and command-finished events from libghostty, plus the agent's window title.

**State machine.** Per session: `idle → working → (needsYou | done | failed) → idle` (on visit). Reports are idempotent; the latest report wins.

**Notification scheduling.**

- Only `needsYou` in an unfocused session produces a notification (configurable).
- A **breakpoint detector** watches keystrokes and focus changes. A notification is delivered when the user has not typed for a short interval, switches focus, or after a maximum wait. It is never dropped.
- Delivered notifications are removed when the session is visited.

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
