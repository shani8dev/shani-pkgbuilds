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
KEYRING_REPO=../shani-keyring
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
# Corrupt the first declared sha256 (shani.gpg's) so it cannot match reality.
sed -i 's/03c03d69fd8d281d73ecaa68ac313c3a3f8d2e60d1796573aa3e8a8f54428362/0000000000000000000000000000000000000000000000000000000000000000/' "$tmpdir/PKGBUILD"
g2_rc=0
g2_out=$("$SCRIPT" --keyring-repo "$KEYRING_REPO" "$tmpdir/PKGBUILD" 2>&1) || g2_rc=$?
if [[ $g2_rc -eq 1 && "$g2_out" == *"MISMATCH"* ]]; then
    ok "G2 mismatch — rejected corrupt checksum (exit 1)"
else
    bad "G2 mismatch — expected exit 1 + MISMATCH (got exit $g2_rc): $g2_out"
fi

echo "────────────────────────────────"
echo "results: $PASS passed, $FAIL failed"
echo "────────────────────────────────"
[[ $FAIL -eq 0 ]]
