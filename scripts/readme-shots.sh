#!/usr/bin/env bash
# Regenerates the README's pictures into assets/: the logo (from the app icon), an animated hero and two
# screenshots of the Debug app (Calm Dev). All of it is headless: nothing opens a window or takes focus.
#
#   DEMO_PROJECT=~/dev/apps/calm scripts/readme-shots.sh
#
# The sessions in the pictures are REAL Claude Code sessions (Haiku 5.5, so a handful of short model calls).
# Each runs with `--permission-mode manual` and without the user's own settings (`--setting-sources project`),
# so it asks before every command, and nothing is approved: the app quits after each run. It needs Claude Code
# installed and logged in, and ffmpeg for the hero. Claude Code draws what it draws, so a new version changes
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
claude="clear; claude --model haiku --permission-mode manual --setting-sources project"
quick="$claude 'Reply with the single word ready'"
essay="$claude 'Write a 3000 word essay called Calm'"
asks="$claude 'Run swift test in Packages/CalmKit and tell me whether it passes'"
log="calm.type:clear; git log --oneline --no-decorate -9"
waits="wait,wait,wait,wait,wait,wait,wait,wait,wait,wait"

# A Claude Code that runs this script has markers in its environment that the demo sessions would inherit.
# Dropped, so a demo session behaves as one started from a terminal.
fresh() { env -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_BRIDGE_SESSION_ID -u CLAUDE_CODE_MESSAGING_SOCKET \
  -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_SESSION_ATTENDED "$@"; }

shoot() { # name, then the self-test's own options
  local name="$1"
  shift
  fresh scripts/selftest.sh "$name" --appearance dark --resize "$size" "$@" > /dev/null
}

# A plain shell, with the files column and a viewed file. The viewer is a web view that now and then has not
# finished loading when the snapshot is taken, which leaves it empty. Try up to three times and keep the
# picture with the most in it.
for try in 1 2 3; do
  shoot "files-$try" --delay 15 --actions \
    "calm.add_project:$project,calm.new_session,$log,wait,calm.toggle_files,wait,wait,calm.view:$project/specs/FEATURES.md,wait,wait,wait,wait,wait,wait"
done
cp "$(ls -S "$tmp"/files-?.png | head -1)" "$tmp/files.png"

# The session menu of a session that asks to run a command.
shoot menu --delay 3 --actions \
  "calm.add_project:$project,calm.new_session,calm.type:$asks,wait,wait,wait,wait,wait,wait,wait,wait,calm.session_menu,wait"

# The hero: one run, a screenshot every half second through the app's own socket (`calm screenshot`
# needs no Screen Recording permission), then a GIF. A session finishes, a second one thinks, a third one
# starts and asks to run a command. Every tick also asks the app for the sessions' states (`calm list`), and
# the GIF is the 14 ticks before the first "needs-you" and the 4 after it, so the cards go from Thinking to
# Needs you whatever the pace of the run. The last picture is held for three seconds.
sock=/tmp/calm-selftest-hero.sock
rm -f "$sock"
mkdir -p "$tmp/frames"
fresh scripts/selftest.sh hero --appearance dark --resize "$size" --delay 45 --actions \
  "calm.add_project:$project,calm.new_session,calm.type:$quick,$waits,calm.new_session,calm.type:$essay,wait,wait,wait,calm.new_session,calm.type:$asks" > /dev/null 2>&1 &
for _ in $(seq 1 100); do [ -S "$sock" ] && break; sleep 0.2; done
needs=""
for n in $(seq 0 79); do
  CALM_SOCKET="$sock" calm screenshot "$tmp/frames/f$(printf %03d "$n").png" > /dev/null
  if [ -z "$needs" ] && CALM_SOCKET="$sock" calm list 2> /dev/null | /usr/bin/grep -q 'needs-you'; then needs="$n"; fi
  sleep 0.5
done
wait
[ -n "$needs" ] || { echo "the hero run never reached needs-you" >&2; exit 1; }
first=$((needs > 14 ? needs - 14 : 0))
ffmpeg -loglevel error -y -framerate 2 -i "$tmp/frames/f%03d.png" \
  -vf "select='between(n,$first,$((needs + 4)))',setpts=N/2/TB,scale=1000:-1:flags=lanczos,tpad=stop_mode=clone:stop_duration=3,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  -loop 0 assets/hero.gif

# Each picture shows its subject and nothing else. The whole window is 1240 x 780 pt (2480 x 1560 px), and the
# subject's box is given in points: x, y, width, height. Pictures end up 1600 px wide at most, which is sharp
# enough for a README and a third of the size.
crop() { # name x y width height
  sips -c $(($5 * 2)) $(($4 * 2)) --cropOffset $(($3 * 2)) $(($2 * 2)) "$tmp/$1.png" --out "assets/$1.png" > /dev/null
  sips -Z 1600 "assets/$1.png" > /dev/null
}
crop menu 680 0 560 470   # the menu, and the title strip it hangs from
crop files 320 0 920 600  # the files column and the viewer, not the sidebar

ictool="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
# 144 px: the README shows it as plain Markdown, which cannot set a width, so the picture itself is small.
"$ictool" Calm/Resources/AppIcon.icon --export-image --output-file assets/logo.png \
  --platform macOS --rendition Default --width 144 --height 144 --scale 1 > /dev/null

# Remove the demo conversations from the user's Claude history: transcripts made since this script started
# whose first prompt is one of the three above, and their lines in the prompt log.
DEMO_PROJECT="$project" STARTED="$started" python3 -I - << 'PY'
import json, os, pathlib
prompts = {"Reply with the single word ready", "Write a 3000 word essay called Calm",
           "Run swift test in Packages/CalmKit and tell me whether it passes"}
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
