#!/bin/bash
# Container test (see run.sh): steam-shortcuts against fake flatpak/pgrep, with
# Valve's binary VDF checked by an independent parser (python vdf, at /vdf).
command -v python3 >/dev/null || pacman -Sy --noconfirm --needed python >/dev/null 2>&1 || { echo "no python"; exit 1; }
mkdir -p /fake; cp /t/fake-bin/* /fake/; chmod +x /fake/*
VP="env PYTHONPATH=/vdf python3"; $VP -c 'import vdf' || { echo "NO VDF"; exit 1; }
S=/pkg/usr/lib/shani-desktop-gamescope/steam-shortcuts
export HOME=/home/t PATH=/fake:$PATH; mkdir -p $HOME
U=$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/userdata
F=$U/12345/config/shortcuts.vdf
L=$HOME/.var/app/com.valvesoftware.Steam/data/shani-console/launch
pass=0; fail=0; ck(){ if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }
ck "no Steam login: no shortcuts, but the console's own apps are noted" 'python3 $S && [ ! -e $U ] && python3 -c "import json; b=json.load(open(\"$HOME/.local/state/shani-console/steam-shortcuts.json\"))[\"baseline\"]; assert \"org.gnome.Loupe\" in b, b"'
mkdir -p $U/12345/config $U/0
$VP -c "import vdf; open('$F','wb').write(vdf.binary_dumps({'shortcuts':{'0':{'appid':-1294967297,'AppName':'My Game','Exe':'\"/home/x/game\"','tags':{'0':'fav'}}}}))"
ck "seed written" '[ -s $F ]'
touch $HOME/steam-running
ck "Steam running: untouched" 'b=$(md5sum < $F); python3 $S 2>/dev/null; [ "$b" = "$(md5sum < $F)" ]'
rm $HOME/steam-running
# Kodi's exported icon (a blue square), and art the owner already set for Heroic
I=/var/lib/flatpak/exports/share/icons/hicolor/128x128/apps; mkdir -p $I
python3 -c "
import gi; gi.require_version('GdkPixbuf','2.0'); from gi.repository import GdkPixbuf
p=GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, True, 8, 128, 128); p.fill(0x2060e0ff); p.savev('$I/tv.kodi.Kodi.png','png',[],[])"
cp $I/tv.kodi.Kodi.png $I/com.heroicgameslauncher.hgl.png
appid() { python3 -c "import zlib; print((zlib.crc32(('\"$L\"' + '$1').encode()) | 0x80000000))"; }
G=$U/12345/config/grid; mkdir -p $G; echo owner > $G/$(appid "Heroic Games Launcher")_hero.jpg
ck "adds installed apps, the Control Center and Desktop Mode" 'python3 $S | grep -q "added com.heroicgameslauncher.hgl, org.libretro.RetroArch, tv.kodi.Kodi, control-center, desktop"'
dump(){ $VP -c "import vdf,json; print(json.dumps(vdf.binary_loads(open('$F','rb').read())))"; }
ck "independent parser: user entry kept, ours correct" 'dump | python3 -c "import json,sys; s=json.load(sys.stdin)[\"shortcuts\"]; assert s[\"0\"][\"AppName\"]==\"My Game\" and s[\"0\"][\"tags\"]=={\"0\":\"fav\"}; names=[v[\"AppName\"] for v in s.values()]; assert names==[\"My Game\",\"Heroic Games Launcher\",\"RetroArch\",\"Kodi\",\"Control Center\",\"Desktop Mode\"], names; h=s[\"1\"]; assert h[\"LaunchOptions\"]==\"com.heroicgameslauncher.hgl\" and h[\"FlatpakAppID\"]==\"com.heroicgameslauncher.hgl\" and h[\"appid\"]<0 and h[\"Exe\"]==\"\\\"$L\\\"\", h; c=s[\"4\"]; assert c[\"LaunchOptions\"]==\"control-center\" and c[\"FlatpakAppID\"]==\"\", c"'
# the launcher hands the host the display Steam gave the launch (flatpak-spawn --host forwards only --env)
cat > /fake/flatpak-spawn <<'X'
#!/bin/sh
printf '%s\n' "$@" > /tmp/spawned
X
chmod +x /fake/flatpak-spawn
sed 's|/usr/bin/flatpak-spawn|/fake/flatpak-spawn|' $L > /tmp/launch; chmod +x /tmp/launch
ck "launcher is in Steam's data dir, executable" '[ -x $L ]'
ck "launcher forwards DISPLAY and the game id to the host app" 'DISPLAY=:7 SteamGameId=99 /tmp/launch tv.kodi.Kodi && grep -qx -- "--host" /tmp/spawned && grep -qx -- "--env=DISPLAY=:7" /tmp/spawned && grep -qx -- "--env=SteamGameId=99" /tmp/spawned && [ "$(tail -3 /tmp/spawned | tr "\n" " ")" = "flatpak run tv.kodi.Kodi " ]'
ck "Control Center entry opens it in game mode" 'DISPLAY=:7 /tmp/launch control-center && grep -qx SHANI_FROM_STEAM=1 /tmp/spawned && tail -1 /tmp/spawned | grep -qx shani-gamescope-control'
ck "Desktop Mode entry asks for the desktop session" 'DISPLAY=:7 /tmp/launch desktop && [ "$(tail -3 /tmp/spawned | tr "\n" " ")" = "pkexec /usr/bin/gamescope-session-select desktop " ]'
# the whole launch, as on the console: launcher -> the host (a flatpak-spawn that
# runs the command as the host would, env from --env) -> reaper -> the app; and
# gamescope's own app id walk (gamescope_appid.py) must find the shortcut's id
cat > /fake/host-spawn <<'X'
#!/bin/sh
while [ $# -gt 0 ]; do case "$1" in --env=*) export "${1#--env=}";; --*) ;; *) break;; esac; shift; done
exec "$@"
X
chmod +x /fake/host-spawn
mkdir -p /usr/lib/shani-desktop-gamescope; cp /pkg/usr/lib/shani-desktop-gamescope/reaper /usr/lib/shani-desktop-gamescope/
sed 's|/usr/bin/flatpak-spawn|/fake/host-spawn|' $L > /tmp/launch-host; chmod +x /tmp/launch-host
KODI=$(dump | python3 -c "import json,sys; print([v for v in json.load(sys.stdin)['shortcuts'].values() if v['AppName']=='Kodi'][0]['appid'] & 0xFFFFFFFF)")
GAME=$(python3 -c "print(($KODI << 32) | 0x02000000)")
rm -f /tmp/app.pid; DISPLAY=:9 SteamGameId=$GAME /tmp/launch-host tv.kodi.Kodi & sleep 1
read APP APPDISPLAY < /tmp/app.pid
ck "gamescope finds the shortcut's app id from the app's process ($KODI)" '[ "$(python3 /t/gamescope_appid.py $APP)" = "$KODI" ]'
ck "...and the app has Steam's display" '[ "$APPDISPLAY" = ":9" ]'
ck "the reaper is the app's parent, named so gamescope sees it" '[ "$(cat /proc/$(awk "{print \$4}" /proc/$APP/stat)/comm)" = reaper ]'
wait
# negative control: the same app started on the host without the reaper is anonymous to gamescope
rm -f /tmp/app.pid; (DISPLAY=:9 flatpak run tv.kodi.Kodi &) ; sleep 1; read APP _ < /tmp/app.pid
ck "negative control: without the reaper gamescope finds no app id" '[ "$(python3 /t/gamescope_appid.py $APP)" = 0 ]'
size() { python3 -c "import gi; gi.require_version('GdkPixbuf','2.0'); from gi.repository import GdkPixbuf; p=GdkPixbuf.Pixbuf.new_from_file('$1'); print(p.get_width(), p.get_height())"; }
K=$(appid Kodi)
ck "Kodi's artwork: capsule 600x900, banner 920x430, hero 1920x620" '[ "$(size $G/${K}p.png)" = "600 900" ] && [ "$(size $G/$K.png)" = "920 430" ] && [ "$(size $G/${K}_hero.png)" = "1920 620" ]'
ck "...on a background in the icon's own colour (blue)" 'python3 -c "
import gi; gi.require_version(\"GdkPixbuf\",\"2.0\"); from gi.repository import GdkPixbuf
p=GdkPixbuf.Pixbuf.new_from_file(\"$G/${K}p.png\"); b=p.get_pixels(); r,g,bl=b[0],b[1],b[2]; assert bl > r + 20 and bl > g, (r,g,bl)"'
ck "...with the icon itself in the middle" 'python3 -c "
import gi; gi.require_version(\"GdkPixbuf\",\"2.0\"); from gi.repository import GdkPixbuf
p=GdkPixbuf.Pixbuf.new_from_file(\"$G/${K}p.png\"); s=p.get_rowstride(); n=p.get_n_channels(); b=p.get_pixels(); i=450*s+300*n; assert (b[i],b[i+1],b[i+2])==(0x20,0x60,0xe0), tuple(b[i:i+3])"'
ck "the owner's own Heroic hero art is kept, the rest is made" '[ "$(cat $G/$(appid "Heroic Games Launcher")_hero.jpg)" = owner ] && [ ! -e $G/$(appid "Heroic Games Launcher")_hero.png ] && [ -e $G/$(appid "Heroic Games Launcher")p.png ]'
ck "no icon (RetroArch): no artwork, no failure" '[ ! -e $G/$(appid RetroArch)p.png ]'
ck "not-listed app (Loupe) not added" 'dump | grep -q Heroic && ! dump | grep -q Loupe'
ck "account 0 ignored" '[ ! -e $U/0/config/shortcuts.vdf ]'
ck "Steam override granted" 'grep -q "override --user --talk-name=org.freedesktop.Flatpak com.valvesoftware.Steam" $HOME/override.log'
ck "second run adds nothing" '[ -z "$(python3 $S)" ]'
# the owner installs an app from Bazaar: it joins the library at the next game-mode start
printf 'com.moonlight_stream.Moonlight\tMoonlight\nio.github.someone.Puzzle\tPuzzle Game\n' > $HOME/installed-later
ck "an app the owner installed later joins the library, under its own name" 'python3 $S | grep -q "added com.moonlight_stream.Moonlight, io.github.someone.Puzzle" && dump | grep -q "Puzzle Game"'
ck "the console's own apps that were there from the start (Loupe) and Steam itself never do" '! dump | grep -q "Image Viewer" && ! dump | grep -q "\"Steam\""'
$VP -c "import vdf; p='$F'; d=vdf.binary_loads(open(p,'rb').read()); del d['shortcuts']['3']; open(p,'wb').write(vdf.binary_dumps(d))"
ck "owner removed Kodi; it stays removed" 'python3 $S >/dev/null; dump | grep -q RetroArch && ! dump | grep -q Kodi'
echo "RESULT pass=$pass fail=$fail"
