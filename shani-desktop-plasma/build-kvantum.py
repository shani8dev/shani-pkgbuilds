#!/usr/bin/env python3
"""Generate the Saturn Kvantum configs from upstream MacTahoe.

Kvantum draws every Qt widget from the theme SVG, but only for widgets
whose section ([ScrollbarSlider], [LineEdit], [Tab], ...) the .kvconfig
defines; a hand-trimmed config silently loses whole widget classes. So
the configs are generated from the complete upstream ones (kvantum-upstream/,
see its README) plus explicit Saturn overrides:

- the accent: MacTahoe's blues -> Saturn coral, the same map the shipped
  SVG artwork uses, so config colours and artwork agree;
- the Saturn neutrals (saturn_palette.py): indigo-tinted dark, cream light;
- translucency/rounded layout: from the Utterly-Round Transparent Kvantum
  template (blur radius, window/menu opacity, general layout), keeping
  MacTahoe as the base for correct colours that saturn_palette recolours.
  The template's opaque=` list keeps apps that break under translucency.

Light Saturn comes from MacTahoe (light artwork), SaturnDark from
MacTahoeDark. Run from the package directory:  python3 build-kvantum.py
"""
from __future__ import annotations

import os
import re

import saturn_palette as sp

HERE = os.path.dirname(os.path.abspath(__file__))
UP = os.path.join(HERE, "kvantum-upstream")
OUT = os.path.join(HERE, "usr/share/Kvantum")

# MacTahoe blue family -> Saturn coral family (derived by aligning the
# upstream SVGs with the recoloured shipped ones; every pair is 1:1).
ACCENT = {
    "#0078f0": "#ff6a3d", "#0852ce": "#f05a33", "#0860f2": "#ff7f50",
    "#1352c4": "#f05a33", "#195dda": "#f05a33", "#195edc": "#ff6a3d",
    "#2e73ef": "#ff6a3d", "#315bef": "#ff7f50", "#3776e8": "#ff6a3d",
    "#3daee9": "#ffa989", "#5294e2": "#ffa989", "#597bf2": "#ff7f50",
    "#b74aff": "#ff6a3d",
    # kvconfig-only blues
    "#3484e2": "#ff7f50", "#a0b4f8": "#ff7f50",
}

