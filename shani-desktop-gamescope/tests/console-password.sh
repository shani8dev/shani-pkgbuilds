#!/bin/bash
# Container test (see run.sh): the console account, its locked password and the
# boot-time first-password helper, against the image's own system-auth.
# Mounts: /pkg = this package, /sa = the image's pam.d/system-auth.
# Runs inside archlinux container. /pkg = shani-desktop-gamescope, /sa = system-auth
set -u
pacman -Syu --noconfirm --needed sudo python >/dev/null 2>&1 || { echo "FAIL setup: pacman"; exit 1; }
cp /sa /etc/pam.d/system-auth
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
for g in input video render audio storage network; do getent group $g >/dev/null || groupadd $g; done
svc=/pkg/usr/lib/systemd/system/gamescope-session-user.service
run_unit() {  # emulate systemd ExecStart lines ($$ -> $)
  grep '^ExecStart=' "$svc" | sed 's/^ExecStart=//; s/\$\$/$/g' | while IFS= read -r line; do eval "$line" >/dev/null 2>&1 || echo "  step failed: $line"; done
}
pass=0; fail=0
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }
asroot_via_sudo() { su -s /bin/bash gamescope -c 'echo "" | sudo -S -p "" id -u' 2>/dev/null; }

# 1. old behaviour (passwd -d) for reference
useradd -m -g users -G wheel gamescope; passwd -d gamescope >/dev/null
check "old: empty password gives sudo root (negative control)" '[ "$(asroot_via_sudo)" = 0 ]'
# 2. upgrade path: the unit locks the empty password
run_unit
check "upgrade: empty password locked" '[ "$(passwd -S gamescope | cut -d" " -f2)" = L ]'
check "upgrade: sudo denied" '[ "$(asroot_via_sudo)" != 0 ]'
# 3. fresh install
userdel -r gamescope 2>/dev/null; run_unit
check "fresh: user exists in wheel" 'id -nG gamescope | grep -qw wheel'
check "fresh: password locked" '[ "$(passwd -S gamescope | cut -d" " -f2)" = L ]'
check "fresh: sudo denied" '[ "$(asroot_via_sudo)" != 0 ]'
# 4. autologin PAM path still works on a locked account (acct_mgmt + setcred, like greetd)
cat > /tmp/pamt.py <<'PY'
import ctypes, sys
pam = ctypes.CDLL("libpam.so.0")
class conv(ctypes.Structure): _fields_=[("f",ctypes.c_void_p),("d",ctypes.c_void_p)]
CB = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)
cb = CB(lambda *a: 0)
c = conv(ctypes.cast(cb, ctypes.c_void_p), None)
h = ctypes.c_void_p()
r = pam.pam_start(b"login", sys.argv[1].encode(), ctypes.byref(c), ctypes.byref(h))
a = pam.pam_acct_mgmt(h, 0); s = pam.pam_setcred(h, 2)
print(a, s)
PY
check "fresh: PAM acct_mgmt ok for autologin (login service)" '[ "$(python /tmp/pamt.py gamescope | cut -d" " -f1)" = 0 ]'
# 5. helper
H=/pkg/usr/lib/shani-desktop-gamescope/console-password
U=$(id -u gamescope)
mkdir -p /stub; export PATH=/stub:$PATH
answers() { printf '%s\n' "$@" > /tmp/answers; cat > /stub/systemd-ask-password <<'S'
#!/bin/bash
l=$(head -1 /tmp/answers); sed -i 1d /tmp/answers; echo "$l"
S
chmod +x /stub/systemd-ask-password; }
check "helper: status refuses another caller" '! PKEXEC_UID=0 $H --status 2>/dev/null'
check "helper: no stdin set mode" '! echo hunter22 | PKEXEC_UID=$U $H 2>/dev/null; [ "$(passwd -S gamescope | cut -d" " -f2)" = L ]'
check "helper: status unset" '[ "$(PKEXEC_UID=$U $H --status)" = unset ]'
check "helper: --boot refused from a pkexec session" 'touch /var/lib/x 2>/dev/null; mkdir -p /var/lib/shani-gamescope; touch /var/lib/shani-gamescope/password-requested; answers pw-bad1 pw-bad1; ! PKEXEC_UID=$U $H --boot 2>/dev/null && [ "$(passwd -S gamescope | cut -d" " -f2)" = L ]'
rm -f /var/lib/shani-gamescope/password-requested
check "boot: nothing without a request" 'answers zzzz1 zzzz1; $H --boot && [ "$(passwd -S gamescope | cut -d" " -f2)" = L ]'
check "helper: request" 'PKEXEC_UID=$U $H --request >/dev/null && [ -e /var/lib/shani-gamescope/password-requested ]'
check "boot: empty answer skips, request consumed" 'answers ""; $H --boot >/dev/null && [ ! -e /var/lib/shani-gamescope/password-requested ] && [ "$(passwd -S gamescope | cut -d" " -f2)" = L ]'
PKEXEC_UID=$U $H --request >/dev/null
check "boot: mismatch then short then match sets it" 'answers aaaa1 bbbb1 ab s3cret-pw s3cret-pw; $H --boot | grep -q "Console password set" && [ "$(passwd -S gamescope | cut -d" " -f2)" = P ]'
check "helper: status set" '[ "$(PKEXEC_UID=$U $H --status)" = set ]'
check "helper: request refused once set" 'PKEXEC_UID=$U $H --request 2>/dev/null; [ $? = 3 ]'
PKEXEC_UID=$U $H --request >/dev/null 2>&1; touch /var/lib/shani-gamescope/password-requested
check "boot: never overwrites an existing password" 'answers other-pw other-pw; $H --boot >/dev/null; [ "$(passwd -S gamescope | cut -d" " -f2)" = P ]'
faillock --user gamescope --reset
check "after: sudo with the right password works" '[ "$(su -s /bin/bash gamescope -c "echo s3cret-pw | sudo -S -p \"\" id -u" 2>/dev/null)" = 0 ]'
check "after: sudo with empty password denied" '[ "$(asroot_via_sudo)" != 0 ]'
run_unit
check "after reboot: owner password untouched" '[ "$(passwd -S gamescope | cut -d" " -f2)" = P ]'
echo "RESULT pass=$pass fail=$fail"
