#!/usr/bin/env python3
"""Generate the Saturn Yakuake skins (Saturn and Saturn-Dark).

Yakuake's skin format (app/skin.cpp upstream) is small and exact: a title
bar with [Border], [Text], [Background] (tiled centre + left/right corners,
whose alpha also shapes the window) and exactly three buttons -
[FocusButton] (keep open, checkable), [ConfigButton] (menu), [QuitButton] -
and a tab bar with tab images, [PlusButton] and [MinusButton]. Buttons are
anchored from the right edge unless `anchor=left`. Images are plain
pictures (no KSvg colour classes), so each skin carries its colours: they
are read here from the Saturn colour schemes' Header group, the same colours
as the window decoration's title bar, so the skins can't drift from the
palette.

Look: the title bar is the bottom edge of the drop-down, rounded like the
Saturn windows (12 px); the selected tab is a soft coral pill; buttons are
quiet glyphs that gain a circle on hover, quit turns logo-red, and keep-open
turns coral while on.

  python3 build-yakuake.py
"""
from __future__ import annotations

import configparser
import json
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "usr/share/yakuake/skins")
SCHEMES = os.path.join(HERE, "usr/share/color-schemes")
SKINS = {"Saturn": "Saturn.colors", "Saturn-Dark": "SaturnDark.colors"}

CORAL, RED, INK = "#ff7f50", "#ef4136", "#2a1610"
R = 12            # rounded bottom corners of the drop-down
TITLE_H, TAB_H, BTN = 30, 32, 24

GLYPH = {
    "pin": "M12 12.8 V17 M9.4 9.6 A2.6 2.6 0 1 1 14.6 9.6 A2.6 2.6 0 1 1 9.4 9.6",
    "menu": "M7.5 8.5 H16.5 M7.5 12 H16.5 M7.5 15.5 H16.5",
    "close": "M8.4 8.4 L15.6 15.6 M15.6 8.4 L8.4 15.6",
    "plus": "M12 7.5 V16.5 M7.5 12 H16.5",
    "lock": "M3.5 6 H8.5 V10 H3.5 Z M4.6 6 V4.6 A1.4 1.4 0 0 1 7.4 4.6 V6",
}


def scheme(path: str) -> dict[str, str]:
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str
    cp.read(path)
    h = cp["Colors:Header"]

    def hexc(key: str) -> str:
        return "#%02x%02x%02x" % tuple(int(v) for v in h[key].split(",")[:3])
    return {"bg": hexc("BackgroundNormal"), "fg": hexc("ForegroundNormal"),
            "fg_rgb": [v.strip() for v in h["ForegroundNormal"].split(",")[:3]]}


def svg(w: int, h: int, body: str) -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="0 0 {w} {h}">{body}</svg>\n')


def glyph(name: str, color: str, alpha: float, width: float = 1.6) -> str:
    return (f'<path d="{GLYPH[name]}" fill="none" stroke="{color}" stroke-opacity="{alpha}" '
            f'stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"/>')


def circle(color: str, alpha: float) -> str:
    return f'<circle cx="12" cy="12" r="11" fill="{color}" fill-opacity="{alpha}"/>'


