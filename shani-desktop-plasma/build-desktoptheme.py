#!/usr/bin/env python3
"""Assemble the Saturn Plasma styles from Utterly-Round.

The shell's own chrome - panel, popups, tooltips, task manager, buttons,
tabs, scrollbars, calendar, plasmoid headings - is drawn by a desktoptheme.
KSvg falls back to Breeze file by file, so a theme that ships only a few
surfaces leaves the rest of the shell stock Breeze. Saturn therefore uses a
complete, rounded, blur-masked upstream style, Utterly-Round by Himprakash
Deka (GPL-2.0-or-later, https://github.com/HimDek/Utterly-Round-Plasma-Style),
whose SVGs draw with ColorScheme-* classes: the per-theme `colors` file
(copied from Saturn's colour schemes) makes it coral-accented, light or dark.

Layout written:
  Saturn/       Utterly-Round translucent edition (+ the Solid edition's
                `solid/` variant, used for opaque-mode panels), Saturn's
                metadata.json, plasmarc and colors (Saturn.colors)
  Saturn-Dark/  the same artwork via relative symlinks, its own metadata,
                plasmarc and colors (SaturnDark.colors)

  python3 build-desktoptheme.py [path/to/Utterly-Round-Plasma-Style]

Without a path it clones UPSTREAM at the pinned COMMIT into a temp dir.
"""
from __future__ import annotations

import gzip
import json
import re
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
THEME_ROOT = os.path.join(HERE, "usr/share/plasma/desktoptheme")
UPSTREAM = "https://github.com/HimDek/Utterly-Round-Plasma-Style"
COMMIT = "7e011c19382f8afa99daac3226828ce82eaf4f13"

# Artwork taken from the translucent edition (everything but its metadata).
ART = ("dialogs", "widgets", "opaque", "translucent", "icons", "weather")
# Stray duplicate in upstream, not referenced by anything.
SKIP = {"translucentbackground copy.svgz"}


def metadata(theme_id: str, name: str, description: str) -> dict:
    return {
        "KPackageStructure": "Plasma/Theme",
        "KPlugin": {
            "Authors": [
                {"Name": "Shani OS", "Email": "shrinivas.v.kumbhar@gmail.com"},
                {"Name": "Himprakash Deka (Utterly-Round)", "Email": "info@himdek.com"},
            ],
            "Category": "",
            "Description": description,
            # The directory name, the KPackage convention. (Plasma resolves the
            # style by directory either way - "default" also loaded fine.)
            "Id": theme_id,
            "License": "GPL-2.0-or-later",
            "Name": name,
            "Version": "2.1-saturn",
        },
        "X-Plasma-API": "5.0",
    }


# Fallback is per FILE, so this replaces Breeze's plasmarc entirely. The
# image wallpaper plugin shows [Wallpaper] defaultWallpaperTheme when no image
# is configured - i.e. on every new desktop - so it must name Saturn (whose
# images_dark/ Plasma picks for dark colour schemes), not Breeze's "Next".
PLASMARC = (
    "[Wallpaper]\n"
    "defaultWallpaperTheme=Saturn\n"
    "defaultFileSuffix=.png\n"
    "defaultWidth=1920\n"
    "defaultHeight=1080\n"
    "\n"
    "[AdaptiveTransparency]\n"
    "enabled=true\n"
    "\n"
    "# KWin's background-contrast behind blurred shell surfaces: keeps text\n"
    "# legible on busy wallpapers without making the glass opaque.\n"
    "[ContrastEffect]\n"
    "enabled=true\n"
    "contrast=0.2\n"
    "intensity=0.6\n"
    "saturation=1.7\n"
)


def write(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def copy_tree(src: str, dst: str) -> None:
    shutil.copytree(src, dst, ignore=lambda _d, names: [n for n in names if n in SKIP])


# Desktop widgets can't get KWin blur: they're drawn inside the desktop
# window (libplasma requests BlurBehind only for panel/popup windows; the
# desktop containment has no blur). So give them a frosted look instead - a
# denser translucent fill that turns the wallpaper behind into soft glass
# rather than a sharp busy image - and make Utterly-Round's clock face, drawn
# fully opaque, match. The opaque/ and solid/ variants (no compositing) stay.
FROST = 0.78
FROSTED = {
    "widgets/background.svgz": "background",
    "translucent/widgets/background.svgz": "background",
    "widgets/clock.svgz": "clockface",
}


def frost(theme_dir: str) -> None:
    for rel, kind in FROSTED.items():
        path = os.path.join(theme_dir, rel)
        with open(path, "rb") as f:
            svg = gzip.decompress(f.read()).decode("utf-8")
        if kind == "background":
            # only the scheme-coloured fill pieces (0.6), never the shadows
            svg, n = re.subn(r'(class="ColorScheme-Background"\s+opacity=")(?:0\.6|\.6)"',
                             rf'\g<1>{FROST}"', svg)
        else:
            i = svg.index('id="ClockFace"')
            head, tail = svg[:i], svg[i:]
            tail, n = re.subn(r"opacity:1;fill:currentColor", f"opacity:{FROST};fill:currentColor", tail, count=1)
            svg = head + tail
        if n == 0:
            raise SystemExit(f"frost: nothing matched in {rel} - upstream artwork changed?")
        with open(path, "wb") as f:
            f.write(gzip.compress(svg.encode("utf-8"), mtime=0))


def reset(path: str) -> None:
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def build(upstream: str) -> None:
    trans = os.path.join(upstream, "desktoptheme/translucent")
    solid = os.path.join(upstream, "desktoptheme/solid/solid")
    saturn = os.path.join(THEME_ROOT, "Saturn")
    dark = os.path.join(THEME_ROOT, "Saturn-Dark")
    for theme in (saturn, dark):
        reset(theme)
        os.makedirs(theme)

    for d in ART:
        copy_tree(os.path.join(trans, d), os.path.join(saturn, d))
    copy_tree(solid, os.path.join(saturn, "solid"))
    frost(saturn)
    shutil.copyfile(os.path.join(upstream, "LICENSE.md"), os.path.join(saturn, "LICENSE.md"))
    for entry in (*ART, "solid", "LICENSE.md"):
        os.symlink(os.path.join("..", "Saturn", entry), os.path.join(dark, entry))

    for theme, name, scheme, desc in (
        (saturn, "Saturn", "Saturn", "Saturn light Plasma style: rounded, blurred, translucent (Utterly-Round)"),
        (dark, "Saturn Dark", "SaturnDark", "Saturn dark Plasma style: rounded, blurred, translucent (Utterly-Round)"),
    ):
        write(os.path.join(theme, "metadata.json"),
              json.dumps(metadata(os.path.basename(theme), name, desc), indent=4) + "\n")
        write(os.path.join(theme, "plasmarc"), PLASMARC)
        shutil.copyfile(os.path.join(HERE, "usr/share/color-schemes", f"{scheme}.colors"),
                        os.path.join(theme, "colors"))
        print(f"built {os.path.relpath(theme, HERE)}")


def main(argv: list[str]) -> int:
    if len(argv) > 1:
        build(os.path.abspath(argv[1]))
        return 0
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["git", "clone", "-q", UPSTREAM, tmp], check=True)
        subprocess.run(["git", "-C", tmp, "checkout", "-q", COMMIT], check=True)
        build(tmp)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
