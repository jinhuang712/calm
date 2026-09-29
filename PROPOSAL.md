# Calm Terminal — Proposal

> A minimal macOS terminal that keeps you calm and focused.

## The problem

Working with CLI coding agents (Claude Code, Codex, OpenCode, pi, omp) has changed what a terminal is for. A typical day now means five to ten long-running agent sessions across several projects. The developer mostly reads, approves and steers; typing commands is the smaller part.

Terminals were not built for this, and it shows:

- **Too many terminals to track.** Which session is working, which finished, which is waiting on me? Finding out means clicking through tabs.
- **Losing the thread.** Switching into a session often starts with "what was this one doing again?"
- **History is scattered.** A decision made in yesterday's conversation is somewhere in one of hundreds of transcript files across five agents' folders.
- **Loud, messy interfaces.** Saturated themes, badges, rings, reordering tabs and settings screens with hundreds of options add stress instead of removing it.
- **Output is hard to work with.** Agent output is Markdown, tables, diffs and file paths, but copying one table cell copies the whole row, and clicking a path rarely opens the right file at the right line.

The result is a low, constant agitation: working hard to keep track of work.

## The proposal

Build **Calm Terminal**, a native macOS terminal designed for supervising CLI agents calmly. It stays a terminal: the agents keep their own interfaces. What Calm adds is the layer around them:

1. **Know without checking.** Calm knows each session's state (working, needs you, done) and shows it quietly at the edge of the screen. It interrupts only when an agent needs you.
2. **Pick up where you left off.** Switching to a session shows what it was doing and what it last asked. Sessions survive quitting the app.
3. **Find any past conversation.** One search box across every agent's history, so "which session talked about X?" takes seconds.
4. **Read agent output comfortably.** Copy a single table cell, open paths at the right line, peek at files and Markdown without leaving the terminal.
5. **Stay out of the way.** Soft themes, calm motion, few settings, defaults that are right.

## Who it is for

Developers on macOS who run several CLI coding agents in parallel every day and want less stress doing it. The first user is the author.

## Approach

A fresh codebase in Swift on libghostty, written from scratch around our own model (projects → sessions → panes, with attention as a first-class concept). Ghostty's own macOS app (MIT) is the reference for known pitfalls; code from other projects is never copied.

## Risks

| Risk | Mitigation |
|---|---|
| A rewrite takes longer than a fork | A usable plain terminal early (roadmap phase 1), features added on a working app |
| Terminal-embedding bugs others already solved | Study Ghostty's macOS app for known pitfalls before writing each layer |
| Agents' transcript formats change without notice | One small adapter per agent, each with fixture tests |
| Scope creep toward a platform | [PHILOSOPHY.md](PHILOSOPHY.md) and [GOALS.md](GOALS.md) define what we refuse to build |

## Documents

| Document | Purpose |
|---|---|
| [PHILOSOPHY.md](PHILOSOPHY.md) | What "calm" means and the principles every decision is checked against |
| [GOALS.md](GOALS.md) | Goals, non-goals and how we know we succeeded |
| [FEATURES.md](FEATURES.md) | Every feature and its exact behavior |
| [UIUX.md](UIUX.md) | Layout, states, motion, color, settings |
| [DESIGNS.md](DESIGNS.md) | Architecture and technical design |
| [ROADMAP.md](ROADMAP.md) | Phases and milestones |
| [AGENTS.md](AGENTS.md) | Instructions for coding agents working in this repo |
