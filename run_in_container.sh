#!/bin/bash
# run_in_container.sh – Runs a command inside the shani-builder container.
# Used internally by make_pkg.sh and updpkgsums.sh.

set -Eeuo pipefail

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <command> [arguments]"
    exit 1
fi

HOST_WORK_DIR="$(dirname "$(realpath "$0")")"

# ── Paths ─────────────────────────────────────────────────────────────────────
HOST_PACMAN_CACHE="${HOST_WORK_DIR}/cache/pacman_cache"
mkdir -p "${HOST_PACMAN_CACHE}"

CONTAINER_WORK_DIR="/build"
CONTAINER_PACMAN_CACHE="/var/cache/pacman"

DOCKER_IMAGE="docker.io/shrinivasvkumbhar/shani-builder"
CUSTOM_MIRROR="https://mirror.albony.in/archlinux/\$repo/os/\$arch"

# ── TTY detection ─────────────────────────────────────────────────────────────
if [ -t 0 ]; then TTY_FLAGS="-it"; else TTY_FLAGS="-i"; fi

# ── Runtime detection ────────────────────────────────────────────────────────
# `--userns=keep-id` (which remaps the container's user to the invoking host
# UID, so bind-mounted files stay writable without a chown dance) is a
# Podman-only extension. Real Docker's CLI rejects it outright:
#   docker: --userns: invalid USER mode
# Many distros symlink /usr/bin/docker -> podman (Podman's Docker-compatible
# shim), in which case `docker --version` self-reports as "podman version
# ...". Only pass the flag when that's actually what's answering to `docker`;
# real Docker just runs as --user builduser without it (uid mismatches with
# the bind mount are then the caller's problem, same as before this script
# existed).
USERNS_FLAGS=()
if docker --version 2>/dev/null | grep -qi podman; then
    USERNS_FLAGS=(--userns=keep-id)
fi

# ── Run ───────────────────────────────────────────────────────────────────────
docker run $TTY_FLAGS --privileged --rm "${USERNS_FLAGS[@]}" --user builduser \
    -v "${HOST_WORK_DIR}:${CONTAINER_WORK_DIR}:z" \
    -v "${HOST_PACMAN_CACHE}:${CONTAINER_PACMAN_CACHE}" \
    -e CUSTOM_MIRROR="${CUSTOM_MIRROR}" \
    -e HOME=/tmp \
    -w "${CONTAINER_WORK_DIR}" \
    "${DOCKER_IMAGE}" \
    bash -c "$(printf '%q ' "$@")"
