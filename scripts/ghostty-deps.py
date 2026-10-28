#!/usr/bin/env python3
"""Pre-fetch Ghostty's Zig dependencies with curl.

Zig's own HTTP client fails behind some local HTTP proxies (it gets
"400 Bad Request"), while curl handles them fine. This downloads every
package listed in Ghostty's build.zig.zon.json with curl and loads it into
Zig's global package cache with `zig fetch`, so `zig build` never needs
the network.

Two things keep one unreachable host from stopping a build (Codeberg answered
503 for translate_c for a while, and 3 of Ghostty's 39 packages are not on its
own CDN or GitHub):

- A copy kept in scripts/ghostty-mirror/ (named like the download, by the
  package's hash) is used first, without the network. Zig checks every package
  against that hash, so a copy cannot change what gets built.
- A package that cannot be downloaded is reported and skipped, not fatal:
  `zig build` fetches again only what it really needs, and says which package
  it could not get. (Fontconfig is Linux-only, for one.)

Usage: ghostty-deps.py <ghostty-src-dir> <download-dir>
"""

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

MIRROR = Path(__file__).resolve().parent / "ghostty-mirror"


def zig_cache_has(src: Path, hash_key: str) -> bool:
    # Zig 0.16 resolves packages from the project-local zig-pkg directory.
    return (src / "zig-pkg" / hash_key).exists()


def place_in_project(src: Path, hash_key: str, archive: Path) -> None:
    """Unpack a fetched package into the project's zig-pkg, the way Zig 0.16 did.

    0.17's `zig fetch` keeps the archive in its global cache, and its `zig build` unpacks it again
    into zig-pkg. On this setup (macOS 27, 0.17.0) that unpacking fails ("failed to delete
    temporary directory ... DirNotEmpty") and leaves the archive's top folder in place, so the
    package hashes to something else and the build stops with "hash mismatch ... N-V-__8AA…".
    Zig takes a package that is already in zig-pkg as it is. `zig build --system` would read
    the cache instead but crashes the 0.17.0 compiler ("reached unreachable code").
    A single top folder is dropped, as Zig does.
    """
    target = src / "zig-pkg" / hash_key
    if target.exists():
        return
    staging = src / "zig-pkg" / f".unpack-{hash_key}"
    shutil.rmtree(staging, ignore_errors=True)
    staging.mkdir(parents=True)
    if subprocess.run(["tar", "-xf", str(archive), "-C", str(staging)]).returncode != 0:
        shutil.rmtree(staging, ignore_errors=True)
        return
    entries = list(staging.iterdir())
    root = entries[0] if len(entries) == 1 and entries[0].is_dir() else staging
    root.rename(target)
    shutil.rmtree(staging, ignore_errors=True)


def tarball_url(url: str) -> str:
    """Turn git+https://github.com/o/r#commit into a GitHub archive URL (Codeberg's has the same shape)."""
    m = re.match(r"git\+https://(github\.com|codeberg\.org)/([^/]+)/([^#?]+?)(?:\.git)?(?:\?[^#]*)?#([0-9a-f]{7,40})$", url)
    if m:
        host, owner, repo, commit = m.groups()
        return f"https://{host}/{owner}/{repo}/archive/{commit}.tar.gz"
    return url


def download(url: str, target: Path) -> bool:
    """Fetches `url` to `target` with curl; False (and nothing left behind) if it can't be had."""
    result = subprocess.run(
        ["curl", "-fsSL", "--retry", "3", "--connect-timeout", "20", "--max-time", "300", "-o", str(target), url],
    )
    if result.returncode != 0:
        target.unlink(missing_ok=True)  # a partial file would be taken for a finished download next run
        return False
    return True


def main() -> int:
    src, downloads = Path(sys.argv[1]), Path(sys.argv[2])
    downloads.mkdir(parents=True, exist_ok=True)
    deps = json.loads((src / "build.zig.zon.json").read_text())
    failed = []
    unreachable = []
    for hash_key, dep in deps.items():
        if zig_cache_has(src, hash_key):
            continue
        url = tarball_url(dep["url"])
        if not url.startswith("https://"):
            failed.append((dep["name"], f"unsupported url {dep['url']}"))
            continue
        suffix = next((ext for ext in (".tar.gz", ".tar.xz", ".tar.zst", ".tgz", ".zip") if url.endswith(ext)), ".tar.gz")
        target = downloads / f"{hash_key}{suffix}"
        mirrored = MIRROR / f"{hash_key}{suffix}"
        if mirrored.exists():
            print(f"  using the copy of {dep['name']} in scripts/ghostty-mirror")
            target = mirrored
        elif not target.exists():
            print(f"  downloading {dep['name']}")
            if not download(url, target):
                unreachable.append((dep["name"], url))
                continue
        result = subprocess.run(["zig", "fetch", str(target)], capture_output=True, text=True, cwd=src)
        got = result.stdout.strip()
        if result.returncode != 0 or got != hash_key:
            failed.append((dep["name"], f"expected {hash_key}, got {got or result.stderr.strip()}"))
        else:
            place_in_project(src, hash_key, target)
    for name, url in unreachable:
        print(f"  could not download {name} from {url}; zig build will try again if it needs it", file=sys.stderr)
    for name, why in failed:
        print(f"  could not prefetch {name}: {why}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
