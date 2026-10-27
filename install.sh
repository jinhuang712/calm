#!/usr/bin/env bash
# Builds Calm (Release) from this checkout and installs it.
#   ./install.sh                     # into /Applications, `calm` linked into ~/.local/bin
#   ./install.sh --dir ~/Applications --bin-dir /usr/local/bin
#   ./install.sh --no-cli            # skip the `calm` link (Calm's own shells have $CALM_CLI anyway)
#   ./install.sh --restart           # also quit a running Calm and open the new one
#
# A running Calm isn't quit, but it is out of date once the new app is on disk. Until it
# restarts, its shells can lose access to Documents, Desktop and Downloads ("Operation not
# permitted", seen 2026-10-01; to macOS every ad-hoc build is a new app). So restart soon:
# Calm → Restart Calm, or --restart here, which quits it and opens the new one. Quitting only
# detaches shells (zmx keeps them alive), so that's safe from inside Calm too. What the old
# Calm reads in the meantime (themes, the viewer, zmx) stays compatible.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
cd "$root"

app_dir="/Applications"
bin_dir="$HOME/.local/bin"
link_cli=1
restart=0

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) app_dir="${2:?--dir needs a folder}"; shift 2 ;;
    --bin-dir) bin_dir="${2:?--bin-dir needs a folder}"; shift 2 ;;
    --no-cli) link_cli=0; shift ;;
    --restart) restart=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "install.sh: unknown option $1" >&2; usage >&2; exit 64 ;;
  esac
done

step() { printf '\033[1m==>\033[0m %s\n' "$*"; }

# The copy a running Calm was moved aside to goes the moment that Calm quits. Calm 0.1.2 and later
# delete it themselves once they've exited (Calm/App/Restart.swift). An older one reopens by the
# path it started from (Calm → Restart Calm), and macOS started the moved copy again rather than
# the new one there (2026-10-12, twice in a row; RUNBOOK.md → Installing under a running Calm). So this leaves a
# waiter behind, which sleeps in zsh's own zselect, starting no process: every 20 ms for an
# older Calm, to come before its restart's reopen (that looks every 0.1 s), and once a second for
# a newer one, whose own cleanup it only backs up (a crash, a kill). The program file goes first:
# without it macOS can't start that copy. get.sh has the same function.
remove_once_quit() { # <moved copy> <the version it says> <pid>...
  local moved="$1" version="$2" tick=2
  shift 2
  if [[ "${version%%-*}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    local major=$((10#${BASH_REMATCH[1]})) minor=$((10#${BASH_REMATCH[2]})) patch=$((10#${BASH_REMATCH[3]}))
    if ((major > 0 || minor > 1 || (minor == 1 && patch >= 2))); then tick=100; fi
  fi
  # shellcheck disable=SC2016 # the script expands its own arguments, in zsh
  nohup /bin/zsh -c '
    zmodload zsh/zselect
    tick=$1 moved=$2
    shift 2
    for pid in "$@"; do
      while kill -0 $pid 2>/dev/null; do zselect -t $tick; done
    done
    /bin/rm -f "$moved/Contents/MacOS/Calm"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$moved" >/dev/null 2>&1
    /bin/rm -rf "$moved"
  ' calm-moved-copy "$tick" "$moved" "$@" </dev/null >/dev/null 2>&1 &
}

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
products="$derived/Build/Products/Release"
built="$products/Calm.app"
pretty() { if command -v xcbeautify >/dev/null 2>&1; then xcbeautify --quiet; else cat; fi; }
# The app is put together afresh each time (a few seconds; compiling stays incremental): once,
# an incremental build kept a stale copy of a package's resource bundle inside it, and installed
# a Calm without the files that commit added (2026-10-07; not reproduced since).
rm -rf "$built"
xcodebuild -project Calm.xcodeproj -scheme Calm -configuration Release \
  -derivedDataPath "$derived" -destination "platform=macOS,arch=arm64" build | pretty
[[ -d "$built" ]] || { echo "install.sh: build finished but $built is missing" >&2; exit 1; }
# Each package resource bundle inside the app must be the one just built.
for bundle in "$products"/*.bundle; do
  [[ -e "$bundle" ]] || continue
  if ! diff -rq "$bundle" "$built/Contents/Resources/$(basename "$bundle")" >/dev/null; then
    echo "install.sh: $(basename "$bundle") in Calm.app differs from the one just built; not installing" >&2
    exit 1
  fi
done

target="$app_dir/Calm.app"
was_running=0
if pgrep -xq Calm; then
  was_running=1
fi
if [[ $was_running -eq 1 && $restart -eq 1 ]]; then
  step "Quitting Calm"
  osascript -e 'tell application id "com.jinhuang.calm" to quit' >/dev/null 2>&1 || true
  for _ in {1..50}; do pgrep -xq Calm || break; sleep 0.2; done
  if pgrep -xq Calm; then
    echo "install.sh: Calm is still running (a dialog may be open). Quit it and run again." >&2
    exit 1
  fi
fi

# Copy next to the old app first, then swap with two renames, so a failed copy never leaves no
# Calm at all. The old app is moved aside, not deleted, while a Calm still runs from it: a
# running app whose own file is gone can't show macOS who it is, and macOS refuses it the
# folder picker (New Project did nothing, 2026-10-07: SecCodeCopyGuestWithAttributes failed,
# ENOENT). Moved, the file is found under its new name (`codesign -vv <pid>` stays valid).
# The moved copy goes once that Calm quits (remove_once_quit, above).
step "Installing to $target"
mkdir -p "$app_dir"
staging="$app_dir/.Calm.app.installing"
rm -rf "$staging"
ditto "$built" "$staging"
if [[ -e "$target" ]]; then
  mv "$target" "$app_dir/.Calm.app.previous-$(date +%Y%m%d-%H%M%S)-$$"
fi
mv "$staging" "$target"
# Only the installed copy may be the Calm macOS starts by bundle ID (the Dock, Spotlight, a
# notification, the dialog for an app it hasn't seen): every copy registered for the ID is a
# candidate, and on 2026-10-07 a restart came back as a day-old Release build left in an old
# worktree. So the build it was copied from goes (the next install puts it together afresh
# anyway), and the installed one is registered.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -u "$built" >/dev/null 2>&1 || true
rm -rf "$built"
"$lsregister" -f "$target" >/dev/null 2>&1 || true
# lsof names each running Calm's program file where it is now, moved or not. A copy nothing runs
# from goes now; one a Calm runs from goes once it quits.
listing="$(lsof -a -c Calm -d txt -Fpn 2>/dev/null || true)"
for old in "$app_dir"/.Calm.app.previous*; do
  [[ -e "$old" ]] || continue
  pids="$(awk -v dir="$old/" '/^p/ { pid = substr($0, 2) } /^n/ && index(substr($0, 2), dir) == 1 { print pid }' <<<"$listing" | sort -u | tr '\n' ' ')"
  if [[ -z "${pids// /}" ]]; then
    rm -rf "$old"
  else
    # shellcheck disable=SC2086 # one argument per pid
    remove_once_quit "$old" "$(defaults read "$old/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)" $pids
  fi
done

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
installed="Calm $version ($(git rev-parse --short HEAD)) installed."
if [[ $was_running -eq 1 && $restart -eq 1 ]]; then
  step "Opening Calm"
  open "$target"
  step "$installed"
elif [[ $was_running -eq 1 ]]; then
  step "$installed Restart Calm soon (Calm → Restart Calm): until then the running one is out of date, and its shells can lose access to Documents, Desktop and Downloads."
else
  step "$installed"
fi
