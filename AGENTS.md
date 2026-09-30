# AGENTS.md

Guidance for coding agents working on Calm Terminal: a minimal macOS terminal that keeps you calm and focused.

## Read first

- [PHILOSOPHY.md](PHILOSOPHY.md) — the principles every change is checked against.
- [FEATURES.md](FEATURES.md) — exact behavior of each feature.
- [DESIGNS.md](DESIGNS.md) — architecture, module boundaries, open decisions.
- [UIUX.md](UIUX.md) — states, motion, color, settings.
- [CLI.md](CLI.md) — every `calm` command, built and planned.
- [ROADMAP.md](ROADMAP.md) — what is built and what is left; don't start a *Later* item without asking.

## Principles

- **Calm first.** Before adding UI, a setting or a notification, apply the test at the end of PHILOSOPHY.md.
- **克制、优雅、极简、Calming.** Restraint, elegance, minimalism, calm: the design guidelines for every screen.
- **Settings are a last resort.** Get the default right. At most one or two settings per feature.
- **Stay a terminal.** No built-in chat, editor, browser or cloud features.
- **Respect module boundaries.** Only `Terminal` touches GhosttyKit; the `CalmKit` package (CalmModel, CalmAgents, CalmSearch, CalmControl, CalmSQLite) stays free of UI frameworks.
- **Agents are adapters.** Agent-specific code lives in its own adapter; the core never special-cases an agent.
- **Degrade, don't crash.** Transcript formats and agent hooks change; failures fall back quietly.
- **Keep docs true.** When behavior changes, update FEATURES.md, DESIGNS.md or UIUX.md in the same change, and ROADMAP.md status when a milestone task lands.

## Code

- Swift 6 with strict concurrency; no `@preconcurrency` escape hatches without a comment explaining why.
- Match the surrounding code's style; comment the *why* of non-obvious code, especially GhosttyKit and macOS workarounds.
- New logic comes with Swift Testing tests. Parsers get fixture files from real data.

## References and licensing

- Calm is Apache-2.0.
- Ghostty (MIT) may be studied and small parts adapted, with attribution in the file header and in `NOTICE`.
- Other projects are for ideas only. Never copy their code. One exception, decided 2026-09-29: the engine patches in `scripts/ghostty-patches`, taken unchanged from `thdxg/ghostty` (MIT) and credited in `NOTICE`. Refresh them from the fork; don't edit them here. Calm's own patches go beside them as separate files (0007 and up, decided 2026-09-29), each as small as it can be and worth offering upstream.

## Workflow

- Work in a git worktree, not directly on `main`, so parallel sessions don't collide.
- Commands: `mise run setup` (tools, GhosttyKit, zmx, Xcode project), `mise run build`, `mise run test`, `mise run lint`, `mise run format`, `mise run run`.
- In a new worktree:
  - Its `mise.toml` isn't trusted yet. Prefix each mise command with `MISE_TRUSTED_CONFIG_PATHS=<the worktree's absolute path>` instead of running `mise trust`.
  - Run `setup` first. GhosttyKit comes from the cache in `~/Library/Caches/calm`, so it takes seconds.
  - `mise run lint` and `format` check nothing there, because `.swiftformat` excludes `.claude`. Run `swiftformat --config .swiftformat --cache ignore --lint .` (without `--lint` to format) and `swiftlint lint --quiet --strict`.
- Self-tests: `scripts/selftest.sh <name> [--type …] [--actions …] [--after …]` launches the Debug app, drives it, saves a PNG of its window, the screen text and a log, and quits; `scripts/xcode.sh snapshot <out.png> [delay]` is the short form. They need no Screen Recording permission and run **headless** by default (no window, no focus taken; `--visible` to watch), isolated from a Calm you may be running (own state, socket, config and zmx directory). They copy and paste through a pasteboard of their own (`NSPasteboard.calm`); route any new copy through it, and never save and restore the user's clipboard instead (that lost an image once). A real program run inside a test (Claude Code) can still write the user's clipboard itself, so ask before running one that selects or copies. `UserDefaults` belong to the Debug app's own bundle id (`com.jinhuang.calm.dev`), so a test can't change the installed Calm's; Debug runs do share them with each other. The home folder isn't either, so a test writes nothing into agents' config folders (a connected agent's files, OpenCode's theme) unless given `--agent-files`, and then only with a scratch `CFFIXED_USER_HOME`.
- `Calm.xcodeproj` is generated from `project.yml`; never edit the project file by hand.
- Run tests and lint before calling work done; report failures honestly. After a change to rendering, animation or timers, also run `mise run perf`: it fails when Calm at rest costs more than its budget (DESIGNS.md → Testing).
- Never quit, reopen or launch the installed Calm (`/Applications/Calm.app`): the user restarts it when they choose. That rules out `osascript … quit`, `open Calm.app`, `mise run run` (it `pkill`s Calm) and `calm` commands that start Calm when its socket is missing. Self-tests stay headless and isolated; they never touch the running app.
- After landing on `main` and pushing it to `origin/main`, reinstall: run `./install.sh` from a checkout at that `main` commit, so the installed Calm matches `main`. It leaves a running Calm alone (the new app starts the next time the user opens Calm), so it's safe to run any time; never pass `--restart`, and tell the user the new version is waiting for their next restart (Calm → Restart Calm).
