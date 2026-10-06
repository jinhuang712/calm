# ghostty-mirror

Copies of Ghostty's build dependencies that come from somewhere less dependable than Ghostty's own
CDN (`deps.files.ghostty.org`) or GitHub, so a build doesn't stop when that host is down.
`scripts/ghostty-deps.py` looks here first. Each file is named like the download it stands for:
the package's Zig hash, then the archive's extension.

| File | From | License |
|---|---|---|
| `translate_c-0.0.0-Q_BUWhVNBwDOEcIqub4VFPJPB6D9dgwzUMHTX5KWr8Xr.tar.gz` | `codeberg.org/vancluever/translate-c`, commit `4e879eb` (Codeberg answered 503 on 2026-09-30 and failed two CI runs) | MIT (Zig contributors; the license is inside the archive) |

A copy cannot change what is built: `zig fetch` computes the hash of what is inside and the script
refuses anything that isn't the hash Ghostty pinned (a corrupt copy fails the build, it is never
skipped).

**To add or update one:** take the URL from Ghostty's `build.zig.zon.json`, download it, check that
`zig fetch <file>` prints exactly the hash, name the file `<hash>.<extension>`, check the license
allows redistribution and list it in `NOTICE` and in the table above. When Ghostty's pin moves and a
package's hash changes, the old file here is simply never looked for again; delete it.

Not mirrored: `fontconfig`, from `gitlab.freedesktop.org`. Its release archive exists only there (the
tag's archive on the same host has different contents, so a different hash), and a macOS build
probably doesn't need it, so `ghostty-deps.py` skips a package it can't download and leaves `zig
build` to say if it really was needed.
