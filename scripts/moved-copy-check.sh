#!/usr/bin/env bash
# Checks remove_once_quit, the waiter install.sh and get.sh leave for a Calm still running from the
# copy they moved aside (RUNBOOK.md → Installing under a running Calm): both scripts' copies of it, against a
# scratch folder and /bin/sleep standing in for that Calm. For an older Calm the program file
# must go within 0.1 s of its exit, before that Calm's restart reopens (it looks every 0.1 s),
# and for a newer one within about a second; never while it runs.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d -t calm-moved-copy)"
trap 'rm -rf "$scratch"' EXIT
failed=0

fail() {
  echo "FAIL $*"
  failed=1
}

now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }

# <script> <version> <seconds the stand-in runs> <most seconds from its exit to the file gone>
check() {
  local script="$1" version="$2" runs="$3" within="$4"
  local moved="$scratch/.Calm.app.previous-$RANDOM"
  mkdir -p "$moved/Contents/MacOS"
  : > "$moved/Contents/MacOS/Calm"
  # The function alone, as the script defines it.
  eval "$(sed -n '/^remove_once_quit() {/,/^}/p' "$root/$script")"
  /bin/sleep "$runs" &
  local calm=$!
  remove_once_quit "$moved" "$version" "$calm"
  local name="$script, Calm '$version'"

  /bin/sleep 0.3
  [[ -e "$moved/Contents/MacOS/Calm" ]] || fail "$name: the copy went while its Calm ran"
  wait "$calm"
  local exited gone
  exited="$(now)"
  for _ in $(seq 1 300); do
    [[ -e "$moved/Contents/MacOS/Calm" ]] || break
    perl -e 'select(undef, undef, undef, 0.005)'
  done
  gone="$(now)"
  if [[ -e "$moved/Contents/MacOS/Calm" ]]; then
    fail "$name: the program file was still there 1.5 s after its Calm quit"
    return
  fi
  local took
  took="$(perl -e "printf '%.3f', $gone - $exited")"
  if perl -e "exit !($took > $within)"; then
    fail "$name: the program file went $took s after its Calm quit, more than $within s"
  else
    echo "ok   $name: the program file went $took s after its Calm quit"
  fi
  for _ in $(seq 1 100); do
    [[ -e "$moved" ]] || break
    /bin/sleep 0.05
  done
  [[ -e "$moved" ]] && fail "$name: the rest of the copy was still there"
}

for script in install.sh get.sh; do
  check "$script" 0.1.1 1 0.1
  check "$script" 0.1.1-dc970ac 1 0.1
  check "$script" "" 1 0.1
  check "$script" 0.1.2 1 1.2
done

if [[ $failed -eq 0 ]]; then
  echo "All checks passed."
fi
exit $failed
