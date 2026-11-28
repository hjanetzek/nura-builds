#!/usr/bin/env python3
# TDM-B as the CS42448 will use it (docs/odroid-n2-cs42448.md): 8 slots x 32 bits, dsp_a, out on
# lane 0 (GPIOA_3, J7 pin 7), in on lane 1 (GPIOA_4, J2 pin 26); SCLK = 256 Fs (12.288 MHz at
# 48 kHz), MCLK = 512 Fs: the TDM block's SCLK divider is at least 2 (with mclk-fs 256 SCLK reached
# only 6.144 MHz, a 128-bit frame, and an 8 x 32-bit stream hung: aplay "I/O error"); the CS42448
# takes MCLK at 512 Fs in single-speed mode. On top of
# dtb-tdmb-capture.py's output. The internal DAC and HDMI take only a 2-slot frame: dai-link-6
# gets stand-in codecs instead (linux,spdif-dit for playback, the capture one already there), so
# the line out stays on TDM-C (dai-link-7).
# Usage: dtb-tdmb-8ch.py IN.dts OUT.dts
import re, sys
src = open(sys.argv[1]).read()
used = {int(x, 16) for x in re.findall(r"phandle = <(0x[0-9a-f]+)>;", src)}
ph = max(used) + 1
codec = ("\n\tnura-tdmb-playback-codec {\n\t\tcompatible = \"linux,spdif-dit\";\n"
         "\t\t#sound-dai-cells = <0x00>;\n\t\tsound-name-prefix = \"TDMB_OUT\";\n"
         f"\t\tphandle = <{ph:#x}>;\n\t}};\n")
m = re.search(r"\n\tsound \{\n", src)
assert m
src = src[:m.start()] + codec + src[m.start():]
d = re.search(r"\n\t\tdai-link-6 \{\n\t\t\tsound-dai = <0x63>;\n(?:.|\n)*?\n\t\t\};\n", src)
assert d, "dai-link-6"
cap = re.search(r"codec-2 \{\n\t\t\t\tsound-dai = <(0x[0-9a-f]+)>;", d.group(0))
assert cap, "codec-2 (capture stand-in)"
ones = " ".join(["0x01"] * 8)
link = ("\n\t\tdai-link-6 {\n\t\t\tsound-dai = <0x63>;\n\t\t\tdai-format = \"dsp_a\";\n"
        f"\t\t\tdai-tdm-slot-tx-mask-0 = <{ones}>;\n\t\t\tdai-tdm-slot-rx-mask-1 = <{ones}>;\n"
        "\t\t\tdai-tdm-slot-num = <0x08>;\n\t\t\tdai-tdm-slot-width = <0x20>;\n"
        "\t\t\tmclk-fs = <0x200>;\n\n"
        f"\t\t\tcodec-0 {{\n\t\t\t\tsound-dai = <{ph:#x}>;\n\t\t\t}};\n\n"
        f"\t\t\tcodec-1 {{\n\t\t\t\tsound-dai = <{cap.group(1)}>;\n\t\t\t}};\n\t\t}};\n")
src = src[:d.start()] + link + src[d.end():]
open(sys.argv[2], "w").write(src)
print(f"playback stand-in codec phandle {ph:#x}, capture {cap.group(1)}")
