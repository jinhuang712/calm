#!/usr/bin/env bash
# Fetches the viewer's JavaScript libraries at pinned versions and checks them (DESIGNS.md →
# Files and viewer). The files are committed, so builds stay offline; run this to update them.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/Calm/Resources/Viewer/vendor"
mkdir -p "$out"

fetch() {
  local name="$1" url="$2" sum="$3"
  curl -sfL --retry 3 -o "$out/$name.tmp" "$url"
  echo "$sum  $out/$name.tmp" | shasum -a 256 -c --quiet
  mv "$out/$name.tmp" "$out/$name"
  echo "✓ $name"
}

# markdown-it 15.0.2 (MIT)
fetch markdown-it.min.js \
  https://cdn.jsdelivr.net/npm/markdown-it@15.0.2/dist/browser/markdown-it.umd.min.js \
  635972b985228e8af9f0143647c68616b7a3bb09f6946e7e4a52e43dcf5e7be5

# highlight.js 11.12.0, common languages (BSD-3-Clause)
fetch highlight.min.js \
  https://cdn.jsdelivr.net/npm/@highlightjs/cdn-assets@11.12.0/highlight.min.js \
  8ab71eb09c51f501e5e25157d9cff100e46cc29bcbfc744d0b746d451fca7f53
