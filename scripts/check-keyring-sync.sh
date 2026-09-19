#!/usr/bin/env bash
# check-keyring-sync.sh - verify shani-keyring file checksums match the
# sha256sums=() a shani-keyring PKGBUILD pins.
#
# Guards the P0 drift case in shani-pkgbuilds/AGENTS.md ("Cross-repo impact"):
# the files in the shani-keyring repo changing without the PKGBUILD here being
# re-pinned breaks a fresh install with a checksum mismatch, and the gap is
# invisible until then.
#
# Modes:
#   --live (default)          fetch each source= URL (curl; wget fallback),
#                             sha256 it, compare to the declared sum. This is
#                             exactly what makepkg downloads and checks. A
#                             curl/network ERROR is a WARN (non-fatal; keeps
#                             offline devs unblocked); a checksum MISMATCH is a
#                             hard failure (exit 1).
#   --keyring-repo <path>     compare <path>/<filename> directly (no network),
#                             using the filename derived from each source URL.
#                             For CI where shani-keyring is checked out out
#                             alongside pkgbuilds.
#
# Usage:
#   check-keyring-sync.sh [--live|--keyring-repo <path>] <pkgbuild>
#
# Mirrors check-skip-checksums.sh: sources the PKGBUILD under `timeout 10` in a
# subshell via the __extract worker (a PKGBUILD can do arbitrary work on source),
# reads the parallel source=() and sha256sums=() arrays (makepkg pairs them by
# index), exits 1 on any mismatch.

set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--live|--keyring-repo <path>] <pkgbuild>

Verify shani-keyring file checksums against a shani-keyring PKGBUILD's
sha256sums=() array.

  --live (default)        fetch each source= URL and checksum the downloaded
                          content (what makepkg will actually verify). Network
                          errors are WARNED (non-fatal); mismatches FAIL.
  --keyring-repo <path>   compare <path>/<filename> directly instead of
                          fetching (offline; for CI with the keyring repo
                          checked out).
EOF
}

# --- internal worker: emit (source\x1esha256sum) pairs from a PKGBUILD -----
# Invoked as: bash "$0" __extract <pkgbuild>. Mirrors check-skip-checksums.sh,
# which sources the PKGBUILD under `timeout 10` (safety against a PKGBUILD that
# does heavy work on source). source=() and sha256sums=() are parallel arrays
# per makepkg (index i <-> index i).
if [[ "${1:-}" == "__extract" ]]; then
pkgbuild="$2"
    # PKGBUILD is data to parse, not a script to execute: it is sourced by
    # design, and source=/sha256sums are read from it, not assigned here.
    # shellcheck disable=SC1090,SC2154
    source "$pkgbuild"
    # shellcheck disable=SC2154  # source=/sha256sums come from the PKGBUILD, not here
    if declare -p source &>/dev/null && declare -p sha256sums &>/dev/null; then
        for i in "${!source[@]}"; do
            printf '%s\x1e%s\n' "${source[$i]}" "${sha256sums[$i]:-MISSING}"
        done
    fi
    exit 0
fi

# --- argument parsing ---
LIVE=true
KEYRING_REPO=""
PKGBUILD=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --live)          LIVE=true; shift ;;
        --keyring-repo)  LIVE=false; KEYRING_REPO="${2:?--keyring-repo requires a <path>}"
                         shift 2 ;;
        -h|--help)       usage; exit 0 ;;
        --*)             echo "$SCRIPT_NAME: unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)
            if [[ -z "$PKGBUILD" ]]; then
                PKGBUILD="$1"
            else
                echo "$SCRIPT_NAME: unexpected extra argument: $1" >&2
                exit 2
            fi
            shift ;;
    esac
done

if [[ -z "$PKGBUILD" ]]; then
    echo "$SCRIPT_NAME: no PKGBUILD path given" >&2
    usage >&2
    exit 2
fi
if [[ "$LIVE" == false && -z "$KEYRING_REPO" ]]; then
    echo "$SCRIPT_NAME: --keyring-repo requires a <path>" >&2
    exit 2
fi
if [[ ! -f "$PKGBUILD" ]]; then
    echo "$SCRIPT_NAME: PKGBUILD not found: $PKGBUILD" >&2
    exit 2
fi

pkgbuild="$(realpath "$PKGBUILD")"

# --- helpers ---

