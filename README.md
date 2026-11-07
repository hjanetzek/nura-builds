# nura-builds

Builds Nura (postmarketOS) packages and images for apps whose recipes live in their own
repositories, on GitHub Actions (native arm64 runners, free for public repositories) or locally.

Targets so far:

| Target | What | Devices |
|---|---|---|
| `zynthian` | zynthian with the Qt Quick UI: Qt 6.12, PySide6, zyncoder, zynthian-data, zynthian-ui, DrivenByMoss (drivenbymoss, dbm-nihost), the kiosk package | Lenovo IdeaPad Duet (`google-kukui`); Raspberry Pi 4 planned |

Next: the Google Pixel 3 (`google-blueline`), see [docs/google-blueline.md](docs/google-blueline.md):
device status, USB OTG (missing on all SDM845 phones; patches on the kernel lists), plan.

## How it works

- `targets/<target>.sh` names the source repositories (cloned into `$NURA_SRC`, recipe directories
  linked into pmbootstrap's pmaports), the build stages and the devices.
- `aports/` holds recipes shared by several apps: Qt 6.12 (`aports/qt6/`, newer than Alpine's 6.11;
  copied from Zrythm's `tools/nura/qt6`, see `aports/qt6/README.md`), PySide6 (`aports/pyside6`),
  LV2 plugins (`aports/lv2`, with the meta package `zynthian-lv2-plugins`), Pure Data and its
  externals (`aports/pd`), engines (`aports/engines`: ZynAddSubFX, setBfree, SooperLooper) and
  zynthian's jalv (`aports/zynthian-jalv`). These came from zynthian-ui's `nura/` with their
  history (2026-11-06). How to package more: [docs/packaging-guide.md](docs/packaging-guide.md);
  zynthian's plugins on Nura: [docs/lv2-plugins.md](docs/lv2-plugins.md); upstream updates:
  `tools/check-updates.py`.
- `scripts/setup.sh` installs pmbootstrap, writes its config (edge, systemd, PipeWire), initialises
  the work dir, links the recipes, installs the signing key and restores built packages.
- `scripts/pin-binary.sh` (run by setup.sh) pins the devices' packages (device package, kernel,
  SoC and firmware packages) to the versions in postmarketOS's binary repository: when pmaports
  already has a newer recipe than the published package, pmbootstrap would build it (the Duet's
  kernel: a full clang/Rust build); instead the recipe is checked out at the newest pmaports commit
  with the published version.
- `scripts/build.sh STAGE` builds one stage and saves the local package repository
  (`$NURA_OUT/packages.tar`); `scripts/image.sh DEVICE` writes an image
  (`$NURA_OUT/<target>-<device>.img.zst`).
- `.github/workflows/<target>.yml` runs the stages as jobs (`stage.yml`), each on a fresh runner:
  stages stay under the 6 h job limit, and a stage whose recipes (and all earlier stages) are
  unchanged takes its packages from the Actions cache. A stage whose recipes changed starts from
  its last cached packages (same earlier stages) and builds only the packages whose
  `pkgver-pkgrel` isn't there yet: bump `pkgrel` with a recipe change. A failed stage saves what
  it built too (key `…-partial-<run>`, never an exact match), and the next run continues from
  there. A plan job (`scripts/plan.sh`) computes all stage keys first: a stage cached under its
  exact key doesn't start at all (the next stage takes its packages from the cache), so a run with
  unchanged Qt takes about 8 minutes. Then one image job per device.
- Weekly (Sunday 01:00 UTC), and by hand with the `rebuild` input, the stages in `REBUILD_STAGES`
  (Qt, PySide) are built from scratch and replace their cached packages: they replace Alpine's
  versions and link against its libraries, so a soname change in Alpine would break them without
  any change to their recipes.
- `.github/workflows/packages.yml` builds single packages by name (see below).

zynthian's stages: `qt1` (qtbase, qtshadertools, qtsvg, qtlanguageserver), `qt2` (qtdeclarative),
`qt3` (qtwayland), `pyside` (PySide6 6.12), `plugins`
(zynthian's jalv, the LV2 plugins and Pure Data externals of `aports/lv2` and `aports/pd` through
their meta packages, zynaddsubfx, setBfree, SooperLooper), `zynthian`
(zyncoder, zynthian-ui and DrivenByMoss from their checkouts, zynthian-data, postmarketos-ui-zynthian; always
rebuilt). The Qt modules are separate stages because their recipes ask for the other modules
without a version, which Alpine's 6.11 would satisfy.

## Downloads

Builds on `main` are published as releases of this repository (`scripts/publish.sh`):

- **Images**: release [`zynthian-latest`](../../releases/tag/zynthian-latest), replaced by each build
  (e.g. `zynthian-google-kukui.img.zst`; write with `zstd -d < FILE | sudo dd of=/dev/sdX bs=4M`).
- **Package repository**: release [`aarch64`](../../releases/tag/aarch64) is an apk repository at
  `https://github.com/hjanetzek/nura-builds/releases/download` (apk asks for
  `<repository>/aarch64/APKINDEX.tar.gz`, and the release's files are at `.../download/aarch64/`).
  Signed with [`keys/nura-builds-ci.rsa.pub`](keys/nura-builds-ci.rsa.pub); images built here
  trust it already. On another device:

  ```sh
  wget -O /etc/apk/keys/nura-builds-ci.rsa.pub https://raw.githubusercontent.com/hjanetzek/nura-builds/main/keys/nura-builds-ci.rsa.pub
  echo https://github.com/hjanetzek/nura-builds/releases/download >> /etc/apk/repositories
  apk update && apk upgrade
  ```

Workflow artifacts (packages per stage, images) stay for a few days for debugging.

## Building single packages

`packages.yml` (by hand) builds named packages, e.g. new recipes on a branch, without the whole
target: it starts from the newest cached packages of the `plugins` stage (Qt,
PySide, the plugins) and uploads the built `.apk` files and the build log as the artifact
`packages-<run id>`. The named packages are always rebuilt, their dependencies only when missing
or outdated.

```sh
gh workflow run packages.yml --ref my-branch -f packages="dexed-lv2 eq10q-lv2"
gh run download <run id>
```

## New plugins on plugin-* branches

`plugin.yml` builds new or changed recipes before they go into the zynthian target: a push to a
`plugin-*` branch builds each recipe directory of `aports/lv2`, `aports/pd` or `aports/engines`
that the branch changes against `main`, one job per package (through `packages.yml`, on the
cached packages of the plugins stage), each with its own log and `.apk` artifact. The zynthian
workflow doesn't run for these branches. When a package builds (and runs on a device), add it to
the meta package (`zynthian-lv2-plugins`, `zynthian-puredata`) or, for an engine, to
`STAGE_plugins`, and merge to `main`.

```sh
git switch -c plugin-foo-lv2      # add aports/lv2/foo-lv2/APKBUILD
git push -u origin plugin-foo-lv2
gh run list -w plugin -L 1
```

## Secrets

| Secret | Purpose |
|---|---|
| `NURA_ABUILD_KEY` | private key that signs the packages (PEM) |
| `NURA_ABUILD_KEY_NAME` | its file name, e.g. `pmos@local-6ae1d406.rsa` |
| `NURA_IMAGE_PASSWORD` | the user's password in images (default `147147`) |

Without a key, each run signs with a new one: packages of different runs don't trust each other
and the cache is of no use. Create a key once (`openssl genrsa -out nura-ci.rsa 4096`) and store
it as the secret; a device installed from another image needs its public key in `/etc/apk/keys`
to install packages from these builds (as `nura/deploy.sh -k` does for the local work dir).

## Running it locally

On an aarch64 machine, or x86_64 with qemu-user registered for aarch64 (slow for Qt):

```sh
export NURA_WORK=$HOME/nura-work NURA_SRC=$HOME/nura-src
scripts/setup.sh
for stage in qt1 qt2 qt3 pyside zynthian; do scripts/build.sh $stage; done
scripts/image.sh google-kukui
```

If Zrythm's `tools/nura` is linked into the same pmaports checkout, its Qt recipes and these are
duplicates: link only one of them.

## Adding a target

Write `targets/<name>.sh` (repositories, stages, inputs, devices) and a workflow calling
`stage.yml` per stage; shared dependencies go to `aports/`.

## Status

As of 2026-11-06:

- **zynthian** builds completely on GitHub: Qt 6.12, PySide6, the plugins stage (jalv, LV2 plugins,
  Pure Data, engines), the zynthian packages and the Duet image (first successful run 2026-11-05).
  With the stages cached, a run takes about 25 minutes (Qt and PySide restored from the cache in a
  minute each, plugins about 10 minutes when rebuilt, zynthian 4, image 5); the device kernel comes
  from postmarketOS's binary repository (`pin-binary.sh`), not built.
- **Publishing** as releases (`zynthian-latest`, the `aarch64` package repository) is new. To check:
  the CI image on the Duet, and `apk update`/`upgrade` from the releases repository (apk following
  GitHub's download redirect).
- **Pixel 3**: work on `pixel3-*` branches (see [docs/google-blueline.md](docs/google-blueline.md)
  there). zynthian runs on it from these builds (rotated to landscape, scaled, touch rotated with
  it). The SDM845 kernel from an overlay of pmaports' recipe, with the USB Type-C/OTG patch series
  backported to its 7.1-rc1 base and the ALSA sequencer enabled: **USB host mode works**, with USB
  MIDI and USB audio in zynthian (tested through a powered USB-C hub, which also charges the phone
  and gives it Ethernet). Not tested yet: bus-powered devices without a hub (the phone's VBUS),
  device mode (USB networking to a PC) with this kernel.
- The Qt 6.12 recipes in `aports/qt6/` are a copy of Zrythm's (`tools/nura/qt6`): keep them in step,
  and link only one of them into a local pmaports checkout.
