#!/usr/bin/env bash
# Installs Calm Terminal from its newest GitHub release: the disk image's app into /Applications,
# with macOS's download mark taken off, and the `calm` command linked into ~/.local/bin.
#   curl -fsSL https://raw.githubusercontent.com/jinhuang712/calm/main/get.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/jinhuang712/calm/main/get.sh | bash -s -- --version 0.1.0
# Options: --version X.Y.Z (default: the newest release), --dir <folder> (default /Applications),
# --bin-dir <folder> (default ~/.local/bin), --no-cli (no `calm` link).
# To build Calm from this checkout instead, run ./install.sh. A running Calm isn't quit (your
# shells live on in it); restart it afterwards, as ./install.sh says too.
#
# It runs only from main(), at the end, so a download cut short runs nothing.
set -euo pipefail

repo="jinhuang712/calm"
mounted=""
work=""

# Its own text, since piped into bash the script has no file to read the comments above from.
usage() {
  cat <<'EOF'
Installs Calm Terminal from its newest GitHub release into /Applications.
  curl -fsSL https://raw.githubusercontent.com/jinhuang712/calm/main/get.sh | bash -s -- [options]
  --version X.Y.Z   that release instead of the newest
  --dir <folder>    install the app there instead of /Applications
  --bin-dir <dir>   link `calm` there instead of ~/.local/bin
  --no-cli          don't link `calm`
EOF
}
step() { printf '\033[1m==>\033[0m %s\n' "$*"; }
fail() { echo "get.sh: $*" >&2; exit 1; }

cleanup() {
  if [[ -n "$mounted" ]]; then hdiutil detach -quiet "$mounted" 2>/dev/null || true; fi
  if [[ -n "$work" ]]; then rm -rf "$work"; fi
}

# GitHub's API allows 60 requests an hour per address without a token; a token raises that.
github() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" "$@"
  else
    curl -fsSL "$@"
  fi
}

main() {
  local version="" app_dir="/Applications" bin_dir="$HOME/.local/bin" link_cli=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version) version="${2:?--version needs a version, like 0.1.0}"; version="${version#v}"; shift 2 ;;
      --dir) app_dir="${2:?--dir needs a folder}"; shift 2 ;;
      --bin-dir) bin_dir="${2:?--bin-dir needs a folder}"; shift 2 ;;
      --no-cli) link_cli=0; shift ;;
      -h | --help) usage; return 0 ;;
      *) echo "get.sh: unknown option $1" >&2; exit 64 ;;
    esac
  done

  [[ "$(uname -s)" == Darwin ]] || fail "Calm is a macOS app."
  [[ "$(uname -m)" == arm64 ]] || fail "Calm needs a Mac with Apple silicon."
  local macos
  macos="$(sw_vers -productVersion)"
  [[ "${macos%%.*}" -ge 26 ]] || fail "Calm needs macOS 26 or later; this Mac has $macos."
  # Homebrew keeps its own record of the app it installed; replacing the app under it would
  # leave that record wrong.
  local prefix
  for prefix in /opt/homebrew /usr/local; do
    if [[ -d "$prefix/Caskroom/calm" ]]; then
      fail "Homebrew installed this Calm. Update it with \`brew upgrade --cask calm\`, or run \`brew uninstall --cask calm\` first to switch."
    fi
  done

  # The newest release, pre-releases included (Calm's are, before 1.0), or the one asked for.
  local api="https://api.github.com/repos/$repo/releases" release
  if [[ -n "$version" ]]; then
    release="$(github "$api/tags/v$version")" || fail "GitHub has no release v$version of Calm."
  else
    release="$(github "$api?per_page=5")" || fail "couldn't ask GitHub for Calm's releases."
    release="$(jq '[.[] | select(.draft | not)][0] // empty' <<<"$release")"
    [[ -n "$release" ]] || fail "Calm has no release yet."
  fi
  version="$(jq -r '.tag_name | ltrimstr("v")' <<<"$release")"
  local name="Calm-$version.dmg" url digest
  url="$(jq -r --arg name "$name" '.assets[] | select(.name == $name) | .browser_download_url' <<<"$release")"
  digest="$(jq -r --arg name "$name" '.assets[] | select(.name == $name) | .digest // empty' <<<"$release")"
  [[ -n "$url" ]] || fail "release v$version has no $name."

  work="$(mktemp -d -t calm-get)"
  trap cleanup EXIT
  step "Downloading Calm $version"
  curl -fL --progress-bar -o "$work/$name" "$url"
  if [[ "$digest" == sha256:* && "$(shasum -a 256 "$work/$name" | cut -d' ' -f1)" != "${digest#sha256:}" ]]; then
    fail "the download doesn't match the release's checksum; nothing was installed."
  fi

  mkdir -p "$app_dir"
  [[ -w "$app_dir" ]] || fail "can't write to $app_dir. Run again with --dir ~/Applications."
  mkdir "$work/mount"
  hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$work/mount" "$work/$name"
  mounted="$work/mount"
  [[ -d "$mounted/Calm.app" ]] || fail "the disk image holds no Calm.app."

  # Copied beside the old app first, then swapped in with two renames, so a failed copy never
  # leaves no Calm. A running Calm keeps working from the old app, moved aside: deleting the file
  # a running app came from stops macOS letting it show the folder picker (DESIGNS.md →
  # Distribution). Older copies go once nothing runs from them. ./install.sh does the same.
  local target="$app_dir/Calm.app" staging="$app_dir/.Calm.app.installing" was="" running=0
  step "Installing to $target"
  rm -rf "$staging"
  ditto "$mounted/Calm.app" "$staging"
  hdiutil detach -quiet "$mounted"
  mounted=""
  if pgrep -xq Calm; then running=1; fi
  if [[ -e "$target" ]]; then
    was="$(defaults read "$target/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
    mv "$target" "$app_dir/.Calm.app.previous-$(date +%Y%m%d-%H%M%S)-$$"
  fi
  mv "$staging" "$target"
  # Calm isn't signed with a Developer ID yet, so macOS won't open it with a download mark on it.
  # curl leaves none, but a copy made through a browser would. /usr/bin/xattr, not whatever
  # `xattr` is first on PATH: Homebrew's python xattr has no -r.
  /usr/bin/xattr -dr com.apple.quarantine "$target"
  local lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$lsregister" -f "$target" >/dev/null 2>&1 || true
  local in_use old
  in_use="$(lsof -a -c Calm -d txt -Fn 2>/dev/null | sed -n 's/^n//p' || true)"
  for old in "$app_dir"/.Calm.app.previous*; do
    [[ -e "$old" ]] || continue
    grep -qF "$old/" <<<"$in_use" || rm -rf "$old"
  done

  if [[ $link_cli -eq 1 ]]; then
    mkdir -p "$bin_dir"
    ln -sf "$target/Contents/Resources/bin/calm" "$bin_dir/calm"
    step "Linked $bin_dir/calm"
    case ":$PATH:" in
      *":$bin_dir:"*) ;;
      *) echo "    Note: $bin_dir isn't on your PATH." ;;
    esac
  fi

  if [[ -n "$was" && "$was" != "$version" ]]; then
    step "Calm $was → $version installed."
  else
    step "Calm $version installed."
  fi
  if [[ $running -eq 1 ]]; then
    step "Restart Calm soon (Calm → Restart Calm): until then the running one is out of date, and its shells can lose access to Documents, Desktop and Downloads."
  else
    step "Open Calm from $app_dir. macOS asks for access to Desktop, Documents and Downloads when Calm first needs them."
  fi
}

main "$@"
