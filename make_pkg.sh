#!/bin/bash
# make_pkg.sh – Build one or more packages and/or refresh their checksums
# inside the shani-builder container. Consolidates the former make_pkg.sh,
# updpkgsums.sh, and test-build.sh into one entry point.
#
# Usage:
#   ./make_pkg.sh <pkg-dir> [pkg-dir2 ...]             build (default)
#   ./make_pkg.sh --updpkgsums <pkg-dir> [...]         refresh checksums, then build
#   ./make_pkg.sh --sums-only <pkg-dir> [...]          refresh checksums only (was updpkgsums.sh)
#   ./make_pkg.sh --all                                every subdir containing a PKGBUILD
#
# Examples:
#   ./make_pkg.sh shani-core
#   ./make_pkg.sh --sums-only epson-inkjet-printer-escpr
#   ./make_pkg.sh --updpkgsums --all
#
# Runtime: run_in_container.sh auto-detects docker, falling back to podman —
# the old test-build.sh "force podman" wrapper was removed because its env
# exports were dead (the runner overwrites CONTAINER_RUNTIME and never reads
# PODMAN_KEEP_ID / never passes --userns=keep-id).

set -Eeuo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
RUNNER="${SCRIPT_DIR}/run_in_container.sh"

if [ ! -x "$RUNNER" ]; then
    echo "Error: run_in_container.sh not found or not executable at: $RUNNER"
    exit 1
fi

# ── Argument parsing ──────────────────────────────────────────────────────────
ALL=false
SUMS_ONLY=false
UPD=false
PACKAGES=()

for arg in "$@"; do
    case "$arg" in
        --all)          ALL=true ;;
        --sums-only)    SUMS_ONLY=true ;;
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
    echo "Usage: $0 [--updpkgsums|--sums-only] <pkg-dir> [pkg-dir2 ...]"
    echo "       $0 [--updpkgsums|--sums-only] --all"
    exit 1
fi

# ── Container step ────────────────────────────────────────────────────────────
# One entry point for both modes. The runner mounts SCRIPT_DIR at
# $CONTAINER_WORK_DIR=/home/builduser/build (NOT /build) and runs as root, but
# makepkg refuses root and the bind mount is host-owned (1001 ≠ builduser) —
# so every step runs in a chowned /var/tmp/pmk scratch copy as builduser, then
# copies its outputs back. /var/tmp is used because the container's /tmp is a
# noexec tmpfs (verified live: /tmp/exec_test → "Permission denied") which
# kills any build that executes ./configure from the scratch dir. WORK is
# captured from \${PWD} BEFORE the scratch `cd` — after that cd, \${PWD} is
# the scratch dir, so using \${PWD} directly in a copy-back is wrong
# (caught live: cp: target '/var/tmp/pmk/brscan4/brscan4/'). $q_pkg is
# %q-quoted against injection via a caller-supplied package name.
container_step() {  # $1 = pkg_name, $2 = inner command sequence
    local q_pkg
    q_pkg="$(printf '%q' "$1")"
    "$RUNNER" /bin/bash -c "
WORK=\${PWD}
rm -rf /var/tmp/pmk && mkdir -p /var/tmp/pmk && \
cp -a \${WORK}/${q_pkg} /var/tmp/pmk/ && \
chown -R builduser:builduser /var/tmp/pmk/${q_pkg} && \
cd /var/tmp/pmk/${q_pkg} && \
# The runner mounts /tmp as a noexec tmpfs (same reason the scratch copy
# above lives in /var/tmp) — tools that exec their own temp output (Go's
# go-build, Rust's target dir, etc.) default TMPDIR to /tmp and would die
# with 'fork/exec ... permission denied' (caught live on snapd's build()).
export TMPDIR=/var/tmp && \
$2"
}

# ── Process each package ──────────────────────────────────────────────────────
FAILED=()
UPDATED=()
BUILT=()
# pacman DB sync before EVERY build — each build spawns a fresh container whose
# DB is at the image snapshot, and the mirror rotates old package versions, so
# syncing only the first build of a multi-package run 404s on the rest
# (caught live: poppler-26.07.0-1/nss 404s in builds #2/#3 of brscan4-escpr-escpr2).
SYNC_CMD="sudo pacman -Sy --noconfirm && "

for pkg in "${PACKAGES[@]}"; do
    pkg_name="$(basename "${pkg%/}")"
    q_pkg="$(printf '%q' "$pkg_name")"
    abs_pkg_dir="${SCRIPT_DIR}/${pkg_name}"

    if [ ! -f "${abs_pkg_dir}/PKGBUILD" ]; then
        echo ""
        echo "!!! Skipping '${pkg_name}': no PKGBUILD found."
        FAILED+=("${pkg_name} (no PKGBUILD)")
        continue
    fi

    if $UPD || $SUMS_ONLY; then
        echo ""
        echo ">>> Updating checksums: ${pkg_name}"
        if container_step "$pkg_name" \
"runuser -u builduser -- bash -c 'updpkgsums && makepkg --printsrcinfo > .SRCINFO' && \
cp /var/tmp/pmk/${q_pkg}/PKGBUILD /var/tmp/pmk/${q_pkg}/.SRCINFO \${WORK}/${q_pkg}/"; then
            UPDATED+=("${pkg_name}")
        else
            echo "!!! updpkgsums failed for: ${pkg_name}, skipping build."
            FAILED+=("${pkg_name} (updpkgsums)")
            continue
        fi
    fi

    if ! $SUMS_ONLY; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ">>> Building: ${pkg_name}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        # -f: the scratch copy echoes the host dir, which already holds any artifact
        # from a previous run — without --force makepkg aborts with "A package has
        # already been built" before producing any output (caught live: brscan4's
        # second build failed exactly this way after its first run copied the .zst back).
        if container_step "$pkg_name" \
"${SYNC_CMD}runuser -u builduser -- makepkg -sf --noconfirm --noprogressbar && \
cp /var/tmp/pmk/${q_pkg}/*.pkg.tar.zst \${WORK}/${q_pkg}/ && \
ls -l \${WORK}/${q_pkg}/*.pkg.tar.zst"; then
            BUILT+=("${pkg_name}")
        else
            echo "!!! Build failed for: ${pkg_name}"
            FAILED+=("${pkg_name}")
        fi
    fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════"
echo "Summary"
echo "════════════════════════════════════════════════"
if [ "${#UPDATED[@]}" -gt 0 ]; then
    echo "✓ Checksums updated (${#UPDATED[@]}):"
    printf '    %s\n' "${UPDATED[@]}"
fi
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
