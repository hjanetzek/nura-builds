# Samsung Galaxy S III Neo (s3ve3g): bringing downstream behaviour to our mainline branch

What worked (and what didn't) while getting the display, GPU, DPMS and brightness of the S III Neo
running on the msm8226-mainline kernel, written for whoever picks up the next subsystem (audio,
battery, Wi-Fi stability, upstreaming). Device facts: `samsung-s3ve3g.md`; display and GPU details:
`samsung-s3ve3g-gpu.md`; audio research: `samsung-s3ve3g-audio.md`.

## The ground rules of this branch

- Branch `galaxy-s3-neo` of nura-builds, **local commits only, no push** during bring-up.
- Kernel changes are patches in `overlays/s3ve3g/device/testing/linux-postmarketos-qcom-msm8226/`
  (applied on msm8226-mainline's tag `v6.16.12-msm8226-u2`). Each patch goes into `source=` and
  `sha512sums=` of its APKBUILD. No pkgrel bumps while iterating: the builder rebuilds with
  `--force`, the deploy compares files and the BOOT partition, not versions.
- Device package (`device-samsung-s3ve3g`): services, udev rules, sysctl, install scripts. A file
  removed from the package disappears from the phone on the next install of the same version.
- No sudo on the host. The phone: `jeff@172.16.42.1` (USB network), passwordless sudo. Use your own
  known_hosts file (`-o UserKnownHostsFile=...`), not `~/.ssh/known_hosts`.
- Debug aids stay on the device until the user says otherwise (early telnet, panic-on-oops, the
  panel driver's `skip_init`/`no_reset`, patch 0010's register trace, `/etc/init.d/kmscube`).

## The loop: edit → phone in about 5 minutes

1. A kernel tree to edit: clone msm8226-mainline (`--filter=blob:none`), check out the tag, apply
   the overlay's patches in order, leave them uncommitted. A new patch is `git diff` of the files it
   touches; if a file already carries an earlier patch, diff against a copy taken before your edit
   (`diff -u a/... b/...`), so each patch applies on top of the previous ones.
2. `tools/s3ve3g-builder.sh build linux-postmarketos-qcom-msm8226` (pmbootstrap in a QEMU VM, SSH
   port 2240, `~/.cache/nura-builds-builder`; never touch other VMs or ports), then `fetch`.
3. `REPO=out/s3ve3g/packages/armv7 KNOWN_HOSTS=... tools/s3ve3g-deploy.sh [-n] PACKAGE...`: installs
   the .apk files over SSH, writes and verifies BOOT, keeps the old BOOT in `out/s3ve3g/`.
4. `tools/s3ve3g-debug/iterate.sh` does 2-3, reboots with sysrq (a wedged display driver blocks a
   normal reboot), waits for SSH and prints the relevant dmesg lines. `regen-patch-0008.sh` shows
   how to regenerate a patch and its checksum from the tree.
5. Look at the screen with `tools/s3ve3g-screenshot.sh NAME` (the camera app's MJPEG stream; the
   snapshot endpoint can be stale) or the project skill `s3neo-screen`. The camera's auto exposure
   hides brightness changes: read the stream's frames around the change instead of single photos.

## Finding what downstream does differently

Mainline's driver usually has the right structure; bugs were in what downstream does implicitly.
Every display fix of this branch came from a register or code comparison, none from guessing
(earlier theories about FIFO bits, LDO mode, PHY timings, QoS and burst mode all cost hours).

- **Source:** LineageOS `android_kernel_samsung_msm8226` (raw files from GitHub: device tree
  `arch/arm/boot/dts/msm8226-*.dtsi`, drivers under `drivers/video/msm/mdss/`, `arch/arm/mach-msm/`,
  `drivers/iommu/msm_iommu*.c`). The DT's `qcom,...-settings` arrays are register writes downstream
  replays; they are lost whenever their block powers off.
- **Live registers of the downstream kernel:** boot TWRP (it runs the downstream kernel, Volume Up
  + Home + Power), copy a static ARM binary over adb and dump `/dev/mem`. busybox `devmem` fails
  above 2 GB there; `tools/s3ve3g-debug/physdump.c` (static, `mmap64`) prints 4 KB pages. Dump the
  same pages under mainline and diff. The byte clock mux (patch 0011) was found this way:
  `VREG_CFG` 0x02 downstream, 0x00 here.
- **Bootloader:** the LK `aboot` partition holds the panel command tables; they can be found by
  byte patterns (the DCS commands of the vendor dtsi). It also tells which state the hardware is in
  when the kernel takes over (the splash screen's clocks, the panel's power).
- **Write a value live before writing a patch:** poking the suspected register from SSH (`/dev/mem`
  read-modify-write) proves a theory in seconds; then put it in the driver.
- **Ask what downstream does after a power-on, not just at probe.** The MDSS power-collapse freeze
  (patch 0015) was TrustZone state: downstream calls `msm_iommu_sec_program_iommu(1)` (SCM
  MP/IOMMU_SECURE_CFG) after each power-on; mainline has the same call as
  `qcom_scm_restore_sec_cfg()`. Same pattern for the VBIF settings. Grep downstream for `scm_call`,
  `restore`, `_settings`, `footswitch` around the subsystem you port.
- **Split hypotheses with a cheap test build:** e.g. the GDSC forced always on (one line in mmcc)
  separated "power collapse loses state" from "clock problem" in one boot.

## Debugging on the phone

- **Live kernel log:** `ssh ... 'sudo cat /dev/kmsg' > log &` in a second session, then run the
  test. It shows the last lines before a freeze; add `drm.debug=0x...` or `pause_on_oops`.
  netconsole does not work (the USB gadget has no netpoll); ramoops kept nothing across a restart.
- `kernel.panic_on_oops = 1`, `kernel.panic = 10` (device package sysctl): an oops restarts the
  phone. Files written shortly before can come back as zeros: `sync` after copying tools to it.
- **Early telnet** on 172.16.42.1:23 (sysinit) for boots that hang before sshd.
- **`/dev/mem` on the MDSS (0xfd900000-0xfd92ffff) while the MDP is runtime-suspended is
  dangerous:** sometimes a bus error, sometimes a hang and a SoC reset. Read it only with the
  screen on, or resume the device first (`power/control = on`). `tools/s3ve3g-debug/peek.py` reads
  single words and flushes before each access (a SIGBUS otherwise eats buffered output).
- `/sys/kernel/debug/clk/clk_summary` oopses when a DSI PLL is unclocked (it reads the PLL's
  registers); read single clocks from `/sys/kernel/debug/clk/<name>/clk_enable_count` instead.
- Power domains: `/sys/kernel/debug/pm_genpd/pm_genpd_summary`; runtime PM of a device:
  `/sys/bus/platform/devices/<dev>/power/{runtime_status,control}`.
- **Pitfalls that looked like driver bugs:** kmscube quits when stdin becomes readable (run it
  from `sleep N | kmscube` or the OpenRC service); `pkill -f` matched our own ssh shell;
  `/etc/issue`'s `ESC[9;5]` silently re-enabled console blanking.

## Recovering a stuck phone

Volume Down + Power for 10 s restarts it. Download mode (Volume Down + Home + Power) and
`heimdall flash --BOOT out/s3ve3g/boot-<time>.img` restore a saved BOOT. TWRP: Volume Up + Home +
Power. Freezes need the user at the device: plan risky tests (power collapse, unclocked register
access) for when they are there, and say before which step the phone may stop answering.

## Working in parallel (audio and display)

One phone, one builder VM: two agents must not deploy, reboot or flash at the same time. A second
agent (e.g. for the WCD9306 audio codec) can work offline for a long time (driver port, DT, build
in its own builder directory and port if needed) and should ask before using the phone. Kernel
patches of both go into the same overlay: number them in order and regenerate checksums; rebase
on each other's patches before deploying.

## What the audio bring-up added (2026-11-13/14)

- **Look where the firmware really is:** the ADSP image is in the modem partition on this phone,
  not apnhlos. Mount every firmware partition and `ls` before concluding a blob is missing.
- **Port a downstream driver whole, then cut:** for the WCD9306 the downstream file was run
  through the kernel's own `scripts/unifdef` with the board's config (`-DCONFIG_SAMSUNG_JACK`
  and so on), split into top-level chunks by a small script, the unneeded ones (MBHC, ANC, I2S,
  SSR) dropped, the API converted by regular expressions (`snd_soc_codec` -> component), and the
  downstream internals it still called provided by a small compatibility layer under the same
  names. The hardware sequences stay exactly as downstream wrote them, and the code can be
  compared line by line. A mainline-style template (here the Xperia Z2 project's WCD9320) is
  for the parts that are mainline-specific (SLIMbus streams, regmap, probe).
- **Fast module iteration:** a full local build with the phone's exact config (BTF on,
  `LOCALVERSION=`) makes modules that load on the phone; a codec change is then a copy and a
  reload instead of a 15-minute VM build. Unbind the card's machine driver first. Build through
  normal targets, never `M=` with `O=` (it writes into the source tree).
- **Mainline helpers can be broken:** `devm_regmap_init_slimbus()` passes a stale stack address
  as the bus context. When a well-trodden path fails with a strange errno, read the helper.
- **Measure audio instead of asking:** the headphone out into an audio interface on the host
  (`pw-record`, numpy for RMS and frequency) answers "does it play, which channel, distorted?"
  without anyone listening; the microphone by acoustic loopback from the speaker.
- **The screen:** something can switch it on while you work (a key press, a service restart).
  Check `bl_power` after every step that touches the system, not only after boot.
