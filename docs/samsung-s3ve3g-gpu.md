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

## Bring-up status (2026-11-12, patches 0008 and 0009)

0008 adds a panel driver (`panel-samsung-s3ve3g-s6e8aa0a`, among the fork's generated MSM8226
panels): the init sequence and fixed gamma parsed from the vendor dtsi, the reset sequence
`<1 20 0 20 1 20>` (GPIO 25, active low), power on GPIO 73 (`enable-gpios`), 4 lanes, burst video
mode; for bring-up it logs the panel id and has `skip_init` (keep the bootloader's setup). 0009
enables MDSS, DSI0 with the panel (vdda L4, vdd L15, vddio L8) and the GPU; the command line has
`msm.allow_vram_carveout=1 msm.vram=64m cma=128m`. msm is blacklisted for now
(`/etc/modprobe.d/s3ve3g-display-manual.conf` in the device package): `modprobe msm` by hand.

What works: msm binds MDP5 (v1.1), DSI0 and the Adreno 305B (a330 firmware loads); the panel
answers over DSI in low-power mode (id `a2 60 90`, the bootloader's `lcd_id=0xa26090`), the init
sequence is accepted; the DSI clocks are exact (VCO 495.5 MHz, byte 61.9 MHz, pixel 82.6 MHz); the
MDP's INTF1 runs at 60 Hz without underruns.

What doesn't: the panel stays black. The DSI's video FIFO underflows on every line (`FIFO_STATUS`
0x88881000: VIDEO_MDP_FIFO_UNDERFLOW and the lanes' HS FIFO underflow; `dsi_err_worker: status=4`
is DSI_ERR_STATE_FIFO, ~80000 interrupts a second, ~5 % CPU); a DCS command in high-speed mode
times out (-110). Ruled out: the init sequence (black with the bootloader's panel setup too), the
framebuffer contents (white written to the scanout buffer), burst vs non-burst, the DMA vs VIG
pipe, downstream's PHY timings (`5C 16 0E 00 22 30 22 25 20 03 04 00`), downstream's MDP QoS/clock
control and VBIF values, restarting the DSI while the MDP runs, the PHY regulator mode (downstream
is DC-DC, mainline's default; LDO mode made no difference).

Downstream for comparison (TWRP's kernel, display on, read with a static `mmap64` /dev/mem reader:
busybox's devmem can't map above 2 GB there): DSI controller, INTF1 and the mixer are nearly
register-identical, `FIFO_STATUS` 0x00001000 (no underflow); the PLL has the same post-dividers,
only the sigma-delta seed and calibration differ; downstream scans out through VIG0 and enables
DSPP. The clock controller (0xfd8c0000, 0xfd8c2000, 0xfd8c5000) too: pixel and byte clocks have
the same source (the DSI PLL) and configuration (M/N/D bypassed), the MDSS branches and GDSC are
the same; downstream runs the MDP at 92.3 MHz (mainline 200 MHz) and MMSS AXI at 37.5 MHz
(mainline 100 MHz). So the static configuration matches; what differs is behaviour: with
mainline's INTF1 timing engine stopped, the DSI's `FIFO_STATUS` reads 0x11111000 (FIFOs empty,
no underflow), and the underflow comes back as soon as INTF1 runs, while INTF1 itself reports no
underrun. Next: the downstream DSI/MDP video-mode enable sequence (mdss_dsi_host.c,
mdss_mdp_intf_video.c) against mainline's, register writes in order (e.g. with msm's register
tracing), and asking the msm8226-mainline people (video-mode DSI panels on 8226).

Without simpledrm (the simple-framebuffer node disabled) msm crashes in
`dsi_pll_28nm_clk_recalc_rate` (external abort): nothing keeps the MDSS clocks on, and the PLL's
registers are read unclocked; the simple-framebuffer node holds them until msm takes over.

Other msm problems seen: blanking and unblanking the display (`fb0/blank`) crashes in
`mdp5_crtc_atomic_flush` (external abort at 0xfd903200); fbcon warns "framebuffer is not in
virtual address space" (msm's fbdev doesn't set FBINFO_VIRTFB; only a warning).

## The display works (2026-11-12, patches 0008, 0011, 0012)

With msm loaded (`modprobe msm`; still blacklisted at boot, see below) the panel shows the console,
reset and initialized by our driver with the vendor tree's init sequence, stable. Three fixes:

1. 0011, the DSI PLL's byte clock mux (VREG_CFG bit 1, POSTDIV1_BYPASS_B): the 8226 VCO prepare
   resets the PLL, which clears it, while the clock framework keeps the parent it read from the
   bootloader (the indirect path, VCO/2) and never writes it again; the byte clock then came
   straight from the VCO, twice what the controller expects: the lanes' HS FIFOs underflowed on
   every line (FIFO_STATUS 0x88881000; the earlier "VIDEO_MDP_FIFO_UNDERFLOW" reading was wrong,
   bit 3 isn't set), high-speed commands timed out. Found by comparing with the downstream
   kernel's registers (VREG_CFG 0x02 there, 0x00 here) and confirmed live: writing 0x02 made
   FIFO_STATUS 0x00001000 (healthy) at once.
2. 0012, the clock lane in LP-11 while the panel is reset and initialized: msm forced it to HS in
   the bridge's pre_enable, before the panel's prepare (and for a non-continuous clock left the
   bootloader's HS force in place, which the controller reset keeps). Out of reset with the clock
   lane in HS the panel answered commands (id, power mode 0x18/0x1c, display on) but its booster
   stayed off and it never took the video stream; with the bootloader's setup kept (no reset) the
   same init sequence worked. The vendor kernel holds the lanes in LP-11 for the panel reset;
   0012 clears the HS force in dsi_ctrl_enable and sets it in a new bridge enable (after the
   panel's prepare, before its enable). A non-continuous clock instead made the picture fade
   into magenta noise.
3. In the panel driver (0008), display on in enable, with the video stream running.

The bootloader's own command table for the panel (aboot, `mdss_dsi_samsung_720p_video_s6e8aa0a`,
found by its byte patterns: Qualcomm LK's `{size, payload, wait}` entries, payloads with 4-byte
DSI headers) differs from the vendor tree's (panel condition F8 0x19/0x04, gamma, ELVSS B1 04 00,
no ACL); both work now, the vendor tree's gives the right colours.

msm loads at boot (the blacklist in `/etc/modprobe.d/s3ve3g-display-manual.conf` is commented out).

Powering the display down and up (DPMS: `fb0/blank`) works since 2026-11-12:
- 0013 commits planes after the modeset enables (unblank aborted on the LM registers before the
  DSI's pixel clock was back) and takes the CRTC's irq masks in atomic_enable; 0014 + the DT give
  the MDSS the MMSS_MISC_AHB_CLK (only the DSI had it); the panel sends sleep in in its disable.
- The freeze that remained: after the MDSS's own runtime suspend/resume the MDP's registers are
  unreachable, and the first CTL write in the CRTC's atomic_enable hung the bus (found with a live
  `cat /dev/kmsg` and drm.debug over SSH: the log stops at "enabling [CRTC:53:crtc-0]" right after
  mdss_runtime_resume/mdp5_runtime_resume). With the MDSS kept from runtime suspend
  (`power/control = on`) blank and unblank work, the MDP, the DSI and the panel still power down.
  The device package does that with a udev rule (`90-s3ve3g-mdss.rules`). The cause in the MDSS
  resume (power domain, a clock, a reset) is still to be found; the rule works around it.
- `s3ve3g-screen off|on` (the screen-off service after boot) uses DPMS with msm: the panel gets
  display off and sleep in, the MDP and DSI suspend; without msm it clears the framebuffer.
- Console blanking stays off (`consoleblank=0`, the ESC[9;5] taken out of `/etc/issue`), it would
  work now.
- Debugging aids: `kernel.panic_on_oops = 1`, `kernel.panic = 10` (device package sysctl; the
  phone restarts by itself; ramoops keeps nothing across that restart here),
  `/sys/module/kernel/parameters/pause_on_oops` and a live `sudo cat /dev/kmsg` over SSH to get an
  oops out (netconsole doesn't work over the USB gadget network: no netpoll), msm.reglog=1.

GPU (2026-11-12): works. kmscube (Alpine's, `kmscube -D /dev/dri/card1`) gets `vendor: freedreno`,
`renderer: FD305`, OpenGL ES 3.0 (Mesa 26.2.6), renders at 60 fps, and the cube is on the panel
(seen through the camera; out/s3ve3g/screens/cube-camera-back2.jpg); the DMA pipe's source address
alternates between kmscube's two buffers. 0013 also takes the CRTC's irq masks from the new state
in atomic_enable (the planes-after-enables order had left them empty: no vblank irq, page flips
never completed).

kmscube quits as soon as its stdin is readable ("user interrupted!"): started in the background
with stdin closed or /dev/null it ran one or two frames, and the display fell back to the console,
which first looked like the MDP not latching new pipe addresses. Run it from an interactive SSH
session, or with a stdin that never delivers (`sleep N | kmscube ...`); the phone has an OpenRC
service for that (`/etc/init.d/kmscube`, local, not in the package yet: `rc-service kmscube
start|stop`; stop it again, its static background on the AMOLED).

The camera app's `/video/snapshot` can return a stale picture: `tools/s3ve3g-screenshot.sh` takes
the newest frame of the MJPEG stream (`/video/mjpeg`) and turns it upright.

The panel driver's bring-up switches (`skip_init`, `no_reset`, the power-mode log) and 0010's
register trace can go once that's done. The camera setup for checking the screen:
`tools/s3ve3g-screenshot.sh` (and the project skill `s3neo-screen`).

## Brightness (2026-11-12, patch 0008)

The AMOLED has no backlight: brightness is the gamma table (DCS 0xFA, 26 bytes, then 0xF7 0x03
"gamma update"). The panel reports id `a2 60 90`, version 0x60 = 96, which mainline's
`panel-samsung-s6e8aa0.c` (the Exynos Galaxy S III's panel) has 25 tables for
(`s6e8aa0_gamma_tables_v96`, about 30-300 cd/m²). The vendor dtsi's fixed table is closest to the
top one. Our driver registers a backlight device with those tables:
`/sys/class/backlight/fd922800.dsi.0/brightness`, 0-24, default 24. It's sent in LP mode while the
video stream runs, applied again on enable (it survives DPMS off/on), and skipped while the panel is
off. Checked through the camera: in the MJPEG stream the screen jumps about 2× (saturated) going
from 0 to 24, before the camera's auto exposure catches up. Not done: smart dimming from the
panel's MTP (per-panel calibrated gamma, as downstream does); 0 is dim but not off (use DPMS).

## Effort and blockers (estimates)

| Step | Effort |
|---|---|
| GPU, MDSS, DSI enabled in the DT, command line, firmware | about half a day |
| Generated panel driver, DSI timing and power sequence debugged over SSH | 1-3 days |
| GPU acceleration with a fixed brightness, in total | about 3-5 focused days |
| Brightness and gamma (porting MTP/smart dimming, or extending s6e8aa0.c) | 1-2 more weeks (fixed tables done) |

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
