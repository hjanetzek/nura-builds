#!/usr/bin/env python3
"""Which packages of the package sets (sets/) have to be built for an architecture, against the
published package repository (docs/ci-plan.md): per package (recipe directory)

- not published (no package with it as origin in the index): build ("new")
- published with another version than the recipe's pkgver-pkgrel: build
- same version, but the recipe's hash differs from the one in the manifest: build with --force
- a set in FORCE_AFTER builds something on this architecture: build everything, with --force
- same version and no manifest entry (published before the manifest existed): up to date; listed
  as "adopt", so that publishing records its hash

Usage: plan-packages.py --arch ARCH --index APKINDEX.tar.gz|- --manifest manifest.json|-
                        [--sets "a b"] [--packages "x y"] [--force] [--json OUT]
  --packages: only these packages (in whatever set they are), always built (--force with --force)
  --force: everything selected, with --force (the weekly rebuild of a set, by hand)
Prints a summary; --json writes {"sets": {set: [{"pkg", "force", "reason"}]}, "adopt": {pkg: entry},
"hashes": {pkg: entry}} (entry: {"version", "hash", "set"}).
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(here, "scripts"))
import apkindex  # noqa: E402


def shell_vars(path, names):
    """Variables of a shell file (set file, APKBUILD), evaluated by bash (dash, Ubuntu's sh, aborts on
    some APKBUILDs: they are written for ash)"""
    script = '. "$1" >/dev/null 2>&1; ' + "; ".join(
        f'printf "%s\\0" "${{{n}:-}}"' for n in names)
    out = subprocess.run(["bash", "-c", script, "bash", path], stdout=subprocess.PIPE,
                         check=True, cwd=os.path.dirname(path)).stdout.decode()
    return dict(zip(names, out.split("\0")))


def recipes():
    """recipe directory name -> path, for nura-builds' recipes (aports/, devices/)"""
    found = {}
    for top in ("aports", "devices"):
        for root, dirs, files in os.walk(os.path.join(here, top)):
            if "APKBUILD" in files:
                found.setdefault(os.path.basename(root), root)
                dirs[:] = []
    return found


def recipe_hash(path):
    """Hash of a recipe directory: the APKBUILD and every file next to it (as stage_hash)"""
    h = hashlib.sha256()
    for root, dirs, files in os.walk(path):
        dirs[:] = sorted(d for d in dirs if d != ".git")
        for f in sorted(files):
            p = os.path.join(root, f)
            h.update(os.path.relpath(p, path).encode() + b"\0")
            with open(p, "rb") as fh:
                h.update(hashlib.sha256(fh.read()).digest())
    return h.hexdigest()[:16]


def flags_extra(arch, set_cflags):
    """What the compiler flags add to a recipe's hash on an architecture: the CPU baseline when
    scripts/abuild-cpu.conf has flags for it (an "<arch>)" branch), and the set's CFLAGS_<arch>;
    empty otherwise, so the other architectures' hashes stay as they were"""
    with open(os.path.join(here, "scripts", "abuild-cpu.conf")) as f:
        conf = f.read()
    extra = conf if re.search(rf"^\s*{re.escape(arch)}\)", conf, re.M) else ""
    # the service manager the packages are built for, when it isn't systemd (as stage_hash)
    target = os.path.join(here, "targets", os.environ.get("TARGET", "zynthian") + ".sh")
    sm = shell_vars(target, [f"SERVICE_MANAGER_{arch}"])[f"SERVICE_MANAGER_{arch}"]
    if sm and sm != "systemd":
        extra += "\0service manager: " + sm
    if set_cflags:
        extra += "\0cflags: " + set_cflags
    return extra


def package_hash(path, extra):
    h = recipe_hash(path)
    if not extra:
        return h
    return hashlib.sha256((h + "\0" + extra).encode()).hexdigest()[:16]


def arch_ok(arch_field, arch, add_arch):
    archs = arch_field.split()
    if add_arch or "noarch" in archs:
        return True
    if f"!{arch}" in archs:
        return False
    return arch in archs or "all" in archs


