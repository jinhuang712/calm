#!/usr/bin/env bash
# Puts an installed Calm.app on a disk image, and checks a disk image as a download.
#   scripts/disk-image.sh make <Calm.app> <volume name> <out.dmg>
#   scripts/disk-image.sh check <Calm.dmg> <version the app must say>
# Shared by release.yml (a tag's disk image) and edge.yml (the newest main's), so both ship what
# the same checks passed. `check` starts a Calm and kills every Calm afterwards, so it runs only
# on a CI runner ($CI is set there), never on a Mac someone works on.
set -euo pipefail

fail() { echo "disk-image.sh: $*" >&2; exit 1; }

# The app, beside a link to /Applications to drag it onto.
make() {
  local app="${1:?make needs the Calm.app}" volume="${2:?make needs a volume name}" dmg="${3:?make needs the .dmg to write}"
  local stage try
  stage="$(mktemp -d -t calm-dmg)"
  ditto "$app" "$stage/Calm.app"
  ln -s /Applications "$stage/Applications"
  # hdiutil now and then finds the folder busy on a runner (something indexing it).
  for try in 1 2 3 4 5; do
    if hdiutil create -volname "$volume" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg"; then
      break
    fi
    [[ $try -lt 5 ]] || { rm -rf "$stage"; exit 1; }
    sleep 10
  done
  rm -rf "$stage"
}

# As someone who downloads it gets it: a browser marks the file quarantined, and what is copied
# off it carries the mark. The README's xattr step takes it off; the app must then be whole, the
# version it says, and start and answer its calm.
check() {
  local dmg="${1:?check needs the .dmg}" version="${2:?check needs a version}"
  [[ -n "${CI:-}" ]] || fail "check starts and kills Calm; run it only on a CI runner."
  local work mount app built listed=""
  work="$(mktemp -d -t calm-dmg-check)"
  mount="$work/mount"
  app="$work/download/Calm.app"
  mkdir -p "$mount" "$work/download"
  xattr -w com.apple.quarantine "0083;$(printf %x "$(date +%s)");Safari;" "$dmg"
  hdiutil attach -nobrowse -readonly -mountpoint "$mount" "$dmg"
  [[ "$(readlink "$mount/Applications")" == /Applications ]] || fail "the disk image's Applications isn't a link to /Applications"
  ditto "$mount/Calm.app" "$app"
  hdiutil detach "$mount"
  if ! xattr -r -l "$app" | grep -q com.apple.quarantine; then
    xattr -w -r com.apple.quarantine "0083;$(printf %x "$(date +%s)");Safari;" "$app"
  fi
  /usr/bin/xattr -dr com.apple.quarantine "$app"
  if xattr -r -l "$app" | grep -q com.apple.quarantine; then
    fail "the README's xattr step left a quarantine mark"
  fi
  codesign --verify --deep --strict --verbose=2 "$app"
  built="$(defaults read "$app/Contents/Info" CFBundleShortVersionString)"
  [[ "$built" == "$version" ]] || fail "the disk image's app says $built, not $version"
  # `calm list` starts the Calm it came with when none answers; a first launch on a fresh
  # machine can take longer than its 5 seconds, so it asks again for up to a minute.
  for _ in $(seq 12); do
    if "$app/Contents/Resources/bin/calm" list; then
      listed=1
      break
    fi
    sleep 5
  done
  pkill -x Calm || true
  rm -rf "$work"
  [[ -n "$listed" ]] || fail "the downloaded Calm didn't start and answer"
}

case "${1:-}" in
  make | check) action="$1"; shift; "$action" "$@" ;;
  *) echo "usage: scripts/disk-image.sh make <Calm.app> <volume name> <out.dmg> | check <Calm.dmg> <version>" >&2; exit 64 ;;
esac
