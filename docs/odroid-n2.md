# Hardkernel ODROID N2 (and N2+) on Nura

Status 2026-11-10: the packages build in CI; **nothing has run on an N2 yet**. Target: zynthian on
the N2 (Amlogic S922X, 4x Cortex-A73 + 2x A53, HDMI), with a PREEMPT_RT kernel as on the Pi 4
([zynthian-rpi.md](zynthian-rpi.md)).

## What postmarketOS has, what we add

pmaports has the **N2+** only (`device/testing/device-odroid-n2plus`): the mainline kernel
`linux-postmarketos-amlogic` (7.2.14), mainline U-Boot (`u-boot-amlogic-odroid-n2plus`, U-Boot's
`odroid-n2` config) and an extlinux boot menu. The plain N2 differs in two places:

- **Device tree**: `meson-g12b-odroid-n2` instead of `meson-g12b-odroid-n2-plus`. The kernel builds
  both (and the N2L's).
- **Boot firmware** (BL2, BL30/31, DDR training, from LibreELEC's `amlogic-boot-fip`): the N2 has
  its own set (`odroid-n2`, same files as `odroid-n2-plus`, different contents). pmaports builds
  U-Boot only with the N2+'s, so the N2 gets its own U-Boot package.

The old N2+ port in k-laus/pmaports (branch `odroid-n2plus`, 2021: Hardkernel's U-Boot 189 with a
`boot.ini`, tobetter's 5.14 kernel) is superseded by pmaports' mainline port; its `boot.ini` chose
the N2 or N2+ dtb from Hardkernel U-Boot's `${variant}`.

| Package | Where | What |
|---|---|---|
| `linux-postmarketos-amlogic-rt` | `aports/kernel/` | pmaports' `linux-postmarketos-amlogic` 7.2.14-r0 with `PREEMPT_RT` (+`EXPERT`) and 1000 Hz, set in `prepare()` and checked after `olddefconfig`. Same files as the original (`/boot/vmlinuz`, dtbs, modules), which it replaces |
| `u-boot-odroid-n2` | `devices/` | pmaports' `u-boot-amlogic` 2026.04-r1 for the N2 only, with the N2's boot firmware: `/usr/share/u-boot/odroid-n2/u-boot.bin.sd-stripped.bin` |
| `device-odroid-n2` | `devices/` | pmaports' `device-odroid-n2plus` 6-r0 with the N2's dtb and U-Boot; kernel choice `device-odroid-n2-kernel-amlogic` (postmarketOS' kernel) or `-kernel-amlogic-rt` (ours) |

Update them by copying pmaports' recipe directories again and keeping our changes (the headers of
the APKBUILDs say what they are).

## CI

`targets/odroid-n2.sh`, `.github/workflows/odroid-n2.yml`: pushes to `odroid-*` branches (or a
manual run) build the stages `kernel` (the RT kernel, ~90 min on the arm64 runner, cached
afterwards) and `device` (U-Boot and the device package, ~7 min). Artifacts:
`apks-odroid-n2-kernel` and `apks-odroid-n2-device` (the newest version of each package, signed
with the CI key `nura-builds-ci.rsa.pub`).

## Install (SD card)

Locally with pmbootstrap, as for the Pi 4. pmbootstrap finds the device package in
`device/nura-builds` of pmaports, a link to this checkout's `devices/` (`scripts/setup.sh` makes
it; or `ln -sfn <nura-builds>/devices <pmaports>/device/nura-builds`), and the kernel in
`nura-builds` (the link to `aports/`).

1. A config of its own, e.g. `~/.config/pmbootstrap-odroid-n2.cfg`:

   ```
   pmbootstrap -c ~/.config/pmbootstrap-odroid-n2.cfg init
   ```

   Vendor `odroid`, device `n2`, kernel `amlogic-rt` (or `amlogic` for postmarketOS' kernel), the UI
   you want (`console` to start with).
2. Build what isn't in postmarketOS' repository (the RT kernel compiles for a long time; with the
   `amlogic` kernel only the first two):

   ```
   pmbootstrap -c ~/.config/pmbootstrap-odroid-n2.cfg build u-boot-odroid-n2 device-odroid-n2 linux-postmarketos-amlogic-rt
   ```

3. Write the card (U-Boot goes to sector 1, before the partitions):

   ```
   pmbootstrap -c ~/.config/pmbootstrap-odroid-n2.cfg install --sdcard=/dev/sdX
   ```

4. Boot with the N2's boot switch on **MMC** (SD card), HDMI and Ethernet connected. Serial console:
   the 4-pin UART header, 115200 baud (`ttyAML0`), the first place to look if HDMI stays dark.

Switching the kernel on the device (the RT kernel from the CI artifact: trust its key first,
`/etc/apk/keys/nura-builds-ci.rsa.pub`):

```
sudo apk add ./linux-postmarketos-amlogic-rt-7.2.14-r0.apk ./device-odroid-n2-kernel-amlogic-rt-1-r0.apk '!device-odroid-n2-kernel-amlogic'
```

## Open

- First boot: U-Boot with the N2 firmware, the dtb from the extlinux menu, HDMI, Ethernet, USB.
- Audio: HDMI and the I2S/SPDIF on the GPIO header (a HAT); latency with the RT kernel
  (`rt-tests`' cyclictest, as on the Pi 4) and with jackd against PipeWire.
- zynthian: the kiosk on HDMI (DRM, Panfrost), the zynthian packages for this device.
