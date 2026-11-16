# CI restructuring: plan (2026-11-16)

Status (2026-11-16): phases 1–5 implemented on branch `ci-restructure` (not on main yet, not run on
GitHub yet); phase 6 (device workflows) open. Decisions taken: the plan's recommendations (sets
publish from main; project libraries stay in their repositories; targets by hand/weekly, no
`repository_dispatch`; the update check opens issues). Goal: individual packages can be updated without rebuilding
everything, the GitHub Actions cache stops being the package store, and zrythm is added as a
second target.

## What we build

| Category | What | Recipes live in | Built today by |
|---|---|---|---|
| 1. Base libraries | Qt 6.12 (6 modules), PySide6: replace Alpine's versions, link against Alpine's libraries | `aports/qt6`, `aports/pyside6` | stages qt1–qt3 and pyside of every target; weekly rebuild from scratch (`REBUILD_STAGES`) |
| 2. Plugins and engines | 70 LV2 plugins, 15 Pd externals, 7 engines (zynaddsubfx, setbfree, linuxsampler, aeolus, ...), zynthian-jalv | `aports/{lv2,pd,engines,zynthian-jalv}` | plugins stage; single recipes on `plugin-*` branches (`plugin.yml`, `packages.yml`) |
| 3. Project libraries | libraries only one project needs, e.g. zrythm's 9 deps (scnlib, magic-enum, type-safe, ...) | the project's repository (`zrythm/tools/nura/deps`) | built locally so far |
| 4. Targets (projects) | the nura'ified repositories: zynthian (zynthian-ui, zyncoder, webconf, packages, drivenbymoss, kiosk), zynthian's upstream variants; new: zrythm (branch `nura-duet`, recipes in `tools/nura/`, kiosk `postmarketos-ui-zrythm`) | the projects' repositories (`nura/`, `tools/nura/`) | the zynthian stage, always rebuilt |
| 5. Kernels and devices | s3ve3g (mainline 7.3.4), pixel3 (OTG), rpi4-rt, odroid-n2-rt: pmaports overlays and device packages | `overlays/<device>`, each on its own branch | per-device workflows (`galaxy-s3-neo.yml`, ...) |
| 6. Images | target × device (google-kukui, qemu-amd64; later s3ve3g, rpi4, ...) | – | the target's workflow |

Architectures, each with its own package set:
- aarch64: kukui, rpi4, odroid, pixel3
- x86_64: qemu
- armv7: s3ve3g; today with overrides such as `STAGE_plugins_armv7` (56 of the plugins) and
  `STAGES_armv7`, partly only on the branch `zynthian-arm7`, which is behind main

## Why everything gets rebuilt today

1. **Stages are chained.** A missing or changed cache entry of qt1 makes every later stage run:
   on 2026-11-16 the Qt stages' caches were evicted (the repository's caches are at 9.7 of GitHub's
   10 GB), and an armv7 zynthian build started with Qt.
2. **The cache is per stage, not per package.** The existing incremental logic: when a stage's
   exact key is missing, it restores its newest entry (partial match) and pmbootstrap builds only
   packages whose `pkgver-pkgrel` isn't in the repository. A recipe change without a pkgrel bump
   isn't rebuilt, and the stage still pulls in its predecessors.
3. **The Actions cache is the package store.** Eviction is a matter of time: plugins (1.6 GB per
   architecture) and the upstream variants (2–2.5 GB) push out the small Qt stages (25–60 MB),
   least recently used first.

## Proposal

### A. The release is the package repository

The existing releases `<arch>` (one apk repository per architecture) become the single source of
truth (2026-11-16: aarch64 210 packages / 2.6 GB, x86_64 161 / 2.2 GB, armv7 148 / 0.9 GB).

- Every build first fetches the published repository of its architecture (`scripts/fetch-released.sh`,
  about a minute), builds only what is missing or changed, and publishes merged.
- `publish.sh` merges instead of replacing: the new index is the published entries plus the
  build's (the build's version of a package replaces the old one), signed with the CI key;
  deleted are only files of packages the publishing workflow owns and no longer builds. Today it
  treats the build's repository as the whole release and deletes everything else, so separate
  workflows would delete each other's packages. The index can be merged as text, without
  downloading the packages.
- The Actions cache keeps only small things: pmaports, distfiles, ccache. Eviction no longer
  costs builds.
- Limit to watch: about 1000 files per release.

### B. A manifest instead of stage keys

- Each release gets a `manifest.json`: package → recipe hash (APKBUILD and its files), source
  repository/commit, workflow run, owner (set or target).
- A build compares the recipes with the manifest and builds exactly the changed ones.
- Dependents are rebuilt only on purpose: a recipe or set can declare that its dependents are
  rebuilt when it changes (`REBUILD_DEPENDENTS`, e.g. Qt → PySide → zynthian-ui); otherwise a
  `pkgrel` bump is enough.
- This replaces the stage chain. Qt keeps an order of its own (qtbase before qtdeclarative, ...),
  because the recipes ask for the other Qt modules without a version and Alpine's 6.11 would
  satisfy that; with the new Qt already in the fetched repository that only matters inside a Qt
  build.

### C. Package sets per architecture

One file per set (`sets/qt.sh`, `sets/plugins.sh`, `sets/zrythm-libs.sh`, ...) instead of stages in
the target file:
- `PACKAGES=` plus `PACKAGES_<arch>` / `EXCLUDE_<arch>`
- the APKBUILD's `arch=` stays authoritative: a set entry whose recipe doesn't list the
  architecture is skipped and noted in the run's summary
