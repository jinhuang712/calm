# Calm Terminal

A minimal macOS terminal that keeps you calm and focused.

Calm is built for days spent supervising CLI coding agents such as Claude Code, Codex, OpenCode and pi. It stays a terminal: the agents keep their own interfaces. Calm quietly shows which session needs you, helps you pick up any thread where you left it, and finds any past conversation in seconds.

> **Status: [0.1.0](CHANGELOG.md), a public preview.** Its author has used it as their only terminal since 2026-09-29, and nobody else has yet, so expect rough edges (see [Known limits](#known-limits)). Install it with [one line](#one-line), [Homebrew](#homebrew) or the [disk image](#download), or [build it from source](#build-from-source).

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

### One line

```sh
curl -fsSL https://raw.githubusercontent.com/jinhuang712/calm/main/get.sh | bash
```

[`get.sh`](get.sh) downloads the newest release's disk image, puts Calm in Applications, takes macOS's download mark off (Calm isn't signed by Apple yet, so macOS won't open it with the mark on), and links the `calm` command into `~/.local/bin`. Run it again to update; a running Calm keeps going on the old version until you choose Calm → Restart Calm (your shells keep running). `| bash -s -- --help` lists its options: a version, the newest build of `main` (below), another folder, no `calm` link.

### Homebrew

```sh
brew install --cask jinhuang712/tap/calm
/usr/bin/xattr -dr com.apple.quarantine /Applications/Calm.app
```

Calm isn't signed by Apple yet, so macOS won't open it as downloaded: the `xattr` line takes the download mark off (the one in `/usr/bin`: Homebrew's own `xattr` package has no `-r`). The cask also puts the `calm` command on your `PATH`. If Calm is already in Applications (from the disk image or `./install.sh`), add `--force` to the first `brew install` to replace it.

To update, run `brew upgrade --cask calm`, the `xattr` line again, and Calm → Restart Calm (your shells keep running).

### Download

1. Download `Calm-<version>.dmg` from the newest release on [Releases](https://github.com/jinhuang712/calm/releases), open it, and drag Calm onto Applications.
2. Calm isn't signed by Apple yet, so macOS won't open it as downloaded. Run this once in Terminal to take the download mark off:

   ```sh
   /usr/bin/xattr -dr com.apple.quarantine /Applications/Calm.app
   ```

3. Open Calm. To type the `calm` command in a terminal, Calm's included, link it into a folder on your `PATH`, here `~/.local/bin` (agents' hooks find it without this):

   ```sh
   mkdir -p ~/.local/bin && ln -sf /Applications/Calm.app/Contents/Resources/bin/calm ~/.local/bin/calm
   ```

To update, quit Calm (your shells keep running), drag the new version over the old one, run the `xattr` line again, and open Calm.

### The newest build of `main`

To try what isn't released yet, on a Mac that has no Xcode to build with:

```sh
curl -fsSL https://raw.githubusercontent.com/jinhuang712/calm/main/get.sh | bash -s -- --edge
```

CI builds every commit of `main` once its tests pass and keeps the newest as the `edge` [pre-release](https://github.com/jinhuang712/calm/releases/tag/edge); `--edge` installs it the way the one line installs a release (the same steps, the same restart). It is not a release: its version is the last release's with the commit it was built from (`0.1.0-dc970ac`, which Calm → Diagnostics and `calm --version` show), it changes with every push to `main`, and it can be rough. Run it again for the next build. The update notice counts it as the release it follows, so it tells you about the next release and never about the one you are already past, and the one line without `--edge` still installs the newest release. When a release comes out, the edge build is replaced by one of the new version.

### Build from source

Requirements: Xcode 26 with its Metal Toolchain, and [mise](https://mise.jdx.dev).

```sh
git clone https://github.com/jinhuang712/calm.git && cd calm
xcodebuild -downloadComponent MetalToolchain   # once, for Ghostty's shaders
mise run setup                                 # tools, GhosttyKit, zmx, Xcode project
mise run build                                 # or: mise run run
mise run test
```

The first `setup` builds Ghostty's engine from source, about 8 minutes on a 3-core machine; later runs reuse the cached build.

To install, `./install.sh` builds a Release copy into `/Applications` and links the `calm` command into `~/.local/bin` (`--help` for options). A running Calm isn't quit; the new version starts the next time you open Calm, or when you choose Calm → Restart Calm, which is worth doing soon, because until then the running Calm is out of date and its shells can lose access to Documents, Desktop and Downloads. `--restart` quits and reopens it instead (your shells stay alive either way).

### Uninstall

Quitting Calm keeps your shells running, so close the sessions you want ended first (⌘W). Then:

- **Homebrew:** `brew uninstall --cask calm`. Add `--zap` to also move Calm's settings and saved sessions to the Trash.
- **One line, disk image or `./install.sh`:** drag Calm from Applications to the Trash, and `rm ~/.local/bin/calm` if it's linked. Calm keeps its settings in `~/.config/calm` and its saved sessions in `~/Library/Application Support/Calm`.

Calm adds files to an agent's own folders only for what you turned on in **Calm → Agents…** (Connect for pi and OpenCode, Send with ⌘ Return). Turn those off there before uninstalling.

### Good to know

- **Calm is signed ad hoc**, downloaded or built yourself, so to macOS every install is a new app: it asks again for access to Desktop, Documents and Downloads after each one. A Developer ID signed and notarized download, which keeps those answers across updates, comes later (see the end of [ROADMAP.md](ROADMAP.md)).
- **Agents need no setup to be seen.** Calm detects them from their process. To get their exact state (a question waiting, a turn finished), connect their hooks from **Calm → Agents…**; each one asks first and can be undone.
- **A terminal, not more.** Calm has no chat, editor or browser of its own, and no account. Its own code makes one network request: once a day it asks GitHub which release of Calm is newest, sending only its version, and Settings → General → Check for updates turns that off. The agents you run talk to their services as they always did, and the file viewer loads what a viewed file points to (a Markdown image, an HTML page's scripts), as a browser would.

## Known limits

- Apple silicon and macOS 26 or later only.
- The download isn't signed by Apple: opening it takes the `xattr` line above (`get.sh` runs it for you), from Homebrew too, and each update asks again for folder access. So Calm isn't in Homebrew's own list of casks, which takes only signed apps; it comes from its own tap.
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
