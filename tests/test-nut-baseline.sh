#!/usr/bin/env bash
#
# test-nut-baseline.sh - test shani-settings.install's install_nut_baseline.
#
# The four NUT configs used to be SHIPPED in the package, which is wrong:
# `nut` owns /etc/nut/{nut,ups,upsd,upsmon}.conf and shani-peripherals
# depends on `nut`, so every profile installed both and pacstrap refused the
# whole transaction with "conflicting files". No image of any profile could
# build. They now live in /usr/share/shani/nut/ as templates and are written
# into /etc/nut by the install hook.
#
# So the function's whole job is deciding, per file, whether the bytes on disk
# are the admin's or ours. Get that wrong in one direction and an upgrade
# silently discards someone's configuration; in the other and a corrected
# baseline can never reach an existing install. Both are tested here against
# real files on disk, with the manifest driven through every branch.
#
# Writes to /etc/nut, /usr/share/shani/nut and /var/lib/shani-settings, so run
# it ONLY in a disposable Arch container:
#
#   SHANI_TEST_DISPOSABLE=1 bash tests/test-nut-baseline.sh
set -uo pipefail

[[ "${SHANI_TEST_DISPOSABLE:-}" == 1 ]] || {
    echo "refusing: writes to /etc/nut and /usr/share/shani; set SHANI_TEST_DISPOSABLE=1 in a throwaway container" >&2
    exit 2
}

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PKG_DIR="$HERE/../shani-settings"
INSTALL="$PKG_DIR/shani-settings.install"
SRC_ROOT="${1:-$HERE/../shani-settings-src}"

