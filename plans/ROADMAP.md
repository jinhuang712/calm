<!-- what-we-build: drafted 2026-10-28 -->

# Roadmap

Calm is built in milestones. Each milestone ends in a working app. Feature IDs (F1…F17) refer to [FEATURES.md](../specs/FEATURES.md) to [GOALS.md](../GOALS.md) appear in branch names and commits. A row can cover a range of task IDs.

A **design discussion** (`D6.1`) settles an open question before the milestone it blocks. The user approves the decisions, which then move to [DESIGNS.md](../DESIGNS.md) | ✅ |
| **M6** Look and feel | whole-window themes, picker, settings screen | F11, F14 | M3 | 🟨 |
| **M7** Session actions | rename, resume, fork, new agent sessions, restart | F12, F15 | M3, M4 | ✅ |
| **M8** Find | ⌘F in a session: the field, Calm's own marks, the map of the scrollback | F16 | M5 | 🟨 built, exit criteria open |
| **M9** Find, further | `.*` patterns, and the whole session for full-screen programs | F16 | M8 | 🟨 built, exit criteria open |

Not yet used in real life: the OpenCode plugin has run only against a fake context, and M7's resume and fork have not run with a real OpenCode.

## M0 — Foundations ✅

| ID | What it delivers |
|---|---|
| M0.1 | Minimum macOS 14.5, Apple silicon only. Newer calls sit behind `#available`. |
| M0.2–M0.10 | Toolchain and `mise run setup`, the pinned Ghostty and its patches, the XcodeGen app, the `calm` CLI, the `CalmKit` package, a smoke test, lint, CI and docs. |

**Exit criteria:** `mise run setup && mise run build` on a clean clone gives an app that launches, and CI passes on `main`. Met.

## M1 — A plain terminal (F1) ✅

| ID | What it delivers |
|---|---|
| M1.1–M1.7 | The terminal view: keys, IME, Option-as-Alt, mouse, ⌥-drag selection, clipboard, OSC 52, resize, scrollback, full screen, ⌘-click on URLs. |
| M1.8–M1.10 | Tabs, splits, drag a session into a split, take a pane out. The command palette. A shortcut audit. |
| M1.12–M1.13 | A dogfood day with self-tests for shell, keys, splits, vim and Chinese text. Cursor glide and smooth scrolling. |

**Exit criteria:** a full day with Claude Code, vim, `htop` and Chinese input, with no blocker. Met 2026-09-30. G11 is met since 2026-09-29.

## M2 — Sessions and projects (F2, F3) ✅

| ID | What it delivers |
|---|---|
| M2.1–M2.4 | `Project`, `Session` and the layout tree. `state.json`, with SQLite for search only. The folder from OSC 7, with a process fallback. Grouping into projects, folders and scratch. |
| M2.5–M2.10 | The sidebar, collapse, New Project, drop a folder, drag to reorder. Motion. zmx keeps shells. `calm open` and `calm list`. `config.toml`. |

**Exit criteria:** quit and relaunch restores everything, with shells running, and a shell that runs `cd` into another project moves to it. Met.

## M3 — Attention (F4, F5, F6, F13) ✅

| ID | What it delivers |
|---|---|
| M3.1–M3.3 | Adapters and detection for Claude Code, Codex, OpenCode and pi. `CALM_SESSION_ID`, `CALM_SOCKET`, `calm status`, `calm notify`. |
| M3.4 | Hooks with consent and undo: a plugin for Claude Code, an extension or plugin for pi and OpenCode from Settings → Agents. |
| M3.5–M3.7b | Fallback signals and the five states. Transcript tails for all four agents. |
| M3.8–M3.12 | Cards, *needs you* notifications, ⌘⇧A, the arrival card with ⌘⇧I, Settings → Agents. |
| M3.13–M3.15 | ⌘ Return sends (Claude Code, OpenCode, pi). The compacting bar and live status words, for Claude Code only. |
| M3.16–M3.17 | The `calm` skill for all four agents. `calm show` takes a session id, and `calm list` prints it first. |

**Exit criteria:** GOALS.md G1, G2 and G8. G1 and G2 met 2026-09-30.

## M4 — Recall (F7) ✅

