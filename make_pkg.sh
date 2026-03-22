#!/bin/bash
# make_pkg.sh – Build one or more packages inside the shani-builder container.
# Always syncs the pacman DB before the first build.
#
# Usage:
#   ./make_pkg.sh <pkg-dir> [pkg-dir2 ...]
#   ./make_pkg.sh --all
#
# Options:
#   --updpkgsums  Run updpkgsums before building each package
#   --all         Build every subdirectory that contains a PKGBUILD
#
# Examples:
#   ./make_pkg.sh shani-core
#   ./make_pkg.sh shani-core shani-tools
#   ./make_pkg.sh --updpkgsums shani-core
#   ./make_pkg.sh --all

set -Eeuo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
RUNNER="${SCRIPT_DIR}/run_in_container.sh"
UPDPKGSUMS="${SCRIPT_DIR}/updpkgsums.sh"

if [ ! -x "$RUNNER" ]; then
    echo "Error: run_in_container.sh not found or not executable at: $RUNNER"
    exit 1
fi

if [ ! -x "$UPDPKGSUMS" ]; then
    echo "Error: updpkgsums.sh not found or not executable at: $UPDPKGSUMS"
    exit 1
fi

# ── Argument parsing ──────────────────────────────────────────────────────────
ALL=false
UPD=false
PACKAGES=()

for arg in "$@"; do
    case "$arg" in
        --all)          ALL=true ;;
        --updpkgsums)   UPD=true ;;
        -*)             echo "Unknown option: $arg"; exit 1 ;;
        *)              PACKAGES+=("$arg") ;;
    esac
done

# ── Collect package list ──────────────────────────────────────────────────────
if $ALL; then
    while IFS= read -r pkgbuild; do
        PACKAGES+=("$(dirname "$pkgbuild")")
    done < <(find "$SCRIPT_DIR" -maxdepth 2 -name PKGBUILD | sort)
fi

if [ "${#PACKAGES[@]}" -eq 0 ]; then
    echo "Usage: $0 [--updpkgsums] <pkg-dir> [pkg-dir2 ...]"
    echo "       $0 [--updpkgsums] --all"
    exit 1
fi

# ── pacman DB sync runs once before the first build ───────────────────────────
SYNC_CMD="sudo pacman -Sy --noconfirm && "

# ── Build each package ────────────────────────────────────────────────────────
FAILED=()
BUILT=()

for pkg in "${PACKAGES[@]}"; do
    pkg_name="$(basename "${pkg%/}")"
    abs_pkg_dir="${SCRIPT_DIR}/${pkg_name}"

    if [ ! -f "${abs_pkg_dir}/PKGBUILD" ]; then
        echo ""
        echo "!!! Skipping '${pkg_name}': no PKGBUILD found."
        FAILED+=("${pkg_name} (no PKGBUILD)")
        continue
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ">>> Building: ${pkg_name}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if $UPD; then
        echo ">>> Updating checksums: ${pkg_name}"
        if ! "$UPDPKGSUMS" "${pkg_name}"; then
            echo "!!! updpkgsums failed for: ${pkg_name}, skipping build."
            FAILED+=("${pkg_name} (updpkgsums)")
            continue
        fi
    fi

    # The container mounts SCRIPT_DIR as /build,
    # so the package subdir is at /build/<pkg_name>
    BUILD_CMD="${SYNC_CMD}cd /build/${pkg_name} && makepkg -s --noconfirm --noprogressbar"

    if "$RUNNER" bash -c "$BUILD_CMD"; then
        BUILT+=("${pkg_name}")
        # DB is fresh after first build — no need to sync again
        SYNC_CMD=""
    else
        echo "!!! Build failed for: ${pkg_name}"
        FAILED+=("${pkg_name}")
    fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════"
echo "Build summary"
echo "════════════════════════════════════════════════"
if [ "${#BUILT[@]}" -gt 0 ]; then
    echo "✓ Built (${#BUILT[@]}):"
    printf '    %s\n' "${BUILT[@]}"
fi
if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "✗ Failed (${#FAILED[@]}):"
    printf '    %s\n' "${FAILED[@]}"
    exit 1
fi
echo ""
echo "Done."
