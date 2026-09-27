#!/usr/bin/env bash
# Thin wrapper around xcodebuild used by the mise tasks.
#   scripts/xcode.sh build | test | run
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
    set -o pipefail
    swift test --package-path Packages/CalmKit --quiet
    xcodebuild "${common[@]}" test | pretty
    ;;
  run)
    app="$derived/Build/Products/Debug/Calm.app"
    pkill -x Calm 2>/dev/null || true
    open "$app"
    ;;
  snapshot)
    # Launch the Debug app, save a PNG of its window, and quit (see Calm/App/SelfTest.swift).
    out="${2:?usage: $0 snapshot <out.png> [delay-seconds]}"
    app="$derived/Build/Products/Debug/Calm.app"
    pkill -x Calm 2>/dev/null || true
    CALM_SNAPSHOT="$out" CALM_SNAPSHOT_DELAY="${3:-1.5}" CALM_SNAPSHOT_QUIT=1 \
      "$app/Contents/MacOS/Calm" 2>&1 | grep -E '^calm-selftest:' || true
    ;;
  *)
    echo "usage: $0 build|test|run|snapshot" >&2
    exit 64
    ;;
esac
