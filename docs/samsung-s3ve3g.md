# Samsung Galaxy S III Neo (samsung-s3ve3g)

GT-I9301I: MSM8226 (4x Cortex-A7, armv7), 1.5 GB RAM, 16 GB eMMC, 720x1280 AMOLED (S6E8AA0A,
DSI), MMS144 touch, SM5502 USB switch (MUIC). Branch `galaxy-s3-neo`: target `targets/s3ve3g.sh`,
workflow `galaxy-s3-neo.yml` (pushes to `galaxy-s3-neo*`), the kernel and the device package only;
images are built locally. zynthian's armv7 packages: branch `zynthian-arm7` (see the README).

## Kernel and device package

pmaports' `device-samsung-s3ve3g` is archived: the downstream kernel 3.4 (LineageOS), which can't run
systemd and has framebuffer graphics only, and no binary packages. The mainline kernel
`linux-postmarketos-qcom-msm8226` (msm8226-mainline's fork, 6.16) has a device tree for the phone,
but with the serial port only. Both are overlays here (`overlays/s3ve3g`, copied over pmaports by
`scripts/setup.sh` before `pmbootstrap init`; the device package in `device/testing`, as
`pmbootstrap init` doesn't take an archived device non-interactively), built in the `kernel` stage:

- `linux-postmarketos-qcom-msm8226` (pkgrel + 100): patch
  `0001-ARM-dts-qcom-msm8226-samsung-s3ve3g-full-device-tree.patch` with a full device tree,
  based on the Galaxy Grand 2 (`ms013g`) and Galaxy Tab 4 (`matisse`) device trees (same downstream
  base), with the wiring of the downstream `msm8226-sec-s3ve3geur-r04`: eMMC, SD card, USB through
  the SM5502 (bit-banged I2C on GPIO 4/5, IRQ 52), keys, hall sensor, MMS144 touch (`mms114`),
  MPU-6500, YAS532, Wi-Fi (pronto), the reserved memory of the Tab 4 3G, and the bootloader's
  splash screen as a simple framebuffer (0x03200000, 720x1280 RGB888; simpledrm). Config: ALSA
  sequencer, YAS530 driver.
- `device-samsung-s3ve3g` (pkgver 104): the mainline kernel, a boot image with the device tree
  appended (Samsung's bootloader picks it by `qcom,msm-id`; no QCDT, no lk2nd), flashed with
  heimdall: the kernel to BOOT, the rootfs to USERDATA (SYSTEM is too small).

Each run uploads the `.apk` files (artifact `apks-s3ve3g-kernel`) and the package repository for a
local image (`packages-s3ve3g-kernel`, `packages.tar`).

Not tested on the device yet. Unknown: whether the bootloader takes the appended device tree (the
`qcom,msm-id` values are the downstream ones and lk2nd's), the memory layout (from the Tab 4 3G),
the framebuffer format, touch with mms114.

## A minimal image, locally

With this repository's scripts (an x86_64 PC is fine: the kernel is cross-compiled), UI `none`:

```sh
export TARGET=s3ve3g NURA_ARCH=armv7 NURA_WORK=$HOME/nura-work-s3ve3g NURA_OUT=$HOME/nura-out-s3ve3g
# the packages from CI (signed with the CI key) ...
gh run download <run id> -n packages-s3ve3g-kernel -D "$NURA_OUT"
scripts/setup.sh    # pmbootstrap config, the overlays over pmaports, restores packages.tar
sudo cp keys/nura-builds-ci.rsa.pub "$NURA_WORK/config_apk_keys/"
# ... or built here instead of the download: scripts/build.sh kernel
scripts/image.sh samsung-s3ve3g
```

`$NURA_OUT/s3ve3g-samsung-s3ve3g.img.zst` (rootfs) and `s3ve3g-samsung-s3ve3g-boot.img.zst` (kernel,
initramfs, device tree). setup.sh copies the overlays into pmbootstrap's pmaports checkout
(`~/.local/var/pmbootstrap/cache_git/pmaports` unless `NURA_PMAPORTS` is set) and removes the
archived device package there. Plain pmbootstrap works too: the overlays copied over the pmaports
checkout the same way, `samsung-s3ve3g` at `pmbootstrap init`, the packages built with `pmbootstrap
build`, then `pmbootstrap install` and `pmbootstrap flasher flash_kernel` / `flash_rootfs` (heimdall).

## Flashing

Download mode: Volume Down + Home + Power, then Volume Up to confirm. heimdall on the PC
(`heimdall print-pit --no-reboot` lists the partition names).

From an SD card first (leaves Android on the eMMC): the rootfs on the card, the boot image to
BOOT; the initramfs finds the root partition by its label on any disk.

```sh
zstd -d s3ve3g-samsung-s3ve3g.img.zst s3ve3g-samsung-s3ve3g-boot.img.zst
sudo dd if=s3ve3g-samsung-s3ve3g.img of=/dev/sdX bs=4M status=progress   # the SD card
heimdall flash --BOOT s3ve3g-samsung-s3ve3g-boot.img
```

To the eMMC: `heimdall flash --BOOT s3ve3g-samsung-s3ve3g-boot.img --USERDATA
s3ve3g-samsung-s3ve3g.img` (the raw image: slow). Back to Android: the stock firmware's boot image
with heimdall (or Odin).

## Debugging

- USB networking (the initramfs and the system): 172.16.42.1, `ssh user@172.16.42.1`, if the
  SM5502 detects the PC (else the USB controller stays without a role).
- Serial console: `blsp1_uart3` at 115200 (`console=ttyMSM0`). Samsung routes it to the micro-USB
  port through the MUIC with a 619 kΩ resistor between ID and ground (a "JIG UART" cable: D+/D- as
  RX/TX), so soldering may not be needed; check the voltage level of the adapter.
- Without display output: the framebuffer format may be another (`r8g8b8` vs. `a8r8g8b8`), or the
  bootloader leaves the panel off; then the panel driver (DSI, S6E8AA0A) is next.
