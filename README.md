# nura-builds

Builds Nura (postmarketOS) packages and images for apps whose recipes live in their own
repositories, on GitHub Actions (native arm64 runners, free for public repositories) or locally.

Targets so far:

| Target | What | Devices |
|---|---|---|
| `zynthian` | zynthian with the Qt Quick UI: Qt 6.12, PySide6, zyncoder, zynthian-data, zynthian-ui, the kiosk package | Lenovo IdeaPad Duet (`google-kukui`); Raspberry Pi 4 planned |

Next: the Google Pixel 3 (`google-blueline`), see [docs/google-blueline.md](docs/google-blueline.md):
device status, USB OTG (missing on all SDM845 phones; patches on the kernel lists), plan.

## How it works

- `targets/<target>.sh` names the source repositories (cloned into `$NURA_SRC`, recipe directories
  linked into pmbootstrap's pmaports), the build stages and the devices.
- `aports/` holds recipes shared by several apps: Qt 6.12 (`aports/qt6/`, newer than Alpine's 6.11;
  copied from Zrythm's `tools/nura/qt6`, see `aports/qt6/README.md`).
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
  unchanged takes its packages from the Actions cache. Then one image job per device.

zynthian's stages: `qt1` (qtbase, qtshadertools, qtsvg, qtlanguageserver), `qt2` (qtdeclarative),
`qt3` (qtwayland), `pyside` (PySide6 6.12, from zynthian-ui's `nura/pyside6`), `plugins`
(zynthian's jalv, the LV2 plugins and Pure Data externals of `nura/lv2` and `nura/pd` through
their meta packages, zynaddsubfx, setBfree), `zynthian`
(zyncoder and zynthian-ui from their checkouts, zynthian-data, postmarketos-ui-zynthian; always
rebuilt). The Qt modules are separate stages because their recipes ask for the other modules
without a version, which Alpine's 6.11 would satisfy.

## Branches and workflows

| Workflow | Runs on | Builds |
|---|---|---|
| `zynthian.yml` | pushes to `main` (recipes, scripts, its target), by hand | zynthian packages and the Duet image |
| `pixel3.yml` | pushes to `pixel3-*` branches, by hand | the Pixel 3's SDM845 kernel from `overlays/pixel3` (artifact `apks-pixel3-kernel`) |

Work on a target happens on branches with its prefix; `main` gets what is ready.

## Overlays

A target can replace pmaports recipes: `OVERLAY=overlays/<target>` in its target file, with recipe
directories at the same path as in pmaports (e.g.
`overlays/pixel3/device/community/linux-postmarketos-qcom-sdm845`). `setup.sh` copies them over
pmaports' recipes, `pin-binary.sh` leaves them alone. An overlay of a package postmarketOS also
publishes needs a higher `pkgrel` than the published one (the Pixel 3 kernel: pmaports' + 100), or
pmbootstrap installs the published package. Keep the overlay in step with pmaports' recipe
(version, config) when updating.

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

Draft, not run on GitHub yet: expect fixes on the first runs (non-interactive `pmbootstrap init`,
disk space on the runners, cache sizes).
