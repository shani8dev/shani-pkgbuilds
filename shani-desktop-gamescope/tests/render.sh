#!/bin/bash
# Container test (see run.sh), in shani-shell's dev image: headless weston +
# nested niri; screenshots of the Control Center and its panels go to /out, then
# the Bluetooth panel is driven against fake_bluez.py on a private system bus.
export XDG_RUNTIME_DIR=/tmp/rt; mkdir -p $XDG_RUNTIME_DIR /run/dbus; chmod 700 $XDG_RUNTIME_DIR
mkdir -p /usr/lib/shani-desktop-gamescope; cp /pkg/usr/lib/shani-desktop-gamescope/* /usr/lib/shani-desktop-gamescope/
cp /pkg/usr/bin/shani-gamescope-control /usr/local/bin/
cat > /tmp/sys.conf <<'C'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>system</type><listen>unix:path=/run/dbus/system_bus_socket</listen>
<policy context="default"><allow user="*"/><allow own="*"/><allow send_type="method_call"/><allow send_destination="*"/><allow receive_type="*"/></policy></busconfig>
C
dbus-daemon --config-file=/tmp/sys.conf --fork
python3 /t/fake_bluez.py > /tmp/bluez.log 2>&1 &
sleep 1; cat /tmp/bluez.log
weston --backend=headless-backend.so --shell=kiosk-shell.so --width=1600 --height=1000 --socket=wayland-parent --idle-time=0 --no-config >/tmp/weston.log 2>&1 &
sleep 2
printf 'prefer-no-csd\nlayout { gaps 0; default-column-width { proportion 1.0; }; }\nwindow-rule { open-maximized true; }\nanimations { off; }\nhotkey-overlay { skip-at-startup; }\n' > /tmp/n.kdl
WAYLAND_DISPLAY=wayland-parent niri -c /tmp/n.kdl >/tmp/niri.log 2>&1 &
sleep 3
export WAYLAND_DISPLAY=wayland-1
dbus-run-session -- bash -c '
pipewire >/dev/null 2>&1 & sleep 0.5; wireplumber >/dev/null 2>&1 & pipewire-pulse >/dev/null 2>&1 & sleep 2
shot() { name=$1; shift; shani-gamescope-control "$@" >/out/app-$name.log 2>&1 & pid=$!; sleep 5; grim /out/$name.png; kill $pid; sleep 1; }
shot main
SHANI_FROM_STEAM=1 shot from-steam
shot password --open password
shot bluetooth --open bluetooth
shot network --open network
shot audio --open audio
for log in /out/app-*.log; do
  grep -q Traceback "$log" && echo "FAIL $(basename "$log" .log) started with an error: $(grep -E "Error" "$log" | tail -1)" || echo "PASS $(basename "$log" .log) started clean"
done
python3 /t/bluetooth_panel.py 2>&1 | grep -E "^(PASS|FAIL|RESULT|Traceback|  File|[A-Za-z]+Error)"
python3 /t/gamepad_keyboard.py 2>&1 | grep -E "^(PASS|FAIL|RESULT|Traceback|  File|[A-Za-z]+Error)"
'