- `KEEPGOING` per set (as armv7's plugins today): one failing plugin doesn't stop the others and
  gets an issue (E)

### D. Workflows by category

| Workflow | Builds | Trigger | Publishes |
|---|---|---|---|
| `packages.yml` (generic) | the changed recipes of a set, for its architectures (matrix) | pushes to main that change the set's recipe directories (path filters per set); by hand (`set`, `arch`, `packages`, `force`) | yes, merged |
| `plugin.yml` (exists) | single recipes on `plugin-*` / `pkg-*` branches, built on the release instead of the cache | push | no (artifacts) |
| `zynthian.yml`, `zrythm.yml` | the project's packages from its checkouts (with its own libraries, category 3), optionally images | by hand, weekly, from the project's repository (below) | yes, merged |
| `kernels.yml` (device matrix) or one workflow per device | kernel and device package | push to the device branch, by hand | yes (same release) |
| `kernel-watch.yml` (exists for s3ve3g on `s3ve3g-kernel-next`) | our patches on new kernel.org releases | weekly | no; an issue when it breaks |
| `update-check.yml` (new, E) | – | weekly | issues |

- From the project repositories: a short workflow in zynthian-ui or zrythm sends a
  `repository_dispatch` to nura-builds on pushes to the nura branch (needs a token with access to
  nura-builds as a secret there). Without it: by hand or weekly, as now.
- Qt and plugins publish from main (per-package builds: a changed plugin recipe builds that
  plugin, a Qt change Qt and what `REBUILD_DEPENDENTS` names). Branches are for testing without
  publishing (`plugin-*`, `pkg-*`). Alternative: explicit branches (`qt*`, `plugins*`) as triggers
  of `packages.yml`.

### E. Weekly update check

`scripts/check-updates.sh`, workflow `update-check.yml`:
- **Upstream releases:** for every recipe the newest upstream version, from GitHub/GitLab releases
  or tags (from `url`/`source`), PyPI, Repology as a fallback; hints per recipe in `updates.conf`
  (package → source, version regex, ignore).
- **One issue per package**, "update `foo-lv2` 1.2 → 1.3", label `update`, written to hand to an
  agent: recipe path, upstream changelog link, the steps (bump `pkgver`, checksum, test build on a
  `pkg-foo` branch for all architectures of its set, merge). Existing issues are updated, not
  duplicated. Later: an agent picks up the issues automatically (or the check opens a PR with the
  bump when the test build passes).
- **Alpine ABI breakage instead of a blind weekly rebuild:** compare the `so:` dependencies of the
  published packages with what Alpine provides now; packages with a missing soname are rebuilt
  (or get an issue). Replaces `REBUILD_STAGES`: Qt is rebuilt from scratch only when Alpine
  changed a library it uses.
- **Kernels:** `kernel-watch` for all devices with mainline kernels, same pattern.

### F. Branches

- main carries all architectures and targets: merge `zynthian-arm7` (the armv7 overrides are
  written for that), and the device branches once they are stable.
- Branches are for testing. That also fixes that schedules and dispatchable workflows only work
  from main.

### G. Zrythm as a target

- `targets/zrythm.sh`: `REPOS="zrythm https://github.com/hjanetzek/zrythm nura-duet tools/nura"`
  (the fork on GitHub still to be checked: the local clone only has `github` → `zrythm/zrythm`)
- its 9 libraries (`tools/nura/deps`) as the project's library set: built from the checkout,
  published and update-checked like the other packages
- zrythm and the kiosk package `postmarketos-ui-zrythm` from the checkout
- aarch64 and x86_64 first; Qt 6.12 from the release if zrythm needs it; images zrythm × devices
  optional

## Deviations from the plan while implementing

- Publishing merges the index at publishing time, not at the build's start, and is serialized per
  architecture (concurrency group `publish-<arch>`), so two workflows can't drop each other's
  packages. The merge works on the index text (`scripts/apkindex.py`, no apk-tools needed), so
  publishing downloads no packages.
- Packages published before the manifest existed are adopted (recorded with their current recipe
  hash) instead of rebuilt.
- Qt is split into sets as the old stages were (qt-base, qt-declarative, qt-wayland, plus
  qt-tools for Zrythm), each a job under the 6 h limit, chained with `FORCE_AFTER`.
- Target stages keep pmbootstrap's own rule: a package whose version is published isn't rebuilt
  (Zrythm's libraries), `--src` packages always are.

## Order of implementation

1. Base, without changing behaviour: `fetch-released.sh`, `publish.sh` merging and the manifest;
   tested against a copy of the release (tag `test-<arch>`).
2. Per-package planning (`plan.sh` against the manifest) and package sets; `packages.yml` for Qt
   and plugins.
3. `zynthian.yml` on the release without the Qt and plugin stages; merge `zynthian-arm7` into main.
4. `zrythm.yml`, `targets/zrythm.sh`.
5. `update-check.yml` and the ABI check; `kernel-watch` for all devices.
6. Device workflows on the release.

## Open decisions

1. Qt and plugins publish from main with per-package builds (recommended), or from explicit
   branches (`qt*`, `plugins*`)?
2. Project libraries such as zrythm's: in the project's repository (recommended: they belong to
   the project), or in `nura-builds/aports`?
3. Triggers from the project repositories: `repository_dispatch` with a token, or by hand/weekly?
4. Update check: issues only for now, or a PR with the bump when the test build passes?
