#!/usr/bin/env python3
"""Package validator for shani-desktop-plasma.

Validates:
- Metadata directory/ID consistency
- Unique desktop-theme IDs
- Expected theme assets present
- No stale SaturnLight/SaturnTwilight references in active package files
- Symlink resolution within package tree
"""
from __future__ import annotations

import json
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
        required_files = [
            "metadata.json",
            "colors",
            "plasmarc",
            "widgets/background.svg",
            "widgets/panel-background.svg",
            "widgets/tooltip.svg",
            "dialogs/background.svg",
        ]
        for rel in required_files:
            if not (theme_root / rel).exists():
                errors.append(f"Missing {theme}/{rel}")

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
            "contents/previews/preview.png",
            "contents/previews/fullscreenpreview.png",
        ]
        for rel in required_files:
            if not (theme_root / rel).exists():
                errors.append(f"Missing {theme}/{rel}")

        # Splash images
        splash_images = theme_root / "contents/splash/images"
        if not splash_images.exists() or not any(splash_images.iterdir()):
            errors.append(f"Missing or empty {theme}/contents/splash/images")

    # Expected yakuake skin
    yakuake_root = root / "usr/share/yakuake/skins/Saturn"
    if not yakuake_root.exists():
        errors.append("Missing yakuake skin: Saturn")
    else:
        required_files = [
            "metadata.json",
            "metadata.desktop",
            "title.skin",
            "tabs.skin",
            "main.svg",
        ]
        for rel in required_files:
            if not (yakuake_root / rel).exists():
                errors.append(f"Missing yakuake/Saturn/{rel}")

        for subdir in ("title", "tabs"):
            subdir_path = yakuake_root / subdir
            if not subdir_path.exists() or not any(subdir_path.iterdir()):
                errors.append(f"Missing or empty yakuake/Saturn/{subdir}")

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

    for file_path in root.rglob("*"):
        if not file_path.is_symlink():
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

    if all_errors:
        print("\nVALIDATION FAILED:")
        for err in all_errors:
            print(f"  ERROR: {err}")
        return 1

    print("\nAll validation checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))