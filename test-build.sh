#!/usr/bin/env bash
# test-build.sh — Build a single PKGBUILD locally using podman for faster feedback.
#
# Adapted from chaotic-portable-builder's cpb script pattern.
# Gives faster feedback than spinning up the full Docker container
# (which takes ~2 minutes to start). Podman is lighter and can use
# --userns=keep-id for writable bind-mounts without chown.
#
# Usage:
#   ./test-build.sh <package-name>
#   ./test-build.sh --all
#
# Prerequisites:
#   - podman installed
#   - shani-builder image pulled (podman pull docker.io/shrinivasvkumbhar/shani-builder)
#   - run_in_container.sh symlink works (shani-pkgbuilds → shani-install-media)
#
# Note: This is a lightweight alternative to ./run_in_container.sh make_pkg.sh.
# Use ./run_in_container.sh make_pkg.sh <package> for full Docker builds.
# Use this script for quick local iteration and faster feedback loops.

set -Eeuo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
RUNNER="${SCRIPT_DIR}/run_in_container.sh"

if [ ! -x "$RUNNER" ]; then
    echo "Error: run_in_container.sh not found or not executable at: $RUNNER"
    echo "Ensure the symlink to shani-install-media/run_in_container.sh is intact."
    exit 1
fi

if ! command -v podman &>/dev/null; then
    echo "Error: podman not found. Install podman or use ./run_in_container.sh for Docker builds."
    exit 1
fi

# Check if the shani-builder image exists locally
if ! podman images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -q "shani-builder"; then
    echo "Pulling shani-builder image with podman..."
    timeout 120 podman pull docker.io/shrinivasvkumbhar/shani-builder || echo "Could not pull — using cached image"
fi

# Build using podman with --userns=keep-id for writable bind-mounts
echo "Building with podman (--userns=keep-id) for faster local feedback..."
echo "Package: ${1:---all}"

# Delegate to run_in_container.sh which handles runtime detection,
# but force podman mode via the CONTAINER_RUNTIME env override
export CONTAINER_RUNTIME="podman"
export PODMAN_KEEP_ID="1"

"$RUNNER" "$@"
