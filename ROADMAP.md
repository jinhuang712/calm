# Roadmap

Calm is built in milestones. Each one ends in a working app that is better than the last, so it can be used every day from Milestone 1 on. Feature IDs (F1…F14) refer to [FEATURES.md](FEATURES.md).

**Current milestone:** M4 — Recall. M1 and M3 are built and wait only on the author's real use (M1.12's dogfooding day; M3's week of work with agents).

## How to read this

- A **milestone** is a usable state of the app, with exit criteria that decide when it is done.
- A **task** is one reviewable piece of work, usually one branch and one pull request. Task IDs (`M2.4`) are used in branch names and commit messages.
- **Decision** tasks settle an open question in [DESIGNS.md](DESIGNS.md) and record the outcome there.
- Check a task off when it is merged. Update the milestone status and "Current milestone" when the exit criteria are met.

Status: ⬜ not started · 🟨 in progress · ✅ done

## Overview

| Milestone | Delivers | Features | Depends on | Status |
|---|---|---|---|---|
| **M0** Foundations | an empty app that builds, launches and passes CI | — | — | ✅ |
| **M1** A plain terminal | tabs, splits and shells good enough for daily use | F1 | M0 | 🟨 |
| **M2** Sessions and projects | the session model, sidebar, auto-grouping, sessions that survive quitting | F2, F3 | M1 | ✅ |
| **M3** Attention | agent detection, session cards, status, calm notifications, arrival card | F4, F5, F6, F13 | M2 | 🟨 |
| **M4** Recall | search across every agent's history | F7 | M2 | 🟨 |
| **M5** Reading | smart links, Copy Cell, files column and viewer | F8, F9, F10 | M1 (M5.3+ need M2) | 🟨 |
| **M6** Look and feel | whole-window themes, picker, settings screen, accessibility pass | F11, F14 | M3 | 🟨 |
| **M7** Session actions | rename, resume, fork | F12 | M3, M4 | ⬜ |

M4 and M5 can run in parallel with M3 once M2 is done.

---

## M0 — Foundations ✅

An empty Calm app, built from a clean clone with one command, with GhosttyKit built from upstream Ghostty.

- [x] **M0.1 Decision:** minimum macOS version (proposed: macOS 26).
- [x] **M0.2 Toolchain:** `mise.toml` pinning Zig (the version Ghostty requires), XcodeGen, swiftformat, swiftlint and xcbeautify; `mise run setup` installs everything.
- [x] **M0.3 Ghostty source:** pin an upstream `ghostty-org/ghostty` commit and fetch it into `vendor/ghostty` (git-ignored).
- [x] **M0.4 GhosttyKit build:** `scripts/build-ghosttykit.sh` builds `GhosttyKit.xcframework` from the pinned commit, cached by commit hash so rebuilds are skipped.
- [x] **M0.5 Project layout:** XcodeGen `project.yml` with the app target, the `calm` CLI target, and a local Swift package for the UI-free modules (starting with `Model`), each with a test target.
- [x] **M0.6 App skeleton:** an empty window that launches; bundle ID `com.jinhuang.calm`; placeholder icon.
- [x] **M0.7 Engine smoke test:** the app initializes libghostty at launch, and a test proves GhosttyKit links.
- [x] **M0.8 Quality tools:** swiftformat and swiftlint configs; `mise run build`, `test`, `lint` and `format`.
- [x] **M0.9 CI:** a GitHub Actions workflow on a macOS runner (setup, cached GhosttyKit build, build, test, lint). Needs the GitHub repository.
- [x] **M0.10 Docs:** AGENTS.md commands confirmed; DESIGNS.md updated with the final project layout.

**Exit criteria**
- `mise run setup && mise run build` on a clean clone produces an app that launches.
- CI passes on `main`.

---

## M1 — A plain terminal (F1) 🟨

Calm works as a normal terminal: no sessions or agents yet, just a fast, correct terminal.

- [x] **M1.1 Engine wrapper:** the `Terminal` module owns libghostty's app object, loads the user's Ghostty config, and drives its event loop.
- [x] **M1.2 Terminal view:** a view that renders one surface running the user's shell.
- [x] **M1.3 Keyboard:** all keys and modifiers, IME (Chinese input included), Option-as-Alt from the Ghostty config.
- [x] **M1.4 Mouse:** selection, ⌥-drag rectangle selection, scrolling, mouse reporting to TUIs.
- [x] **M1.5 Clipboard:** copy, paste, OSC 52.
- [x] **M1.6 Window behavior:** resize, scrollback, font size changes, focus, full screen.
- [x] **M1.7 URLs:** ⌘-click opens URLs in the default browser (file paths come in M5).
- [x] **M1.8 Tabs and splits:** new tab, split right and down, move focus between panes, close, resize dividers; panes grow in and fold away.
- [x] **M1.9 Command palette:** ⌘P lists every action with its shortcut.
- [x] **M1.13 Terminal motion:** cursor glide and trail (one soft shader). Smooth scrolling is blocked on an engine change; see DESIGNS.md → Motion in the terminal.
- [x] **M1.10 Shortcut audit:** check Calm's shortcuts against Ghostty's defaults and common agent keys (⌘K in particular); update UIUX.md.
- [ ] **M1.11 Quick terminal:** a drop-down terminal on a global hotkey. *Moved to Later: not needed for daily agent work.*
- [ ] **M1.12 Dogfood:** use Calm as the only terminal for a full day and fix the blockers found. *Needs the author; automated self-tests pass (shell, key events, selection and copy, splits, tabs, palette, vim, resize, Chinese text).*

