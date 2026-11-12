# Samsung Galaxy S III Neo (s3ve3g): GPU and display on mainline

Research notes (2026-11-12), nothing implemented yet. Status: the display is the bootloader's
framebuffer (simple-framebuffer, simpledrm), no GPU acceleration, no brightness control. The GPU,
an Adreno 305B, has current open-source drivers (drm/msm, Mesa freedreno); what is missing is the
display path (MDSS, DSI, a driver for the S6E8AA0A panel), which the GPU driver needs in order to
bind. MSM8226 has no IOMMU in mainline, so the GPU would run without memory protection (VRAM
carveout), as on postmarketOS's other MSM8226 devices.

"Unverified" marks what was inferred, not read or tested.

## The GPU

- Adreno 305B, chip id 0x03000512: downstream `msm8226-v2.dtsi` (`qcom,chipid = <0x03000512>`,
  overriding `msm8226-gpu.dtsi`'s 0x03000510 for v1); mainline `compatible = "qcom,adreno-305.18"`.
- Kernel: drm/msm, its own entry in `drivers/gpu/drm/msm/adreno/a3xx_catalog.c` since v6.9
  (Luca Weiss, "drm/msm/adreno: Add A305B support", 3d6ab124a4d5): firmware `a330_pm4.fw` and
  `a330_pfp.fw` (not a300), 128 KB GMEM from OCMEM. Before v6.9 it was run with the a305
  configuration (wrong firmware and GMEM size). MSM8226 v1 (0x03000510) isn't listed.
- Firmware: linux-firmware `qcom/a330_pfp.fw`, `qcom/a330_pm4.fw`; pmaports
  `firmware-qcom-adreno-a330`.
- Userspace: Mesa freedreno a3xx (gallium), maintained, in Mesa 26.3 (`FD305B` in
  `freedreno_devices.py`): GLES 3.0, desktop GL 3.1; a2xx-a4xx have fake MSAA. pmaports'
  `soc-qcom-msm8226` sets `GSK_RENDERER=cairo` (GTK's ngl renderer is slower and crashes more on
  a305).

## Mainline and fork state

- MSM8226 in mainline: MDSS, MDP5 (`qcom,msm8226-mdp5`), DSI (`qcom,msm8226-dsi-ctrl`) and the
  28 nm DSI PHY (`qcom,dsi-phy-28nm-8226`) since v6.6 (d5fb01ad5eb4); the GPU node since v6.8
  (fc209f869310).
- Our fork's `qcom-msm8226.dtsi` has all of them, disabled: the GPU at 0xfdb00000 with
  `sram = <&gmu_sram>` (OCMEM), OPPs 450/320/200/19 MHz, no `iommus`, no `interconnects`.
- No IOMMU: neither MSM8226 nor MSM8974 has the GPU/MDP IOMMU in mainline (downstream:
  `kgsl_iommu: qcom,iommu@fdb10000`, `qcom,msm-smmu-v1`; mainline `qcom_iommu` covers
  8916/8917/8937/8953/8976). No pending patches for 8226; Dmitry Baryshkov's 2026 series for ARM32
  MSM IOMMU platforms covers APQ8064. Without an IOMMU the a3xx driver refuses to run
  ("No memory protection without IOMMU") unless `msm.allow_vram_carveout=1`; the carveout size
  is `msm.vram=` (16 MB default).
- In the fork only `qcom-apq8026-lg-lenok.dts` (G Watch R) and `qcom-msm8926-htc-memul.dts` (One
  mini 2) enable `&gpu` and `&mdss`, both with generated panel drivers
  (`drivers/gpu/drm/panel/msm8226-generated/`); matisse, ms013g, milletwifi, titan, falcon and the
  Lumias use simple-framebuffer.
- pmaports: `device-qcom-msm8226` has `msm.allow_vram_carveout=1 cma=256m msm.vram=192m` on its
  command line and depends on `firmware-qcom-adreno-a330`; htc-memul the same, lg-lenok the
  carveout flag only.
- In v6.16 the adreno GPU binds as a component of the MDSS/MDP5 driver (a headless GPU only for
  `amd,imageon`): `&gpu` alone doesn't come up.

## The panel

Downstream (`dsi-panel-s6e8aa0a-720p-video.dtsi`, `msm8226-sec-s3ve3geur-r04.dtsi`, driver
`mdss_s6e8aa0a_hd_dsi_panel.c`, 2,731 lines with MTP reading and smart dimming):

- S6E8AA0A AMOLED, 720x1280 at 60 Hz, video mode, 4 lanes, RGB888, burst mode (traffic mode 2).
- Timings: HFP 315, HBP 25, HSW 2; VFP 13, VBP 2, VSW 1.
- Reset TLMM GPIO 25 (active low), `qcom,disp-on-gpio` TLMM GPIO 73; DSI supplies vdd L15
  (3.3 V), vddio L8 (1.8 V), vdda L4 (1.2 V).

Mainline `panel-samsung-s6e8aa0.c` (written for Exynos) fits in principle (4 lanes, RGB888, video
burst mode), needs `vdd3-supply`, `vci-supply`, `reset-gpios` and a `display-timings` node, and
reads the panel id (DCS 0xD1), accepting only version bytes 32, 96, 142 and 210; ours is unknown
until read on the phone. The likelier route is a driver generated from the downstream device tree
with linux-mdss-dsi-panel-driver-generator (as the fork's lenok and memul panels): the init
sequence without smart dimming, so a fixed brightness (or a few fixed gamma steps).

## What our kernel would need

- Config: already there `DRM_MSM=m`, `DRM_MSM_MDSS`, `DRM_MSM_MDP5`, `DRM_MSM_DSI`,
  `DRM_MSM_DSI_28NM_PHY`, `QCOM_OCMEM=y`, CMA; `MSM_IOMMU`/`QCOM_IOMMU` off (no use without an
  IOMMU); to add: the panel driver (generated, or `DRM_PANEL_SAMSUNG_S6E8AA0`).
- Device tree: `&gpu`, `&mdss`, `&mdss_dsi0` (supplies, the panel node with its GPIOs and
  supplies), `&mdss_dsi0_phy` enabled; the simple-framebuffer kept until msm takes over.
- Command line: `msm.allow_vram_carveout=1`, `msm.vram=` and `cma=` (pmaports' 192 MB/256 MB
  are a large part of 1.5 GB: try smaller); the bootloader's 1024-byte limit applies, so into
  `CONFIG_CMDLINE`.
- Firmware: `firmware-qcom-adreno-a330` in the image.

## Effort and blockers (estimates)

| Step | Effort |
|---|---|
| GPU, MDSS, DSI enabled in the DT, command line, firmware | about half a day |
| Generated panel driver, DSI timing and power sequence debugged over SSH | 1-3 days |
| GPU acceleration with a fixed brightness, in total | about 3-5 focused days |
| Brightness and gamma (porting MTP/smart dimming, or extending s6e8aa0.c) | 1-2 more weeks |

Blockers, in order: the panel driver and its power sequence; the handover from the bootloader's
framebuffer (resetting the MDSS clocks may blank the screen: test with SSH at hand); no IOMMU
(carveout only, no memory protection); the a305's limits (GLES 3.0, GTK's ngl renderer).

Unverified: whether MDSS with DSI but no working panel binds far enough for the GPU to come up
(a shortcut to test the GPU before the panel); whether msm's DSI ignores the Exynos driver's
`VSYNC_FLUSH`/`AUTO_VERT` flags; whether disp-on GPIO 73 maps onto a fixed regulator for
vdd3/vci.

References:
- https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=3d6ab124a4d5dece5778ac6b7ebea6b6754e7e28
- https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=fc209f869310776c437daba478246df64d82c38b
- https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=d5fb01ad5eb449ccfd950e946a882639cad168b3
- https://gitlab.freedesktop.org/mesa/mesa/-/raw/main/src/freedreno/common/freedreno_devices.py
- https://lore.kernel.org/r/20200109002606.35653-1-masneyb@onstation.org (MSM8974 MDP IOMMU RFC, not merged)
