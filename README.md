# nura-builds

Builds Nura (postmarketOS) packages and images for apps whose recipes live in their own
repositories, on GitHub Actions (native arm64 runners, free for public repositories) or locally.

Targets so far:

| Target | What | Devices |
|---|---|---|
| `zynthian` | zynthian with the Qt Quick UI: Qt 6.12, PySide6, zyncoder, zynthian-data, zynthian-ui, zynthian-packages (the content pack catalogue), zynthian-webconf, the kiosk package | Lenovo IdeaPad Duet (`google-kukui`); Raspberry Pi 4 with a zynthian kit (`zynthian-rpi4`, to test: [docs/zynthian-rpi.md](docs/zynthian-rpi.md), [docs/rpi-plan.md](docs/rpi-plan.md)); QEMU (`qemu-amd64`); Samsung Galaxy S III Neo (`qcom-msm8226`, armv7) |
| `zrythm` | Zrythm (the DAW) in a labwc kiosk session: its libraries, zrythm from the checkout of `hjanetzek/zrythm` (`nura`), `postmarketos-ui-zrythm`; recipes in Zrythm's `tools/nura/` | Lenovo IdeaPad Duet (`google-kukui`), QEMU (`qemu-amd64`) |
| (in `zynthian`) | zynthian-ui from upstream (`zynthian-ui-vangelis`, `zynthian-ui-tomita`): the Tk UI with the port patches, packages only, see [docs/zynthian-upstream.md](docs/zynthian-upstream.md) | as above |

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
  history (2026-11-06); zynthian's own recipes (zynthian-ui, zyncoder, zyncoder-hw, zynthian-data,
  zynthian-hw, the kiosk package postmarketos-ui-zynthian) and deploy.sh followed on 2026-11-19
  (`aports/zynthian`, [its README](aports/zynthian/README.md)). How to package more: [docs/packaging-guide.md](docs/packaging-guide.md);
  zynthian's plugins on Nura: [docs/lv2-plugins.md](docs/lv2-plugins.md); upstream updates:
  `scripts/check-updates.py` (weekly in `update-check.yml`).
- `scripts/setup.sh` installs pmbootstrap, writes its config (edge, systemd, PipeWire), initialises
  the work dir, links the recipes, installs the signing key and restores built packages.
- `scripts/pin-binary.sh` (run by setup.sh) pins the devices' packages (device package, kernel,
  SoC and firmware packages) to the versions in postmarketOS's binary repository: when pmaports
  already has a newer recipe than the published package, pmbootstrap would build it (the Duet's
  kernel: a full clang/Rust build); instead the recipe is checked out at the newest pmaports commit
  with the published version.
- **The package repository is the store** ([docs/ci-plan.md](docs/ci-plan.md)): the releases
  `<arch>` (aarch64, x86_64, armv7). Every build starts from the published repository of its
  architecture (`scripts/fetch-released.sh`), builds what is missing or changed, and publishes
  merged (`scripts/publish.sh`: the published index plus the new packages, signed with the CI key;
  serialized per architecture across workflows, concurrency group `publish-<arch>`). The Actions
  cache holds no packages.
