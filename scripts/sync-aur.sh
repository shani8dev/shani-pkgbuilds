#!/usr/bin/env bash
# sync-aur.sh - sync a package directory's build files from upstream AUR.
#
# Fetches the current AUR snapshot for a package, diffs its PKGBUILD and
# auxiliary build files (patches, .install, etc.) against the local copy,
# and reports exactly what changed. With --apply it replaces the local
# build files with the AUR versions and `git add`s them.
#
# What it intentionally does NOT do:
#   - touch .SRCINFO (regen locally: ./make_pkg.sh --sums-only <dir>)
#   - delete files AUR no longer ships (reported as "superseded" so the
#     operator can `git rm` them deliberately, e.g. a dropped patch)
#   - second-guess checksums/SKIPs: repo rules (see AGENTS.md) demand real
#     checksums for remote sources and repo-specific pins (hplip-minimal's
#     _plugin_sha256). The tool copies PKGBUILD verbatim and warns when it
#     contains 'SKIP' so the operator restores the repo model before build.
#
# Usage:
#   sync-aur.sh <pkg-dir> [aur-pkgname] [--apply]
#
# Examples:
#   ./scripts/sync-aur.sh splix                  # dry-run diff vs AUR splix
#   ./scripts/sync-aur.sh hplip-minimal --apply  # copy AUR files, git add
#   ./scripts/sync-aur.sh my-dir aur-name --apply # dir name != AUR name
#
# After --apply: ./make_pkg.sh --sums-only <pkg-dir>  (real sums + .SRCINFO)
#               ./make_pkg.sh <pkg-dir>                (real build)

set -Eeuo pipefail

AUR_BASE="https://aur.archlinux.org/cgit/aur.git/snapshot"
APPLY=false

usage() {
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

is_build_file() {
    local name="$1"
    case "$name" in
        PKGBUILD | *.patch | *.diff | *.install | *.hook | *.service | \
        *.timer | *.conf | *.rules | *.desktop | *.png | *.svg | *.cookies)
            return 0 ;;
        *) return 1 ;;
    esac
}

# --- arg parsing ---
declare -a args=()
for a in "$@"; do
    case "$a" in
        --apply) APPLY=true ;;
        --help | -h) usage 0 ;;
        -*) echo "unknown option: $a" >&2; usage 1 ;;
        *) args+=("$a") ;;
    esac
done
[ "${#args[@]}" -ge 1 ] || usage 1

dir="${args[0]}"
pkg="${args[1]:-$(basename "$dir")}"

[ -d "$dir" ] || { echo "error: no such directory: $dir" >&2; exit 1; }
[ -f "$dir/PKGBUILD" ] || { echo "error: no PKGBUILD in $dir" >&2; exit 1; }

# --- fetch + extract AUR snapshot ---
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
snap_tar="$tmp/$pkg.tar.gz"
echo "fetching AUR snapshot: $AUR_BASE/$pkg.tar.gz"
curl -fsSL -o "$snap_tar" "$AUR_BASE/$pkg.tar.gz"
snap_pkg="$tmp/snap/$pkg"
mkdir -p "$tmp/snap"
tar -xzf "$snap_tar" -C "$tmp/snap"
[ -f "$snap_pkg/PKGBUILD" ] || { echo "error: snapshot for '$pkg' has no PKGBUILD (wrong AUR name?)" >&2; exit 1; }

mapfile -t snap_files < <(find "$snap_pkg" -maxdepth 1 -type f -printf '%f\n' | sort)
mapfile -t local_files < <(find "$dir" -maxdepth 1 -type f -printf '%f\n' | sort)

# --- version summary ---
echo "--- version ---"
ver() { grep -m1 -E "^$1=" "$2" || true; }
v_local="$(ver pkgver "$dir/PKGBUILD")-$(ver pkgrel "$dir/PKGBUILD")"
v_aur="$(ver pkgver "$snap_pkg/PKGBUILD")-$(ver pkgrel "$snap_pkg/PKGBUILD")"
e_local="$(ver epoch "$dir/PKGBUILD")"
e_aur="$(ver epoch "$snap_pkg/PKGBUILD")"
printf 'local  %s%s\n' "$v_local" "${e_local:+ epoch=$e_local}"
printf 'aur    %s%s\n' "$v_aur" "${e_aur:+ epoch=$e_aur}"

# --- diff each AUR build file ---
echo "--- build files ---"
declare -a to_copy=()
declare -a extras=()
for f in "${snap_files[@]}"; do
    case "$f" in
        .SRCINFO)
            echo "  .SRCINFO  (skipped - regen locally via --sums-only)"
            continue ;;
    esac
    if ! is_build_file "$f"; then
        extras+=("$f"); echo "  $f  (AUR-only extra, not synced)"
        continue
    fi
    if [ ! -f "$dir/$f" ]; then
        echo "  $f  NEW in AUR (absent locally)"
        to_copy+=("$f")
    elif cmp -s "$dir/$f" "$snap_pkg/$f"; then
        echo "  $f  identical"
    else
        echo "  $f  CHANGED (local vs AUR):"
        diff -u "$dir/$f" "$snap_pkg/$f" | sed 's/^/      /' || true
        to_copy+=("$f")
    fi
done

# --- superseded local build files ---
declare -a superseded=()
for f in "${local_files[@]}"; do
    if is_build_file "$f" && [ ! -e "$snap_pkg/$f" ]; then
        superseded+=("$f")
    fi
done
if [ "${#superseded[@]}" -gt 0 ]; then
    echo "--- superseded (local build files AUR no longer ships) ---"
    for f in "${superseded[@]}"; do
        echo "  $f"
    done
    echo "  (git rm these deliberately if the new PKGBUILD no longer references them)"
fi

if [ "$APPLY" = true ]; then
    echo "--- applying ---"
    for f in "${to_copy[@]}"; do
        cp "$snap_pkg/$f" "$dir/$f"
        echo "  copied  $f"
        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            git add "$dir/$f"
        fi
    done
    if grep -q "'SKIP'" "$dir/PKGBUILD"; then
        echo "  WARNING: applied PKGBUILD contains 'SKIP' checksum(s) - restore"
        echo "  real checksums / repo pins before build (see AGENTS.md)."
    fi
    echo "--- next steps ---"
    echo "  ./make_pkg.sh --sums-only $dir   # real sums + fresh .SRCINFO"
    echo "  ./make_pkg.sh $dir               # real build"
else
    echo "(dry run - re-run with --apply to copy the changed/new files)"
fi
