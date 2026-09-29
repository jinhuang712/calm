#!/bin/bash
# Paints the things a program can put in a row's first or last cell, to see what Calm's
# `window-padding-color = extend` does with them. Row numbers count from 1.
#
#   bash scripts/fixtures/edge-cursor.sh
#
#   row  2  a background painted across the whole row      padding takes its color
#   row  4  a reverse-video space at column 0               pi's cursor on an empty prompt: stays a cell
#   row  6  reverse-video "你" at column 0, then "好"        the same over a wide character: stays a cell
#   row  8  reverse-video "h" at column 0, then "ello"      the same over a letter: stays a cell
#   row 10  a reverse-video space in the last column        the same on the right: stays a cell
#   row 12  a band ten cells wide from column 0             a label with a background: padding takes its color
#
# Used by the padding self-test (DESIGNS.md → Padding and title strip).
set -eu
read -r rows cols < <(stty size)
bar=$(printf '%*s' "$cols" '')

printf '\033[?25l\033[2J'
printf '\033[2;1H\033[48;5;60m%s\033[0m' "$bar"
printf '\033[4;1H\033[7m \033[0m'
printf '\033[6;1H\033[7m你\033[0m好'
printf '\033[8;1H\033[7mh\033[0mello'
printf '\033[10;%dH\033[7m \033[0m' "$cols"
printf '\033[12;1H\033[48;5;60m%10s\033[0m' 'label'
sleep 30
