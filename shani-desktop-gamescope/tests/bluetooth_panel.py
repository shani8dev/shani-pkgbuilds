# Drives the real BluetoothPanel against the fake BlueZ and asserts on what reached it.
import sys
sys.path.insert(0, "/usr/lib/shani-desktop-gamescope")
import gi
gi.require_version("Gtk", "4.0"); gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk
import panels

results = []
def check(name, ok):
    results.append(ok); print(("PASS " if ok else "FAIL ") + name, flush=True)

def calls():
    try: return open("/tmp/bluez-calls").read()
    except OSError: return ""

def rows(panel):
    out = []
    def walk(w):
        if isinstance(w, Adw.ActionRow): out.append((w.get_title(), w.get_subtitle()))
        c = w.get_first_child()
        while c: walk(c); c = c.get_next_sibling()
    walk(panel)
    return out

app = Adw.Application(application_id="dev.shani.btdrive")
def steps(panel):
    yield 1.0
    r = rows(panel)
    check("paired headset listed with battery", ("Arctis Headset", "Headset · Connected · battery 80%") in r)
    check("controller offered for pairing", ("Wireless Controller", "Controller · Select to pair") in r)
    check("nameless advertiser hidden", not any(t in ("", None) for t, _ in r))
    check("discovery started", "StartDiscovery" in calls())
    path = "/org/bluez/hci0/dev_AA"
    objs = panel._objects()
    panel._connect(path, objs[path]["org.bluez.Device1"])
    yield 1.5
    c = calls()
    check("pair, trust, connect in order", c.index("Device1.Pair") < c.index("'Trusted'") < c.index("Device1.Connect"))
    check("controller now under My devices as connected", ("Wireless Controller", "Controller · Connected") in rows(panel))
    panel._forget("/org/bluez/hci0/dev_BB")
    yield 1.0
    check("forget removes the headset", "RemoveDevice" in calls() and not any(t == "Arctis Headset" for t, _ in rows(panel)))
    panel.power.set_active(False)
    yield 1.0
    check("power off reaches the adapter", "Properties.Set ('org.bluez.Adapter1', 'Powered', False)" in calls())
    panel.close()
    yield 0.5
    check("closing stops discovery", "StopDiscovery" in calls())
    print(f"RESULT pass={sum(results)} fail={len(results)-sum(results)}", flush=True)
    app.quit()

def activate(a):
    win = Adw.ApplicationWindow(application=a); win.present()
    panel = panels.BluetoothPanel(win); panel.present()
    it = steps(panel)
    def tick():
        try: GLib.timeout_add(int(next(it) * 1000), tick)
        except StopIteration: pass
        return False
    tick()
app.connect("activate", activate)
app.run([])
