#!/usr/bin/env python3
"""Repack TWRP for the Samsung Galaxy S III Neo with the downstream kernel of nura-builds
(linux-samsung-s3ve3g, CI artifact apks-s3ve3g-recovery): TWRP's ramdisk and command line, the
kernel and dt.img from the package. That kernel has the ram_console, so TWRP's /proc/last_kmsg shows
the RAM log of the previous boot (the mainline kernel's ramoops at 0x1FB00000), and /dev/mem.
See docs/samsung-s3ve3g.md.

Usage: tools/s3ve3g-twrp-repack.py twrp-3.3.1-1-s3ve3g.img linux-samsung-s3ve3g-*.apk out.img
Then, in download mode: heimdall flash --RECOVERY out.img
"""
import gzip
import hashlib
import io
import struct
import sys
import tarfile
from dataclasses import dataclass

HDR = "<8s10I16s512s32s1024s"  # Android boot image header v0, with the QCDT size in the "unused" slot


def pad(data, page):
    return data + b"\0" * (-len(data) % page)


@dataclass
class BootImg:
    ka: int
    ra: int
    sa: int
    ta: int
    page: int
    unused: int
    name: bytes
    cmdline: bytes
    extra: bytes
    kernel: bytes
    ramdisk: bytes
    second: bytes
    dt: bytes


def read_bootimg(path: str) -> BootImg:
    d = open(path, "rb").read()
    f = struct.unpack_from(HDR, d)
    if f[0] != b"ANDROID!":
        sys.exit(f"{path}: not an Android boot image")
    ks, ka, rs, ra, ss, sa, ta, page, dts, unused = f[1:11]
    o = page
    kernel = d[o:o + ks]; o += len(pad(kernel, page))
    ramdisk = d[o:o + rs]; o += len(pad(ramdisk, page))
    second = d[o:o + ss]; o += len(pad(second, page))
    dt = d[o:o + dts]
    return BootImg(ka, ra, sa, ta, page, unused, f[11], f[12], f[14], kernel, ramdisk, second, dt)


def read_apk(path):
    # an apk is concatenated gzip streams of tar segments
    data = gzip.decompress(open(path, "rb").read())
    files = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:", ignore_zeros=True) as t:
        for m in t:
            if m.isfile() and m.name in ("boot/vmlinuz", "boot/dt.img"):
                fo = t.extractfile(m)
                if fo is not None:
                    files[m.name] = fo.read()
    for n in ("boot/vmlinuz", "boot/dt.img"):
        if n not in files:
            sys.exit(f"{path}: no {n}")
    return files["boot/vmlinuz"], files["boot/dt.img"]


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    img = read_bootimg(sys.argv[1])
    kernel, dt = read_apk(sys.argv[2])
    if dt[:4] != b"QCDT":
        sys.exit("dt.img: no QCDT header")
    page = img.page
    sha = hashlib.sha1()
    for part in (kernel, img.ramdisk, img.second, dt):
        sha.update(part)
        sha.update(struct.pack("<I", len(part)))
    hdr = struct.pack(HDR, b"ANDROID!", len(kernel), img.ka, len(img.ramdisk), img.ra,
                      len(img.second), img.sa, img.ta, page, len(dt), img.unused,
                      img.name, img.cmdline, sha.digest().ljust(32, b"\0"), img.extra)
    out = pad(hdr, page) + pad(kernel, page) + pad(img.ramdisk, page)
    if img.second:
        out += pad(img.second, page)
    out += pad(dt, page)
    open(sys.argv[3], "wb").write(out)
    print(f"{sys.argv[3]}: kernel {len(kernel)}, ramdisk {len(img.ramdisk)} (TWRP), dt.img {len(dt)}, "
          f"{len(out)} bytes; cmdline {img.cmdline.rstrip(bytes(1)).decode()!r}")


main()
