#!/bin/bash
# A stand-in Claude Code with a pasted image, for self-tests of ⌘ over `[Image #n]` (FEATURES.md
# → F8). Run it in a self-test whose Calm has CLAUDE_CODE_TMPDIR set to a scratch folder (its
# shells inherit it), as DESIGNS.md → Agents shows: it lays out image #1 where Claude Code keeps
# one, says which conversation this is through `calm status` as the hooks would, draws a prompt
# holding the tags (#9 has no file), and stands in for claude. It draws after Calm knows the
# agent, as the real one keeps redrawing.
set -euo pipefail
: "${CLAUDE_CODE_TMPDIR:?run this in a self-test started with CLAUDE_CODE_TMPDIR set}"
session=selftest-images
folder="$CLAUDE_CODE_TMPDIR/claude-$(id -u)/-selftest/$session/images"
mkdir -p "$folder"
# A 1 × 1 PNG.
base64 -d > "$folder/1.png" <<< "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
(
  sleep 2.5
  "$CALM_CLI" status idle --agent claudeCode --agent-session "$session"
  sleep 0.5
  printf '❯ [Image #1] which one? and [Image #9] has no file\n'
) &
exec "$(dirname "$0")/agent-standin.sh" claude 60
