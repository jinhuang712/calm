# Roadmap

Phases are ordered so that Calm is usable early and every phase adds to a working app. Feature IDs refer to [FEATURES.md](FEATURES.md).

Status: ⬜ not started · 🟨 in progress · ✅ done

## Phase 0 — Foundations ⬜

- Repository, build setup (XcodeGen + mise), formatting, linting, tests, CI.
- GhosttyKit built from upstream Ghostty at a pinned commit, integrated and linking.
- Settle the minimum macOS version ([DESIGNS.md](DESIGNS.md)).

**Done when:** an empty app builds, launches and passes CI.

## Phase 1 — A plain terminal (F1) ⬜

- One window, tabs and splits running real shells through libghostty.
- Ghostty config, keyboard input, IME (Chinese input), clipboard, selection, links to URLs, resize, scrollback.
- Command palette.

**Done when:** the author can use Calm as a plain terminal for a full day without hitting a blocker.

## Phase 2 — Sessions and projects (F2, F3) ⬜

- The Project → Session → Pane model.
- Sidebar with projects and sessions; auto-grouping by folder with animated moves.
- Sessions survive quitting; layouts restored.

**Done when:** quitting and relaunching restores everything, and sessions file themselves under the right project.

## Phase 3 — Attention (F4, F5, F6, F13 status) ⬜

- Agent detection for Claude Code, Codex, OpenCode, pi and omp.
- `calm status` over the control socket; hook setup for each agent.
- Session states in the sidebar; *needs you* notifications at natural pauses.
- Arrival card.

**Done when:** the author no longer clicks through tabs to find which agent is waiting.

## Phase 4 — Recall (F7) ⬜

- Transcript indexer (command-line first: `calm search`), then ⌘K in the app.
- Tokenizer benchmark on real transcripts, Chinese included.

**Done when:** "which session talked about X?" is answered with one search.

## Phase 5 — Reading (F8, F9, F10) ⬜

- Smart links with relative paths and line numbers.
- Copy Cell.
- Files column and full-area read-only viewer (esc returns to the session).

**Done when:** copying a cell, opening a path at a line and previewing a file each take one action.

## Phase 6 — Look and feel (F11, F14) ⬜

- Whole-window themes with a curated soft set and the picker.
- The five-section settings screen.

**Done when:** a new user can make Calm look right in under a minute without editing files.

## Phase 7 — Session actions (F12) ⬜

- Rename, resume and fork for agents that support them.

**Done when:** resuming or forking a conversation is one right-click.

## Later

- Spotlight integration (semantic index on macOS 27+).
- Scrollback search across open sessions, paste history.
- Signing, notarization, Sparkle updates, Homebrew cask, public release.

## Not planned

See [GOALS.md](GOALS.md#non-goals).
