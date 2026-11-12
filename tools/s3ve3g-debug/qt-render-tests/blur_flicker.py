#!/usr/bin/env python3
"""Render test 2 (KeypadBlur structure): change the screen every 50 ms, read each frame back and
check the blurred keypad area: the blurred source (bright colors, darkened by brightness -0.2) must
never come out (nearly) black.  python3 blur_flicker.py [SECONDS] [OUTDIR] [--nocheck]"""
import os, sys
import shiboken6
from PySide6.QtCore import QTimer, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow

args = [a for a in sys.argv[1:] if not a.startswith("--")]
secs = float(args[0]) if args else 20
outdir = args[1] if len(args) > 1 else "/tmp/blur_flicker"
nocheck = "--nocheck" in sys.argv
os.makedirs(outdir, exist_ok=True)
app = QGuiApplication(sys.argv)
engine = QQmlApplicationEngine(QUrl.fromLocalFile(os.path.join(os.path.dirname(os.path.abspath(__file__)), "blur_flicker.qml")))
win = shiboken6.wrapInstance(shiboken6.getCppPointer(engine.rootObjects()[0])[0], QQuickWindow)
st = {"frames": 0, "bad": 0, "saved": 0}

def step():
    s = win.property("step")
    if not nocheck:
        img = win.grabWindow()
        d = img.devicePixelRatio()
        h = img.height()
        # sample a row of points in the blurred area between the keys and below them
        dark = 0
        pts = [(x, y) for x in range(10, int(img.width() / d) - 10, 40) for y in (700 + 10, 700 + 140, h / d - 20)]
        for x, y in pts:
            c = img.pixelColor(int(x * d), int(y * d))
            if c.red() + c.green() + c.blue() < 30:
                dark += 1
        st["frames"] += 1
        if dark > len(pts) // 4:
            st["bad"] += 1
            if st["saved"] < 5:
                img.save(os.path.join(outdir, "bad-%03d.png" % st["frames"]))
                st["saved"] += 1
                print("frame %d: %d of %d samples black" % (st["frames"], dark, len(pts)), flush=True)
    win.setProperty("step", s + 1)

t = QTimer(); t.timeout.connect(step); t.start(50)
QTimer.singleShot(int(secs * 1000), app.quit)
app.exec()
print("blur test, renderer %s: %d frames checked, %d with a black blur area" % (
    os.environ.get("QT_QUICK_BACKEND", "gl"), st["frames"], st["bad"]), flush=True)
