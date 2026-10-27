# AGENTS.md

Guidance for coding agents working on Calm Terminal: a minimal macOS terminal that keeps you calm and focused.

## Read first

- [PROPOSAL.md](PROPOSAL.md) — why Calm exists, what we want and what we don't.
- [PHILOSOPHY.md](PHILOSOPHY.md) — the stances every change is checked against. Its last section is the test for every change.
- [DESIGNS.md](DESIGNS.md) — the eight principles the code is built around, and the decisions with their reasons.
- [GOALS.md](GOALS.md) — what we measure, with readings and thresholds.
- [FEATURES.md](FEATURES.md) — exact behavior of each feature, each feature's own decisions, what fails, *Later* and *Not planned*.
- [UIUX.md](UIUX.md) — states, motion, color, keys.
- [CLI.md](CLI.md) — every `calm` command, built and planned.
- [ROADMAP.md](ROADMAP.md) — milestones, progress and design questions still open. Do not start a *Later* item without asking.
- [RUNBOOK.md](RUNBOOK.md) — build, release, install, and the first step when something is wrong.
- [TODO.md](TODO.md) and [CHANGELOG.md](CHANGELOG.md) — small open items, and what shipped.

## Principles

- **Calm first.** Before you add UI, a setting or a notification, apply the test at the end of PHILOSOPHY.md.
- **Restraint, elegance, minimalism, calm.** These are the design guidelines for every screen (UIUX.md → Design guidelines).
- **Settings are a last resort.** Get the default right. Give each feature at most one or two settings.
- **Stay a terminal.** No built-in chat, editor, browser or cloud features.
- **Respect module boundaries.** Only `Terminal` touches GhosttyKit. `CalmKit` (CalmModel, CalmAgents, CalmSearch, CalmControl, CalmSQLite) has no UI framework.
- **Agents are adapters.** Agent-specific code lives in its own adapter. The core never special-cases an agent.
- **Degrade, don't crash.** Transcript formats and agent hooks change, so a failure falls back quietly.
- **Keep docs true.** Each fact has one home. Behavior and a feature's own decisions go in FEATURES.md, a rule that spans the project in DESIGNS.md, how it looks in UIUX.md, a number in GOALS.md, and what shipped in CHANGELOG.md. When behavior changes, update the owner first and its summaries in the same change. When a milestone task lands, update ROADMAP.md.
- **Headings are addresses.** Code comments and docs cite headings (`FEATURES.md → Not planned`). Before you rename one, search for it and fix every reference in the same change.
- **A claim is checked.** A command, a number or a behavior in a doc is run or measured, or marked "not yet verified". A goal is met only with a reading and a date.

## Code

- Use Swift 6 with strict concurrency. Explain every `@preconcurrency` escape hatch in a comment.
- Match the surrounding style. Comment the *why* of non-obvious code, especially GhosttyKit and macOS workarounds.
- New logic needs Swift Testing tests. Parsers need fixture files made from real data.

## References and licensing

- Calm is Apache-2.0. Other projects are for ideas only: never copy their code.
- You may study Ghostty (MIT) and adapt small parts. Give attribution in the file header and in `NOTICE`.
- One exception (decided 2026-09-29): `scripts/ghostty-patches` come unchanged from `thdxg/ghostty` (MIT), credited in `NOTICE`. Refresh them from the fork, never edit them here.
- Calm's own patches go beside them as separate files, 0007 and up (decided 2026-09-29). Keep each as small as possible and worth offering upstream.

## Workflow

- Work in a git worktree, not on `main`, so parallel sessions do not collide.
- Commands: `mise run setup` (tools, GhosttyKit, zmx, Xcode project), `build`, `test`, `lint`, `format`, `run`.
- A new worktree has an untrusted `mise.toml`. Prefix each mise command with `MISE_TRUSTED_CONFIG_PATHS=<the worktree's absolute path>`, not `mise trust`. Run `setup` first (seconds, from the `~/Library/Caches/calm` cache).
- In a worktree, `mise run lint` and `format` check no files, because `.swiftformat` excludes `.claude`. Run `swiftformat --config .swiftformat --cache ignore --lint .` (no `--lint` to format) and `swiftlint lint --quiet --strict`.
- Self-tests: `scripts/selftest.sh <name> [--type …] [--actions …] [--after …]` runs the Debug app, saves a window PNG, the screen text and a log, and quits. `scripts/xcode.sh snapshot <out.png> [delay]` is the short form.
- Self-tests need no Screen Recording permission. They run **headless** by default: `--visible` shows a window, so leave it off unless the user asks to watch.
- Self-tests are isolated from a running Calm: state, socket, config, zmx directory and Claude Code plugin live in the test's support folder.
- Self-tests paste through their own pasteboard (`NSPasteboard.calm`). Route every new copy through it. Never save and restore the user's clipboard, because that lost an image (once). A real program in a test (Claude Code) can still write it, so ask before you run one that selects or copies.
- `UserDefaults` belong to the Debug bundle id `com.jinhuang.calm.dev`, so a test cannot change the installed Calm's. Debug runs share them.
- The home folder is not isolated. A test writes no agent config (a connected agent's files, OpenCode's theme) unless given `--agent-files`, and then only with a scratch `CFFIXED_USER_HOME`.
- **Don't pop up windows.** Test headless: no `--visible`, no launching the Debug app to look at it, nothing that steals focus. The user works in another window.
- **Design HTML and Artifacts: give a link, don't open it.** Put the link in your reply (`file://` for a local file, the URL for an Artifact). Never `open` the file, launch the browser or use the Artifact `open` action. A headless browser check is fine.
- `Calm.xcodeproj` is generated from `project.yml`. Never edit it by hand.
- Run tests and lint before you call work done. Report failures honestly. After a change to rendering, animation or timers, also run `mise run perf`: it fails when Calm at rest exceeds its budget (DESIGNS.md → Cost is a budget of instructions and wakeups, checked by a script).
- Never quit, reopen or launch the installed Calm (`/Applications/Calm.app`): the user restarts it. So never run `osascript … quit`, `open Calm.app`, `mise run run` (it `pkill`s Calm) or a `calm` command that starts Calm when its socket is missing.
- After you land on `main` and push to `origin/main`, run `./install.sh` from a checkout at that commit, so the installed Calm matches `main`. Never pass `--restart`.
- `./install.sh` does not quit a running Calm, which is then out of date. Until it restarts, its shells can lose access to Documents, Desktop and Downloads ("Operation not permitted", seen 2026-10-01; RUNBOOK.md → Installing under a running Calm). In the same message, tell the user to restart Calm soon (Calm → Restart Calm), and why.
