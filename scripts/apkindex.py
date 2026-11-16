#!/usr/bin/env python3
"""APKINDEX.tar.gz without apk-tools: read, merge and sign package indexes, for publishing on
runners without apk/abuild (scripts/publish.sh).

An APKINDEX.tar.gz is a signature (a gzip stream holding a tar member .SIGN.RSA.<key>.pub, cut
before the tar end marker) followed by a gzip stream with the tar members DESCRIPTION and
APKINDEX. The signature is RSA with SHA-1 over the second gzip stream, as abuild-sign makes it
(openssl dgst -sha1 -sign). APKINDEX is blocks of "X:value" lines separated by an empty line,
one block per package (P: name, V: version, A: arch, o: origin, ...).

Usage:
  apkindex.py list INDEX                       name version file per package
  apkindex.py merge OUT BASE NEW [--drop NAME...] [--key KEY --key-name NAME] [--description TEXT]
      the packages of BASE (the published index), minus those NEW has (by name) and minus the
      names given with --drop, plus all of NEW; signed with KEY (PEM) as KEY-NAME
      (e.g. pmos@local-6ae1d406.rsa) when given. BASE may be "-" (none).
  apkindex.py sign IN OUT --key KEY --key-name NAME   (re)sign an index
  apkindex.py filter IN OUT FILE...            unsigned index of only the packages whose file
      (<name>-<version>.apk) is among FILE (paths or names), e.g. the packages a build added
"""
import gzip
import io
import subprocess
import sys
import tarfile
import time
import zlib


def gzip_members(data):
    """The separate gzip streams of a file"""
    streams = []
    while data:
        d = zlib.decompressobj(16 + zlib.MAX_WBITS)
        d.decompress(data)
        used = len(data) - len(d.unused_data)
        streams.append(data[:used])
        data = d.unused_data
    return streams


def read_index(path):
    """(description, [blocks]) of an APKINDEX.tar.gz; a block is a list of "X:value" lines"""
    with open(path, "rb") as f:
        data = f.read()
    streams = gzip_members(data)
    # the last stream holds DESCRIPTION and APKINDEX (an unsigned index has only that one)
    with tarfile.open(fileobj=io.BytesIO(gzip.decompress(streams[-1]))) as t:
        text = t.extractfile("APKINDEX").read().decode()  # type: ignore[union-attr]
        try:
            descr = t.extractfile("DESCRIPTION").read().decode()  # type: ignore[union-attr]
        except KeyError:
            descr = ""
    blocks = [b.split("\n") for b in text.strip("\n").split("\n\n") if b.strip()]
    return descr, blocks


def field(block, key):
    for line in block:
        if line.startswith(key + ":"):
            return line[len(key) + 1:]
    return None


def index_stream(descr, blocks):
    """The gzip stream with DESCRIPTION and APKINDEX, as apk index writes it"""
    text = "".join("\n".join(b) + "\n\n" for b in blocks).encode()
    buf = io.BytesIO()
    now = int(time.time())
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as t:
        for name, content in (("DESCRIPTION", descr.encode()), ("APKINDEX", text)):
            info = tarfile.TarInfo(name)
            info.size = len(content)
            info.mtime = now
            info.mode = 0o644
            t.addfile(info, io.BytesIO(content))
    return gzip.compress(buf.getvalue(), 9, mtime=now)


def signature_stream(payload, key, key_name):
    """abuild-sign's signature: a tar member .SIGN.RSA.<key_name>.pub with the RSA-SHA1
    signature of the payload, without the tar end marker (abuild-tar --cut), gzipped"""
    sig = subprocess.run(["openssl", "dgst", "-sha1", "-sign", key], input=payload,
                         stdout=subprocess.PIPE, check=True).stdout
    info = tarfile.TarInfo(f".SIGN.RSA.{key_name}.pub")
    info.size = len(sig)
    info.mtime = int(time.time())
    info.mode = 0o644
    info.uname = info.gname = "root"
    member = info.tobuf(format=tarfile.USTAR_FORMAT) + sig
    member += b"\0" * (-len(sig) % 512)
    return gzip.compress(member, 9)


def write_index(path, descr, blocks, key=None, key_name=None):
    payload = index_stream(descr, blocks)
    sig = signature_stream(payload, key, key_name) if key else b""
    with open(path, "wb") as f:
        f.write(sig + payload)


def main(argv):
    def opt(name, default=None):
        if name in argv:
            i = argv.index(name)
            value = argv[i + 1]
            del argv[i:i + 2]
            return value
        return default

    key = opt("--key")
    key_name = opt("--key-name")
    descr_opt = opt("--description")
    drop = []
    if "--drop" in argv:
        i = argv.index("--drop")
        drop = argv[i + 1:]
        del argv[i:]
    if key and not key_name:
        sys.exit("--key needs --key-name")

    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "list":
        _, blocks = read_index(argv[2])
        for b in blocks:
            print(field(b, "P"), f'{field(b, "V")}', f'{field(b, "P")}-{field(b, "V")}.apk')
    elif cmd == "merge":
        out, base, new = argv[2:5]
        descr_new, new_blocks = read_index(new)
        base_blocks = read_index(base)[1] if base != "-" else []
        names = {field(b, "P") for b in new_blocks} | set(drop)
        blocks = [b for b in base_blocks if field(b, "P") not in names] + new_blocks
        blocks.sort(key=lambda b: field(b, "P") or "")
        write_index(out, descr_opt if descr_opt is not None else descr_new, blocks, key, key_name)
        print(f"{out}: {len(blocks)} packages ({len(new_blocks)} new or updated, "
              f"{len(base_blocks) - (len(blocks) - len(new_blocks))} replaced or dropped)")
    elif cmd == "filter":
        import os
        descr, blocks = read_index(argv[2])
        files = {os.path.basename(f) for f in argv[4:]}
        keep = [b for b in blocks if f'{field(b, "P")}-{field(b, "V")}.apk' in files]
        write_index(argv[3], descr, keep)
        print(f"{argv[3]}: {len(keep)} of {len(blocks)} packages")
    elif cmd == "sign":
        descr, blocks = read_index(argv[2])
        write_index(argv[3], descr, blocks, key, key_name)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
