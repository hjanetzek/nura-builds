# zynthian on Raspberry Pi kits, ODROID N2: plan (2026-11-17)

Goal: CI builds `zynthian-zynthian-rpi4.img.zst` and publishes it in `zynthian-latest`. A zynthian
owner writes it to a second SD card, picks their kit, and the Pi boots into the Qt UI on the kit's
display, with audio, encoders and touch. Their ZynthianOS card stays untouched. Background:
[zynthian-rpi.md](zynthian-rpi.md) (plan and measurements on the V4 kit, 2026-11-10), the outreach
plan in zynthian-stuff's `research/zynthian-gpu-ui-research.md` (section 5).

## What's on the branches (2026-11-17)

All three are about 30 commits behind main and predate the CI restructuring
([ci-plan.md](ci-plan.md)): they still use `stage.yml`, which is gone.

| Branch | Contents | State |
|---|---|---|
| `device-zynthian-rpi4` (6 commits) | Device package for the Pi 4 (pmaports' raspberry-pi4 base, Alpine's linux-rpi, ZynthianOS' boot settings in usercfg.txt, kit overlays in `/boot/zynthian-kit.txt`, GPIO/I2C/SPI groups, `zynscreen-drm` overlay for the V4 panel); zynthian target with `zynthian-rpi4` in `DEVICES`, `zynthian-hw` as an extra image package; `packages.yml` with an image input | tested on the V4 kit 2026-11-10; CI built only the device package, never an image |
| `rpi4-rt-kernel` (4) | `linux-rpi-rt` (PREEMPT_RT, 1000 Hz), own target and workflow | CI green 2026-11-10 |
| `odroid-n2-rt-kernel` (12, contains rpi4-rt) | `linux-postmarketos-amlogic-rt`; U-Boot and device package for the plain N2; `docs/odroid-n2.md` | packages only, no image |
| `rpi-findings` (local, worktree nura-builds-docs) | `docs/zynthian-rpi.md` | not pushed |

## A. Into the new structure (mechanics) — done 2026-11-17 (branch rpi-merge)

1. Device packages in `devices/` (`device-zynthian-rpi4`, `device-odroid-n2`, `u-boot-odroid-n2`),
   each linked into pmaports' `device/testing/` by setup.sh: `pmbootstrap init` skips unknown
   categories (the ODROID findings), so the rpi branch's `device/nura-builds` link isn't enough.
2. Kernels as recipes: `aports/kernel/linux-rpi-rt`, `aports/kernel/linux-postmarketos-amlogic-rt`.
3. Package sets for aarch64: `kernels` (KEEPGOING) and `devices` (device packages, U-Boot): built per
   package and published to the release like everything else, a kernel only when its recipe changes.
4. Drop `targets/rpi4.sh`, `targets/odroid-n2.sh`, `rpi4.yml`, `odroid-n2.yml` and the branches'
   `stage.yml` changes (superseded by the sets).
5. zynthian target: `DEVICES="google-kukui zynthian-rpi4"`, `zynthian-hw` in the zynthian stage
   (aarch64), per-device extra packages (`EXTRA_PACKAGES_zynthian_rpi4`, image.sh). The image
   matrix of build-target.yml comes from `DEVICES`: no workflow change.
6. `packages.yml` with the image input (an image for one device from a test branch, without the
   whole target).
7. `docs/zynthian-rpi.md` and `docs/odroid-n2.md` into main, README.

Conflicts expected in `targets/zynthian.sh`, `setup.sh`, `image.sh`, `zynthian.yml`,
`packages.yml` (all rewritten by the restructuring): carry the commits over by hand, not rebase.

## B. Testable on a kit

1. **Display.** HDMI and the V5's DSI panel are DRM: the kiosk (cage/niri) works. The V4's SPI
   panel: the DRM driver ili9486 binds but the panel stays white (its init sequence doesn't suit
   this panel revision). Short term: a kiosk mode without compositor, Qt's linuxfb on fbtft (the
   lightest option measured: SPI traffic idle 0.03 MB/s, Tk on ZynthianOS 1.36 MB/s), as the
   S III Neo runs eglfs without a compositor; no native plugin windows in that mode. In zynthian-ui
   (`nura/postmarketos-ui-zynthian`), chosen by the kit setting.
2. **Kit selection.** The tester enters the kit in a file on the SD card's FAT partition before the
   first boot (from any PC): `zynthian-kit.txt` with a ready block per kit (V4, V5, ...: sound
   card, display, wiring layout). Default without an entry: HDMI and onboard audio. `zynthian-kit
   V4` on the device stays as a second way.
3. **Encoders and switches:** `zyncoder-hw` and the Qt hardware input (prototype), enabled by the
   kit setting.
4. **Touch:** the ADS7846 calibration rule (`LIBINPUT_CALIBRATION_MATRIX="-1 0 1 0 -1 1"`) in the
   device package.
5. **Audio:** HifiBerry DAC+ADC through the overlay; check PipeWire/JACK in the kiosk on the kit.
6. **Access:** a known default password, SSH on, hostname `zynthian`; Wi-Fi setup in the release
   notes.
7. Later: a Qt layout for 480x320 (the V4 panel).

## C. Test and release

CI builds the image; test on the V4 kit with a checklist (boot, display, audio in/out, encoders and
switches, touch, a chain with an LV2 synth, CPU load). Then the image in `zynthian-latest`, with
release notes for testers (kits, what works, known gaps, where to report bugs): the base for the
forum topic.

## Later

- The RT kernel as a choice in the device package (as `device-odroid-n2-kernel-amlogic-rt`).
- A Pi 5 device for the V5 (pmaports `raspberry-pi5`, kernel flavour `bcm2712`).
- A zynthian image for the ODROID N2.

## Open decisions

1. V4 display: linuxfb kiosk mode now (quick, no plugin windows), or first the ili9486 init
   sequence (the DRM path)? Suggested: linuxfb now, DRM later.
2. Kit selection: an entry on the FAT partition before the first boot (suggested), or a menu at
   first boot?
3. ODROID: packages only for now (kernel, U-Boot, device), the zynthian image later?
4. RT kernel in the Pi image by default, or linux-rpi first?
