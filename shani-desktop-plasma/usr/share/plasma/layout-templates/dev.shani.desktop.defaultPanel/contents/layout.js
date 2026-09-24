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
  // Known limitation (verified 2026-09-23, applet 0.14.0 / Aurorae 6.7): the
  // applet only treats plugin "org.kde.kwin.aurorae" as Aurorae, but on
  // Plasma 6.7 SVG themes are listed by "org.kde.kwin.aurorae.v2" (v1 lists
  // only QML themes). So it can't find the Saturn theme and draws Breeze's
  // buttons for maximized windows - kept deliberately (maintainer's choice
  // over keeping title bars). Following the current decoration means a
  // future applet release that knows v2 picks up the Saturn buttons.
  buttons.writeConfig("selectedPlugin", "org.kde.kwin.aurorae")
  buttons.writeConfig("selectedTheme", "__aurorae__svg__Saturn-Dark")
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
// Network Speed - Plasma's own, Plasma-6-native sensor widget (ksystemstats;
// every third-party one shells out via the Plasma 5 compat layer) with the
// Saturn compact face (arrows in the scheme's positive/accent colours), no title. Keys verified against libksysguard SensorFaceController and the
// applet's main.xml (Appearance/chartFace, Sensors/highPrioritySensorIds,
// the face's own arrows/colours).
if (knownWidgetTypes.includes("org.kde.plasma.systemmonitor.net")) {
  var net = panel.addWidget("org.kde.plasma.systemmonitor.net")
  net.currentConfigGroup = ["Appearance"]
  // dev.shani.netspeed (usr/share/ksysguard/sensorfaces): download over
  // upload in two small lines - the stock faces are wide or tiny charts
  net.writeConfig("chartFace", "dev.shani.netspeed")
  net.writeConfig("title", "")
  net.currentConfigGroup = ["Sensors"]
  net.writeConfig("highPrioritySensorIds", '["network/all/download","network/all/upload"]')
  // arrow colours come from the colour scheme (the face uses positive/accent)
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
