# ODROID N2: a CS42448 codec over TDM (plan)

Status: plan, nothing built yet (2026-11-28). Goal: 8 analog outputs and 6 analog inputs on the
ODROID N2 (S922X, Amlogic G12B) through a Cirrus Logic CS42448 on TDM-B, for zynthian and
MicroDexed-touch. Starting point: the brainstorming notes in zynthian-stuff
(`odroid-n2/audio-hw-cd42448.md`); their device tree is written for Hardkernel's vendor kernel
(4.9) and doesn't apply to ours. This document is the mainline version.

Our N2 runs `linux-postmarketos-amlogic-rt` 7.2.14 (aports/kernel; PREEMPT_RT, 1000 Hz, the ALSA
sequencer since r1), the dtb `amlogic/meson-g12b-odroid-n2` (devices/device-odroid-n2), booted by
U-Boot through postmarketOS' generated `/boot/extlinux/extlinux.conf`.

## What is checked (on the running N2, 2026-11-28)

- Pin groups (pinctrl debugfs, `ff634400.bus:pinctrl@40`), all currently unclaimed:
  `mclk0_a` GPIOA_0, `tdm_b_sclk` GPIOA_1, `tdm_b_fs` GPIOA_2, `tdm_b_dout0` and `tdm_b_din0`
  both GPIOA_3, `tdm_b_din1` GPIOA_4, `i2c2_sda_x` GPIOX_17, `i2c2_sck_x` GPIOX_18.
  So full duplex needs two lanes: playback on lane 0 (GPIOA_3), capture on lane 1 (GPIOA_4).
- The TDM drivers are there as modules: `SND_MESON_AXG_TDM_INTERFACE`, `_TDMIN`, `_TDMOUT`,
  `_SOUND_CARD`, `SND_MESON_G12A_TOHDMITX`; `SND_SOC_SPDIF` (spdif-dit / -dir, usable as stand-in
  codecs).
- The codec driver is NOT built: mainline's CS42448 driver is `sound/soc/codecs/cs42xx8.c`
  (`CONFIG_SND_SOC_CS42XX8` + `CONFIG_SND_SOC_CS42XX8_I2C`, compatible `"cirrus,cs42448"`);
  `CS42XX8_I2C` is off in our config.
- The board's sound card (`amlogic,axg-sound-card`, "ODROID-N2") already uses TDM-B and TDM-C:
  dai-link-6 (TDM-B) and dai-link-7 (TDM-C), i2s, each to HDMI (`tohdmitx`) and the internal DAC
  (`toacodec`, then the U19 amplifier to the line out). The routing also has the internal
  loopbacks (`TDM_B Loopback` into `TDMIN_A/B/C` and `TDMIN_LB`).
- I2C: i2c3 (`i2c@1c000`) carries the RTC (pcf8563 at 0x51); i2c2 (`i2c@1d000`, the header's
  pins 3/5 on GPIOX_17/18) is disabled. The dtb has no `__symbols__`, so U-Boot can't apply
  overlays to it; `extlinux.conf` is rewritten on kernel upgrades.
- CPUs 0-1 are Cortex-A53, 2-5 Cortex-A73; `cpufreq.default_governor=performance` is set on the
  kernel command line (device-odroid-n2).

## Pinout and I/O voltage (measured with a scope, 2026-11-28)

The dts names gpiochip0's lines after the header pins (Hardkernel numbers the 7-pin header J7 as
pins 41-47, after the 40-pin header J2): line 49 GPIOA_0 "PIN_44", 50 GPIOA_1 "PIN_46",
51 GPIOA_2 "PIN_45", 52 GPIOA_3 "PIN_47", 53 GPIOA_4 "PIN_26", 82 GPIOX_17 "PIN_3",
83 GPIOX_18 "PIN_5". Checked on the board (J7 header soldered on): each line toggled as a GPIO at
its own rate (libgpiod's gpioset as transient systemd units; started from an SSH session they die
at its logout), probed against J2 pin 14 (GND):

