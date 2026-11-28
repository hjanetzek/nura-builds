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

## Open, to check against Hardkernel's N2 schematic before wiring

- The 7-pin header J7 (unpopulated): which pin carries MCLK (GPIOA_0), SCLK (A_1), FS (A_2) and
  lane 0 (A_3); the notes say pins 4/6/5/7.
- That the 40-pin header's pin 26 is GPIOA_4, and pins 3/5 are I2C2 (GPIOX_17/18).
- The I/O voltage of the GPIOA bank (the notes say VDD_AO, which is the AO bank's supply) and
  whether the CS42448's serial port (VL) matches it.
- The CS42448's TDM requirements: in TDM mode it needs SCLK = 256 Fs; MCLK/LRCK ratio and the
  slot format (DSP_A / left-justified with a one-SCLK FS pulse) from its datasheet.

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
		mclk-fs = <256>;
		codec-0 { sound-dai = <&cs42448>; };
		/delete-node/ codec-1;
	};
};
```

## Bring-up steps

0. Internal loopback, no wiring, no dtb change: play on the TDM-B frontend, record through
   `TDMIN_LB` (`TDMIN_LB SRC SEL`, a `TODDR_x` to `IN 6`). Checks the capture path and the
   formats.
1. Pins on TDM-B (dtb change only): `aplay` on the HDMI/line-out frontend; scope or logic
   analyzer on J7: MCLK 12.288 MHz, SCLK 3.072 MHz, FS 48 kHz, data on lane 0.
2. Digital loopback (dtb change only): with the N2 off, a jumper from lane 0 (GPIOA_3, J7) to
   lane 1 (GPIOA_4, header pin 26); record on the TDM-B capture frontend while playing a sine,
   and compare the recording with the source (bit-exact, no slips). nura-builds' audio checks
   (numpy, as for the S3's loopback) do the comparison.
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
