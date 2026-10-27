#!/usr/bin/env bash
# Regenerates the README's pictures into assets/: the logo (from the app icon), a short GIF and two screenshots
# of the Debug app (Calm Dev). All of it is headless: nothing opens a window or takes focus.
#
#   DEMO_PROJECT=~/dev/apps/calm scripts/readme-shots.sh
#
# Each picture shows one thing, cropped to it:
#   needs-you.gif  a session goes from Thinking to Needs you (the sidebar card, and the question it asks)
#   files.png      the files column beside a file in the viewer
#   menu.png       the session menu
#
# The session in the pictures is a REAL Claude Code session (Haiku 5.5, so a few short model calls). It runs
# with `--permission-mode manual` and without the user's own settings (`--setting-sources project`), so it
# asks before every command, and nothing is approved: the app quits after each run. It needs Claude Code
# installed and logged in, and ffmpeg for the GIF. Claude Code draws what it draws, so a new version changes
# the pictures: say which version took them in the README.
#
# The demo conversations are written into the user's Claude history like any other. This script removes
# exactly those (by their session ids) when it is done.
#
# DEMO_PROJECT is the folder every session runs in, and the title strip shows its path. It defaults to
# this checkout; from a worktree, point it at a short path. It must be a clone of this repository, because
# one prompt asks Claude to run the package tests. Needs `mise run build` first, and Xcode for the logo.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
project="${DEMO_PROJECT:-$root}"
tmp="$(mktemp -d)"
started="$(date +%s)"
export CALM_SELFTEST_OUT="$tmp"
mkdir -p assets

size=1240x780
asks="clear; claude --model haiku --permission-mode manual --setting-sources project 'Run swift test in Packages/CalmKit and tell me whether it passes'"

# A Claude Code that runs this script has markers in its environment that the demo session would inherit.
# Dropped, so a demo session behaves as one started from a terminal.
fresh() { env -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_BRIDGE_SESSION_ID -u CLAUDE_CODE_MESSAGING_SOCKET \
  -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_SESSION_ATTENDED "$@"; }

# One headless run of the app, a screenshot of its window every $tick seconds through its own socket
# (`calm screenshot` needs no Screen Recording permission), then a GIF of the part that matters.
#
#   gif <name> <tick> <ticks> <crop: x y width height, in points> <hold seconds> <first> <last> <actions>
#
# <first> and <last> pick the pictures: with "needs-you" as <last>, the GIF ends 4 ticks after the first tick
# where `calm list` says a session needs you, and starts <first> ticks before it. With "all", the GIF starts at
# tick <first> and runs to the end, and still pictures are dropped. The last picture is held for <hold> seconds.
gif() {
  local name="$1" tick="$2" ticks="$3" cx="$4" cy="$5" cw="$6" ch="$7" hold="$8" first="$9" last="${10}" actions="${11}"
  local sock="/tmp/calm-selftest-$name.sock" frames="$tmp/frames-$name" found="" n pid
  local delay
  delay="$(python3 -c "print(int($tick * $ticks) + 8)")"
  rm -f "$sock"
  mkdir -p "$frames"
  fresh scripts/selftest.sh "$name" --appearance dark --resize "$size" --delay "$delay" --actions "$actions" > /dev/null 2>&1 &
  pid=$!
  for _ in $(seq 1 100); do [ -S "$sock" ] && break; sleep 0.2; done
  for n in $(seq 0 $((ticks - 1))); do
    CALM_SOCKET="$sock" calm screenshot "$frames/f$(printf %03d "$n").png" > /dev/null
    if [ "$last" = "needs-you" ] && [ -z "$found" ] && CALM_SOCKET="$sock" calm list 2> /dev/null | /usr/bin/grep -q 'needs-you'; then
      found="$n"
    fi
    sleep "$tick"
  done
  wait "$pid" || true
  local select="1" filter=""
  if [ "$last" = "needs-you" ]; then
    [ -n "$found" ] || { echo "$name never reached needs-you" >&2; return 1; }
    select="between(n,$((found > first ? found - first : 0)),$((found + 4)))"
  else
    select="gte(n,$first)"
    filter="mpdecimate,"
  fi
  local rate
  rate="$(python3 -c "print(round(1 / $tick, 3))")"
  # The frames are 2x (a 1240 x 780 pt window is 2480 x 1560 px), so the crop box is doubled.
  ffmpeg -loglevel error -y -framerate "$rate" -i "$frames/f%03d.png" \
    -vf "select='$select',crop=$((cw * 2)):$((ch * 2)):$((cx * 2)):$((cy * 2)),${filter}setpts=N/$rate/TB,scale=1000:-1:flags=lanczos,tpad=stop_mode=clone:stop_duration=$hold,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
    -loop 0 "$tmp/$name.gif"
}

