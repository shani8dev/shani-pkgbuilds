[Appearance]
ColorScheme=SaturnDark
# Font: none set, so Konsole uses the system fixed-width font (kdeglobals
# fixed=, FiraMono Nerd Font) like every other KDE app
LineSpacing=1
BlurBehind=true

[Cursor Options]
CursorShape=2
CustomCursorColor=255,127,80
UseCustomCursorColor=true

[General]
# Command= is required, and fish is a declared dependency because of it.
# Konsole/Yakuake do NOT fall back to the login shell when it is absent:
# Profile::Command is inherited from the built-in profile, whose value is
# defaultShell() = qgetenv("SHELL"). With no $SHELL in the environment
# (systemd units, bare ExecStart=, non-login su) that is empty, and
# Session::run() logs
#   Could not find '', starting '/usr/bin/bash' instead.  Please check your
#   profile settings.
# and silently runs bash, ignoring the user's real shell. Pinning fish keeps
# chsh working: the terminal runs the shell named here, so `chsh` is picked up
# on next launch.
Command=/usr/bin/fish
Name=Shani
Parent=FALLBACK/
TerminalColumns=110

[Interaction Options]
AutoCopySelectedText=true
TrimLeadingSpacesInSelectedText=true
TrimTrailingSpacesInSelectedText=true
UnderlineFilesEnabled=true

[Keyboard]
KeyBindings=default

[Scrolling]
HistoryMode=1
HistorySize=20000

[Terminal Features]
BlinkingCursorEnabled=true
