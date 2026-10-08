# Calm Terminal

A minimal macOS terminal that keeps you calm and focused.

Calm is built for days spent supervising CLI coding agents such as Claude Code, Codex, OpenCode and pi. It stays a terminal: the agents keep their own interfaces. Calm quietly shows which session needs you, helps you pick up any thread where you left it, and finds any past conversation in seconds.

> **Status: [0.1.0](CHANGELOG.md), a public preview.** Its author has used it as their only terminal since 2026-09-29, and nobody else has yet, so expect rough edges (see [Known limits](#known-limits)). Download it from [Releases](https://github.com/jinhuang712/calm/releases), or build it from source.

## What it does

- **Shows which session needs you.** Every session in the sidebar says whether its agent is working, needs you, is done or failed, for Claude Code, Codex, OpenCode and pi. Only *needs you* ever notifies.
- **Keeps sessions alive.** Quitting Calm detaches your shells instead of killing them; relaunching brings back every session, split and running agent.
- **Starts your agent with one key.** ⌘N opens a session running Claude Code, or the agent you choose, with the options you picked (skip permissions, a new worktree); ⌘T is a plain shell.
- **Groups by project, by itself.** Sessions file under the project or folder they work in; scratch sessions (⌘⇧N) are for throwaway work.
- **Finds any past conversation.** ⌘K searches every agent's history; a past conversation can be resumed, or forked into a new split.
- **Finds in a session.** ⌘F marks every match and maps them along the pane's edge, and in a full-screen agent it searches everything the session showed, not only the screen.
- **Is comfortable to read in.** ⌘-click opens a path at its line, ⌥-click copies a table cell, and a files column and viewer show what an agent changed.
- **Is quiet by default.** Soft themes, gentle motion and very few settings.

Exact behavior is in [FEATURES.md](FEATURES.md).

## Install

Calm needs macOS 26 on Apple silicon.

### Homebrew

```sh
brew install --cask jinhuang712/tap/calm
xattr -dr com.apple.quarantine /Applications/Calm.app
```

Calm isn't signed by Apple yet, so macOS won't open it as downloaded: the `xattr` line takes the download mark off. The cask also puts the `calm` command on your `PATH`. To update, run `brew upgrade --cask calm`, the `xattr` line again, and Calm → Restart Calm (your shells keep running).

### Download

1. Download `Calm-<version>.dmg` from the newest release on [Releases](https://github.com/jinhuang712/calm/releases), open it, and drag Calm onto Applications.
2. Calm isn't signed by Apple yet, so macOS won't open it as downloaded. Run this once in Terminal to take the download mark off:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Calm.app
   ```

3. Open Calm. To use the `calm` command in other terminals too (Calm's own shells have it):

   ```sh
   mkdir -p ~/.local/bin && ln -sf /Applications/Calm.app/Contents/Resources/bin/calm ~/.local/bin/calm
   ```

To update, quit Calm (your shells keep running), drag the new version over the old one, run the `xattr` line again, and open Calm.

### Build from source

Requirements: Xcode 26 with its Metal Toolchain, and [mise](https://mise.jdx.dev).

```sh
xcodebuild -downloadComponent MetalToolchain   # once, for Ghostty's shaders
mise run setup                                 # tools, GhosttyKit, zmx, Xcode project
mise run build                                 # or: mise run run
mise run test
```

The first `setup` builds Ghostty's engine from source, about 8 minutes on a 3-core machine; later runs reuse the cached build.

To install, `./install.sh` builds a Release copy into `/Applications` and links the `calm` command into `~/.local/bin` (`--help` for options). A running Calm isn't quit; the new version starts the next time you open Calm, or when you choose Calm → Restart Calm, which is worth doing soon, because until then the running Calm is out of date and its shells can lose access to Documents, Desktop and Downloads. `--restart` quits and reopens it instead (your shells stay alive either way).

### Good to know

- **Calm is signed ad hoc**, downloaded or built yourself, so to macOS every install is a new app: it asks again for access to Desktop, Documents and Downloads after each one. A Developer ID signed and notarized download, which keeps those answers across updates, comes later (see the end of [ROADMAP.md](ROADMAP.md)).
- **Agents need no setup to be seen.** Calm detects them from their process. To get their exact state (a question waiting, a turn finished), connect their hooks from **Calm → Agents…**; each one asks first and can be undone.
- **A terminal, not more.** Calm has no chat, editor or browser of its own, and no account. Its own code makes no network requests, and there is no update check yet. The agents you run talk to their services as they always did, and the file viewer loads what a viewed file points to (a Markdown image, an HTML page's scripts), as a browser would.

## Known limits

- Apple silicon and macOS 26 or later only.
- The download isn't signed by Apple: opening it takes the `xattr` line above, from Homebrew too, and each update asks again for folder access. So Calm isn't in Homebrew's own list of casks, which takes only signed apps; it comes from its own tap.
- Only the author has used it. How a new user's first minute goes has not been checked, and Settings has a few more options than its budget allows (window options; FEATURES.md → Themes).
- OpenCode's plugin, which reports its state, has not had real use yet.
- A window left in full screen came back filled but not in full screen once in six test launches; the cause isn't known.
- Links: a link a program sets with OSC 8 gets no dotted mark, and a few shapes of link that a program cut across lines aren't joined.
- There is no VoiceOver pass (the labels that exist stay, but it isn't a goal).

## Reporting a problem

Open an [issue](https://github.com/jinhuang712/calm/issues). **⌘P → Dump Logs** writes a text file with Calm's version, settings and each session's state, and only ids, states and counts: never a folder, a title or a word anyone wrote, so it is safe to attach.

## Documents

- [Proposal](PROPOSAL.md) — the problem and the plan
- [Philosophy](PHILOSOPHY.md) — what "calm" means here
- [Goals](GOALS.md) — goals, non-goals, success criteria
- [Features](FEATURES.md) — exact behavior of each feature
- [UI and UX](UIUX.md) — layout, states, motion, color
- [Designs](DESIGNS.md) — architecture and technical design
- [Roadmap](ROADMAP.md) — milestones and what is left

## Inspiration

This project is guided by the idea of **calm technology**: technology that stays in the periphery and moves to the center of your attention only when it matters.

- Mark Weiser & John Seely Brown, *Designing Calm Technology* (Xerox PARC, 1995)
- Kevin Pu et al., *Assistance or Disruption? Exploring and Evaluating the Design and Trade-offs of Proactive AI Programming Support* (CHI 2025), showing that quiet presence indicators and context reduce disruption when working alongside AI agents.

Calm's terminal engine is [Ghostty](https://github.com/ghostty-org/ghostty)'s libghostty.

## License

[Apache-2.0](LICENSE). See [NOTICE](NOTICE) for third-party attributions.
