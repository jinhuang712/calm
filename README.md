# Calm Terminal

A minimal macOS terminal that keeps you calm and focused.

Calm is built for days spent supervising CLI coding agents such as Claude Code, Codex, OpenCode and pi. It stays a terminal: the agents keep their own interfaces. Calm quietly shows which session needs you, helps you pick up any thread where you left it, and finds any past conversation in seconds.

> **Status:** pre-alpha. See the [roadmap](ROADMAP.md) for what works so far.

## Build from source

Requirements: macOS 26 on Apple silicon, Xcode 26 with its Metal Toolchain, and [mise](https://mise.jdx.dev).

```sh
xcodebuild -downloadComponent MetalToolchain   # once, for Ghostty's shaders
mise run setup                                 # tools, GhosttyKit, Xcode project
mise run build                                 # or: mise run run
mise run test
```

The first `setup` builds Ghostty's engine from source and takes a while; later runs reuse the cached build.

To install, `./install.sh` builds a Release copy into `/Applications` and links the `calm` command into `~/.local/bin` (`--help` for options). A running Calm is left alone and the new version starts the next time you open Calm, or when you choose Calm → Restart Calm; `--restart` quits and reopens it instead (your shells stay alive either way).

## Documents

- [Proposal](PROPOSAL.md) — the problem and the plan
- [Philosophy](PHILOSOPHY.md) — what "calm" means here
- [Goals](GOALS.md) — goals, non-goals, success criteria
- [Features](FEATURES.md) — exact behavior of each feature
- [UI and UX](UIUX.md) — layout, states, motion, color
- [Designs](DESIGNS.md) — architecture and technical design
- [Roadmap](ROADMAP.md) — phases and milestones

## Inspiration

This project is guided by the idea of **calm technology**: technology that stays in the periphery and moves to the center of your attention only when it matters.

- Mark Weiser & John Seely Brown, *Designing Calm Technology* (Xerox PARC, 1995)
- Kevin Pu et al., *Assistance or Disruption? Exploring and Evaluating the Design and Trade-offs of Proactive AI Programming Support* (CHI 2025), showing that quiet presence indicators and context reduce disruption when working alongside AI agents.

Calm's terminal engine is [Ghostty](https://github.com/ghostty-org/ghostty)'s libghostty.

## License

[Apache-2.0](LICENSE). See [NOTICE](NOTICE) for third-party attributions.
