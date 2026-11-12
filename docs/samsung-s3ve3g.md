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

Boot time (2026-11-12): 1:16 at first, 43 s now (kernel and initramfs 17 s, userspace 26 s):
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

Missing: battery and charging (no mainline driver for the PM8226 charger and fuel gauge), sound,
a panel driver (S6E8AA0A: brightness, blanking), cpufreq above 787 MHz (CPR, speed bins), SD card
(the controller probes, untested with a card), vibrator, LED, light/proximity sensor, NFC, modem.

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
`nura/tools/run_qemu.sh` and `qemu_setup.sh`, see the script's header: own directory, SSH port 2240,
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
  held a downstream log, so our kernel dies before that). `ignore_loglevel`: the bootloader appends
  `loglevel=4`, which hides most messages from every console. Read with the repacked TWRP
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
