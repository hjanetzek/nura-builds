#!/usr/bin/env python3
"""Synthetic touches into the real zynthian (cage, output rotated to 1280x720) and checks of what
cage shows (grim): key/strip backgrounds that turn black after touch events.

    sudo python3 touch_glitch.py [ROUNDS] [OUTDIR]

Run as root (uinput); grim connects to the user's Wayland socket (XDG_RUNTIME_DIR below)."""
import glob, os, subprocess, sys, time
from evdev import UInput, AbsInfo, ecodes as e

ROUNDS = int(sys.argv[1]) if len(sys.argv) > 1 else 10
OUT = sys.argv[2] if len(sys.argv) > 2 else "/tmp/touch_glitch"
os.makedirs(OUT, exist_ok=True)
RT = "/tmp/xdg-jeff"
WL = sorted(f for f in os.listdir(RT) if f.startswith("wayland-") and not f.endswith(".lock"))[0]
W, H = 1280, 720

cap = {e.EV_KEY: [e.BTN_TOUCH],
       e.EV_ABS: [(e.ABS_X, AbsInfo(0, 0, W - 1, 0, 0, 0)), (e.ABS_Y, AbsInfo(0, 0, H - 1, 0, 0, 0)),
                  (e.ABS_MT_SLOT, AbsInfo(0, 0, 9, 0, 0, 0)), (e.ABS_MT_TRACKING_ID, AbsInfo(0, 0, 65535, 0, 0, 0)),
                  (e.ABS_MT_POSITION_X, AbsInfo(0, 0, W - 1, 0, 0, 0)), (e.ABS_MT_POSITION_Y, AbsInfo(0, 0, H - 1, 0, 0, 0))]}
ui = UInput(cap, name="s3ve3g synthetic touch", input_props=[e.INPUT_PROP_DIRECT])
time.sleep(1.5)   # cage/libinput pick the device up
tid = [0]

def down(x, y):
    tid[0] += 1
    for t, c, v in ((e.EV_ABS, e.ABS_MT_SLOT, 0), (e.EV_ABS, e.ABS_MT_TRACKING_ID, tid[0]), (e.EV_ABS, e.ABS_MT_POSITION_X, x),
                    (e.EV_ABS, e.ABS_MT_POSITION_Y, y), (e.EV_KEY, e.BTN_TOUCH, 1), (e.EV_ABS, e.ABS_X, x), (e.EV_ABS, e.ABS_Y, y)):
        ui.write(t, c, v)
    ui.syn()

def move(x, y):
    for t, c, v in ((e.EV_ABS, e.ABS_MT_POSITION_X, x), (e.EV_ABS, e.ABS_MT_POSITION_Y, y), (e.EV_ABS, e.ABS_X, x), (e.EV_ABS, e.ABS_Y, y)):
        ui.write(t, c, v)
    ui.syn()

def up():
    ui.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, -1); ui.write(e.EV_KEY, e.BTN_TOUCH, 0); ui.syn()

def grab():
    env = dict(os.environ, XDG_RUNTIME_DIR=RT, WAYLAND_DISPLAY=WL)
    data = subprocess.run(["grim", "-t", "ppm", "-"], env=env, capture_output=True).stdout
    # P6 header: magic, width, height, maxval
    parts = data.split(b"\n", 3)
    w, h = map(int, parts[1].split())
    return w, h, parts[3]

def px(img, x, y):
    w, h, d = img
    i = (y * w + x) * 3
    return d[i], d[i + 1], d[i + 2]

# sample points: corners of the keypad cells (left columns, bottom row) and the strips' panel
pts = []
for cx in (0, 145):
    for cy in range(0, 570, 114):
        pts += [(cx + 10, cy + 10), (cx + 130, cy + 100)]
for cx in range(0, 1280, 128):
    pts += [(cx + 10, 582), (cx + 115, 708)]
pts += [(300, 90), (1185, 150), (300, 455), (1185, 455)]

ref = grab()
base = [p for p in pts if 25 < sum(px(ref, *p)) < 250]   # dark grey backgrounds in the reference
print("sample points: %d of %d are background in the reference" % (len(base), len(pts)), flush=True)
stats = {"frames": 0, "bad": 0, "saved": 0}

def check(tag):
    img = grab()
    stats["frames"] += 1
    black = [p for p in base if sum(px(img, *p)) < 15]
    if black:
        stats["bad"] += 1
        if stats["saved"] < 8:
            w, h, d = img
            with open(os.path.join(OUT, "bad-%03d-%s.ppm" % (stats["frames"], tag)), "wb") as f:
                f.write(b"P6\n%d %d\n255\n" % (w, h) + d)
            stats["saved"] += 1
        print("frame %d (%s): %d of %d background points black, e.g. %s" % (stats["frames"], tag, len(black), len(base), black[:4]), flush=True)

def drag(x, y0, y1, n=8):
    down(x, y0); check("drag-down")
    for k in range(1, n + 1):
        move(x, y0 + (y1 - y0) * k // n); check("drag-move")
    up(); check("drag-up"); time.sleep(0.15); check("after")

def tap(x, y):
    down(x, y); check("tap-down"); time.sleep(0.08); up(); check("tap-up"); time.sleep(0.15); check("after")

for r in range(ROUNDS):
    drag(1225, 420, 180); drag(1225, 180, 420)     # Main volume
    drag(341, 420, 180); drag(341, 180, 420)       # Clippy volume
    tap(1225, 476); tap(1225, 476)                 # Main mute on/off
    tap(341, 476); tap(341, 476)                   # Clippy mute on/off
ui.close()
print("touch test: %d frames checked, %d with black backgrounds" % (stats["frames"], stats["bad"]), flush=True)
