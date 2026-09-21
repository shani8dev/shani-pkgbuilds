var plasma = getApiVersion(1)

// Center Krunner on screen - requires relogin
const krunner = ConfigFile('krunnerrc')
krunner.group = 'General'
krunner.writeEntry('FreeFloating', true);

// Change keyboard repeat delay from default 600ms to 250ms
const kbd = ConfigFile('kcminputrc')
kbd.group = 'Keyboard'
kbd.writeEntry('RepeatDelay', 250);

// Create Top Panel
// Property names/values verified against plasma-workspace shell/scripting/panel.cpp:
//   floating -> [General] floating (bool)
//   opacity  -> [General] panelOpacity (int enum; accepts "adaptive"|"opaque"|"translucent")
//   hiding   -> none | autohide | dodgewindows | windowsgobelow
const panel = new Panel
panel.alignment = "left"
panel.hiding = "none"
panel.floating = true
panel.opacity = "adaptive"
panel.height = Math.round(gridUnit * 1.8);
panel.location = "top"


// The order in which the below Applets are listed will be reflected from Left to Right in the Top Panel. //

// The Kickoff launcher - branded Shani glyph (macOS-style app logo)
var launcher = panel.addWidget("org.kde.plasma.kickoff")
launcher.currentConfigGroup = ["General"]
launcher.writeConfig("icon", "start-here-shani")
launcher.writeConfig("lengthFirstMargin", 7)
// Widget.globalShortcut - verified against shell/scripting/widget.h
launcher.globalShortcut = "Alt+F1"

// Window buttons - Using a fork for Plasma 6 (plasma6-applet-window-buttons https://aur.archlinux.org/packages/plasma6-applets-window-buttons)
if (knownWidgetTypes.includes("org.kde.windowbuttons")) {
  var buttons = panel.addWidget("org.kde.windowbuttons")
  buttons.currentConfigGroup = ["General"]
  buttons.writeConfig("buttonSizePercentage", 42)
  buttons.writeConfig("containmentType", "Plasma")
  buttons.writeConfig("inactiveStateEnabled", true)
  buttons.writeConfig("lengthFirstMargin", 6)
  buttons.writeConfig("lengthLastMargin", 6)
  buttons.writeConfig("lengthMarginsLock", false)
  buttons.writeConfig("selectedPlugin", "org.kde.kwin.aurorae")
  buttons.writeConfig("selectedTheme", "Saturn")
  buttons.writeConfig("spacing", 6)
  buttons.writeConfig("useCurrentDecoration", true)
  buttons.writeConfig("useDecorationMetrics", false)
  buttons.writeConfig("visibility", 2)
}

// Window Title - Using a fork for Plasma 6 (plasma6-applet-window-title https://aur.archlinux.org/packages/plasma6-applets-window-title)
if (knownWidgetTypes.includes("org.kde.windowtitle")) {
  var title = panel.addWidget("org.kde.windowtitle")
  title.currentConfigGroup = ["General"]
  title.writeConfig("filterActivityInfo", false)
  title.writeConfig("lengthFirstMargin", 7)
  title.writeConfig("lengthMarginsLock", false)
  title.writeConfig("filterByScreen", true)
  title.currentConfigGroup = ["Appearance"]
  title.writeConfig("altTxt", "Shani OS 🪐 ")
  title.writeConfig("isBold", true)
  title.writeConfig("visible", false)
}

// Window AppMenu - NOT PORTED TO PLASMA 6 YET, REPLACED BY GLOBAL MENU BELOW
//var appmenu = panel.addWidget("org.kde.windowappmenu")
//appmenu.currentConfigGroup = ["General"]
//appmenu.writeConfig("fillWidth", true)
//appmenu.writeConfig("toggleMaximizedOnDoubleClick", true)
//appmenu.writeConfig("filterByScreen", true)
//appmenu.writeConfig("spacing", 4)

// Window Global Menu - REMOVE IF WINDOW APP MENU GETS PORTED
var plasmaappmenu = panel.addWidget("org.kde.plasma.appmenu")

// Add Left Expandable Spacer
var spacer = panel.addWidget("org.kde.plasma.panelspacer")

// Digital Clock
var digitalclock = panel.addWidget("org.kde.plasma.digitalclock")
digitalclock.currentConfigGroup = ["Appearance"]
digitalclock.writeConfig("autoFontAndSize", false)
digitalclock.writeConfig("customDateFormat", "dddd, MMM d")
digitalclock.writeConfig("dateDisplayFormat", "BesideTime")
digitalclock.writeConfig("dateFormat", "custom")
digitalclock.writeConfig("enabledCalendarPlugins", "alternatecalendar,astronomicalevents,holidaysevents")
digitalclock.writeConfig("fontFamily", "Noto Sans")
digitalclock.writeConfig("fontStyleName", "Regular")
digitalclock.writeConfig("fontWeight", 400)
digitalclock.writeConfig("showWeekNumbers", true)

// Add Right Expandable Spacer
var spacer = panel.addWidget("org.kde.plasma.panelspacer")

// Kimpanel
if (knownWidgetTypes.includes("org.kde.plasma.kimpanel")) {
  panel.addWidget("org.kde.plasma.kimpanel");
}
// Media Controls - always-visible playback control, unlike macOS's opt-in Now Playing
if (knownWidgetTypes.includes("org.kde.plasma.mediacontroller")) {
  panel.addWidget("org.kde.plasma.mediacontroller");
}
// System Tray - surface clipboard history (macOS has nothing like it)
var tray = panel.addWidget("org.kde.plasma.systemtray")
tray.currentConfigGroup = ["General"]
// verified against applets/systemtray/main.xml: shownItems = comma-separated
// plugin ids forced visible in the main tray area (Klipper is hidden by default)
tray.writeConfig("shownItems", "org.kde.plasma.clipboard")

// User Switcher
if (knownWidgetTypes.includes("org.kde.plasma.userswitcher")) {
  var switcher = panel.addWidget("org.kde.plasma.userswitcher")
  switcher.currentConfigGroup = ["General"]
  switcher.writeConfig("showFace", true)
  switcher.writeConfig("showName", false)
  switcher.writeConfig("showTechnicalInfo", true)
}

// End of Top Panel creation //
