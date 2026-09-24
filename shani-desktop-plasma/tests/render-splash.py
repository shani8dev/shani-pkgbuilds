#!/usr/bin/env python3
"""Load a look-and-feel's splash/Splash.qml in the QML engine and grab frames.

KSplash (ksplashqml) loads contents/splash/Splash.qml into a QQuickView and
drives its `stage` property 1..6 as the session starts. This does the same,
headless (QT_QPA_PLATFORM=offscreen, software scenegraph), so a QML error
fails loudly instead of leaving a silent black splash:

  tests/render-splash.py <look-and-feel dir> <out-prefix> [WxH]

Writes <out-prefix>-stage1.png and -stage5.png; exit 1 on any QML error or
an all-black frame. Needs python-pyqt6 and the Kirigami/QtQuick modules the
splash imports (installed with plasma-workspace).
"""
import os
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

from PyQt6.QtCore import QTimer, QUrl, QSize
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQuick import QQuickView

lnf, prefix = sys.argv[1], sys.argv[2]
w, h = (int(v) for v in (sys.argv[3] if len(sys.argv) > 3 else "1920x1080").split("x"))
app = QGuiApplication(sys.argv[:1])
view = QQuickView()
view.setResizeMode(QQuickView.ResizeMode.SizeRootObjectToView)
view.resize(QSize(w, h))
errors = []
view.statusChanged.connect(lambda s: errors.extend(e.toString() for e in view.errors()))
view.setSource(QUrl.fromLocalFile(os.path.join(lnf, "contents/splash/Splash.qml")))
errors.extend(e.toString() for e in view.errors())
if view.rootObject() is None or errors:
    print("QML ERROR:", *errors, sep="\n  ")
    sys.exit(1)
view.show()
root = view.rootObject()
dark = []


def grab(name):
    img = view.grabWindow()
    img.save(f"{prefix}-{name}.png")
    # mean luminance of a sparse sample: all-black means nothing rendered
    lum = sum(img.pixelColor(x, y).lightness() for x in range(0, w, 40) for y in range(0, h, 40))
    dark.append(lum < 3 * (w // 40) * (h // 40) // 100)  # <1% average lightness
    print(f"{prefix}-{name}.png")


QTimer.singleShot(300, lambda: root.setProperty("stage", 1))
QTimer.singleShot(2500, lambda: grab("stage1"))
QTimer.singleShot(2700, lambda: root.setProperty("stage", 5))
QTimer.singleShot(4200, lambda: grab("stage5"))
QTimer.singleShot(4400, app.quit)
app.exec()
if any(dark):
    print("all-black frame")
    sys.exit(1)
