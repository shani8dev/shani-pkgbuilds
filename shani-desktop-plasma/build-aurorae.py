#!/usr/bin/env python3
"""Generate the Saturn window decorations (Aurorae v2 themes).

Breeze's window corners are hard-coded (~5 px) and look sharp next to the
rounded Saturn shell (Utterly-Round, 12-16 px). Utterly-Round's own Aurorae
decoration has the right shape but no shadow: Aurorae's shadow IS whatever
the `decoration` frame paints in its padding (aurorae v2 updateShadow), and
Utterly paints a flat band there. So Saturn draws its own, in the same
language as the shell:

- 12 px rounded corners on all four sides (a slim 6 px frame round the
  client carries the bottom ones), a 1 px hairline edge;
- a soft drop shadow in the 24 px padding (the frame's outer ring);
- title bar in the colour scheme's Header colours (.ColorScheme-Header*),
  so it merges with app toolbars like Breeze, light or dark automatically,
  slightly translucent with a mask-* frame so KWin blurs behind it;
- every KWin button: close / minimize / maximize as calm traffic lights in
  the SHANI logo's red and amber plus mint (glyphs appear on hover), and
  on-all-desktops / keep-above / keep-below / shade / help as quiet glyph
  buttons that turn coral while toggled on. The window-menu button is the
  app's own icon (no menu.svg: Aurorae then draws the icon).

Two themes only because the title text colour is fixed per theme:
Saturn (light) and Saturn-Dark.

  python3 build-aurorae.py
"""
from __future__ import annotations

import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "usr/share/aurorae/themes")

P = 24          # shadow padding on every side
R = 12          # top corner radius
K = 32          # length of stretchable edge pieces
B = 16          # button size
F = 6           # frame round the client (sides, bottom): carries the rounded bottom corners

CLOSE, MINIMIZE, MAXIMIZE = "#ef4136", "#fbb040", "#7dd6aa"   # logo red, logo amber, mint
CORAL = "#ff7f50"

THEMES = {
    # name: (display name, shadow alpha active/inactive, hairline, text active/inactive)
    "Saturn": ("Saturn", (0.22, 0.12), ("#000000", 0.10), ("35,38,39", "120,122,125")),
    "Saturn-Dark": ("Saturn Dark", (0.42, 0.24), ("#ffffff", 0.08), ("222,222,225", "153,153,160")),
}

STYLE = ('<style type="text/css" id="current-color-scheme">'
         '.ColorScheme-HeaderBackground{color:#2d2c3b;}'
         '.ColorScheme-HeaderText{color:#dedee1;}'
         '</style>')


def svg(w: float, h: float, body: str) -> str:
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">\n'
            f'{STYLE}\n{body}\n</svg>\n')


def stops(alpha: float, start: float) -> str:
    """Shadow falloff: `alpha` at the window edge (offset `start`), 0 at the rim."""
    pts = [(start, alpha), (start + (1 - start) * 0.35, alpha * 0.45),
           (start + (1 - start) * 0.70, alpha * 0.12), (1.0, 0.0)]
    if start > 0:
        pts.insert(0, (0.0, 0.0))
        pts.insert(1, (start - 1e-4, 0.0))
    return "".join(f'<stop offset="{o:.4f}" stop-color="#000000" stop-opacity="{a:.4f}"/>' for o, a in pts)


class Sheet:
    """Elements laid out in a row; each <g id=...> holds one frame piece."""

    def __init__(self) -> None:
        self.parts: list[str] = []
        self.defs: list[str] = []
        self.x = 0.0
        self.h = 0.0

    def add(self, eid: str, w: float, h: float, body: str) -> None:
        # a transparent rect pins the element's bounds to exactly w x h
        self.parts.append(f'<g id="{eid}" transform="translate({self.x} 0)">'
                          f'<rect width="{w}" height="{h}" fill="#000000" fill-opacity="0"/>{body}</g>')
        self.x += w + 4
        self.h = max(self.h, h)

    def grad(self, gid: str, kind: str, attrs: str, alpha: float, start: float) -> str:
        self.defs.append(f'<{kind}Gradient id="{gid}" gradientUnits="userSpaceOnUse" {attrs}>'
                         f'{stops(alpha, start)}</{kind}Gradient>')
        return f"url(#{gid})"

    def render(self) -> str:
        return svg(self.x, self.h, "<defs>" + "".join(self.defs) + "</defs>\n" + "\n".join(self.parts))


