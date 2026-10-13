# Roadmap

Calm is built in milestones. Each milestone ends in a working app. Feature IDs (F1…F17) refer to [FEATURES.md](FEATURES.md).
**Current milestone:** M9. M0 to M7 are built. M8 and M9 are built, and their exit criteria wait on use.

**Open work:**

- M6, M8, M9: the exit criteria marked Open below. The *Later* list.
- OpenCode: the M3 plugin is checked against a fake context only. M7 resume and fork have not run with a real OpenCode.
- M3.14 and M3.15 exist for Claude Code only.

## How to read this

A **milestone** is a usable state of the app. A **task** is one reviewable piece of work. Task IDs (`M2.4`) appear in branch names and commits.
A **Decision** task settles an open question in [DESIGNS.md](DESIGNS.md) and records the outcome there. A row can cover a range of task IDs.
When exit criteria are met, update the milestone status and "Current milestone". Status: ⬜ not started · 🟨 in progress · ✅ done.

## Overview

| Milestone | Delivers | Features | Depends on | Status |
|---|---|---|---|---|
| **M0** Foundations | an empty app that builds, launches and passes CI | — | — | ✅ |
| **M1** A plain terminal | tabs, splits and shells good enough for daily use | F1 | M0 | ✅ |
| **M2** Sessions and projects | the session model, sidebar, grouping, sessions that survive quitting | F2, F3 | M1 | ✅ |
| **M3** Attention | agent detection, session cards, status, calm notifications, arrival card | F4, F5, F6, F13 | M2 | ✅ |
| **M4** Recall | search across every agent's history | F7 | M2 | ✅ |
| **M5** Reading | smart links, Copy Cell, files column and viewer | F8, F9, F10 | M1 (M5.3+ need M2) | ✅ |
| **M6** Look and feel | whole-window themes, picker, settings screen, accessibility pass | F11, F14 | M3 | 🟨 |
| **M7** Session actions | rename, resume, fork | F12 | M3, M4 | ✅ |
| **M8** Find | ⌘F in a session: the field, Calm's own marks, the map of the scrollback | F16 | M5 | 🟨 (built, exit criteria open) |
| **M9** Find, further | `.*` patterns, and the whole session for full-screen programs | F16 | M8 | 🟨 (built, exit criteria open) |

## M0 — Foundations ✅

| ID | What exists | Note |
|---|---|---|
| M0.1 | Minimum macOS 14.5, Apple silicon only. Newer calls are behind `#available`. | Was macOS 26, lowered 2026-10-12. |
| M0.2–M0.10 | `mise.toml` toolchain, `mise run setup`. `scripts/ghostty.env` pins Ghostty. `scripts/ghosttykit.sh` builds GhosttyKit with `scripts/ghostty-patches`. XcodeGen app, `calm` CLI, `CalmKit`. Smoke test, lint, CI, docs. | |

**Exit criteria:** `mise run setup && mise run build` on a clean clone gives an app that launches. CI passes on `main`. Met.

## M1 — A plain terminal (F1) ✅

| ID | What exists | Note |
|---|---|---|
| M1.1–M1.7 | `Terminal` module owns libghostty. Keys, IME, Option-as-Alt, mouse, ⌥-drag selection, clipboard, OSC 52, resize, scrollback, full screen. ⌘-click opens URLs. | |
| M1.8–M1.10 | Tabs, splits, drag a session into a split, take a pane out. ⌘P lists actions with no well-known key (FEATURES.md → Command palette). Shortcut audit. | Palette reworked 2026-09-30 from a list of every action. |
| M1.12–M1.13 | Dogfood day, with self-tests for shell, keys, splits, vim, Chinese text. Cursor glide and smooth scrolling (DESIGNS.md → Motion in the terminal). | Author's only terminal since 2026-09-29. |

**Exit criteria:** A full day with Claude Code, vim, `htop` and Chinese input, with no blocker. Met (2026-09-30).

## M2 — Sessions and projects (F2, F3) ✅

| ID | What exists | Note |
|---|---|---|
| M2.1–M2.4 | `Project`, `Session`, layout tree in `CalmModel`. `state.json`, SQLite for search only. Folder by OSC 7, process fallback. Grouping: projects, folders, scratch. | Grouping changed after real use (2026-09-28). |
| M2.5–M2.10 | Sidebar, collapse, New Project, drop a folder, drag to reorder. Motion. zmx 0.8.1 (MIT) keeps shells (DESIGNS.md → Persistence). `calm open`, `calm list`. `config.toml`. | Reorder added 2026-10-10. |

**Exit criteria:** Quit and relaunch restores everything, shells running. A shell that runs `cd` into another project moves to it. Met.

## M3 — Attention (F4, F5, F6, F13) ✅