| ID | What it delivers |
|---|---|
| M4.1–M4.8 | Parsers tested on real fixtures. An incremental FTS5 index. Ranking. `calm search`. ⌘K, grouped like the sidebar. OpenCode read from its database. |

**Exit criteria:** GOALS.md G3. Met before 2026-09-30, with no script to reproduce it (G3).

## M5 — Reading (F8, F9, F10) ✅

| ID | What it delivers |
|---|---|
| M5.1–M5.2 | Smart links with `path:line[:column]`. Copy Cell. |
| M5.3–M5.6 | The files column (⌘\\) with Changes and a 5-second refresh. The viewer for Markdown, HTML, PDF, images and code. `calm open <file>`. |
| M5.7–M5.10 | Link marks and the ⌘ tag. Hard-wrapped links joined. The pasted-image tag. The Show Files row and readout. Viewer header and diffs. |

**Exit criteria:** GOALS.md G4. Met 2026-09-30.

## M6 — Look and feel (F11, F14) 🟨

| ID | What it delivers |
|---|---|
| M6.1–M6.4 | Five contrast-checked themes, light and dark. Chrome takes theme colors. Matching themes for OpenCode and pi. The picker, glass or solid, layout, motion, adaptive background. |
| M6.5–M6.6 | Settings (⌘,): Appearance, Agents, General, Shortcuts. VoiceOver labels, Increase Contrast, interface size. |
| M6.7–M6.10 | App icon and Dock states. The welcome page. Card sizes. The no-session page. |

**Exit criteria:** GOALS.md G9 and G10. G9 is not met (Agent status 3, Themes 7, New agent sessions 4). G10 is open.

## M7 — Session actions (F12, F15) ✅

| ID | What it delivers |
|---|---|
| M7.1–M7.5 | Rename. Resume in place or from ⌘K. Fork (Claude Code, Codex, pi, and OpenCode through its API). Card menus. ⌘⇧T reopens the last of ten closed sessions. |
| M7.6 | ⌘N starts the chosen agent with option chips. ⌘⇧N uses a scratch folder. ⌘T stays a shell. |
| M7.7 | Restart an agent after an update, with an amber hint while it is outdated, for all four agents. |

**Exit criteria:** GOALS.md G5. Met 2026-09-30, with a real agent, not each agent.

## M8 — Find (F16) 🟨

| ID | What it delivers |
|---|---|
| M8.1–M8.3 | The ⌘F field, "3 of 11", a search per pane. Calm matches and draws the marks itself. |
| M8.4–M8.6 | The scrollback map. The full-screen note that leads to ⌘K. Slides and fades with no cost at rest. |
| M8.7 | Find in the viewer: Calm's page, PDFKit, web view find. |

**Exit criteria:** GOALS.md G12 and G6. G12 is open. G6 not run since M8.

## M9 — Find, further (F16) 🟨

| ID | What it delivers |
|---|---|
| M9.1–M9.3 | `.*` patterns and ⌥⌘R. The primary screen read behind a full-screen program. 50,000 kept lines per session. |
| M9.4–M9.5 | The Screen \| Session switch and the session page, with time marks, a count and the map. |

**Exit criteria:** GOALS.md G12 and G7. G12 is open. G7 met 2026-10-07.

## Waiting for design

| Feature | Depends on | Discussed |
|---|---|---|
| Sidebar ordering beyond dragging a project's header | What to order: projects automatically, sessions inside a project, or a pinned area | ⬜ not yet |
| Reaching a session from another device (`calm attach`, `calm watch`) | Whether a second client of another size breaks Calm's pane (not checked) | ⬜ not yet |
| Telling a nested pi or OpenCode from the session's own | `calm status --agent …` sends no process ancestors, so a nested agent of the same kind is not told apart | ⬜ not yet |
| Whether a subagent's tool calls fire the parent's hooks | The live line shows the parent's steps. A real check with Claude Code is needed | ⬜ not yet |
| A Developer ID build, notarization and Sparkle | An Apple Developer Program account. It also decides whether grants survive updates | ⬜ not yet |
| A first-minute check for a new user (G10) | A new user to watch | ⬜ not yet |

## Later

See [FEATURES.md → Later, if needed](../specs/FEATURES.md#later-if-needed).
