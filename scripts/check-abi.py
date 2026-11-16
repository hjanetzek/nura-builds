#!/usr/bin/env python3
"""Published packages whose shared libraries are gone (docs/ci-plan.md): for each package of the
release "<arch>", the "so:" dependencies of its index entry that neither Alpine edge (main,
community, testing), postmarketOS edge nor the release itself provides any more (a soname change
in Alpine: ICU, Boost, OpenSSL, ...). Prints the origins (recipe directories) to rebuild, one per
line; update-check.yml starts sets.yml for them (or reports them).

Usage: check-abi.py ARCH [RELEASE_INDEX]      (without RELEASE_INDEX: downloaded with gh)
"""
import os
import subprocess
import sys
import tempfile
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import apkindex  # noqa: E402

MIRRORS = [
    "https://dl-cdn.alpinelinux.org/alpine/edge/main",
    "https://dl-cdn.alpinelinux.org/alpine/edge/community",
    "https://dl-cdn.alpinelinux.org/alpine/edge/testing",
    "https://mirror.postmarketos.org/postmarketos/master",
]


def provides(path):
    names = set()
    for b in apkindex.read_index(path)[1]:
        names.add(apkindex.field(b, "P"))
        for p in (apkindex.field(b, "p") or "").split():
            names.add(p.split("=")[0])
    return names


def main(argv):
    arch = argv[1]
    tmp = tempfile.mkdtemp()
    if len(argv) > 2:
        release = argv[2]
    else:
        subprocess.run(["gh", "release", "download", arch, "-p", "APKINDEX.tar.gz", "-D", tmp],
                       check=True)
        release = os.path.join(tmp, "APKINDEX.tar.gz")
    available = provides(release)
    for i, m in enumerate(MIRRORS):
        p = os.path.join(tmp, f"{i}.tar.gz")
        req = urllib.request.Request(f"{m}/{arch}/APKINDEX.tar.gz",
                                     headers={"User-Agent": "nura-builds-abi-check"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r, open(p, "wb") as f:
                f.write(r.read())
            available |= provides(p)
        except Exception as e:
            print(f"::warning::{m}/{arch}: {e}", file=sys.stderr)

    broken = {}
    for b in apkindex.read_index(release)[1]:
        missing = [d.split("=")[0] for d in (apkindex.field(b, "D") or "").split()
                   if d.startswith("so:") and d.split("=")[0] not in available]
        if missing:
            origin = apkindex.field(b, "o") or apkindex.field(b, "P")
            broken.setdefault(origin, set()).update(missing)
    for origin, libs in sorted(broken.items()):
        print(origin)
        print(f"  {origin}: {' '.join(sorted(libs))}", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv)
