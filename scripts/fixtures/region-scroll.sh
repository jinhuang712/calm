#!/bin/bash
# Scrolls a region of the alternate screen the way Claude Code's full-screen view does (its bytes,
# captured from Claude Code 2.1.284): every 0.1 s, inside one synchronized update, set the scroll
# region, scroll it by a few rows, reset it, and paint the rows that came in. The rows below the
# region stand for the prompt and never move.
#
#   bash scripts/fixtures/region-scroll.sh [rows per step] [steps] [hint]
#
# A positive step scrolls up (SU), as an answer streams in; a negative one scrolls down (SD), as
# when scrolling back. With `hint`, a hint is drawn again on the region's last row after every
# scroll, as Claude Code draws its "Jump to bottom" hint while scrolled back, in a magenta box
# (#ff00ff) the motion probe can count (`CALM_SELFTEST_MOTION_COLOR`).
#
# Used by the smooth-scroll self-tests (DESIGNS.md → Motion in the terminal). Rows get bars of
# different lengths so no two look alike, which lets the motion probe tell shifts apart.
set -eu
step=${1:-3}
steps=${2:-20}
hint=${3:-}
read -r rows cols < <(stty size)
top=2
bottom=$((rows - 4))
bar=$(printf '%*s' "$cols" '' | tr ' ' '#')
hint_x=$((cols / 2))
line=0
count=${step#-}

paint() {
  local length=$(((line * 37) % (cols - 20) + 4))
  printf '\033[%d;1H\033[2Kline %03d %s' "$1" "$line" "${bar:0:length}"
  line=$((line + 1))
}

draw_hint() {
  printf '\033[%d;%dH\033[48;2;255;0;255m\033[38;2;255;255;255m Jump to bottom (click) \033[0m' "$bottom" "$hint_x"
}

printf '\033[?1049h\033[H\033[2J'
for ((row = top; row <= bottom; row++)); do paint "$row"; done
[[ -n "$hint" ]] && draw_hint
printf '\033[%d;1H> prompt' $((rows - 1))
sleep 1.5 # the probe is sampling by now

for ((index = 0; index < steps; index++)); do
  if ((step > 0)); then
    printf '\033[?2026h\033[%d;%dr\033[%dS\033[r' "$top" "$bottom" "$count"
    for ((row = bottom - count + 1; row <= bottom; row++)); do paint "$row"; done
    # The old hint scrolled up with the rest; clear it, as Claude Code does.
    [[ -n "$hint" ]] && printf '\033[%d;%dH\033[K' $((bottom - count)) "$hint_x"
  else
    printf '\033[?2026h\033[%d;%dr\033[%dT\033[r' "$top" "$bottom" "$count"
    for ((row = top; row < top + count; row++)); do paint "$row"; done
  fi
  [[ -n "$hint" ]] && draw_hint
  printf '\033[?2026l'
  sleep 0.1
done

sleep 2
printf '\033[?1049l'
