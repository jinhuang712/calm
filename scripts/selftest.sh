#!/usr/bin/env bash
# Launch the Debug app once, drive it, capture a snapshot and the screen text, then quit.
# Needs no Screen Recording permission (see Calm/App/SelfTest.swift).
#
#   scripts/selftest.sh <name> [--type TEXT] [--actions a,b,c] [--delay SECONDS] …
#
# Writes $CALM_SELFTEST_OUT/<name>.png, <name>.txt and <name>.log
# (default out dir: /tmp/calm-selftest).
#
# Runs are isolated from a Calm the user may be running: headless by default (no window, no
# focus taken, see Calm/App/Headless.swift), and with their own state file, socket, config,
# generated Ghostty files and zmx directory. The user's Ghostty config is left out unless
# --ghostty-config is given, so runs don't depend on it. Only the instance this script starts is
# ever stopped.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
name="${1:?usage: $0 <name> [--type TEXT] [--actions a,b] [--delay S]}"
shift
out="${CALM_SELFTEST_OUT:-/tmp/calm-selftest}"
mkdir -p "$out"

type_text=""
actions=""
after=""
delay="1.5"
keys=""
drag=""
resize=""
persist=""
state=""
config=""
headless=1
search_home=""
ghostty_config=none
appearance=""
snapshot_window=""
shell="${SHELL:-/bin/zsh}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --type) type_text="$2"; shift 2 ;;
    --actions) actions="$2"; shift 2 ;;
    --after) after="$2"; shift 2 ;;       # actions to run after typing (e.g. calm.new_session)
    --delay) delay="$2"; shift 2 ;;
    --keys) keys="$2"; shift 2 ;;         # typed through real key events; "\r" in the text means Return
    --drag) drag=1; shift ;;              # drag-select the first rows, copy, and log the clipboard
    --resize) resize="$2"; shift 2 ;;     # e.g. 700x420: resize the window and log the grid size
    --persist) persist=1; shift ;;        # keep zmx persistence on (default: off, so runs leave nothing behind)
    --state) state="$2"; shift 2 ;;       # use this state file (default: a fresh one per run)
    --plain-shell) shell=/bin/bash; shift ;; # persistent sessions get no shell integration (no OSC 7)
    --config) config="$2"; shift 2 ;;     # Calm settings text for config.toml (default: none, so defaults)
    --visible) headless=0; shift ;;       # show the window and take focus (default: headless)
    --search-home) search_home="$2"; shift 2 ;; # transcripts to index for search (default: none, never the real home)
    --ghostty-config) ghostty_config=user; shift ;; # read the user's Ghostty config too (default: Calm's defaults only)
    --appearance) appearance="$2"; shift 2 ;; # light or dark instead of the system's
    --window) snapshot_window="$2"; shift 2 ;; # snapshot the window with this title (e.g. Settings)
    *) echo "unknown option $1" >&2; exit 64 ;;
  esac
done

app="$root/build/DerivedData/Build/Products/Debug/Calm.app/Contents/MacOS/Calm"

if [[ -z "$state" ]]; then
  state="$out/$name.state.json"
  rm -f "$state"
fi

config_file="$out/$name.config.toml"
printf '%b' "$config" > "$config_file"

# Self-tests' persistent shells live apart from a real Calm's: at launch Calm ends calm-*
# shells its state doesn't know, and a test's state knows none of the user's. Kept short:
# zmx puts a Unix socket per session here.
zmx_dir="${TMPDIR:-/tmp}/calm-zmx-test"

# Search gets its own index, and an empty home unless one is given: tests never index the
# user's real transcripts.
index_file="$out/$name.index.sqlite"
rm -f "$index_file"*
if [[ -z "$search_home" ]]; then
  search_home="$out/$name.search-home"
  mkdir -p "$search_home"
fi

# Calm writes its generated Ghostty files (defaults, themes) here instead of Application Support.
support_dir="$out/$name.support"
rm -rf "$support_dir"

env \
  CALM_STATE_FILE="$state" \
  CALM_SUPPORT_DIR="$support_dir" \
  CALM_GHOSTTY_CONFIG="$ghostty_config" \
  CALM_APPEARANCE="$appearance" \
  CALM_SNAPSHOT_WINDOW="$snapshot_window" \
  CALM_CONFIG_FILE="$config_file" \
  CALM_ZMX_DIR="$zmx_dir" \
  CALM_INDEX_FILE="$index_file" \
  CALM_SEARCH_HOME="$search_home" \
  CALM_NO_NOTIFICATIONS=1 \
  CALM_HEADLESS="$headless" \
  SHELL="$shell" \
  CALM_SOCKET="/tmp/calm-selftest-$name.sock" \
  CALM_NO_PERSISTENCE="$([[ -n "$persist" ]] && echo 0 || echo 1)" \
  CALM_SNAPSHOT="$out/$name.png" \
  CALM_SELFTEST_TEXT="$out/$name.txt" \
  CALM_SELFTEST_TYPE="$type_text" \
  CALM_SELFTEST_ACTIONS="$actions" \
  CALM_SELFTEST_AFTER="$after" \
  CALM_SELFTEST_KEYS="$(printf '%b' "$keys")" \
  CALM_SELFTEST_DRAG="$drag" \
  CALM_SELFTEST_RESIZE="$resize" \
  CALM_SNAPSHOT_DELAY="$delay" \
  CALM_SNAPSHOT_QUIT=1 \
  OS_ACTIVITY_DT_MODE=1 \
  "$app" > "$out/$name.log" 2>&1 &
pid=$!

# A watchdog for a run that hangs: it stops this instance only, never another Calm, and
# leaves by itself within a second of the app quitting.
limit=$(( ${delay%.*} + 60 ))
(
  for ((second = 0; second < limit; second++)); do
    kill -0 "$pid" 2>/dev/null || exit 0
    sleep 1
  done
  kill "$pid" 2>/dev/null && echo "calm-selftest: stopped after ${limit}s" >> "$out/$name.log"
) &
watchdog=$!
wait "$pid" || true
wait "$watchdog" 2>/dev/null || true

grep -E '^calm-selftest:|^calm:' "$out/$name.log" || true
grep -i -E 'shader|error' "$out/$name.log" | grep -v -E 'linkd|synchronousRemoteObjectProxy|Process Instance Registry|intents framework|CVDisplayLink|display link' | head -20 || true
echo "→ $out/$name.png  $out/$name.txt"
