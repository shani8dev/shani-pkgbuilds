"""The Saturn neutral palette, shared by every build-*.py script.

Shani is Saturn: lord of time, the deep-blue (neela) planet, watched over by
his raven, seen here against the night-sky wallpaper. The neutrals follow
that instead of flat grey:

- dark:  greys drift toward a soft night-sky indigo, strongest in the
         backgrounds and fading out toward the (near-white) text, so
         surfaces feel calm without tinting what you read;
- light: greys warm toward cream, strongest in the brightest surfaces, so
         pages read as soft paper, not glaring white.

Only exact greys (r == g == b) are touched, and a tinted colour is never a
grey again, so applying this twice changes nothing. Accent coral and every
other non-grey colour pass through untouched; the few harsh semantic colours
are replaced by SEMANTIC below.
"""
from __future__ import annotations

import re


def tint(v: int, mode: str) -> tuple[int, int, int]:
    """Tinted equivalent of the grey (v, v, v) for mode 'dark' or 'light'."""
    if v == 0:
        return (0, 0, 0)                      # shadows/masks stay true black
    if mode == "dark":
        k = 1 - v / 255                       # 1 at black .. 0 at white
        r, g, b = v - round(4 * k), v - round(5 * k), v + round(14 * k)
    else:
        k = v / 255                           # 0 at black .. 1 at white
        r, g, b = v, v - round(4 * k), v - round(10 * k)
    return tuple(max(0, min(255, c)) for c in (r, g, b))


# Harsh semantic colours -> soothing ones (checked by check-contrast.py).
SEMANTIC = {
    "dark": {(1, 237, 213): (125, 214, 170)},    # neon teal -> soft mint
    "light": {(0, 120, 107): (30, 122, 84)},     # teal -> calm green
}


def _hex_sub(m: re.Match, mode: str) -> str:
    h, alpha = m.group(1), m.group(2) or ""
    rgb = tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    new = SEMANTIC[mode].get(rgb)
    if new is None and rgb[0] == rgb[1] == rgb[2]:
        new = tint(rgb[0], mode)
    if new is None:
        return m.group(0)
    out = "#%02x%02x%02x" % new
    return (out.upper() if h.isupper() else out) + alpha


def apply(text: str, mode: str, rgb_triplets: bool) -> str:
    """Tint every grey in text: '#rrggbb[aa]' always, 'r,g,b' when rgb_triplets."""
    text = re.sub(r"#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?(?![0-9a-fA-F])", lambda m: _hex_sub(m, mode), text)
    if rgb_triplets:
        text = re.sub(r"(?<![\d.])(\d{1,3})(\s*,\s*)(\d{1,3})\2(\d{1,3})(?![\d.,])",
                      lambda m: _rgb3(m, mode), text)
    return text


def _rgb3(m: re.Match, mode: str) -> str:
    rgb = (int(m.group(1)), int(m.group(3)), int(m.group(4)))
    if max(rgb) > 255:
        return m.group(0)
    sep = m.group(2)
    new = SEMANTIC[mode].get(rgb)
    if new is None and rgb[0] == rgb[1] == rgb[2]:
        new = tint(rgb[0], mode)
    return m.group(0) if new is None else f"{new[0]}{sep}{new[1]}{sep}{new[2]}"
