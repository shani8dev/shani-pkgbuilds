#!/usr/bin/env python3
"""Package validator for shani-desktop-plasma.

Validates:
- Metadata directory/ID consistency
- Unique desktop-theme IDs
- Expected theme assets present
- No stale SaturnLight/SaturnTwilight references in active package files
- Symlink resolution within package tree
- Theme references (look-and-feel defaults, layout.js, skel, greeter in the
  .install) resolve to a shipped or upstream theme, and each config set is
  consistently light or dark
"""
from __future__ import annotations

import configparser
import json
import re
import os
import sys
from pathlib import Path
from typing import Any


def find_package_root(start: Path | None = None) -> Path:
    """Find the package root directory (where this script lives by default)."""
    if start is None:
        start = Path(__file__).parent
    return start.resolve()


def read_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def validate_metadata_consistency(root: Path) -> list[str]:
    """Validate that metadata.json IDs match their directory names."""
    errors = []

    # Plasma desktoptheme metadata
    for theme_dir in (root / "usr/share/plasma/desktoptheme").iterdir():
        if not theme_dir.is_dir():
            continue
        meta_path = theme_dir / "metadata.json"
        if not meta_path.exists():
            errors.append(f"Missing metadata.json in {theme_dir.relative_to(root)}")
            continue
        meta = read_json(meta_path)
        plugin_id = meta.get("KPlugin", {}).get("Id")
        # Plasma desktop themes conventionally use "default" as the Id
        if plugin_id != theme_dir.name and plugin_id != "default":
            errors.append(
                f"Desktop theme {theme_dir.name}: metadata Id '{plugin_id}' != directory name"
            )

    # Plasma look-and-feel metadata
    for theme_dir in (root / "usr/share/plasma/look-and-feel").iterdir():
        if not theme_dir.is_dir():
            continue
        meta_path = theme_dir / "metadata.json"
        if not meta_path.exists():
            errors.append(f"Missing metadata.json in {theme_dir.relative_to(root)}")
            continue
        meta = read_json(meta_path)
        plugin_id = meta.get("KPlugin", {}).get("Id")
        if plugin_id != theme_dir.name:
            errors.append(
                f"Look-and-feel {theme_dir.name}: metadata Id '{plugin_id}' != directory name"
            )

    # Yakuake skin metadata
    for skin_dir in (root / "usr/share/yakuake/skins").iterdir():
        if not skin_dir.is_dir():
            continue
        meta_path = skin_dir / "metadata.json"
        if not meta_path.exists():
            errors.append(f"Missing metadata.json in {skin_dir.relative_to(root)}")
            continue
        meta = read_json(meta_path)
        plugin_id = meta.get("KPlugin", {}).get("Id")
        if plugin_id != skin_dir.name:
            errors.append(
                f"Yakuake skin {skin_dir.name}: metadata Id '{plugin_id}' != directory name"
            )

    # Wallpaper metadata
    for wp_dir in (root / "usr/share/wallpapers").iterdir():
        if not wp_dir.is_dir():
            continue
        meta_path = wp_dir / "metadata.json"
        if not meta_path.exists():
            errors.append(f"Missing metadata.json in {wp_dir.relative_to(root)}")
            continue
        meta = read_json(meta_path)
        plugin_id = meta.get("KPlugin", {}).get("Id")
        if plugin_id != wp_dir.name:
            errors.append(
                f"Wallpaper {wp_dir.name}: metadata Id '{plugin_id}' != directory name"
            )

    return errors


def validate_unique_desktop_theme_ids(root: Path) -> list[str]:
    """Validate that desktop-theme IDs are unique across themes."""
    errors = []
    seen_ids: dict[str, str] = {}

    for theme_dir in (root / "usr/share/plasma/desktoptheme").iterdir():
        if not theme_dir.is_dir():
            continue
        meta_path = theme_dir / "metadata.json"
        if not meta_path.exists():
            continue
        meta = read_json(meta_path)
        plugin_id = meta.get("KPlugin", {}).get("Id")
        # Plasma desktop themes conventionally use "default" as the Id
        # Allow multiple themes to use "default" since they're in different directories
        if plugin_id != "default" and plugin_id in seen_ids:
            errors.append(
                f"Duplicate desktop-theme Id '{plugin_id}': "
                f"{theme_dir.name} and {seen_ids[plugin_id]}"
            )
        elif plugin_id != "default":
            seen_ids[plugin_id] = theme_dir.name

    return errors