def frame(sheet: Sheet, prefix: str, shadow: float, hairline: tuple[str, float],
          fill_opacity: float, mask: bool = False) -> None:
    """One 9-patch: shadow ring in the padding, header fill inside."""
    c = P + R
    fill = ('fill="#000000"' if mask else
            f'fill="currentColor" class="ColorScheme-HeaderBackground" fill-opacity="{fill_opacity}"')
    hl_col, hl_a = hairline
    # hairlines are filled 1 px shapes, never strokes: a stroke spills half a
    # pixel past the piece, FrameSvg reads margins from element bounds, and
    # QtSvg (SVG Tiny) has no clipPath to contain it -> visible seams
    hl = "" if mask else f'fill="{hl_col}" fill-opacity="{hl_a}"'

    def grad_rect(gid, w, h, kind, attrs, start):
        if mask:
            return ""
        return f'<rect width="{w}" height="{h}" fill="{sheet.grad(prefix + gid, kind, attrs, shadow, start)}"/>'

    def piece(name, w, h, body):
        sheet.add(f"{prefix}-{name}", w, h, body)

    def corner(gid):
        """A rounded corner in top-left orientation: radial shadow round the
        arc, quarter-disc fill, ring hairline."""
        sh = grad_rect(gid, c, c, "radial", f'cx="{c}" cy="{c}" r="{c}"', R / c)
        arc = f'<path d="M {P} {c} A {R} {R} 0 0 1 {c} {P} L {c} {c} Z" {fill}/>'
        ring = "" if mask else (f'<path d="M {P - 1} {c} A {R + 1} {R + 1} 0 0 1 {c} {P - 1} '
                                f'L {c} {P} A {R} {R} 0 0 0 {P} {c} Z" {hl}/>')
        return sh + arc + ring

    def edge(gid):
        """A straight edge in top orientation: shadow, then R px of fill."""
        return (grad_rect(gid, K, c, "linear", f'x1="0" y1="{P}" x2="0" y2="0"', 0)
                + f'<rect y="{P}" width="{K}" height="{R}" {fill}/>'
                + ("" if mask else f'<rect y="{P - 1}" width="{K}" height="1" {hl}/>'))

    # All four corners are rounded. The bottom row mirrors the top: its R px
    # of fill plus the frame's BorderBottom/BorderLeft/BorderRight (rc) form
    # a slim header-coloured frame round the client, whose outer corners
    # carry the curve - Aurorae never reports a radius to KWin
    # (setBorderRadius), so KWin can't clip the client itself.
    hflip, vflip = f'translate({c} 0) scale(-1 1)', f'translate(0 {c}) scale(1 -1)'
    for name, t in (("topleft", ""), ("topright", hflip),
                    ("bottomleft", vflip), ("bottomright", f"translate({c} {c}) scale(-1 -1)")):
        piece(name, c, c, f'<g transform="{t}">{corner(name)}</g>' if t else corner(name))
    piece("top", K, c, edge("top"))
    piece("bottom", K, c, f'<g transform="{vflip}">{edge("bottom")}</g>')
    # left / right edges are as thick as the corners (c = P + R): FrameSvg
    # takes each side's margin from one piece and expects corner and edge to
    # match (a 24 px edge beside a 36 px corner once made the top-right
    # corner stick 12 px out). The inner R px is fill, under the client
    # except the rc's border width.
    piece("left", c, K, grad_rect("left", P, K, "linear", f'x1="{P}" y1="0" x2="0" y2="0"', 0)
          + f'<rect x="{P}" width="{R}" height="{K}" {fill}/>'
          + ("" if mask else f'<rect x="{P - 1}" width="1" height="{K}" {hl}/>'))
    piece("right", c, K, f'<g transform="{hflip}">'
          + grad_rect("right", P, K, "linear", f'x1="{P}" y1="0" x2="0" y2="0"', 0)
          + f'<rect x="{P}" width="{R}" height="{K}" {fill}/>'
          + ("" if mask else f'<rect x="{P - 1}" width="1" height="{K}" {hl}/>') + '</g>')
    piece("center", K, K, f'<rect width="{K}" height="{K}" {fill}/>')


def decoration(shadow: tuple[float, float], hairline: tuple[str, float]) -> str:
    sheet = Sheet()
    frame(sheet, "decoration", shadow[0], hairline, 0.94)
    frame(sheet, "decoration-inactive", shadow[1], hairline, 0.94)
    frame(sheet, "mask", 0, hairline, 1, mask=True)
    return sheet.render()


# ---- buttons ---------------------------------------------------------------

GLYPH = {
    "close": "M5.3 5.3 L10.7 10.7 M10.7 5.3 L5.3 10.7",
    "minimize": "M4.8 8 H11.2",
    # filled (F:) triangles, as macOS: pointing out = maximize, in = restore
    "maximize": "F:M4.9 4.9 H9.6 L4.9 9.6 Z M11.1 11.1 H6.4 L11.1 6.4 Z",
    "restore": "F:M7.6 7.6 V3.9 L3.9 7.6 Z M8.4 8.4 V12.1 L12.1 8.4 Z",
    "alldesktops": "M8 8.8 V12 M6 6.6 A2 2 0 1 1 10 6.6 A2 2 0 1 1 6 6.6",
    "keepabove": "M5 9.6 L8 6.6 L11 9.6",
    "keepbelow": "M5 6.4 L8 9.4 L11 6.4",
    "shade": "M5 5.6 H11 M5 8.2 H11 M6.5 10.8 H9.5",
    "help": "M6.3 6.4 A1.8 1.8 0 1 1 8.9 7.9 C8.2 8.3 8 8.7 8 9.5 M8 11.6 V11.7",
}
TRAFFIC = {"close": CLOSE, "minimize": MINIMIZE, "maximize": MAXIMIZE, "restore": MAXIMIZE}


