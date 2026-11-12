#!/usr/bin/env python3
"""Automated check for broken frames (black button backgrounds) of zynthian's Qt UI on freedreno.

    python3 panel_flicker.py [SECONDS] [OUTDIR]

Changes the panels' colors every 50 ms (like touch), reads each changed frame back with
grabWindow() and compares every panel's center pixel with its expected color. Prints the number of
checked frames and mismatches; saves the first bad frames as PNG in OUTDIR. Run with the GL
renderer and, as reference, QT_QUICK_BACKEND=software.
"""
import os
import sys
from PySide6.QtCore import QTimer, QUrl, QPointF
from PySide6.QtGui import QGuiApplication, QColor
from PySide6.QtQml import QQmlApplicationEngine

secs = float(sys.argv[1]) if len(sys.argv) > 1 else 20
outdir = sys.argv[2] if len(sys.argv) > 2 else "/tmp/panel_flicker"
os.makedirs(outdir, exist_ok=True)
app = QGuiApplication(sys.argv)
engine = QQmlApplicationEngine(QUrl.fromLocalFile(os.path.join(os.path.dirname(os.path.abspath(__file__)), "panel_flicker.qml")))
import shiboken6
from PySide6.QtQuick import QQuickWindow
win = shiboken6.wrapInstance(shiboken6.getCppPointer(engine.rootObjects()[0])[0], QQuickWindow)

def find_items(item, out):
    name = item.objectName()
    if name.startswith("panel"):
        out[int(name[5:])] = item
    for c in item.childItems():
        find_items(c, out)
    return out

panels = {}
palette = [QColor(c) for c in ("#c03030", "#30a040", "#3050c0", "#c0a030")]
stats = {"frames": 0, "bad": 0, "bad_panels": 0, "saved": 0, "black": 0}

def close(a, b):
    return abs(a.red() - b.red()) < 24 and abs(a.green() - b.green()) < 24 and abs(a.blue() - b.blue()) < 24

def check():
    if not panels:
        find_items(win.contentItem(), panels)
    img = win.grabWindow()
    dpr = img.devicePixelRatio()
    step = win.property("step")
    bad = []
    for i in range(16):
        p = panels[i]
        c = p.mapToScene(QPointF(p.width() / 2, p.height() / 2))
        got = img.pixelColor(int(c.x() * dpr), int(c.y() * dpr))
        want = palette[(i + step) % 4]
        if not close(got, want):
            bad.append((i, got.name()))
            if got.red() + got.green() + got.blue() < 60:
                stats["black"] += 1
    stats["frames"] += 1
    if bad:
        stats["bad"] += 1
        stats["bad_panels"] += len(bad)
        if stats["saved"] < 5:
            img.save(os.path.join(outdir, "bad-%03d.png" % stats["frames"]))
            stats["saved"] += 1
            print("frame %d step %d bad panels %s" % (stats["frames"], step, bad), flush=True)
    win.setProperty("step", step + 1)

t = QTimer(); t.timeout.connect(check); t.start(50)
QTimer.singleShot(int(secs * 1000), app.quit)
QTimer.singleShot(1000, lambda: None)
app.exec()
print("renderer %s: %d frames checked, %d bad frames, %d bad panels (%d black)" % (
    os.environ.get("QT_QUICK_BACKEND", "gl"), stats["frames"], stats["bad"], stats["bad_panels"], stats["black"]), flush=True)
