#!/usr/bin/env bash
# Type-checks the app and the CLI as macOS 14.5 (Calm's minimum, project.yml) against the newest SDK,
# which flags every call that needs a newer macOS and has no `#available` guard. The build and the
# tests run on the runner's own macOS, so nothing else would notice such a call.
# Needs GhosttyKit (`mise run ghosttykit`) for its header; CalmKit is built here at its own minimum.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

modulemap="$(find Frameworks/GhosttyKit.xcframework -name module.modulemap 2>/dev/null | head -1 || true)"
if [[ -z "$modulemap" ]]; then
  echo "typecheck-min-os.sh: no GhosttyKit in Frameworks/; run mise run ghosttykit first" >&2
  exit 1
fi
headers="$(dirname "$modulemap")"

(cd Packages/CalmKit && swift build >/dev/null)
modules="$(cd Packages/CalmKit && swift build --show-bin-path)/Modules"

for target in Calm CLI; do
  echo "Type-checking $target for macOS 14.5…"
  find "$target" -name '*.swift' -print0 | xargs -0 swiftc -typecheck \
    -target arm64-apple-macos14.5 -swift-version 6 -D DEBUG \
    -I "$modules" -I "$headers" -Xcc "-fmodule-map-file=$root/$modulemap"
done
