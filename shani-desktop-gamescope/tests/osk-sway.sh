#!/bin/bash
# Container test (see run.sh), archlinux image: desktop mode's on-screen
# keyboard. Headless sway runs the console's own sway drop-in; squeekboard
# must start from it, appear on the waybar toggle (D-Bus SetVisible) and pop up
# by itself on a text field when screen-keyboard-enabled is on (touchscreens).
pass=0; fail=0
ok()  { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
pacman -Syu --noconfirm --needed sway squeekboard grim dbus dconf ttf-dejavu foot python >/dev/null 2>&1 || { echo "FAIL setup: pacman"; exit 1; }
useradd -m u
install -m755 /pkg/usr/bin/shani-osk /usr/local/bin/shani-osk
cat > /tmp/inner.sh <<'IN'
set -u
export XDG_RUNTIME_DIR=/tmp/rt-u; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman
mkdir -p ~/.config/sway
# only what the test needs from 90-shani-gamescope.conf: the keyboard lines
{ echo 'output HEADLESS-1 resolution 1280x800'; grep -E '^set \$mod|squeekboard|shani-osk|^for_window' /pkg/etc/sway/config.d/90-shani-gamescope.conf; } > ~/.config/sway/config
cat ~/.config/sway/config >&2
# the packaged sway carries cap_sys_nice, which a rootless container refuses to exec
cp /usr/bin/sway /tmp/sway
/tmp/sway -c ~/.config/sway/config >/tmp/sway.log 2>&1 &
for i in $(seq 40); do [ -S $XDG_RUNTIME_DIR/wayland-1 ] && break; sleep 0.25; done
export WAYLAND_DISPLAY=wayland-1
osk=shani-osk
visible() { busctl --user get-property sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 Visible 2>/dev/null; }
for i in $(seq 40); do busctl --user status sm.puri.OSK0 >/dev/null 2>&1 && break; sleep 0.25; done
busctl --user status sm.puri.OSK0 >/dev/null 2>&1 && echo "PASS squeekboard started by the sway config" || echo "FAIL squeekboard started by the sway config"
sleep 1; grim /out/osk-hidden.png
[ "$(visible)" = "b false" ] && echo "PASS hidden at start (no touchscreen)" || echo "FAIL hidden at start: $(visible)"
$osk toggle; sleep 1.5
[ "$(visible)" = "b true" ] && echo "PASS toggle shows it" || echo "FAIL toggle shows it: $(visible)"
grim /out/osk-shown.png
$osk toggle; sleep 1.5
[ "$(visible)" = "b false" ] && echo "PASS toggle hides it" || echo "FAIL toggle hides it: $(visible)"
# the home's workspace rules: the home and its password prompt stay on 1, any
# other app goes to 2 and is brought to the front
grep -q 'Error' /tmp/sway.log && echo "FAIL sway config errors: $(grep Error /tmp/sway.log | head -2)" || echo "PASS the drop-in's rules load without errors"
export SWAYSOCK=$(ls $XDG_RUNTIME_DIR/sway-ipc.*.sock 2>/dev/null | head -1)
ws_of() { swaymsg -t get_tree -r | python3 -c '
import json,sys
want=sys.argv[1]
def walk(n, ws):
    if n.get("type")=="workspace": ws=n.get("name")
    if n.get("app_id")==want: print(ws); return True
    return any(walk(c, ws) for c in n.get("nodes",[])+n.get("floating_nodes",[]))
walk(json.load(sys.stdin), None)' "$1"; }
cur_ws() { swaymsg -t get_workspaces -r | python3 -c 'import json,sys; print([w["name"] for w in json.load(sys.stdin) if w["focused"]][0])'; }
foot --app-id=dev.shani.gamescope-control sleep 30 >/dev/null 2>&1 & sleep 1.5
[ "$(ws_of dev.shani.gamescope-control)" = 1 ] && echo "PASS the home stays on workspace 1" || echo "FAIL the home stays on workspace 1: $(ws_of dev.shani.gamescope-control)"
foot --app-id=org.mozilla.firefox sleep 30 >/dev/null 2>&1 & sleep 1.5
[ "$(ws_of org.mozilla.firefox)" = 2 ] && [ "$(cur_ws)" = 2 ] && echo "PASS an app opens on workspace 2, in front" || echo "FAIL an app opens on workspace 2: $(ws_of org.mozilla.firefox), focused $(cur_ws)"
# from the home (workspace 1), the password prompt stays over it
swaymsg -q workspace number 1; sleep 0.5
foot --app-id=polkit-gnome-authentication-agent-1 sleep 30 >/dev/null 2>&1 & sleep 1.5
w=$(ws_of polkit-gnome-authentication-agent-1)
[ "$w" = 1 ] && [ "$(cur_ws)" = 1 ] && echo "PASS the password prompt stays over the home" || echo "FAIL the password prompt stays over the home: on '$w', focused $(cur_ws)"
# auto: only a touchscreen machine gets the pop-up-on-text-field default, and
# only while the owner never chose (squeekboard itself shows on a focused text
# field when it is on - its own documented behaviour, server-context-service.c)
key=/org/gnome/desktop/a11y/applications/screen-keyboard-enabled
shani-osk auto
[ -z "$(dconf read $key)" ] && echo "PASS auto: no touchscreen, the setting stays unset" || echo "FAIL auto: no touchscreen: $(dconf read $key)"
mkdir -p /tmp/fakebin
printf '#!/bin/sh\necho ID_INPUT=1\necho ID_INPUT_TOUCHSCREEN=1\n' > /tmp/fakebin/udevadm; chmod +x /tmp/fakebin/udevadm
PATH=/tmp/fakebin:$PATH shani-osk auto
[ "$(dconf read $key)" = true ] && echo "PASS auto: a touchscreen turns pop-up on" || echo "FAIL auto: a touchscreen turns pop-up on: $(dconf read $key)"
dconf write $key false
PATH=/tmp/fakebin:$PATH shani-osk auto
[ "$(dconf read $key)" = false ] && echo "PASS auto: the owner's choice is kept" || echo "FAIL auto: the owner's choice is kept: $(dconf read $key)"
IN
chown u /tmp/inner.sh; mkdir -p /out; chmod 777 /out
su u -c 'cd; dbus-run-session -- bash /tmp/inner.sh' 2>/tmp/inner.err | tee /tmp/res
grep -q '^FAIL' /tmp/res && { tail -20 /tmp/sway.log; grep -v -e MESA -e portal /tmp/inner.err | tail; }
echo "RESULT pass=$(grep -c ^PASS /tmp/res) fail=$(grep -c ^FAIL /tmp/res)"
