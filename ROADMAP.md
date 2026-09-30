# Roadmap

Calm is built in milestones. Each one ends in a working app that is better than the last, so it can be used every day from Milestone 1 on. Feature IDs (F1…F14) refer to [FEATURES.md](FEATURES.md).

**Current milestone:** none open. M0 to M7 are all built, and the author has used Calm as their only terminal since 2026-09-29, which met the exit criteria of M1, M3, M4, M5 and M7 (2026-09-30). What is left: a new user's first minute, and F11's settings against the budget (M6); the author's use of OpenCode's new plugin (M3); and the *Later* list. OpenCode's search, resume and fork are built.

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
| **M1** A plain terminal | tabs, splits and shells good enough for daily use | F1 | M0 | ✅ |
| **M2** Sessions and projects | the session model, sidebar, auto-grouping, sessions that survive quitting | F2, F3 | M1 | ✅ (grouping revised after real use: projects, folders, scratch) |
| **M3** Attention | agent detection, session cards, status, calm notifications, arrival card | F4, F5, F6, F13 | M2 | ✅ |
| **M4** Recall | search across every agent's history | F7 | M2 | ✅ |
| **M5** Reading | smart links, Copy Cell, files column and viewer | F8, F9, F10 | M1 (M5.3+ need M2) | ✅ |
| **M6** Look and feel | whole-window themes, picker, settings screen, accessibility pass | F11, F14 | M3 | 🟨 |
| **M7** Session actions | rename, resume, fork | F12 | M3, M4 | ✅ |

M4 and M5 can run in parallel with M3 once M2 is done.

---

## M0 — Foundations ✅

An empty Calm app, built from a clean clone with one command, with GhosttyKit built from upstream Ghostty and Calm's patches.

- [x] **M0.1 Decision:** minimum macOS version. **Decided: macOS 26**, Apple silicon only.
- [x] **M0.2 Toolchain:** `mise.toml` pinning Zig (the version Ghostty requires), XcodeGen, swiftformat, swiftlint and xcbeautify; `mise run setup` installs everything.
- [x] **M0.3 Ghostty source:** pin an upstream `ghostty-org/ghostty` commit in `scripts/ghostty.env`; it is fetched into `~/Library/Caches/calm/ghostty`.
- [x] **M0.4 GhosttyKit build:** `scripts/ghosttykit.sh` builds `GhosttyKit.xcframework` from the pinned commit with `scripts/ghostty-patches` applied, cached by commit and patch set so rebuilds (and other worktrees) reuse it.
- [x] **M0.5 Project layout:** XcodeGen `project.yml` with the app target, the `calm` CLI target, and a local Swift package (`CalmKit`) for the UI-free modules, each with a test target.
- [x] **M0.6 App skeleton:** an empty window that launches; bundle ID `com.jinhuang.calm`; placeholder icon.
- [x] **M0.7 Engine smoke test:** the app initializes libghostty at launch, and a test proves GhosttyKit links.
- [x] **M0.8 Quality tools:** swiftformat and swiftlint configs; `mise run build`, `test`, `lint` and `format`.
- [x] **M0.9 CI:** a GitHub Actions workflow on a macOS runner (setup, cached GhosttyKit build, build, test, lint). Needs the GitHub repository.
- [x] **M0.10 Docs:** AGENTS.md commands confirmed; DESIGNS.md updated with the final project layout.

**Exit criteria**
- `mise run setup && mise run build` on a clean clone produces an app that launches.
- CI passes on `main`.

---

## M1 — A plain terminal (F1) ✅

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
- [x] **M1.13 Terminal motion:** cursor glide and trail (one soft shader). Smooth scrolling, including programs' scroll regions (Claude Code's streaming view), through a patch to the engine; see DESIGNS.md → Motion in the terminal.
- [x] **M1.10 Shortcut audit:** check Calm's shortcuts against Ghostty's defaults and common agent keys (⌘K in particular); update UIUX.md.
- [x] **M1.12 Dogfood:** use Calm as the only terminal for a full day and fix the blockers found. *Done by the author's real use (2026-09-30): Calm has been their only terminal since 2026-09-29, and the small things found went in as fixes. Automated self-tests pass too (shell, key events, selection and copy, splits, tabs, palette, vim, resize, Chinese text).*

**Exit criteria**
- A full working day in Calm with Claude Code, an editor such as vim, `htop` and Chinese input, with no blocker. *Met (the author, 2026-09-30).*

---

## M2 — Sessions and projects (F2, F3) ✅

