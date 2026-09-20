#!/usr/bin/env bash
# check-commit-sync.sh - detect (and optionally fix) stale _commit pins in
# this repo's first-party shani* PKGBUILDs.
#
# shani-pkgbuilds/AGENTS.md calls this out explicitly: "Every shani-*
# first-party package here packages the *actual source repo* of the same
# name - if that source repo changes, this repo's matching PKGBUILD needs
# a pkgrel bump to match, or the packaged artifact silently drifts from
# what's actually in the source repo. There is currently no automated
# check that catches this drift."
#
# This script is that check. For every PKGBUILD that pins a source to a
# commit via _commit=, it resolves that repo's default-branch HEAD and
# reports whether the pin is stale (behind HEAD) or current (at HEAD).
#
# Modes:
#   (default)          report only; exit 1 if any pin is stale/unresolved
#   -a | --apply       update stale _commit= pins to upstream HEAD and bump
#                      pkgrel by 1, so the packaged artifact tracks the
#                      source repo
#
# Usage:
#   check-commit-sync.sh [--apply] [<pkg-dir> ... | --all]
#
# Exit codes:
#   0   every resolvable pin is at upstream HEAD
#   1   at least one pin is stale or could not be resolved
#   2   usage error (unknown option / missing PKGBUILD)
#
# Mirrors its sibling checkers' shape (check-skip-checksums.sh,
# check-keyring-sync.sh): the PKGBUILD is sourced under `timeout` in a
# subshell via the __extract worker (a PKGBUILD can do arbitrary work on
# source), its _commit/source/pkgrel are read from it, and network errors
# are WARNs (non-fatal), not hard failures.

set -Eeuo pipefail
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--apply] [<pkg-dir> ... | --all]

Detect pkgs whose pinned _commit= is behind their upstream repo's HEAD.

  --apply    rewrite _commit= to upstream HEAD and bump pkgrel in each
             stale PKGBUILD. Dry-run by default: report only.
  --all      check every PKGBUILD in the repo (the default when no
             <pkg-dir> is given)
  <pkg-dir>  check only these package(s); repeatable

Exit 0 when every resolved pin is current; 1 when any is stale or could
not be resolved; 2 on usage errors.
EOF
}

