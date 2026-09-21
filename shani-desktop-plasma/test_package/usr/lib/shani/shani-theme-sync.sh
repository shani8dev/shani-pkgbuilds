#!/bin/bash
# Global Theme switching only reliably pushes a fixed set of keys live
# (color scheme, Plasma theme, icons, cursor, wallpaper, KWin decoration).
# Kvantum, GTK app style, and Konsole/Yakuake's terminal color scheme are
# NOT in that recognized set, so they keep whatever they had from the
# previous login until something re-syncs them. This runs once per session
# start and brings all three in line with whichever Saturn color scheme
# is currently active.

scheme=$(kreadconfig6 --file kdeglobals --group General --key ColorScheme 2>/dev/null)

# NOTE: do NOT try to seed a missing ColorScheme key via kwriteconfig6 —
# a live Plasma session strips that key back out immediately (verified:
# written value reads back via kreadconfig but never lands in the file),
# so persist nothing and just default in memory.
if [ -z "$scheme" ]; then
  scheme="Saturn"
fi
# Unlike ColorScheme, widgetStyle DOES stick — and without it Qt apps
# ignore Kvantum entirely even when its theme is correctly selected.
if [ -z "$(kreadconfig6 --file kdeglobals --group General --key widgetStyle 2>/dev/null)" ]; then
  kwriteconfig6 --file kdeglobals --group General --key widgetStyle "kvantum" 2>/dev/null
fi

# --- KWin decoration: seed Breeze when absent, never overwrite ---
# Breeze follows the active color scheme (coral accent included) and needs
# no per-variant theme files. An explicitly different value is the user's
# choice and is left alone.
if [ -z "$(kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme 2>/dev/null)" ]; then
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library "org.kde.breeze" 2>/dev/null
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme "Breeze" 2>/dev/null
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
seed_kwin Effect-blur enabled true
seed_kwin Effect-blur radius 10

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

case "$scheme" in
  SaturnDark)     kvantum_target=SaturnDark;      gtk_dark=true;  gtk_icons=breeze-dark; konsole_scheme=SaturnDark  ;;
  Saturn)    kvantum_target=Saturn; gtk_dark=false; gtk_icons=breeze;      konsole_scheme=Saturn ;;
  *) exit 0 ;;
esac

# --- Kvantum ---
current_kvantum=$(kreadconfig6 --file kvantum.kvconfig --group General --key theme 2>/dev/null)
if [ "$current_kvantum" != "$kvantum_target" ]; then
  if command -v kvantummanager >/dev/null 2>&1; then
    kvantummanager --set "$kvantum_target" >/dev/null 2>&1
  else
    kwriteconfig6 --file kvantum.kvconfig --group General --key theme "$kvantum_target"
  fi
fi

# --- GTK 3/4 prefer-dark-theme and icon theme ---
for ver in gtk-3.0 gtk-4.0; do
  f="$HOME/.config/$ver/settings.ini"
  [ -f "$f" ] || continue

  current_gtk=$(kreadconfig6 --file "$ver/settings.ini" --group Settings --key gtk-application-prefer-dark-theme 2>/dev/null)
  if [ "$current_gtk" != "$gtk_dark" ]; then
    kwriteconfig6 --file "$ver/settings.ini" --group Settings --key gtk-application-prefer-dark-theme "$gtk_dark"
  fi

  current_icons=$(kreadconfig6 --file "$ver/settings.ini" --group Settings --key gtk-icon-theme-name 2>/dev/null)
  if [ "$current_icons" != "$gtk_icons" ]; then
    kwriteconfig6 --file "$ver/settings.ini" --group Settings --key gtk-icon-theme-name "$gtk_icons"
  fi
done

# --- Konsole/Yakuake default profile ---
profile="$HOME/.local/share/konsole/shani.profile"
if [ -f "$profile" ]; then
  current_konsole=$(kreadconfig6 --file "$profile" --group General --key ColorScheme 2>/dev/null)
  if [ "$current_konsole" != "$konsole_scheme" ]; then
    kwriteconfig6 --file "$profile" --group General --key ColorScheme "$konsole_scheme"
  fi
fi