The core model arrives: sessions grouped under projects, restored after quitting.

- [x] **M2.1 Model:** `Project`, `Session` and the split layout tree in the `CalmModel` module, fully unit-tested.
- [x] **M2.2 State store:** save and restore projects, sessions and layouts in `state.json` (JSON was enough; SQLite stays for the search index). The windowed frame uses AppKit's autosave; a window left filling the screen, or in full screen, is remembered in `state.json` (AppKit's autosave doesn't record a filled one).
- [x] **M2.3 Working directory:** track each session's folder through OSC 7, with a process-based fallback.
- [x] **M2.4 Auto-grouping:** longest-prefix project match, git-root fallback, automatic projects, pinned sessions; unit-tested. *Revised after real use: projects you make, folder groups by git root or folder, and scratch sessions on top (FEATURES.md → F2).*
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

## M3 — Attention (F4, F5, F6, F13) ✅

Calm knows what every agent is doing and interrupts only when one needs you.

- [x] **M3.1 Agent detection:** the adapter protocol and foreground-process detection for Claude Code, Codex, OpenCode and pi. *omp was supported too, until 2026-09-29: it was removed (little use, and not installed to check against). Saved sessions that mention it still load (DESIGNS.md → Supported agents).*
- [x] **M3.2 Research:** how Codex reports approvals, OpenCode plugin events and pi's extension API, and where each agent stores transcripts. Record findings in DESIGNS.md.
- [x] **M3.3 Status contract:** inject `CALM_SESSION_ID` and `CALM_SOCKET` into every shell; `calm status <state> [message]` and `calm notify`.
- [x] **M3.4 Hook setup:** per-agent hook installers that write each agent's own config, with consent and an undo. *Claude Code: a plugin loaded through `CLAUDE_CODE_PLUGIN_DIRS`, nothing written to its config. pi: an extension added from Settings → Agents, with consent and Disconnect; it names its conversation on every report (`calm status --agent pi --transcript …`), and Calm keeps the file current at launch. OpenCode: a TUI plugin added from Settings → Agents, with consent and Disconnect (2026-09-30): it runs in the terminal's own `opencode`, not the shared service, and names its session on every report (DESIGNS.md → OpenCode plugin). **Codex hooks: decided 2026-09-29 not to build them.** Since Codex 0.157 every session runs in one shared daemon, which runs persistent hooks with its own environment, so a hook can't tell which Calm session it belongs to; its own notifications and Calm's transcript tails already give state, recap and interruption (DESIGNS.md → Codex hooks). Revisit if that daemon changes.*
- [x] **M3.5 Fallback signals:** bell, OSC 9;4 progress, OSC 9/777 notifications, command-finished events and window titles. *Titles left out: their formats vary between agents and versions.*
- [x] **M3.6 State machine:** idle, working, needs you, done, failed; unit-tested.
- [x] **M3.7 Transcript tails:** read the latest message, current step and todo progress from transcripts (Claude Code first). *Claude Code, including the agent's own title and Esc interruptions. The other three agents are M3.7b.*
- [x] **M3.7b Transcript tails for the other agents:** Codex, OpenCode and pi readers on the same `TranscriptReading` protocol. *Built, and read against the author's real history (184 Codex rollouts, 192 pi sessions, 60 OpenCode sessions: none unreadable). What each gives a card: a recap and Esc interruptions; a title for pi and OpenCode (Codex keeps none in its files); no step or progress (no todo record appears in these agents' recent history). Reading runs off the main thread and steps past megabytes of tool output. Finding an agent's transcript without a hook: the file the process has open, else `codex resume <id>`, else the one transcript for its folder written since it started, and none when that is ambiguous. Verified end to end headless with stand-in agents. *Fixed the day it landed, after the author's live Codex showed no recap and never worked:* a terminal `codex` under the shared daemon says `source: "vscode"` in its rollout, so the terminal is told from the desktop app by `originator` (the first rule counted only `cli`); and Codex and OpenCode, which never tell Calm they are working, get **working** and **done** from their transcripts' turn markers (DESIGNS.md → Transcript tails → Turn phase). Checked against the live process, not only history. OpenCode search indexing (M4) and OpenCode resume and fork (M7) are still open.*
- [x] **M3.8 Session cards:** name, state and step, progress bar, two-line recap, worktree name; plain shells stay compact. *Built: the agent's own title, time, state mark, label and current step, todo progress bar, two-line recap (what it asked while it needs you, else its latest message), worktree name, compact plain shells, needs-you tint. A diff size on the card was dropped (2026-09-29): the files column's header already counts the project's lines.*
- [x] **M3.9 Notifications:** breakpoint detection, a macOS notification for *needs you* only, click to focus, ⌘⇧A to jump to the next waiting session, never dropped.
- [x] **M3.10 Arrival card:** shown when switching into an agent session; fades on typing; ⌘⇧I recalls it.
- [x] **M3.11 First run:** design and build the screen that offers hook setup for each installed agent. *Became Settings → Agents, opened from Calm → Agents….*
- [x] **M3.12 Agents settings:** which states notify, sound on or off.