PASSES=0
FAILS=0
pass() { printf '  ok   %s\n' "$1"; PASSES=$((PASSES + 1)); }
fail() { printf '  FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }

ETCD=/etc/nut
SHARED=/usr/share/shani/nut
STATE=/var/lib/shani-settings/nut-baseline.sha256
FILES=(nut.conf ups.conf upsd.conf upsmon.conf)

[[ -r $INSTALL ]] || { echo "no $INSTALL" >&2; exit 2; }

# Only the function under test, so the rest of the hook (systemctl enable,
# samba group juggling) does not run.
eval "$(awk '/^install_nut_baseline\(\) \{/,/^\}/' "$INSTALL")"
declare -F install_nut_baseline >/dev/null || { echo "install_nut_baseline not found in $INSTALL" >&2; exit 2; }

reset_nut() {   # a "fresh install": nut's own stock config, nothing of ours
    rm -rf "$ETCD" "$SHARED" "$STATE"
    mkdir -p "$ETCD" "$SHARED"
    for f in "${FILES[@]}"; do
        printf '# stock %s shipped by the nut package\n' "$f" >"$ETCD/$f"
    done
    cp -r "$SRC_ROOT/usr/share/shani/nut/." "$SHARED/"
}

stock_digest() { sha256sum "$ETCD/$1" 2>/dev/null | cut -d' ' -f1; }
ours_digest()  { sha256sum "$SHARED/$1" 2>/dev/null | cut -d' ' -f1; }

# `pacman -Qkk nut` is the only question the function asks about files it has
# no manifest entry for, so it is the one thing worth driving from outside.
# Default: nut is absent from the container, so it reports nothing and the
# files look untouched - which is what a first install looks like.
stub_pacman() {
    mkdir -p /tmp/nuttest-bin
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*"\ncat <<'"'"'EOF'"'"'\n%s\nEOF\n' "$1" >/tmp/nuttest-bin/pacman
    chmod +x /tmp/nuttest-bin/pacman
    export PATH="/tmp/nuttest-bin:$PATH"
}
stub_pacman ""

echo "install_nut_baseline"

# 1. first install takes over nut's stock config
reset_nut
out=$(install_nut_baseline 2>&1); rc=$?
all_ours=yes
for f in "${FILES[@]}"; do
    [[ $(stock_digest "$f") == $(ours_digest "$f") ]] || all_ours=no
done
[[ $rc == 0 && $all_ours == yes ]] \
    && pass "first install replaces nut's stock config with our templates" \
    || fail "first install (rc=$rc, all_ours=$all_ours): $out"
[[ -f $STATE ]] && pass "manifest written" || fail "no manifest at $STATE"

# 2. idempotent: a second run changes nothing at all. Compares inode as well
#    as content - `install` builds a new file, so a rewrite that happens to
#    produce identical bytes is still a rewrite, and an upgrade hook that
#    rewrites four files on every run is not idempotent.
before=$(stat -c '%i %s' "$ETCD"/* | sha256sum)
out=$(install_nut_baseline 2>&1); rc=$?
after=$(stat -c '%i %s' "$ETCD"/* | sha256sum)
[[ $rc == 0 && $before == "$after" ]] \
    && pass "re-running changes nothing (idempotent, not even a rewrite)" \
    || fail "second run was not idempotent: $out"

# 3. a corrected baseline reaches an existing install, via the manifest
printf '# improved %s\n' nut.conf >"$SHARED/nut.conf"
install_nut_baseline >/dev/null 2>&1
[[ $(stock_digest nut.conf) == $(ours_digest nut.conf) ]] \
    && pass "improved template propagates to an existing install" \
    || fail "improved template did not reach an existing install"

# 4. the admin's edit survives a baseline that changed under it
printf '# the admin was here\n' >"$ETCD/ups.conf"
printf '# improved again\n' ups.conf >"$SHARED/ups.conf"
out=$(install_nut_baseline 2>&1)
[[ $(cat "$ETCD/ups.conf") == "# the admin was here" ]] \
    && pass "admin edit is never clobbered" \
    || fail "admin edit was overwritten: $(cat "$ETCD/ups.conf")"
grep -q 'ups.conf was modified' <<<"$out" \
    && pass "and the admin is told, not left to guess" \
    || fail "admin edit was skipped silently: $out"
grep -q ' ups.conf$' "$STATE" \
    && fail "manifest claims a file the admin owns" \
    || pass "manifest does not claim the admin's file"

# 5. a file we own that goes missing is restored. Without a manifest branch
#    for absence this reads as "the admin edited it", because there is no
#    longer anything to compare against.
rm -f "$ETCD/upsd.conf"
out=$(install_nut_baseline 2>&1)
[[ $(stock_digest upsd.conf) == $(ours_digest upsd.conf) ]] \
    && pass "a file of ours that went missing is restored" \
    || fail "missing file not restored"
grep -q 'upsd.conf was missing' <<<"$out" \
    && pass "and the restore is reported" \
    || fail "restore happened silently: $out"

# 6. pacman says nut's file was modified and we have no manifest entry:
#    that is the admin's, so leave it alone. Without the manifest this is the
#    only evidence available, so it has to be believed.
reset_nut
rm -f "$STATE"
printf '# edited by hand, no manifest knows about this\n' >"$ETCD/nut.conf"
stub_pacman 'warning: nut: /etc/nut/nut.conf (Modification detected)'
out=$(install_nut_baseline 2>&1)
[[ $(cat "$ETCD/nut.conf") == "# edited by hand, no manifest knows about this" ]] \
    && pass "pacman's 'Modification detected' is honoured with no manifest" \
    || fail "overwrote a file pacman reported as modified"
# ...and the reason is tested, not merely the path: a file pacman reports as
# MISSING is not a modification, and must still be taken over.
reset_nut
rm -f "$STATE"
stub_pacman 'warning: nut: /etc/nut/ups.conf (No such file or directory)'
install_nut_baseline >/dev/null 2>&1
[[ $(stock_digest ups.conf) == $(ours_digest ups.conf) ]] \
    && pass "'No such file or directory' is not read as a modification" \
    || fail "treated a missing file as a modification and refused to take it over"
stub_pacman ""

echo
echo "the conflict that broke every image build"

# 7. THE REGRESSION GUARD. The package must not ship anything under etc/nut.
# This is the assertion whose absence let the bug through: the configs were
# packaged and verified for runtime behaviour, but nothing ever asked whether
# pacman would accept the file list.
shipped=$(cd "$SRC_ROOT" 2>/dev/null && git ls-files etc/nut 2>/dev/null)
[[ -z $shipped ]] \
    && pass "source tree ships nothing under etc/nut" \
    || fail "source tree still ships: $shipped"
[[ -f $SHARED/nut.conf && -f $SHARED/upsmon.conf ]] \
    && pass "templates present in usr/share/shani/nut" \
    || fail "templates missing from usr/share/shani/nut"

# 8. the move preserved the bytes. The hardening is the whole point of these
#    files, and a hand-edit during the move would not fail anything else here.
if [[ -d $SRC_ROOT/.git ]] && git -C "$SRC_ROOT" -c safe.directory='*' show HEAD:etc/nut/nut.conf >/dev/null 2>&1; then
    moved_ok=yes
    for f in "${FILES[@]}"; do
        orig=$(git -C "$SRC_ROOT" -c safe.directory='*' show "HEAD:etc/nut/$f" 2>/dev/null | sha256sum | cut -d' ' -f1)
        [[ -n $orig && $orig == $(sha256sum "$SRC_ROOT/usr/share/shani/nut/$f" | cut -d' ' -f1) ]] || moved_ok=no
    done
    [[ $moved_ok == yes ]] \
        && pass "move preserved every file byte-for-byte" \
        || fail "template content differs from what was in etc/nut"
else
    echo "  skip move-preserved-bytes (git could not read HEAD:etc/nut here; not a content failure)"
fi

echo
if [[ $FAILS -eq 0 ]]; then echo "All nut baseline checks passed ($PASSES)"; exit 0; fi
echo "$FAILS nut baseline check(s) failed"; exit 1