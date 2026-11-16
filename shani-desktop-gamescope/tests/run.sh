#!/usr/bin/env bash
# Run shani-desktop-gamescope's tests in disposable containers (they create
# users, change PAM state and start compositors - never run them on a host).
#
#   tests/run.sh [password|shortcuts|panels|osk|pointer ...]    (default: all)
#
# password   - archlinux image: the console account is created with a locked
#              password, an old empty one is locked once, sudo is denied until
#              a password is set at boot, the helper never overwrites one.
# shortcuts  - archlinux image: non-Steam shortcuts written for each account,
#              read back by Valve-format parser `vdf` (fetched from PyPI into
#              the container, never run on the host).
# panels     - shani-shell's dev image (build it: shani-shell/dev/check.sh):
#              screenshots in tests/out/, Bluetooth panel against a fake BlueZ,
#              the Wi-Fi password and RESET typed with controller actions only
#              (gamepad.Navigator + the on-screen keyboard).
# osk        - archlinux image: headless sway with the console's drop-in;
#              squeekboard starts, the Waybar/Super+K toggle shows and hides
#              it, and with screen-keyboard-enabled it follows a text field.
# pointer    - archlinux image: pad-pointer's driver (stick speed, dead zone,
#              triggers as buttons and axes, DirectInput Z/RZ, Steam pause,
#              unplug), and that with no /dev/uinput it exits quietly. Never
#              given the real /dev/uinput: a pointer there would move the host's.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); pkg=$(dirname "$here")
shani=$(cd "$pkg/../.." && pwd)
sa="$shani/shani-install-media/image_profiles/shared/overlay/rootfs/etc/pam.d/system-auth"
rc=0
run() { echo "== $1"; shift; "$@" 2>&1 | grep -E '^(PASS|FAIL|RESULT)|step failed|NO VDF|no python' ; [ "${PIPESTATUS[0]}" -eq 0 ] || rc=1; }
targets=("$@")
has() { [ ${#targets[@]} -eq 0 ] || [[ " ${targets[*]} " == *" $1 "* ]]; }

if has password; then
  run password podman run --rm -v "$pkg:/pkg:ro" -v "$sa:/sa:ro" -v "$here:/t:ro" \
    docker.io/library/archlinux:latest bash /t/console-password.sh
fi
if has shortcuts; then
  run shortcuts podman run --rm -v "$pkg:/pkg:ro" -v "$here:/t:ro" docker.io/library/archlinux:latest bash -c '
    pacman -Syu --noconfirm --needed python python-pip python-gobject gdk-pixbuf2 >/dev/null 2>&1 || { echo "FAIL setup: pacman"; exit 1; }
    pip install --quiet --break-system-packages --target /vdf vdf >/dev/null 2>&1 || { echo "FAIL setup: pip vdf"; exit 1; }
    bash /t/steam-shortcuts.sh'
fi
if has panels; then
  mkdir -p "$here/out"
  run panels podman run --rm --network=none -v "$pkg:/pkg:ro" -v "$here:/t:ro" -v "$here/out:/out" \
    localhost/shani-shell-dev:latest bash /t/render.sh
  echo "   screenshots: $here/out/"
fi
if has osk; then
  mkdir -p "$here/out"
  run osk podman run --rm -v "$pkg:/pkg:ro" -v "$here:/t:ro" -v "$here/out:/out" \
    docker.io/library/archlinux:latest bash /t/osk-sway.sh
fi
if has pointer; then
  run pointer podman run --rm -v "$pkg:/pkg:ro" -v "$here:/t:ro" docker.io/library/archlinux:latest bash -c '
    pacman -Syu --noconfirm --needed python python-evdev >/dev/null 2>&1 || { echo "FAIL setup: pacman"; exit 1; }
    PAD_POINTER=/pkg/usr/lib/shani-desktop-gamescope/pad-pointer python3 -I /t/pad_pointer.py || exit 1
    python3 -I /pkg/usr/lib/shani-desktop-gamescope/pad-pointer 2>/tmp/e; rc=$?
    [ $rc = 0 ] && grep -q "no /dev/uinput" /tmp/e && echo "PASS no uinput: exits quietly" || { echo "FAIL no uinput: rc $rc $(cat /tmp/e)"; exit 1; }'
fi
exit $rc
