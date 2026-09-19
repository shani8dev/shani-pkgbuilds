#!/usr/bin/env bash
# TDD harness for scripts/check-keyring-sync.sh (no external deps).
#   G1 green  : repo checksums match declared PKGBUILD sha256sums (exit 0)
#   G1-live   : live-fetched content matches too (skip if offline, non-fatal)
#   G2 red    : a PKGBUILD copy with one checksum corrupted is REJECTED (exit 1)
#
# Repo's AGENTS.md mandates the "corrupt-then-rebuild" proof for any checksum
# work — i.e. prove a checker actually rejects tampered content, not just that
# it's present. G2 is that proof.
set -Eeuo pipefail
cd "$(dirname "$0")/.."   # repo root — so all paths below resolve

SCRIPT=./scripts/check-keyring-sync.sh
PKGKEYRING=shani-keyring/PKGBUILD
# Auto-detect the keyring layout. Three shapes exist:
#   * local dev:  sibling checkout at ../shani-keyring
#   * CI (security.yml / check-keyring-sync.yml): child checkout at
#     shani-keyring-repo — it CANNOT be `shani-keyring` because shani-pkgbuilds
#     already tracks its own shani-keyring/ dir (this repo's PKGBUILD + .install),
#     and actions/checkout@v4 refuses to clone into a non-empty existing dir.
# Verified live: all three layouts resolve to the same shani.gpg/trusted/revoked.
if [[ -d ../shani-keyring ]]; then
    KEYRING_REPO=../shani-keyring
elif [[ -d shani-keyring-repo ]]; then
    KEYRING_REPO=shani-keyring-repo
elif [[ -d shani-keyring ]]; then
    KEYRING_REPO=shani-keyring
else
    KEYRING_REPO=../shani-keyring
fi
PASS=0; FAIL=0

ok()  { printf '    ✓ %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '    ✗ %s\n' "$1"; FAIL=$((FAIL+1)); }

echo "════════════════════════════════════════════════"
echo "check-keyring-sync.sh tests"
echo "════════════════════════════════════════════════"

# --- G1: green via local keyring-repo (hermetic, no network) ---
echo "G1: --keyring-repo (expect PASS / exit 0)"
if "$SCRIPT" --keyring-repo "$KEYRING_REPO" "$PKGKEYRING" 2>&1; then
    ok "G1 green — keyring files match PKGBUILD sha256sums"
else
    bad "G1 green — expected pass, got failure"
fi

# --- G1-live: green via live fetch (CI-equivalent); skip gracefully if offline ---
echo "G1-live: --live fetch (expect PASS / exit 0, skip if offline)"
g1_rc=0
g1_out=$("$SCRIPT" "$PKGKEYRING" 2>&1) || g1_rc=$?
if [[ $g1_rc -eq 0 && "$g1_out" == *"All keyring checksums match"* ]]; then
    ok "G1-live green — fetched content matches"
elif [[ $g1_rc -eq 0 && "$g1_out" == *"non-fatal"* ]]; then
    ok "G1-live skipped — no network (non-fatal)"
else
    bad "G1-live — unexpected exit $g1_rc: $g1_out"
fi

# --- G2: mismatch rejected (corrupt one declared checksum, keep real files) ---
echo "G2: corrupted PKGBUILD (expect FAIL / exit 1 + MISMATCH)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
cp "$PKGKEYRING" "$tmpdir/PKGBUILD"
# Corrupt the first declared sha256sum so it cannot match reality.
# Extract the first 64-hex sha256sum from the (unmodified) PKGBUILD and
# replace it with zeros — a hardcoded hash here silently no-ops if the
# upstream hash ever changes, which is exactly how this test went red.
first_hash=$(grep -oE '[0-9a-f]{64}' "$PKGKEYRING" | head -1)
if [[ -z "$first_hash" ]]; then
    bad "G2 mismatch — no 64-hex sha256sum found in $PKGKEYRING to corrupt"
else
    sed -i "s/$first_hash/0000000000000000000000000000000000000000000000000000000000000000/" "$tmpdir/PKGBUILD"
    g2_rc=0
    g2_out=$("$SCRIPT" --keyring-repo "$KEYRING_REPO" "$tmpdir/PKGBUILD" 2>&1) || g2_rc=$?
    if [[ $g2_rc -eq 1 && "$g2_out" == *"MISMATCH"* ]]; then
        ok "G2 mismatch — rejected corrupt checksum (exit 1)"
    else
        bad "G2 mismatch — expected exit 1 + MISMATCH (got exit $g2_rc): $g2_out"
    fi
fi

echo "────────────────────────────────"
echo "results: $PASS passed, $FAIL failed"
echo "────────────────────────────────"
[[ $FAIL -eq 0 ]]
