#!/usr/bin/env python3
"""Generate each look-and-feel's splash background from its wallpaper.

The splash shows the look's own wallpaper frosted like the shell's blurred
glass. The blur is baked here (Gaussian, like KWin's blur behind a panel)
instead of done at boot with a QML shader effect: no runtime dependency, and
nothing to fail on the one screen that must never be blank. Splash.qml is
identical in all three looks; only images/ differ.

  python3 build-splash.py          (needs python-pillow)
"""
from __future__ import annotations

import os
import shutil

from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
LNF = os.path.join(HERE, "usr/share/plasma/look-and-feel")
WALL = os.path.join(HERE, "usr/share/wallpapers/Saturn/contents")
VARIANTS = {"Saturn": "images", "Saturn-Dark": "images_dark", "Saturn-Twilight": "images_twilight"}
SIZE = (1920, 1080)
# The vivid logo reads on every (dimmed) backdrop; Saturn-Dark's copy is canonical.
LOGO_SRC = "Saturn-Dark"


def main() -> int:
    src_qml = os.path.join(LNF, LOGO_SRC, "contents/splash/Splash.qml")
    for lnf, variant in VARIANTS.items():
        splash = os.path.join(LNF, lnf, "contents/splash")
        img = Image.open(os.path.join(WALL, variant, "1920x1080.png")).convert("RGB").resize(SIZE)
        img = img.filter(ImageFilter.GaussianBlur(28))
        img.save(os.path.join(splash, "images/background.png"), optimize=True)
        if lnf != LOGO_SRC:
            for rel in ("images/shanilogo.png", "Splash.qml"):
                shutil.copyfile(os.path.join(LNF, LOGO_SRC, "contents/splash", rel), os.path.join(splash, rel))
        print(f"built look-and-feel/{lnf}/contents/splash")
    assert src_qml
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
