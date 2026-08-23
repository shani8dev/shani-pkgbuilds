var plasma = getApiVersion(1)

// Enforce the Saturn Plasma Style (documented scripting global property);
// belt-and-braces alongside plasmarc written by contents/defaults
theme = 'Saturn-dark'

// Center Krunner on screen - requires relogin
const krunner = ConfigFile('krunnerrc')
krunner.group = 'General'
krunner.writeEntry('FreeFloating', true);

// Change keyboard repeat delay from default 600ms to 250ms
const kbd = ConfigFile('kcminputrc')
kbd.group = 'Keyboard'
kbd.writeEntry('RepeatDelay', 250);

// Create Top Panel //
loadTemplate("dev.shani.desktop.defaultPanel")

// Create Bottom Panel (Dock) //
loadTemplate("dev.shani.desktop.defaultDock")

var desktopsArray = desktopsForActivity(currentActivity());
for( var j = 0; j < desktopsArray.length; j++) {
    desktopsArray[j].wallpaperPlugin = 'org.kde.image';
}
