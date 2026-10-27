#!/usr/bin/env bash
# Regenerates the README's pictures into assets/: the logo (from the app icon) and headless screenshots
# of the Debug app (Calm Dev). Nothing opens a window or takes focus.
#
#   DEMO_PROJECT=~/dev/apps/calm scripts/readme-shots.sh
#
# The sessions in the pictures are REAL Claude Code sessions (Haiku 5.5, so about five short model calls).
# Each runs with `--permission-mode manual` and without the user's own settings (`--setting-sources project`),
# so it asks before every command, and nothing is approved: the app quits after each snapshot. It needs
# Claude Code installed and logged in. Claude Code draws what it draws, so a new version changes the
# pictures: say which version took them in the README.
#
# DEMO_PROJECT is the folder every session runs in, and the title strip shows its path. It defaults to
# this checkout; from a worktree, point it at a short path. It must be a clone of this repository, because
# one prompt asks Claude to run the package tests. Needs `mise run build` first, and Xcode for the logo.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
project="${DEMO_PROJECT:-$root}"
tmp="$(mktemp -d)"
export CALM_SELFTEST_OUT="$tmp"
mkdir -p assets

size=1240x780
claude="clear; claude --model haiku --permission-mode manual --setting-sources project"
quick="$claude 'Reply with the single word ready'"
essay="$claude 'Write a 3000 word essay called Calm'"
asks="$claude 'Run swift test in Packages/CalmKit and tell me whether it passes'"
log="calm.type:clear; git log --oneline --no-decorate -9"
waits="wait,wait,wait,wait,wait,wait,wait,wait,wait,wait"

shoot() { # name, look, then the self-test's own options
  local name="$1" look="$2"
  shift 2
  scripts/selftest.sh "$name" --appearance "$look" --resize "$size" "$@" > /dev/null
}

# The sidebar: one session that finished, one that is busy writing, one that asks to run a command.
for look in dark light; do
  shoot "hero-$look" "$look" --delay 12 --actions \
    "calm.add_project:$project,calm.new_session,calm.type:$quick,$waits,calm.new_session,calm.type:$essay,wait,wait,wait,calm.new_session,calm.type:$asks"
done
shoot menu dark --delay 3 --actions \
  "calm.add_project:$project,calm.new_session,calm.type:$asks,wait,wait,wait,wait,wait,wait,wait,wait,calm.session_menu,wait"

# Plain shells running read-only git commands.
shoot palette dark --delay 3 --actions "calm.add_project:$project,calm.new_session,$log,wait,calm.cmd_p,wait"
shoot files dark --delay 15 --actions \
  "calm.add_project:$project,calm.new_session,$log,wait,calm.toggle_files,wait,wait,calm.view:$project/specs/FEATURES.md,wait,wait,wait,wait,wait,wait"
shoot split dark --delay 3 --actions \
  "calm.add_project:$project,calm.new_session,$log,wait,calm.cmd_opt_right,wait,calm.type:clear; git status -sb; git branch --show-current,wait"
for theme in Dusk Forest Plum; do
  shoot "theme-$theme" dark --delay 3 --config "theme = \"$theme\"\n" --actions "calm.add_project:$project,calm.new_session,$log,wait"
done
shoot welcome dark --delay 3 --welcome
shoot settings dark --delay 3 --actions "calm.settings:appearance"

# Pictures at 1600 px wide are sharp enough for a README and a third of the size.
for name in hero-dark hero-light menu palette files split theme-Dusk theme-Forest theme-Plum welcome settings; do
  sips -Z 1600 "$tmp/$name.png" --out "assets/$name.png" > /dev/null
done

ictool="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
# 144 px: the README shows it as plain Markdown, which cannot set a width, so the picture itself is small.
"$ictool" Calm/Resources/AppIcon.icon --export-image --output-file assets/logo.png \
  --platform macOS --rendition Default --width 144 --height 144 --scale 1 > /dev/null

rm -rf "$tmp"
ls -la assets
