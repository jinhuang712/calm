#!/usr/bin/env bash
# Launch the Debug app once, drive it, capture a snapshot and the screen text, then quit.
# Needs no Screen Recording permission (see Calm/App/SelfTest.swift).
#
#   scripts/selftest.sh <name> [--type TEXT] [--actions a,b,c] [--delay SECONDS]
#
# Writes $CALM_SELFTEST_OUT/<name>.png, <name>.txt and <name>.log
# (default out dir: /tmp/calm-selftest).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
name="${1:?usage: $0 <name> [--type TEXT] [--actions a,b] [--delay S]}"
shift
out="${CALM_SELFTEST_OUT:-/tmp/calm-selftest}"
mkdir -p "$out"

type_text=""
actions=""
delay="1.5"
keys=""
drag=""
resize=""
persist=""
state=""
config=""
shell="${SHELL:-/bin/zsh}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --type) type_text="$2"; shift 2 ;;
    --actions) actions="$2"; shift 2 ;;
    --delay) delay="$2"; shift 2 ;;
    --keys) keys="$2"; shift 2 ;;   # typed through real key events; "\r" in the text means Return
    --drag) drag=1; shift ;;         # drag-select the first rows, copy, and log the clipboard
    --resize) resize="$2"; shift 2 ;; # e.g. 700x420: resize the window and log the grid size
    --persist) persist=1; shift ;;   # keep zmx persistence on (default: off, so runs leave nothing behind)
    --state) state="$2"; shift 2 ;;  # use this state file (default: a fresh one per run)
    --plain-shell) shell=/bin/bash; shift ;; # persistent sessions get no shell integration (no OSC 7)
    --config) config="$2"; shift 2 ;; # Calm settings text for config.toml (default: none, so defaults)
    *) echo "unknown option $1" >&2; exit 64 ;;
  esac
done

app="$root/build/DerivedData/Build/Products/Debug/Calm.app/Contents/MacOS/Calm"
pkill -x Calm 2>/dev/null || true

if [[ -z "$state" ]]; then
  state="$out/$name.state.json"
  rm -f "$state"
fi

config_file="$out/$name.config.toml"
printf '%b' "$config" > "$config_file"

env \
  CALM_STATE_FILE="$state" \
  CALM_CONFIG_FILE="$config_file" \
  SHELL="$shell" \
  CALM_SOCKET="/tmp/calm-selftest-$name.sock" \
  CALM_NO_PERSISTENCE="$([[ -n "$persist" ]] && echo 0 || echo 1)" \
  CALM_SNAPSHOT="$out/$name.png" \
  CALM_SELFTEST_TEXT="$out/$name.txt" \
  CALM_SELFTEST_TYPE="$type_text" \
  CALM_SELFTEST_ACTIONS="$actions" \
  CALM_SELFTEST_KEYS="$(printf '%b' "$keys")" \
  CALM_SELFTEST_DRAG="$drag" \
  CALM_SELFTEST_RESIZE="$resize" \
  CALM_SNAPSHOT_DELAY="$delay" \
  CALM_SNAPSHOT_QUIT=1 \
  OS_ACTIVITY_DT_MODE=1 \
  "$app" > "$out/$name.log" 2>&1 || true

grep -E '^calm-selftest:|^calm:' "$out/$name.log" || true
grep -i -E 'shader|error' "$out/$name.log" | grep -v -E 'linkd|synchronousRemoteObjectProxy|Process Instance Registry|intents framework|CVDisplayLink|display link' | head -20 || true
echo "→ $out/$name.png  $out/$name.txt"
