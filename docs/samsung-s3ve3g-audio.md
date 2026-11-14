# Samsung Galaxy S III Neo (s3ve3g): audio on mainline

Status (2026-11-14): **speaker, headphones and the main microphone work**, with jack detection,
an ALSA UCM profile and JACK. Branch `s3ve3g-audio` of nura-builds (worktree
`../nura-builds-audio`), kernel patches 0016-0018, device package files `ucm-*.conf`,
`s3ve3g-audio*`. Not done: the second microphone, the headset microphone and its buttons
(3/4-pole detection), the earpiece, calls.

| Part | State | Notes |
|---|---|---|
| ADSP (LPASS Q6) | works | firmware from the **modem** partition (`modem:/image/adsp.*`, not apnhlos), loaded at 0x0d900000 (relocatable) |
| APR, q6core/afe/asm/adm | work | mainline QDSP6 on the old APR v2 firmware |
| SLIMbus (NGD, BAM) | works | `qcom,slim-ngd-v1.5.0`, the ADSP is the bus manager |
| WCD9306 codec | works | enumerates as `slim217,e0`, chip id `01 00 03 01`, version 1 (Tapan 2.0), QFUSE: WCD9306 |
| Speaker (class D, RX4) | works | by ear |
| Headphones (HPHL/HPHR, class H) | works | 440 Hz at -15 to -20 dBFS on a Scarlett, >50 dB channel separation |
| Main microphone (AMIC1) | works | the speaker recorded at -15 dBFS, repeated captures identical |
| Jack detection | works | TLMM 69, ALSA control "Headphone Jack"; the output follows it |
| Second microphone (AMIC3/AMIC4) | open | powered and biased, picks up almost nothing from the speaker |
| Headset mic, buttons | open | needs MIC BIAS2 while detecting and the PM8226 VADC (MPP8) |
| Earpiece (EAR PA) | untested | in the driver (DAC1, EAR PA) |
| 24 bit streams | 16 bit only | the firmware rejects 24 bit back ends and plays 24 bit front ends distorted |

## Using it

- Output: `sudo s3ve3g-audio speaker|headphones`, `s3ve3g-audio` shows the current one. The
  OpenRC service `s3ve3g-audio` (`s3ve3g-audio follow`, supervised) switches to the headphones
  when a plug goes in and to the speaker when it comes out.
- Without an audio server: play on `plughw:CARD=Neo` (any rate and format) or
  `hw:CARD=Neo,0` (48 kHz stereo, 16 bit). The ALSA `default` device points to PipeWire
  (`99-pipewire-default.conf`), which doesn't run on the headless image.
- Capture: `hw:CARD=Neo,1` (MultiMedia2; MultiMedia1 can't play and record at once), UCM device
  `Mic`; the ADSP gives the mono mic on both channels.
- UCM: `/usr/share/alsa/ucm2/conf.d/apq8096/Samsung Galaxy S III Neo.conf`, verb `HiFi`, devices
  `Speaker`, `Headphones` (JackControl "Headphone Jack" for PipeWire), `Mic`. `alsaucm` forgets
  its state between runs: `s3ve3g-audio` enables and disables the other device first.
- JACK: `JACK_NO_AUDIO_RESERVATION=1 jackd -R -P 70 -d alsa -d hw:CARD=Neo,0 -r48000 -p256 -n2`
  runs realtime as a user in the audio group (`/etc/security/limits.d/95-s3ve3g-audio-rt.conf`:
  rtprio 95, memlock unlimited). jackd's driver options take optional arguments: `-r 48000` (with a
  space) arrives as 0, write `-r48000` or `--rate=48000`. `alsa-plugins-jack` for `aplay -D jack`.

## The kernel side (patches 0016-0018)

- **0016, device tree:** `&adsp` with the APR services (q6asm DAIs 0-2), the SLIMbus BAM
  (0xfe104000) and NGD (0xfe12f000), under `ngd@1` the interface device and the codec
  (`slim217,e0`, `<0 0>` and `<1 0>`): reset TLMM 72 (active low), supplies S4/L25 (charge pump,
  switched by the driver) and L6/L6/L4 (on from probe), MCLK, `hp-det-gpios` (TLMM 69, pull-up),
  `qcom,micbias1-ext-cap`. The sound card (`qcom,msm8226-sndcard`): MultiMedia1/2 front ends,
  SLIMbus playback (codec DAI 0) and capture (DAI 1), mic bias routing as downstream.
