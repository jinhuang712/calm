#!/usr/bin/env bash
# Collects the full license texts of what Calm bundles into Calm/Resources/Licenses (shipped in
# the app, as the MIT, BSD, OFL, LGPL and MPL licenses require; NOTICE says what each is for).
# Run when a bundled component changes, or when the Ghostty pin does: the engine's own
# dependencies are read from its source, so run scripts/ghosttykit.sh first.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/Calm/Resources/Licenses"
mkdir -p "$out"
source "$root/scripts/ghostty.env"

fetch() { curl -sfL --retry 3 -o "$out/$1" "$2"; }

fetch Ghostty.txt "https://raw.githubusercontent.com/ghostty-org/ghostty/$GHOSTTY_COMMIT/LICENSE"
fetch zmx.txt https://raw.githubusercontent.com/neurosnap/zmx/main/LICENSE
fetch markdown-it.txt https://cdn.jsdelivr.net/npm/markdown-it@15.0.2/LICENSE
fetch highlight.js.txt https://cdn.jsdelivr.net/npm/@highlightjs/cdn-assets@11.12.0/LICENSE
# The agent marks taken from these repositories (NOTICE → Agent marks).
fetch OpenCode.txt https://raw.githubusercontent.com/anomalyco/opencode/dev/LICENSE
fetch Codex.txt https://raw.githubusercontent.com/openai/codex/main/LICENSE
fetch pi.txt https://raw.githubusercontent.com/badlogic/pi-mono/main/LICENSE

# What Ghostty's engine links in, embeds or ships beside it, at the versions the pin builds
# (NOTICE → Ghostty's engine). The source tree is the one scripts/ghosttykit.sh builds.
patches=("$root"/scripts/ghostty-patches/*.patch)
patches_id="$(cat "${patches[@]}" | shasum -a 256 | cut -c1-12)"
src="${CALM_CACHE_DIR:-$HOME/Library/Caches/calm}/ghostty/$GHOSTTY_COMMIT-$patches_id/src"
[[ -d "$src/zig-pkg" ]] || { echo "licenses.sh: no engine source at $src; run scripts/ghosttykit.sh first" >&2; exit 1; }

# A dependency's folder, by its name in the build.zig.zon files (Ghostty's, its pkg/ ones and
# those of the packages it fetched). Entries that only point at a local path are skipped.
dep() {
  local hash
  hash="$(awk -v name=".$1" '
    $1 == name && $2 == "=" && $0 !~ /\.path/ { inside = 1 }
    inside && /\.hash/ { match($0, /"[^"]*"/); print substr($0, RSTART + 1, RLENGTH - 2); exit }
    inside && /}/ && !/\.\{/ { inside = 0 }
  ' "$src/build.zig.zon" "$src"/pkg/*/build.zig.zon "$src"/zig-pkg/*/build.zig.zon)"
  if [[ -z "$hash" || ! -d "$src/zig-pkg/$hash" ]]; then
    echo "licenses.sh: no package for $1 in $src" >&2
    exit 1
  fi
  echo "$src/zig-pkg/$hash"
}

# Linked into the engine (C and C++ libraries).
cp "$(dep freetype)/docs/FTL.TXT" "$out/FreeType.txt"
cp "$(dep zlib)/LICENSE" "$out/zlib.txt"
cp "$(dep libpng)/LICENSE" "$out/libpng.txt"
cp "$(dep oniguruma)/COPYING" "$out/Oniguruma.txt"
cp "$(dep glslang)/LICENSE.txt" "$out/glslang.txt"
cp "$(dep spirv_cross)/LICENSE" "$out/SPIRV-Cross.txt"
cp "$(dep highway)/LICENSE" "$out/Highway.txt"
cp "$(dep wuffs)/LICENSE-MIT" "$out/wuffs.txt"
cp "$(dep imgui)/LICENSE.txt" "$out/Dear-ImGui.txt"
cp "$(dep gettext)/gettext-runtime/intl/COPYING.LIB" "$out/libintl-LGPL-2.1.txt"
simdutf="$(sed -n 's/^#define SIMDUTF_VERSION "\(.*\)"$/\1/p' "$src/pkg/simdutf/vendor/simdutf.h")"
fetch simdutf.txt "https://raw.githubusercontent.com/simdutf/simdutf/v$simdutf/LICENSE-MIT"
fetch stb.txt https://raw.githubusercontent.com/nothings/stb/master/LICENSE
fetch dear_bindings.txt https://raw.githubusercontent.com/dearimgui/dear_bindings/main/LICENSE.txt
# Zig packages compiled into it, and Zig's own standard library.
cp "$(dep libxev)/LICENSE" "$out/libxev.txt"
cp "$(dep uucode)/LICENSE.md" "$out/uucode.txt"
fetch Unicode.txt https://raw.githubusercontent.com/jacobsandlund/uucode/main/licenses/LICENSE_unicode
fetch Bjoern-Hoehrmann.txt https://raw.githubusercontent.com/jacobsandlund/uucode/main/licenses/LICENSE_Bjoern_Hoehrmann
cp "$(dep vaxis)/LICENSE" "$out/vaxis.txt"
cp "$(dep zigimg)/LICENSE" "$out/zigimg.txt"
cp "$(dep zf)/LICENSE" "$out/zf.txt"
cp "$(dep zig_objc)/LICENSE" "$out/zig-objc.txt"
dep z2d >/dev/null # z2d ships no license file; its sources say MPL-2.0.
fetch z2d-MPL-2.0.txt https://www.mozilla.org/media/MPL/2.0/index.txt
cp "$(mise where zig)/LICENSE" "$out/Zig.txt"
# Fonts embedded in it.
cp "$(dep jetbrains_mono)/OFL.txt" "$out/JetBrains-Mono-OFL.txt"
cp "$(dep nerd_fonts_symbols_only)/LICENSE" "$out/Symbols-Nerd-Font.txt"
# Shipped beside it in Resources/ghostty: the themes, and the shell integration scripts (bash's
# and zsh's are GPL-3.0, started from kitty's; bash-preexec is MIT).
fetch iTerm2-Color-Schemes.txt https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/master/LICENSE
fetch bash-preexec.txt https://raw.githubusercontent.com/rcaloras/bash-preexec/master/LICENSE.md
fetch GPL-3.0.txt https://www.gnu.org/licenses/gpl-3.0.txt

for file in "$out"/*.txt; do
  echo "✓ $(basename "$file"): $(head -3 "$file" | tr '\n' ' ' | cut -c1-80)"
done
