#!/usr/bin/env python3
# nura-builds: a QCDT table (dt.img) version 1 as Samsung's msm8226 bootloader reads it and as the
# downstream build makes it: one entry per qcom,msm-id triple <platform variant soc_rev> of each
# DTB, i.e. (platform_id, variant_id, soc_rev, offset, size). pmaports' skales dtbTool writes 0 in
# place of soc_rev for version 1 (the subtype), so no entry matched exactly.
# Each DTB gets FREE bytes of free space (totalsize raised, zeros appended): the bootloader adds the
# memory ranges and its long command line (about 1 KB of its own) to the DTB in place, with only a
# small padding of its own, and resets when that doesn't fit.
#
# Usage: mkqcdt-v1.py OUT.img DTB...
import struct
import sys

PAGE = 2048
FREE = 16384
FDT_BEGIN_NODE, FDT_END_NODE, FDT_PROP, FDT_NOP, FDT_END = 1, 2, 3, 4, 9


def root_prop(dtb, name):
    magic, _total, off_struct, off_strings = struct.unpack_from(">4I", dtb)
    if magic != 0xD00DFEED:
        sys.exit("not a DTB")
    o, depth = off_struct, 0
    while True:
        tag, = struct.unpack_from(">I", dtb, o)
        o += 4
        if tag == FDT_BEGIN_NODE:
            o = (dtb.index(b"\0", o) + 4) & ~3
            depth += 1
        elif tag == FDT_END_NODE:
            depth -= 1
        elif tag == FDT_PROP:
            ln, nameoff = struct.unpack_from(">II", dtb, o)
            o += 8
            pname = dtb[off_strings + nameoff:dtb.index(b"\0", off_strings + nameoff)].decode()
            if depth == 1 and pname == name:
                return dtb[o:o + ln]
            o = (o + ln + 3) & ~3
        elif tag == FDT_NOP:
            pass
        elif tag == FDT_END:
            return None


def pad(b):
    return b + b"\0" * (-len(b) % PAGE)


def grow(dtb):
    total, = struct.unpack_from(">I", dtb, 4)
    dtb = dtb[:total] + b"\0" * FREE
    return dtb[:4] + struct.pack(">I", len(dtb)) + dtb[8:]


def main():
    out, dtbs = sys.argv[1], [grow(open(f, "rb").read()) for f in sys.argv[2:]]
    entries = []
    for i, dtb in enumerate(dtbs):
        ids = root_prop(dtb, "qcom,msm-id")
        if not ids or len(ids) % 12:
            sys.exit(f"{sys.argv[2 + i]}: no qcom,msm-id with triples")
        for k in range(0, len(ids), 12):
            entries.append((struct.unpack(">3I", ids[k:k + 12]), i))
    table_len = 12 + 20 * len(entries) + 4
    offsets, o = [], len(pad(b"\0" * table_len))
    for dtb in dtbs:
        offsets.append(o)
        o += len(pad(dtb))
    table = struct.pack("<4sII", b"QCDT", 1, len(entries))
    for (plat, variant, soc_rev), i in entries:
        table += struct.pack("<5I", plat, variant, soc_rev, offsets[i], len(pad(dtbs[i])))
    table += struct.pack("<I", 0)
    data = pad(table) + b"".join(pad(d) for d in dtbs)
    open(out, "wb").write(data)
    for (plat, variant, soc_rev), i in entries:
        print(f"{out}: {plat:#x} {variant:#x} {soc_rev:#x} -> {sys.argv[2 + i]}")


main()
