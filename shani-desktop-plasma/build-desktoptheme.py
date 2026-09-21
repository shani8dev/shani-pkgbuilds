#!/usr/bin/env python3
"""Generate the Saturn Plasma desktop theme (widgets/panel-background etc.).

The shell's own chrome — panel, popups, tooltips, plasmoid backgrounds — is
drawn by a desktoptheme, not by Breeze's window decoration or by Kvantum. A
desktoptheme with no SVGs is not neutral: KSvg falls back to the `default`
theme file by file, so the shell keeps Breeze's geometry and only changes
colour. This script draws those surfaces instead: a larger, consistent corner
radius, a hairline border, and — crucially — a `mask-*` element set. KSvg
falls back per FILE, not per element, so every surface shipped here must carry
every element the shell asks of it; a missing id draws nothing at all.

Colours are routed through `currentColor` + `ColorScheme-*` classes rather than
baked, so one set of SVGs serves Saturn (light) and Saturn-Dark (dark): the
per-theme `colors` file resolves the classes. Twilight points at Saturn-Dark to
keep its dark chrome.

Run from the package directory:  python3 build-desktoptheme.py
"""
from __future__ import annotations

import json
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
THEME_ROOT = os.path.join(HERE, "usr/share/plasma/desktoptheme")

R_BIG, R_MED, BW, K = 10, 7, 1, 32
SURFACE = "ColorScheme-Background"
BORDER = "ColorScheme-Text"
MASK = "#ffffff"

# file relative path -> (radius, fill opacity, border opacity, content margin)
SURFACES = {
    "widgets/panel-background.svg": (R_BIG, 0.65, 0.18, 4),
    "dialogs/background.svg": (R_BIG, 0.78, 0.18, 6),
    "widgets/tooltip.svg": (R_MED, 0.78, 0.20, 4),
    "widgets/background.svg": (R_MED, 0.72, 0.15, 6),
}


def _paint(color: str, css: str | None, opacity: float) -> str:
    out = f'fill="{color}"'
    if css:
        out += f' class="{css}"'
    out += f' fill-opacity="{opacity:g}"'
    return out


def _corner(r: int, bw: int, fill, border, fx: int, fy: int):
    parts = [f'<rect x="0" y="0" width="{r}" height="{r}" fill="#000000" fill-opacity="0"/>']
    if fill:
        parts.append(
            f'<path d="M {bw} {r} A {r - bw} {r - bw} 0 0 1 {r} {bw} L {r} {r} Z" {fill}/>'
        )
    if border:
        parts.append(
            f'<path d="M 0 {r} A {r} {r} 0 0 1 {r} 0 L {r} {bw} '
            f'A {r - bw} {r - bw} 0 0 0 {bw} {r} Z" {border}/>'
        )
    transform = ""
    if fx or fy:
        transform = (f' transform="translate({r if fx else 0} {r if fy else 0}) '
                     f'scale({-1 if fx else 1} {-1 if fy else 1})"')
    return f'<g{transform}>{"".join(parts)}</g>', r


def _edge(r: int, bw: int, fill, border, side: str):
    w, h = (K, r) if side in ("top", "bottom") else (r, K)
    parts = [f'<rect x="0" y="0" width="{w}" height="{h}" fill="#000000" fill-opacity="0"/>']
    if fill:
        parts.append(f'<rect x="0" y="0" width="{w}" height="{h}" {fill}/>')
    if border:
        bx, by, bw_, bh = {
            "top": (0, 0, w, bw),
            "bottom": (0, h - bw, w, bw),
            "left": (0, 0, bw, h),
            "right": (w - bw, 0, bw, h),
        }[side]
        parts.append(f'<rect x="{bx}" y="{by}" width="{bw_}" height="{bh}" {border}/>')
    return "".join(parts), (w, h)


