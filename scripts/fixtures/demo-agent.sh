#!/bin/bash
# A stand-in agent for the README's screenshots (scripts/readme-shots.sh): it prints a made-up
# Claude Code style screen, then becomes a process whose argv[0] is "claude", so Calm's probe finds
# an agent with nothing real started and no model called. Run it as a child of the shell, not with
# `exec` in the shell itself (see agent-standin.sh). $1: needs, working or done.
state="${1:?usage: demo-agent.sh needs|working|done}"
b=$'\033[1m'; d=$'\033[2m'; r=$'\033[0m'
clay=$'\033[38;5;173m'; amber=$'\033[38;5;179m'; sage=$'\033[38;5;108m'
case "$state" in
  needs)
    printf '\n%s●%s The test fails when two requests find the token expired together: TokenStore refreshes it twice.\n\n' "$clay" "$r"
    printf '  %sEdit%s(Sources/Auth/TokenStore.swift)\n  %s⎿ Added a lock around the refresh (+12 −3)%s\n\n' "$b" "$r" "$d" "$r"
    printf '  %sBash%s(swift test --filter AuthTests)\n\n' "$b" "$r"
    # ASCII inside the box, so printf's padding counts characters, not bytes
    row() { printf '%s│%s %-48s %s│%s\n' "$amber" "$r" "$1" "$amber" "$r"; }
    printf '%s╭──────────────────────────────────────────────────╮%s\n' "$amber" "$r"
    row "Run this command?"
    row "> 1. Yes"
    row "  2. Yes, and don't ask again for swift test"
    row "  3. No, and tell Claude what to do differently"
    printf '%s╰──────────────────────────────────────────────────╯%s\n' "$amber" "$r"
    ;;
  working)
    printf '\n%s✻%s Reading SearchRanking.swift…\n' "$clay" "$r"
    ;;
  done)
    printf '\n%s●%s Drafted the notes for 0.1.5 in CHANGELOG.md.\n\n  %s✓%s 3 of 3 tasks done\n' "$sage" "$r" "$sage" "$r"
    ;;
esac
exec -a claude /bin/sleep 300
