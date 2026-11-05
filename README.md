# nura-builds

Builds Nura (postmarketOS) packages and images for apps whose recipes live in their own
repositories, on GitHub Actions (native arm64 runners, free for public repositories) or locally.

Targets so far:

| Target | What | Devices |
|---|---|---|
| `zynthian` | zynthian with the Qt Quick UI: Qt 6.12, PySide6, zyncoder, zynthian-data, zynthian-ui, the kiosk package | Lenovo IdeaPad Duet (`google-kukui`); Raspberry Pi 4 planned |

## How it works

- `targets/<target>.sh` names the source repositories (cloned into `$NURA_SRC`, recipe directories
  linked into pmbootstrap's pmaports), the build stages and the devices.
- `aports/` holds recipes shared by several apps: Qt 6.12 (`aports/qt6/`, newer than Alpine's 6.11;
  copied from Zrythm's `tools/nura/qt6`, see `aports/qt6/README.md`).
- `scripts/setup.sh` installs pmbootstrap, writes its config (edge, systemd, PipeWire), initialises
  the work dir, links the recipes, installs the signing key and restores built packages.
- `scripts/build.sh STAGE` builds one stage and saves the local package repository
  (`$NURA_OUT/packages.tar`); `scripts/image.sh DEVICE` writes an image
  (`$NURA_OUT/<target>-<device>.img.zst`).
- `.github/workflows/<target>.yml` runs the stages as jobs (`stage.yml`), each on a fresh runner:
  stages stay under the 6 h job limit, and a stage whose recipes (and all earlier stages) are
  unchanged takes its packages from the Actions cache. Then one image job per device.

zynthian's stages: `qt1` (qtbase, qtshadertools, qtsvg, qtlanguageserver), `qt2` (qtdeclarative),
`qt3` (qtwayland), `pyside` (PySide6 6.12, from zynthian-ui's `nura/pyside6`), `zynthian`
(zyncoder and zynthian-ui from their checkouts, zynthian-data, postmarketos-ui-zynthian; always
rebuilt). The Qt modules are separate stages because their recipes ask for the other modules
without a version, which Alpine's 6.11 would satisfy.

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
