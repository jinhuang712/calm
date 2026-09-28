#!/usr/bin/env bash
# Builds GhosttyKit.xcframework and Ghostty's runtime resources from the
# pinned upstream Ghostty commit (scripts/ghostty.env) with Calm's patches
# (scripts/ghostty-patches) applied, then copies them into Frameworks/.
# Builds are cached per commit and patch set under ~/Library/Caches/calm, so
# worktrees and repeat runs reuse the same build.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/ghostty.env
source "$root/scripts/ghostty.env"

# Applied in name order. A build is named by the commit and a hash of the
# patches, so changing a patch never reuses a build made without it.
patches=("$root"/scripts/ghostty-patches/*.patch)
patches_id="$(cat "${patches[@]}" | shasum -a 256 | cut -c1-12)"
build="$GHOSTTY_COMMIT-$patches_id"

cache_root="${CALM_CACHE_DIR:-$HOME/Library/Caches/calm}/ghostty"
cache="$cache_root/$build"
src="$cache/src"
out="$cache/out"
dest="$root/Frameworks"

if [[ -f "$dest/.ghostty-build" && "$(cat "$dest/.ghostty-build")" == "$build" ]]; then
  echo "GhosttyKit $GHOSTTY_REF (patches $patches_id) is up to date."
  exit 0
fi

if [[ ! -d "$out/GhosttyKit.xcframework" ]]; then
  # A checkout is reused only once every patch is in: a run stopped halfway
  # starts over rather than building a half-patched tree.
  if [[ ! -f "$src/.calm-patches" || "$(cat "$src/.calm-patches")" != "$patches_id" ]]; then
    echo "Fetching Ghostty $GHOSTTY_REF ($GHOSTTY_COMMIT)…"
    rm -rf "$src"
    mkdir -p "$src"
    git -C "$src" init -q
    git -C "$src" remote add origin https://github.com/ghostty-org/ghostty.git
    git -C "$src" fetch -q --depth 1 origin "$GHOSTTY_COMMIT"
    git -C "$src" checkout -q FETCH_HEAD

    for patch in "${patches[@]}"; do
      echo "Applying $(basename "$patch")…"
      if ! git -C "$src" apply --check "$patch"; then
        echo "error: $(basename "$patch") does not apply to Ghostty $GHOSTTY_COMMIT." >&2
        echo "Take the patches from the $GHOSTTY_PATCHES_FROM commit whose parent is that commit" >&2
        echo "(see scripts/ghostty-patches/README.md)." >&2
        exit 1
      fi
      git -C "$src" apply "$patch"
    done
    echo "$patches_id" > "$src/.calm-patches"
  fi

  echo "Fetching Ghostty's dependencies…"
  # Downloads are named by content hash, so every build shares them.
  python3 "$root/scripts/ghostty-deps.py" "$src" "$cache_root/downloads"

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
rm -f "$dest/.ghostty-commit" # the stamp before patches were part of a build
echo "$build" > "$dest/.ghostty-build"
echo "GhosttyKit $GHOSTTY_REF (patches $patches_id) ready in Frameworks/."
