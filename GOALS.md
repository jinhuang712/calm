<!-- what-we-build: drafted 2026-10-28 -->

# Goals

GOALS holds two kinds of number: goals that pass or fail, and benchmarks tracked against a reference. The wants are the four in [PROPOSAL.md](PROPOSAL.md) → What we want. A goal counts as met when its measure holds in the author's daily use (the user's own report) or in `mise run perf`. [ROADMAP.md](ROADMAP.md) uses these IDs as exit criteria.

## Goals

| # | Goal | Want | Measure | Method | Measured on | Status |
|---|---|---|---|---|---|---|
| G1 | Find a waiting agent | Know at a glance | 0 tab switches to find which agent waits | The author's daily use | The author's Mac | ✅ Met 2026-09-30 |
| G2 | Never miss "needs you" | Know at a glance | 0 missed in a week of daily use | The author's daily use | The author's Mac | ✅ Met 2026-09-30, after 4 days of heavy use, not a week. Not measured again since |
| G3 | Fast search | Come back without rebuilding the context | A query takes < 50 ms while typing. An index update with nothing new takes < 50 ms | A timing run on the author's own history. No script is committed | The author's history, Debug build | ✅ Met before 2026-09-30: queries 0.7–14 ms, update 8 ms. Not reproducible by script |
| G4 | Reading takes one action | Read output where it appears | Copy a table cell, open a path at its line, view a file: 1 action each | The author's daily use | The author's Mac | ✅ Met 2026-09-30 |
| G5 | Resume or fork in one step | Come back without rebuilding the context | 1 right-click | The author's daily use, with one real agent, not each | The author's Mac | ✅ Met 2026-09-30 |
| G6 | Cost at rest | Calm by default | An idle shell: ≤ 40 M instructions/s and ≤ 60 wakeups/s. Three working agents, in view or hidden, or compacting: ≤ 40 M and ≤ 80 | `mise run perf`, scenarios `idle`, `seen`, `unseen`, `compacting` (`scripts/perf-check.py`) | A headless Debug run | ✅ Met. Date not recorded. Not run in this rewrite |
| G7 | Cost of a streaming full-screen program | Calm by default | In view: ≤ 400 M instructions/s and ≤ 400 wakeups/s. Hidden: ≤ 40 M and ≤ 80 | `mise run perf`, scenarios `fullscreen`, `fullscreen-unseen` | A headless Debug run | ✅ Met 2026-10-07 |
| G8 | Every major agent | Know at a glance | 4 agents detected and tracked: Claude Code, Codex, OpenCode, pi | Each adapter's tests on fixtures from real sessions (`Packages/CalmKit/Tests/CalmAgentsTests/Fixtures`) | Real transcripts of each agent. The OpenCode plugin has run only against a fake context | ✅ Met. Date not recorded |
| G9 | Few settings | Calm by default | ≤ 2 settings per feature | Count the **Settings:** line of each feature in FEATURES.md | FEATURES.md | ❌ Not met 2026-10-28: Agent status (3), Themes (7), New agent sessions (4) |
| G10 | A new user's first minute | Calm by default | A new user makes Calm look right in < 1 minute, without editing a file | Watch new users, 5 sessions | Nobody but the author has used Calm | ⬜ Open: not yet measured |
| G11 | Daily driver | All four wants | The author uses no other terminal | The author's report | The author's Mac | ✅ Met since 2026-09-29 |
| G12 | Find a line from earlier in a session | Come back without rebuilding the context | Number not set. The check: ⌘F finds a line in a long log, and in Claude Code's full-screen view finds a line shown an hour earlier (Session) | The author's daily use | The author's Mac | ⬜ Open: not yet measured |

## Benchmarks

| # | Benchmark | Compared with | Method | Last measured |
|---|---|---|---|---|
| B1 | Cost per scenario: instructions/s and wakeups/s | The budgets in G6 and G7, and the same scenario at the last release | `mise run perf` | Not measured in this rewrite. The last recorded: G7 on 2026-10-07 |
| B2 | Engine patches: lines and files | Their own value at each Ghostty upgrade. The smooth-scrolling share (about 88%) is what leaves when upstream ships it | `cat scripts/ghostty-patches/*.patch \| wc -l` | 7,979 lines in 17 patches, 2026-10-28. The first reading: no earlier value is recorded |
| B3 | Search timings: query, no-change update, first full index | G3's 50 ms limit | A timing run on the author's history. No script is committed | Query 0.7–14 ms, update 8 ms, first full index 12.6 s for 502 files and 1.4 GB (Debug build, before 2026-09-30) |