# Fetch a URL to a temp file; return 0 on HTTP success, non-zero on curl/wget
# error (caller treats this as a non-fatal WARN, not a checksum mismatch).
fetch_url() {
    local out="$1" url="$2"
    if command -v curl &>/dev/null; then
        curl --fail --silent --show-error --retry 2 --retry-delay 1 \
             --connect-timeout 5 --max-time 20 -o "$out" "$url"
    else
        wget -q --tries=3 --timeout=20 -O "$out" "$url"
    fi
}

compute_sha256() {
    if command -v sha256sum &>/dev/null; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# Strip makepkg source= decoration to the raw download URL:
#   "name::url" -> "url"   (rename prefix)
#   "?signed"   -> dropped (git-source signing flag)
#   "#commit=…" -> dropped (immutable commit fragment; the raw file at the URL
#                  is what we checksum, the same as makepkg fetches)
raw_url() {
    local src="$1"
    src="${src#*::}"      # strip optional "name::" rename prefix
    src="${src%%\?*}"     # strip query string (incl. ?signed)
    src="${src%%#*}"      # strip fragment (incl. #commit=sha)
    printf '%s' "$src"
}

# The on-disk filename a source URL refers to (last path component).
filename_of_url() {
    basename "$(raw_url "$1")"
}

# --- main: extract pairs from the PKGBUILD ---
if ! pairs=$(timeout 10 bash "$0" __extract "$pkgbuild" 2>/dev/null); then
    echo "${SCRIPT_NAME}: failed to source PKGBUILD (or timed out): $pkgbuild" >&2
    echo "════════════════════════════════════════════════"
    echo "Keyring checksum sync — PARSE FAILED"
    echo "════════════════════════════════════════════════"
    exit 1
fi

MISMATCH=()
WARN=()
OK=()

while IFS=$'\x1e' read -r src sum; do
    [[ -z "$src" ]] && continue

    url="$(raw_url "$src")"
    fname="$(filename_of_url "$src")"

    if [[ "$LIVE" == true ]]; then
        tmp="$(mktemp)"
        if fetch_url "$tmp" "$url"; then
            actual="$(compute_sha256 "$tmp")"
            if [[ "$actual" == "$sum" ]]; then
                OK+=("$fname: $sum")
            else
                MISMATCH+=("$fname: declared=$sum actual=$actual")
            fi
            rm -f "$tmp"
        else
            WARN+=("$fname: could not fetch $url (network) — skipped")
            rm -f "$tmp" 2>/dev/null || true
        fi
    else
        local_file="${KEYRING_REPO%/}/${fname}"
        if [[ -f "$local_file" ]]; then
            actual="$(compute_sha256 "$local_file")"
            if [[ "$actual" == "$sum" ]]; then
                OK+=("$fname: $sum")
            else
                MISMATCH+=("$fname: declared=$sum actual=$actual (keyring repo file)")
            fi
        else
            WARN+=("$fname: not found in keyring repo: $local_file — skipped")
        fi
    fi
done <<< "$pairs"

echo "════════════════════════════════════════════════"
echo "Keyring checksum sync"
echo "════════════════════════════════════════════════"
if [[ ${#OK[@]} -gt 0 ]]; then
    printf '    ✓ %s\n' "${OK[@]}"
fi
if [[ ${#WARN[@]} -gt 0 ]]; then
    echo "⚠ ${#WARN[@]} warning(s):"
    printf '    ⚠ %s\n' "${WARN[@]}"
fi
if [[ ${#MISMATCH[@]} -gt 0 ]]; then
    echo "✗ Found ${#MISMATCH[@]} checksum mismatch(es):"
    printf '    ✗ %s\n' "${MISMATCH[@]}"
    echo
    echo "MISMATCH — shani-keyring file checksums do not match $pkgbuild sha256sums=."
    echo "Either the upstream keyring changed (regenerate with updpkgsums and"
    echo "bump pkgrel) or a checksum was entered incorrectly."
    exit 1
fi

if [[ ${#OK[@]} -gt 0 && ${#WARN[@]} -gt 0 ]]; then
    echo "All checked checksums match; warnings above are non-fatal (network/skipped)."
elif [[ ${#OK[@]} -gt 0 && ${#WARN[@]} -eq 0 && ${#MISMATCH[@]} -eq 0 ]]; then
    echo "All keyring checksums match"
elif [[ ${#OK[@]} -eq 0 && ${#WARN[@]} -gt 0 && ${#MISMATCH[@]} -eq 0 ]]; then
    echo "No files checked (all skipped — network/missing); nothing failed."
fi

exit 0