def validate_expected_assets(root: Path) -> list[str]:
    """Validate that expected theme assets are present."""
    errors = []

    # Expected desktoptheme structure for each theme
    expected_desktoptheme = {
        "Saturn",
        "Saturn-Dark",
    }

    for theme in expected_desktoptheme:
        theme_root = root / "usr/share/plasma/desktoptheme" / theme
        if not theme_root.exists():
            errors.append(f"Missing desktoptheme directory: {theme}")
            continue

        # Required files
        for rel in ("metadata.json", "colors", "plasmarc", "LICENSE.md"):
            if not (theme_root / rel).exists():
                errors.append(f"Missing {theme}/{rel}")
        # KSvg accepts .svg or .svgz. Every surface Plasma draws the shell
        # with; one missing here falls back to stock Breeze for that surface.
        for rel in ("widgets/background", "widgets/panel-background", "widgets/tooltip",
                    "dialogs/background", "widgets/tasks", "widgets/button",
                    "widgets/plasmoidheading", "widgets/viewitem", "widgets/scrollbar",
                    "widgets/tabbar", "widgets/lineedit", "widgets/translucentbackground"):
            if not any((theme_root / f"{rel}.{ext}").exists() for ext in ("svg", "svgz")):
                errors.append(f"Missing {theme}/{rel}.svg(z)")

        # Required subdirectories with at least one file
        required_subdirs = [
            "opaque/widgets",
            "solid/widgets",
            "translucent/widgets",
            "translucent/dialogs",
        ]
        for subdir in required_subdirs:
            subdir_path = theme_root / subdir
            if not subdir_path.exists() or not any(subdir_path.iterdir()):
                errors.append(f"Missing or empty {theme}/{subdir}")

    # Expected look-and-feel themes
    expected_look_and_feel = {"Saturn", "Saturn-Dark", "Saturn-Twilight"}
    for theme in expected_look_and_feel:
        theme_root = root / "usr/share/plasma/look-and-feel" / theme
        if not theme_root.exists():
            errors.append(f"Missing look-and-feel directory: {theme}")
            continue

        required_files = [
            "metadata.json",
            "contents/defaults",
            "contents/layouts/org.kde.plasma.desktop-layout.js",
            "contents/splash/Splash.qml",
            # names from plasma-workspace shell/packageplugins/lookandfeel:
            # the fullscreen preview is looked up as .jpg only, and the
            # Splash Screen KCM's thumbnail is previews/splash.png
            "contents/previews/preview.png",
            "contents/previews/fullscreenpreview.jpg",
            "contents/previews/splash.png",
            "contents/previews/lockscreen.png",
        ]
        for rel in required_files:
            if not (theme_root / rel).exists():
                errors.append(f"Missing {theme}/{rel}")
        # a .png fullscreen preview is never found by Plasma (it looks for .jpg)
        if (theme_root / "contents/previews/fullscreenpreview.png").exists():
            errors.append(f"{theme}: previews/fullscreenpreview.png is ignored by Plasma - it must be fullscreenpreview.jpg")

        # Splash images
        splash_images = theme_root / "contents/splash/images"
        if not splash_images.exists() or not any(splash_images.iterdir()):
            errors.append(f"Missing or empty {theme}/contents/splash/images")

    # Expected yakuake skins (Yakuake's real format: app/skin.cpp upstream),
    # and every image a .skin file references must exist - a missing one is
    # silently blank (the pre-2026-09-23 skin referenced 15 that didn't).
    for skin in ("Saturn", "Saturn-Dark"):
        yakuake_root = root / "usr/share/yakuake/skins" / skin
        for rel in ("metadata.json", "metadata.desktop", "title.skin", "tabs.skin"):
            if not (yakuake_root / rel).exists():
                errors.append(f"Missing yakuake/{skin}/{rel}")
        for sk in yakuake_root.glob("*.skin"):
            for ref in re.findall(r"=(/\S+\.(?:svg|png))", sk.read_text(encoding="utf-8")):
                if ref != "/icon.png" and not (yakuake_root / ref.lstrip("/")).is_file():
                    errors.append(f"yakuake/{skin}/{sk.name}: {ref} does not exist")

    # Expected wallpaper
    wallpaper_root = root / "usr/share/wallpapers/Saturn"
    if not wallpaper_root.exists():
        errors.append("Missing wallpaper: Saturn")
    else:
        required_files = ["metadata.json", "metadata.desktop"]
        for rel in required_files:
            if not (wallpaper_root / rel).exists():
                errors.append(f"Missing wallpaper/Saturn/{rel}")

        for variant in ("images", "images_dark", "images_twilight"):
            variant_path = wallpaper_root / "contents" / variant
            if not variant_path.exists() or not any(variant_path.iterdir()):
                errors.append(f"Missing or empty wallpaper/Saturn/contents/{variant}")

    # Expected layout templates
    for template in ("dev.shani.desktop.defaultPanel", "dev.shani.desktop.defaultDock"):
        template_root = root / "usr/share/plasma/layout-templates" / template
        if not template_root.exists():
            errors.append(f"Missing layout template: {template}")
        else:
            for rel in ("metadata.json", "contents/layout.js"):
                if not (template_root / rel).exists():
                    errors.append(f"Missing {template}/{rel}")

    return errors