- **MCLK:** 9.6 MHz from the RPM's `div_clk1` (`RPM_SMD_DIV_CLK1`, downstream "osr_clk") on PM8226
  GPIO1 function 1 (pinctrl `cdc-mclk-default-state`). Unlike MSM8974 (where the Xperia Z2
  project needed the PMIC's own divider), this works on MSM8226: the headphones play.
- **0017, the WCD9306 driver** (`sound/soc/codecs/wcd9306*.{c,h}`): downstream `wcd9306.c` as
  Samsung built it (`CONFIG_SAMSUNG_JACK`: no MBHC), unifdef'd, converted to the component API
  with its function and register names kept (`TAPAN_A_*`, `WCD9XXX_A_*`; the regmap adds the
  SLIMbus offset 0x800 through `reg_base`). The downstream resource manager is reduced to
  bandgap, clock block (MCLK/RCO), RX bias and micbias filters (no MBHC notifiers);
  `wcd9306-clsh.c` is downstream's class H state machine. SLIMbus streams (hw_params, trigger,
  channel maps) follow mainline's wcd9335 and the Z2 project's WCD9320 port, with its fixes
  (per-port mux state, unchanged writes ignored, stream torn down on stop). An `MCLK` supply
  widget switches the clock (reference counted). Left out: MBHC/impedance, ANC, I2S, WCD9302
  tables, SSR, the IIR coefficient controls.
- **0018, machine driver:** mainline's APQ8096 driver (DT links, SLIMbus channels 144+ for RX
  and 128+ for TX, as downstream `msm8226.c`), the back end fixed at 16 bit (as sdm845.c), and
  with `qcom,msm8226-sndcard` 16 bit front ends.

### Bugs found on the way

- **`devm_regmap_init_slimbus()` is broken in mainline:** `__devm_regmap_init_slimbus()` passes
  `&slimbus` (the address of its local pointer) as the bus context. Every access then goes through
  a stale stack address: -EINVAL at boot, an oops in `slim_do_transfer()` in other timing.
  wcd9335 uses the non-devm variant; so does this driver. Worth a patch upstream.
