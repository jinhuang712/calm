#!/bin/bash
# Scrolls a region of the alternate screen the way Claude Code's full-screen view streams an
# answer (its bytes, captured from Claude Code 2.1.284): every 0.1 s, inside one synchronized
# update, set the scroll region, scroll it up a few rows (SU), reset it, and paint the new rows.
# The rows below the region stand for the prompt and never move.
#
#   bash scripts/fixtures/region-scroll.sh [rows per step] [steps]
#
# Used by the smooth-scroll self-test (DESIGNS.md → Motion in the terminal). Rows get bars of
# different lengths so no two look alike, which lets the motion probe tell shifts apart.
set -eu
step=${1:-3}
steps=${2:-20}
read -r rows cols < <(stty size)
top=2
bottom=$((rows - 4))
bar=$(printf '%*s' "$cols" '' | tr ' ' '#')
line=0

paint() {
  local length=$(((line * 37) % (cols - 20) + 4))
  printf '\033[%d;1H\033[2Kline %03d %s' "$1" "$line" "${bar:0:length}"
  line=$((line + 1))
}

printf '\033[?1049h\033[H\033[2J'
for ((row = top; row <= bottom; row++)); do paint "$row"; done
printf '\033[%d;1H> prompt' $((rows - 1))
sleep 1.5 # the probe is sampling by now

for ((index = 0; index < steps; index++)); do
  printf '\033[?2026h\033[%d;%dr\033[%dS\033[r' "$top" "$bottom" "$step"
  for ((row = bottom - step + 1; row <= bottom; row++)); do paint "$row"; done
  printf '\033[?2026l'
  sleep 0.1
done

sleep 2
printf '\033[?1049l'
