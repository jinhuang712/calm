# Designs

Technical design of Calm Terminal. What the features do is in [FEATURES.md](FEATURES.md); this document covers how. Items marked **Decision** are open and should be settled before the phase that needs them.

## Tech stack

| Layer | Choice |
|---|---|
| Language | Swift 6, strict concurrency checking on |
| UI | SwiftUI for chrome (sidebar, panels, settings, search); AppKit for windows and the terminal view |
| Terminal engine | libghostty, used through the GhosttyKit framework |
| Storage | SQLite (app state, search index with FTS5) |
| Build | XcodeGen (`project.yml`) + `mise` tasks |
| Quality | swiftformat, swiftlint, Swift Testing |
| Minimum OS | macOS 26 (**Decision:** confirm; it keeps the codebase free of old-version branches) |

**GhosttyKit source:** built from upstream Ghostty (`ghostty-org/ghostty`) at a pinned commit, with the Zig version Ghostty requires (0.16 at the time of writing), locally and in CI. No third-party forks or prebuilt binaries.

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

## Auto-grouping

1. The shell reports its working directory (OSC 7 through libghostty's pwd action); a process-based lookup is the fallback.
2. On change, find the project whose `path` is the longest prefix of the directory.
3. If none, find the git repository root and create an automatic project for it, or use the folder itself.
4. Move the session unless it is pinned. Moves are animated in the sidebar.

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

- Shells run under a small session daemon so they survive app quit; the app reattaches on launch.
- **Decision:** reuse an existing session-persistence tool (for example zmx) or write a minimal PTY holder. Check the tool's license and maintenance before depending on it.
- App state (projects, sessions, layouts, window frames) lives in `~/Library/Application Support/Calm/state.sqlite`.

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

## Configuration

- One file: `~/.config/calm/config.toml`. The settings screen reads and writes it.
- Ghostty options continue to come from the user's Ghostty config.
- Unknown keys are preserved when the settings screen writes the file.

## Control protocol

- Unix socket at `~/Library/Application Support/Calm/calm.sock`, newline-delimited JSON requests and responses.
- Commands: `open`, `search`, `status`, `notify`, `list`. Versioned with a `v` field.
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