def set_packages(name, arch, recipe_dirs):
    """The set's packages for an architecture, as groups (lists), and its settings"""
    path = os.path.join(here, "sets", f"{name}.sh")
    v = shell_vars(path, ["ARCHES", "PACKAGES", "DIRS", f"PACKAGES_{arch}", f"EXCLUDE_{arch}",
                          "FORCE_AFTER", "KEEPGOING", f"ADD_ARCH_{arch}", f"CFLAGS_{arch}"])
    if arch not in v["ARCHES"].split():
        return None, v
    spec = v[f"PACKAGES_{arch}"] or v["PACKAGES"]
    groups = [g.split() for g in spec.split(";") if g.split()]
    if not v[f"PACKAGES_{arch}"] and v["DIRS"]:
        listed = {p for g in groups for p in g}
        extra = []
        for d in v["DIRS"].split():
            base = os.path.join(here, d)
            for name_, p in sorted(recipe_dirs.items()):
                if (p == base or p.startswith(base + os.sep)) and name_ not in listed:
                    extra.append(name_)
        if extra:
            groups.append(extra)
    exclude = set(v[f"EXCLUDE_{arch}"].split())
    groups = [[p for p in g if p not in exclude] for g in groups]
    return [g for g in groups if g], v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--arch", required=True)
    ap.add_argument("--index", default="-")
    ap.add_argument("--manifest", default="-")
    ap.add_argument("--sets", default="")
    ap.add_argument("--packages", default="")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--json")
    a = ap.parse_args()

    published = {}   # origin -> version
    if a.index != "-" and os.path.exists(a.index):
        for b in apkindex.read_index(a.index)[1]:
            # the newest of the origin's entries (an index can list several versions)
            origin = apkindex.field(b, "o") or apkindex.field(b, "P")
            v = apkindex.field(b, "V")
            if origin not in published or apkindex.version_key(v) > apkindex.version_key(published[origin]):
                published[origin] = v
    manifest = {}
    if a.manifest != "-" and os.path.exists(a.manifest):
        with open(a.manifest) as f:
            manifest = json.load(f).get("packages", {})

    order = open(os.path.join(here, "sets", "order")).read().split()
    wanted_sets = a.sets.split() or order
    only = set(a.packages.split())
    recipe_dirs = recipes()
    result, adopt, hashes, building = {}, {}, {}, set()
    missing = []

    for s in order:
        if s not in wanted_sets and not only:
            continue
        groups, v = set_packages(s, a.arch, recipe_dirs)
        if groups is None:
            continue
        add_arch = {os.path.basename(p) for p in v[f"ADD_ARCH_{a.arch}"].split()}
        forced_by = [d for d in v["FORCE_AFTER"].split() if d in building]
        extra = flags_extra(a.arch, v[f"CFLAGS_{a.arch}"])
        todo = []
        for g in groups:
            for pkg in g:
                if only and pkg not in only:
                    continue
                path = recipe_dirs.get(pkg)
                if not path:
                    missing.append(f"{s}: {pkg}")
                    continue
                r = shell_vars(os.path.join(path, "APKBUILD"), ["pkgver", "pkgrel", "arch"])
                if not arch_ok(r["arch"], a.arch, pkg in add_arch):
                    continue
                version = f'{r["pkgver"]}-r{r["pkgrel"]}'
                entry = {"version": version, "hash": package_hash(path, extra), "set": s}
                hashes[pkg] = entry
                pub, known = published.get(pkg), manifest.get(pkg)
                if only:
                    todo.append({"pkg": pkg, "force": a.force or pub == version, "reason": "asked for"})
                elif a.force:
                    todo.append({"pkg": pkg, "force": True, "reason": "forced"})
                elif forced_by:
                    todo.append({"pkg": pkg, "force": True, "reason": f"after {' '.join(forced_by)}"})
                elif pub is None:
                    todo.append({"pkg": pkg, "force": False, "reason": "new"})
                elif pub != version:
                    todo.append({"pkg": pkg, "force": False, "reason": f"{pub} -> {version}"})
                elif known is None:
                    adopt[pkg] = entry
                elif known.get("hash") != entry["hash"]:
                    todo.append({"pkg": pkg, "force": True, "reason": "recipe changed"})
        if todo:
            result[s] = todo
            building.add(s)

    for s, todo in result.items():
        print(f"{a.arch} {s}: " + ", ".join(f'{t["pkg"]} ({t["reason"]})' for t in todo))
    if not result:
        print(f"{a.arch}: nothing to build")
    if adopt:
        print(f"{a.arch}: {len(adopt)} published packages without manifest entry (adopted)")
    for m in missing:
        print(f"::warning::no recipe for {m}")
    if a.json:
        with open(a.json, "w") as f:
            json.dump({"arch": a.arch, "sets": result, "adopt": adopt, "hashes": hashes}, f, indent=1)


if __name__ == "__main__":
    main()