**Exit criteria**
- For a week of normal work, the author never clicks through tabs to find which agent is waiting.
- No *needs you* is missed.

*Status: every task is built and self-tested headless (stand-in agents emitting real hook payloads and escape sequences). Exit criteria met in the author's real use (2026-09-30): no clicking through sessions to find a waiting agent, and no missed *needs you*. It was four days of heavy agent work rather than a week, which the author judged enough. OpenCode's plugin was built afterwards (2026-09-30; checked against a fake context, not yet a real turn).*

---

## M4 — Recall (F7) ✅

Any past conversation, across every agent, is one search away.

- [x] **M4.1 Transcript parsers:** one per agent, tested against fixture files from real sessions; failures degrade quietly.
- [x] **M4.2 Decision:** search tokenizer — benchmark `trigram` and `unicode61` on real transcripts, Chinese included.
- [x] **M4.3 Indexer:** the FTS5 schema in `index.sqlite`, incremental indexing from stored offsets (at launch, every three minutes and when ⌘K opens); user and agent messages only.
- [x] **M4.4 Ranking:** BM25 plus boosts for title matches, recency and the current project; unit-tested.
- [x] **M4.5 CLI:** `calm search <text>`.
- [x] **M4.6 Search panel:** ⌘K, live results, jump to an open session or resume a closed one.
- [x] **M4.7 Performance:** measure query time and index size on the author's full history, and set targets from the results.

**Exit criteria**
- "Which session talked about X?" is answered with one search, most of the time.

*Status: built and self-tested headless against fixture transcripts; measured on the author's real history (M4.7). Exit criterion met in the author's real use (2026-09-30). OpenCode's history is indexed too (2026-09-30): sessions read from its own database by version, not from files by offset (DESIGNS.md → Search → Agents' own databases).*

---

## M5 — Reading (F8, F9, F10) ✅

Agent output is easy to act on.

