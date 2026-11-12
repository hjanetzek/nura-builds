#!/usr/bin/env python3
"""Render test 3 (changing labels, glyph cache): change the screen every 50 ms, read each frame back and
check the blurred keypad area: the blurred source (bright colors, darkened by brightness -0.2) must
never come out (nearly) black.  python3 text_flicker.py [SECONDS] [OUTDIR] [--nocheck]"""
import os, sys
import shiboken6
from PySide6.QtCore import QTimer, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow

args = [a for a in sys.argv[1:] if not a.startswith("--")]
secs = float(args[0]) if args else 20
outdir = args[1] if len(args) > 1 else "/tmp/text_flicker"
nocheck = "--nocheck" in sys.argv
os.makedirs(outdir, exist_ok=True)
app = QGuiApplication(sys.argv)
engine = QQmlApplicationEngine(QUrl.fromLocalFile(os.path.join(os.path.dirname(os.path.abspath(__file__)), "text_flicker.qml")))
win = shiboken6.wrapInstance(shiboken6.getCppPointer(engine.rootObjects()[0])[0], QQuickWindow)
st = {"frames": 0, "bad": 0, "saved": 0}

def step():
    s = win.property("step")
    if not nocheck:
        img = win.grabWindow()
        d = img.devicePixelRatio()
        h = img.height()
        # the button backgrounds (#3050c0) at points away from the labels: never (nearly) black
        dark = 0
        pts = [(20 + c * 166 + dx, 20 + r * 126 + dy) for r in range(4) for c in range(4) for dx, dy in ((15, 15), (135, 95))]
        for x, y in pts:
            col = img.pixelColor(int(x * d), int(y * d))
            if col.red() + col.green() + col.blue() < 60:
                dark += 1
        st["frames"] += 1
        if dark:
            st["bad"] += 1
            if st["saved"] < 5:
                img.save(os.path.join(outdir, "bad-%03d.png" % st["frames"]))
                st["saved"] += 1
                print("frame %d: %d of %d samples black" % (st["frames"], dark, len(pts)), flush=True)
    win.setProperty("step", s + 1)

t = QTimer(); t.timeout.connect(step); t.start(50)
QTimer.singleShot(int(secs * 1000), app.quit)
app.exec()
print("blur test, renderer %s: %d frames checked, %d with black button background" % (
    os.environ.get("QT_QUICK_BACKEND", "gl"), st["frames"], st["bad"]), flush=True)
