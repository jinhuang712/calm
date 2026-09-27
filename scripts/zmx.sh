#!/usr/bin/env bash
# Downloads the pinned zmx release (session persistence, MIT, https://zmx.sh), verifies its
# checksum, caches it, and copies the binary to Frameworks/bin/zmx for bundling.
set -euo pipefail

ZMX_VERSION=0.8.1
ZMX_SHA256=1d86b1c9fba47fa707a6f0e976b20510b07c1c26d0ed010b9414b2a2c5e6beef

root="$(cd "$(dirname "$0")/.." && pwd)"
cache="${CALM_CACHE_DIR:-$HOME/Library/Caches/calm}/zmx/$ZMX_VERSION"
dest="$root/Frameworks/bin"

if [[ ! -x "$cache/zmx" ]]; then
  echo "Fetching zmx ${ZMX_VERSION}…"
  mkdir -p "$cache"
  curl -fsSL --retry 3 -o "$cache/zmx.tar.gz" "https://zmx.sh/a/zmx-$ZMX_VERSION-macos-aarch64.tar.gz"
  echo "$ZMX_SHA256  $cache/zmx.tar.gz" | shasum -a 256 -c --quiet
  tar -xzf "$cache/zmx.tar.gz" -C "$cache"
  rm "$cache/zmx.tar.gz"
fi

mkdir -p "$dest"
cp "$cache/zmx" "$dest/zmx"
echo "zmx ${ZMX_VERSION} ready in Frameworks/bin/."
