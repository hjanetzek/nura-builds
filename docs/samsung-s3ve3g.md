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
  sequencer, YAS530 driver, Terminus 16x32 console font (`fbcon=font:TER16x32` in the device
  package's kernel command line, with the console on the screen last).
- `device-samsung-s3ve3g` (pkgver 104): the mainline kernel, the device tree in a QCDT table
  (`dt.img`, version 1: platform, variant, soc_rev; Samsung's bootloader picks the entry by
  `qcom,msm-id`), no lk2nd. The kernel package makes it (`mkqcdt-v1.py`, the same bytes as the
  downstream build's for the downstream DTB): pmaports' skales `dtbTool` writes 0 instead of
  soc_rev (0x20000) for version 1, so no entry matched exactly. It also gives the DTB 16 KB of
  free space (kernel r111): with debug markers at the decompressor's first instruction (patch
  0003, r110) nothing reached the RAM buffer, so the bootloader never jumped into the kernel; it
  edits the DTB in place before (memory ranges, its own ~1 KB of command line plus ours) with
  only a small padding, and resets when that fails. lk2nd (QCDT version 2) and an appended DTB
  go to download mode instead: this bootloader takes QCDT version 1 only. An appended device tree didn't boot (the phone went straight back to
  download mode); lk2nd too packs its device trees for Samsung's msm8226 bootloaders as QCDT. Flashed with
  heimdall: the kernel to BOOT, the rootfs to USERDATA (SYSTEM is too small). BOOT holds about
  10 MB: with the whole initramfs (13 MB, zstd) the boot image had 19 MB ("BOOT partition is too
  small"), so `deviceinfo_create_initfs_extra` (filesystem tools, udev, the FDE unlocker in
  initramfs-extra on the rootfs' boot partition) and `lzma` compression.

Each run uploads the `.apk` files (artifact `apks-s3ve3g-kernel`) and the package repository for a
local image (`packages-s3ve3g-kernel`, `packages.tar`).

Status 2026-11-12: flashing works (heimdall, BOOT and USERDATA). With an appended device tree the
bootloader went back to download mode; with QCDT it starts the kernel ("KERNEL IS NOT SEANDROID
ENFORCING"), which resets about 2 s later (Samsung logo, black, again). Tried: the reserved memory
as downstream (kernel r106). Trying (device package r4): no `earlycon` (the release bootloader
likely leaves the UART unclocked: an access resets the SoC; the generic msm8226 port has lk2nd set
it up), `clk_ignore_unused pd_ignore_unused` (simpledrm is a module, loaded after the kernel turns
off the "unused" MDSS clocks and power domain under the splash framebuffer). A downstream boot.img
(LineageOS) has the same QCDT entries (version 1, the first three msm-ids) and load addresses. Unknown: whether an entry matches (the
`qcom,msm-id` values are the downstream ones and lk2nd's), the memory layout (from the Tab 4 3G),
the framebuffer format, touch with mms114.

## Kernel 7.3.4 (branch s3ve3g-kernel-next, 2026-11-15)

msm8226-mainline has nothing newer than `v6.16.12-msm8226-u2` (no 6.17+ branch; MSM8974's fork
stops at 6.16 too), so the recipe now takes kernel.org's `linux-7.3.4.tar.xz` (latest stable;
7.4 is at rc2) and applies the fork's stack as patch 0000 (`git format-patch` of its 56 commits
on v6.16.12, ported: the QRTR bus needed `include/linux/device-id/qrtr.h` for the split
`mod_devicetable.h`; dropped: the revert of "Limit command submission when no IOMMU" (that check
is gone), "increase default vram carveout" (no carveout any more), and what went upstream since:
the Moto G2 binding, the Xperia M2 DT and binding). pmaports' recipe itself applies no patches.
Our patches: 0001, 0002, 0004-0011, 0013, 0014, 0016 as they were (0009 with the GPU off by 0019); 0012 (DSI bridge
callbacks are atomic now), 0015, 0017 (ASoC renames), 0018 adapted; none went upstream.

- **Boot image layout:** the zImage is loaded at 0x8000, where the kernel is decompressed to;
  the decompressor first copies itself past the end of the decompressed kernel, and that copy
  must stay below the device tree, which the bootloader puts at 0x01e00000
  (`deviceinfo_flash_offset_tags`). 6.16.12 had 0.7 MB to spare; 7.3.4 with
  `CONFIG_DEBUG_INFO_BTF` (4.3 MB of `.BTF` in the image) overwrote the DTB and hung at the
  Samsung logo. BTF is off now (pmOS' kconfig check wants it; nothing here uses it;
  `MODULE_ALLOW_BTF_MISMATCH` goes with it), and the recipe's build() fails when the margin is
  gone (7.3.4: ends at 0x1b1xxxx, 3 MB left).
- Works (tested): boot, USB network, SSH, Wi-Fi, CPU scaling with the S2 voltages up to
  1593.6 MHz (as on 6.16), sound: speaker, headphones, main mic, JACK, the display (below).
- **JACK:** q6asm takes period sizes in steps of 480 frames (10 ms) since 6.18 (81c53b52de21):
  `-p480` or `-p960`, not `-p512` ("cannot set period size").
- **Display through the MDP IOMMU (patches 0019, 0020).** Since 6.17 msm refuses to
  run without an IOMMU (drm_gpuvm: "Remove vram carveout support", "stop supporting no-IOMMU
  configuration"). MSM8226's MDP IOMMU (SMMU v1 at 0xfd928000, global registers owned by
  TrustZone, secure id 1, context banks from 0xfd930000) now runs on qcom_iommu. What it took:
  - TZ routes the MDP's stream to context bank 0 only after the IOMMU secure page tables are
    set up (IOMMU_SECURE_PTBL_SIZE/INIT, 90112 bytes); before, the traffic bypasses the SMMU
    (the scanout read the physical address equal to the IOVA, DSI commands from an IOVA
    buffer reached nothing). The downstream kernel does it at boot; done ~1 min after boot
    (qcom_iommu's secure context) the SoC reset 1.5-3 s later, whatever memory the table was
    in; done at the end of the SCM probe (0020, 0.11 s) it works. SET_CP_POOL_SIZE: not
    supported by this TZ (-95).
  - qcom_iommu as downstream's msm_iommu-v1 programs the context bank: short-descriptor page
    tables (TTBCR 0, PRRR/NMRR, ASID in CONTEXTIDR), no access flag (with AFE every access
    gave an access flag fault), terminate instead of stall on faults (a stall wedged the MDP
    and the DSI command DMA); the context banks programmed again after each power collapse
    of the MDSS GDSC.
  - The bootloader's splash scanout is stopped (INTF1 timing engine off, pipe unstaged) before
    the MDP gets its IOMMU domain, as downstream's splash handoff does: its fetches of the
    physical framebuffer faulted and left TLB syncs timing out and the DSI DMA dead.
  Tested: console on msm from 11.7 s (10 s earlier than with 6.16's carveout), no IOMMU
  faults, DPMS off/on with the GDSC collapsing (mdss off-0) and back, brightness 0-24,
  bl_power 4/0, sound alongside.
- **GPU through its own IOMMU (patch 0021).** The GPU's SMMU (kgsl_iommu, 0xfdb10000, no TZ
  secure id) runs on arm-smmu as a generic SMMU v1 ("qcom,msm8226-smmu-v1"): context banks at
  +0x8000 (its ID registers say +0x4000), no access flag (every access faulted with it: the
  first submission never completed), TLBIVA instead of the missing TLBIVAL; streams 0 and 1
  (gfx3d_user/priv). kmscube (FD305, GLES 3.0) renders at 60 fps on the panel, also after a DPMS
  cycle, with sound alongside. The MDP IOMMU likewise has no TLBIVAL: it invalidates the whole
  context (TLBIASID) on unmap, else stale pages stayed on screen.
- Testing kmscube: run it as the OpenRC service (`rc-service kmscube start`), not from an SSH
  one-liner with `sudo timeout ...`: that way it never takes over the display (on 6.16 too).
- **Open issues:**
  - Fixed (patch 0027): the MDP IOMMU's TLB syncs timed out (5 s) during msm's first init on
    some boots, and the first panel enable failed (blue, then black screen). msm maps and
    unmaps buffers there while the MDP and so the SMMU are runtime-suspended: TLB maintenance
    now only while the SMMU is active (invalidated on resume instead), and the MDP core clock
    is the SMMU's "tbu" clock. 7 of 7 boots clean afterwards (before: about every second).
  - Fixed (patch 0028): the layer mixer's border colour (shown without a staged plane) is set
    to black; it was blue (flashes during the boot splash, the blue screen after screen-off).
  - Open: one or two short blue flickers before the boot splash (msm takes over at ~4.3-4.7 s,
    panel on at ~5.2 s). Ruled out: the layer mixer's border colour at the splash handover and
    at mode set (0028, and 0029's black border fill with the timing engine running instead of
    stopped), the interface underflow colour (0030; ~10 underrun interrupts at each enable).
    Remaining candidates: the panel itself while it is reset and initialised (S6E8AA0A
    prepare/enable), the bootloader's handover (LK's splash, simpledrm's takeover). 0029/0030
    stay: harmless, and they keep blue out of other moments (underruns, CRTC without a plane).
  - The GPU microcode (a330_pm4/pfp.fw) is in the initramfs now (device package's mkinitfs
    files list): msm binds there and requested it before the rootfs was mounted.
  - After the screen-off service (~20 s), something re-enables the CRTC without its plane in
    most boots: a blue screen (the mixer's border colour) until `s3ve3g-screen on`. Not getty,
    seatd or console writes; detaching fbcon before the DPMS blank made it worse.
  - The GPU's GDSC (oxili_cx) stayed on after kmscube quit (GPU and SMMU runtime-active).
- **Slow UI (zynthian view switches ~560 ms by touch, fixed by patch 0022).** Not the IOMMU:
  every runtime suspend of the GPU spun for 1 s and failed (-EBUSY) because "drm/msm/a3xx: Drain
  VBIF before GPU suspend" (7.2) waits for six VBIF XIN acks and the A305B has three (HALT_CTRL1
  0x70007); a frame submitted meanwhile waited for that suspend: 1 in 3 GPU jobs took
  100-900 ms instead of ~20 ms. Measured with ftrace (drm_sched_job_run -> GPU irq, rpm events):
  after 0022 jobs 20 ms median, 24 ms max; runtime suspend under 1 ms. Over OSC (no touch) a view
  switch took ~160 ms CPU (Python/Qt) + ~20 ms GPU on 6.16 and 7.3.4 alike; the touch path itself
  (MMS144 interrupts) was fine. zynthian-ui's spike (`spike.py --bench`) switches in 2-25 ms.
- **GPU memory speed (patch 0023).** Through its IOMMU the GPU first ran memory-bound work far
  slower than 6.16 did from the carveout (glmark2 texture 65 vs 104-109 fps, shadow 12 vs 27).
  Downstream's "bfb" settings of the GPU SMMU (implementation-defined registers 0x2008-0x256c,
  qcom,iommu-bfb-regs of &kgsl_iommu) written at SMMU reset bring every scene to 6.16's speed.
- **Test suites (2026-11-15, 7.3.4 with 0000-0023; tools built on/for the phone):**
  - igt-gpu-tools (git 5a61add, built on the phone, tests/msm): msm_bo 50 pass, 1 skip
    (cached-coherent); msm_submit 8/8; msm_submitoverhead runs (1000 BOs: 1072 submits/2 s,
    1389 without implicit sync); msm_mapping ring/memptrs fail, but the test writes a6xx
    PM4 type-7 packets, which hang an a3xx (no fault-info devcoredump); msm_shrink,
    msm_recovery, msm_perfcntrs skip (need gen >= 6 or perf counters).
  - glmark2-es2-drm 2023.01 (720x1280, --swap-mode immediate, mailbox fallback): 7.3.4 score
    89 (before 0023: 72); 6.16.12: same per-scene fps on all scenes it completes, but terrain
    segfaults and refract fails to set up (64 MB carveout), so no total. Run it as root with
    zynthian stopped (DRM master).
  - dEQP (VK-GL-CTS main 5bb4c7e, deqp-gles2/-gles3 cross-built with clang against a sysroot
    copied from the phone, surfaceless, EGL_PLATFORM=surfaceless, 256x256 pbuffer
    rgba8888d24s8ms0 as Mesa's CI; own batch runner instead of deqp-runner), compared with
    Mesa's expectations for the Adreno 306 (src/freedreno/ci/freedreno-a306-fails/flakes.txt):
    GLES2 mustpass (17165): 17019 pass, 30 fail, 111 not supported, 5 quality warnings, no
    crash; 23 of the fails are in the a306 list, the 7 others pass when run again (3x); 12 GPU
    hangs were recovered during the run.
    GLES3 mustpass, every second test (22402 of 44804): 21884 pass, 173 fail, 149 not
    supported, 195 quality warnings, no crash; 43 fails in the a306 list, 86 in tests Mesa's CI
    skips for the a306 (.*msaa.*, .*multisample.*), 12 pass when run again, 2 fail every time
    (fbo.blit.conversion.rg8_to_rgb10_a2, fbo.invalidate.incomplete.depth_stencil: A305B vs
    A306 or Mesa, not checked on 6.16); 15 GPU hangs were recovered (hangcheck), some of them
    from the tests that later passed. Not run: glcts KHR, piglit, fdperf, the suites on 6.16.
  - Tools: igt in ~/igt on the phone; dEQP built in /home/jeff/bastel/github/deqp-armv7
    (toolchain.cmake, sysroot from the phone), on the phone in ~/deqp with deqprun.py.
- **GPU/kernel test suites** (TODO list, the parts run are above) to run on 7.3.4 (and 6.16.12 for comparison): igt-gpu-tools
  msm tests (msm_submit, msm_mapping, msm_recovery, msm_shrink, ...) for the IOMMU, submit and
  recovery paths; dEQP-GLES2/GLES3 (VK-GL-CTS) via deqp-runner, compared with Mesa's expected
  results for the Adreno 306 in src/freedreno/ci/ (deqp-freedreno-a306*.toml,
  freedreno-a306-fails/flakes.txt); glmark2 (glmark2-es2-drm on KMS) as a benchmark on both
  kernels; optionally piglit; fdperf (src/freedreno/perfcntrs) for GPU counters.

### zynthian glitches and audio start (2026-11-16)

- zynthian's UI showed occasional glitches on 6.16.12 and 7.3.4 alike, gone with
  `FD_MESA_DEBUG=inorder` (freedreno doesn't reorder batches or stage writes to busy buffers):
  a second freedreno problem besides the a3xx buffer blit fix in Mesa 26.2.6-r1, not a kernel
  one. The eglfs launcher sets `inorder` by default (`FD_MESA_DEBUG=` turns it off).
- On 7.3.4 the audio DSP sometimes refuses playback buffers when a JACK stream starts
  (`q6asm-dai: Error queuing playback buffer -11`, at 37, 147 and 279 s in one boot): jackd's
  ALSA driver then stops ("could not start playback (Broken pipe)" or later "Driver is not
  running") and refuses clients, so zynthian exits. Another start usually works. The launcher
  restarts jackd when the driver fails in its first seconds; failures later in a stream aren't
  caught.
- **Fixed (patches 0024, 0025):** the trigger is an xrun, not the start itself. zynthian's
  clients miss deadlines while it starts ("Process error"), and jackd recovers with prepare and
  start.
  - **q6asm-dai (0024):** since upstream e386c2cf3df2 (6.19) playback periods are queued from
    `.ack`, as far as `appl_ptr - queue_ptr`. `queue_ptr` was never reset, while prepare resets
    `appl_ptr`. After the recovery the difference underflowed, and `.ack` sent write commands until
    the APR channel's SMD FIFO to the ADSP was full: the -11 (`rpmsg_trysend()`), and the
    application's write failed. Now `queue_ptr` is reset in prepare and wraps at the boundary,
    never more than the buffer's periods are queued at once, a full FIFO keeps the periods pending
    (queued from a work item or the next write-done), and the DSP buffer index and hardware pointer
    start over with a new buffer mapping. Reproduced on the old kernel by stopping jackd for
    0.3 s (SIGSTOP/SIGCONT): the error pair at once.
  - **wcd9306 (0025):** with 0024 alone the recovered stream ran but was silent: the codec's
    trigger stop disabled its SLIMbus slave ports, which only hw_params enables again, and a
    restart has no hw_params. The ports are now disabled in hw_free.
  - Tested on #101 with both patches: 50 jackd starts without a failure. 15 were with zynthian
    through the launcher (a fresh jackd each time; before, one in six failed), 30 bare with a
    forced xrun each, and 5 checks of the sound itself: a 1 kHz tone through JACK, after 0, 3 and 5
    forced xruns, recorded at the same level on the headphone out (Scarlett) and by the main mic.

## A minimal base, locally

As for the ODROID N2: pmbootstrap with a config of its own, UI `console` (a login on the screen:
the framebuffer console on the bootloader's splash framebuffer, simpledrm, Terminus 16x32 font;
and on serial), SSH over USB networking. The kernel recipe replaces pmaports' one of the same name
and pmaports' archived device package has to go, so not links into your pmaports checkout but a
worktree of it with the overlays copied over (`tools/s3ve3g-pmaports.sh`, run again after
changing them):

```sh
tools/s3ve3g-pmaports.sh     # ~/.local/var/pmbootstrap/cache_git/pmaports-s3ve3g
```

`~/.config/pmbootstrap-s3ve3g.cfg`:

```
[pmbootstrap]
aports = /home/<user>/.local/var/pmbootstrap/cache_git/pmaports-s3ve3g
build_pkgs_on_install = False
device = samsung-s3ve3g
hostname = s3neo
is_default_channel = False
locale = C.UTF-8
service_manager = openrc
ssh_key_glob = ~/.ssh/id_ed25519.pub
ssh_keys = True
timezone = Europe/Berlin
ui = console
user = <user>
work = /home/<user>/.local/var/pmbootstrap-s3ve3g

[providers]
postmarketos-base-ui-audio-backend = postmarketos-base-ui-audio-backend-pipewire
```

Give it a work directory of its own (`work = ...`): pmbootstrap treats systemd and OpenRC as
different channels (`systemd-edge`, `edge`) and refuses chroots of the other one, so a shared work
dir would need a `zap` at every switch between projects. `pmbootstrap init` on a new work dir
resets `aports` to that work dir's own pmaports clone unless the worktree is entered as the
pmaports path: then pmaports' archived device package and the downstream kernel get installed
(a 13 MB boot image, "BOOT partition is too small"), and `flash_rootfs` writes the rootfs to SYSTEM
(the archived deviceinfo has no `flash_heimdall_partition_rootfs`): that happened once
(2026-11-12) and overwrote stock Android's system partition, with the Wi-Fi NV file (see above
for a copy; Android itself needs the stock firmware's system.img to come back).

```sh
C=~/.config/pmbootstrap-s3ve3g.cfg
pmbootstrap -c $C build linux-postmarketos-qcom-msm8226 device-samsung-s3ve3g   # cross-compiled
pmbootstrap -c $C install --sdcard=/dev/sdX     # the rootfs on an SD card
pmbootstrap -c $C flasher flash_kernel          # boot image to BOOT, phone in download mode
```

Instead of the kernel build: the CI's packages (artifact `apks-s3ve3g-kernel`, signed with the CI
key) into pmbootstrap's local repository:

```sh
gh run download <run id> -n apks-s3ve3g-kernel -D /tmp/s3ve3g
W=$(pmbootstrap -c $C config work)
sudo cp keys/nura-builds-ci.rsa.pub "$W/config_apk_keys/"
sudo cp /tmp/s3ve3g/packages/edge/armv7/*.apk "$W/packages/edge/armv7/"
pmbootstrap -c $C index
```

With this repository's scripts (CI's way, its own work dir, UI `none`): `TARGET=s3ve3g
NURA_ARCH=armv7 scripts/setup.sh` (with `packages-s3ve3g-kernel` in `$NURA_OUT`, or
`scripts/build.sh kernel`), then `scripts/image.sh samsung-s3ve3g`: `$NURA_OUT/s3ve3g-samsung-s3ve3g.img.zst`
and `-boot.img.zst`. setup.sh copies the overlays into the pmaports checkout it uses (CI's way).

## The command line limit

Samsung's bootloader appends about 840 characters to the boot image's command line (sec_log,
cordon, connie, ...) and doesn't boot when the total exceeds 1024 bytes: it shows the red "not
SEANDROID enforcing" text, then resets (a loop), without starting the kernel. Found with hybrid
images (TWRP, which boots from BOOT, with our 329-character command line loops; downstream's 141
and TWRP's 75 boot) and the RAM log (debug markers at the decompressor's first instruction never
appeared). So the boot image keeps only pmOS's `pmos_*` options (about 130 characters, at most
183): the device options are built into the kernel (`CONFIG_CMDLINE`, `CONFIG_CMDLINE_EXTEND`,
appended to the bootloader's line; `COMMAND_LINE_SIZE` raised to 2048, patch 0004), and the device
package overrides `quiet` and plymouth's options with empty files in `/etc/kernel-cmdline.d`.

## First boots (2026-11-12)

With the command line fixed, pmOS boots to the login prompt (framebuffer console on the splash
framebuffer, Terminus 16x32). Found on the way:

- Kernel modules must match: `flasher flash_kernel` only replaces the boot image; the modules in
  the rootfs stay those of the installed kernel and were refused when the kernel changed (BTF
  mismatch, `failed to validate module [ext2] BTF: -22`: no /boot, emergency mode). Since r113
  `CONFIG_MODULE_ALLOW_BTF_MISMATCH=y`: test builds keep the version and only the boot image is
  flashed (as long as the kernel's core structures don't change):

  ```sh
  pmbootstrap -c $C build --force linux-postmarketos-qcom-msm8226
  pmbootstrap -c $C chroot -r -- apk fix -r linux-postmarketos-qcom-msm8226   # same version: reinstall
  pmbootstrap -c $C flasher flash_kernel
  ```

  A new rootfs (`install`) needs `flash_rootfs` and `flash_kernel` (new UUIDs each install).
- No USB networking in the booted system: pmOS's initramfs sets up the gadget once, early in
  stage 1, and found no UDC: the USB controller waits for the USB switch (extcon), and
  extcon-sm5502 was a module that probed later. Built in (kernel r113: `EXTCON_SM5502`,
  `I2C_GPIO`, `INPUT_EVDEV`).
- Logs without network: the ramoops buffer from TWRP (`/proc/last_kmsg`, the first part of the
  boot), and the initramfs's log drive in its debug shell (USB mass storage `PMOS_LOGS`:
  `pmOS_init.txt`, `dmesg.txt`).

## Hardware status (2026-11-12, kernel r113)

Works: boot to the login prompt, USB networking (cdc_ncm, SSH at 172.16.42.1), simpledrm on the
splash framebuffer (720x1280; built in since the debug markers of patch 0003 were removed: it holds
the framebuffer's clocks and power domain from early on), eMMC, keys, hall sensor, power key, touchscreen (MMS144 with the
mms114 driver: whole screen, axes right, multitouch; its open-drain interrupt needs the pull-up and
a level trigger),
magnetometer (yas532), IMU (mpu6500), PMIC ADCs, Wi-Fi (2.4 and 5 GHz; `hal_start_scan ... err=5`
from the old firmware is harmless), Bluetooth (registers), 4 CPUs with cpufreq up to 787 MHz.

Firmware: the device package copies what the device needs from the stock partitions into
`/lib/firmware` once, before udev (`s3ve3g-firmware`, systemd unit and OpenRC script): the Wi-Fi
core's firmware (`wcnss.mdt`, `wcnss.b*`, apnhlos/image; the only remote processor enabled) and the
NV calibration file `wlan/prima/WCNSS_qcom_wlan_nv.bin` (system/etc/firmware/wlan/prima; without it
the WCNSS firmware crashes in a loop; if the system partition no longer has it, the same file,
29816 bytes, sha256 5e235506a12c5e7cde329c045d702f801b4fa7a2ac036a49445c12f0d5347701, is in
LineageOS' android_device_samsung_msm8226-common, lineage-18.1, prima/; copy it to
/lib/firmware/wlan/prima/ on the device). It replaces msm-firmware-loader, which mounted and scanned
all firmware partitions on every boot (4 s at 787 MHz, before udev) and didn't find the NV file.

Wi-Fi stability (2026-11-12): with NetworkManager's default power save the WCNSS firmware crashed
after 6 to 16 minutes in every run (after failed `hal_enter_bmps` power-save entries), with and
without CPU scaling. With power save off (`wifi.powersave = 2` in
`/etc/NetworkManager/conf.d/90-wifi-powersave-off.conf`, on the phone only so far) a 25-minute run
had no crash, with CPU scaling on and a download of about 540 KiB/s for most of it. Power save is
the likely trigger; it isn't in the device package yet. A WCNSS restart after a crash still fails.

Boot time (2026-11-12): 1:16 at first, 43 s with systemd at 787 MHz, 35.1 s with OpenRC; 24.7 s
with the CPU voltages (patches 0005/0006, up to 1190.4 MHz: from cpufreq-dt's module at 17 s on),
17.8 s now: cpufreq-dt built in (the CPU at speed from 0.6 s), no `ignore_loglevel`, and a no-op
`/lib/mdev/persistent-storage` in the initramfs (the device package; postmarketos-initramfs's
mdev.conf calls it but doesn't include it: 30 "not found" lines). Root switched at 9.4 s, getty at
17.8 s. Earlier (systemd, 43 s: kernel and initramfs 17 s, userspace 26 s):
simpledrm built in, systemd-nsresourced/-mountfsd masked (their BPF programs fail on this kernel;
nsresourced once held up udevd for 32 s), nftables (firewall) and plymouth masked, no
msm-firmware-loader. What remains is the CPU at 787 MHz (higher frequencies need voltage scaling:
speed bin/PVS fuses, the CPU rail through SAW/SPM, CPR; none in mainline for MSM8226), and
NetworkManager (5 s) on the path to the login prompt.

Init system: systemd was only nura-builds' default, so the local image switches to OpenRC
(`service_manager = openrc` in `~/.config/pmbootstrap-s3ve3g.cfg`). The device package works with
both: no boot splash for either (it depends on `postmarketos-base-nosplash`, the provider of
`postmarketos-bootsplash-virtual` without plymouth); systemd: the masks above in `/etc/systemd/system`;
OpenRC: the `device-samsung-s3ve3g-openrc` subpackage (installed with `postmarketos-base-openrc`),
whose post-install script enables `s3ve3g-firmware` (sysinit) and removes `nftables` from the default
runlevel (after `postmarketos-base-nftables-openrc` added it). The `l24: unsupportable voltage range` warning is the
iris driver's default for vdddig; downstream feeds vddrfa and vdddig from l24 too.

Missing: the battery gauge (PM8226 BMS: no mainline driver; the charger works, see below),
smart dimming for the panel (fixed gamma tables for brightness 0-24 work; see samsung-s3ve3g-gpu.md for the panel, GPU and
display path), CPR and speed-bin reading for the CPU, SD card
(the controller probes, untested with a card), NFC, cameras, modem.

Charger, LED, light sensor, touch keys, vibrator (2026-11-20, kernel 7.3.4, patch 0031, all with
mainline drivers, wiring from the downstream device tree):

| Part | Wiring | Driver | State |
|---|---|---|---|
| Charger (PM8226 SMBB) | | `qcom_smbb`, power supplies `smbb-bif`, `smbb-usbin`, `smbb-dcin` | charges from USB: "Charging", "Fast", battery present and good; limits as downstream: 4.2 V, recharge below 4.1 V, input minimum 4.3 V, 1.5 A (downstream doesn't override Qualcomm's defaults for the s3ve3g's 2100 mAh battery) |
| Battery level | VPH_PWR (VADC_VSYS) | `qcom_smbb` with patch 0032: `voltage_now`, and `capacity` from the battery's open circuit voltage curve at 25 degrees C (downstream's battery data for the 2100 mAh battery, simple-battery node, patch 0033) | an estimate (no fuel gauge driver): reads high while charging and low under load. A full charge to downstream's 4.2 V reads about 90 % (the battery is a 4.35 V one). zynthian's top bar shows it |
| Notification LED AN30259A | bit-banged I2C (SDA 23, SCL 16), 0x30 | `leds-an30259a`: `red:status`, `green:status`, `blue:status` | registers, brightness accepted; not seen yet |
| Light/proximity CM36651 | same bus, 0x18 (and 0x0c, 0x19), interrupt GPIO 65, supply GPIO 110 (from L19) | `cm36651` (IIO): red, green, blue, clear, proximity | values read |
| Touch keys (menu, back) | Cypress on bit-banged I2C (SDA 114, SCL 66), 0x20, interrupt GPIO 49, supply GPIO 67, key light GPIO 56 | `tm2-touchkey` as `cypress,midas-touchkey` (Samsung's Galaxy S III firmware: key state in register 0, LED commands 0x10/0x20, as downstream's cypress_touchkey_s3), KEY_BACK and KEY_MENU, LED `tm2-touchkey` | probes; key presses not tried yet |
| Vibrator DRV2603 | enable GPIO 111, PWM input GPIO 33 (gp0_clk) | `gpio-vibrator` (force feedback), the PWM input held high | the enable line switches; whether the motor turns not checked yet. Downstream drives the PWM input at 25 kHz, 90 %: if a static level isn't enough, `clk-pwm` on GCC_GP1_CLK (GPIO 33 function gp0_clk; MSM8226's GP clock table needs a 25 kHz entry: 19.2 MHz / 16 * 1/48) and `pwm-vibrator` |

Audio (WCD9306 codec on SLIMbus, no mainline driver): samsung-s3ve3g-audio.md.

Screen: brightness is `/sys/class/backlight/fd922800.dsi.0/brightness` (0-24, gamma tables). Without msm
(the bootloader's framebuffer, simpledrm) there is none and `fb0/blank` doesn't turn it dark. The AMOLED's black pixels are off, so the device
package turns the screen black after boot against burn-in: `s3ve3g-screen off` detaches the text
console from the framebuffer and clears it (OpenRC `s3ve3g-screen-off` in the default runlevel,
systemd `s3ve3g-screen-off.service`); `s3ve3g-screen on` brings the console back (or
`rc-service s3ve3g-screen-off stop`). buffyboard (on-screen keyboard) draws on its own.

## CPU above 787 MHz: what mainline lacks (2026-11-12)

The A7 PLL (`qcom,msm8226-a7pll`, up to 1344 MHz in its OPP table) and cpufreq are mainline
(Luca Weiss, "Add CPU frequency scaling support for MSM8226", accepted 2024-06): its CPU OPP table
stops at 787.2 MHz without voltages ("Higher CPU frequencies need speedbin support"; his cover
letter: speedbin support planned after that; nothing on linux-arm-msm since, patchwork search
2026-11-12; the msm8226-mainline fork's `*-wip-cpufreq` branches are that same series). Downstream
(the S III Neo's device tree):

- `qcom,clock-a7-8226`: frequency/corner tables per speed bin (qfprom row 0x16 at 0xfc4b80b0, bits
  0-2: speed bin, 6-10: PVS): speed0/6 up to 1190.4 MHz, speed2/4/5/7 up to 1401.6 MHz, speed1
  finer steps.
- `qti,cpr-regulator` (`apc_corner`): 12 corners mapped to SVS/NOM/TURBO; ceilings per PVS class
  slow/nom/fast: TURBO 1.28/1.20/1.14 V, SVS and NOM 1.14-1.15 V; closed-loop CPR on top;
  VDD_MX (L3, RPM) must stay at or above the CPU voltage (`vdd-mx-vmin-method = 1`, max 1.35 V).
- `qcom,spm-regulator` on PM8226 S2 (0x1700, 0.9-1.33 V): the voltage goes through the SAW2/SPM,
  whose power-collapse sequence writes the PMIC itself.

What exists in mainline and what is missing, in order:

1. CPU rail through the SPM: `drivers/soc/qcom/spm.c` registers SPM regulators (`set_vdd` per SoC,
   linear range) but implements only SAW2 v1.1 (APQ8064); MSM8226's SAW2 v2.1 entry exists for
   cpuidle only. Needed: a v2.1 `set_vdd` (VCTL, PMIC_DATA_0/1; PM8226 S2's voltage encoding, see
   downstream spm-regulator.c) and the regulator on the CPU SAW nodes. Setting S2 directly over SPMI
   (`qcom,pm8226-regulators` has it) would be undone by the SPM after idle; the SAW coupling in
   `qcom_spmi-regulator.c` is SAW3 only (MSM8996).
2. VDD_MX: downstream's `vdd-mx-supply` is PM8226 L3 (`pm8226_l3_ao`, an RPM LDO voltage, not a
   corner), raised to the CPU voltage when that goes higher; cpufreq-dt has one supply only.
3. Speed bin: `qcom-cpufreq-nvmem` with an `msm8226` entry (`qcom_cpufreq_simple_get_version`, as
   MSM8909) and an nvmem cell for the raw qfprom row (the qfprom node starts at 0xfc4bc000, the fuse
   is at 0xfc4b80b0); OPPs with `opp-supported-hw` per bin and `opp-microvolt`.
4. Voltages: open loop first, the slow-PVS ceilings for every chip (TURBO 1.28 V: safe, warmer);
   PVS-dependent voltages need PVS reading in cpufreq-nvmem (as the Krait variants do).
5. CPR (lower voltages, closed loop): `drivers/pmdomain/qcom/cpr.c` (CPR v1, genpd) knows only
   qcs404; an MSM8226 description from downstream's `qti,cpr-*` fuse layout.

1-3 with the slow ceilings would give 1190.4 MHz (or 1401.6 MHz on the higher bins) safely.

This phone (read in the repacked TWRP, downstream kernel; /dev/mem doesn't map the qfprom there):
speed bin 1, cpufreq 300 MHz to 1593.6 MHz (the speed1 table); at 1593.6 MHz CPR held S2 at 1.23 V
(corner 12). Speed bin 1 gets a 50 mV uplift (`qti,cpr-uplift-speed-bin = 1`, at most 1.35 V), so
its TURBO ceilings are 1.33/1.25/1.19 V (slow/nom/fast): the chip is slow or nom. Open loop (no CPR)
the top frequencies need 1.33 V (near S2's 1.35 V maximum, with VDD_MX as high); CPR would bring
that to about 1.23 V.

### What the overlay does (patches 0005, 0006)

Read on the running phone (mainline, `/dev/mem` and `/sys/kernel/debug/regmap/0-01/registers`;
read single PMIC registers with `dd bs=9 skip=$((0xADDR)) count=1` on that file: reading all of it
asks the arbiter for 64K registers, most of them denied and logged):

- Only the L2/APCS SAW (0xf9012000) has the PMIC arbiter port: SAW2_ID 0x2010086f (bit 2 set), the
  CPU SAWs 0x120f0861. SAW2 version 0x20010000 (v2.1).
- S2: FTS2 (type 0x1c, subtype 0x08), range 1 (0x1740 = 1: 700-2040 mV, 10 mV steps), setpoint
  0x73 (1.15 V, from the bootloader), mode PWM (0x80), step control 0x81 (9.6 mV/us with
  downstream's margin).
- L3 (VDD_MX): 0x49 in range 0, 1.2875 V; the CPU voltage stays below that.
- A write of the voltage (mV / 10) to the L2 SAW's VCTL (0x1c, port 0; after RST 0x18 := 1) sets
  S2 at once: PMIC_STS (0x14) and S2's setpoint 0x1741 follow (tried 0x73 -> 0x74 -> 0x73).

0005 adds that to `spm.c`, a regulator on the `qcom,msm8226-saw2-v2.1-l2` node (shared by all
CPUs, written from any). 0006 (s3ve3g) supplies the CPUs from it, with OPP voltages open loop for
speed bin 1: SVS 1.05 V (300, 384 MHz), NOM 1.15 V (600, 787.2 MHz), TURBO 1.28 V (998.4-1190.4 MHz,
and 1305.6-1593.6 MHz as boost frequencies, off by default):

```sh
echo 1 | sudo tee /sys/devices/system/cpu/cpufreq/boost   # up to 1593.6 MHz (until reboot)
```

No speed-bin reading (the OPPs are for this phone's bin), no CPR, no MX scaling.

Tested (2026-11-12): S2 follows the frequency (0x69 at 300 MHz, 0x73 at 600/787.2 MHz, 0x80 from
998.4 MHz); 3 minutes of sha256 over a 16 MB file on all four cores, every result compared, at
1190.4 MHz (925 runs, none wrong, 62 °C) and with boost at 1593.6 MHz (1088 runs, none wrong,
67 °C, levelling off).

### Boot splash (2026-11-16)

pmOS's boot splash (plymouth with the DRM renderer, `postmarketos-bootsplash`) comes up right
after the Samsung logo, with no console text before it:
- **Kernel command line:** plymouth's `splash plymouth.ignore-serial-consoles plymouth.prefer-fbcon`
  are in CONFIG_CMDLINE (the boot image's command line has no room: Samsung's bootloader appends
  ~840 characters, 1024 at most); the device package still empties `20-plymouth.conf`.
- **No text before the splash:** `quiet loglevel=3 vt.global_cursor_default=0` and
  FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER: fbcon only takes over simpledrm's framebuffer when
  something is printed, so the bootloader's logo stays until msm and plymouth take over
  (loglevel=3 after quiet: msm's KERN_ERR messages, e.g. "Couldn't initialize GPU devfreq", would
  otherwise trigger the takeover). simpledrm itself stays: it keeps the MDSS clocks and power
  domain on until msm takes over (without the simple-framebuffer node msm crashed reading the
  DSI PLL).
- **msm in the initramfs:** the device package's mkinitfs modules list
  (`/usr/share/mkinitfs/modules/90-device-samsung-s3ve3g.modules`: msm, the panel module);
  mkinitfs no longer reads `deviceinfo_modules_initfs`. The GPU microcode (a330_pm4/pfp) is in the
  initramfs too (files list), since msm asks for it before the rootfs is mounted. msm is ready at
  ~4.5 s instead of ~11.7 s; boot image ~8.0 of 10 MB.
- **CRNG seeded early (0026):** udevd in the initramfs waited ~1.9 s for the CRNG (ready at 5.6 s).
  qcom-rng now registers MSM8226's PRNG (`qcom,prng`) as a hwrng with full quality: the CRNG is
  ready at 0.23 s. A trade-off accepted for a tinkering device (upstream doesn't credit this PRNG).
- **Fixes on the way:** the MDP IOMMU's TLB sync timed out (5 s) on about every second boot and
  the first panel enable then failed (blue, then black screen): TLB maintenance now only while the
  SMMU is powered, a full invalidate on resume, the MDP core clock as the SMMU's "tbu" clock (0027).
  The mixer border colour was blue (msm never set it), seen as blue flashes at the takeover and
  after the screen-off service: black now (0028).
- Timeline now: init 0.5 s; subpartitions mounted, initramfs-extra (plymouth, 8.9 MB) extracted
  by ~3.4 s; stage 2 / udev 3.4 s; msm ~4.5 s; plymouth on msm.

### Debugging aid: screen and GPU capture on the home key (2026-11-16)

`tools/s3ve3g-debug/s3ve3g-capture.py` (root): on each press of the home key (KEY_HOMEPAGE on
"GPIO Buttons") it saves to `/var/tmp/s3ve3g-captures/<time>-*` the framebuffer on the screen
as PNG (also rotated as zynthian shows it), 5 s of GPU submissions from msm's debugfs `rd`
(command streams; RD_FULL=1 adds the buffers; for Mesa's freedreno tools, cffdump) and the kernel
log. The screenshot reads the scanned-out buffer through DRM as root (GETFB2, exported as a dma-buf
and mapped; msm's GEM_INFO mmap offset is refused for another client's buffer on 7.3.4), so the
application keeps DRM master. `--once` captures without the key. Started by hand, not a service.

## Sensor hub and boot time to zynthian (2026-11-18)

**Sensor hub (open):** the ADSP's sensor hub (Qualcomm Sensor Manager: on the S III Neo typically
magnetometer, proximity and ambient light) doesn't work. `qcom_sns_reg` finds no registry
(`Direct firmware load for qcom/sensors/sns.reg failed`), and `qcom_smgr`, which udev loads when
the ADSP announces its sensor service (`qrtr:100:1`), waits ~6 s for the sensor list and fails
(`Failed to get available sensors: -ETIMEDOUT`). `udev-settle` - and with it seatd and
s3ve3g-zynthian - waited for that probe at every boot, so it is blacklisted
(`/etc/modprobe.d/s3ve3g-no-smgr.conf`). Accelerometer and gyroscope don't need it
(`inv_mpu6050` on I2C).
- `sns.reg` is a per-device calibration/configuration registry: Android's sensors daemon builds it
  from `/system/etc/sensors/sensor_def*.conf` at first start and keeps it in `/persist/sensors/`
  or `/data/misc/sensors/`. This phone's `persist` partition has only `sensors/sensors_settings`
  ("1"), `userdata` and `system` are gone (no file system); the boot.img and the TWRP image
  (twrp-3.7.0_9-1-s3ve3g) have no sensor files either.
- The way to try: the stock firmware (GT-I9301I) `system.img` -> `sensor_def*.conf`, then generate
  the registry from it (replicate the sensors daemon's conversion, or run it once); then remove
  the blacklist file.
- Worth it for zynthian? Little (compass, proximity; maybe automatic brightness from the light
  sensor).

**Boot to zynthian** (first frame of zynthian after a reboot; 4 boots each, kernel r100 7.3.4):

| | seatd | s3ve3g-zynthian | zynthian process | first frame |
|---|---|---|---|---|
| before (zynthian after s3ve3g-screen-off "after local", plymouth waited for) | 15.2-20.5 s | 15.4-20.7 s | 18.6-23.8 s | 35 / 40 s |
| zynthian before the network services, plymouth told to quit | 17.6-17.9 s | 18.3-18.6 s | 20.2-20.7 s | 37 s |
| plus qcom_smgr blacklisted | 12.9-13.2 s | 13.6-13.9 s | 15.5-15.9 s | 32-33 s |
| plus zynthian-ui main 4f33b58c (lazy imports, deferred QML) | 12.9-13.1 s | 13.5-13.7 s | 15.5-15.6 s | **26-27 s** |

The rest: the initramfs until the switch root ~7.7 s (stage 1 -> 2 ~2.9 s, a kernel warning banner
at ~4 s, ~2.3 s before the e2fsck), and zynthian's own cold start (from the process start to the first frame after a boot: ~16.5 s
before, ~10.5-11 s with 4f33b58c; on a service restart ~9 s before: cold page cache). The first-frame
marker (`/tmp/runtime-<user>/zynthian-first-frame`) survives a reboot here (/tmp isn't a tmpfs):
compare its mtime with the boot time.

## Network over USB (2026-11-12)

The phone's Wi-Fi gives about 550 KiB/s; the USB network (172.16.42.1 phone, 172.16.42.2 host)
carries about 7 MB/s (an ssh transfer, and a mirror download through the host). For installing
packages the phone can use the host's internet connection:

- **The USB interface's name depends on the USB port** (enp34s0f3u1u3u2, later enp34s0f3u1u1u3):
  after replugging into another port the ufw route rule must name the new one, otherwise TCP
  stalls (ping still works) - apk then hangs with "Socket not connected". Wi-Fi is the fallback.
- **Host (needs root), with ufw:** `net/ipv4/ip_forward=1` in `/etc/ufw/sysctl.conf`; at the top of
  `/etc/ufw/before.rules` a NAT table
  `*nat` / `:POSTROUTING ACCEPT [0:0]` / `-A POSTROUTING -s 172.16.42.0/24 -o <uplink> -j MASQUERADE` / `COMMIT`;
  `sudo ufw route allow in on <usb interface> out on <uplink>`; `sudo ufw reload`.
  - Use the interface's real name (here `enp34s0f3u1u3u2`), not its altname (`enx…`, from the
    phone's fixed USB MAC): iptables matches real names only, a rule with the altname silently never
    matches. The real name depends on the USB port.
  - ufw forwards ICMP by itself (before.rules): a working ping proves nothing about the route rule;
    test TCP (`nc -zv <ip> 443`).
- **Phone (runtime, lost on reboot):** `ip route replace default via 172.16.42.2 dev usb0 metric 100`
  (below Wi-Fi's 600, which stays as fallback). Here the path behind the host takes at most 1480-byte
  packets (`ping -s 1452` passes, 1472 doesn't) and no "fragmentation needed" comes back through the
  NAT, so also `mtu 1480 advmss 1440` on that route.
- **IPv6 goes around it:** NetworkManager gives wlan0 an IPv6 default route, and musl (which ignores
  `/etc/gai.conf`) prefers IPv6: hosts with an AAAA record (GitHub has none, many mirrors do) are
  reached over Wi-Fi. `sysctl net.ipv6.conf.wlan0.disable_ipv6=1` while installing.
- **Mirror:** the mirror matters as much as the link. The Alpine CDN gave the host 420 KiB/s to
  5.5 MB/s (cold/warm cache), RWTH Aachen 13 MB/s; the phone's Alpine repositories point there
  (`/etc/apk/repositories`, the original kept as `.orig`). Measuring with BusyBox: `date` has no
  nanoseconds, use `/proc/uptime`; throughput of an interface from `/proc/net/dev` over a few
  seconds (no iftop needed).
- **Without root on the host:** `tools/s3ve3g-debug/http-proxy.py` listening on 172.16.42.2 and
  `http_proxy=` for apk (passed through `sudo env`, `sudo -E` drops it); `ssh -R` doesn't work, the
  phone's sshd has `AllowTcpForwarding no`. The host's firewall must allow the port from the USB
  interface.
- Package repository of nura-builds for armv7 (zynthian, our Qt 6.12/PySide6 6.12): key
  `keys/nura-builds-ci.rsa.pub` into `/etc/apk/keys/`, `https://github.com/hjanetzek/nura-builds/releases/download`
  into `/etc/apk/repositories`. apk keeps an installed Alpine Qt 6.11 unless the Qt packages are
  named with `apk add -u`.

## Kernel updates over SSH

Once the device runs (USB networking), new builds go to it without heimdall or a new rootfs:
`tools/s3ve3g-deploy.sh` copies the packages to the device as a local repository, installs those
files with apk (a rebuild with the same version too; apk's `fix` would want the installed build's
checksum; kernel and modules stay in step), and the
device's mkinitfs/boot-deploy writes `/boot/boot.img`; the script checks it (Android header, QCDT,
size against the partition), saves the current BOOT contents first (`out/s3ve3g/boot-*.img` here,
for `heimdall flash --BOOT` if the new kernel doesn't boot; `/boot/boot-partition.prev.img` on the
device), writes it to the `boot` partition, verifies it and reboots (`-n`: no reboot). An unchanged
boot image isn't written. (boot-deploy's own `deviceinfo_flash_kernel_on_update` looks for the GPT
label `BOOT`, heimdall's name for it; the GPT label is `boot`.)

```sh
pmbootstrap -c $C build --force linux-postmarketos-qcom-msm8226
KNOWN_HOSTS=... tools/s3ve3g-deploy.sh            # default packages: kernel, device, device-openrc
```

Without sudo here: `tools/s3ve3g-builder.sh` runs pmbootstrap in a QEMU VM (zynthian-ui's
zynthian-ui's `tools/run_qemu.sh` and `qemu_setup.sh`, see the script's header: own directory, SSH port 2240,
headless), with its own work dir and pmaports there, the overlays synced into it; sources already
downloaded here are copied over (GitHub rate-limits tarball downloads from the VM):

```sh
tools/s3ve3g-builder.sh setup                       # once
tools/s3ve3g-builder.sh build                       # kernel and device package (--force)
tools/s3ve3g-builder.sh fetch                       # to out/s3ve3g/packages/armv7
KNOWN_HOSTS=... tools/s3ve3g-builder.sh key         # once: the phone trusts the VM's signing key
REPO=out/s3ve3g/packages/armv7 KNOWN_HOSTS=... tools/s3ve3g-deploy.sh
```

## Flashing

Download mode: Volume Down + Home + Power, then Volume Up to confirm. heimdall on the PC
(`heimdall print-pit --no-reboot` lists the partition names).

From an SD card first (leaves Android on the eMMC): the rootfs on the card, the boot image to
BOOT; the initramfs finds the root partition by its label on any disk. With pmbootstrap as above;
with image files:

```sh
zstd -d s3ve3g-samsung-s3ve3g.img.zst s3ve3g-samsung-s3ve3g-boot.img.zst
sudo dd if=s3ve3g-samsung-s3ve3g.img of=/dev/sdX bs=4M status=progress   # the SD card
heimdall flash --BOOT s3ve3g-samsung-s3ve3g-boot.img
```

To the eMMC: `heimdall flash --BOOT s3ve3g-samsung-s3ve3g-boot.img --USERDATA
s3ve3g-samsung-s3ve3g.img` (the raw image: slow). Back to Android: the stock firmware's boot image
with heimdall (or Odin).

## Debugging

- The kernel log from the first moments (kernel r108, device package r5): `earlycon=ramcon,0x1fb00000`,
  our early console (patch 0002) writing the last 4 KB of the log into the same buffer in the same
  format, from `setup_arch` on (ramoops only starts at `device_initcall`: with r107 the buffer still
  held a downstream log, so our kernel dies before that). The bootloader appends `loglevel=4`,
  which hides most messages from every console, ramoops and ramcon included: for a full log put
  `ignore_loglevel` back into `CONFIG_CMDLINE` (it was there for the bring-up; without it the
  boot is about 7 s faster: each line printed costs about 45 ms on the serial and framebuffer
  consoles). Read with the repacked TWRP
  (`/proc/last_kmsg`). Our `__log_buf` (0x0173d7f4) doesn't survive: TWRP's kernel data covers it.
- The kernel log across resets (ramoops, kernel r107): the console goes to downstream's
  `ram_console` buffer (1 MB at 0x1FB00000, `RAMCONSOLE_PHYS_ADDR` in the downstream
  `board-8226.c`), which the bootloader keeps. After a crash or reset, boot a downstream kernel
  (TWRP in RECOVERY: Volume Up + Home + Power) and read it, the same header as Android's
  persistent RAM: `adb shell cat /proc/last_kmsg`, or raw:
  `adb shell 'dd if=/dev/mem bs=1048576 skip=507 count=1' > ramoops.bin` (507 MB = 0x1FB00000;
  the log starts after a 12-byte header, `DBGC`), `strings ramoops.bin`. On the next boot of our
  kernel the old log is in `/sys/fs/pstore/console-ramoops-0`.
  The official TWRP (3.3.1-1-s3ve3g, https://twrp.me/samsung/samsunggalaxys3neo.html) has neither:
  its prebuilt 3.4 kernel lacks the ram_console and /dev/mem. Hence a repacked TWRP: CI's
  `recovery` stage builds pmaports' archived downstream kernel (`linux-samsung-s3ve3g`, overlay
  with `CONFIG_DEVMEM=y`; artifact `apks-s3ve3g-recovery`), and
  `tools/s3ve3g-twrp-repack.py twrp-3.3.1-1-s3ve3g.img linux-samsung-s3ve3g-*.apk twrp-ramconsole.img`
  puts its kernel and dt.img into TWRP (ramdisk and command line kept); `heimdall flash
  --RECOVERY twrp-ramconsole.img`. After a reset (no battery pull): Volume Up + Home + Power,
  `adb shell cat /proc/last_kmsg`.
- The bootloader's command line (seen in TWRP): `console=null`, `uart_dbg=0` (the UART is off for
  debug output), `sec_log=0x100000@0x3fe00008`, `sec_dbg=0x80000@0x3ff00008` (Samsung's own log
  buffers), `mdss_mdp.panel=1:dsi:0:mdss_dsi_samsung_720p_video_s6e8aa0a` (the bootloader sets up
  the panel), `samsung.board_rev=4`, `androidboot.bootloader=I9301IXXUAQL1`. RAM as the downstream
  kernel gets it (`/proc/iomem`): 0-0x083fffff, 0x0c400000-0x0cafffff, 0x0f600000-0x0f9fffff,
  0x0ff00000-0x0fffffff, 0x10600000-0x5f2fffff.

- USB networking (the initramfs and the system): 172.16.42.1, `ssh user@172.16.42.1`, if the
  SM5502 detects the PC (else the USB controller stays without a role).
- Serial console: `blsp1_uart3` at 115200 (`console=ttyMSM0`). Samsung routes it to the micro-USB
  port through the MUIC with a 619 kΩ resistor between ID and ground (a "JIG UART" cable: D+/D- as
  RX/TX), so soldering may not be needed; check the voltage level of the adapter.
- Without display output: the framebuffer format may be another (`r8g8b8` vs. `a8r8g8b8`), or the
  bootloader leaves the panel off; then the panel driver (DSI, S6E8AA0A) is next.
