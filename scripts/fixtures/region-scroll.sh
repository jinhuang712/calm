#!/bin/bash
# Moves a region of the alternate screen by a few rows every 0.1 s, the way agents' full-screen
# views stream an answer or scroll back, inside one synchronized update per step. The rows below
# the region stand for the prompt and never move.
#
#   bash scripts/fixtures/region-scroll.sh [rows per step] [steps] [hint] [repaint]
#
# A positive step moves the content up, as an answer streams in; a negative one moves it down, as
# when scrolling back. By default each step scrolls the region (DECSTBM with SU or SD) and paints
# the rows that came in, as Claude Code does (its bytes, captured from 2.1.284). With `repaint`,
# each step instead rewrites every row of the region in place with the content moved, as pi's
# full-screen view does, so the terminal sees no scroll at all. With `hint`, a hint is drawn again
# on the region's last row after every step, as Claude Code draws its "Jump to bottom" hint while
# scrolled back, in a magenta box (#ff00ff) the motion probe can count (`--motion-color`).
#
# Used by the smooth-scroll self-tests (DESIGNS.md → Motion in the terminal). Rows get bars of
# different lengths so no two look alike, which lets the motion probe tell shifts apart.
set -eu
step=3 steps=20 hint="" repaint="" numbers=0
for arg in "$@"; do
  case "$arg" in
    hint) hint=1 ;;
    repaint) repaint=1 ;;
    "") ;;
    *) if ((numbers == 0)); then step=$arg; else steps=$arg; fi; numbers=$((numbers + 1)) ;;
  esac
done
read -r rows cols < <(stty size)
top=2
bottom=$((rows - 4))
bar=$(printf '%*s' "$cols" '' | tr ' ' '#')
hint_x=$((cols / 2))
count=${step#-}
first=500 # the line shown on the region's top row; lines are numbered, so moving back has room

# Line `n` at `row`, the same text wherever it is drawn.
draw() {
  local length=$((($2 * 37) % (cols - 20) + 4))
  printf '\033[%d;1H\033[2Kline %03d %s' "$1" "$2" "${bar:0:length}"
}

draw_hint() {
  printf '\033[%d;%dH\033[48;2;255;0;255m\033[38;2;255;255;255m Jump to bottom (click) \033[0m' "$bottom" "$hint_x"
}

printf '\033[?1049h\033[H\033[2J'
for ((row = top; row <= bottom; row++)); do draw "$row" $((first + row - top)); done
[[ -n "$hint" ]] && draw_hint
printf '\033[%d;1H> prompt' $((rows - 1))
sleep 1.5 # the probe is sampling by now

for ((index = 0; index < steps; index++)); do
  printf '\033[?2026h'
  first=$((first + step))
  if [[ -n "$repaint" ]]; then
    for ((row = top; row <= bottom; row++)); do draw "$row" $((first + row - top)); done
  elif ((step > 0)); then
    printf '\033[%d;%dr\033[%dS\033[r' "$top" "$bottom" "$count"
    for ((row = bottom - count + 1; row <= bottom; row++)); do draw "$row" $((first + row - top)); done
    # The old hint scrolled up with the rest; clear it, as Claude Code does.
    [[ -n "$hint" ]] && printf '\033[%d;%dH\033[K' $((bottom - count)) "$hint_x"
  else
    printf '\033[%d;%dr\033[%dT\033[r' "$top" "$bottom" "$count"
    for ((row = top; row < top + count; row++)); do draw "$row" $((first + row - top)); done
  fi
  [[ -n "$hint" ]] && draw_hint
  printf '\033[?2026l'
  sleep 0.1
done

sleep 2
printf '\033[?1049l'
