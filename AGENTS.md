# AGENTS.md

Guidance for coding agents working on Calm Terminal: a minimal macOS terminal that keeps you calm and focused.

## Read first

- [PHILOSOPHY.md](PHILOSOPHY.md) — the principles every change is checked against.
- [FEATURES.md](FEATURES.md) — exact behavior of each feature.
- [DESIGNS.md](DESIGNS.md) — architecture, module boundaries, open decisions.
- [UIUX.md](UIUX.md) — states, motion, color, settings.
- [ROADMAP.md](ROADMAP.md) — what phase we're in; don't build ahead of it without asking.

## Principles

- **Calm first.** Before adding UI, a setting or a notification, apply the test at the end of PHILOSOPHY.md.
- **克制、优雅、极简、Calming.** Restraint, elegance, minimalism, calm: the design guidelines for every screen.
- **Settings are a last resort.** Get the default right. At most one or two settings per feature.
- **Stay a terminal.** No built-in chat, editor, browser or cloud features.
- **Respect module boundaries.** Only `Terminal` touches GhosttyKit; `Model` stays free of UI frameworks.
- **Agents are adapters.** Agent-specific code lives in its own adapter; the core never special-cases an agent.
- **Degrade, don't crash.** Transcript formats and agent hooks change; failures fall back quietly.
- **Keep docs true.** When behavior changes, update FEATURES.md, DESIGNS.md or UIUX.md in the same change, and ROADMAP.md status when a phase item lands.

## Code

- Swift 6 with strict concurrency; no `@preconcurrency` escape hatches without a comment explaining why.
- Match the surrounding code's style; comment the *why* of non-obvious code, especially GhosttyKit and macOS workarounds.
- New logic comes with Swift Testing tests. Parsers get fixture files from real data.

## References and licensing

- Calm is Apache-2.0.
- Ghostty (MIT) may be studied and small parts adapted, with attribution in the file header and in `NOTICE`.
- Other projects are for ideas only. Never copy their code.

## Workflow

- Work in a git worktree, not directly on `main`, so parallel sessions don't collide.
- Commands (once phase 0 lands): `mise run setup`, `mise run build`, `mise run test`, `mise run lint`, `mise run format`.
- Run tests and lint before calling work done; report failures honestly.
