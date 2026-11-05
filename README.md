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

As of 2026-11-05:

- **zynthian** builds completely on GitHub: Qt 6.12, PySide6, the plugins stage (jalv, LV2 plugins,
  Pure Data, engines), the zynthian packages and the Duet image (first successful run 2026-11-05).
  With the stages cached, a run takes about 25 minutes (Qt and PySide restored from the cache in a
  minute each, plugins about 10 minutes when rebuilt, zynthian 4, image 5); the device kernel comes
  from postmarketOS's binary repository (`pin-binary.sh`), not built.
- **Publishing** as releases (`zynthian-latest`, the `aarch64` package repository) is new. To check:
  the CI image on the Duet, and `apk update`/`upgrade` from the releases repository (apk following
  GitHub's download redirect).
- **Pixel 3**: work on `pixel3-*` branches (see [docs/google-blueline.md](docs/google-blueline.md)):
  the SDM845 kernel built from an overlay of pmaports' recipe; the USB OTG patch series don't apply
  to its 7.1-rc1 base yet.
- The Qt 6.12 recipes in `aports/qt6/` are a copy of Zrythm's (`tools/nura/qt6`): keep them in step,
  and link only one of them into a local pmaports checkout.
