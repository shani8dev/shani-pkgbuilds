#!/bin/bash
# updpkgsums.sh – Run updpkgsums inside the shani-builder container
# for one, many, or all packages.
#
# Usage:
#   ./updpkgsums.sh <pkg-dir> [pkg-dir2 ...]
#   ./updpkgsums.sh --all

set -Eeuo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
RUNNER="${SCRIPT_DIR}/run_in_container.sh"

if [ ! -x "$RUNNER" ]; then
    echo "Error: run_in_container.sh not found or not executable at: $RUNNER"
    exit 1
fi

# ── Argument parsing ──────────────────────────────────────────────────────────
ALL=false
PACKAGES=()

for arg in "$@"; do
    case "$arg" in
        --all) ALL=true ;;
        -*)    echo "Unknown option: $arg"; exit 1 ;;
        *)     PACKAGES+=("$arg") ;;
    esac
done

if $ALL; then
    while IFS= read -r pkgbuild; do
        PACKAGES+=("$(dirname "$pkgbuild")")
    done < <(find "$SCRIPT_DIR" -maxdepth 2 -name PKGBUILD | sort)
fi

if [ "${#PACKAGES[@]}" -eq 0 ]; then
    echo "Usage: $0 <pkg-dir> [pkg-dir2 ...]"
    echo "       $0 --all"
    exit 1
fi

# ── Process each package ──────────────────────────────────────────────────────
FAILED=()
UPDATED=()

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
    echo ">>> updpkgsums: ${pkg_name}"

    if "$RUNNER" bash -c "cd /build/${pkg_name} && updpkgsums && makepkg --printsrcinfo > .SRCINFO"; then
        UPDATED+=("${pkg_name}")
    else
        echo "!!! updpkgsums failed for: ${pkg_name}"
        FAILED+=("${pkg_name}")
    fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════"
echo "updpkgsums summary"
echo "════════════════════════════════════════════════"
if [ "${#UPDATED[@]}" -gt 0 ]; then
    echo "✓ Updated (${#UPDATED[@]}):"
    printf '    %s\n' "${UPDATED[@]}"
fi
if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "✗ Failed (${#FAILED[@]}):"
    printf '    %s\n' "${FAILED[@]}"
    exit 1
fi
echo ""
echo "Done."
