#!/usr/bin/env python3
# Step 2 of docs/odroid-n2-cs42448.md: capture on TDM-B's lane 1 (GPIOA_4, J2 pin 26), on top of
# dtb-tdmb-pins.py's output. The board's TDM-B link (dai-link-6) only has playback codecs (the
# internal DAC, HDMI): it gets a capture-capable stand-in codec (linux,spdif-dir, a node of its
# own), the lane 1 receive mask, and the sound card the route TDMIN_B IN 1 <- TDM_B Capture (as
# the G12A U200's routing; the N2's has only the loopback inputs).
# Usage: dtb-tdmb-capture.py IN.dts OUT.dts
import re, sys
src = open(sys.argv[1]).read()
used = {int(x, 16) for x in re.findall(r"phandle = <(0x[0-9a-f]+)>;", src)}
ph = max(used) + 1

# the stand-in codec, a top-level node
codec = ("\n\tnura-tdmb-capture-codec {\n\t\tcompatible = \"linux,spdif-dir\";\n"
         "\t\t#sound-dai-cells = <0x00>;\n\t\tsound-name-prefix = \"TDMB_IN\";\n"
         f"\t\tphandle = <{ph:#x}>;\n\t}};\n")
m = re.search(r"\n\tsound \{\n", src)
assert m, "sound node"
src = src[:m.start()] + codec + src[m.start():]

# the route TDMIN_B IN 1 <- TDM_B Capture
r = re.search(r"(\n\t\taudio-routing = )(\"[^;]*\");", src)
assert r, "audio-routing"
assert "\"TDMIN_B IN 1\"" not in r.group(2)
src = src[:r.start(2)] + r.group(2) + ", \"TDMIN_B IN 1\", \"TDM_B Capture\"" + src[r.end(2):]

# dai-link-6 (TDM-B, sound-dai = tdmif_b's phandle 0x63): rx mask on lane 1, codec-2
d = re.search(r"(\n\t\tdai-link-6 \{\n\t\t\tsound-dai = <0x63>;\n(?:\t\t\t[^\n]*\n)*?\t\t\tmclk-fs = <0x100>;\n)", src)
assert d, "dai-link-6"
src = src[:d.end()] + "\t\t\tdai-tdm-slot-rx-mask-1 = <0x01 0x01>;\n" + src[d.end():]
c1 = re.search(r"(\n\t\tdai-link-6 \{(?:.|\n)*?\n\t\t\tcodec-1 \{\n(?:.|\n)*?\n\t\t\t\};\n)", src)
assert c1, "codec-1"
src = src[:c1.end()] + f"\n\t\t\tcodec-2 {{\n\t\t\t\tsound-dai = <{ph:#x}>;\n\t\t\t}};\n" + src[c1.end():]
open(sys.argv[2], "w").write(src)
print(f"stand-in codec phandle {ph:#x}")
