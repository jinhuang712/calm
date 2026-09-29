# Goals

## Primary goal

Make supervising many CLI coding agents on a Mac feel calm: the user always knows which session needs them, can resume any thread without effort, and never works to keep track of work.

## Goals

| # | Goal | What it looks like |
|---|---|---|
| G1 | **Know without checking** | The state of every session (working, needs you, done, failed) is visible at a glance, without switching tabs |
| G2 | **Never miss a "needs you"** | Every agent request for input reaches the user, at a natural pause |
| G3 | **Resume without effort** | Switching into a session shows what it was doing and what it last asked; sessions survive quitting the app |
| G4 | **Find any past conversation** | A search across all agents' history returns the right session in seconds |
| G5 | **Organized automatically** | Sessions group under their project folder with no manual arranging |
| G6 | **Comfortable reading** | Copying a table cell, opening a path at a line and previewing a file each take one action |
| G7 | **Calm by default** | Soft themes, gentle motion and quiet status out of the box; very few settings |
| G8 | **Every major agent** | Claude Code, Codex, OpenCode and pi are all detected and tracked |
| G9 | **Native and fast** | Launches quickly, feels like a Mac app, renders through libghostty |

## Non-goals

| Non-goal | Why |
|---|---|
| Built-in AI chat or model calls | Agents bring their own interfaces; Calm stays a terminal |
| File editing, code review | Belongs in the user's editor |
| In-app browser, computer use | Playwright and browser tools already do this well |
| Accounts, cloud sync, relays, own mobile app | Agents' own remote features and SSH cover remote access |
| Windows or Linux | macOS-native is the point |
| Configurability for its own sake | Choice overload works against calm |
| Replacing tmux for remote servers | Out of scope; SSH into a remote tmux still works inside Calm |
| A drop-down quick terminal on a global hotkey | Not needed for daily agent work |

## Success criteria

These are checked by the author's daily use, since the first user is the author.

- **Daily driver:** Calm replaces every other terminal for agent work.
- **No tab hunting:** the user no longer clicks through tabs to find which agent is waiting.
- **Thread recovery:** "which session was that?" is answered with one search, most of the time.
- **Settings budget:** the settings screen stays small, and each feature adds at most one or two settings.
- **Stress:** the author reports feeling less agitated during agent-heavy days (subjective, but it is the point).

## Constraints

- macOS 26 or later, Apple silicon only ([DESIGNS.md](DESIGNS.md)).
- Swift and libghostty.
- Apache-2.0. No code copied from other projects; Ghostty (MIT) may be adapted with attribution, and the engine patches come unchanged from a Ghostty fork (MIT), credited in NOTICE.
- Everything stays local: no network calls except updates and what the user's own agents do.
