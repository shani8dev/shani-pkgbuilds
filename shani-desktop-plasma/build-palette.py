#!/usr/bin/env python3
"""Apply the Saturn palette (saturn_palette.py) to every shipped colour file.

Colour schemes, Konsole schemes and the Kvantum artwork share one set of
neutrals, so apps, window chrome and the terminal match exactly. The
Kvantum .kvconfig files get the same tint from build-kvantum.py; the Plasma
styles' `colors` are copies of the colour schemes (build-desktoptheme.py).
Idempotent - safe to re-run.

  python3 build-palette.py
"""
from __future__ import annotations

import os

import saturn_palette as sp

HERE = os.path.dirname(os.path.abspath(__file__))
SHARE = os.path.join(HERE, "usr/share")
TARGETS = {
    "dark": ["color-schemes/SaturnDark.colors", "konsole/SaturnDark.colorscheme",
             "Kvantum/SaturnDark/SaturnDark.svg"],
    "light": ["color-schemes/Saturn.colors", "konsole/Saturn.colorscheme",
              "Kvantum/Saturn/Saturn.svg"],
}


def main() -> int:
    for mode, rels in TARGETS.items():
        for rel in rels:
            path = os.path.join(SHARE, rel)
            with open(path, encoding="utf-8") as f:
                old = f.read()
            new = sp.apply(old, mode, rgb_triplets=not rel.endswith(".svg"))
            if new != old:
                with open(path, "w", encoding="utf-8") as f:
                    f.write(new)
            print(f"{'tinted' if new != old else 'unchanged'} {rel} ({mode})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