# --- internal worker: emit (commit<tab>pkgrel<tab>repo) from a PKGBUILD ----
# Invoked as: bash "$0" __extract <pkgbuild>. Source the PKGBUILD under
# `timeout` like the sibling checkers, then emit the fields we need. The
# repo URL is derived from the first `source=`/`url=` entry that references
# a commit pin. Only forms actually seen in this repo are recognized; bare
# local file sources / raw.githubusercontent URLs have no repo to check and
# are emitted as an empty repo (the caller skips those).
if [[ "${1:-}" == "__extract" ]]; then
    pkgbuild="$2"
    # Pre-define the makepkg-provided environment a PKGBUILD may reference at
    # top level (CARCH/CHOST/var names) so `set -u` doesn't abort on one
    # (real case: brscan4's PKGBUILD reads $CARCH when sourced). Keep the
    # list to the common ones — if a package needs another, mk preserves the
    # working pattern: make_pkg.sh runs PKGBUILDs under real makepkg.
    CARCH="${CARCH:-x86_64}"
    CHOST="${CHOST:-x86_64-pc-linux-gnu}"
    CFLAGS="${CFLAGS:-}"
    CXXFLAGS="${CXXFLAGS:-}"
    LDFLAGS="${LDFLAGS:-}"
    pkgdir="${pkgdir:-/pkg}"
    srcdir="${srcdir:-/src}"
    # shellcheck disable=SC1090  # PKGBUILD is data to parse, not executed here
    source "$pkgbuild"
    # shellcheck disable=SC2154  # _commit/source/url/pkgrel come from the PKGBUILD

    commit="${_commit:-}"
    repo=""

    if declare -p source &>/dev/null; then
        for s in "${source[@]}"; do
            # strip optional "name::" rename prefix and any ?signed/#fragment
            s="${s#*::}"
            s="${s%%\?*}"
            s="${s%%#*}"
            case "$s" in
                git+*://*/*.git)
                    s="${s#git+}"
                    s="${s%.git}"
                    repo="$s"
                    ;;
            esac
            [[ -n "$repo" ]] && break
        done
    fi
    # A source that's an owner/repo/archive/<commit>.tar.gz has the repo in
    # the URL even without git+ decoration.
    if [[ -z "$repo" ]] && declare -p source &>/dev/null; then
        for s in "${source[@]}"; do
            s="${s#*::}"
            s="${s%%\?*}"
            s="${s%%#*}"
            if [[ "$s" =~ ^https://([^/]+)/([^/]+)/([^/]+)/archive/ ]]; then
                # only treat it as pin-referencing if it embeds _commit
                [[ "$s" == *"${_commit:-}"* ]] && repo="https://${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/${BASH_REMATCH[3]}"
                [[ -n "$repo" ]] && break
            fi
        done
    fi
    # Fall back to url= for the repo when source= has none.
    if [[ -z "$repo" ]] && declare -p url &>/dev/null; then
        repo="${url%%\?*}"
        repo="${repo%%#*}"
    fi

    # commit could be quoted or carry a trailing comment when sourced from a
    # PKGBUILD line like _commit='abc123...'  # Replace ...
    commit="${commit//\"/}"
    commit="${commit//\'/}"
    # Sentinel for "no pin" so the leading field position survives a `read`
    # (bash collapses leading/multiple IFS delimiters).
    [[ -z "$commit" ]] && commit="NONE"
    # shellcheck disable=SC2154
    printf '%s\t%s\t%s\n' "$commit" "${pkgrel:-}" "$repo"
    exit 0
fi

# --- helpers ---
# Resolve upstream default-branch HEAD for a repo URL via ls-remote (works
# for both git+ sources and tarball/archive sources).
resolve_head() {
    local repo="$1"
    local out
    out="$(timeout 15 git ls-remote "$repo" HEAD 2>/dev/null)" || return 1
    awk '{print $1; exit}' <<< "$out"
}

# --- argument parsing ---
APPLY=false
ALL=false
PACKAGES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--apply)  APPLY=true; shift ;;
        --all)       ALL=true; shift ;;
        -h|--help)   usage; exit 0 ;;
        --*)         echo "$SCRIPT_NAME: unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)           PACKAGES+=("$1"); shift ;;
    esac
done

