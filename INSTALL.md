<!-- what-we-build: approved 2026-10-28 -->

# Install

Calm needs macOS 14.5 or later on Apple silicon. The fastest way is the one line in [README.md](README.md#-install). This page has every other way, and how to update and remove Calm. The commands were copied from the earlier README and are not yet verified in this rewrite.

## One line

```sh
curl -fsSL https://raw.githubusercontent.com/jinhuang712/calm/main/get.sh | bash
```

[`get.sh`](get.sh) downloads the newest release, puts Calm in Applications and links the `calm` command into `~/.local/bin`. It also removes the macOS download mark, because Apple has not signed Calm.

To update, choose **Update and Restart** in the `↑` notice of the sidebar, or run the script again. A running Calm keeps the old version until you choose **Calm → Restart Calm**. Your shells keep running.

`| bash -s -- --help` lists the options: a version, the newest build of `main`, another folder, and no `calm` link.

## Homebrew

```sh
brew install --cask jinhuang712/tap/calm
/usr/bin/xattr -dr com.apple.quarantine /Applications/Calm.app
```

The `xattr` line removes the download mark. Use the one in `/usr/bin`, because the Homebrew `xattr` package has no `-r`. The cask also puts `calm` on your `PATH`. If Calm is already in Applications, add `--force` to `brew install`.

To update, run `brew upgrade --cask calm`, run the `xattr` line again, and choose **Calm → Restart Calm**.

## The disk image

1. Download `Calm-<version>.dmg` from [Releases](https://github.com/jinhuang712/calm/releases), open it, and drag Calm onto Applications.
2. Run `/usr/bin/xattr -dr com.apple.quarantine /Applications/Calm.app` once to remove the download mark.
3. Open Calm. To type `calm` in a terminal, run `mkdir -p ~/.local/bin && ln -sf /Applications/Calm.app/Contents/Resources/bin/calm ~/.local/bin/calm`. Agent hooks find the command without this link.

To update, quit Calm, drag the new version over the old one, run the `xattr` line again, and open Calm.

## The newest build of `main`

To try what is not released yet, on a Mac without Xcode:

```sh
curl -fsSL https://raw.githubusercontent.com/jinhuang712/calm/main/get.sh | bash -s -- --edge
```

CI builds every commit of `main` after its tests pass and keeps the newest as the `edge` [pre-release](https://github.com/jinhuang712/calm/releases/tag/edge). `--edge` installs it with the same steps and restart as the one line. Its version is the last release plus the commit (`0.1.0-dc970ac`), shown by Calm → Diagnostics and `calm --version`. The build changes with every push and can be rough. The update notice counts it as the release it follows, and a new release replaces it.

## Build from source

You need Xcode 26 with its Metal Toolchain, and [mise](https://mise.jdx.dev).

```sh
git clone https://github.com/jinhuang712/calm.git && cd calm
xcodebuild -downloadComponent MetalToolchain   # once, for Ghostty's shaders
mise run setup                                 # tools, GhosttyKit, zmx, Xcode project
mise run build                                 # or: mise run run
mise run test
```

The first `setup` builds the Ghostty engine and takes about 8 minutes on a 3-core machine. Later runs reuse the cache.

`./install.sh` builds a Release copy into `/Applications` and links `calm` into `~/.local/bin`. `--help` lists the options. It does not quit a running Calm, so choose **Calm → Restart Calm** soon after it finishes. `--restart` quits and reopens Calm instead. Your shells stay alive either way.

## After you update

Choose **Calm → Restart Calm**. Until then, the old Calm's shells can lose access to Documents, Desktop and Downloads ("Operation not permitted"). Your shells keep running through a restart.

## Uninstall

Quitting Calm keeps your shells running. Close the sessions you want to end first (⌘W). Then remove Calm:

- **Homebrew:** run `brew uninstall --cask calm`. Add `--zap` to also trash the settings and saved sessions.
- **Other installs:** drag Calm to the Trash, and run `rm ~/.local/bin/calm` if you linked it. Settings are in `~/.config/calm`. Saved sessions are in `~/Library/Application Support/Calm`.

Calm adds files to agent folders only for what you turned on in **Calm → Agents…** (Connect for pi, OpenCode and Codex, Send with ⌘ Return). Turn these off there first.

## Good to know

- **Calm is signed ad hoc.** To macOS, every install is a new app, so macOS asks again for Desktop, Documents and Downloads access. A notarized Developer ID build is planned (see [ROADMAP.md](plans/ROADMAP.md)).
- **Agents need no setup to be seen.** Calm detects them from their process. For exact state, connect hooks in **Calm → Agents…**. Connecting also teaches the agent the `calm` command. Each connection asks first and can be undone.
- **Calm uses the network for updates only.** Once a day, it asks GitHub for the newest release and sends only its version. **Settings → General → Check for updates** turns this off. When you choose Update and Restart, Calm downloads the release by running `get.sh`. The agents you run talk to their own services, and the file viewer loads what a file points to (a Markdown image, HTML scripts), as a browser does.

How releases and the installers are built is in [RUNBOOK.md](RUNBOOK.md).
