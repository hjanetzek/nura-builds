#!/usr/bin/env python3
"""Newer upstream versions of nura-builds' recipes (aports/), for the weekly update check
(update-check.yml, docs/ci-plan.md): one line (or JSON entry) per recipe with an update.

Where the newest version comes from:
- GitHub (source or url on github.com): the latest release, else the highest version tag; for
  snapshot versions (<x>_git<YYYYMMDD>) the newest commit on the default branch, reported when it
  is more than SNAPSHOT_DAYS newer than the snapshot (or a release newer than it exists)
- download.qt.io (Qt, PySide): the newest release in Qt's official_releases directory
- otherwise Repology (the newest version any distribution has)
updates.conf (next to aports/) adjusts this per recipe: "<pkgname> skip", "<pkgname> github
<owner>/<repo>", "<pkgname> repology <project>", "<pkgname> ignore <version regex>".

Usage: check-updates.py [--json OUT] [PKGNAME...]     (GH_TOKEN for GitHub's API)
"""
import datetime
import json
import os
import re
import subprocess
import sys
import urllib.request

here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SNAPSHOT_DAYS = 60
UA = {"User-Agent": "nura-builds-update-check"}


def get(url, headers=None):
    req = urllib.request.Request(url, headers=dict(UA, **(headers or {})))
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode()


def gh(path):
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if not token:
        try:
            token = subprocess.run(["gh", "auth", "token"], stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL, check=True).stdout.decode().strip()
        except Exception:
            token = None
    h = {"Accept": "application/vnd.github+json"}
    if token:
        h["Authorization"] = f"Bearer {token}"
    return json.loads(get(f"https://api.github.com/{path}", h))


def vkey(v):
    """Comparable key of a version: numbers numerically, letters after (1.2 < 1.2.1 < 1.10)"""
    return [(0, int(p), "") if p.isdigit() else (1, 0, p) for p in re.findall(r"\d+|[a-z]+", v.lower())]


def clean(tag):
    """A tag as a version: without a leading name and "v" (v1.2.3, foo-1.2.3, release_1_2)"""
    t = re.sub(r"^[^\d]*?(?=\d)", "", tag)
    if re.fullmatch(r"\d+(_\d+)+", t):
        t = t.replace("_", ".")
    return t


def is_version(t):
    return bool(re.fullmatch(r"\d+(\.\d+)*([a-z]\d*)?", t)) and not re.search(r"(rc|alpha|beta|pre)", t)


def recipe_info(path):
    script = ('. ./APKBUILD >/dev/null 2>&1; printf "%s\\0%s\\0%s\\0%s" "$pkgname" "$pkgver" '
              '"$url" "$(printf "%s\\n" $source | grep "://" | sed "s/^[^:]*:://")"')
    out = subprocess.run(["sh", "-c", script], cwd=path, stdout=subprocess.PIPE,
                         stdin=subprocess.DEVNULL, check=True).stdout.decode().split("\0")
    return {"pkgname": out[0], "pkgver": out[1], "url": out[2], "sources": out[3].split()}


def github_repo(info):
    for u in info["sources"] + [info["url"]]:
        m = re.match(r"https?://(?:codeload\.)?github\.com/([^/]+)/([^/#?]+)", u)
        if m:
            return f"{m.group(1)}/{m.group(2).removesuffix('.git')}"
    return None