if $ALL && [[ ${#PACKAGES[@]} -gt 0 ]]; then
    echo "$SCRIPT_NAME: --all cannot be combined with explicit packages" >&2
    exit 2
fi
if [[ ${#PACKAGES[@]} -eq 0 ]]; then
    ALL=true
fi

if $ALL; then
    while IFS= read -r pkgbuild; do
        PACKAGES+=("$(dirname "$pkgbuild")")
    done < <(find "$REPO_ROOT" -maxdepth 2 -name PKGBUILD | sort)
fi
# --- main ---
STALE_PKGS=()    # "pkg_dir\thead_sha\tpkgrel\trepo"
CURRENT_PKGS=()
UNRESOLVED=()
SKIPPED=()

for pkg in "${PACKAGES[@]}"; do
    pkg_name="$(basename "${pkg%/}")"
    pkgbuild="$REPO_ROOT/${pkg_name}/PKGBUILD"

    if [[ ! -f "$pkgbuild" ]]; then
        echo "$SCRIPT_NAME: no PKGBUILD at $pkgbuild - skipping" >&2
        SKIPPED+=("$pkg_name (no PKGBUILD)")
        continue
    fi

    fields="$(timeout 10 bash "$0" __extract "$pkgbuild" 2>/dev/null)" || {
        SKIPPED+=("$pkg_name (could not parse PKGBUILD)")
        continue
    }
    # shellcheck disable=SC2034  # parsed via read
    IFS=$'\t' read -r commit pkgrel repo <<< "$fields"

    if [[ -z "$commit" || "$commit" == "NONE" || "$commit" != [0-9a-f]* ]]; then
        SKIPPED+=("$pkg_name (no _commit pin)")
        continue
    fi
    if [[ -z "$repo" ]]; then
        SKIPPED+=("$pkg_name (no repo derivable)")
        continue
    fi

    head="$(resolve_head "$repo")" || true
    if [[ -z "$head" ]]; then
        UNRESOLVED+=("$pkg_name ($repo)")
        continue
    fi

    if [[ "$head" == "$commit" ]]; then
        CURRENT_PKGS+=("$pkg_name (pkgrel=$pkgrel): pinned at HEAD ${commit:0:8}")
    else
        STALE_PKGS+=("$pkg_name"$'\t'"$head"$'\t'"$pkgrel"$'\t'"$repo")
    fi
done
echo "════════════════════════════════════════════════"
echo "Pinned-commit sync check"
echo "════════════════════════════════════════════════"

if [[ ${#CURRENT_PKGS[@]} -gt 0 ]]; then
    echo "✓ ${#CURRENT_PKGS[@]} pin(s) current:"
    printf '    ✓ %s\n' "${CURRENT_PKGS[@]}"
fi
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    echo "– ${#SKIPPED[@]} skipped (no pin / no repo / unparseable):"
    printf '    – %s\n' "${SKIPPED[@]}"
fi
if [[ ${#UNRESOLVED[@]} -gt 0 ]]; then
    echo "⚠ ${#UNRESOLVED[@]} pin(s) could not be resolved (network):"
    printf '    ⚠ %s\n' "${UNRESOLVED[@]}"
fi
if [[ ${#STALE_PKGS[@]} -gt 0 ]]; then
    echo "✗ ${#STALE_PKGS[@]} stale pin(s) (pinned != upstream HEAD):"
    for entry in "${STALE_PKGS[@]}"; do
        # shellcheck disable=SC2034
        IFS=$'\t' read -r pkg_name head pkgrel repo <<< "$entry"
        printf '    ✗ %s (pkgrel=%s): pinned != HEAD %s (%s)\n' "$pkg_name" "$pkgrel" "${head:0:8}" "$repo"
    done
fi
apply_bump() {
    local pkg_name="$1" new_commit="$2"
    local pkgbuild="$REPO_ROOT/${pkg_name}/PKGBUILD"
    local old_pkgrel new_pkgrel
    old_pkgrel="$(awk -F= '/^pkgrel=/{print $2; exit}' "$pkgbuild")"
    new_pkgrel=$(( old_pkgrel + 1 ))

    # Replace only the pinned hex value and the pkgrel number, in place;
    # everything else (quoting style, trailing # comment, surrounding text)
    # is preserved byte-for-byte. The hex pattern is anchored to a 40-char
    # [0-9a-f] run so it can't touch the source= line's ${_commit} expansion.
    sed -ri \
        -e "s/^(_commit=['\"]?)[0-9a-fA-F]{40}/\1${new_commit}/" \
        -e "s/^pkgrel=[0-9]+/pkgrel=${new_pkgrel}/" \
        "$pkgbuild"
    echo "    → $pkg_name: _commit -> ${new_commit:0:8}, pkgrel $old_pkgrel -> $new_pkgrel"
}

if [[ ${#STALE_PKGS[@]} -gt 0 ]]; then
    echo ""
    if $APPLY; then
        echo "Applying ${#STALE_PKGS[@]} _commit update(s) + pkgrel bump(s)..."
        for entry in "${STALE_PKGS[@]}"; do
            # shellcheck disable=SC2034
            IFS=$'\t' read -r pkg_name head pkgrel repo <<< "$entry"
            apply_bump "$pkg_name" "$head"
        done
        echo "Done. Review with: git diff"
        echo "Then rebuild each changed package: ./make_pkg.sh <pkg-dir>"
    else
        echo "Stale. Run with --apply to bump _commit to HEAD and pkgrel +1."
    fi
fi

echo ""
if [[ ${#UNRESOLVED[@]} -gt 0 ]]; then
    echo "⚠ ${#UNRESOLVED[@]} pin(s) unresolved (network unavailable?) - exit 1."
    exit 1
fi
if [[ ${#STALE_PKGS[@]} -gt 0 ]]; then
    if $APPLY; then
        echo "All stale pins updated. Re-run to confirm clean (exit 0)."
        exit 0
    fi
    echo "✗ ${#STALE_PKGS[@]} stale pin(s) - exit 1. Run with --apply to bump them."
    exit 1
fi
echo "All resolvable pins are current."
exit 0
