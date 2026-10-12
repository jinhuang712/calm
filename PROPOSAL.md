# Calm Terminal — Proposal

> A minimal macOS terminal that keeps you calm and focused.

Proposed 2026-09-27. For what is built today, see [ROADMAP.md](ROADMAP.md).

## In short

Coding agents changed the developer's job from typing to supervising. Terminals did not change with it. Calm Terminal is a native macOS terminal built for that job: it shows which agent needs you, keeps every thread, and stays quiet the rest of the time.

## The shift

| Before agents | With agents |
|---|---|
| One shell, one task | 5 to 10 long-running sessions across several projects |
| The developer types | The developer reads, approves and steers |
| A tab is a place to work | A tab is a place to check |
| History is a shell's scrollback | History is hundreds of transcripts in four agents' folders |

## Pain points

1. **Too many terminals to track.** To learn which session is working, done or waiting, the user clicks through tabs. All day.
2. **Losing the thread.** Every switch into a session starts with the same question: "What was this one doing?"
3. **Scattered history.** Yesterday's decision is in one of hundreds of transcript files. On the author's Mac: 502 files and 13,889 messages in 1.4 GB, from Claude Code, Codex and pi. Claude Code deletes transcripts after 30 days by default, and 281 of 424 sessions were already gone.
4. **Loud interfaces.** Saturated themes, badges, rings, tabs that reorder and large settings screens add stress to work that is already demanding.
5. **Output that is hard to use.** Copying one table cell copies the whole row. Clicking a path rarely opens the right file at the right line.

**The result:** constant, low agitation from keeping track of work instead of doing it.

## What we want

| Pain | What Calm does |
|---|---|
| Too many terminals | The state of every session is visible at a glance. Only "needs you" sends a notification. |
| Losing the thread | Switching into a session shows what it was doing and what it last asked. Sessions survive quitting the app. |
| Scattered history | One search finds any past conversation, across every agent, and resumes it. |
| Loud interfaces | Soft themes, gentle motion, quiet status and few settings. |
| Hard-to-use output | ⌘-click opens a path at its line. ⌥-click copies one table cell. A files column and a viewer show what an agent changed. |

Underneath all five: **Calm stays a terminal.** The agents keep their own interfaces. Calm improves the space around them.

## What we don't want

| Not this | Why |
|---|---|
| An IDE | Editing and code review belong in the user's editor. |
| An agent | The agents bring their own chat. Calm makes no model calls. |
| A platform | No accounts, cloud or relays. The agents' own remote features and SSH cover remote access. |
| A settings maze | When an option needs a paragraph to explain, the default is wrong. |
| Cross-platform | Calm is macOS only, so it can be native. |

The full list is in [FEATURES.md → Explicitly not planned](FEATURES.md#explicitly-not-planned).

## Who it is for

Developers on macOS who run several CLI coding agents in parallel every day: Claude Code, Codex, OpenCode and pi. The first user is the author.

## Approach

- **A new Swift codebase on libghostty,** Ghostty's terminal engine. The model is projects → sessions → panes, with attention as a first-class concept.
- **Native:** SwiftUI and AppKit, Mac conventions, Apple silicon.
- **Agents through adapters:** one small adapter per agent. The core never special-cases an agent.
- **Local only:** no server, no account. All state is in files on the Mac.
- **Built on what exists:** zmx keeps shells alive, SQLite FTS5 indexes the search, Ghostty's macOS app (MIT) shows the known pitfalls. Calm copies no code. The engine patches come unchanged from a Ghostty fork (MIT) and are credited in NOTICE.

## Risks

| Risk | Mitigation |
|---|---|
| A new codebase takes longer than a fork | Ship a usable plain terminal first (ROADMAP.md → M1), then add features to a working app. |
| Terminal-embedding bugs that others already solved | Study Ghostty's macOS app for known pitfalls before writing each layer. |
| Agents change their transcript formats without notice | One small adapter per agent, each with tests on real transcripts. A failure shows less, never crashes. |
| Scope creep toward a platform | "What we don't want" above, and the test in PHILOSOPHY.md. |

## How we know it works

Success is measured, not felt. [GOALS.md](GOALS.md) holds the checks: 0 tab switches to find a waiting agent, 0 missed "needs you", search under 50 ms, and a cost at rest held to a budget.

## Documents

| Document | Answers |
|---|---|
| [PHILOSOPHY.md](PHILOSOPHY.md) | Why is Calm this way? |
| [GOALS.md](GOALS.md) | What do we measure? |
| [FEATURES.md](FEATURES.md) | What does Calm do, and what will it do? |
| [DESIGNS.md](DESIGNS.md) | How is it built, and why that way? |
| [UIUX.md](UIUX.md) | How does it look and move? |
| [ROADMAP.md](ROADMAP.md) | When? |
| [AGENTS.md](AGENTS.md) | How do coding agents work in this repo? |
