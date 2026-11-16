#!/usr/bin/env python3
"""Samsung Galaxy S III Neo, debugging: the home key captures what the screen shows and what the
GPU gets, for glitch hunting while an application (zynthian on eglfs) owns the display.

On each press of the home key (KEY_HOMEPAGE on "GPIO Buttons"):
- the framebuffer currently scanned out, as PNG (as scanned out, portrait, and rotated by
  ROTATE degrees, as seen with zynthian's ZYNTHIAN_UI_ROTATION=90): through DRM as root
  (GETFB2 gives root a GEM handle to the owner's buffer, exported as a dma-buf and mapped; msm's
  GEM_INFO offset is refused for it on 7.3.4), so the application keeps DRM master and isn't
  disturbed
- the GPU submissions for CAPTURE_S seconds from msm's debugfs "rd" (command streams; with
  RD_FULL=1 also the buffers, much bigger), decodable with Mesa's freedreno tools (cffdump)
- the kernel log at that moment
into OUTDIR/<time>-*. Run as root:  python3 s3ve3g-capture.py [--once]  (--once: capture now,
without waiting for the key).
Environment: OUTDIR (/var/tmp/s3ve3g-captures), CAPTURE_S (5), ROTATE (90), RD_FULL (0), CARD (1)
"""
import fcntl, mmap, os, re, struct, subprocess, sys, threading, time

OUTDIR = os.environ.get("OUTDIR", "/var/tmp/s3ve3g-captures")
CAPTURE_S = float(os.environ.get("CAPTURE_S", "5"))
ROTATE = int(os.environ.get("ROTATE", "90"))
RD_FULL = os.environ.get("RD_FULL", "0") == "1"
CARD = os.environ.get("CARD", "1")
DEBUGFS = f"/sys/kernel/debug/dri/{CARD}"

def _iowr(nr, size):	# _IOWR('d', nr, size)
    return (3 << 30) | (size << 16) | (ord('d') << 8) | nr

# struct drm_mode_fb_cmd2: fb_id, width, height, pixel_format, flags, handles[4], pitches[4],
# offsets[4] (u32), then modifier[4] (u64, 8-aligned: at 72): 104 bytes
FB_CMD2 = struct.Struct("<5I4I4I4I4x4Q")
DRM_IOCTL_MODE_GETFB2 = _iowr(0xCE, FB_CMD2.size)
# struct drm_prime_handle: handle, flags (u32), fd (s32): 12 bytes
PRIME = struct.Struct("<IIi")
DRM_IOCTL_PRIME_HANDLE_TO_FD = _iowr(0x2D, PRIME.size)
DRM_CLOEXEC = os.O_CLOEXEC
# struct drm_gem_close: handle, pad
DRM_IOCTL_GEM_CLOSE = (1 << 30) | (8 << 16) | (ord('d') << 8) | 0x09

def scanout_fb_id():
    """The framebuffer on the primary plane (debugfs state: the first plane with fb=N, N > 0)"""
    with open(f"{DEBUGFS}/state") as f:
        for m in re.finditer(r"fb=(\d+)", f.read()):
            if int(m.group(1)):
                return int(m.group(1))
    return None