def validate_no_stale_references(root: Path) -> list[str]:
    """Validate no stale SaturnLight/SaturnTwilight references in active package files."""
    errors = []

    # Files to check for stale references
    check_dirs = [
        root / "etc",
        root / "usr",
    ]

    stale_patterns = ["SaturnLight", "SaturnTwilight"]

    for check_dir in check_dirs:
        if not check_dir.exists():
            continue
        for file_path in check_dir.rglob("*"):
            if not file_path.is_file():
                continue
            # Skip binary files
            try:
                content = file_path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue

            for pattern in stale_patterns:
                if pattern in content:
                    # Allow in comments or specific known contexts
                    rel = file_path.relative_to(root)
                    # Check if it's in a comment or string that's clearly documenting legacy
                    lines = content.split("\n")
                    for i, line in enumerate(lines, 1):
                        if pattern in line:
                            stripped = line.strip()
                            # Allow if it's a comment line
                            if stripped.startswith("#") or stripped.startswith("//") or stripped.startswith("/*"):
                                continue
                            # Allow in shani-theme-sync.sh where it's explicitly handled as legacy alias
                            if "shani-theme-sync.sh" in str(file_path):
                                continue
                            errors.append(
                                f"Stale reference '{pattern}' in {rel}:{i}: {line.strip()}"
                            )

    return errors


def validate_symlinks(root: Path) -> list[str]:
    """Validate that symlinks resolve within the package tree."""
    errors = []

    # only what the PKGBUILD packages (etc/, usr/) - not build leftovers
    for file_path in [f for d in ("etc", "usr") for f in (root / d).rglob("*")]:
        if not file_path.is_symlink():
            continue

        if not file_path.exists():
            errors.append(f"Broken symlink: {file_path.relative_to(root)} -> {os.readlink(file_path)}")
            continue
        try:
            target = file_path.resolve()
            # Check if target is within package root
            try:
                target.relative_to(root)
            except ValueError:
                errors.append(
                    f"Symlink {file_path.relative_to(root)} points outside package tree: {target}"
                )
        except OSError as e:
            errors.append(f"Broken symlink {file_path.relative_to(root)}: {e}")

    return errors


def validate_color_schemes(root: Path) -> list[str]:
    """Validate color scheme files exist and are parseable."""
    errors = []
    color_schemes_dir = root / "usr/share/color-schemes"
    if not color_schemes_dir.exists():
        errors.append("Missing usr/share/color-schemes directory")
        return errors

    expected = {"Saturn.colors", "SaturnDark.colors"}
    found = {f.name for f in color_schemes_dir.iterdir() if f.suffix == ".colors"}
    missing = expected - found
    for m in missing:
        errors.append(f"Missing color scheme: {m}")

    # Basic parse check
    import configparser
    for scheme_file in color_schemes_dir.glob("*.colors"):
        parser = configparser.ConfigParser()
        parser.optionxform = str
        try:
            parser.read(scheme_file, encoding="utf-8")
            if not parser.has_section("General"):
                errors.append(f"Color scheme {scheme_file.name} missing [General] section")
            # Key is 'Name' (capitalized) in the actual files
            if not parser.has_option("General", "Name"):
                errors.append(f"Color scheme {scheme_file.name} missing 'Name' in [General]")
        except Exception as e:
            errors.append(f"Failed to parse color scheme {scheme_file.name}: {e}")

    return errors


