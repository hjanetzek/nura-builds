# Samsung Galaxy S III Neo (samsung-s3ve3g)

GT-I9301I: MSM8226 (4x Cortex-A7, armv7), 1.5 GB RAM, 16 GB eMMC, 720x1280 AMOLED (S6E8AA0A,
DSI), MMS144 touch, SM5502 USB switch (MUIC). Built on branch `zynthian-arm7` (workflow
`zynthian-armv7.yml`, see the README).

## Kernel and device package

pmaports' `device-samsung-s3ve3g` is archived: the downstream kernel 3.4 (LineageOS), which can't run
systemd and has framebuffer graphics only, and no binary packages. The mainline kernel
`linux-postmarketos-qcom-msm8226` (msm8226-mainline's fork, 6.16) has a device tree for the phone,
but with the serial port only. Both are overlays here (`overlays/s3ve3g`, copied over pmaports by
`scripts/setup.sh` before `pmbootstrap init`; the device package in `device/testing`, as
`pmbootstrap init` doesn't take an archived device non-interactively), built in the `device` stage:

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

The `.apk` files are the artifact `apks-zynthian-device` of each run; with the input `images`, the
image `zynthian-samsung-s3ve3g.img.zst` and the boot image `zynthian-samsung-s3ve3g-boot.img.zst`
(artifact `zynthian-samsung-s3ve3g`, release `zynthian-armv7-latest`). The image has UI `none` with
zynthian-ui installed (no kiosk package: it depends on the plugins).

Not tested on the device yet. Unknown: whether the bootloader takes the appended device tree (the
`qcom,msm-id` values are the downstream ones and lk2nd's), the memory layout (from the Tab 4 3G),
the framebuffer format, touch with mms114.

## Flashing

Download mode: Volume Down + Home + Power, then Volume Up to confirm. heimdall on the PC
(`heimdall print-pit --no-reboot` lists the partition names).

From an SD card first (leaves Android on the eMMC): the rootfs on the card, the boot image to
BOOT; the initramfs finds the root partition by its label on any disk.

```sh
zstd -d zynthian-samsung-s3ve3g.img.zst zynthian-samsung-s3ve3g-boot.img.zst
sudo dd if=zynthian-samsung-s3ve3g.img of=/dev/sdX bs=4M status=progress   # the SD card
heimdall flash --BOOT zynthian-samsung-s3ve3g-boot.img
```

To the eMMC: `heimdall flash --BOOT zynthian-samsung-s3ve3g-boot.img --USERDATA
zynthian-samsung-s3ve3g.img` (the raw image: slow). Back to Android: the stock firmware's boot
image with heimdall (or Odin).

With pmbootstrap: this repository's `overlays/s3ve3g` copied over the pmaports checkout (as
`scripts/setup.sh` does: the device package goes to `device/testing`, pmaports' archived copy
removed), `samsung-s3ve3g` at `pmbootstrap init`; then
`pmbootstrap flasher flash_kernel` and `flash_rootfs` (heimdall).

## Debugging

- USB networking (the initramfs and the system): 172.16.42.1, `ssh user@172.16.42.1`, if the
  SM5502 detects the PC (else the USB controller stays without a role).
- Serial console: `blsp1_uart3` at 115200 (`console=ttyMSM0`). Samsung routes it to the micro-USB
  port through the MUIC with a 619 kΩ resistor between ID and ground (a "JIG UART" cable: D+/D- as
  RX/TX), so soldering may not be needed; check the voltage level of the adapter.
- Without display output: the framebuffer format may be another (`r8g8b8` vs. `a8r8g8b8`), or the
  bootloader leaves the panel off; then the panel driver (DSI, S6E8AA0A) is next.