def circle(fill: str, opacity: float, cls: str = "") -> str:
    c = f' class="{cls}"' if cls else ""
    return f'<circle cx="8" cy="8" r="6.5" fill="{fill}"{c} fill-opacity="{opacity}"/>'


def glyph(name: str, color: str, opacity: float, cls: str = "") -> str:
    c = f' class="{cls}"' if cls else ""
    d = GLYPH[name]
    if d.startswith("F:"):
        return f'<path d="{d[2:]}" fill="{color}"{c} fill-opacity="{opacity}"/>'
    return (f'<path d="{d}" fill="none" stroke="{color}"{c} stroke-opacity="{opacity}" '
            'stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>')


def button(name: str) -> str:
    text = "ColorScheme-HeaderText"
    if name in TRAFFIC:
        col, ink = TRAFFIC[name], "#2a1610"
        states = {
            "active": circle(col, 1),
            "hover": circle(col, 1) + glyph(name, ink, 0.75),
            "pressed": circle(col, 0.7) + glyph(name, ink, 0.85),
            "inactive": circle("currentColor", 0.22, text),
            "hover-inactive": circle(col, 1) + glyph(name, ink, 0.75),
            "deactivated": circle("currentColor", 0.12, text),
            "deactivated-inactive": circle("currentColor", 0.10, text),
        }
    else:
        states = {
            "active": glyph(name, "currentColor", 0.70, text),
            "hover": circle("currentColor", 0.12, text) + glyph(name, "currentColor", 0.95, text),
            # pressed is also "toggled on" (pinned, kept above, shaded...)
            "pressed": circle(CORAL, 1) + glyph(name, "#2a1610", 0.85),
            "inactive": glyph(name, "currentColor", 0.35, text),
            "hover-inactive": circle("currentColor", 0.12, text) + glyph(name, "currentColor", 0.9, text),
            "pressed-inactive": circle(CORAL, 0.55) + glyph(name, "#2a1610", 0.7),
            "deactivated": glyph(name, "currentColor", 0.18, text),
        }
    parts, x = [], 0
    for state, body in states.items():
        parts.append(f'<g id="{state}-center" transform="translate({x} 0)">'
                     f'<rect width="{B}" height="{B}" fill="#000000" fill-opacity="0"/>{body}</g>')
        x += B + 4
    return svg(x, B, "\n".join(parts))


def rc(texts: tuple[str, str]) -> str:
    return f"""[General]
ActiveTextColor={texts[0]}
InactiveTextColor={texts[1]}
Animation=150
TitleAlignment=Center
TitleVerticalAlignment=Center
UseTextShadow=false
Shadow=true
LeftButtons=XIA
RightButtons=SFBLHM

[Layout]
BorderLeft={F}
BorderRight={F}
BorderBottom={F}
BorderTop=0
TitleEdgeTop=7
TitleEdgeBottom=7
TitleEdgeLeft=10
TitleEdgeRight=10
TitleEdgeTopMaximized=4
TitleEdgeBottomMaximized=4
TitleEdgeLeftMaximized=8
TitleEdgeRightMaximized=8
TitleBorderLeft=8
TitleBorderRight=8
TitleHeight=22
ButtonWidth={B}
ButtonHeight={B}
ButtonMarginTop=3
ButtonMarginTopMaximized=3
ButtonSpacing=8
ExplicitButtonSpacer=12
PaddingLeft={P}
PaddingRight={P}
PaddingTop={P}
PaddingBottom={P}
"""


def main() -> int:
    for name, (display, shadow, hairline, texts) in THEMES.items():
        d = os.path.join(OUT, name)
        os.makedirs(d, exist_ok=True)
        files = {"decoration.svg": decoration(shadow, hairline), f"{name}rc": rc(texts)}
        for b in GLYPH:
            files[f"{b}.svg"] = button(b)
        files["metadata.desktop"] = (
            "[Desktop Entry]\n"
            f"Name={display}\n"
            "Comment=Saturn window decoration: rounded, shadowed, follows the colour scheme\n"
            f"X-KDE-PluginInfo-Name={name}\n"
            "X-KDE-PluginInfo-Author=Shani OS\n"
            "X-KDE-PluginInfo-Email=shrinivas.v.kumbhar@gmail.com\n"
            "X-KDE-PluginInfo-License=GPL-3.0-or-later\n"
            "X-KDE-PluginInfo-Version=1.0\n")
        for fn, text in files.items():
            with open(os.path.join(d, fn), "w", encoding="utf-8") as f:
                f.write(text)
        print(f"built aurorae/themes/{name} ({len(files)} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