# Upstream names the package depends on (breeze, breeze-gtk, kvantum) —
# anything else a config names must be shipped by this package.
UPSTREAM = {
    "desktoptheme": {"default", "breeze-dark", "breeze-light"},
    "icons": {"breeze", "breeze-dark", "hicolor"},
    "cursors": {"breeze_cursors", "Breeze_Light"},
    "gtk": {"Breeze", "Breeze-Dark"},
    "lookandfeel": {"org.kde.breeze", "org.kde.breeze.desktop",
                    "org.kde.breezedark.desktop", "org.kde.breezetwilight.desktop"},
}

# (config file, group, key) -> kind; group None = any group (skel files
# without sections, or the LnF defaults' "[file][group]" section names).
THEME_KEYS = [
    ("kdeglobals", "General", "ColorScheme", "colorscheme"),
    ("kdeglobals", "Icons", "Theme", "icons"),
    ("kdeglobals", "KDE", "LookAndFeelPackage", "lookandfeel"),
    ("kdeglobals", "KDE", "DefaultLightLookAndFeel", "lookandfeel"),
    ("kdeglobals", "KDE", "DefaultDarkLookAndFeel", "lookandfeel"),
    ("kvantum.kvconfig", "General", "theme", "kvantum"),
    ("plasmarc", "Theme", "name", "desktoptheme"),
    ("kcminputrc", "Mouse", "cursorTheme", "cursors"),
    ("ksplashrc", "KSplash", "Theme", "splash"),
    ("kscreenlockerrc", "Greeter", "Theme", "lookandfeel"),
    ("settings.ini", "Settings", "gtk-theme-name", "gtk"),
    ("settings.ini", "Settings", "gtk-icon-theme-name", "icons"),
    ("settings.ini", "Settings", "gtk-cursor-theme-name", "cursors"),
    ("gtkrc-2.0", None, "gtk-theme-name", "gtk"),
    ("gtkrc-2.0", None, "gtk-icon-theme-name", "icons"),
    ("gtkrc-2.0", None, "gtk-cursor-theme-name", "cursors"),
    ("gtkrc", None, "gtk-theme-name", "gtk"),
]
# Kinds whose value says "light" or "dark" (cursors/splash/lookandfeel
# pointers are shared by both variants).
TONED = {"colorscheme", "icons", "kvantum", "desktoptheme"}


def _ini(text: str) -> configparser.ConfigParser:
    cp = configparser.ConfigParser(strict=False, interpolation=None,
                                   comment_prefixes=("#", ";"))
    cp.optionxform = str
    if not text.lstrip().startswith("["):
        text = "[__top__]\n" + text
    cp.read_string(text)
    return cp


def _shipped(root: Path, kind: str, name: str) -> bool:
    share = root / "usr/share"
    if name in UPSTREAM.get(kind, ()):
        return True
    return {
        "colorscheme": lambda: (share / "color-schemes" / f"{name}.colors").is_file(),
        "icons": lambda: (share / "icons" / name / "index.theme").is_file() and any(
            d.strip() and d.strip() != "cursors" for d in _ini((share / "icons" / name / "index.theme")
            .read_text(encoding="utf-8")).get("Icon Theme", "Directories", fallback="").split(",")),
        "cursors": lambda: (share / "icons" / name / "cursors").is_dir(),
        "kvantum": lambda: (share / "Kvantum" / name / f"{name}.kvconfig").is_file(),
        "desktoptheme": lambda: (share / "plasma/desktoptheme" / name / "metadata.json").is_file(),
        "lookandfeel": lambda: (share / "plasma/look-and-feel" / name / "metadata.json").is_file(),
        "splash": lambda: (share / "plasma/look-and-feel" / name / "contents/splash").is_dir(),
        "gtk": lambda: False,
    }[kind]()


def _theme_refs(cfgfile: str, cp: configparser.ConfigParser):
    """Yield (kind, key, value) for every theme key present in cp."""
    for f, group, key, kind in THEME_KEYS:
        if f != cfgfile:
            continue
        for sec in cp.sections():
            if group is not None and sec.split("][")[-1] != group:
                continue
            if key in cp[sec]:
                yield kind, key, cp[sec][key].strip().strip('"')


