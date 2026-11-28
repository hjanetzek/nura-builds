#!/usr/bin/env python3
# The ODROID N2's dtb with TDM-B on the header pins (docs/odroid-n2-cs42448.md, step 1): as the G12A
# U200 reference board, &tdmif_b gets the pins mclk0_a (GPIOA_0, J7 pin 4), tdm_b_sclk (A_1, J7-6),
# tdm_b_fs (A_2, J7-5), tdm_b_dout0 (A_3, J7-7), tdm_b_din1 (A_4, J2-26) and the pad clocks
# MCLK_PAD0 <- MST_B_MCLK, SCLK_PAD1 <- MST_B_SCLK, LRCLK_PAD1 <- MST_B_LRCLK.
# Usage: tdmb-pins.py IN.dts OUT.dts (a dts decompiled from the board's dtb)
import re, sys
src = open(sys.argv[1]).read()
used = {int(x, 16) for x in re.findall(r"phandle = <(0x[0-9a-f]+)>;", src)}
nxt = max(used) + 1
pins = ["mclk0-a", "tdm-b-sclk", "tdm-b-fs", "tdm-b-dout0", "tdm-b-din1"]
ph = {}
for name in pins:
    m = re.search(r"(\n(\t+)" + re.escape(name) + r" \{\n)", src)
    assert m, name
    body_start = m.end()
    # an existing phandle in this node (before its first child)?
    seg = src[body_start:src.index("{", body_start)]
    e = re.search(r"phandle = <(0x[0-9a-f]+)>;", seg)
    if e:
        ph[name] = int(e.group(1), 16)
        continue
    ph[name] = nxt
    src = src[:body_start] + m.group(2) + "\t" + f"phandle = <{nxt:#x}>;\n" + src[body_start:]
    nxt += 1
CLK = 0x19  # clkc_audio, as in tdmif_b's own clocks
AUD = {"MST_B_MCLK": 50, "MST_B_SCLK": 80, "MST_B_LRCLK": 87,
       "TDM_MCLK_PAD0": 155, "TDM_SCLK_PAD1": 161, "TDM_LRCLK_PAD1": 158}
assert re.search(r"audio-controller-1 \{\n\t\tcompatible = \"amlogic,axg-tdm-iface\";[^}]*clocks = <0x19 0x50 0x19 0x57 0x19 0x32>;", src), "tdmif_b"
add = ("\t\tpinctrl-0 = <" + " ".join(f"{ph[n]:#x}" for n in pins) + ">;\n"
       "\t\tpinctrl-names = \"default\";\n"
       f"\t\tassigned-clocks = <{CLK:#x} {AUD['TDM_MCLK_PAD0']:#x} {CLK:#x} {AUD['TDM_SCLK_PAD1']:#x} {CLK:#x} {AUD['TDM_LRCLK_PAD1']:#x}>;\n"
       f"\t\tassigned-clock-parents = <{CLK:#x} {AUD['MST_B_MCLK']:#x} {CLK:#x} {AUD['MST_B_SCLK']:#x} {CLK:#x} {AUD['MST_B_LRCLK']:#x}>;\n"
       "\t\tassigned-clock-rates = <0x00 0x00 0x00>;\n")
src, n = re.subn(r"(audio-controller-1 \{\n\t\tcompatible = \"amlogic,axg-tdm-iface\";\n)", r"\1" + add.replace("\\", "\\\\"), src, count=1)
assert n == 1
open(sys.argv[2], "w").write(src)
print("phandles:", {k: hex(v) for k, v in ph.items()})