**Exit criteria**
- A full working day in Calm with Claude Code, an editor such as vim, `htop` and Chinese input, with no blocker.

---

## M2 — Sessions and projects (F2, F3) ✅

The core model arrives: sessions grouped under projects, restored after quitting.

- [x] **M2.1 Model:** `Project`, `Session`, `Pane` and layout tree in the `Model` module, fully unit-tested.
- [x] **M2.2 State store:** save and restore projects, sessions and layouts in `state.json` (JSON was enough; SQLite stays for the search index). The window frame uses AppKit's autosave.
- [x] **M2.3 Working directory:** track each session's folder through OSC 7, with a process-based fallback.
- [x] **M2.4 Auto-grouping:** longest-prefix project match, git-root fallback, automatic projects, pinned sessions; unit-tested.
- [x] **M2.5 Sidebar:** projects with compact session rows, collapse with summary, New Project, drop a folder to add a project. (Rich cards arrive in M3.)
- [x] **M2.6 Motion:** cards slide between projects, the hidden sidebar peeks in at the edge, session switching shows live previews; respects Reduce Motion.
- [x] **M2.7 Decision:** session persistence — reuse zmx or write a minimal PTY holder (check license and maintenance first). **Decided: zmx 0.8.1** (MIT), bundled; see DESIGNS.md → Persistence.
- [x] **M2.8 Persistence:** quitting detaches shells; launching reattaches with scrollback and running processes.
- [x] **M2.9 Control socket and CLI:** the `calm` CLI with `open` and `list` over the local socket.
- [x] **M2.10 Config:** `~/.config/calm/config.toml` with the auto-grouping setting.

**Exit criteria**
- Quit and relaunch restores every project, session and layout, with shells still running.
- A shell that `cd`s into another project moves there on its own.

---

## M3 — Attention (F4, F5, F6, F13) 🟨

Calm knows what every agent is doing and interrupts only when one needs you.

- [x] **M3.1 Agent detection:** the adapter protocol and foreground-process detection for Claude Code, Codex, OpenCode, pi and omp.
- [x] **M3.2 Research:** how Codex reports approvals, OpenCode plugin events, pi and omp extension APIs, and where omp stores transcripts. Record findings in DESIGNS.md.
- [x] **M3.3 Status contract:** inject `CALM_SESSION_ID` and `CALM_SOCKET` into every shell; `calm status <state> [message]` and `calm notify`.
- [ ] **M3.4 Hook setup:** per-agent hook installers that write each agent's own config, with consent and an undo. *Claude Code: a plugin loaded through `CLAUDE_CODE_PLUGIN_DIRS`, nothing written to its config. pi: an extension added from the Agents panel, with consent and Disconnect. Codex and omp: their own notifications (hooks would need Codex's /hooks approval; later). OpenCode: a hint until its shared service can be tied to a terminal.*
- [x] **M3.5 Fallback signals:** bell, OSC 9;4 progress, OSC 9/777 notifications, command-finished events and window titles. *Titles left out: their formats vary between agents and versions.*
- [x] **M3.6 State machine:** idle, working, needs you, done, failed; unit-tested.
- [x] **M3.7 Transcript tails:** read the latest message, current step and todo progress from transcripts (Claude Code first). *Claude Code done, including the agent's own title and Esc interruptions; Codex, OpenCode, pi and omp readers follow the same `TranscriptReading` protocol.*
- [x] **M3.8 Session cards:** name, state and step, progress bar, two-line recap, worktree and diff size; plain shells stay compact. *Built: the agent's own title, time, state mark, label and current step, todo progress bar, two-line recap (what it asked while it needs you, else its latest message), worktree name, compact plain shells, needs-you tint. Diff size comes with the files column (M5).*
- [x] **M3.9 Notifications:** breakpoint detection, a macOS notification for *needs you* only, click to focus, ⌘⇧A to jump to the next waiting session, never dropped.
- [x] **M3.10 Arrival card:** shown when switching into an agent session; fades on typing; ⌘⇧I recalls it.
- [x] **M3.11 First run:** design and build the screen that offers hook setup for each installed agent.
- [x] **M3.12 Agents settings:** which states notify, sound on or off.

**Exit criteria**
- For a week of normal work, the author never clicks through tabs to find which agent is waiting.
- No *needs you* is missed.