def build(name: str, c: dict[str, str]) -> None:
    d = os.path.join(OUT, name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(os.path.join(d, "title"))
    os.makedirs(os.path.join(d, "tabs"))
    bg, fg = c["bg"], c["fg"]
    files: dict[str, str] = {}

    # ---- title bar (bottom edge of the drop-down) ----
    edge = f'<rect width="100%" height="1" fill="{fg}" fill-opacity="0.08"/>'
    files["title/back.svg"] = svg(1, TITLE_H, f'<rect width="1" height="{TITLE_H}" fill="{bg}"/>' + edge)
    left = f'<path d="M0 0 H{R + 2} V{TITLE_H} H{R} A{R} {R} 0 0 1 0 {TITLE_H - R} Z" fill="{bg}"/>'
    files["title/left.svg"] = svg(R + 2, TITLE_H, left + edge)
    files["title/right.svg"] = svg(R + 2, TITLE_H, f'<g transform="translate({R + 2} 0) scale(-1 1)">{left}</g>' + edge)
    # Button images are opaque in the bar's own colour: with Translucency on,
    # a transparent pixel in a button shows the desktop through it (the
    # buttons don't inherit the bar's painted background) - a visible box.
    base = f'<rect width="{BTN}" height="{BTN}" fill="{bg}"/>'
    for key, g in (("focus", "pin"), ("config", "menu"), ("quit", "close")):
        files[f"title/{key}_up.svg"] = svg(BTN, BTN, base + glyph(g, fg, 0.70))
        if key == "quit":
            files["title/quit_over.svg"] = svg(BTN, BTN, base + circle(RED, 1) + glyph(g, "#ffffff", 0.95))
            files["title/quit_down.svg"] = svg(BTN, BTN, base + circle(RED, 0.75) + glyph(g, "#ffffff", 0.95))
        else:
            files[f"title/{key}_over.svg"] = svg(BTN, BTN, base + circle(fg, 0.12) + glyph(g, fg, 0.95))
            # down doubles as "checked" for the keep-open toggle
            files[f"title/{key}_down.svg"] = svg(BTN, BTN, base + circle(CORAL, 1) + glyph(g, INK, 0.85))

    # ---- tab bar ----
    files["tabs/back_image.svg"] = svg(1, TAB_H, f'<rect width="1" height="{TAB_H}" fill="{bg}"/>')
    files["tabs/left_corner.svg"] = svg(1, TAB_H, f'<rect width="1" height="{TAB_H}" fill="{bg}"/>')
    files["tabs/right_corner.svg"] = svg(1, TAB_H, f'<rect width="1" height="{TAB_H}" fill="{bg}"/>')
    pill_top, pill_h, pr = 5, 22, 11
    pill = f'fill="{CORAL}" fill-opacity="0.20"'
    files["tabs/selected_back.svg"] = svg(1, TAB_H, f'<rect width="1" height="{TAB_H}" fill="{bg}"/>'
                                          f'<rect y="{pill_top}" width="1" height="{pill_h}" {pill}/>')
    half = (f'<rect width="{pr}" height="{TAB_H}" fill="{bg}"/>'
            f'<path d="M{pr} {pill_top} A{pr} {pr} 0 0 0 {pr} {pill_top + pill_h} Z" {pill}/>')
    files["tabs/selected_left.svg"] = svg(pr, TAB_H, half)
    files["tabs/selected_right.svg"] = svg(pr, TAB_H, f'<g transform="translate({pr} 0) scale(-1 1)">{half}</g>')
    files["tabs/unselected_back.svg"] = svg(1, TAB_H, f'<rect width="1" height="{TAB_H}" fill="{bg}"/>')
    files["tabs/unselected_side.svg"] = svg(pr, TAB_H, f'<rect width="{pr}" height="{TAB_H}" fill="{bg}"/>')
    files["tabs/separator.svg"] = svg(1, TAB_H, f'<rect width="1" height="{TAB_H}" fill="{bg}"/>'
                                      f'<rect y="10" width="1" height="12" fill="{fg}" fill-opacity="0.14"/>')
    files["tabs/lock.svg"] = svg(12, 12, glyph("lock", fg, 0.8, 1.2))
    for key, g in (("add", "plus"), ("close", "close")):
        files[f"tabs/{key}_up.svg"] = svg(BTN, BTN, base + glyph(g, fg, 0.70))
        files[f"tabs/{key}_over.svg"] = svg(BTN, BTN, base + circle(fg, 0.12) + glyph(g, fg, 0.95))
        files[f"tabs/{key}_down.svg"] = svg(BTN, BTN, base + circle(CORAL, 1) + glyph(g, INK, 0.85))

    r, g_, b = c["fg_rgb"]
    btn_y = (TITLE_H - BTN) // 2
    files["title.skin"] = f"""[Description]
Skin={name}
Author=Shani OS
Email=shrinivas.v.kumbhar@gmail.com
Icon=/icon.svg

[Border]
red={r}
green={g_}
blue={b}
width=0

[Text]
x=18
y=20
red={r}
green={g_}
blue={b}
text=
bold=false
centered=true

[Background]
back_image=/title/back.svg
left_corner=/title/left.svg
right_corner=/title/right.svg

[FocusButton]
x={16 + 3 * (BTN + 4)}
y={btn_y}
up_image=/title/focus_up.svg
over_image=/title/focus_over.svg
down_image=/title/focus_down.svg

[ConfigButton]
x={16 + 2 * (BTN + 4)}
y={btn_y}
up_image=/title/config_up.svg
over_image=/title/config_over.svg
down_image=/title/config_down.svg

[QuitButton]
x={16 + BTN + 4}
y={btn_y}
up_image=/title/quit_up.svg
over_image=/title/quit_over.svg
down_image=/title/quit_down.svg
"""
    tab_y = (TAB_H - BTN) // 2
    files["tabs.skin"] = f"""[Description]
Skin={name}
Author=Shani OS
Email=shrinivas.v.kumbhar@gmail.com
Icon=/icon.svg

[Tabs]
x={8 + BTN + 6}
y=0
red={r}
green={g_}
blue={b}
selected_text_bold=false
separator_image=/tabs/separator.svg
selected_background=/tabs/selected_back.svg
selected_left_corner=/tabs/selected_left.svg
selected_right_corner=/tabs/selected_right.svg
unselected_background=/tabs/unselected_back.svg
unselected_left_corner=/tabs/unselected_side.svg
unselected_right_corner=/tabs/unselected_side.svg
prevent_closing_image=/tabs/lock.svg
prevent_closing_image_x=4
prevent_closing_image_y=10

[Background]
back_image=/tabs/back_image.svg
left_corner=/tabs/left_corner.svg
right_corner=/tabs/right_corner.svg

[PlusButton]
x=8
y={tab_y}
up_image=/tabs/add_up.svg
over_image=/tabs/add_over.svg
down_image=/tabs/add_down.svg

[MinusButton]
x={8 + BTN}
y={tab_y}
up_image=/tabs/close_up.svg
over_image=/tabs/close_over.svg
down_image=/tabs/close_down.svg
"""
    display = "Saturn Dark" if name.endswith("Dark") else "Saturn"
    files["metadata.desktop"] = f"""[Desktop Entry]
Type=Service
ServiceTypes=Yakuake/Skin
Name={display}
Comment=Saturn skin for Yakuake: rounded, coral tab pill, the Saturn palette
X-KDE-PluginInfo-Author=Shani OS
X-KDE-PluginInfo-Email=shrinivas.v.kumbhar@gmail.com
X-KDE-PluginInfo-Name={name}
X-KDE-PluginInfo-Version=2.0
X-KDE-PluginInfo-License=GPL-3.0-or-later
X-KDE-PluginInfo-EnabledByDefault=true
"""
    files["metadata.json"] = json.dumps({"KPlugin": {
        "Authors": [{"Email": "shrinivas.v.kumbhar@gmail.com", "Name": "Shani OS"}],
        "Category": "", "Dependencies": [], "EnabledByDefault": True,
        "Description": "Saturn skin for Yakuake: rounded, coral tab pill, the Saturn palette",
        "Id": name, "License": "GPL-3.0-or-later", "Name": display, "Version": "2.0",
        "Website": "https://shani.dev"}}, indent=4) + "\n"
    files["icon.svg"] = svg(24, 24, circle(CORAL, 1) + glyph("menu", INK, 0.85))
    for rel, text in files.items():
        with open(os.path.join(d, rel), "w", encoding="utf-8") as f:
            f.write(text)
    print(f"built yakuake/skins/{name} ({len(files)} files)")


def main() -> int:
    for name, colors in SKINS.items():
        build(name, scheme(os.path.join(SCHEMES, colors)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
