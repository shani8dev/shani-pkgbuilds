#!/bin/bash
# Real-render check of this package's theming: boots kwin_wayland (headless,
# virtual backend - no X11 anywhere) + plasmashell with a fresh home seeded
# from etc/skel (+ the chosen look-and-feel's defaults applied by
# lookandfeeltool), then screenshots the shell, Dolphin, Konsole, Yakuake,
# the lock screen, GTK 3/4 apps and Kvantum's gallery - all as native
# Wayland clients, captured with tests/qtgrab.py (KWin ScreenShot2 D-Bus).
# Run INSIDE an Arch container with this package directory at /pkg and:
#   plasma-desktop plasma-workspace kwin kvantum kde-gtk-config breeze-gtk
#   dolphin konsole yakuake fish gtk3-demos gtk4-demos
#   wayland imagemagick qt6-base python-dbus (wayland: headers to compile
#   tests/fakeinput.c; python-dbus + imagemagick: KWin ScreenShot2 capture and
#   compare/identify for the PASS/FAIL margins)
# Missing package dependencies give false readings (without kde-gtk-config
# GTK apps look unthemed) - install what the PKGBUILD depends on.
#
# Wayland-only, not X11: Plasma 6.8 dropped the kwin-x11 package, and
# plasmashell 6.8.3 segfaults on the X11/Xvfb path in a headless container
# (KConfigGroup null deref, stock Breeze too - proven not theme-related),
# while on its native Wayland path it runs. Everything X11 is replaced:
# wmctrl/xdotool -> kwin scripting + tests/fakeinput.c (KWin's
# org_kde_kwin_fake_input protocol - KWin implements neither
# zwlr_virtual_pointer nor zwp_virtual_keyboard, so wlrctl/wtype are out);
# screenshot -> tests/qtgrab.py (KWin's ScreenShot2 D-Bus, the same call
# spectacle makes - this container's spectacle silently no-ops).
#
#   tests/plasma-session.sh [Saturn-Dark|Saturn|Saturn-Twilight] [out-dir]
#
# For look-and-feel previews also install the dock's apps (discover firefox
# plasma-systemmonitor kate kcalc); the dock's flatpak launchers are pointed
# at the distro .desktop files when no flatpak exports exist (test-only).
#
# Prints RESULT lines; screenshots go to out-dir (default /tmp/plasma-shots).
set -u
LNF=${1:-Saturn-Dark}; OUT=${2:-/tmp/plasma-shots}; TAG=${KV_THEME:+-$KV_THEME}${DECO:+-$DECO}; PKG=${PKG:-/pkg}
mkdir -p "$OUT"
r() { printf 'RESULT %-40s %s\n' "$1" "$2"; }
# build the input-injection helper (KWin fake_input protocol - KWin implements
# neither zwlr_virtual_pointer nor zwp_virtual_keyboard, so wlrctl/wtype are
# out). Screenshots use tests/qtgrab.py (KWin's ScreenShot2 D-Bus); the C++
# demarshaller in qtgrab.cpp never worked and KWin 6.8's CaptureActiveScreen
# returns a black buffer, so the Python helper captures screen 0 instead.
cc -O2 -o "$OUT/fakeinput" "$PKG/tests/fakeinput.c" -lwayland-client || true
cp "$PKG/tests/qtgrab.py" "$OUT/qtgrab.py"
# Kvantum and XCursor only search the standard dirs, not XDG_DATA_DIRS.
for d in "$PKG"/usr/share/Kvantum/*; do ln -sfn "$d" "/usr/share/Kvantum/$(basename "$d")"; done
ln -sfn "$PKG/usr/share/icons/Saturn" /usr/share/icons/Saturn
export XDG_DATA_DIRS="$PKG/usr/share:/usr/share" XDG_CONFIG_DIRS="$PKG/etc/xdg:/etc/xdg"
export HOME=/tmp/plasma-home-$LNF XDG_RUNTIME_DIR=/tmp/plasma-rt-$LNF
rm -rf "$HOME" "$XDG_RUNTIME_DIR"; cp -a "$PKG/etc/skel" "$HOME"; mkdir -m700 -p "$XDG_RUNTIME_DIR"
# Plasma 6.8.3 segfaults whenever layout/panel scripting runs (new Panel's
# property setters write to an invalid KConfigGroup, even for the stock
# defaultPanel template). Seed the panel/dock config directly so the shell
# never evaluates the look's layout.js - verified: shell stays alive with
# both panels loaded.
cp "$PKG/tests/appletsrc-wayland" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
pkill -x kwin_wayland 2>/dev/null; pkill plasmashell 2>/dev/null; sleep 1
# dock launchers point at flatpak exports; stand in distro .desktop files
fx=/var/lib/flatpak/exports/share/applications
# stale-screenshot protection: this look's shots from a previous run must
# never satisfy this run's compare (an earlier run scored false PASS on them).
# Match only this look's 11 shot names - a plain "Saturn-*.png" glob also
# swallows Saturn-Dark and Saturn-Twilight shots from earlier looks.
for s in desktop calendar launcher dolphin maximized konsole lockscreen gtk3 gtk4 yakuake kvantum; do
  rm -f "$OUT/$LNF$TAG-$s.png"
done
if [ ! -d "$fx" ]; then
  mkdir -p "$fx"
  for a in org.kde.kate org.kde.kcalc; do
    [ -f "/usr/share/applications/$a.desktop" ] && ln -sf "/usr/share/applications/$a.desktop" "$fx/$a.desktop"
  done
  printf '[Desktop Entry]\nType=Application\nName=ONLYOFFICE\nExec=true\nIcon=x-office-document\n' \
    > "$fx/org.onlyoffice.desktopeditors.desktop"
fi
cat > "$XDG_RUNTIME_DIR/session.sh" <<'IN'
LNF=$1 OUT=$2 TAG=$3 PKG=$4
# Plasma 6.8.3's lookandfeeltool and plasma-apply-lookandfeel both abort
# (KConfigGroup crash, same family as panel layout scripting), silently
# leaving every look on the skel's Saturn-Dark. Apply the look's own config
# defaults directly, the same keys those tools would write.
python3 "$PKG/tests/apply-lnf-defaults.py" "$LNF" "$HOME" "$PKG"
# The look's defaults enable time-of-day auto switching; in a container that
# silently flips a dark look back to light mid-run. Pin the requested look.
kwriteconfig6 --file kdeglobals --group KDE --key AutomaticLookAndFeel false
# KV_THEME=<name> swaps just the Kvantum theme (e.g. an upstream one, to tell
# a Saturn regression from upstream design); APP_STYLE=<style> runs the apps
# under another widget style (default kvantum), to isolate Kvantum
[ -n "${KV_THEME:-}" ] && kwriteconfig6 --file Kvantum/kvantum.kvconfig --group General --key theme "$KV_THEME"
# startplasma prepends kdedefaults (where applying a Global Theme writes its
# settings) to XDG_CONFIG_DIRS; without it the shell ignores the theme.
export XDG_CONFIG_DIRS="$HOME/.config/kdedefaults:$XDG_CONFIG_DIRS"
# ...and marks the session as KDE: without XDG_CURRENT_DESKTOP=KDE Qt never
# loads the Plasma platform theme, so apps get no colour scheme at all
# (Breeze Light views inside a dark Kvantum window).
export XDG_CURRENT_DESKTOP=KDE XDG_SESSION_DESKTOP=KDE XDG_SESSION_TYPE=wayland KDE_FULL_SESSION=true KDE_SESSION_VERSION=6
# ...and pushes it to D-Bus activation: kded (kde-gtk-config), portals etc.
# are D-Bus-activated and otherwise never see kdedefaults or the KDE session.
dbus-update-activation-environment --all 2>/dev/null
# etc/xdg/autostart/shani-theme-sync.desktop (phase 1) - the only thing that
# switches Kvantum/GTK/Konsole to the applied look
bash /pkg/usr/lib/shani/shani-theme-sync.sh
# GTK_THEME_NAME=<name> overrides the GTK theme the sync script picks (A/B tests)
[ -n "${GTK_THEME_NAME:-}" ] && for v in gtk-3.0 gtk-4.0; do kwriteconfig6 --file "$v/settings.ini" --group Settings --key gtk-theme-name "$GTK_THEME_NAME"; done
# DECO=<aurorae theme dir name> tries an Aurorae window decoration instead
# of the look's own (for comparing decorations)
if [ -n "${DECO:-}" ]; then
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme "__aurorae__svg__$DECO"
fi
# everything below is a Wayland client of the kwin we just started
export QT_QPA_PLATFORM=wayland
# KWin's virtual framebuffer backend gives plasmashell a real output to bind
# its layer-shell panels/popups to. Without --virtual KWin only has a
# placeholder output: the shell is alive and its containments exist, but it
# paints nothing (every screenshot is black, except plain app windows).
kwin_wayland --virtual --width 1920 --height 1080 >"$OUT/kwin-$LNF.log" 2>&1 &
for i in $(seq 1 10); do
  sleep 1
  wl=$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | head -1)
  [ -n "$wl" ] && break
done
[ -n "${wl:-}" ] || { echo "RESULT $LNF kwin_wayland FAILED (no wayland socket)"; exit 1; }
export WAYLAND_DISPLAY=$(basename "$wl")
dbus-update-activation-environment WAYLAND_DISPLAY 2>/dev/null
# plasmashell 6.8.3 startup-races kwin's virtual output (observed: segfaults
# within seconds on some attempts, survives under gdb); real startplasma
# restarts it too - retry until the bus name answers, max 3 attempts
for try in 1 2 3; do
  plasmashell >>"$OUT/plasmashell-$LNF.log" 2>&1 &
  PX=$!
  for i in $(seq 1 25); do
    sleep 1
    qdbus6 org.kde.plasmashell /PlasmaShell >/dev/null 2>&1 && break 2
    kill -0 $PX 2>/dev/null || { echo "plasmashell attempt $try died, retrying" >&2; break; }
  done
  qdbus6 org.kde.plasmashell /PlasmaShell >/dev/null 2>&1 && break
done
qdbus6 org.kde.plasmashell /PlasmaShell >/dev/null 2>&1 || echo "WARNING: plasmashell not answering after 3 attempts" >&2
shot() { python3 "$OUT/qtgrab.py" "$OUT/$LNF$TAG-$1.png" 0 >/dev/null 2>&1; }
# Layout scripting is intentionally NOT used here: desktops()[0].addWidget()
# crashes plasmashell 6.8.3 in the same KConfigGroup setter as `new Panel`
# (verified with evaluateScript bisect: `new Panel` alone survives,
# `p.height = 40` segfaults). The pre-seeded appletsrc above gives the shell
# its panels without running any layout JS; the desktop shot stays plain.
dbus-send --session --dest=org.freedesktop.Notifications --type=method_call \
  /org/freedesktop/Notifications org.freedesktop.Notifications.Notify \
  string:Plasma uint32:0 string:dialog-information string:Welcome string:"How are you?" \
  array:string: dict:string:string: int32:15000 >/dev/null 2>&1
sleep 5
# what the shell actually loaded, and whether KWin composites (no compositor
# => Plasma draws the opaque/ variants, no blur)
echo "loaded-plasma-theme=$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript 'print(theme)' 2>&1 | tr -d '\n')"
echo "kwin-decoration=$(qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation 2>/dev/null | grep -iE '^(Plugin|Theme):' | head -2 | tr '\n' ';')"
echo "kwin-compositing=$(qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation 2>/dev/null | grep -iE '^(Compositing is active|Compositing Type|OpenGL renderer)' | tr '\n' ';')"
shot desktop
# the compositor's output size (kwin_wayland's virtual default is 1920x1080)
read -r W H < <(identify -format '%w %h' "$OUT/$LNF$TAG-desktop.png")
# calendar popup: pointer to the panel clock and click. NOTE: on KWin 6.8's
# virtual output fake input can move the pointer (dock launches work) but the
# clock only shows a hover tooltip, never the calendar popup - this shot
# legitimately FAILs the subject-visible check in the container. Do not lower
# the threshold to make it pass; the missing popup is the finding.
"$OUT/fakeinput" click $((W / 2)) 8 >/dev/null 2>&1
sleep 3; shot calendar
"$OUT/fakeinput" key ff1b >/dev/null 2>&1; sleep 1   # Escape closes the popup
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu >/dev/null 2>&1; sleep 3; shot launcher
"$OUT/fakeinput" key ff1b >/dev/null 2>&1; sleep 1
QT_STYLE_OVERRIDE=${APP_STYLE:-kvantum} dolphin "$HOME" >/dev/null 2>&1 &
sleep 8
# KWin's headless placeholder output gives Dolphin a tiny default geometry;
# maximize it before the shot so the capture actually shows the file view.
cat > "$XDG_RUNTIME_DIR/maxdolphin.js" <<'JS'
for (const w of workspace.windowList()) {
  if (w.resourceClass === "dolphin" || w.resourceClass === "org.kde.dolphin") {
    w.frameGeometry = { x: 100, y: 80, width: 1600, height: 900 };
    w.maximized = true;
  }
}
JS
qid=$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$XDG_RUNTIME_DIR/maxdolphin.js")
qdbus6 org.kde.KWin /Scripting/Script$qid org.kde.kwin.Script.run >/dev/null 2>&1
qdbus6 org.kde.KWin /Scripting/Script$qid org.kde.kwin.Script.stop >/dev/null 2>&1
# KWin needs a couple of frames after the resize before the view repaints;
# capturing earlier gives a near-black window and a false FAIL.
sleep 6
shot dolphin
# decoration button states and maximize: kwin scripting replaces wmctrl
# (which is X11-only); also place the window at a known spot so the pointer
# hover below lands on the title bar
cat > "$XDG_RUNTIME_DIR/winops.js" <<'JS'
// Wayland resourceClass is the desktop-file id (org.kde.dolphin), X11 was the
// binary name (dolphin) - match both
for (const w of workspace.windowList()) {
  if (w.resourceClass !== "dolphin" && w.resourceClass !== "org.kde.dolphin") continue;
  w.frameGeometry = { x: 200, y: 150, width: 1000, height: 600 };
  w.keepAbove = true;
  w.onAllDesktops = true;
}
JS
qid=$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$XDG_RUNTIME_DIR/winops.js")
qdbus6 org.kde.KWin /Scripting/Script$qid org.kde.kwin.Script.run >/dev/null 2>&1
qdbus6 org.kde.KWin /Scripting/Script$qid org.kde.kwin.Script.stop >/dev/null 2>&1
sleep 2
# hover a decoration button (top-left area) - informational shot, not asserted
"$OUT/fakeinput" move 230 165 >/dev/null 2>&1
sleep 2
shot deco-states
sleep 1
cat > "$XDG_RUNTIME_DIR/max.js" <<'JS'
for (const w of workspace.windowList()) {
  if (w.resourceClass !== "dolphin" && w.resourceClass !== "org.kde.dolphin") continue;
  w.keepAbove = false;
  w.onAllDesktops = false;
  w.maximized = true;
}
JS
qid=$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$XDG_RUNTIME_DIR/max.js")
qdbus6 org.kde.KWin /Scripting/Script$qid org.kde.kwin.Script.run >/dev/null 2>&1
qdbus6 org.kde.KWin /Scripting/Script$qid org.kde.kwin.Script.stop >/dev/null 2>&1
sleep 3
shot maximized
pkill dolphin
# print all 16 ANSI colours as text and as blocks, so the shot shows the palette
cat > /tmp/ansi-demo.sh <<'ANSI'
for b in "" "1;"; do for i in 0 1 2 3 4 5 6 7; do printf "\e[${b}3${i}m %-8s\e[0m" "$i${b:+ bold}"; done; echo; done
for i in 0 1 2 3 4 5 6 7; do printf "\e[4${i}m    \e[0m"; done; for i in 0 1 2 3 4 5 6 7; do printf "\e[10${i}m    \e[0m"; done; echo
printf "\e[36mcyan: git hunk\e[0m  \e[90mbright black: comment\e[0m  \e[1mbold\e[0m\n"
sleep 30
ANSI
QT_STYLE_OVERRIDE=${APP_STYLE:-kvantum} konsole -e bash /tmp/ansi-demo.sh >"$OUT/konsole-$LNF.log" 2>&1 &
sleep 5
shot konsole
pkill konsole
# the real lock screen (--testing: windowed, unlock with any key/password)
/usr/lib/kscreenlocker_greet --testing >"$OUT/lock-$LNF.log" 2>&1 &
sleep 6; shot lockscreen; pkill -f kscreenlocker_greet
# GTK: what kde-gtk-config left in the user's GTK colours, and real apps
echo "gtk3-colors=$(grep -m2 -oE '@define-color theme_bg_color_[a-z]+ #[0-9a-f]+' $HOME/.config/gtk-3.0/colors.css 2>/dev/null | tr '\n' ' ') gtk4-colors=$( [ -e $HOME/.config/gtk-4.0/colors.css ] && grep -m1 -oE '@define-color theme_bg_color_[a-z]+ #[0-9a-f]+' $HOME/.config/gtk-4.0/colors.css || echo MISSING)"
gtk3-widget-factory >/dev/null 2>&1 &
sleep 5; shot gtk3; pkill -f gtk3-widget-factory
gtk4-widget-factory >"$OUT/gtk4-$LNF.log" 2>&1 &
sleep 15; shot gtk4; pkill -f gtk4-widget-factory
# Yakuake: drop it down with two tabs (skin + the shani terminal profile)
QT_STYLE_OVERRIDE=${APP_STYLE:-kvantum} yakuake >"$OUT/yakuake-$LNF.log" 2>&1 &
sleep 5
qdbus6 org.kde.yakuake /yakuake/sessions org.kde.yakuake.addSession >/dev/null 2>&1
qdbus6 org.kde.yakuake /yakuake/window org.kde.yakuake.toggleWindowState >/dev/null 2>&1
sleep 4
shot yakuake
echo "yakuake-skin=$(kreadconfig6 --file yakuakerc --group Appearance --key Skin)"
qdbus6 org.kde.yakuake /yakuake/window org.kde.yakuake.toggleWindowState >/dev/null 2>&1
pkill yakuake
QT_STYLE_OVERRIDE=${APP_STYLE:-kvantum} kvantumpreview >/dev/null 2>&1 &
sleep 6
shot kvantum
echo "plasmarc=$(kreadconfig6 --file plasmarc --group Theme --key name) kvantum=$(kreadconfig6 --file Kvantum/kvantum.kvconfig --group General --key theme) scheme=$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)"
pkill kvantumpreview; pkill plasmashell; pkill -x kwin_wayland; true
IN
GTK_THEME_NAME="${GTK_THEME_NAME:-}" DECO="${DECO:-}" APP_STYLE="${APP_STYLE:-}" KV_THEME="${KV_THEME:-}" \
  dbus-run-session -- bash "$XDG_RUNTIME_DIR/session.sh" "$LNF" "$OUT" "$TAG" "$PKG"
for s in desktop calendar launcher dolphin maximized konsole lockscreen gtk3 gtk4 yakuake kvantum; do
  f="$OUT/$LNF$TAG-$s.png"
  if [[ ! -s "$f" ]]; then r "$LNF screenshot $s" "FAIL (no file)"; continue; fi
  # a screenshot captures the whole screen whatever is on it, so non-empty
  # proves nothing: require the shot to differ from the desktop baseline,
  # and report the margin so a near-miss is visible.
  if [[ "$s" == desktop ]]; then r "$LNF screenshot $s" "PASS (baseline)"; continue; fi
  d=$(compare -metric AE "$OUT/$LNF$TAG-desktop.png" "$f" null: 2>&1)
  d=${d%%[^0-9]*}                       # compare prints e.g. "12345 (0.592857)"
  # Threshold from the image itself, not $W/$H: under `set -u` a typo'd var
  # aborts the run.
  read -r iw ih < <(identify -format '%w %h' "$f")
  if (( d < iw * ih / 200 )); then
    r "$LNF screenshot $s" FAIL
    echo "DETAIL $LNF $s: only $d px differ from desktop - subject not visible?"
  else
    # Keep RESULT lines byte-stable so the committed baseline stays diffable;
    # the margin is informational, so it goes on its own line.
    r "$LNF screenshot $s" PASS
    echo "DETAIL $LNF $s: $d px differ from desktop"
  fi
done
if grep -qiE "could not find|check your profile" "$OUT/yakuake-$LNF.log" 2>/dev/null; then
  r "$LNF yakuake shell resolution" "FAIL (see yakuake-$LNF.log)"
  grep -iE "could not find|check your profile" "$OUT/yakuake-$LNF.log" | head -3
else r "$LNF yakuake shell resolution" "PASS (no shell warning)"; fi
PSLOG="$OUT/plasmashell-$LNF.log"
if grep -iE "desktoptheme|Saturn|svg" "$PSLOG" | grep -iE "warn|error|fail|not found" | head -5 | grep -q .; then
  r "$LNF plasmashell theme warnings" "FAIL (see plasmashell-$LNF.log)"
  grep -iE "desktoptheme|Saturn|svg" "$PSLOG" | grep -iE "warn|error|fail|not found" | head -5
else r "$LNF plasmashell theme warnings" "PASS (none)"; fi
pkill -x kwin_wayland 2>/dev/null; true