*Status: every task is built and self-tested headless (stand-in agents emitting real hook payloads and escape sequences). Left: Codex hooks (need Codex's /hooks approval; its own notifications already work), diff size on cards (with the files column, M5), and the week of real use.*

---

## M4 — Recall (F7) 🟨

Any past conversation, across every agent, is one search away.

- [x] **M4.1 Transcript parsers:** one per agent, tested against fixture files from real sessions; failures degrade quietly.
- [x] **M4.2 Decision:** search tokenizer — benchmark `trigram` and `unicode61` on real transcripts, Chinese included.
- [x] **M4.3 Indexer:** the FTS5 schema in `index.sqlite`, incremental indexing with file watching and stored offsets; user and agent messages only.
- [x] **M4.4 Ranking:** BM25 plus boosts for title matches, recency and the current project; unit-tested.
- [x] **M4.5 CLI:** `calm search <text>`.
- [x] **M4.6 Search panel:** ⌘K, live results, jump to an open session or resume a closed one.
- [x] **M4.7 Performance:** measure query time and index size on the author's full history, and set targets from the results.

**Exit criteria**
- "Which session talked about X?" is answered with one search, most of the time.

*Status: built and self-tested headless against fixture transcripts; measured on the author's real history (M4.7). Left: the author's real use to confirm the exit criterion, and OpenCode's SQLite history (not indexed yet).*

---

## M5 — Reading (F8, F9, F10) 🟨

Agent output is easy to act on.

- [x] **M5.1 Smart links:** relative paths resolved against the session's folder, `path:line[:column]`, editor detection and opening at the line.
- [x] **M5.2 Copy Cell:** find the cell's borders in the text grid, join wrapped lines, trim padding; fixture tests from real agent tables; ⌥-double-click and right-click menu.
- [x] **M5.3 Files column:** the project's tree right of the sidebar, git-ignore filtering, change markers, ⌘⇧E, follows the focused session. *Built: git listing off the main thread (or a bounded walk outside git), M/A/D/R/U markers and dots on changed folders, branch and change count in the header, 5 s refresh while shown, click opens the viewer with the viewed file highlighted. The sidebar and the column now slide without resizing the terminal on every frame.*
- [x] **M5.4 Decision:** viewer rendering — native or a web view.
- [x] **M5.5 Viewer:** Markdown, HTML, PDF, images and code cover the main area; esc returns to the session; Open in editor.
- [x] **M5.6 CLI:** `calm open <file>`.

**Exit criteria**
- Copying a table cell, opening a path at a line and viewing a file each take one action.

*Status: every task is built and self-tested headless. Left: the author's real use to confirm the exit criterion, changed-file diffs in the viewer (FEATURES.md → Later) and diff size on session cards (M3.8).*

---

## M6 — Look and feel (F11, F14) 🟨

Calm looks right out of the box, and making it yours takes a minute.

- [x] **M6.1 Theme format:** the theme file and loader; a curated set of about twelve soft themes in light and dark pairs. *Built: six families in light and dark, generated and contrast-checked; the default gives way to the user's Ghostty theme, a picked one (`theme` in config.toml) wins and follows the appearance.*
- [x] **M6.2 Themed chrome:** sidebar, cards, files column and viewer take their colors from the theme. *Built: the theme's sidebar, text, accent and red when its background is on screen; derived from the terminal otherwise.*
- [x] **M6.3 Theme picker:** live previews; one click applies; follows the system appearance. *Built: Settings (⌘,) → Theme, a grid of previews in the current appearance, plus a Ghostty choice when the user's Ghostty config has its own colors.*
- [x] **M6.4 Window options:** glass or solid background; card or edge-to-edge layout; the motion setting (full, reduced, off); adaptive background. *Built: Settings → Appearance → Window, applied live; the adaptive background (an app's OSC 11) now eases the sidebar into its colors. Glass is self-tested for layering only: the window server's blur doesn't show in headless snapshots.*
- [ ] **M6.5 Settings screen:** Appearance, General, Agents, Keys and Advanced; writes `config.toml` and keeps unknown keys.
- [ ] **M6.6 Accessibility:** VoiceOver labels, states shown by shape as well as color, Reduce Motion, Increase Contrast.

**Exit criteria**
- A new user can make Calm look right in under a minute without editing files.
- The settings screen fits the budget in PHILOSOPHY.md.

---

## M7 — Session actions (F12) ⬜

Conversations can be renamed, resumed and forked.

- [ ] **M7.1 Rename:** rename any session.
- [ ] **M7.2 Resume:** resume a closed agent session in its project folder, using each agent's own command.
- [ ] **M7.3 Fork:** fork a conversation into a new split or tab, for agents that support it.
- [ ] **M7.4 Menus:** right-click actions on session cards.

**Exit criteria**
- Resuming or forking a conversation is one right-click.

---

## In every milestone

- Keep FEATURES.md, DESIGNS.md and UIUX.md true in the same change as the code.
- Update the design canvas before a milestone with new screens (M2, M3, M5, M6).
- New logic comes with tests; the app is dogfooded daily from M1 on.

## Later

- Quick terminal (drop-down on a global hotkey), moved from M1.11.
- Release: Developer ID signing, notarization, Sparkle updates, a Homebrew cask, public launch.
- Changed-file diffs in the viewer.
- Spotlight integration (semantic index on macOS 27+).
- Scrollback search across open sessions; paste history.

## Not planned

See [GOALS.md](GOALS.md#non-goals).
