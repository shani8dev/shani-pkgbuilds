#!/bin/bash
# Global Theme switching only reliably pushes a fixed set of keys live
# (color scheme, Plasma theme, icons, cursor, wallpaper, KWin decoration).
# Kvantum, GTK app style, and Konsole/Yakuake's terminal color scheme are
# NOT in that recognized set, so they keep whatever they had from the
# previous login until something re-syncs them. This runs once per session
# start and brings all three in line with whichever Saturn color scheme
# is currently active.

#
# --watch (what the autostart entry runs): sync once, then again whenever
# the colour scheme can have changed mid-session - Plasma's automatic
# light/dark switching (AutomaticLookAndFeel=true in the Saturn looks), the
# Colors KCM, plasma-apply-colorscheme. Those announce it on the session bus
# as KConfig's ConfigChanged on /kdeglobals and/or KGlobalSettings'
# notifyChange; dbus-monitor (from dbus, always present) subscribes to both.
# Each sync is a separate process, so its early `exit` for a non-Saturn
# scheme can't end the watch; this script's own writes use kwriteconfig6
# without --notify, so they never re-trigger it.
if [ "${1:-}" = "--watch" ]; then
  "$0"
  dbus-monitor --session \
    "type='signal',path='/kdeglobals',interface='org.kde.kconfig.notify',member='ConfigChanged'" \
    "type='signal',interface='org.kde.KGlobalSettings',member='notifyChange'" 2>/dev/null |
  while read -r line; do
    case "$line" in
      signal*member=ConfigChanged*|signal*member=notifyChange*) ;;
      *) continue ;;
    esac
    # a theme switch fires several signals at once: settle, then sync once
    while read -r -t 1 _; do :; done
    "$0"
  done
  exit 0
fi

scheme=$(kreadconfig6 --file kdeglobals --group General --key ColorScheme 2>/dev/null)

# NOTE: do NOT try to seed a missing ColorScheme key via kwriteconfig6 —
# a live Plasma session strips that key back out immediately (verified:
# written value reads back via kreadconfig but never lands in the file),
# so persist nothing and just default in memory.
if [ -z "$scheme" ]; then
  scheme="SaturnDark"
fi
# Unlike ColorScheme, widgetStyle DOES stick — and without it Qt apps
# ignore Kvantum entirely even when its theme is correctly selected.
# KDE reads it from [KDE] (as skel and the look-and-feel defaults write it).
if [ -z "$(kreadconfig6 --file kdeglobals --group KDE --key widgetStyle 2>/dev/null)" ]; then
  kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle "kvantum" 2>/dev/null
fi

# --- KWin decoration: seed the Saturn decoration when absent, never overwrite ---
# (build-aurorae.py; its title bar follows the active colour scheme). The
# look-and-feel switches Saturn/Saturn-Dark with the look. An explicitly
# different value is the user's choice and is left alone.
if [ -z "$(kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme 2>/dev/null)" ]; then
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library "org.kde.kwin.aurorae.v2" 2>/dev/null
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme "__aurorae__svg__Saturn-Dark" 2>/dev/null
fi

# --- Blur: seed when absent, never overwrite ---
# NOTE (Plasma 6): the old Translucency/BackgroundBlur/BackgroundContrast
# effects are gone — kwin's built-in `blur` effect (plus Kvantum's
# translucent_windows+blurring and the translucent Breeze panel) is the
# entire blur path. Only these keys are live; anything else is dead config.
seed_kwin() { # $1=group $2=key $3=value
  if [ -z "$(kreadconfig6 --file kwinrc --group "$1" --key "$2" 2>/dev/null)" ]; then
    kwriteconfig6 --file kwinrc --group "$1" --key "$2" "$3" 2>/dev/null
  fi
}
seed_kwin Plugins blurEnabled true
seed_kwin Effect-blur BlurStrength 15
# Older Saturn builds seeded a blur strength of 40. KWin indexes a 15-entry table
# with it (blur.cpp, numOfBlurSteps = 15) - anything above 15 reads past the
# table and crashes KWin whenever blur renders. Clamp it.
bs=$(kreadconfig6 --file kwinrc --group Effect-blur --key BlurStrength 2>/dev/null)
case "$bs" in
  ''|*[!0-9]*) ;;
  *) [ "$bs" -gt 15 ] && kwriteconfig6 --file kwinrc --group Effect-blur --key BlurStrength 15 ;;
esac
seed_kwin Effect-blur NoiseStrength 0
seed_kwin Effect-blur Saturation 105
# (Background contrast behind blurred shell surfaces is set by the Plasma
# style: desktoptheme plasmarc [ContrastEffect]; KWin has no such kwinrc group.)

# --- Accent: scheme coral is the single source of truth ---
# Every Saturn .colors file declares accentcolor=#ff7f50 (255,127,80).
# A custom AccentColor/LastUsedCustomAccentColor left in kdeglobals (e.g.
# from an old System Settings pick) overrides that scheme value and tints
# selection/focus/link away from coral — force the scheme value so the
# whole desktop matches the Bibata cursor.
seed_accent() {
  if [ "$(kreadconfig6 --file kdeglobals --group General --key AccentColor 2>/dev/null)" != "255,127,80" ]; then
    kwriteconfig6 --file kdeglobals --group General --key AccentColor "255,127,80" 2>/dev/null
  fi
}
seed_accent

# Normalize legacy aliases to canonical schemes
case "$scheme" in
  SaturnLight)
    scheme="Saturn"
    ;;
  SaturnTwilight)
    scheme="SaturnDark"
    ;;
esac