class Sheet:
    def __init__(self):
        self.items: list[tuple[str, str, int, int]] = []
        self.ids: set[str] = set()

    def add(self, eid: str, body: str, w: int, h: int) -> None:
        if eid in self.ids:
            raise ValueError(f"duplicate element id: {eid}")
        self.ids.add(eid)
        self.items.append((eid, body, w, h))

    def frame(self, prefix: str, r: int, fill, border, margin: int | None = None) -> None:
        p = f"{prefix}-" if prefix else ""
        for name, (fx, fy) in (
            ("topleft", (0, 0)), ("topright", (1, 0)),
            ("bottomleft", (0, 1)), ("bottomright", (1, 1)),
        ):
            body, size = _corner(r, BW, fill, border, fx, fy)
            self.add(p + name, body, size, size)
        for side in ("top", "bottom", "left", "right"):
            body, (w, h) = _edge(r, BW, fill, border, side)
            self.add(p + side, body, w, h)
        self.add(p + "center", f'<rect x="0" y="0" width="{K}" height="{K}" {fill}/>', K, K)
        if margin is not None:
            for side in ("top", "bottom", "left", "right"):
                self.add(
                    f"{p}hint-{side}-margin",
                    f'<rect x="0" y="0" width="{margin}" height="{margin}" '
                    f'fill="#000000" fill-opacity="0"/>',
                    margin, margin,
                )

    def render(self) -> str:
        pad, x, y, rowh, maxw = 8, 8, 8, 0, 0
        out = []
        for eid, body, w, h in self.items:
            if x + w > 900:
                x, y, rowh = 8, y + rowh + pad, 0
            out.append(f'<g id="{eid}" transform="translate({x} {y})">{body}</g>')
            x += w + pad
            rowh = max(rowh, h)
            maxw = max(maxw, x)
        total_w, total_h = maxw, y + rowh + pad
        head = (
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{total_w}" height="{total_h}" '
            f'viewBox="0 0 {total_w} {total_h}">\n'
            '  <style type="text/css" id="current-color-scheme">\n'
            '    .ColorScheme-Text { color:#231f20; stop-color:#231f20; }\n'
            '    .ColorScheme-Background { color:#eff0f1; stop-color:#eff0f1; }\n'
            '  </style>\n'
        )
        return head + "\n".join(out) + "\n</svg>\n"


def build_sheet(r: int, opacity: float, border_opacity: float, margin: int) -> str:
    s = Sheet()
    fill = _paint("currentColor", SURFACE, opacity)
    border = _paint("currentColor", BORDER, border_opacity)
    s.frame("", r, fill, border, margin=margin)
    # The blur mask: an opaque white copy of the shape. Without it a translucent
    # panel or popup gets no blur behind it.
    mask_fill = _paint(MASK, None, 1.0)
    s.frame("mask", r, mask_fill, None)
    if r == R_BIG and margin == 4:  # the panel also carries a thick variant
        s.frame("thick", r, fill, border, margin=margin)
    return s.render()


def write(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def build_variant(root: str, mode: str) -> None:
    """mode is 'base' (adaptive), 'opaque', 'solid' or 'translucent'."""
    for rel, (r, opacity, border_opacity, margin) in SURFACES.items():
        if mode in ("opaque", "solid"):
            effective = 1.0
        elif mode == "translucent":
            effective = max(opacity - 0.15, 0.45)
        else:
            effective = opacity
        write(os.path.join(root, rel),
              build_sheet(r, effective, border_opacity, margin))


METADATA = {
    "KPlugin": {
        "Authors": [{"Name": "Shani OS", "Email": "shrinivas.v.kumbhar@gmail.com"}],
        "Category": "",
        "Description": "Saturn Plasma style - rounded, translucent shell surfaces "
                       "with proper blur masks",
        "Id": "default",
        "License": "GPL-3.0-or-later",
        "Name": "Saturn",
        "Name[en_GB]": "Saturn",
    },
    "X-Plasma-API": "5.0",
}

# Mirrors Breeze's default/plasmarc: fallback is per FILE, so shipping our own
# plasmarc would otherwise drop these defaults for new activities.
PLASMARC = (
    "[Wallpaper]\n"
    "defaultWallpaperTheme=Next\n"
    "defaultFileSuffix=.png\n"
    "defaultWidth=1920\n"
    "defaultHeight=1080\n"
    "\n"
    "[AdaptiveTransparency]\n"
    "enabled=true\n"
)


def main() -> int:
    for name, scheme in (("Saturn", "Saturn"), ("Saturn-Dark", "SaturnDark")):
        root = os.path.join(THEME_ROOT, name)
        # base (adaptive), opaque, solid, translucent
        build_variant(root, "base")
        for sub in ("opaque", "solid"):
            build_variant(os.path.join(root, sub), sub)
        build_variant(os.path.join(root, "translucent"), "translucent")
        write(os.path.join(root, "metadata.json"), json.dumps(METADATA, indent=4) + "\n")
        write(os.path.join(root, "plasmarc"), PLASMARC)
        shutil.copyfile(
            os.path.join(HERE, "usr/share/color-schemes", f"{scheme}.colors"),
            os.path.join(root, "colors"),
        )
        print(f"built desktoptheme/{name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