# A still, cropped to its subject. The whole window is 1240 x 780 pt (2480 x 1560 px), and the box is x, y,
# width, height in points. Pictures end up 1600 px wide at most.
crop() { # name x y width height
  sips -c $(($5 * 2)) $(($4 * 2)) --cropOffset $(($3 * 2)) $(($2 * 2)) "$tmp/$1.png" --out "assets/$1.png" > /dev/null
  sips -Z 1600 "assets/$1.png" > /dev/null
}

# 1. A session goes from Thinking to Needs you: the card in the sidebar and the question it asks.
gif needs-you 0.5 60 0 0 900 470 3 3 needs-you \
  "calm.add_project:$project,calm.new_session,calm.type:$asks"
cp "$tmp/needs-you.gif" assets/needs-you.gif

# 2. The files column beside a file in the viewer. It is a still, because `calm screenshot` cannot see inside the
# viewer's web view (the picture of a run's end can). The web view draws only while a display is awake, and now
# and then it has not finished loading when the run ends: either leaves the viewer empty. Try up to three times,
# keep the picture with the most in it, and keep the old picture when even that one is empty (under 300 KB).
for try in 1 2 3; do
  fresh scripts/selftest.sh "files-$try" --appearance dark --resize "$size" --delay 15 --actions \
    "calm.add_project:$project,calm.new_session,calm.type:clear; git log --oneline --no-decorate -9,wait,calm.toggle_files,wait,wait,calm.view:$project/specs/FEATURES.md,wait,wait,wait,wait,wait,wait" > /dev/null
done
cp "$(ls -S "$tmp"/files-?.png | head -1)" "$tmp/files.png"
cp assets/files.png "$tmp/files-before.png" 2> /dev/null || true
crop files 320 0 920 600 # the files column and the viewer, not the sidebar
if [ "$(stat -f %z assets/files.png)" -lt 300000 ]; then
  echo "files.png came out empty (is the display asleep?): keeping the old one" >&2
  cp "$tmp/files-before.png" assets/files.png
fi

# 3. The session menu of a session that asks to run a command.
fresh scripts/selftest.sh menu --appearance dark --resize "$size" --delay 3 --actions \
  "calm.add_project:$project,calm.new_session,calm.type:$asks,wait,wait,wait,wait,wait,wait,wait,wait,calm.session_menu,wait" > /dev/null
crop menu 680 0 560 470 # the menu, and the title strip it hangs from

ictool="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
# 144 px: the logo is a plain picture, so the picture itself is small.
"$ictool" Calm/Resources/AppIcon.icon --export-image --output-file assets/logo.png \
  --platform macOS --rendition Default --width 144 --height 144 --scale 1 > /dev/null

# Remove the demo conversations from the user's Claude history: transcripts made since this script started
# whose first prompt is the one above, and their lines in the prompt log.
DEMO_PROJECT="$project" STARTED="$started" python3 -I - << 'PY'
import json, os, pathlib
prompts = {"Run swift test in Packages/CalmKit and tell me whether it passes"}
home = pathlib.Path.home() / ".claude"
folder = home / "projects" / os.environ["DEMO_PROJECT"].replace("/", "-").replace(".", "-")
started = int(os.environ["STARTED"])
ids = set()
for f in folder.glob("*.jsonl") if folder.is_dir() else []:
    if f.stat().st_birthtime < started:
        continue
    for line in f.open():
        try:
            record = json.loads(line)
        except ValueError:
            continue
        message = record.get("message") or {}
        content = message.get("content") if message.get("role") == "user" else None
        if isinstance(content, list):
            content = "".join(part.get("text", "") for part in content if isinstance(part, dict))
        if isinstance(content, str):
            if content.strip() in prompts:
                ids.add(f.stem)
                f.unlink()
            break
log = home / "history.jsonl"
if ids and log.exists():
    kept = [l for l in log.read_text().split("\n") if not any('"sessionId":"%s"' % i in l for i in ids)]
    log.write_text("\n".join(kept))
print("removed %d demo conversations from the Claude history" % len(ids))
PY

rm -rf "$tmp"
ls -la assets
