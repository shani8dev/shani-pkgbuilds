var plasma = getApiVersion(1)

// Create bottom panel (Dock) //

const dock = new Panel

// Basic Dock Geometry
// Property names/values verified against plasma-workspace shell/scripting/panel.cpp
// (opacity accepts "adaptive"|"opaque"|"translucent"; hiding enum same as panel)
dock.alignment = "center"
dock.floating = true
dock.opacity = "adaptive"
dock.height = Math.round(gridUnit * 3.8)
dock.hiding = "dodgewindows"
dock.lengthMode = "fit"
dock.location = "bottom"

// Icons-Only Task Manager
var tasks = dock.addWidget("org.kde.plasma.icontasks")
tasks.currentConfigGroup = ["General"]
tasks.writeConfig("fill", false)
tasks.writeConfig("iconSpacing", 2)
tasks.writeConfig("launchers", "applications:org.kde.discover.desktop,preferred://browser,preferred://filemanager,applications:org.kde.konsole.desktop,applications:org.kde.plasma-systemmonitor.desktop,applications:systemsettings.desktop,file:///var/lib/flatpak/exports/share/applications/org.kde.kate.desktop,file:///var/lib/flatpak/exports/share/applications/org.onlyoffice.desktopeditors.desktop,file:///var/lib/flatpak/exports/share/applications/org.kde.kcalc.desktop")
tasks.writeConfig("maxStripes", 1)
tasks.writeConfig("showOnlyCurrentDesktop", false)
tasks.writeConfig("showOnlyCurrentScreen", false)

// Trash - macOS has one; ours is a real widget with drag-drop support
if (knownWidgetTypes.includes("org.kde.plasma.trash")) {
  dock.addWidget("org.kde.plasma.trash")
}

// End of Dock creation //