case "$scheme" in
  SaturnDark)     kvantum_target=SaturnDark;      gtk_dark=true;  gtk_icons=breeze-dark; gtk_theme=Breeze;      konsole_scheme=SaturnDark; yakuake_skin=Saturn-Dark ;;
  Saturn)         kvantum_target=Saturn;          gtk_dark=false; gtk_icons=breeze;      gtk_theme=Breeze;      konsole_scheme=Saturn;     yakuake_skin=Saturn ;;
  *) exit 0 ;;
esac

# --- Kvantum themes for Flatpak apps ---
# Flatpak Qt apps use Kvantum (org.kde.KStyle.Kvantum + the first-login
# override), but a sandbox can't see /usr/share/Kvantum - only
# ~/.config/Kvantum, granted read-only. Keep the user copies of the Saturn
# themes identical to the installed ones (copied only when they differ, so
# package upgrades propagate). Host apps read the same files.
# (content compared with sha256sum - coreutils; cmp is diffutils, not always
# installed, and mtimes can't be used: pacman keeps build-time mtimes)
same() { [ -f "$2" ] && [ "$(sha256sum < "$1")" = "$(sha256sum < "$2")" ]; }
for t in Saturn SaturnDark; do
  src=/usr/share/Kvantum/$t dst="$HOME/.config/Kvantum/$t"
  [ -d "$src" ] || continue
  if ! same "$src/$t.kvconfig" "$dst/$t.kvconfig" || ! same "$src/$t.svg" "$dst/$t.svg"; then
    mkdir -p "$dst" && cp -f "$src/$t.kvconfig" "$src/$t.svg" "$dst/"
  fi
done

# --- Kvantum ---
# Kvantum reads ~/.config/Kvantum/kvantum.kvconfig - NOT ~/.config/kvantum.kvconfig,
# which is where a look-and-feel's [kvantum.kvconfig] defaults (and a bare
# `--file kvantum.kvconfig`) would land. Applying a Global Theme never
# switches Kvantum; this is the only thing that does.
current_kvantum=$(kreadconfig6 --file Kvantum/kvantum.kvconfig --group General --key theme 2>/dev/null)
if [ "$current_kvantum" != "$kvantum_target" ]; then
  if command -v kvantummanager >/dev/null 2>&1; then
    kvantummanager --set "$kvantum_target" >/dev/null 2>&1
  else
    kwriteconfig6 --file Kvantum/kvantum.kvconfig --group General --key theme "$kvantum_target"
  fi
fi

# --- GTK colours: kde-gtk-config regenerates gtk-{3,4}.0/colors.css,
# gtk.css and window_decorations.css from the colour scheme at every login.
# Older Saturn skel shipped gtk-4.0 copies as symlinks relative to the wrong
# directory (broken), which blocked it from writing, leaving GTK 4 apps in
# stock Breeze blue. Remove broken links; the next write replaces them.
for f in colors.css gtk.css window_decorations.css; do
  l="$HOME/.config/gtk-4.0/$f"
  [ -L "$l" ] && [ ! -e "$l" ] && rm -f "$l"
done

# --- GTK 3/4 prefer-dark-theme and icon theme ---
for ver in gtk-3.0 gtk-4.0; do
  f="$HOME/.config/$ver/settings.ini"
  [ -f "$f" ] || continue

  current_gtk=$(kreadconfig6 --file "$ver/settings.ini" --group Settings --key gtk-application-prefer-dark-theme 2>/dev/null)
  if [ "$current_gtk" != "$gtk_dark" ]; then
    kwriteconfig6 --file "$ver/settings.ini" --group Settings --key gtk-application-prefer-dark-theme "$gtk_dark"
  fi

  # GTK 3/4 theme is always Breeze: kde-gtk-config generates its colours from
  # the scheme (light or dark). Breeze-Dark ignores them in GTK 4 (verified:
  # stock blue widgets), so older installs' Breeze-Dark is moved to Breeze.
  current_theme=$(kreadconfig6 --file "$ver/settings.ini" --group Settings --key gtk-theme-name 2>/dev/null)
  case "$current_theme" in
    Breeze|Breeze-Dark|"")
      [ "$current_theme" != "$gtk_theme" ] && kwriteconfig6 --file "$ver/settings.ini" --group Settings --key gtk-theme-name "$gtk_theme" ;;
  esac

  current_icons=$(kreadconfig6 --file "$ver/settings.ini" --group Settings --key gtk-icon-theme-name 2>/dev/null)
  if [ "$current_icons" != "$gtk_icons" ]; then
    kwriteconfig6 --file "$ver/settings.ini" --group Settings --key gtk-icon-theme-name "$gtk_icons"
  fi
done

# --- Konsole/Yakuake default profile ---
profile="$HOME/.local/share/konsole/shani.profile"
if [ -f "$profile" ]; then
  # Konsole reads ColorScheme from [Appearance]; older Saturn builds wrote
  # it to [General], where Konsole ignores it - move it.
  kwriteconfig6 --file "$profile" --group General --key ColorScheme --delete 2>/dev/null
  current_konsole=$(kreadconfig6 --file "$profile" --group Appearance --key ColorScheme 2>/dev/null)
  if [ "$current_konsole" != "$konsole_scheme" ]; then
    kwriteconfig6 --file "$profile" --group Appearance --key ColorScheme "$konsole_scheme"
  fi
fi

# --- Yakuake skin follows the scheme (a non-Saturn skin is the user's choice) ---
# Yakuake reads Skin from [Appearance]; older Saturn skel files put it under
# [Window], where it was ignored (stock skin) - drop that stray key.
kwriteconfig6 --file yakuakerc --group Window --key Skin --delete 2>/dev/null
case "$(kreadconfig6 --file yakuakerc --group Appearance --key Skin 2>/dev/null)" in
  Saturn|Saturn-Dark|"")
    kwriteconfig6 --file yakuakerc --group Appearance --key Skin "$yakuake_skin" ;;
esac