- [x] **M5.1 Smart links:** relative paths resolved against the session's folder, `path:line[:column]`, editor detection and opening at the line.
- [x] **M5.2 Copy Cell:** find the cell's borders in the text grid, join wrapped lines, trim padding; fixture tests from real agent tables; ⌥-double-click and right-click menu. *Reworked after real use (2026-09-30), and the right-click item removed: hold ⌥ to outline the cell under the pointer, ⌥-click to copy it, also in Claude Code's full-screen view; an ⌥-drag inside a cell selects and copies only that cell's text, across its wrapped lines (the same day, after the author found the drag still ran across whole rows). Tested against Claude Code's own full-screen bytes.*
- [x] **M5.3 Files column:** the project's tree right of the sidebar, git-ignore filtering, change markers, ⌘\\ (first ⌘⇧E), follows the focused session. *Built: git listing off the main thread (or a bounded walk outside git), M/A/D/R/U markers and dots on changed folders, branch and change count in the header, 5 s refresh while shown, click opens the viewer with the viewed file highlighted. The sidebar and the column now slide without resizing the terminal on every frame. Redesigned after real use: a Changes section on top with each file's line counts (and the project's in the header), then the tree, drawn in the sidebar's metrics and aligned with it.*
- [x] **M5.4 Decision:** viewer rendering — native or a web view.
- [x] **M5.5 Viewer:** Markdown, HTML, PDF, images and code cover the main area; esc returns to the session; Open in editor.
- [x] **M5.6 CLI:** `calm open <file>`.
- [x] **M5.7 Link marks and tag:** a faint dotted line under every link that opens, and a tag beside the one under ⌘ (what it is, where, what a click does; thumbnails for images). *Built: libghostty's own link pattern in CalmModel, tested against Ghostty's cases; marks only on still text; soft-wrapped links joined; links a program cut across rows itself (an agent's full-screen view) joined by `HardWrap` for ⌘-click, tag, underline and marks.*

**Exit criteria**
- Copying a table cell, opening a path at a line and viewing a file each take one action.

*Status: every task is built and self-tested headless. Copy Cell failed in Claude Code's full-screen view in the author's real use (2026-09-30: ⌥-double-click copied a whole row, and right-click offers no Copy Cell while a program takes the mouse), and its gesture was reworked the same day (M5.2). Exit criterion met in the author's real use (2026-09-30): ⌥-click and the in-cell ⌥-drag copy the right text in Claude Code's full-screen view, ⌘-click opens a path at its line, and the viewer shows a file. Changed-file diffs in the viewer stay under Later (FEATURES.md → Later).*

---

## M6 — Look and feel (F11, F14) 🟨

Calm looks right out of the box, and making it yours takes a minute.

- [x] **M6.1 Theme format:** the theme file and loader; a curated set of soft themes in light and dark pairs. *Built: five themes (fewer than the twelve first planned, on purpose: each is its own direction) in light and dark, generated and contrast-checked (reworked from six tints of one theme into five directions, with a softer, neutral default); the default gives way to the user's Ghostty theme, a picked one (`theme` in config.toml) wins and follows the appearance. OpenCode, whose own themes ignore the terminal's colors, is asked for a theme in Calm's shells (2026-09-30), unless its config names one: once connected, Calm's own `calm` theme, written from the theme on screen and followed live; else its `system` theme. A connected pi wears a `calm` theme too, set by Calm's extension over pi's built-ins without touching its settings.*
- [x] **M6.2 Themed chrome:** sidebar, cards, files column and viewer take their colors from the theme. *Built: the theme's sidebar, text, accent and red when its background is on screen; derived from the terminal otherwise.*
- [x] **M6.3 Theme picker:** live previews; one click applies; follows the system appearance. *Built: Settings (⌘,) → Appearance, a row of previews in the current appearance under a live miniature of the window, plus a Ghostty choice when the user's Ghostty config has its own colors.*
- [x] **M6.4 Window options:** glass or solid background; card or edge-to-edge layout; the motion setting (full, reduced, off); adaptive background. *Built: Settings → Appearance, applied live; the adaptive background (an app's OSC 11) now eases the sidebar into its colors. Glass is self-tested for layering only: the window server's blur doesn't show in headless snapshots.*
- [x] **M6.5 Settings screen:** Appearance, Agents, General and Shortcuts; writes `config.toml` and keeps unknown keys. *Built as a page that takes the whole window (⌘,, esc back), with a list of sections where the sidebar was, in the theme's colors; it shows config.toml lines it couldn't read and when macOS blocks notifications. It replaced a native toolbar-tab window whose tabs resized it and whose controls wore the system blue. Not in yet: a font and size control (General names the font and opens the Ghostty config), updates and SSH options (neither feature exists yet). New top-level keys no longer land after a blank line.*
- [x] **M6.6 Accessibility:** VoiceOver labels, states shown by shape as well as color, Reduce Motion, Increase Contrast. *Built: Increase Contrast for the chrome and Calm's themes (text to 4.5:1, hierarchy kept), live updates when either setting changes, files column reachable by keyboard and VoiceOver. An interface size (100 to 150%) scales all of Calm's chrome. States already had shapes; cards, rows and the theme picker have labels. Not verified with VoiceOver itself (SwiftUI builds its accessibility tree only when an assistive app connects, which headless runs can't do), and not planned to be.*

- [x] **M6.7 App icon:** Calm's mark in light and dark, and a Dock icon that shows running, done and failed while Calm runs. *Built:*
  - *the icon file: an Icon Composer document (`scripts/app-icon.py`), compiled by Xcode into light, dark and tinted renditions;*
  - *the Dock states: drawn by Calm only while not idle, redrawn only when a frame changes, still under Reduce Motion.*

  *Checked as rendered PNGs (`ictool` for the icon file, `calm.dock_icon:` for the Dock states), not yet in a real Dock: headless self-tests have none.*
- [x] **M6.8 Welcome page:** with no session open, the window shows the real mark, search over past sessions and projects together, a list of each, and the three ways to start; a plain welcome while there is nothing to list. *Built:*
  - *the mark: the Dock icon's own view, with an arrival and a breathing cursor (`WelcomeMarkMotion`); it comes to rest after eight breaths;*
  - *search: the ⌘K model for sessions, `ProjectSearch` for projects; ↑ ↓ ← → ↵ Esc; ⌘K focuses the page's field;*
  - *layouts: two columns, one column when one side is empty, stacked in a narrow window, the welcome rows when there is nothing (or a new user with no project).*

  *Checked as rendered PNGs in every layout, light and dark, and with the mark frozen at moments of its arrival (`CALM_WELCOME_MARK_AT`); driven through `calm.welcome_*` actions; unfrozen snapshots a half breath apart differ as they should. Not seen: how the motion feels on screen, which headless can't show.*
- [x] **M6.9 Session card sizes:** Full, Compact or Minimal in Settings → Appearance, asked for by the author to fit more sessions in view. *Built (2026-09-30), picked from three rounds of mockups: Compact puts the state and the recap on one line under the title, Minimal is the title with the time in the state's color; at both, a card that waits for you grows a line. Chips like the interface sizes, and the window miniature follows. The working line lost its minutes at every size (the corner's time counts them). Checked as rendered PNGs at each size, light and dark, with Differentiate Without Color, and the Settings page. A size picked live first reached the sidebar only when a session next changed (the settings aren't observed); fixed, and checked within a second of the change. Then **Shrink cards to fit** (off by default): the cards step down from the chosen size when the sessions don't fit and back up when they do; checked headless in a short window (Full → Compact), a shorter one (→ Minimal), a tall one (stays Full), after closing sessions (back to Full), switched on live, and off (stays Full, scrolls). Its explanation moved from a tooltip into the row's one line of help (picked from three mockups), naming the size the cards step down from. Not seen: the height easing on screen, and the restoring state at the smaller sizes.*
- [x] **M6.10 No session chosen:** after closing the session on screen, the main area was plain background ("kinda empty"). Now it shows the sessions waiting for you, each with all it last said, or with none waiting, the welcome page's search and lists. *Built (2026-09-30), picked by the author from three local mockups: waiting cards (B) when something waits, search and lists (C) when nothing does. Checked as rendered PNGs headless: one and two waiting (needs you above done, ↓ moving ↵ Open), the lists against a real index, light and dark, a search with no match. Not seen: keyboard focus in a key window (headless windows are never key), and the crossfade on screen.*

**Exit criteria**
- A new user can make Calm look right in under a minute without editing files.
- The settings screen fits the budget in GOALS.md (F11's window options are over it; FEATURES.md → F11).

*Status: every task is built and self-tested headless. Glass and the Settings page checked on screen by the author (2026-09-30), which headless snapshots can't show. A VoiceOver pass is not planned (2026-09-30, the author's call: accessibility isn't among Calm's goals; the labels already built stay). Left: the exit criteria (a new user's first minute, and F11's window options, which are over the settings budget).*

---

## M7 — Session actions (F12) ✅

Conversations can be renamed, resumed and forked.

- [x] **M7.1 Rename:** rename any session. *Inline, from the card's menu; saved with the workspace.*
- [x] **M7.2 Resume:** resume a closed agent session in its project folder, using each agent's own command. *In place after the agent exits (the session remembers its conversation); closed sessions from ⌘K.*
- [x] **M7.3 Fork:** fork a conversation into a new split or tab, for agents that support it. *Claude Code, Codex, pi.*
- [x] **M7.4 Menus:** right-click actions on session cards.
- [x] **M7.5 Reopen closed session:** ⌘⇧T opens the session closed last again (up to ten, in memory), resuming the agent conversation that was running in it. *Ghostty's `undo` binding on ⌘⇧T is unbound in Calm's defaults.*

**Exit criteria**
- Resuming or forking a conversation is one right-click.

*Status: built and self-tested headless with stand-in conversations. Resume and fork worked with a real agent in the author's use (2026-09-30), which meets the exit criterion; not every agent was checked one by one. OpenCode resumes with `opencode --session <id>` and forks through its own API, since 2.0.19's interface has no `--fork` (2026-09-30; neither run with a real OpenCode yet).*

---

## In every milestone

- Keep FEATURES.md, DESIGNS.md and UIUX.md true in the same change as the code.
- Update the design canvas before a milestone with new screens (M2, M3, M5, M6).
- New logic comes with tests; the app is dogfooded daily from M1 on.

## Later

- Release: Developer ID signing, notarization, Sparkle updates, a Homebrew cask, public launch.
- Changed-file diffs in the viewer.
- Copy an attach command, to reach a session over SSH from another device.
- Spotlight integration (semantic index on macOS 27+).
- Scrollback search across open sessions; paste history.
- Triggers on output patterns; a keyboard copy mode.

## Not planned

See [GOALS.md](GOALS.md#non-goals).
