#!/usr/bin/env bash
# Builds Calm (Release) from this checkout and installs it.
#   ./install.sh                     # into /Applications, `calm` linked into ~/.local/bin
#   ./install.sh --dir ~/Applications --bin-dir /usr/local/bin
#   ./install.sh --no-cli            # skip the `calm` link (Calm's own shells have $CALM_CLI anyway)
#
# A running Calm is left alone: the app is swapped on disk and the running one keeps going on
# the old version until you restart it, so this is safe to run from inside Calm.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
cd "$root"

app_dir="/Applications"
bin_dir="$HOME/.local/bin"
link_cli=1

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) app_dir="${2:?--dir needs a folder}"; shift 2 ;;
    --bin-dir) bin_dir="${2:?--bin-dir needs a folder}"; shift 2 ;;
    --no-cli) link_cli=0; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "install.sh: unknown option $1" >&2; usage >&2; exit 64 ;;
  esac
done

step() { printf '\033[1m==>\033[0m %s\n' "$*"; }

command -v mise >/dev/null 2>&1 || { echo "install.sh: needs mise (https://mise.jdx.dev)" >&2; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "install.sh: needs Xcode" >&2; exit 1; }

# Tools, GhosttyKit, zmx and the Xcode project. Each step is cached, so repeat runs are quick.
step "Preparing tools and GhosttyKit"
# Running this checkout's installer is consent to its pinned tools (fresh clones start untrusted).
mise trust --quiet "$root/mise.toml"
mise install --quiet
eval "$(mise env --shell bash)"
scripts/ghosttykit.sh
scripts/zmx.sh
xcodegen generate --quiet

# A separate derived-data folder, so the Debug build and self-tests are left alone.
step "Building Calm (Release)"
derived="$root/build/DerivedData-Release"
pretty() { if command -v xcbeautify >/dev/null 2>&1; then xcbeautify --quiet; else cat; fi; }
xcodebuild -project Calm.xcodeproj -scheme Calm -configuration Release \
  -derivedDataPath "$derived" -destination "platform=macOS,arch=arm64" build | pretty
built="$derived/Build/Products/Release/Calm.app"
[[ -d "$built" ]] || { echo "install.sh: build finished but $built is missing" >&2; exit 1; }

target="$app_dir/Calm.app"

# Copy next to the old app first, then swap, so a failed copy never leaves no Calm at all.
# A running Calm keeps its already-loaded code (the old files live on until it exits); the
# resources it reads later, such as zmx and themes, come from the new bundle.
step "Installing to $target"
mkdir -p "$app_dir"
staging="$app_dir/.Calm.app.installing"
rm -rf "$staging"
ditto "$built" "$staging"
rm -rf "$target"
mv "$staging" "$target"

if [[ $link_cli -eq 1 ]]; then
  mkdir -p "$bin_dir"
  ln -sf "$target/Contents/Resources/bin/calm" "$bin_dir/calm"
  step "Linked $bin_dir/calm"
  case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *) echo "    Note: $bin_dir isn't on your PATH." ;;
  esac
fi

version="$(defaults read "$target/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")"
step "Calm $version ($(git rev-parse --short HEAD)) installed."
if pgrep -xq Calm; then
  echo "    Calm is still running the old version. Quit and reopen it when you're ready; your shells stay alive."
fi
