#!/usr/bin/env bash
# Collects the full license texts of what Calm bundles into Calm/Resources/Licenses (shipped in
# the app, as the MIT and BSD licenses require). Run when a bundled component changes.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/Calm/Resources/Licenses"
mkdir -p "$out"
source "$root/scripts/ghostty.env"

curl -sfL --retry 3 -o "$out/Ghostty.txt" "https://raw.githubusercontent.com/ghostty-org/ghostty/$GHOSTTY_COMMIT/LICENSE"
curl -sfL --retry 3 -o "$out/zmx.txt" https://raw.githubusercontent.com/neurosnap/zmx/main/LICENSE
curl -sfL --retry 3 -o "$out/markdown-it.txt" https://cdn.jsdelivr.net/npm/markdown-it@15.0.2/LICENSE
curl -sfL --retry 3 -o "$out/highlight.js.txt" https://cdn.jsdelivr.net/npm/@highlightjs/cdn-assets@11.12.0/LICENSE
# The agent marks taken from these repositories (NOTICE → Agent marks).
curl -sfL --retry 3 -o "$out/OpenCode.txt" https://raw.githubusercontent.com/anomalyco/opencode/dev/LICENSE
curl -sfL --retry 3 -o "$out/Codex.txt" https://raw.githubusercontent.com/openai/codex/main/LICENSE

for file in "$out"/*.txt; do
  echo "✓ $(basename "$file"): $(head -3 "$file" | tr '\n' ' ' | cut -c1-80)"
done
