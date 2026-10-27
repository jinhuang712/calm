<!-- what-we-build: approved 2026-10-28 -->

# Runbook

Calm is not a service, but it has a pipeline that someone must keep working: the build, the release, and the four ways to install it. This page holds the procedures for that pipeline and the first step when a Mac misbehaves. The commands were copied from the earlier DESIGNS.md and are not yet verified in this rewrite. The reasons for the choices are in [DESIGNS.md](DESIGNS.md), and the rules for coding agents in [AGENTS.md](AGENTS.md).

## Build and check

| Step | Command |
|---|---|
| Set up tools, GhosttyKit, zmx and the Xcode project | `mise run setup` (the first run builds the engine, about 8 minutes on a 3-core machine, then it is cached in `~/Library/Caches/calm`) |
| Build, test, lint, format | `mise run build`, `mise run test`, `mise run lint`, `mise run format` |
| Check cost at rest | `mise run perf` (after a change to rendering, animation or timers) |
| Run one self-test, headless | `scripts/selftest.sh <name> [--type …] [--actions …] [--after …]` |
| Take a window snapshot | `scripts/xcode.sh snapshot <out.png> [delay]` |
| Make the README's logo and screenshots again | `DEMO_PROJECT=~/dev/apps/calm scripts/readme-shots.sh` after `mise run build`. Headless, with stand-in sessions, and it writes `assets/`. The Debug build shows the violet mark and a DEV tag |
| Read the trace | `calm trace`, or `/usr/bin/log show --last 5m --predicate 'subsystem == "com.jinhuang.calm" AND category == "trace"'` (plain `log` is a zsh builtin) |

- `Calm.xcodeproj` is generated from `project.yml`. Never edit it by hand.
- Building needs Xcode 26 with its Metal Toolchain (`xcodegen` and Zig are pinned in `mise.toml`).
- `mise run test` runs the package's tests, then the app's, even when the first fails.
- A new worktree has an untrusted `mise.toml`. Prefix each mise command with `MISE_TRUSTED_CONFIG_PATHS=<the worktree's absolute path>`.

## Cut a release

1. Bump the version in `project.yml` and `CLI/main.swift`, and run `xcodegen generate`. `VersionTests` fails when they disagree.
2. Give the version a section in CHANGELOG.md headed `## X.Y.Z — <date>`. Put each paragraph and item on one line, because a release's notes break lines wherever the text does.
3. Land it on `main`.
4. When CI on `main` is green, push the tag on that commit: `git tag vX.Y.Z <sha>`, `git push origin vX.Y.Z`.

`.github/workflows/release.yml` does the rest. It checks the tag, builds from source with no cache (so a release proves a fresh clone builds), tests, makes and checks a disk image (`scripts/disk-image.sh`), and publishes. Then it starts `homebrew.yml` and `get.yml`, and restarts the edge build.

- **Before you push the tag,** run the whole tree's lint, build and test locally. A release once went red on a long line in a pulled commit.
- **If CI fails after the tag,** fix it on `main`, delete the tag, and tag the new commit.

## The four ways to install

The user's steps for each way are in [INSTALL.md](INSTALL.md). This section is how they are built and kept working.

| Way | What it does | Where it is built |
|---|---|---|
| `get.sh` (the one line) | Installs the newest `vMAJOR.MINOR.PATCH` release, checked against the asset's sha256, then swaps the app the way `install.sh` does. Refuses a Calm that Homebrew installed, and a Mac older than macOS 14.5 | The repository's root |
| Homebrew | `brew install --cask jinhuang712/tap/calm`. `homebrew.yml` points the cask in the tap at the release, with a deploy key that can write to the tap only. The cask does not remove the download mark, so its caveats give the `xattr` line | `jinhuang712/homebrew-tap` |
| The disk image | `Calm-<version>.dmg` on the release page | `release.yml` |
| `install.sh` | Builds a Release Calm into `/Applications` and links `calm` into `~/.local/bin` | A local checkout |

- `get.sh` runs `/usr/bin/xattr` by path, because Homebrew's python `xattr` has no `-r`. It runs only from `main()` at its end, so a download cut short runs nothing.
- `install.sh` refuses an app whose resource bundles differ from the ones just built, swaps with two renames so a failed copy never leaves no Calm, and unregisters and deletes the build it copied from.
- Homebrew's own cask list takes only apps that pass Gatekeeper, so Calm has its own tap until it has a Developer ID.

## Edge builds

The newest `main` for a Mac with no Xcode: `curl -fsSL https://raw.githubusercontent.com/jinhuang712/calm/main/get.sh | bash -s -- --edge`.

- `edge.yml` runs when CI ends green on `main`, and publishes one pre-release tagged `edge`. The disk image goes up before the tag moves.
- An edge build's version is the last release's plus the commit (`0.1.0-dc970ac`). The update notice counts it as the release it follows.
- Everything that means "the newest release" must skip `edge`.
- The tag moves with each build. A clone that fetched it needs `git fetch --tags --force`.

## Installing under a running Calm

`./install.sh` and `get.sh` do not quit a running Calm. Until it restarts, a Calm whose app was replaced can lose its shells' access to Documents, Desktop and Downloads ("Operation not permitted", seen 2026-10-01, cause not proven).

1. Install.
2. Tell the user to choose **Calm → Restart Calm** soon, and why.
3. Never pass `--restart`, and never quit or launch the installed Calm yourself.

- The old app is moved aside (`.Calm.app.previous-<time>`) while a Calm runs from it, and Calm 0.1.2 and later remove it when they quit. For an older Calm or a crash, the installers leave a waiter. `scripts/moved-copy-check.sh` measures it, and `get.yml` checks it.
- A real fix waits for a stable signature (Developer ID).

## Move the Ghostty pin

1. Move the three lines of `scripts/ghostty.env` together (`GHOSTTY_REF`, `GHOSTTY_COMMIT`, `GHOSTTY_PATCHES_FROM`). `GHOSTTY_COMMIT` is the upstream parent of the fork commit that the fork patches (0005 and 0006) come from. Update the Zig version in `mise.toml` to match Ghostty's `build.zig.zon`.
2. Refresh 0005 and 0006 from the fork. Never edit them here.
3. Run `scripts/ghosttykit.sh`. A patch that does not apply stops the build, so fix Calm's own patches (0007 and up) one at a time.
4. Run `scripts/licenses.sh`, because the notices of what the engine builds in change with the pin.
5. Run `mise run test` and `mise run perf`.

`scripts/ghostty-patches/README.md` says what each patch does. Zig's packages come from `scripts/ghostty-deps.py`, which uses the copies in `scripts/ghostty-mirror/` first.

## When something is wrong

| Symptom | First step |
|---|---|
| Cards stay gray, or stay on *Working* | `calm doctor`. A second Calm holding the socket is the usual cause |
| A restart shows the wrong state for a while | `calm trace --last 10m` |
| A bug report with no logs | **⌘P → Dump Logs**: ids, states and counts only, safe to attach |
| Shells say "Operation not permitted" in Documents | Calm → Restart Calm (Installing under a running Calm) |
| `get.sh` refuses | Calm was installed by Homebrew. Use `brew upgrade --cask calm` |
| CI fails fetching a Zig package | Add a copy to `scripts/ghostty-mirror/`. Zig checks every package's hash |
| `git fetch --tags` rejects `edge` | `git fetch --tags --force` |
| A Debug build shows "persistent shell exited at once" after a rebuild | A copy over the running app breaks its code signature. Remove the app and copy a fresh one (from earlier notes, not re-checked) |
