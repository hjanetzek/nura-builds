# Next target: Google Pixel 3 (google-blueline)

Status: planning, 2026-11-05. zynthian (Qt UI) on a Pixel 3, built by nura-builds like the Duet
image. Sources: the device's [Nura wiki page](https://wiki.nura.eco/wiki/Google_Pixel_3_(google-blueline))
(history checked 2026-11-05), pmaports (local checkout of 2026-10-27), the sdm845-mainline kernel
tree, the Linux kernel mailing lists.

## The device

| | |
|---|---|
| SoC | Qualcomm Snapdragon 845 (SDM845): 4× Kryo 385 Gold 2.5 GHz + 4× Silver 1.6 GHz, Adreno 630 |
| Memory, storage | 4 GB, 64/128 GB |
| Display | 1080×2160 P-OLED (portrait) |
| Audio | no 3.5 mm jack: external audio only over USB-C (USB audio, i.e. host mode) or Bluetooth |
| pmaports | `device/testing/device-google-blueline`; kernel `linux-postmarketos-qcom-sdm845` (sdm845-mainline tree, tag `sdm845-7.1-rc1-r0`, Linux 7.1-rc1); device tree `qcom/sdm845-google-blueline`; firmware `firmware-google-blueline`, `firmware-google-blueline-dtbo` |
| Flashing | fastboot (`deviceinfo_flash_method="fastboot"`, boot image generated); bootloader must be unlocked (`fastboot flashing unlock`) |
| Debug | UART over the USB-C SBU pins (Android debug cable, 115200 baud, see the wiki page); `console=ttyMSM0,115200` in the device's kernel command line |
| Sibling | Pixel 3 XL (`google-crosshatch`, archived in pmaports) shares `sdm845-google-common.dtsi` |

Status on the wiki (testing category, packaged, boots):

| Works | Partly | Doesn't |
|---|---|---|
| screen, touch, 3D, flashing, eMMC, battery, Wi-Fi (with `rmtfs pd-mapper tqftpserv`), Bluetooth, USB networking, FDE, XWayland | audio (speaker output fixed by pmaports MR 5686), GPS | **USB OTG**, accelerometer, camera, calls, SMS, mobile data |

For zynthian the gaps that matter are USB host mode (MIDI controllers, USB audio interfaces,
headphone adapters) and audio; telephony and camera don't.

## USB OTG: why it doesn't work, and the work on it

**Why.** Not specific to the Pixel 3: in the sdm845-mainline tree every SDM845 phone (Pixel 3/3 XL,
OnePlus 6/6T, Poco F1, SHIFT6mq) has `dr_mode = "peripheral"` on the DWC3 controller and no Type-C
connector or role switch in its device tree (`sdm845-google-common.dtsi`: `&usb_1_dwc3 { dr_mode =
"peripheral"; };`). Qualcomm's PMIC Type-C driver (`drivers/usb/typec/tcpm/qcom`) supports only
PM8150B and PMI632, not the PMI8998 of these phones, and `pmi8998.dtsi` has no Type-C node. The
pmaports kernel config already has what host mode needs on the kernel side (`USB_DWC3_DUAL_ROLE`,
`USB_ROLE_SWITCH`, `TYPEC`, `TYPEC_TCPM`, `TYPEC_QCOM_PMIC`).

**Work in progress** (none of it merged, not in the sdm845-mainline tree yet):

