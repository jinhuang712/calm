#!/usr/bin/env bash
# Checks that `calm status` / `calm notify` are safe in agents' hooks: silent, exit 0 and
# quick when there is no Calm session or no running Calm, and never launching the app.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cli="$root/build/DerivedData/Build/Products/Debug/Calm.app/Contents/Resources/bin/calm"
failed=0

check() {
  local name="$1"
  shift
  local start end output code
  start=$(date +%s)
  output="$("$@" 2>&1)"
  code=$?
  end=$(date +%s)
  if [[ $code -ne 0 || -n "$output" || $((end - start)) -gt 3 ]]; then
    echo "FAIL $name: exit $code, $((end - start))s, output: $output"
    failed=1
  else
    echo "ok   $name"
  fi
}

check "status outside Calm" env -u CALM_SESSION_ID "$cli" status working
check "notify outside Calm" env -u CALM_SESSION_ID "$cli" notify hello
check "status with no running Calm" env CALM_SESSION_ID=6F9619FF-8B86-D011-B42D-00C04FC964FF \
  CALM_SOCKET=/tmp/calm-hook-check-none.sock "$cli" status needs-you "Allow edit?"

if pgrep -x Calm > /dev/null; then
  echo "note: Calm is running, so the no-launch check is skipped"
else
  sleep 1
  if pgrep -x Calm > /dev/null; then
    echo "FAIL status launched Calm"
    failed=1
  else
    echo "ok   Calm was not launched"
  fi
fi
exit $failed