def _check_set(root: Path, label: str, refs: list[tuple[str, str, str]],
               expect_dark: bool | None, errors: list[str]) -> None:
    for kind, key, value in refs:
        if not _shipped(root, kind, value):
            errors.append(f"{label}: {key}={value} names a {kind} that is not shipped")
        elif expect_dark is not None and kind in TONED and ("dark" in value.lower()) != expect_dark:
            errors.append(f"{label}: {key}={value} is {'light' if expect_dark else 'dark'} "
                          f"but this set is {'dark' if expect_dark else 'light'}")


def validate_theme_references(root: Path) -> list[str]:
    """Every theme a config names must exist; each config set must be one tone."""
    errors: list[str] = []
    lnf_root = root / "usr/share/plasma/look-and-feel"

    # 1. Look-and-feel defaults: "[<file>][<group>]" sections in one file.
    for lnf in sorted(d for d in lnf_root.iterdir() if d.is_dir()):
        defaults = lnf / "contents/defaults"
        if not defaults.is_file():
            continue
        cp = _ini(defaults.read_text(encoding="utf-8"))
        dark = "Dark" in lnf.name
        # Twilight (as Breeze Twilight): light apps, dark Plasma style.
        twilight = "Twilight" in lnf.name
        refs: list[tuple[str, str, str]] = []
        for sec in cp.sections():
            f = sec.split("][")[0]
            f = "settings.ini" if f.endswith("settings.ini") else f.lstrip(".")
            if sec == "KSplash":
                f = "ksplashrc"
            sub = configparser.ConfigParser(interpolation=None)
            sub.optionxform = str
            sub.read_dict({sec: dict(cp[sec])})
            refs += list(_theme_refs(f, sub))
        shell = [r for r in refs if r[0] == "desktoptheme"]
        _check_set(root, f"look-and-feel/{lnf.name}/defaults", shell, dark or twilight, errors)
        _check_set(root, f"look-and-feel/{lnf.name}/defaults",
                   [r for r in refs if r[0] != "desktoptheme"], dark, errors)
        # Plasma's DefaultWallpaper reads [Wallpaper] Image as a wallpaper
        # PACKAGE name (wallpapers/<name>); anything else (a file:// URL)
        # silently falls through to the stock "Next" wallpaper.
        if cp.has_section("Wallpaper") and "Image" in cp["Wallpaper"]:
            img = cp["Wallpaper"]["Image"].strip()
            if not (root / "usr/share/wallpapers" / img / "metadata.json").is_file():
                errors.append(f"look-and-feel/{lnf.name}/defaults: [Wallpaper] Image={img} is not a "
                              "shipped wallpaper package name (Plasma falls back to 'Next')")
        own = [v for k, key, v in refs if k == "lookandfeel" and key == "LookAndFeelPackage"]
        if own and own[0] != lnf.name:
            errors.append(f"look-and-feel/{lnf.name}/defaults: LookAndFeelPackage={own[0]}")
        # layout.js runs when the theme is applied with its layout; a
        # hard-coded Plasma style there overrides [plasmarc] above.
        plasmarc = [v for k, _, v in refs if k == "desktoptheme"]
        for js in (lnf / "contents/layouts").glob("*.js"):
            for m in re.finditer(r"^\s*theme\s*=\s*['\"]([^'\"]+)", js.read_text(encoding="utf-8"), re.M):
                if plasmarc and m.group(1) != plasmarc[0]:
                    errors.append(f"look-and-feel/{lnf.name}: {js.name} sets theme='{m.group(1)}' "
                                  f"but defaults set plasmarc name={plasmarc[0]}")

    # KPackage only resolves files inside the package root: a symlink out of
    # it (e.g. a layout.js pointing at a sibling look-and-feel) is ignored and
    # the shell silently falls back to Plasma's stock layout.
    for lnf in sorted(d for d in lnf_root.iterdir() if d.is_dir()):
        for f in lnf.rglob("*"):
            if f.is_symlink() and lnf.resolve() not in f.resolve().parents:
                errors.append(f"look-and-feel/{lnf.name}: {f.relative_to(lnf)} symlinks outside the "
                              "package (KPackage ignores it)")

    # 2. skel: one file per config; the whole skel must match its LnF's tone.
    skel = root / "etc/skel"
    skel_refs: list[tuple[str, str, str]] = []
    for path in sorted(skel.rglob("*")):
        if not path.is_file() or path.suffix in (".css", ".svg"):
            continue
        name = "settings.ini" if path.name == "settings.ini" else path.name.lstrip(".")
        if name == "gtkrc-2.0" and path.parent.name == ".config":
            name = "gtkrc-2.0"
        if not any(name == f for f, *_ in THEME_KEYS):
            continue
        try:
            body = path.read_text(encoding="utf-8")
            if name.startswith("gtkrc"):
                body = "\n".join(l for l in body.splitlines() if "=" in l)
            cp = _ini(body)
        except configparser.Error as e:
            errors.append(f"{path.relative_to(root)}: unparsable ({e})")
            continue
        skel_refs += [(k, f"{path.relative_to(skel)}:{key}", v) for k, key, v in _theme_refs(name, cp)]
    skel_lnf = [v for k, key, v in skel_refs if key.endswith(":LookAndFeelPackage")]
    _check_set(root, "etc/skel", skel_refs,
               ("dark" in skel_lnf[0].lower()) if skel_lnf else None, errors)

    # 3. Greeter heredocs in the .install (written to kdedefaults/<file>).
    install = root / "shani-desktop-plasma.install"
    text = install.read_text(encoding="utf-8")
    greeter: list[tuple[str, str, str]] = []
    for m in re.finditer(r'cat > "\$[dk]/([^"]+)" <<\'EOF\'\n(.*?)\nEOF', text, re.S):
        greeter += list(_theme_refs(m.group(1), _ini(m.group(2))))
    g_lnf = [v for k, key, v in greeter if key == "LookAndFeelPackage"]
    _check_set(root, "greeter (.install)", greeter,
               ("dark" in g_lnf[0].lower()) if g_lnf else None, errors)
    written = set(re.findall(r'cat > "\$[dk]/([^"]+)"', text))
    chowned = set(re.findall(r'"\$d"/(\S+)', text)) | set(re.findall(r'"\$k/([^"]+)"', text))
    for f in sorted(written - chowned):
        errors.append(f"greeter (.install): kdedefaults/{f} is written but not chowned to plasmalogin")
    for m in re.finditer(r'"(/usr/share/icons/[^"]+)"', text):
        if not (root / m.group(1).lstrip("/")).is_dir() and not m.group(1).endswith("/hicolor"):
            errors.append(f".install ICON_DIRS: {m.group(1)} is not shipped")

    # 4. Icons the panel templates name must be findable by the icon loader:
    # in hicolor (always searched) or in a listed Directories= entry.
    icons = root / "usr/share/icons"
    for js in (root / "usr/share/plasma/layout-templates").rglob("*.js"):
        for m in re.finditer(r'writeConfig\("icon",\s*"([^"]+)"', js.read_text(encoding="utf-8")):
            name, found = m.group(1), False
            for theme in icons.iterdir() if icons.is_dir() else ():
                idx = theme / "index.theme"
                dirs = (["*"] if theme.name == "hicolor" else
                        _ini(idx.read_text()).get("Icon Theme", "Directories", fallback="").split(",")
                        if idx.is_file() else [])
                for d in filter(None, (x.strip() for x in dirs)):
                    if list(theme.glob(f"{d}/{name}.*")) or list(theme.glob(f"{d}/*/{name}.*")):
                        found = True
            if not found:
                errors.append(f"{js.relative_to(root)}: icon '{name}' is not in hicolor or "
                              "any listed icon-theme directory (the loader will not find it)")
    # KWin's blur indexes a 15-entry table with BlurStrength (blur.cpp,
    # numOfBlurSteps = 15) with no bounds check: >15 crashes KWin.
    for path in [*(root / "etc").rglob("*"), *(root / "usr/share/plasma/look-and-feel").rglob("defaults"),
                 *(root / "usr/lib/shani").glob("*.sh")]:
        if not path.is_file() or path.suffix in (".png", ".svg", ".svgz"):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for m in re.finditer(r"BlurStrength(?:=|\s+)(\d+)", text):
            if not 1 <= int(m.group(1)) <= 15:
                errors.append(f"{path.relative_to(root)}: BlurStrength {m.group(1)} outside KWin's 1-15 "
                              "(out-of-bounds read, KWin crashes when blur renders)")
    # A decoration named in kwinrc / look-and-feel defaults must be shipped:
    # Aurorae v2 needs aurorae/themes/<name>/{metadata.desktop,<name>rc,decoration.svg};
    # a missing one silently falls back to Breeze.
    for path in [root / "etc/skel/.config/kwinrc", *lnf_root.glob("*/contents/defaults")]:
        for m in re.finditer(r"theme=__aurorae__svg__(\S+)", path.read_text(encoding="utf-8")):
            d = root / "usr/share/aurorae/themes" / m.group(1)
            for need in ("metadata.desktop", f"{m.group(1)}rc", "decoration.svg", "close.svg"):
                if not (d / need).is_file():
                    errors.append(f"{path.relative_to(root)}: decoration {m.group(1)} lacks {need}")

    # Yakuake reads Skin from [Appearance] (yakuake.kcfg); under [Window] it is
    # ignored and the stock skin shows.
    yrc = root / "etc/skel/.config/yakuakerc"
    if yrc.is_file():
        cp = _ini(yrc.read_text(encoding="utf-8"))
        if cp.has_option("Window", "Skin"):
            errors.append("etc/skel/.config/yakuakerc: Skin under [Window] (Yakuake reads [Appearance])")
        skin = cp.get("Appearance", "Skin", fallback=None)
        if skin and not (root / "usr/share/yakuake/skins" / skin / "title.skin").is_file():
            errors.append(f"etc/skel/.config/yakuakerc: Skin={skin} is not a shipped Yakuake skin")

    # Konsole (and Yakuake) read a profile's colour scheme from [Appearance]
    # only; one under [General] is silently ignored (stock Breeze colours).
    for prof in (root / "etc/skel").rglob("*.profile"):
        cp = _ini(prof.read_text(encoding="utf-8"))
        if cp.has_option("General", "ColorScheme"):
            errors.append(f"{prof.relative_to(root)}: ColorScheme under [General] (Konsole reads [Appearance])")
        scheme = cp.get("Appearance", "ColorScheme", fallback=None)
        if scheme and not (root / "usr/share/konsole" / f"{scheme}.colorscheme").is_file():
            errors.append(f"{prof.relative_to(root)}: ColorScheme={scheme} is not a shipped Konsole scheme")
        # No Command= does NOT get the login shell: Profile::Command is inherited
        # from the built-in profile as defaultShell() = qgetenv("SHELL") (konsole
        # Profile.cpp), so with $SHELL unset (systemd unit, non-login su) it is
        # empty and Session::run() warns and silently runs bash. Pin the shell.
        if not cp.get("General", "Command", fallback=None):
            errors.append(
                f"{prof.relative_to(root)}: no Command= under [General]; it inherits "
                "qgetenv(\"SHELL\") and warns/falls back to bash when $SHELL is unset"
            )

    # DefaultProfile resolves under GenericDataLocation/konsole (~/.local/share/
    # konsole, /usr/share/konsole) - not the yakuake/profiles path the name suggests -
    # and a dangling name silently leaves konsole's built-in profile in place.
    for rc_name, profile_dirs in (
        ("etc/skel/.config/yakuakerc", ("etc/skel/.local/share/konsole",)),
        ("etc/skel/.config/konsolerc", ("etc/skel/.local/share/konsole",)),
    ):
        rc = root / rc_name
        if not rc.is_file():
            continue
        default_profile = _ini(rc.read_text(encoding="utf-8")).get(
            "Desktop Entry", "DefaultProfile", fallback=None
        )
        if not default_profile:
            continue
        if not any((root / d / default_profile).is_file() for d in profile_dirs):
            errors.append(
                f"{rc.relative_to(root)}: DefaultProfile={default_profile} matches no "
                f"shipped profile in {', '.join(profile_dirs)} (konsole silently uses its built-in)"
            )
    return errors


def main(argv: list[str]) -> int:
    root = find_package_root(Path(argv[1]) if len(argv) > 1 else None)

    print(f"Validating package at: {root}")
    all_errors = []

    all_errors.extend(validate_metadata_consistency(root))
    all_errors.extend(validate_unique_desktop_theme_ids(root))
    all_errors.extend(validate_expected_assets(root))
    all_errors.extend(validate_no_stale_references(root))
    all_errors.extend(validate_symlinks(root))
    all_errors.extend(validate_color_schemes(root))
    all_errors.extend(validate_theme_references(root))

    if all_errors:
        print("\nVALIDATION FAILED:")
        for err in all_errors:
            print(f"  ERROR: {err}")
        return 1

    print("\nAll validation checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))