- **A rebind needs new SLIMbus logical addresses:** the probe resets the codec, but the core keeps
  `is_laddr_valid` and its status "up" (no status callback, messages to the old address time
  out). The driver reports the codec and the interface device absent before the reset
  (`slim_report_absent()`, exported but only declared in the core's private header).
- **24 bit:** the ADSP refuses a 24 bit SLIMbus AFE port (`AFE_PORT_CMD_DEVICE_START` error 1)
  and plays 24 bit front end streams distorted and ~20 dB down.
- **A card rebind** re-probes the component: its mux state has to be reset with the channel lists.

### Microphones

ADC-to-decimator pairing matters (each ADC only through certain decimators, silently otherwise):
ADC1 (main mic) works through DEC1. ADC3 and ADC4 (with MIC BIAS1/MIC BIAS2 External, the
downstream routing) power up but record the speaker only at -50 to -60 dBFS, mostly its second
harmonic. ADC2 is the headset mic (a TRS cable grounds its contact). To try with someone talking
into the top of the phone.

## Testing without ears

The headphone out on a Focusrite Scarlett (inputs 1 and 2; the phone's left channel arrives on
input 2): `pw-record` both inputs while the phone plays, RMS and dominant frequency per channel
(the scripts were `rec-test.sh` and `wavstat.py` in the session's scratch directory). The main
mic by acoustic loopback: a tone on the speaker, recorded through `hw:CARD=Neo,1`. DAPM state:
`/sys/kernel/debug/asoc/Samsung Galaxy S III Neo/217:e0:1:0/dapm/`; registers:
`/sys/kernel/debug/regmap/217:e0:1:0/registers` (cache for non-volatile ones; DAPM keeps a path
up for 5 s after a stream, so wait before taking an idle snapshot).

A codec module built on the host loads on the phone when the local build matches the phone's
config exactly (BTF on, `LOCALVERSION=` empty, the same patches): `module_layout` otherwise.
Host libbpf needs `HOSTCFLAGS=-Wno-error=incompatible-pointer-types-discards-qualifiers` with
clang 23. Build modules through the normal targets, not `M=` (that writes into the source tree).

# Research notes (2026-11-12)

The notes below are from before the bring-up; where they differ from the above, the above holds.

## Hardware (downstream device tree and drivers)

Codec: WCD9306 Tapan on SLIMbus, `qcom,tapan-slim-pgd` (`msm8226.dtsi`).

- SLIMbus addresses: codec `[00 01 E0 00 17 02]`, interface device `[00 00 E0 00 17 02]`:
  manufacturer 0x217, product 0xE0; in mainline notation `slim217,e0` at `<1 0>` (codec) and
  `<0 0>` (interface device), as mainline does it for Taiko (`slim217,a0`).
- Reset: TLMM GPIO 72; interrupt: TLMM GPIO 68.
- Supplies (all in our DTS already): vdd-buck S4 (1.8 V, 650 mA), vdd-h and vdd-px L6 (1.8 V),
  vdd-cx L4 (1.2 V), vdd-buckhelper L25 (1.775-2.125 V).
- Micbias: `qcom,cdc-micbias1-ext-cap`; cfilt1 1.8 V, cfilt2 2.7 V, cfilt3 1.8 V; micbias1-3 on
  cfilt1-3; `ldoh-v` 0x3.
- MCLK 9.6 MHz on PM8226 GPIO1 (function 1, "XO_PMIC_CDC_MCLK"), from the RPM's `div_clk1`
  (`clock-8226.c`: `CLK_LOOKUP("osr_clk", div_clk1.c, "msm-dai-q6-dev.16384")`).
- The machine driver also handles a WCD9302 variant at runtime; that the I9301I has the 9306 is
  unverified.

SLIMbus: the NGD controller at 0xfe12f000 (0x35000), its BAM at 0xfe104000, interrupts SPI 163
and 164, the same as MSM8974. The ADSP is the bus manager; SLIMbus data ports are AFE ports on the
ADSP.

Machine driver `sound/soc/msm/msm8226.c` (`qcom,msm8226-audio-tapan`): back ends `SLIMBUS_0_RX`
(to the codec's `tapan_rx1`) and `SLIMBUS_0_TX` (from `tapan_tx1`), shared channels 144-148 (RX)
and 128-132 (TX); front ends through q6asm and routing.

Outputs and inputs (`msm8226-sec-s3ve3geur-r04.dtsi` routing):

| Path | Hardware |
|---|---|
| Speaker | the codec's own class-D driver (SPK_OUT, RX4); no external amplifier (MAX98504 commented out in the defconfig fragment, no amp GPIOs) |
| Earpiece | EAR PA (RX1, DAC1) |
| Headphones | HPHL/HPHR (RX1/RX2, class H, compander COMP1) |
| Main mic | AMIC1, MIC BIAS1 External |
| Headset mic | AMIC2, MIC BIAS2 External |
| Sub mic | AMIC3, MIC BIAS1 |
| Third mic | AMIC4, MIC BIAS2 (voice paths) |

Jack detection is Samsung's (`sec_jack`, `CONFIG_SAMSUNG_JACK=y`), not the codec's MBHC
(`tapan_hs_detect` is off):

- Detect: TLMM GPIO 69, active low; send/end button: TLMM GPIO 35, active low.
- The mic voltage through the PM8226 VADC (channel 0x27, MPP8 at 1:3): below 900 mV a 3-pole
  plug, above a 4-pole headset; buttons 0-320 mV KEY_MEDIA, 321-440 mV VOLUMEUP, 441+ mV
  VOLUMEDOWN.
- While detecting, MIC BIAS2 is forced on (`msm8226_enable_ear_micbias()`).
- An s3ve3g workaround for interrupt flooding (`sec_jack.c:718`).

Downstream config: `MSM_PIL_LPASS_QDSP6V5`, `MSM_ADSP_LOADER`, `SLIMBUS_MSM_NGD`, `WCD9306_CODEC`,
`SND_SOC_MSM8226`; device fragment `SAMSUNG_JACK=y`.

## LineageOS userspace

`audio/mixer_paths.xml` of `s3ve3g-common` (header "GT-I9301I_EUR_XX (s3ve3g)") and
`audio_platform_info.xml`; no UCM. The building blocks for a UCM profile:

| Path | Controls |
|---|---|
| Playback | `SLIMBUS_0_RX Audio Mixer MultiMedia1` 1 |
| Capture | `MultiMedia1 Mixer SLIM_0_TX` 1 |
| Speaker | `SLIM RX1 MUX` AIF1_PB, `SLIM_0_RX Channels` One, `RX4 MIX1 INP1` RX1, `SPK DAC Switch` 1; `RX4 Digital Volume` 83, `SPK DRV Volume` 7-8 |
| Earpiece | `SLIM RX1 MUX` AIF1_PB, `RX1 MIX1 INP1` RX1, `CLASS_H_DSM MUX` RX_HPHL, `DAC1 Switch` 1; `EAR PA Gain` POS_2_DB, `RX1 Digital Volume` 83 |
| Headphones | `SLIM RX1/RX2 MUX` AIF1_PB, `SLIM_0_RX Channels` Two, `RX1/RX2 MIX1 INP1` RX1/RX2, `CLASS_H_DSM MUX` RX_HPHL, `HPHL DAC Switch` 1, `COMP1 Switch` 1; `HPHL/HPHR Volume` 16, `RX1/RX2 Digital Volume` 84 |
| Main mic | `AIF1_CAP Mixer SLIM TX1` 1, `SLIM TX1 MUX` DEC1, `DEC1 MUX` ADC1; `ADC1 Volume` 19, `DEC1 Volume` 84 |
| Headset mic | as the main mic, `DEC1 MUX` ADC2 |
| Sub mic | as the main mic, `DEC1 MUX` ADC3 |

Voice calls use the ADSP voice services (`SLIM_0_RX_Voice Mixer CSVoice`, `Voice_Tx Mixer
SLIM_0_TX_Voice`). The ACDB calibration files aren't needed with mainline's q6 drivers.

## Mainline state

- Codec: mainline has `wcd9335`, `wcd934x` and the SoundWire `wcd937x/8x/9x`; no WCD9306, no
  WCD9320. No patches found (lore, the msm8226-mainline organisation, pmaports). The postmarketOS
  wiki lists MSM8226 audio as not working (Galaxy Tab 4, Grand 2).
- ADSP: mainline `qcom_q6v5_pas.c` knows `qcom,msm8226-adsp-pil` (`adsp.mdt`). The fork's
  `qcom-msm8226.dtsi` has the `adsp` node with its `lpass` SMD edge, disabled; lenok, sparrow and
  matisse enable it (pmaports: `firmware-lg-lenok-adsp`, `firmware-asus-sparrow-adsp`).
- SLIMbus: mainline `qcom-ngd-ctrl.c` (`qcom,slim-ngd-v1.5.0`, `-v2.1.0`), QMI service 0x301 on
  the ADSP. It works on MSM8974 with v1.5.0 (z3ntu's `flto-msm8974-5.11` branch, the Xperia Z2
  project https://github.com/RobLymm/xperia-sirius-linux); 8226 has the same LPASS generation
  and addresses, so it very probably works (unverified). It also registers a PDR lookup
  (`avs/audio`) old firmware doesn't serve; 8974 works regardless.
- QDSP6 on the old ADSP firmware: the Z2 project runs mainline APR v2 over `apr_audio_svc` with
  q6core/q6afe/q6asm/q6adm/q6routing; speaker (MI2S, TFA9890) and WCD9320 headphones over
  `SLIMBUS_0_RX` work; capture every other time, no jack detection, several crashes fixed in its
  codec port (the same kinds will turn up in a Tapan port). Its channel lesson applies here: the
  ADSP gets shared channels 144+ (RX) and 128+ (TX), not codec port numbers.
- No MSM8226 device has mainline audio; on MSM8974 only that out-of-tree work.
- Calls: the ADSP voice services (CVS/CVP/MVM) aren't mainline (ports: the Z2 project's
  `drivers/audio/q6voice`, the postmarketOS q6voice project); our modem isn't up anyway.

## What our kernel would need

Config (not set now: `SND_SOC_QCOM`, `QCOM_APR`, `SLIMBUS`; already there: `QCOM_Q6V5_PAS=m`,
`QRTR`, `QRTR_SMD`, `QCOM_QMI_HELPERS`, `QCOM_BAM_DMA=y`, `RPMSG_QCOM_SMD=y`):
`QCOM_APR`, `SLIMBUS`, `SLIM_QCOM_NGD_CTRL`, `SND_SOC_QCOM`, `SND_SOC_QDSP6`, a machine driver
(the Z2 project's `msm8974-sndcard.c`, or one in the style of mainline `sdm845.c`/`apq8096.c`), the
new `SND_SOC_WCD9306` (with `REGMAP_SLIMBUS`), probably `QCOM_SYSMON`; for the jack's ADC
`QCOM_SPMI_VADC`, maybe `EXTCON_ADC_JACK`.

Device tree:

1. `&adsp` enabled, with an `apr` node (`qcom,apr-v2`, `qcom,smd-channels = "apr_audio_svc"`)
   under its SMD edge: q6core, q6afe (DAIs), q6asm (DAIs), q6adm (routing), shaped as in z3ntu's
   `qcom-msm8974.dtsi`.
2. The SLIMbus BAM (`dma-controller@fe104000`, `qcom,bam-v1.4.0`, SPI 164, `qcom,ee = <1>`,
   `qcom,controlled-remotely`) and the controller (`slim@fe12f000`, `qcom,slim-ngd-v1.5.0`,
   SPI 163, DMA channels 3 and 4).
3. Under `ngd@1`: the interface device `slim217,e0` at `<0 0>` and the codec `slim217,e0` at
   `<1 0>`: reset TLMM 72, interrupt TLMM 68, the S4/L6/L4/L25 supplies, the MCLK and a pinctrl
   for PM8226 GPIO1 function 1, `#sound-dai-cells`.
4. A `sound` node: `SLIMBUS_0_RX`/`TX` links between the codec and q6routing, q6asm front ends,
   the routing from the downstream list (widget names follow the new driver).
5. Jack: `gpio-keys` (`SW_HEADPHONE_INSERT` on TLMM 69, active low; KEY_MEDIA on TLMM 35) or
   jack GPIOs in the machine driver. 3/4-pole detection and the volume buttons need VADC channel
   0x27 with MPP8 as an analog input and MIC BIAS2 on while detecting: a small driver,
   `extcon-adc-jack`, or always assuming a headset.

Open question, the MCLK: mainline `rpmcc-msm8226` models `RPM_SMD_DIV_CLK1` as a fixed 19.2 MHz;
the Z2 project found mainline `div_clk1` can't make 9.6 MHz and used the PMIC's own divider
(`clk-spmi-pmic-div`) on its PM8941. Whether that holds for PM8226 is unverified. Without MCLK
the codec answers on the bus but stays silent.

Firmware: `adsp.mdt` and `adsp.bNN` from `apnhlos:/image`, one more line in
`s3ve3g-firmware.sh` (as for wcnss). The number of segments is still to be checked on the phone;
the `adsp_region` (0x0d900000, 0x1800000) has to hold the image.

Userspace: an ALSA UCM profile (`HiFi.conf`) from the mixer paths above, if the port keeps the
downstream control names. Mainline q6routing names the front-end controls
`SLIMBUS_0_RX Audio Mixer MultiMedia1` and `MultiMedia2 Mixer SLIMBUS_0_TX` (downstream:
`SLIM_0_TX`); the Z2 project captures through MultiMedia2.

## Effort (estimates)

| Step | Effort | Check |
|---|---|---|
| 1. ADSP, APR, q6 | 1-2 days | q6core/afe/asm/adm probe, QMI service 0x301 shows up |
| 2. SLIMbus controller and BAM | 1-3 days | the codec enumerates as `slim217,e0` without a driver |
| 3. WCD9306 driver | 3-8 weeks part time | downstream `wcd9306.c` is 7,000 lines on the wcd9xxx core, resmgr and class-H helpers; MBHC can be left out (Samsung doesn't use it). Template: the Z2/z3ntu WCD9320 port plus mainline `wcd9335`'s structure. Order: speaker, earpiece and headphones, capture |
| 4. Machine driver | 2-4 days | |
| 5. Jack detection | 2-5 days | |
| 6. UCM profile | 1 day | |
| 7. Calls | blocked | modem bring-up, out-of-tree q6voice |

Steps 1-2 test the main unknown after the codec (whether 8226's controller and ADSP firmware
behave like 8974's) before the port.

References: the Xperia Z2 project (above, `audio_README.md`, `audio_wcd9320-README.md`), z3ntu's
`flto-msm8974-5.11` `qcom-msm8974.dtsi`, the postmarketOS wiki pages of the Galaxy Tab 4 10.1 and
Grand 2, the postmarketOS q6voice blog post (2026-05-08), LineageOS `s3ve3g-common` lineage-18.1.