1. [RFC "Qualcomm Type-C support for 1st generation"](https://lore.kernel.org/all/20260926-typec-v1-0-31adc19f32c6@ixit.cz/),
   David Heidelberg, 12 patches, 2026-09-26: a Type-C port driver for PMI8998/PM660
   (`qcom_pmic_typec_port_gen1.c`), the Type-C node in `pmi8998.dtsi`, and a patch enabling it in
   `sdm845-google-common.dtsi` (Pixel 3 / 3 XL). Tested on Pixel 3 / 3 XL, SHIFT6mq and OnePlus 6
   with an externally powered dock (no VBUS from the phone yet). Reviewed by Dmitry Baryshkov and
   Bryan O'Donoghue.
2. ["Enable Qualcomm VBUS block on PMI8998 and PM660"](https://lore.kernel.org/all/20261031-pmi8998-vbus-v1-0-4d805e5a0f27@ixit.cz/),
   David Heidelberg, 11 patches, 2026-10-31: the PMIC's VBUS booster as a regulator (0.5–1.5 A),
   enabled for Pixel 3 / 3a / 3 XL / 3a XL and other SDM845/SDM670 phones. With the Type-C driver
   this gives real OTG: the phone powers the connected device.
3. An earlier, separate series by "taygoth"
   ([May 2026](https://lore.kernel.org/all/5f4271701066943ead54f82003ab282c4b39f3da.1779127507.git.taygoth@gmail.com/)):
   PMI8998 Type-C controller and VBUS regulator nodes.

David Heidelberg is probably also "dh" of pmaports
[MR !6953](https://gitlab.nura.eco/nura/pmaports/-/merge_requests/6953) (Pixel 3 XL: U-Boot,
kernel switch, "debug problems with USB on mainline" next; closed unmerged 2025-11-18).

Until this is merged: with series 1 only, devices behind an externally powered dock or hub; for
bus-powered devices (most MIDI controllers, headphone adapters) series 2 as well.

## Plan

1. **First image, current kernel (no OTG).** Add `google-blueline` to `DEVICES` in
   `targets/zynthian.sh` and to the image job's matrix. The zynthian packages are the Duet's
   (aarch64), only the image differs. `scripts/image.sh` writes the rootfs image only: fastboot
   devices also need the boot image (`pmbootstrap export`, or from the rootfs); add that. Wi-Fi
   needs `rmtfs pd-mapper tqftpserv` in the image (wiki); check whether the device package or
   `soc-qcom` already pulls them in.
2. **Kiosk on a phone.** The panel is portrait (1080×2160) without a DRM panel orientation, so the
   kiosk script has to rotate the output explicitly (`wlr-randr --transform 90`) for zynthian's
   landscape layout; at scale 1.5 that is 1440×720 logical pixels, a 2:1 screen (the Duet: 1280×800,
   16:10): check the layouts (keypad, mixer, lists). Touch rotates with the output in cage (check).
3. **Audio.** Speaker output works (wiki: partly); check PipeWire with the SDM845 UCM profile,
   latency at a 256-frame quantum, and the speaker's quality for monitoring. Real use needs USB audio
   (step 4) or Bluetooth.
4. **Kernel with OTG** (branch `pixel3-otg-kernel`, `overlays/pixel3`): pmaports' SDM845 kernel
   recipe (7.1_rc1, `pkgrel` 104) with 15 patches (`otg-*.patch`):
   - the qcom PMIC Type-C driver files at their v7.4-rc1 state (the series' base: VBUS regulator
     from the connector node, cancelling work on stop, include cleanups);
   - the Type-C RFC without the other phones' patches (1–6, 8, 10) and the VBUS series' Pixel 3
     parts (1–4, 6); the binding documents, the PMI8998 VBUS node, the Pixel 3 device tree and the
     charger patch adapted to the 7.1 tree (marked in their messages; the charger keeps SMB5 there,
     so the OTG_CFG write is dropped from the SMB2 init sequence only);
   - ours: the Pixel 3 connector in the dual power role with the VBUS booster as `vbus-supply` and a
     5 V / 1.5 A source PDO (the RFC leaves it sink-only until VBUS is supported).
   Checked locally: all patches apply in abuild's order; the Type-C module, charger and VBUS
   regulator cross-compile (clang, pmaports' config) without warnings; the 24 device trees using
   `pmi8998.dtsi` build, and the Pixel 3's has `dr_mode = "otg"`, the Type-C node and VBUS enabled.
   No kernel config changes (the gen1 driver is part of `TYPEC_QCOM_PMIC`). To test on the device:
   role switching with a powered hub, then bus-powered MIDI controllers and a USB-C headphone
   adapter; charging still works (sink role).
5. **Follow upstream.** Track the two series (v2, merge); drop the patches once the sdm845-mainline
   tree has them.

## Open questions

- Does the Adreno 630 (freedreno) run Qt Quick as well as Panfrost on the Duet, and does the
  XWayland glamor issue of the Duet (`docs/nura-display.md` in zynthian-ui) occur here? (The Qt UI
  is native Wayland, so it only matters for the Tk UI.)
- CPU affinity and governor: 4 fast + 4 slow cores like the Duet; the Duet's
  setup (UI and audio on the fast cluster) should carry over.
- Battery and charging while OTG powers a device: VBUS current limit 0.5–1.5 A (series 2).
- Pixel 3 XL (`google-crosshatch`) as a second device: archived in pmaports, same common device tree.
