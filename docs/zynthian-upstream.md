# zynthian from upstream on Nura

For those who want zynthian as upstream ships it (the Tk UI), not the Qt UI port: nura-builds
builds zynthian-ui from upstream's branches with a small series of port patches, as the packages

| Package | Upstream | Recipe |
|---|---|---|
| `zynthian-ui-vangelis` | `vangelis` (stable) | `aports/zynthian-upstream/zynthian-ui-vangelis` |
| `zynthian-ui-tomita` | `tomita` (development) | `aports/zynthian-upstream/zynthian-ui-tomita` |

in the same package repository as everything else (release `aarch64`). Everything around
zynthian-ui is shared with the Qt build: zyncoder (upstream's tomita and vangelis are identical;
our fork adds the port's two commits), zynthian-data, zynthian's jalv, the engines, LV2 plugins and
Pure Data externals, the kiosk package.

## Install

Each of them provides `zynthian-ui` (versioned, so apk installs only one of them) and installs where
zynthian-ui does. On a Nura zynthian install (or an image), where the kiosk package
(postmarketos-ui-zynthian) depends on zynthian-ui, switch with

```sh
sudo apk del zynthian-ui              # only drops it from the world file: the kiosk still needs it
sudo apk add zynthian-ui-tomita       # replaces it (or zynthian-ui-vangelis)
sudo systemctl restart tinydm
```

and back the same way (`apk del zynthian-ui-tomita`, `apk add zynthian-ui`). Not
`apk add zynthian-ui-tomita '!zynthian-ui'`: the `!` excludes the providers of the name too. From a
host, zynthian-ui's `nura/tools/switch_ui.sh qt|vangelis|tomita` does it (checked on the Duet:
Qt -> tomita -> vangelis -> Qt). The kiosk session starts the Tk UI when the installed zynthian-ui
has no Qt UI (postmarketos-ui-zynthian r16; the patched launcher falls back as well).

## The patches

The port's essentials from the nura branch of hjanetzek/zynthian-ui (written with
`git format-patch`, one file per commit, each with its own description):

- desktop mode (`ZYNTHIAN_DESKTOP=1`): no Raspberry Pi hardware, no update_zynthian_sys.sh, no
  RBPi audio device, engines whose program isn't installed hidden;
- directories from the environment instead of `/zynthian/...` (`zynconf/zynthian_paths.py`),
  native libraries from `ZYNTHIAN_LIB_DIR`, user controller drivers without a link in the code
  tree, ZynthianOS paths in snapshots and Organelle patches mapped to this system's;
- `desktop/`: the install script the recipe uses (`install.sh ui`), the launcher
  (`/usr/bin/zynthian`, zynthian's jalv on the PATH), the environment, the UI scale;
- PipeWire: port aliases kept locally when pipewire-jack refuses them, the main output on the
  first two hardware outputs (`ZYNTHIAN_AUDIO_MAIN_OUTPUT`; the admin menu entry is in the Qt
  port's shared modules only);
- fixes needed to run: jack_capture from PATH, engine shells with `TERM=dumb`, the audio player at
  exit, zynclippy on 64 bit, the ALSA mixer's start-up time, the help viewer without tkinterweb.

The vangelis series is the tomita series with three patches adapted (context conflicts only: autoconnect, the directories, jalv's RBPi check). The series
shrinks as these changes go upstream (the nura branch's PR #1 and its upstream log,
`docs/upstream-candidates.md` there).

## Updating

`tools/update-zynthian-upstream.sh BRANCH [COMMIT]` moves a recipe to upstream's newest commit (or
COMMIT): it applies the patches there with `git am -3`, writes them back, and sets `_commit`,
`pkgver` and the checksums. On a conflict it stops in its work tree; resolve, `git am --continue`,
then run it again with `-k`. Run with the current commit, it reproduces the recipe unchanged.

## Build

The `upstream` stage of the zynthian target (after the `zynthian` stage, which builds zyncoder from
its checkout). Not in images. A failed upstream stage doesn't stop the publishing of the other
packages.

To check on a device: the Tk UI in the kiosk (XWayland), LV2 chains with zynthian's jalv, audio on
the main output, snapshots.