def screenshot(stem):
    fb_id = scanout_fb_id()
    if not fb_id:
        return "no framebuffer on the screen"
    fd = os.open(f"/dev/dri/card{CARD}", os.O_RDWR)
    try:
        buf = bytearray(FB_CMD2.pack(fb_id, *([0] * 16), *([0] * 4)))
        fcntl.ioctl(fd, DRM_IOCTL_MODE_GETFB2, buf)
        f = FB_CMD2.unpack(buf)
        width, height, fourcc = f[1], f[2], f[3]
        handle, pitch, offset = f[5], f[9], f[13]
        if not handle:
            return "GETFB2 gave no handle (not root?)"
        pr = bytearray(PRIME.pack(handle, DRM_CLOEXEC, -1))
        fcntl.ioctl(fd, DRM_IOCTL_PRIME_HANDLE_TO_FD, pr)
        dmabuf = PRIME.unpack(pr)[2]
        try:
            size = offset + pitch * height
            m = mmap.mmap(dmabuf, (size + 4095) & ~4095, mmap.MAP_SHARED, mmap.PROT_READ)
            data = bytes(m[offset:offset + pitch * height])
            m.close()
        finally:
            os.close(dmabuf)
            fcntl.ioctl(fd, DRM_IOCTL_GEM_CLOSE, struct.pack("<II", handle, 0))
    finally:
        os.close(fd)
    if fourcc not in (0x34325258, 0x34324241):	# XR24, AR24: B G R X in memory
        return f"unsupported format {fourcc:#x}"
    from PIL import Image
    img = Image.frombuffer("RGBX", (width, height), data, "raw", "BGRX", pitch, 1).convert("RGB")
    img.save(f"{stem}-screen.png")
    if ROTATE:
        img.rotate(ROTATE, expand=True).save(f"{stem}-screen-rotated.png")
    return f"screen {width}x{height} fb {fb_id}"

def gpu_capture(stem):
    """msm's rd: every submit while the file is open (blocking reads)"""
    rd_full = "/sys/module/msm/parameters/rd_full"
    try:
        with open(rd_full, "w") as f:
            f.write("Y" if RD_FULL else "N")
    except OSError:
        pass
    out = f"{stem}-gpu.rd"
    end = time.time() + CAPTURE_S
    n = 0
    with open(f"{DEBUGFS}/rd", "rb", buffering=0) as rd, open(out, "wb") as o:
        os.set_blocking(rd.fileno(), False)
        while time.time() < end:
            try:
                chunk = rd.read(1 << 16)
            except BlockingIOError:
                chunk = None
            if chunk:
                o.write(chunk); n += len(chunk)
            else:
                time.sleep(0.01)
    return f"gpu {n} bytes in {CAPTURE_S:g} s"

def capture():
    os.makedirs(OUTDIR, exist_ok=True)
    stem = os.path.join(OUTDIR, time.strftime("%Y%m%d-%H%M%S"))
    results = {}
    t = threading.Thread(target=lambda: results.__setitem__("gpu", gpu_capture(stem)))
    t.start()
    try:
        results["screen"] = screenshot(stem)
    except Exception as e:	# a failed screenshot shouldn't stop the GPU capture
        results["screen"] = f"screenshot failed: {e}"
    with open(f"{stem}-dmesg.txt", "w") as f:
        f.write(subprocess.run(["dmesg"], capture_output=True, text=True).stdout[-20000:])
    t.join()
    msg = f"{stem}: {results.get('screen')}, {results.get('gpu')}"
    print(msg, flush=True)
    subprocess.run(["logger", "-t", "s3ve3g-capture", msg])

def find_key_device():
    for d in sorted(os.listdir("/sys/class/input")):
        if d.startswith("event"):
            try:
                with open(f"/sys/class/input/{d}/device/name") as f:
                    if f.read().strip() == "GPIO Buttons":
                        return f"/dev/input/{d}"
            except OSError:
                pass
    return None

def main():
    if "--once" in sys.argv:
        capture()
        return
    dev = find_key_device()
    if not dev:
        sys.exit("no GPIO Buttons input device")
    ev = struct.Struct("llHHi")	# struct input_event (32-bit: 16 bytes)
    busy = threading.Lock()
    with open(dev, "rb", buffering=0) as f:
        while True:
            _, _, typ, code, value = ev.unpack(f.read(ev.size))
            if typ == 1 and code == 172 and value == 1 and busy.acquire(blocking=False):	# EV_KEY KEY_HOMEPAGE press
                def run():
                    try:
                        capture()
                    finally:
                        busy.release()
                threading.Thread(target=run, daemon=True).start()

if __name__ == "__main__":
    main()
