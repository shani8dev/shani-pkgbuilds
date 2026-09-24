#!/usr/bin/env python3
"""WCAG contrast audit for the Saturn colour schemes.

Reading a scheme can't tell you whether its text is legible; computing the
actual WCAG contrast ratio can. This script parses every `Colors:*` group in
the shipped schemes and asserts that each foreground/background pair a user
actually reads clears a minimum ratio, exiting non-zero on a hard failure so
it can gate CI.

Methodology is borrowed from kde-neonnoir's generate.py (contrast assertions
on every fg/bg pair); the implementation is our own.

Thresholds (WCAG 2.1):
  4.5  AA normal text        - body text on window/view/button/tooltip bg
  3.0  AA large/UI graphics  - status, links, inactive, focus rings, WM title
Selection foregrounds are held to 4.5 because selected text is normal text.
"""
from __future__ import annotations

import configparser
import glob
import os
import sys

AA_TEXT = 4.5
AA_UI = 3.0

# (foreground key, minimum ratio, human label) applied to each Colors:* group.
CHECKS = [
    ("foregroundnormal", AA_TEXT, "body text"),
    ("foregroundinactive", AA_UI, "inactive/de-emphasised text"),
    ("foregroundactive", AA_UI, "active accent text"),
    ("foregroundlink", AA_UI, "link text"),
    ("foregroundvisited", AA_UI, "visited link text"),
    ("foregroundnegative", AA_UI, "negative/error text"),
    ("foregroundneutral", AA_UI, "neutral/warning text"),
    ("foregroundpositive", AA_UI, "positive/success text"),
    ("decorationfocus", AA_UI, "focus ring"),
]


def _srgb_channel(value: float) -> float:
    value = value / 255.0
    return value / 12.92 if value <= 0.03928 else ((value + 0.055) / 1.055) ** 2.4


def relative_luminance(rgb: tuple[int, int, int]) -> float:
    r, g, b = (_srgb_channel(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(fg: tuple[int, int, int], bg: tuple[int, int, int]) -> float:
    l1, l2 = relative_luminance(fg), relative_luminance(bg)
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def parse_rgb(raw: str) -> tuple[int, int, int]:
    parts = [int(p.strip()) for p in raw.split(",")]
    if len(parts) != 3:
        raise ValueError(f"expected 3 components, got {raw!r}")
    return parts[0], parts[1], parts[2]


def audit(path: str) -> tuple[list[str], list[str], str]:
    parser = configparser.ConfigParser()
    parser.optionxform = str  # keep keys exactly as written (already lowercase)
    with open(path, encoding="utf-8") as handle:
        parser.read_file(handle)

    scheme = parser.get("General", "name", fallback=os.path.basename(path))
    failures: list[str] = []
    warnings: list[str] = []

    for section in parser.sections():
        if not section.startswith("Colors:"):
            continue
        if not parser.has_option(section, "backgroundnormal"):
            continue
        bg = parse_rgb(parser.get(section, "backgroundnormal"))
        for key, floor, label in CHECKS:
            raw_fg = parser.get(section, key, fallback=None)
            if raw_fg is None:
                continue
            ratio = contrast_ratio(parse_rgb(raw_fg), bg)
            line = f"  {section}.{key} vs backgroundnormal: {ratio:4.2f}:1 (need {floor})"
            if ratio < floor:
                failures.append(f"{line}  <-- {label}")
            elif ratio < floor + 1.0:
                warnings.append(f"{line}  (tight: {label})")

    # Alternate background carries zebra stripes / alternating rows.
    for section in parser.sections():
        if not section.startswith("Colors:"):
            continue
        if not parser.has_option(section, "backgroundalternate"):
            continue
        bg = parse_rgb(parser.get(section, "backgroundalternate"))
        for key, floor, label in (("foregroundnormal", AA_TEXT, "body text"),):
            raw_fg = parser.get(section, key, fallback=None)
            if raw_fg is None:
                continue
            ratio = contrast_ratio(parse_rgb(raw_fg), bg)
            line = f"  {section}.{key} vs backgroundalternate: {ratio:4.2f}:1 (need {floor})"
            if ratio < floor:
                failures.append(f"{line}  <-- {label}")

    # Window-manager titlebar colours.
    if parser.has_section("WM"):
        pairs = (
            ("activeforeground", "activebackground", "active title text"),
            ("inactiveforeground", "inactivebackground", "inactive title text"),
        )
        for fg_key, bg_key, label in pairs:
            if parser.has_option("WM", fg_key) and parser.has_option("WM", bg_key):
                ratio = contrast_ratio(
                    parse_rgb(parser.get("WM", fg_key)),
                    parse_rgb(parser.get("WM", bg_key)),
                )
                line = f"  WM.{fg_key} vs {bg_key}: {ratio:4.2f}:1 (need {AA_UI})"
                if ratio < AA_UI:
                    failures.append(f"{line}  <-- {label}")

    return failures, warnings, scheme


def check_konsole(root: str) -> int:
    """Konsole ANSI colours must be legible on the scheme's own background:
    4.5:1 for the hues, 3:1 for the slot that mirrors the background (black on
    dark, white on light), and each intense colour distinct from its normal."""
    import re
    fails = 0
    for path in sorted(glob.glob(os.path.join(root, "usr/share/konsole/*.colorscheme"))):
        text = open(path, encoding="utf-8").read()
        col = lambda g: parse_rgb(re.search(rf"\[{g}\]\nColor=([0-9, ]+)", text).group(1))
        bg = col("Background")
        dark = relative_luminance(bg) < 0.5
        print(f"\n== {os.path.basename(path)} (Konsole ANSI) ==")
        bad = []
        for i in range(8):
            normal, intense = col(f"Color{i}"), col(f"Color{i}Intense")
            # the slot that mirrors the background (black on dark, white on
            # light) is used for bars/panels: its normal colour need only be
            # distinguishable (1.2:1); its intense ("bright black" = dim text)
            # must reach 3:1. Every other colour is text: 4.5:1.
            bgslot = (dark and i == 0) or (not dark and i == 7)
            for label, c in (("", normal), ("Intense", intense)):
                need = (1.2 if label == "" else AA_UI) if bgslot else AA_TEXT
                r = contrast_ratio(c, bg)
                if r < need:
                    bad.append(f"Color{i}{label} {r:.2f} < {need}")
            if normal == intense:
                bad.append(f"Color{i}Intense identical to Color{i}")
        for b in bad:
            print("  FAIL", b)
        if not bad:
            print("  all 16 ANSI colours legible and distinct")
        fails += len(bad)
    return fails


def main(argv: list[str]) -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    if len(argv) > 1:
        paths = argv[1:]
    else:
        paths = sorted(glob.glob(os.path.join(here, "usr/share/color-schemes/*.colors")))
    if not paths:
        print("no .colors files found", file=sys.stderr)
        return 2

    hard_fail = False
    for path in paths:
        failures, warnings, scheme = audit(path)
        print(f"\n== {scheme}  ({os.path.relpath(path, here)}) ==")
        for item in warnings:
            print(f"warning: {item}")
        for item in failures:
            print(f"FAIL:    {item}")
        if not failures:
            print("  all foreground/background pairs meet their minimum ratio")
        hard_fail = hard_fail or bool(failures)

    hard_fail = check_konsole(here) > 0 or hard_fail
    print()
    if hard_fail:
        print("contrast audit FAILED")
        return 1
    print("contrast audit passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
