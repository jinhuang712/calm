#!/bin/bash
# A stand-in agent for self-tests: a process whose argv[0] is the agent's name ($1: claude,
# codex, pi, opencode), so Calm's probe finds a running agent with nothing real started and no
# model called. It runs from the shell as a child, as an agent would; `exec -a` in the shell
# itself replaces the shell, which the probe doesn't take for an agent. Sleeps $2 seconds (300).
exec -a "${1:?usage: agent-standin.sh <agent> [seconds]}" /bin/sleep "${2:-300}"