THEMES = {
    # name: (upstream file, overrides {section: {key: value}})
    "Saturn": ("MacTahoe.kvconfig", {
        "%General": {
            # user-facing text is Saturn's; upstream attribution (LGPL-3.0)
            # lives in usr/share/licenses/shani-desktop-plasma/THIRD-PARTY
            "author": "Shani OS",
            "comment": "Saturn - the ShaniOS light Kvantum theme",
            # --- translucency: from Utterly-Round Transparent template ---
            "reduce_window_opacity": "40",
            "reduce_menu_opacity": "40",
            "menu_blur_radius": "14",
            "tooltip_blur_radius": "14",
            # --- general layout: from Utterly-Round Transparent template ---
            "animate_states": "false",
            "attach_active_tab": "true",
            "check_size": "14",
            "drag_from_buttons": "true",
            "groupbox_top_label": "true",
            "hide_combo_checkboxes": "true",
            "layout_margin": "9",
            "layout_spacing": "6",
            "left_tabs": "true",
            "menu_separator_height": "6",
            "menu_shadow_depth": "5",
            "no_inactiveness": "true",
            "opaque": "QMPlay2,kaffeine,kmplayer,subtitlecomposer,kdenlive,vlc,avidemux,avidemux2_qt4,avidemux3_qt4,avidemux3_qt5,kamoso,QtCreator,VirtualBox,trojita,dragon,digikam,virtualboxvm",
            "progressbar_thickness": "8",
            "scroll_min_extent": "60",
            "scroll_width": "12",
            "scrollable_menu": "false",
            "scrollbar_in_view": "true",
            "slider_handle_length": "18",
            "slider_handle_width": "18",
            "spin_button_width": "32",
            "splitter_width": "4",
            "toolbar_icon_size": "22",
            "toolbar_interior_spacing": "3",
            "toolbar_item_spacing": "1",
            "tooltip_shadow_depth": "6",
            "transient_groove": "true",
            "transient_scrollbar": "true",
            "tree_branch_line": "false",
            "vertical_spin_indicators": "true",
        },
        "Hacks": {
            "centered_forms": "true",
            "disabled_icon_opacity": "70",
            "lxqtmainmenu_iconsize": "22",
            "transparent_dolphin_view": "true",
            "transparent_pcmanfm_view": "true",
        },
        "GeneralColors": {"link.visited.color": "#c0502c",
                          # upstream typo: 7 hex digits
                          "inactive.base.color": "#ffffff74"},
    }),
    "SaturnDark": ("MacTahoeDark.kvconfig", {
        "%General": {
            "author": "Shani OS",
            "comment": "Saturn Dark - the ShaniOS dark Kvantum theme",
            # --- translucency: from Utterly-Round Transparent template ---
            "reduce_window_opacity": "40",
            "reduce_menu_opacity": "40",
            "menu_blur_radius": "14",
            "tooltip_blur_radius": "14",
            # --- general layout: from Utterly-Round Transparent template ---
            "animate_states": "false",
            "attach_active_tab": "true",
            "check_size": "14",
            "drag_from_buttons": "true",
            "groupbox_top_label": "true",
            "hide_combo_checkboxes": "true",
            "layout_margin": "9",
            "layout_spacing": "6",
            "left_tabs": "true",
            "menu_separator_height": "6",
            "menu_shadow_depth": "5",
            "no_inactiveness": "true",
            "opaque": "QMPlay2,kaffeine,kmplayer,subtitlecomposer,kdenlive,vlc,avidemux,avidemux2_qt4,avidemux3_qt4,avidemux3_qt5,kamoso,QtCreator,VirtualBox,trojita,dragon,digikam,virtualboxvm",
            "progressbar_thickness": "8",
            "scroll_min_extent": "60",
            "scroll_width": "12",
            "scrollable_menu": "false",
            "scrollbar_in_view": "true",
            "slider_handle_length": "18",
            "slider_handle_width": "18",
            "spin_button_width": "32",
            "splitter_width": "4",
            "toolbar_icon_size": "22",
            "toolbar_interior_spacing": "3",
            "toolbar_item_spacing": "1",
            "tooltip_shadow_depth": "6",
            "transient_groove": "true",
            "transient_scrollbar": "true",
            "tree_branch_line": "false",
            "vertical_spin_indicators": "true",
        },
        "Hacks": {
            "centered_forms": "true",
            "disabled_icon_opacity": "70",
            "lxqtmainmenu_iconsize": "22",
            "transparent_dolphin_view": "true",
            "transparent_pcmanfm_view": "true",
        },
        "GeneralColors": {"link.visited.color": "#ffa989"},
    }),
}


def recolor(text: str) -> str:
    return re.sub(r"#[0-9a-fA-F]{6}(?![0-9a-fA-F])",
                  lambda m: ACCENT.get(m.group(0).lower(), m.group(0)), text)


def apply_overrides(text: str, overrides: dict[str, dict[str, str]]) -> str:
    out, section, pending = [], None, {}
    lines = text.splitlines()
    for i, line in enumerate(lines):
        m = re.match(r"^\[(.+)\]\s*$", line)
        if m:
            section = m.group(1)
            pending = dict(overrides.get(section, {}))
        elif section and "=" in line and not line.lstrip().startswith("#"):
            key = line.split("=", 1)[0].strip()
            if key in pending:
                line = f"{key}={pending.pop(key)}"
        out.append(line)
        nxt = lines[i + 1] if i + 1 < len(lines) else "["
        if section and pending and re.match(r"^\[", nxt):
            # keys the upstream section lacks go at its end
            while out and not out[-1].strip():
                out.pop()
            out += [f"{k}={v}" for k, v in pending.items()] + [""]
            pending = {}
    return "\n".join(out) + "\n"


def main() -> int:
    for name, (src, overrides) in THEMES.items():
        with open(os.path.join(UP, src), encoding="utf-8") as f:
            text = f.read()
        text = apply_overrides(recolor(text), overrides)
        # the Saturn neutrals (night-sky indigo / cream), same as the SVGs
        text = sp.apply(text, "dark" if name.endswith("Dark") else "light", rgb_triplets=False)
        header = (f"# {name} Kvantum theme (ShaniOS). GENERATED by build-kvantum.py -\n"
                  "# edit the script, not this file.\n")
        path = os.path.join(OUT, name, f"{name}.kvconfig")
        with open(path, "w", encoding="utf-8") as f:
            f.write(header + text)
        print(f"built {os.path.relpath(path, HERE)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
