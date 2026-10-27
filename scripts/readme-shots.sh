#!/usr/bin/env bash
# Regenerates the README's pictures into assets/: the logo (from the app icon) and headless
# screenshots of the Debug app (Calm Dev). Nothing opens a window, takes focus or calls a model:
# the sessions are stand-ins (scripts/fixtures/demo-agent.sh) in an isolated self-test.
#
#   scripts/readme-shots.sh
#
# DEMO_PROJECT is the folder the demo sessions run in, and the title strip shows its path. It
# defaults to this checkout; from a worktree, point it at a short path, for example
# DEMO_PROJECT=~/dev/apps/calm. Needs `mise run build` first, and Xcode for the logo.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
project="${DEMO_PROJECT:-$root}"
tmp="$(mktemp -d)"
export CALM_SELFTEST_OUT="$tmp"
mkdir -p assets

demo="bash $root/scripts/fixtures/demo-agent.sh"
sessions="calm.add_project:$project,calm.new_session"
sessions+=",calm.type:clear; $demo done,wait,wait,calm.agent:done,calm.agent_title:Write the release notes"
sessions+=",calm.new_session,calm.type:clear; $demo working,wait,wait,calm.agent:working,calm.agent_title:Add search ranking"
sessions+=",calm.new_session,calm.type:clear; $demo needs,wait,wait,calm.agent:needsYou,calm.agent_title:Fix flaky auth test"

for look in dark light; do
  scripts/selftest.sh "hero-$look" --appearance "$look" --resize 1240x780 --delay 2 --actions "$sessions" > /dev/null
  cp "$tmp/hero-$look.png" "assets/hero-$look.png"
done
scripts/selftest.sh welcome-dark --welcome --appearance dark --resize 1240x780 --delay 3 > /dev/null
cp "$tmp/welcome-dark.png" assets/welcome-dark.png
scripts/selftest.sh settings-dark --appearance dark --resize 1240x780 --delay 3 --actions "calm.settings:appearance" > /dev/null
cp "$tmp/settings-dark.png" assets/settings-dark.png

ictool="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
"$ictool" Calm/Resources/AppIcon.icon --export-image --output-file assets/logo.png \
  --platform macOS --rendition Default --width 512 --height 512 --scale 1 > /dev/null
"$ictool" Calm/Resources/AppIcon.icon --export-image --output-file assets/logo-dark.png \
  --platform macOS --rendition Dark --width 512 --height 512 --scale 1 > /dev/null

rm -rf "$tmp"
ls -la assets
