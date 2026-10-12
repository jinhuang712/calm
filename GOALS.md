# Goals

Each goal is a check with a number. A goal is met when its measure holds in the author's daily use or in `mise run perf` (DESIGNS.md → Testing). The exit criteria in ROADMAP.md refer to these IDs.

| # | Goal | Measure | Status |
|---|---|---|---|
| G1 | Find a waiting agent | 0 tab switches to find which agent waits | ✅ Met 2026-09-30 |
| G2 | Never miss "needs you" | 0 missed in a week of daily use | ✅ Met 2026-09-30, after 4 days of heavy use |
| G3 | Fast search | A query takes < 50 ms while typing. An index update with nothing new takes < 50 ms. | ✅ Met: 0.7–14 ms and 8 ms (DESIGNS.md → Search) |
| G4 | Reading takes one action | Copy a table cell, open a path at its line, view a file: 1 action each | ✅ Met 2026-09-30 |
| G5 | Resume or fork in one step | 1 right-click | ✅ Met 2026-09-30 |
| G6 | Cost at rest | An idle shell: ≤ 40 M instructions/s and ≤ 60 wakeups/s. Three working agents, in view or hidden: ≤ 40 M and ≤ 80. | ✅ Met (`mise run perf`) |
| G7 | Cost of a streaming full-screen program | In view: ≤ 400 M instructions/s and ≤ 400 wakeups/s. Hidden: ≤ 40 M and ≤ 80. | ✅ Met 2026-10-07 |
| G8 | Every major agent | 4 agents detected and tracked: Claude Code, Codex, OpenCode, pi | ✅ Met |
| G9 | Few settings | ≤ 2 settings per feature | ⬜ Open: F11's window options are over |
| G10 | A new user's first minute | A new user makes Calm look right in < 1 minute, without editing a file | ⬜ Open |
| G11 | Daily driver | The author uses no other terminal | ✅ Met since 2026-09-29 |
