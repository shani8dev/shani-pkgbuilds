#!/bin/bash
# check-skip-checksums.sh – Flag SKIP checksums on non-VCS sources.
#
# sha256sums=('SKIP') (and the sha1/sha512/b2/md5 variants) is only a
# legitimate gap-filler for a VCS source pinned to a specific commit/tag
# (git+, svn+, hg+, bzr+ in the source= URL) — the pin itself is the
# integrity anchor there. On any other source (a plain tarball/file URL),
# SKIP means the download has no integrity check at all.
#
# This has slipped in unnoticed before (hplip-minimal's real SourceForge
# tarball; the now-removed shani-dracut-secureboot's local file sources) —
# this script exists to catch the next one before it ships.
#
# Usage:
#   ./check-skip-checksums.sh <pkg-dir> [pkg-dir2 ...]
#   ./check-skip-checksums.sh --all
#
# Exit code: 0 if nothing flagged, 1 if at least one SKIP was found on a
# non-VCS source (or a PKGBUILD couldn't be parsed).

set -Eeuo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# ── Internal worker mode ─────────────────────────────────────────────────────
# Re-invoked as `bash check-skip-checksums.sh __extract PKGBUILD_PATH` under
# `timeout`, in its own process, so a PKGBUILD that runs something network-
# bound at the top level (a few here resolve _commit via a bare
# `$(git ls-remote ...)` outside any function, which executes immediately on
# source) can't hang the main run — it just times out like any other parse
# failure. Kept as a re-exec of this same file instead of an inline `bash -c`
# string to avoid a nested-quoting mess around the printf/array syntax below.
if [[ "${1:-}" == "__extract" ]]; then
    pkgbuild="$2"
    # shellcheck disable=SC1090
    source "$pkgbuild"
    for suffix in "" _x86_64 _i686 _aarch64; do
        src_var="source${suffix}"
        sum_var="sha256sums${suffix}"
        [[ -v "$src_var" ]] || continue
        [[ -v "$sum_var" ]] || continue
        declare -n _srcs="$src_var"
        declare -n _sums="$sum_var"
        for i in "${!_srcs[@]}"; do
            printf '%s\x1e%s\n' "${_srcs[$i]}" "${_sums[$i]:-MISSING}"
        done
        unset -n _srcs _sums
    done
    exit 0
fi

ALL=false
PACKAGES=()
for arg in "$@"; do
    case "$arg" in
        --all) ALL=true ;;
        -*) echo "Unknown option: $arg" >&2; exit 1 ;;
        *)  PACKAGES+=("$arg") ;;
    esac
done

if $ALL; then
    while IFS= read -r pkgbuild; do
        PACKAGES+=("$(dirname "$pkgbuild")")
    done < <(find "$SCRIPT_DIR" -maxdepth 2 -name PKGBUILD | sort)
fi

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
    echo "Usage: $0 <pkg-dir> [pkg-dir2 ...]"
    echo "       $0 --all"
    exit 1
fi

# is_pinned_source URL — true if SKIP is legitimate for this source because
# its content is already immutably pinned some other way.
is_pinned_source() {
    local url="$1"
    # VCS source (git+/svn+/hg+/bzr+) — the #commit=/#tag= fragment is the
    # integrity anchor.
    [[ "$url" =~ ^(git|svn|hg|bzr)\+ ]] && return 0
    # No URL scheme at all — a bare filename shipped in the package's own
    # directory. There's no network fetch to protect against; its integrity
    # is exactly this git repo's integrity, same as the PKGBUILD itself.
    [[ "$url" != *://* ]] && return 0
    # A path segment that's a full 40-hex-char commit hash (e.g. GitHub's
    # /archive/<commit>.tar.gz) is just as immutable as a git+ source pinned
    # to that same commit — the hash IS the content pin.
    [[ "$url" =~ /[0-9a-f]{40}(\.(tar\.gz|tar\.xz|tar\.bz2|zip)|/) ]] && return 0
    return 1
}

FLAGGED=()
PARSE_FAILED=()

for pkg in "${PACKAGES[@]}"; do
    pkg_name="$(basename "${pkg%/}")"
    pkgbuild="${SCRIPT_DIR}/${pkg_name}/PKGBUILD"

    if [[ ! -f "$pkgbuild" ]]; then
        PARSE_FAILED+=("${pkg_name} (no PKGBUILD)")
        continue
    fi

    pairs=$(timeout 10 bash "$0" __extract "$pkgbuild" 2>/dev/null) || {
        PARSE_FAILED+=("${pkg_name} (failed to source PKGBUILD, or timed out)")
        continue
    }

    [[ -z "$pairs" ]] && continue

    while IFS=$'\x1e' read -r src sum; do
        [[ -z "$src" ]] && continue
        # Strip a "name::url" rename prefix before checking the URL scheme.
        url="${src#*::}"
        if [[ "$sum" == "SKIP" ]] && ! is_pinned_source "$url"; then
            FLAGGED+=("${pkg_name}: SKIP on non-VCS source: ${url}")
        fi
    done <<< "$pairs"
done

echo "════════════════════════════════════════════════"
echo "SKIP-checksum lint"
echo "════════════════════════════════════════════════"
if [[ ${#FLAGGED[@]} -gt 0 ]]; then
    echo "✗ Found ${#FLAGGED[@]} SKIP checksum(s) on a non-VCS source:"
    printf '    %s\n' "${FLAGGED[@]}"
fi
if [[ ${#PARSE_FAILED[@]} -gt 0 ]]; then
    echo "! Could not check ${#PARSE_FAILED[@]} package(s):"
    printf '    %s\n' "${PARSE_FAILED[@]}"
fi
if [[ ${#FLAGGED[@]} -eq 0 && ${#PARSE_FAILED[@]} -eq 0 ]]; then
    echo "✓ No illegitimate SKIP checksums found."
fi

(( ${#FLAGGED[@]} > 0 )) && exit 1
exit 0
