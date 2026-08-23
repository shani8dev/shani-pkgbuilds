#!/bin/bash
# Global Theme switching only reliably pushes a fixed set of keys live
# (color scheme, Plasma theme, icons, cursor, wallpaper, KWin decoration).
# Kvantum, GTK app style, and Konsole/Yakuake's terminal color scheme are
# NOT in that recognized set, so they keep whatever they had from the
# previous login until something re-syncs them. This runs once per session
# start and brings all three in line with whichever Saturn color scheme
# is currently active.

scheme=$(kreadconfig6 --file kdeglobals --group General --key ColorScheme 2>/dev/null)

case "$scheme" in
  SaturnDark)     kvantum_target=Saturn;         gtk_dark=true;  gtk_icons=Saturn;      konsole_scheme=SaturnDark     ;;
  SaturnLight)    kvantum_target=SaturnLight;    gtk_dark=false; gtk_icons=SaturnLight; konsole_scheme=SaturnLight    ;;
  SaturnTwilight) kvantum_target=SaturnTwilight; gtk_dark=true;  gtk_icons=Saturn;      konsole_scheme=SaturnTwilight ;;
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
