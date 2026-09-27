#!/usr/bin/env bash
# Builds GhosttyKit.xcframework and Ghostty's runtime resources from the
# pinned upstream Ghostty commit (scripts/ghostty.env), then copies them into
# Frameworks/. Builds are cached per commit under ~/Library/Caches/calm, so
# worktrees and repeat runs reuse the same build.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/ghostty.env
source "$root/scripts/ghostty.env"

cache="${CALM_CACHE_DIR:-$HOME/Library/Caches/calm}/ghostty/$GHOSTTY_COMMIT"
src="$cache/src"
out="$cache/out"
dest="$root/Frameworks"

if [[ -f "$dest/.ghostty-commit" && "$(cat "$dest/.ghostty-commit")" == "$GHOSTTY_COMMIT" ]]; then
  echo "GhosttyKit $GHOSTTY_REF is up to date."
  exit 0
fi

if [[ ! -d "$out/GhosttyKit.xcframework" ]]; then
  if [[ ! -d "$src/.git" ]]; then
    echo "Fetching Ghostty $GHOSTTY_REF ($GHOSTTY_COMMIT)…"
    rm -rf "$src"
    mkdir -p "$src"
    git -C "$src" init -q
    git -C "$src" remote add origin https://github.com/ghostty-org/ghostty.git
    git -C "$src" fetch -q --depth 1 origin "$GHOSTTY_COMMIT"
    git -C "$src" checkout -q FETCH_HEAD
  fi

  echo "Fetching Ghostty's dependencies…"
  python3 "$root/scripts/ghostty-deps.py" "$src" "$cache/downloads"

  echo "Building GhosttyKit (this takes a while the first time)…"
  (
    cd "$src"
    zig build \
      -Doptimize=ReleaseFast \
      -Demit-xcframework=true \
      -Demit-macos-app=false \
      -Dxcframework-target=native \
      -Di18n=false \
      -Dsentry=false
  )

  rm -rf "$out"
  mkdir -p "$out"
  cp -R "$src/macos/GhosttyKit.xcframework" "$out/"
  if [[ -d "$src/zig-out/share" ]]; then
    cp -R "$src/zig-out/share" "$out/share"
  fi
fi

mkdir -p "$dest"
rsync -a --delete "$out/GhosttyKit.xcframework/" "$dest/GhosttyKit.xcframework/"
if [[ -d "$out/share" ]]; then
  rsync -a --delete "$out/share/" "$dest/ghostty-share/"
fi
echo "$GHOSTTY_COMMIT" > "$dest/.ghostty-commit"
echo "GhosttyKit $GHOSTTY_REF ready in Frameworks/."
