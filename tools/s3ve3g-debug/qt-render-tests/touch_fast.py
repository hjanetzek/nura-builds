#!/usr/bin/env python3
"""Fast synthetic drags (touch events every 10 ms, like a finger) into the real zynthian, frames
grabbed continuously in a second thread and checked for black backgrounds (touch_glitch.py's
sample points).  sudo python3 touch_fast.py [SECONDS] [OUTDIR]"""
import os, sys, threading, time
secs = float(sys.argv[1]) if len(sys.argv) > 1 else 30
out = sys.argv[2] if len(sys.argv) > 2 else "/tmp/touch_fast"
sys.argv = [sys.argv[0], "0", out]
exec(open("/tmp/gltest/touch_glitch.py").read().split("for r in range(ROUNDS):")[0])
stop = [False]

def grabber():
    while not stop[0]:
        check("cont")

th = threading.Thread(target=grabber); th.start()
t_end = time.time() + secs
while time.time() < t_end:
    for x in (1225, 341):
        down(x, 420)
        for k in range(48):
            y = 420 - (240 * k) // 47 if (k // 24) % 2 == 0 else 180 + (240 * (k - 24)) // 23
            move(x, y + (k % 3)); time.sleep(0.01)
        up(); time.sleep(0.05)
    tap(1225, 476)
stop[0] = True; th.join()
ui.close()
print("fast touch test: %d frames checked, %d with black backgrounds" % (stats["frames"], stats["bad"]), flush=True)
