<!-- what-we-build: drafted 2026-10-28 -->

# Calm Terminal — Proposal

> A minimal macOS terminal that keeps you calm and focused.

Proposed 2026-09-27. This is what the project will be: what is built is in [FEATURES.md](FEATURES.md), and where the work stands is in [ROADMAP.md](ROADMAP.md).

## In short

You start five agents before lunch, in four projects. After lunch you click through tabs to find the one that has waited twenty minutes for a yes. When you find it, you cannot remember what it was doing.

**Calm Terminal is a native macOS terminal for supervising coding agents: it shows which one needs you, keeps every thread, and stays quiet the rest of the time.**

## Pain points

1. **Too many terminals to track.** To learn which session is working, done or waiting, you click through tabs. All day, and a miss costs a stalled agent.
2. **Losing the thread.** Every switch into a session starts with the same question: "What was this one doing?"
3. **Scattered history.** Yesterday's decision is in one of hundreds of transcript files. On the author's Mac: 502 files and 13,889 messages in 1.4 GB, from Claude Code, Codex and pi. Claude Code deletes transcripts after 30 days by default, and 281 of 424 sessions were already gone.
4. **Loud interfaces.** Saturated themes, badges, rings, tabs that reorder and large settings screens add stress to work that is already demanding.
5. **Output that is hard to use.** Copying one table cell copies the whole row. Clicking a path rarely opens the right file at the right line.

All five share a root: constant, low agitation from keeping track of work instead of doing it.

## The shift

| Before agents | With agents |
|---|---|
| One shell, one task | 5 to 10 long-running sessions across several projects |
| The developer types | The developer reads, approves and steers |
| A tab is a place to work | A tab is a place to check |
| History is a shell's scrollback | History is hundreds of transcripts in four agents' folders |

## The idea

**A terminal built for the one who watches, not the one who types.** Its unit is the session, a conversation with a goal, a folder and an agent, and its first-class concept is attention: what waits for you, and nothing else. The agents keep their own interfaces. Calm improves the space around them.

## What we want

- **Know at a glance, with no clicking.** The state of every session is visible all the time, and only "needs you" sends a notification. This is the answer to tracking many terminals, and to loud interfaces too, because everything else stays quiet.
- **Come back without rebuilding the context.** Switching into a session shows what it was doing and what it last asked. Sessions survive quitting the app, and one search finds any past conversation, across every agent, and resumes it.
- **Calm by default.** Soft themes, gentle motion and few settings. A good default beats an option.
- **Read output where it appears.** ⌘-click opens a path at its line, ⌥-click copies one table cell, and a files column shows what an agent changed.

## How it works

Three agents run in two projects. The sidebar shows one card for each:

- A blue card says what the agent is doing now ("Reading SessionCard.swift").
- An amber card means it waits for you. It is the only one that sends a notification.
- A sage card means it is done, with a two-line recap of its last message.

⌘⇧A jumps to the waiting session. ⌘K searches every past conversation of every agent, and a right-click resumes or forks the one you find. The exact behavior is in [FEATURES.md](FEATURES.md).

## What we don't want

- **An IDE.** Editing and code review belong in the user's editor.
- **An agent.** The agents bring their own chat. Calm makes no model calls.
- **A platform.** No accounts, cloud or relays. The agents' own remote features and SSH cover remote access.
- **A settings maze.** When an option needs a paragraph to explain, the default is wrong.
- **Cross-platform.** Calm is macOS only, so it can be native.

For the full list, see [FEATURES.md → Not planned](FEATURES.md#not-planned).

## Who it is for

Developers on macOS who run several CLI coding agents in parallel every day: Claude Code, Codex, OpenCode and pi. The first user is the author.

## Approach

- **A new Swift codebase on libghostty,** Ghostty's terminal engine. The model is projects → sessions → panes, with attention as a first-class concept.
- **Native:** SwiftUI and AppKit, Mac conventions, Apple silicon.
- **Agents through adapters:** one small adapter per agent. The core never special-cases an agent.
- **Local only:** no server, no account. All state is in files on the Mac.
- **Built on what exists:** zmx keeps shells alive, SQLite FTS5 indexes the search, Ghostty's macOS app (MIT) shows the known pitfalls. Calm copies no code. The engine patches come unchanged from a Ghostty fork (MIT) and are credited in NOTICE.

## Risks

| Risk | What reduces it |
|---|---|
| A new codebase takes longer than a fork | Ship a usable plain terminal first (ROADMAP.md → M1), then add features to a working app. |
| Terminal-embedding bugs that others already solved | Study Ghostty's macOS app for known pitfalls before writing each layer. |
| Agents change their transcript formats without notice | One small adapter per agent, each with tests on real transcripts. A failure shows less, never crashes. |
| Scope creep toward a platform | "What we don't want" above, and the test in PHILOSOPHY.md. |

## How we know it works

[GOALS.md](GOALS.md) holds the checks. The headline ones: 0 tab switches to find a waiting agent, 0 missed "needs you", search under 50 ms, and a cost at rest held to a budget.
