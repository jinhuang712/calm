#!/usr/bin/env python3
"""Pre-fetch Ghostty's Zig dependencies with curl.

Zig's own HTTP client fails behind some local HTTP proxies (it gets
"400 Bad Request"), while curl handles them fine. This downloads every
package listed in Ghostty's build.zig.zon.json with curl and loads it into
Zig's global package cache with `zig fetch`, so `zig build` never needs
the network.

Usage: ghostty-deps.py <ghostty-src-dir> <download-dir>
"""

import json
import re
import subprocess
import sys
from pathlib import Path


def zig_cache_has(src: Path, hash_key: str) -> bool:
    # Zig 0.16 resolves packages from the project-local zig-pkg directory.
    return (src / "zig-pkg" / hash_key).exists()


def tarball_url(url: str) -> str:
    """Turn git+https://github.com/o/r#commit into a GitHub archive URL."""
    m = re.match(r"git\+https://github\.com/([^/]+)/([^#?]+?)(?:\.git)?(?:\?[^#]*)?#([0-9a-f]{7,40})$", url)
    if m:
        owner, repo, commit = m.groups()
        return f"https://github.com/{owner}/{repo}/archive/{commit}.tar.gz"
    return url


def main() -> int:
    src, downloads = Path(sys.argv[1]), Path(sys.argv[2])
    downloads.mkdir(parents=True, exist_ok=True)
    deps = json.loads((src / "build.zig.zon.json").read_text())
    failed = []
    for hash_key, dep in deps.items():
        if zig_cache_has(src, hash_key):
            continue
        url = tarball_url(dep["url"])
        if not url.startswith("https://"):
            failed.append((dep["name"], f"unsupported url {dep['url']}"))
            continue
        suffix = next((ext for ext in (".tar.gz", ".tar.xz", ".tar.zst", ".tgz", ".zip") if url.endswith(ext)), ".tar.gz")
        target = downloads / f"{hash_key}{suffix}"
        if not target.exists():
            print(f"  downloading {dep['name']}")
            subprocess.run(["curl", "-fsSL", "--retry", "3", "-o", str(target), url], check=True)
        result = subprocess.run(["zig", "fetch", str(target)], capture_output=True, text=True, cwd=src)
        got = result.stdout.strip()
        if result.returncode != 0 or got != hash_key:
            failed.append((dep["name"], f"expected {hash_key}, got {got or result.stderr.strip()}"))
    for name, why in failed:
        print(f"  could not prefetch {name}: {why}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