| Pin | Measured | GPIO | TDM-B function |
|---|---|---|---|
| J7 pin 4 | 470 Hz (500 set) | GPIOA_0 | MCLK (`mclk0_a`) |
| J7 pin 6 | 242 Hz (250) | GPIOA_1 | SCLK (`tdm_b_sclk`) |
| J7 pin 5 | 123 Hz (125) | GPIOA_2 | FS (`tdm_b_fs`) |
| J7 pin 7 | 62 Hz (62.5) | GPIOA_3 | lane 0 out (`tdm_b_dout0`) |
| J2 pin 26 | 31 Hz (31) | GPIOA_4 | lane 1 in (`tdm_b_din1`) |

High level 3.3 V on all of them: the GPIOA bank runs at 3.3 V, so the CS42448's serial port
supply (VL) is 3.3 V, without level shifters. (A probe whose ground had no contact showed 50 Hz
mains hum of several volts on every pin, with negative excursions: a GPIO can't go below 0 V.)

## Open

- The CS42448's TDM requirements: in TDM mode it needs SCLK = 256 Fs; MCLK/LRCK ratio and the
  slot format (DSP_A / left-justified with a one-SCLK FS pulse) from its datasheet.
- J2 pins 3/5 as I2C2 (GPIOX_17/18): from the dts line names, not yet probed.

## HDMI audio: off

The user never uses HDMI audio (2026-11-28): the mixer switch `TOHDMITX` is off on the N2 and
stored in `/var/lib/alsa/asound.state` (restored at boot by alsa-restore.service). The dts patch
for the codec (step 3) drops the `tohdmitx` codecs from dai-link-6/7 as well, which leaves TDM-B
to the header and the CS42448, and TDM-C to the internal DAC (line out).

## The TDM-B question

TDM-B is the interface on the header pins, and the board's card already drives it for HDMI and
the line out (dai-link-6, 2 slots i2s). Putting it on the pins means its frame goes out there too.

- For the bring-up (steps 1-2 below) that is fine and even useful: the pins carry the existing
  2-slot i2s stream (SCLK 3.072 MHz at 48 kHz, 2 x 32 bits).
- For the CS42448 (8 slots x 32 bits, SCLK = MCLK = 12.288 MHz) dai-link-6 becomes the codec's
  link alone, and HDMI/line out stay on TDM-C (dai-link-7), which feeds both already.

## Device tree (mainline syntax, a sketch to verify)

Pinctrl node names are those of `meson-g12-common.dtsi` (check them there); phandles as in
`meson-g12b-odroid-n2.dtsi`.

Step 1-2, the pins on TDM-B (the existing link unchanged):

```dts
&tdmif_b {
	pinctrl-0 = <&mclk0_a_pins>, <&tdm_b_sclk_pins>, <&tdm_b_fs_pins>,
		    <&tdm_b_dout0_pins>, <&tdm_b_din1_pins>;
	pinctrl-names = "default";
	assigned-clocks = <&clkc_audio AUD_CLKID_TDM_SCLK_PAD1>,
			  <&clkc_audio AUD_CLKID_TDM_LRCLK_PAD1>;
	assigned-clock-parents = <&clkc_audio AUD_CLKID_MST_B_SCLK>,
				 <&clkc_audio AUD_CLKID_MST_B_LRCLK>;
	assigned-clock-rates = <0>, <0>;
};
```

(The pad clock assignment follows other G12 boards with an external DAC, e.g. the SEI510's TDM
DAC links; which pad index belongs to TDM-B on G12 needs checking.)

Capture on lane 1 needs a capture-capable codec on dai-link-6 (tohdmitx and toacodec are
playback only): for the bring-up `linux,spdif-dir` as a stand-in codec, with the lane masks on
the link:

```dts
/ {
	spdif_in_dummy: audio-codec-dummy {
		compatible = "linux,spdif-dir";
		#sound-dai-cells = <0>;
	};
};

&sound {
	dai-link-6 {
		dai-tdm-slot-tx-mask-0 = <1 1>;
		dai-tdm-slot-rx-mask-1 = <1 1>;	/* lane 1 = GPIOA_4 */
		codec-2 {
			sound-dai = <&spdif_in_dummy>;
		};
	};
};
```

CS42448 (step 4): i2c2 on the header pins, the codec, and dai-link-6 as its own link:

```dts
&i2c2 {
	status = "okay";
	pinctrl-0 = <&i2c2_sda_x_pins>, <&i2c2_sck_x_pins>;
	pinctrl-names = "default";

	cs42448: audio-codec@48 {
		compatible = "cirrus,cs42448";
		reg = <0x48>;
		#sound-dai-cells = <0>;
		clocks = <&clkc_audio AUD_CLKID_MST_B_MCLK>;	/* MCLK pad: check */
		clock-names = "mclk";
		/* supplies (VA, VD, VLS, VLC) per the board */
	};
};

&sound {
	dai-link-6 {
		dai-format = "dsp_a";		/* per the CS42448's TDM format */
		dai-tdm-slot-tx-mask-0 = <1 1 1 1 1 1 1 1>;
		dai-tdm-slot-rx-mask-1 = <1 1 1 1 1 1 0 0>;
		dai-tdm-slot-num = <8>;
		dai-tdm-slot-width = <32>;
		mclk-fs = <512>;	/* SCLK = MCLK / 2 at least (step 2b) */
		codec-0 { sound-dai = <&cs42448>; };
		/delete-node/ codec-1;
	};
};
```

## Bring-up steps

0. Internal loopback, no wiring, no dtb change: play on the TDM-B frontend, record through
   `TDMIN_LB` (`TDMIN_LB SRC SEL`, a `TODDR_x` to `IN 6`). Checks the capture path and the
   formats.
   Done 2026-11-28, bit-exact: mixer `FRDDR_A SRC 1 EN` on, `FRDDR_A SINK 1 SEL` = OUT 1,
   `TDMOUT_B SRC SEL` = IN 0 (playback frontend device 0 to TDM-B), `TDMIN_LB SRC SEL` = IN 1
   (TDM_B Loopback), `TODDR_A SRC SEL` = IN 6 (capture frontend device 3). A generated S32_LE
   stereo file (1 kHz left, 1.5 kHz right, a ramp marker) played with `aplay -D hw:ODROIDN2,0`
   while `arecord -D hw:ODROIDN2,3 -f S32_LE -c2 -r48000` ran: after aligning on the marker,
   143989 of 144000 frames identical in both channels (the last 11 are the stream's stop), no
   channel swap or slot shift.
1. Pins on TDM-B (dtb change only): `aplay` on the HDMI/line-out frontend; scope or logic
   analyzer on J7: MCLK 12.288 MHz, SCLK 3.072 MHz, FS 48 kHz, data on lane 0.
   Done 2026-11-28 with a dtb edited on the N2: `tools/odroid-n2/dtb-tdmb-pins.py` (on a dts
   decompiled from `/boot/meson-g12b-odroid-n2.dtb`) gives `&tdmif_b` the pins mclk0_a,
   tdm_b_sclk, tdm_b_fs, tdm_b_dout0, tdm_b_din1 (new phandles for their pinctrl nodes) and the
   U200's pad clocks (MCLK_PAD0 <- MST_B_MCLK, SCLK_PAD1 <- MST_B_SCLK, LRCLK_PAD1 <-
   MST_B_LRCLK); installed as `/boot/meson-g12b-odroid-n2-tdmb.dtb` next to the original, with
   `fdt` in `/boot/extlinux/extlinux.conf` pointing to it (backup `extlinux.conf.orig`; pmOS
   rewrites extlinux.conf on kernel upgrades, which switches back to the original dtb). After the
   boot the pinctrl debugfs shows GPIOA_0..4 claimed by audio-controller-1 with those functions.
   With `speaker-test -D hw:ODROIDN2,0 -F S32_LE -r 48000` (i2s, mclk-fs 256, 2 x 32-bit slots)
   the scope showed MCLK 12.29 MHz (J7-4), SCLK 3.07 MHz (J7-6), FS 48 kHz (J7-5) and data
   bursts on DOUT0 (J7-7).
2. Digital loopback (dtb change only): with the N2 off, a jumper from lane 0 (GPIOA_3, J7) to
   lane 1 (GPIOA_4, header pin 26); record on the TDM-B capture frontend while playing a sine,
   and compare the recording with the source (bit-exact, no slips). nura-builds' audio checks
   (numpy, as for the S3's loopback) do the comparison.
   Done 2026-11-28, bit-exact. `tools/odroid-n2/dtb-tdmb-capture.py` (on step 1's dts) gives
   dai-link-6 a capture-capable stand-in codec (a `linux,spdif-dir` node; snd-soc-spdif-rx loads
   for it), `dai-tdm-slot-rx-mask-1 = <1 1>` and the card the route `"TDMIN_B IN 1", "TDM_B
   Capture"` (the N2's routing had only the loopback inputs; the U200's has it); installed as
   `/boot/meson-g12b-odroid-n2-tdmb2.dtb` (extlinux.conf's fdt). Mixer: `TDMIN_B SRC SEL` = IN 1,
   `TODDR_A SRC SEL` = IN 1 (capture frontend device 3), playback as in step 0. Jumper J7 pin 7
   to J2 pin 26; the same S32_LE test file as step 0: left to left 143990 of 144000 frames
   identical, right to right 143989 (the rest is the stream's stop), the cross comparisons
   differ throughout (no channel swap, no slot shift).
2b. 8 slots in each direction, as the CS42448 will run: done 2026-11-28, stable and bit-exact.
   `tools/odroid-n2/dtb-tdmb-8ch.py` (on step 2's dts) makes dai-link-6 `dsp_a`, 8 x 32-bit slots,
   tx on lane 0, rx on lane 1, `mclk-fs = <512>`, with stand-in codecs only (linux,spdif-dit for
   playback, the spdif-dir for capture; the internal DAC and HDMI take only a 2-slot frame, so the
   line out stays on TDM-C); `/boot/meson-g12b-odroid-n2-tdmb8.dtb`. Both frontends then offer 1-8
   channels.
   MCLK must be 512 Fs: the TDM block's SCLK divider is at least 2. With mclk-fs 256 (MCLK
   12.288 MHz) SCLK reached only 6.144 MHz (a 128-bit frame) and an 8 x 32-bit stream hung (aplay:
   "write error: I/O error", the clock summary showed aud_mst_b_sclk 6143951). With 512: MCLK
   24.576 MHz, SCLK 12.288 MHz, LRCLK 48 kHz. The CS42448 takes MCLK = 512 Fs in single-speed
   mode, so the codec's link uses mclk-fs 512 as well (the sketch above says 256: corrected here).
   Loopback over the jumper (J7 pin 7 to J2 pin 26) at SCLK 12.288 MHz, S32_LE, every channel its
   own sine and a marker: 60 s, all 8 channels bit-exact (each in its own slot); 600 s with
   `tools/odroid-n2/tdm8-loopback.py 600` (the source generated block by block into aplay's stdin,
   arecord into /tmp with a 2 s buffer, compared block by block): 28,800,000 frames x 8 channels,
   0 differing samples, no xruns. (A first 600 s run that wrote the 920 MB source and the capture
   to the SD card lost data in two arecord overruns of 837 and 145 ms, SD write stalls; bit-exact
   up to them.)
3. Kernel: `CONFIG_SND_SOC_CS42XX8_I2C=m` (and `CS42XX8`) in linux-postmarketos-amlogic-rt's
   prepare(), and the dts change as a patch in that recipe (durable; a dtb edited on the device
   is lost at the next kernel upgrade, because pmOS copies the package's dtb and rewrites
   extlinux.conf).
4. The CS42448: probe over I2C (i2cdetect on i2c2, the driver binding), the 8-slot link, playback
   per channel, capture per channel, then latency (period sizes; whether the axg FIFOs take 64-128
   frames is untested).

Steps 1-2 can run with a dtb edited on the N2 (dtc there, booted under its own name) or with a
patch in the kernel recipe; step 3 needs the kernel rebuild.

## Real time

PREEMPT_RT and the performance governor are in place. Audio threads on the A73 cores (2-5),
memlock and rtprio for the audio group (`/etc/security/limits.d/95-audio-rt.conf` on the N2).
