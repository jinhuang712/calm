# Calm Terminal

A minimal macOS terminal that keeps you calm and focused.

Calm is built for days spent supervising CLI coding agents such as Claude Code, Codex, OpenCode and pi. Calm stays a terminal: the agents keep their own interfaces. Calm shows which session needs you, restores any thread where you left it, and finds any past conversation.

> **Status: [0.1.2](CHANGELOG.md), a public preview.** Only the author has used it (since 2026-09-29), so expect rough edges (see [Known limits](#known-limits)). Install it with [one line](#one-line), [Homebrew](#homebrew) or the [disk image](#download), or [build it from source](#build-from-source).

## What it does

- **Shows which session needs you.** The sidebar shows if each agent is working, needs you, is done or has failed. Only *needs you* sends a notification.
- **Keeps sessions alive.** When you quit Calm, it detaches your shells. When you relaunch, every session, split and running agent returns.
- **Starts your agent with one key.** ⌘N opens a session with Claude Code, or the agent you choose, and your options. ⌘T opens a plain shell.
- **Groups by project.** Calm files each session under its project or folder. Scratch sessions (⌘⇧N) are for throwaway work.
- **Finds any past conversation.** ⌘K searches the history of every agent. You can resume a conversation or fork it into a new split.
- **Finds in a session.** ⌘F marks every match and maps the matches along the pane edge. In a full-screen agent, it searches everything the session showed.
- **Helps reading.** ⌘-click opens a path at its line. ⌥-click copies a table cell. A files column and a viewer show what an agent changed.
- **Stays quiet by default.** Calm has soft themes, gentle motion and few settings.

[FEATURES.md](FEATURES.md) describes the exact behavior.

## Install

Calm needs macOS 14.5 or later on Apple silicon.

### One line

```sh
curl -fsSL https://raw.githubusercontent.com/jinhuang712/calm/main/get.sh | bash
```

[`get.sh`](get.sh) downloads the newest release, puts Calm in Applications and links the `calm` command into `~/.local/bin`.
It also removes the macOS download mark, because Apple has not signed Calm.
To update, choose Update and Restart in the `↑` notice of the sidebar, or run the script again.
A running Calm keeps the old version until you choose Calm → Restart Calm. Your shells keep running.
`| bash -s -- --help` lists the options: a version, the newest build of `main`, another folder, and no `calm` link.

### Homebrew

```sh
brew install --cask jinhuang712/tap/calm
/usr/bin/xattr -dr com.apple.quarantine /Applications/Calm.app
```

The `xattr` line removes the download mark. Use the one in `/usr/bin`, because the Homebrew `xattr` package has no `-r`.
The cask also puts `calm` on your `PATH`. If Calm is already in Applications, add `--force` to `brew install`.
To update, run `brew upgrade --cask calm`, run the `xattr` line again, and choose Calm → Restart Calm.

### Download

1. Download `Calm-<version>.dmg` from [Releases](https://github.com/jinhuang712/calm/releases), open it, and drag Calm onto Applications.
2. Run `/usr/bin/xattr -dr com.apple.quarantine /Applications/Calm.app` once to remove the download mark.
3. Open Calm. To type `calm` in a terminal, run `mkdir -p ~/.local/bin && ln -sf /Applications/Calm.app/Contents/Resources/bin/calm ~/.local/bin/calm`. Agent hooks find the command without this link.

To update, quit Calm, drag the new version over the old one, run the `xattr` line again, and open Calm.

### The newest build of `main`

To try what is not released yet, on a Mac without Xcode, run:

```sh
curl -fsSL https://raw.githubusercontent.com/jinhuang712/calm/main/get.sh | bash -s -- --edge
```

CI builds every commit of `main` after its tests pass and keeps the newest as the `edge` [pre-release](https://github.com/jinhuang712/calm/releases/tag/edge).
`--edge` installs it with the same steps and restart as the one line.
Its version is the last release plus the commit (`0.1.0-dc970ac`), shown by Calm → Diagnostics and `calm --version`.
The build changes with every push and can be rough. The update notice counts it as the release it follows. A new release replaces it.

### Build from source

Requirements: Xcode 26 with its Metal Toolchain, and [mise](https://mise.jdx.dev).

```sh
git clone https://github.com/jinhuang712/calm.git && cd calm
xcodebuild -downloadComponent MetalToolchain   # once, for Ghostty's shaders
mise run setup                                 # tools, GhosttyKit, zmx, Xcode project
mise run build                                 # or: mise run run
mise run test
```

The first `setup` builds the Ghostty engine and takes about 8 minutes on a 3-core machine. Later runs reuse the cache.
`./install.sh` builds a Release copy into `/Applications` and links `calm` into `~/.local/bin`. `--help` lists the options.
It does not quit a running Calm. Choose Calm → Restart Calm soon: the old Calm's shells can lose access to Documents, Desktop and Downloads.
`--restart` quits and reopens Calm instead. Your shells stay alive either way.

### Uninstall

Quitting Calm keeps your shells running. Close the sessions you want to end first (⌘W). Then remove Calm:

- **Homebrew:** run `brew uninstall --cask calm`. Add `--zap` to also trash the settings and saved sessions.
- **Other installs:** drag Calm to the Trash, and run `rm ~/.local/bin/calm` if you linked it. Settings are in `~/.config/calm`. Saved sessions are in `~/Library/Application Support/Calm`.

Calm adds files to agent folders only for what you turned on in **Calm → Agents…** (Connect for pi, OpenCode and Codex, Send with ⌘ Return). Turn these off there first.

### Good to know

- **Calm is signed ad hoc.** To macOS, every install is a new app, so macOS asks again for Desktop, Documents and Downloads access. A notarized Developer ID build is planned (see [ROADMAP.md](ROADMAP.md)).
- **Agents need no setup to be seen.** Calm detects them from their process. For exact state, connect hooks in **Calm → Agents…**. Connecting also teaches the agent the `calm` command. Each connection asks first and can be undone.
- **Calm is a terminal and nothing more.** It has no chat, editor, browser or account. Its code uses the network only for updates.
- Once a day, Calm asks GitHub for the newest release and sends only its version. Settings → General → Check for updates turns this off.
- When you choose Update and Restart, Calm downloads the release by running `get.sh`.
- The agents you run talk to their own services. The file viewer loads what a file points to (a Markdown image, HTML scripts), as a browser does.

## Known limits

- Apple has not signed the download, so each update asks again for folder access. Homebrew's own cask list takes only signed apps, so Calm has its own tap.
- Nobody has checked the first minute of a new user. Settings has more options than its budget allows (FEATURES.md → F11).
- The OpenCode plugin, which reports state, has had no real use yet.
- A window left in full screen can come back filled but not in full screen. The cause is unknown.
- A link set with OSC 8 gets no dotted mark. Calm does not join some links that a program cut across lines.
- There is no VoiceOver pass, and VoiceOver support is not a goal.

## Reporting a problem

Open an [issue](https://github.com/jinhuang712/calm/issues). **⌘P → Dump Logs** writes a text file with the version, settings and session states.
It holds only ids, states and counts, never a folder, a title or a word that anyone wrote. It is safe to attach.

## Documents

[Proposal](PROPOSAL.md) (problem and plan), [Philosophy](PHILOSOPHY.md) (what "calm" means), [Goals](GOALS.md) (measurable goals),
[Features](FEATURES.md) (exact behavior), [UI and UX](UIUX.md) (layout, states, motion, color),
[Designs](DESIGNS.md) (architecture), [Roadmap](ROADMAP.md) (milestones and what is left).

## Inspiration

This project follows **calm technology**: technology that stays in the periphery and moves to the center of your attention only when it matters.

- Mark Weiser and John Seely Brown, *Designing Calm Technology* (Xerox PARC, 1995)
- Kevin Pu et al., *Assistance or Disruption? Exploring and Evaluating the Design and Trade-offs of Proactive AI Programming Support* (CHI 2025). Quiet presence indicators reduce disruption when you work with AI agents.
- Calm's terminal engine is libghostty from [Ghostty](https://github.com/ghostty-org/ghostty).

## License

[Apache-2.0](LICENSE). See [NOTICE](NOTICE) for third-party attributions.