def newest_github(repo, current):
    snap = re.match(r"(.*)_git(\d{8})$", current)
    best = None
    try:
        rel = gh(f"repos/{repo}/releases/latest")
        t = clean(rel["tag_name"])
        if is_version(t):
            best = t
    except Exception:
        pass
    if best is None:
        try:
            tags = [clean(t["name"]) for t in gh(f"repos/{repo}/tags?per_page=100")]
            tags = [t for t in tags if is_version(t)]
            if tags:
                best = max(tags, key=vkey)
        except Exception:
            pass
    if snap:
        base, date = snap.group(1), datetime.datetime.strptime(snap.group(2), "%Y%m%d")
        if best and base not in ("0", "") and vkey(best) > vkey(base):
            return best, f"release {best} (snapshot of {snap.group(2)})"
        try:
            meta = gh(f"repos/{repo}")
            c = gh(f"repos/{repo}/commits/{meta['default_branch']}")
            cdate = datetime.datetime.strptime(c["commit"]["committer"]["date"][:10], "%Y-%m-%d")
            if (cdate - date).days > SNAPSHOT_DAYS:
                v = f"{base}_git{cdate:%Y%m%d}"
                return v, f"newer commits ({c['sha'][:10]}, {cdate:%Y-%m-%d})"
        except Exception as e:
            return None, f"github: {e}"
        return None, None
    return best, None


def newest_qt(info):
    if "QtForPython" in " ".join(info["sources"]):
        listing = get("https://download.qt.io/official_releases/QtForPython/pyside6/")
        vs = re.findall(r"PySide6-(\d+\.\d+\.\d+)-src/", listing)
    else:
        listing = get("https://download.qt.io/official_releases/qt/")
        minors = sorted(set(re.findall(r'href="(\d+\.\d+)/"', listing)), key=vkey)
        vs = re.findall(r'href="(\d+\.\d+\.\d+)/"', get(f"https://download.qt.io/official_releases/qt/{minors[-1]}/"))
    return max(vs, key=vkey) if vs else None


def newest_repology(project):
    data = json.loads(get(f"https://repology.org/api/v1/project/{project}"))
    vs = [p["version"] for p in data if p.get("status") == "newest"]
    return max(vs, key=vkey) if vs else None


def main(argv):
    out_json = None
    if "--json" in argv:
        i = argv.index("--json")
        out_json = argv[i + 1]
        del argv[i:i + 2]
    only = set(argv[1:])
    conf = {}
    p = os.path.join(here, "updates.conf")
    if os.path.exists(p):
        for line in open(p):
            parts = line.split("#")[0].split()
            if len(parts) >= 2:
                conf.setdefault(parts[0], []).append(parts[1:])

    updates, notes = [], []
    for root, dirs, files in sorted(os.walk(os.path.join(here, "aports"))):
        if "APKBUILD" not in files:
            continue
        dirs[:] = []
        info = recipe_info(root)
        name, cur = info["pkgname"], info["pkgver"]
        if only and name not in only:
            continue
        rules = {r[0]: r[1:] for r in conf.get(name, [])}
        if "skip" in rules or not info["sources"]:
            continue
        rel = os.path.relpath(root, here)
        try:
            why = None
            if "repology" in rules:
                new, src = newest_repology(rules["repology"][0]), "repology"
            elif "github" in rules or github_repo(info):
                repo = rules["github"][0] if "github" in rules else github_repo(info)
                new, why = newest_github(repo, cur)
                src = f"https://github.com/{repo}"
            elif any("download.qt.io" in s for s in info["sources"]):
                new, src = newest_qt(info), "https://download.qt.io/official_releases/"
            else:
                project = re.sub(r"-lv2$", "", name)
                new, src = newest_repology(project), f"https://repology.org/project/{project}"
        except Exception as e:
            notes.append(f"{name}: {e}")
            continue
        if not new or new == cur:
            continue
        if "ignore" in rules and re.fullmatch(rules["ignore"][0], new):
            continue
        if "_git" not in cur and vkey(new) <= vkey(cur):
            continue
        updates.append({"pkgname": name, "current": cur, "new": new, "recipe": rel,
                        "source": src, "note": why or ""})
        print(f"{name}: {cur} -> {new} ({src}{', ' + why if why else ''})", flush=True)
    for n in notes:
        print(f"::warning::{n}")
    if out_json:
        json.dump(updates, open(out_json, "w"), indent=1)


if __name__ == "__main__":
    main(sys.argv)
