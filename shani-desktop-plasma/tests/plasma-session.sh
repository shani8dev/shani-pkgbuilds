#!/bin/bash
# Real-render check of this package's theming: boots kwin_x11 + plasmashell
# on Xvfb with a fresh home seeded from etc/skel (+ the chosen look-and-feel's
# defaults applied by lookandfeeltool), then screenshots the shell, Dolphin,
# Konsole, Yakuake, the lock screen, GTK 3/4 apps and Kvantum's gallery.
# Run INSIDE an Arch container with this package directory at /pkg and:
#   plasma-desktop plasma-workspace kwin-x11 kvantum kde-gtk-config breeze-gtk
#   dolphin konsole yakuake fish gtk3-demos gtk4-demos wmctrl
#   xorg-server-xvfb xdotool imagemagick
# Missing package dependencies give false readings (without kde-gtk-config
# GTK apps look unthemed) - install what the PKGBUILD depends on.
#
#   [SCREEN=1920x1080] tests/plasma-session.sh [Saturn-Dark|Saturn|Saturn-Twilight] [out-dir]
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
# Kvantum and XCursor only search the standard dirs, not XDG_DATA_DIRS.
for d in "$PKG"/usr/share/Kvantum/*; do ln -sfn "$d" "/usr/share/Kvantum/$(basename "$d")"; done
ln -sfn "$PKG/usr/share/icons/Saturn" /usr/share/icons/Saturn
export XDG_DATA_DIRS="$PKG/usr/share:/usr/share" XDG_CONFIG_DIRS="$PKG/etc/xdg:/etc/xdg"
export HOME=/tmp/plasma-home-$LNF XDG_RUNTIME_DIR=/tmp/plasma-rt-$LNF DISPLAY=:7
rm -rf "$HOME" "$XDG_RUNTIME_DIR"; cp -a "$PKG/etc/skel" "$HOME"; mkdir -m700 -p "$XDG_RUNTIME_DIR"
pkill -x Xvfb 2>/dev/null; sleep 1
# dock launchers point at flatpak exports; stand in distro .desktop files
fx=/var/lib/flatpak/exports/share/applications
if [ ! -d "$fx" ]; then
  mkdir -p "$fx"
  for a in org.kde.kate org.kde.kcalc; do
    [ -f "/usr/share/applications/$a.desktop" ] && ln -sf "/usr/share/applications/$a.desktop" "$fx/$a.desktop"
  done
  printf '[Desktop Entry]\nType=Application\nName=ONLYOFFICE\nExec=true\nIcon=x-office-document\n' \
    > "$fx/org.onlyoffice.desktopeditors.desktop"
fi
Xvfb :7 -screen 0 "${SCREEN:-1600x900}x24" +extension GLX >/dev/null 2>&1 &
sleep 2
cat > "$XDG_RUNTIME_DIR/session.sh" <<'IN'
LNF=$1 OUT=$2 TAG=$3
plasma-apply-lookandfeel -a "$LNF" >/dev/null 2>&1
# the look-and-feel's [plasmarc]/[kvantum]/[kdeglobals] defaults, as the KCM applies them
lookandfeeltool -a "$LNF" >/dev/null 2>&1
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
export XDG_CURRENT_DESKTOP=KDE XDG_SESSION_DESKTOP=KDE KDE_FULL_SESSION=true KDE_SESSION_VERSION=6
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
kwin_x11 --replace >/tmp/kwin-$LNF.log 2>&1 &
sleep 4
plasmashell >/tmp/plasmashell-$LNF.log 2>&1 &
sleep 20
shot() { import -window root "$OUT/$LNF$TAG-$1.png"; }
# the same surfaces the Utterly-Round screenshots show: desktop widgets,
# a notification, the clock's calendar popup and the app launcher
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
  var d = desktops()[0];
  d.addWidget("org.kde.plasma.mediacontroller", 80, 120, 360, 280);
  d.addWidget("org.kde.plasma.analogclock", 520, 140, 240, 240);' >/dev/null 2>&1
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
W=$(xdotool getdisplaygeometry | cut -d" " -f1)
xdotool mousemove $((W / 2)) 20 click 1; sleep 3; shot calendar
xdotool key Escape; sleep 1
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu >/dev/null 2>&1; sleep 3; shot launcher
xdotool key Escape; sleep 1
QT_STYLE_OVERRIDE=${APP_STYLE:-kvantum} dolphin "$HOME" >/dev/null 2>&1 &
sleep 8
import -window root "$OUT/$LNF$TAG-dolphin.png"
# decoration button states: toggle keep-above + on-all-desktops (those
# buttons draw their "pressed" = toggled frame), hover the close button
wmctrl -r Dolphin -b add,above,sticky 2>/dev/null
eval "$(xdotool search --name Dolphin getwindowgeometry --shell 2>/dev/null | head -5)"
[ -n "${X:-}" ] && xdotool mousemove $((X + 18)) $((Y - 18))
sleep 2
import -window root "$OUT/$LNF$TAG-deco-states.png"
# maximized: the window-buttons widget takes over the decoration's buttons
wmctrl -r Dolphin -b remove,above,sticky 2>/dev/null
wmctrl -r Dolphin -b add,maximized_vert,maximized_horz 2>/dev/null
sleep 3
import -window root "$OUT/$LNF$TAG-maximized.png"
pkill dolphin
# print all 16 ANSI colours as text and as blocks, so the shot shows the palette
cat > /tmp/ansi-demo.sh <<'ANSI'
for b in "" "1;"; do for i in 0 1 2 3 4 5 6 7; do printf "\e[${b}3${i}m %-8s\e[0m" "$i${b:+ bold}"; done; echo; done
for i in 0 1 2 3 4 5 6 7; do printf "\e[4${i}m    \e[0m"; done; for i in 0 1 2 3 4 5 6 7; do printf "\e[10${i}m    \e[0m"; done; echo
printf "\e[36mcyan: git hunk\e[0m  \e[90mbright black: comment\e[0m  \e[1mbold\e[0m\n"
sleep 30
ANSI
QT_STYLE_OVERRIDE=${APP_STYLE:-kvantum} konsole -e bash /tmp/ansi-demo.sh >/tmp/konsole-$LNF.log 2>&1 &
sleep 5
import -window root "$OUT/$LNF$TAG-konsole.png"
pkill konsole
# the real lock screen (--testing: windowed, unlock with any key/password)
/usr/lib/kscreenlocker_greet --testing >/tmp/lock-$LNF.log 2>&1 &
sleep 6; import -window root "$OUT/$LNF$TAG-lockscreen.png"; pkill -f kscreenlocker_greet
# GTK: what kde-gtk-config left in the user's GTK colours, and real apps
echo "gtk3-colors=$(grep -m2 -oE '@define-color theme_bg_color_[a-z]+ #[0-9a-f]+' $HOME/.config/gtk-3.0/colors.css 2>/dev/null | tr '\n' ' ') gtk4-colors=$( [ -e $HOME/.config/gtk-4.0/colors.css ] && grep -m1 -oE '@define-color theme_bg_color_[a-z]+ #[0-9a-f]+' $HOME/.config/gtk-4.0/colors.css || echo MISSING)"
GDK_BACKEND=x11 gtk3-widget-factory >/dev/null 2>&1 &
sleep 5; import -window root "$OUT/$LNF$TAG-gtk3.png"; pkill -f gtk3-widget-factory
GDK_BACKEND=x11 gtk4-widget-factory >/dev/null 2>&1 &
sleep 5; import -window root "$OUT/$LNF$TAG-gtk4.png"; pkill -f gtk4-widget-factory
# Yakuake: drop it down with two tabs (skin + the shani terminal profile)
QT_STYLE_OVERRIDE=${APP_STYLE:-kvantum} yakuake >"$OUT/yakuake-$LNF.log" 2>&1 &
sleep 5
qdbus6 org.kde.yakuake /yakuake/sessions org.kde.yakuake.addSession >/dev/null 2>&1
qdbus6 org.kde.yakuake /yakuake/window org.kde.yakuake.toggleWindowState >/dev/null 2>&1
sleep 4
import -window root "$OUT/$LNF$TAG-yakuake.png"
echo "yakuake-skin=$(kreadconfig6 --file yakuakerc --group Appearance --key Skin)"
qdbus6 org.kde.yakuake /yakuake/window org.kde.yakuake.toggleWindowState >/dev/null 2>&1
pkill yakuake
QT_STYLE_OVERRIDE=${APP_STYLE:-kvantum} kvantumpreview >/dev/null 2>&1 &
sleep 6
import -window root "$OUT/$LNF$TAG-kvantum.png"
echo "plasmarc=$(kreadconfig6 --file plasmarc --group Theme --key name) kvantum=$(kreadconfig6 --file Kvantum/kvantum.kvconfig --group General --key theme) scheme=$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)"
pkill kvantumpreview; pkill plasmashell; pkill kwin_x11
IN
GTK_THEME_NAME="${GTK_THEME_NAME:-}" DECO="${DECO:-}" APP_STYLE="${APP_STYLE:-}" KV_THEME="${KV_THEME:-}" dbus-run-session -- bash "$XDG_RUNTIME_DIR/session.sh" "$LNF" "$OUT" "$TAG"
for s in desktop calendar launcher dolphin maximized konsole lockscreen gtk3 gtk4 yakuake kvantum; do
  f="$OUT/$LNF$TAG-$s.png"
  if [[ ! -s "$f" ]]; then r "$LNF screenshot $s" "FAIL (no file)"; continue; fi
  # `import -window root` captures the whole screen whatever is on it, so
  # non-empty proves nothing: require the shot to differ from the desktop
  # baseline, and report the margin so a near-miss is visible.
  if [[ "$s" == desktop ]]; then r "$LNF screenshot $s" "PASS (baseline)"; continue; fi
  d=$(compare -metric AE "$OUT/$LNF$TAG-desktop.png" "$f" null: 2>&1)
  d=${d%%[^0-9]*}                       # compare prints e.g. "12345 (0.592857)"
  # Threshold from the image itself, not $W/$H: those are set in the pre-session
  # section and H is never set at all, so under `set -u` they abort the run.
  read -r iw ih < <(identify -format '%w %h' "$f")
  if (( d < iw * ih / 200 )); then
    r "$LNF screenshot $s" FAIL
    echo "DETAIL $LNF $s: only $d px differ from desktop - subject not visible?"
  else
    # Keep RESULT lines byte-stable so tests/baseline-plasma-6.7.result stays
    # diffable; the margin is informational, so it goes on its own line.
    r "$LNF screenshot $s" PASS
    echo "DETAIL $LNF $s: $d px differ from desktop"
  fi
done
if grep -qiE "could not find|check your profile" "$OUT/yakuake-$LNF.log" 2>/dev/null; then
  r "$LNF yakuake shell resolution" "FAIL (see yakuake-$LNF.log)"
  grep -iE "could not find|check your profile" "$OUT/yakuake-$LNF.log" | head -3
else r "$LNF yakuake shell resolution" "PASS (no shell warning)"; fi
if grep -iE "desktoptheme|Saturn|svg" /tmp/plasmashell-$LNF.log | grep -iE "warn|error|fail|not found" | head -5 | grep -q .; then
  r "$LNF plasmashell theme warnings" "FAIL (see /tmp/plasmashell-$LNF.log)"
  grep -iE "desktoptheme|Saturn|svg" /tmp/plasmashell-$LNF.log | grep -iE "warn|error|fail|not found" | head -5
else r "$LNF plasmashell theme warnings" "PASS (none)"; fi
pkill -x Xvfb