- **Package sets** (`sets/`, workflow `sets.yml`): Qt 6.12 and PySide6 for armv7 (`qt-base`,
  `qt-declarative`, `qt-wayland`, `pyside`; aarch64 and x86_64 use Alpine's, see
  `aports/qt6/README.md` and `sets/dropped.sh`), Qt TaskTree and Canvas Painter for Zrythm
  (`qt-tools`), the plugins (LV2, Pure Data, engines, zynthian's jalv), Mesa (armv7), PREEMPT_RT kernels
  (`kernels`: linux-rpi-rt, linux-postmarketos-amlogic-rt) and our device packages (`devices/`, set
  `devices`: zynthian-rpi4, the ODROID N2 with its U-Boot, [docs/odroid-n2.md](docs/odroid-n2.md)),
  with their architectures and per-architecture lists. `scripts/plan-packages.py` compares each
  recipe with the published index and `manifest.json` (per package: recipe hash, version, set or
  target, run): it builds what is new, has another version or a changed recipe (with `--force`),
  and a set's dependents when `FORCE_AFTER` says so (Qt Quick after qtbase, ...). On pushes to
  `main` that change `aports/` or `sets/` only the changed packages are built.
- **Targets** (`targets/<target>.sh`, workflows `zynthian.yml`, `zrythm.yml` on
  `build-target.yml`): the target's own packages from the checkouts of its repositories, on top of
  the published repository, then optionally the images (`scripts/image.sh DEVICE` writes
  `$NURA_OUT/<target>-<device>.img.zst`). By hand, weekly per architecture, and on pushes that
  change the target.
- **Checks** (`update-check.yml`, Mondays): newer upstream versions of the recipes
  (`scripts/check-updates.py`, settings in `updates.conf`) as one issue per recipe (label
  `update`, with the steps for an agent), and published packages whose shared libraries
  Alpine/postmarketOS dropped (`scripts/check-abi.py`), rebuilt through `sets.yml`. Instead of a
  blind weekly rebuild of Qt.
- `.github/workflows/packages.yml` builds single packages by name on the published repository
  (see below).

zynthian's stages: `zynthian` (zyncoder, zynthian-ui, DrivenByMoss, zynthian-packages and
zynthian-webconf from their checkouts, zynthian-data, postmarketos-ui-zynthian; always rebuilt)
and `upstream` (zynthian-ui from upstream's vangelis and tomita with the port patches). Zrythm's:
`deps` (its libraries; built when their version isn't published yet) and `zrythm`.

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

- **amd64**: the same for x86_64, built weekly (Sunday 05:00 UTC) and when asked for (Actions >
  zynthian > Run workflow, architecture `x86_64`; pushes build aarch64 only): release
  [`x86_64`](../../releases/tag/x86_64) at the same repository URL (apk asks for
  `<repository>/x86_64/APKINDEX.tar.gz`), and with `images` the QEMU image
  `zynthian-qemu-amd64.img.zst` in `zynthian-latest`. On x86-64 runners; cache keys
  `packages-zynthian_x86_64-<stage>-...` (`NURA_ARCH`, `DEVICES_x86_64` in the target file).

- **armv7**: zynthian for 32-bit ARM phones, first the Samsung Galaxy S III Neo (`samsung-s3ve3g`,
  MSM8226): `zynthian.yml` with architecture `armv7` (and weekly), release
  [`armv7`](../../releases/tag/armv7), images in `zynthian-armv7-latest`. Only part of the plugins
  (`sets/plugins.sh`: `PACKAGES_armv7`), so no kiosk package; the image has UI `none` with
  zynthian-ui installed. The device is the generic mainline port `qcom-msm8226`. Recipes of the
  other repositories that list only `aarch64 x86_64` get `armv7` added in the checkouts
  (`ADD_ARCH_armv7`). On arm64 runners: armv7 natively where the CPU runs 32-bit code, under QEMU
  otherwise.

```sh
gh workflow run packages.yml --ref my-branch -f packages="dexed-lv2 eq10q-lv2"
gh run download <run id>
```

## New plugins on plugin-* branches

`plugin.yml` builds new or changed recipes before they go into the zynthian target: a push to a
`plugin-*` branch builds each recipe directory of `aports/lv2`, `aports/pd` or `aports/engines`
that the branch changes against `main`, one job per package (through `packages.yml`, on the
published package repository), each with its own log and `.apk` artifact. The zynthian
workflow doesn't run for these branches. When a package builds (and runs on a device), add it to
the meta package (`zynthian-lv2-plugins`, `zynthian-puredata`) (for armv7: `PACKAGES_armv7` in
`sets/plugins.sh`) and merge to `main`: `sets.yml` builds and publishes just that package.

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
| `NURA_IMAGE_PASSWORD` | the user's password in images (default: the target's `IMAGE_PASSWORD`, zynthian `raspberry`, else `147147`) |

Without a key, each run signs with a new one: packages of different runs don't trust each other
and the published repository can't be merged into. Create a key once (`openssl genrsa -out nura-ci.rsa 4096`) and store
it as the secret; a device installed from another image needs its public key in `/etc/apk/keys`
to install packages from these builds (as `aports/zynthian/deploy.sh -k` does for the local work dir).

## Running it locally

On an aarch64 machine, or x86_64 with qemu-user registered for aarch64 (slow for Qt):

```sh
export NURA_WORK=$HOME/nura-work NURA_SRC=$HOME/nura-src
scripts/setup.sh
scripts/fetch-released.sh              # the published packages (Qt, PySide, plugins); needs gh
scripts/build.sh zynthian
scripts/image.sh google-kukui
```

If Zrythm's `tools/nura` is linked into the same pmaports checkout as a whole, its Qt recipes and
these are duplicates: the target zrythm links its recipe directories without `qt6`.

To try a branch on a device without pmbootstrap or sudo on the host, `tools/vm-deploy.sh` builds in
the builder VM (zynthian-ui's `tools/run_qemu.sh`, SSH port 2240) with these same scripts and
installs the result over SSH, then restarts zynthian checked (zynthian-ui's `tools/restart_ui.py`):

```sh
tools/vm-deploy.sh -d duet -U ../zynthian-ui-mybranch            # zynthian-ui from a worktree
tools/vm-deploy.sh -d s3 zynthian-ui zyncoder                   # armv7, both checkouts
tools/vm-deploy.sh -d pi zynthian-data                          # a recipe of aports/
```

Devices `duet`, `pi`, `pixel`, `s3`, `vm` (or `-H HOST -a ARCH`); the first build of an
architecture sets up pmbootstrap in the VM and downloads the architecture's release as the base.

## Adding a target

Write `targets/<name>.sh` (repositories with their recipe directories, stages, UI, devices) and a
workflow like `zrythm.yml` (build-target.yml, then publish); dependencies shared with other
targets go to `aports/` and a package set (`sets/`).

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
