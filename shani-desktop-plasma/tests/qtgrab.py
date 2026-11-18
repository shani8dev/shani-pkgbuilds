#!/usr/bin/env python3
"""Wayland screenshot: KWin's ScreenShot2 CaptureScreen over the session bus.

Replaces tests/qtgrab.cpp (its reply demarshalling was never reliable). On
KWin 6.8's virtual output CaptureActiveScreen returns an all-black buffer, so
ask for the screen by name - discovered from CaptureActiveScreen's metadata
("Placeholder-1" in the headless harness). The fd argument is a pipe: KWin
writes raw RGBX8888 and closes it; read until stride*height bytes (a memfd
can read EOF while the writer is still working).
"""

import os
import sys
import time

import dbus

out = sys.argv[1]

bus = dbus.SessionBus()
iface = dbus.Interface(
    bus.get_object("org.kde.KWin", "/org/kde/KWin/ScreenShot2"),
    "org.kde.KWin.ScreenShot2",
)


def drain(fd, want):
    data = b""
    empty = 0
    while len(data) < want and empty < 60:
        chunk = os.read(fd, want - len(data))
        if not chunk:
            empty += 1
            time.sleep(0.1)
            continue
        empty = 0
        data += chunk
    return data


def size_of(meta):
    return int(meta["stride"]) * int(meta["height"])


# First capture only tells us the screen's name; its pixels are black.
probe_r, probe_w = os.pipe()
probe_meta = iface.CaptureActiveScreen({}, dbus.types.UnixFd(probe_w))
os.close(probe_w)
drain(probe_r, size_of(probe_meta))
os.close(probe_r)
screen = str(probe_meta["screen"])

r, w = os.pipe()
meta = iface.CaptureScreen(dbus.String(screen), {}, dbus.types.UnixFd(w))
os.close(w)
width, height, stride = (int(meta[k]) for k in ("width", "height", "stride"))
data = drain(r, stride * height)
os.close(r)
if len(data) != stride * height:
    sys.exit(f"incomplete capture: {len(data)} of {stride * height} bytes")
raw = out + ".raw"
with open(raw, "wb") as f:
    f.write(data)
if (
    os.system(f"convert -size {width}x{height} -depth 8 rgba:{raw} -alpha off {out}")
    == 0
):
    os.remove(raw)
