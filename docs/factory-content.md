# Factory content: zynthian-factory-content

Nura's zynthian image replicates ZynthianOS' image, but leaves out the large data that comes from
elsewhere (SoundFonts, sample packs, extra wavetables). One command on the device pulls it in
afterwards, so that every factory snapshot loads all its chains:

```sh
zynthian-factory-content        # install what is missing (about 3 GB to download)
zynthian-factory-content -l     # list the content and what is installed
zynthian-factory-content -n     # dry run: what would be installed
```

Run it as the device user (the one zynthian runs as; over ssh or in a terminal), with network.
Packages are installed with `sudo` (or `doas`), which asks for that user's password. Already
installed parts are skipped, so it can be run again after an interruption. Afterwards restart
zynthian (`sudo systemctl restart tinydm`, or reboot): the new banks and plugins show up then.

The command comes with the `zynthian-packages` package (in the image through the kiosk package).

## What it installs

**Packages** of this repository that are built but kept out of the image:

| Package | Download | Installed | What |
|---|---|---|---|
| `fluid-soundfont` (+ `-gm`, `-gs`) | 130 MB | 150 MB | FluidR3 GM and GS SoundFonts (Debian's, MIT), as ZynthianOS has them in `/usr/share/sounds/sf2`; factory snapshot `003-FluidR3 GM` |
| `fluidplug-lv2` (+ `-data`) | 260 MB | 300 MB | FluidPlug's SoundFont instruments (LV2), their SoundFonts also listed by the fluidsynth engine |
| `vaporizer2-lv2-data-extra` | 490 MB | 910 MB | Vaporizer2's Analog and Digital wavetables and its larger presets (the plugin and its essential data are in the image) |

**Content packs** of [zynthian-packages](https://github.com/zynthian/zynthian-packages): the
ones ZynthianOS' image (Vangelis 2610) comes with installed, plus the Salamander Drumkit of the
factory snapshot `014-Useless`:

| Pack | Size | Licence |
|---|---|---|
| Zynthian Factory SFZs | 738 MB | various (GPL, MIT, CC0, CC-BY-SA, unknown) |
| Zynthian Factory SF2s | 474 MB | various (GPL, MIT, CC0, CC-BY-SA) |
| Salamander Drumkit | 358 MB | CC BY-SA |
| Zynthian Salamander Grand | 220 MB | CC-BY |
| Hydrogen Drumkits | 195 MB | various (GPLv3, CC0, CC-BY-SA) |
| Stevie Clavinet | 60 MB | unknown |
| jRhodes3d | 60 MB | CC BY-NC |
| Zynthian Meatbass | 15 MB | CC0 |
| TR808-fischer | 12 MB | CC0 |
| DrawbarOrgan | 100 KB | CC0 (Factory SFZs contain it: shows as installed with them) |

The packs are downloaded from their origin (os.zynthian.org, GitHub) by the packs' own scripts,
as webconf's Extra Packs page does: nothing of them is hosted here. That is also why they aren't
packages: some licences don't allow redistribution (non-commercial, unknown).

In total about 3 GB to download and 3.5 GB installed. The Duet's root partition has room; a
QEMU VM disk of 8 GB doesn't (grow it first).

## Where it goes

- Packs: `/var/lib/zynthian/zynthian-data` (`ZYNTHIAN_PACKS_DATA_DIR`), with zynthian-data's
  layout (`soundfonts/sfz`, `soundfonts/sf2`, `soundfonts/hydrogen`, ...). The packaged
  `/usr/share/zynthian/zynthian-data` is read-only; this directory is the writable system data
  beside it, created by `zynthian-packages` (group `audio`, setgid). zynthian lists it as
  **System** data (sfizz, fluidsynth and linuxsampler banks, the audio player, the file browser,
  LV2 presets), and factory snapshot paths under `/zynthian/zynthian-data/` fall back to it
  (zynthian-ui: `zynconf/zynthian_paths.py`, `system_data_paths()`, `remap_os_paths()`).
- Each installed pack is recorded where webconf records its installs
  (`~/.config/zynthian/packages/<category>/<pack>`): webconf's Extra Packs page shows them as
  installed and uninstalls them.
- Packages: as any package (`apk del` removes them).

## Factory snapshots

What the 15 factory snapshots of Vangelis need beyond the image's packages (audited 2026-11-08 by
engine, plugin and referenced file):

| Snapshot | Needs |
|---|---|
| 001-ThreeOnThree, 002-House In RTP, 006-Tide, 010-Origin, 012-Introducing V5, 013-Money for nothing | LinuxSampler (SFZ instruments; `linuxsampler` is in the image) and Factory SFZs |
| 003-FluidR3 GM | `fluid-soundfont` |
| 008-Drone | TAL-Filter (in the image: `distrho-ports-lv2`) |
| 009-Zynesthesia | Factory SFZs, jRhodes3d |
| 011-Everything must flow | Factory SFZs |
| 014-Useless | Salamander Drumkit, Factory SFZs |
| 004, 005, 007, 015 | nothing beyond the image (DJ EQ and SC4 are disabled by default, as on ZynthianOS, and load from snapshots all the same) |

Checked: every referenced engine and plugin is installed and every referenced file exists after
`zynthian-factory-content`. To do: load each snapshot and compare the chains with ZynthianOS.

## Maintenance

- The script is `nura/zynthian-packages/zynthian-factory-content` on the `nura` branch of
  [hjanetzek/zynthian-packages](https://github.com/hjanetzek/zynthian-packages) (the fork whose
  recipe builds `zynthian-packages`); its lists `APKS` and `PACKS` are the content.
- When a new ZynthianOS release changes what its image comes with, compare the image with a Nura
  install (LV2 bundles, presets, zynthian-data, the packs installed under
  `/zynthian/config/packages`) and the factory snapshots' needs, and update the lists. Small
  content (programs, plugins, presets) goes into the image, large data into this script.
- Not covered (also not in ZynthianOS' image by default, or not packaged): Pianoteq (commercial),
  the internet radio engine (vlc), Aeolus, MOD-UI.
