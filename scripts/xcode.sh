#!/usr/bin/env bash
# Thin wrapper around xcodebuild used by the mise tasks.
#   scripts/xcode.sh build | test | test-packages | test-app | run
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

derived="$root/build/DerivedData"
common=(-project Calm.xcodeproj -scheme Calm -configuration Debug -derivedDataPath "$derived" -destination "platform=macOS,arch=arm64")

pretty() {
  if command -v xcbeautify >/dev/null 2>&1; then xcbeautify --quiet; else cat; fi
}

case "${1:-build}" in
  build)
    set -o pipefail
    xcodebuild "${common[@]}" build | pretty
    ;;
  test)
    # The app's tests run even when the package's fail, so one run shows every failure (CI
    # once showed one per run: a red package test hid two red app tests for three runs).
    status=0
    "$root/scripts/xcode.sh" test-packages || status=1
    "$root/scripts/xcode.sh" test-app || status=1
    exit "$status"
    ;;
  test-packages)
    swift test --package-path Packages/CalmKit --quiet
    ;;
  test-app)
    set -o pipefail
    xcodebuild "${common[@]}" test | pretty
    ;;
  run)
    app="$derived/Build/Products/Debug/Calm.app"
    pkill -x Calm 2>/dev/null || true
    # A new Calm quits at once if the old one still answers on the control socket.
    for _ in {1..50}; do pgrep -x Calm >/dev/null || break; sleep 0.1; done
    open "$app"
    ;;
  snapshot)
    # Launch the Debug app headless and isolated, save a PNG of its window, and quit
    # (see scripts/selftest.sh and Calm/App/SelfTest.swift).
    out="${2:?usage: $0 snapshot <out.png> [delay-seconds]}"
    CALM_SELFTEST_OUT="$(dirname "$out")" "$root/scripts/selftest.sh" "$(basename "$out" .png)" --delay "${3:-1.5}" \
      | grep -E '^calm-selftest:' || true
    ;;
  *)
    echo "usage: $0 build|test|test-packages|test-app|run|snapshot" >&2
    exit 64
    ;;
esac