| ID | What exists | Note |
|---|---|---|
| M3.1–M3.3 | Adapters and detection for Claude Code, Codex, OpenCode, pi. `CALM_SESSION_ID`, `CALM_SOCKET`, `calm status`, `calm notify`. | omp removed 2026-09-29 (little use). Saved omp sessions load. |
| M3.4 | Hooks with consent and undo. Claude Code: plugin via `CLAUDE_CODE_PLUGIN_DIRS`. pi, OpenCode: extension or plugin from Settings → Agents. | Codex has no hooks: its shared daemon cannot tell which Calm session a hook belongs to. |
| M3.5–M3.7b | Fallback signals (no window titles). States: idle, working, needs you, done, failed. Transcript tails for all four agents (DESIGNS.md → Transcript tails). | Codex and OpenCode never report working. Turn markers give it. |
| M3.8–M3.12 | Cards, *needs you* notifications, ⌘⇧A, arrival card with ⌘⇧I, Settings → Agents. | No diff size on cards (2026-09-29): the files column counts lines. |
| M3.13–M3.15 | ⌘ Return sends, Return makes a new line (Claude Code, OpenCode, pi). Compacting bar and live status words, Claude Code only. | Codex cannot bind ⌘. |
| M3.16 | The `calm` skill for all four agents (F13): in Claude Code's plugin, from pi's extension, and through Connect for OpenCode and Codex. | Added 2026-10-13. Codex's first Connect. Forking during a turn checked with each agent. |
| M3.17 | `calm show` takes a session id, and `calm list` prints it first, so a fork can be looked up. | Added 2026-10-13. The parked commands left CLI.md, and FEATURES.md no longer repeats it. |

**Exit criteria:** GOALS.md G1 and G2. Met (2026-09-30).

## M4 — Recall (F7) ✅

| ID | What exists | Note |
|---|---|---|
| M4.1–M4.8 | Parsers with real fixtures. FTS5 `index.sqlite`, incremental. BM25 plus boosts. `calm search`. ⌘K groups like the sidebar and marks every word. OpenCode read from its database (DESIGNS.md → Search). | Tokenizer chosen by benchmark on real transcripts, Chinese included. |

**Exit criteria:** "Which session talked about X?" is answered with one search. Met (2026-09-30).

## M5 — Reading (F8, F9, F10) ✅

| ID | What exists | Note |
|---|---|---|
| M5.1–M5.2 | Smart links with `path:line[:column]`. Copy Cell: hold ⌥ to outline, ⌥-click to copy. Works in Claude Code's full-screen view. | Reworked 2026-09-30: ⌥-double-click copied a whole row. No right-click item. |
| M5.3–M5.6 | Files column (⌘\\): markers, Changes section, 5 s refresh. Viewer for Markdown, HTML, PDF, images, code. `calm open <file>`. | |
| M5.7–M5.10 | Link marks, ⌘ tag, `HardWrap`. Pasted-image tag. Show Files row and readout. Viewer header and diffs (`FileDiff`). | Show Files added because nothing showed the column existed. |

**Exit criteria:** GOALS.md G4. Met (2026-09-30).

## M6 — Look and feel (F11, F14) 🟨

| ID | What exists | Note |
|---|---|---|
| M6.1–M6.4 | Five contrast-checked themes, light and dark. Chrome takes theme colors. Matching theme for OpenCode and pi. Picker, glass or solid, layout, motion, adaptive background. | Five, not twelve: each is its own direction. |
| M6.5–M6.6 | Settings (⌘,): Appearance, Agents, General, Shortcuts. VoiceOver labels, Increase Contrast, interface size 100 to 150%. | No font control yet. No VoiceOver pass (2026-09-30): accessibility is not a goal. |
| M6.7–M6.10 | App icon and Dock states. Welcome page. Card sizes Full, Compact, Minimal, Shrink cards to fit. No session chosen: waiting cards or welcome search. | |

**Exit criteria:** GOALS.md G9 and G10. Both open.

## M7 — Session actions (F12) ✅

| ID | What exists | Note |
|---|---|---|
| M7.1–M7.5 | Rename. Resume in place or from ⌘K. Fork (Claude Code, Codex, pi). Card menus. ⌘⇧T reopens the last of ten closed sessions. | OpenCode forks through its API: 2.0.19 has no `--fork`. |
| M7.6 | ⌘N starts the chosen agent with option chips. ⌘⇧N uses a scratch folder. ⌘T stays a shell. | |
| M7.7 | ⌘P restarts an agent after an update. Amber hint while it is outdated. All four agents. | Was a second M7.6, renumbered. pi's own options are not carried. |

**Exit criteria:** GOALS.md G5. Met (2026-09-30, with a real agent, not each agent).

## M8 — Find (F16) 🟨

| ID | What exists | Note |
|---|---|---|
| M8.1–M8.3 | ⌘F field, "3 of 11", own search per pane. Calm matches itself (`FindMatcher`), no engine patch. Calm draws marks, colored from the theme (`FindColors`). | esc works in the field only: Calm unbinds `escape=end_search`. |
| M8.4–M8.6 | Scrollback map (`FindMap`). Full-screen note with Search all of it, engine patch 0018. Sliding band, fades, no cost at rest. | |
| M8.7 | Find in the viewer: own page, PDFKit, web view find. esc closes find first. | |

**Exit criteria:** ⌘F finds a line in a long log, and the full-screen note leads to ⌘K. Open. Calm at rest costs what it did (`mise run perf`). Open.

## M9 — Find, further (F16) 🟨

| ID | What exists | Note |
|---|---|---|
| M9.1–M9.3 | `.*` patterns, ⌥⌘R, `FindQuery`, patch 0019. Patch 0020 reads the primary screen. `ScreenKeeper` keeps 50,000 lines, patch 0021. | PDFs and web pages have no switch. |
| M9.4–M9.5 | Screen \| Session switch. `SessionPage`: kept lines with time marks, marks, count, map. esc or Screen returns. | |

**Exit criteria:** A line Claude Code showed an hour earlier is found with ⌘F, Session. Open. GOALS.md G7. Met (2026-10-07).

## Later

Planned features without a milestone are in [FEATURES.md → Later, if needed](FEATURES.md#later-if-needed). What Calm will not do is in [FEATURES.md → Explicitly not planned](FEATURES.md#explicitly-not-planned).
