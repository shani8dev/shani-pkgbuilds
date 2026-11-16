# Drives the Control Center with controller actions only (gamepad.Navigator,
# the same entry point the evdev reader calls): the Wi-Fi password and the
# factory-reset word are typed on the on-screen keyboard, B closes the front
# dialog and not its window. Screenshots go to /out.
import importlib.machinery, importlib.util, subprocess, sys
sys.path.insert(0, "/usr/lib/shani-desktop-gamescope")
import gi
gi.require_version("Gtk", "4.0"); gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk
import gamepad, panels

loader = importlib.machinery.SourceFileLoader("ctl", "/usr/local/bin/shani-gamescope-control")
spec = importlib.util.spec_from_loader("ctl", loader); ctl = importlib.util.module_from_spec(spec); loader.exec_module(ctl)

results = []
def check(name, ok):
    results.append(bool(ok)); print(("PASS " if ok else "FAIL ") + name, flush=True)

# the stick: one step per push, re-armed near the centre
s = gamepad.Stick(-32768, 32767, "left", "right")
fired = [s.feed(v) for v in (0, 25000, 30000, 32767, 5000, 26000, -30000, 0, -30000)]
check("stick: one step per push", fired == [None, "right", None, None, None, "right", None, None, "left"])
h = gamepad.Stick(-1, 1, "up", "down")
check("hat: each press is a step", [h.feed(v) for v in (1, 0, 1, 0, -1)] == ["down", None, "down", None, "up"])

def osk(win):
    d = gamepad.Navigator.dialog_of(win)
    return d if isinstance(d, gamepad.OnScreenKeyboard) else None

def keys(nav, *actions):
    for a in actions:
        nav.press(a)

app = Adw.Application(application_id="dev.shani.osk")
def steps(win, nav):
    # --- the home: shelves of cards, moved between by position; B keeps it open
    home = ctl.ControlWindow(win.get_application()); home.present()
    yield 1.5
    nav_home = gamepad.Navigator(home)
    check("the home has its shelves (play, apps or system, power)",
          "switch_to_game_mode" in home.cards and "power:systemctl suspend" in home.cards and "network" in home.cards)
    first = home.get_focus()
    check("a card has the focus from the start", first in home.cards.values())
    def y_of(w):
        ok, pt = w.compute_point(home, __import__("gi").repository.Graphene.Point())
        return pt.y
    nav_home.press("down")
    yield 0.4
    below = home.get_focus()
    check("down goes to the shelf below", below in home.cards.values() and y_of(below) > y_of(first) + 40)
    nav_home.press("right")
    yield 0.4
    check("right moves along the shelf", home.get_focus() in home.cards.values() and home.get_focus() is not below)
    nav_home.press("b")
    yield 0.4
    check("B does not close the home", home.get_visible())
    nav_home.press("up"); yield 0.3; nav_home.press("up"); yield 0.3
    check("up comes back to the top shelf", y_of(home.get_focus()) < y_of(below))
    subprocess.run(["grim", "/out/home-focus.png"])

    # --- the same home with a TV remote: real key presses through the compositor
    def key(*names):
        for n in names:
            subprocess.run(["wtype", "-k", n])
    home.close()
    yield 0.5
    home = ctl.ControlWindow(win.get_application()); home.present()   # a new window has the keyboard
    yield 1.5
    home.on_input("pad")
    home.cards["switch_to_game_mode"].grab_focus()
    yield 0.3
    start = home.get_focus()
    key("Down")
    yield 0.4
    check("remote Down goes to the shelf below", home.get_focus() in home.cards.values() and y_of(home.get_focus()) > y_of(start) + 40)
    key("Right")
    yield 0.4
    check("remote Right moves along the shelf", y_of(home.get_focus()) > y_of(start) + 40)
    check("the hints switched to the remote's names", home.hint_mode == "remote")
    home.on_input("pad")
    key("Escape")
    yield 0.4
    check("remote Back reaches the home and does not close it", home.hint_mode == "remote" and home.get_visible())
    home.on_input("pad")
    key("XF86Back")
    yield 0.4
    check("...nor does the remote's own Back key", home.hint_mode == "remote" and home.get_visible())
    # Back closes a panel over it, and the focus is where it was
    before = home.get_focus()
    reset = ctl.ResetWindow(home); reset.present()
    yield 0.8
    key("XF86Back")
    yield 0.8
    check("remote Back closes the panel in front", not reset.get_visible())
    check("...and the home keeps its place", home.get_focus() is before)
    # OK on an empty text field: the on-screen keyboard, typed with the arrows and OK
    reset = ctl.ResetWindow(home); reset.present()
    yield 0.8
    reset.entry.grab_focus()
    key("Return")
    yield 0.8
    k = osk(reset)
    check("remote OK on an empty field opens the keyboard", k is not None)
    if k is not None:
        key("Right", "Right", "Right")       # q -> r
        yield 0.3
        key("Return")                         # OK types the key under the cursor
        yield 0.4
        check("arrows and OK type on it", reset.entry.get_text() == "r")
        key("Escape")
        yield 0.5
        check("remote Back closes the keyboard, the text stays", osk(reset) is None and reset.entry.get_text() == "r")
        key("Return")
        yield 0.5
        check("OK on a field with text does not reopen it (Enter submits)", osk(reset) is None)
    reset.close()
    home.close()
    yield 0.5

    # --- Wi-Fi password with a controller
    panel = panels.NetworkPanel(win); panel.present()
    got = []
    panel._add_and_activate = lambda network, password: got.append(password)
    network = {"ssid": "HomeNet", "device": None, "ap": None}
    panel._ask_password(network)
    yield 1.0
    nav.press("a")
    yield 0.8
    k = osk(panel)
    check("A on the password field opens the keyboard", k is not None)
    if k is None:
        return
    # Q (Select = one capital), w e r t y, then up to the digits: 1 2, and an extra 2 deleted with X
    keys(nav, "select", "a", *["right", "a"] * 5, "up", *["left"] * 5, "a", "right", "a", "a", "x")
    yield 0.5
    check("typed into the field", k.field.get_text() == "Qwerty12")
    check("password stays hidden on the keyboard", k.preview.get_label() == "••••••••▏")
    subprocess.run(["grim", "/out/osk-wifi.png"])
    nav.press("start")
    yield 0.8
    check(f"Start = Enter: the network is joined with that password ({got})", got == ["Qwerty12"])
    check("keyboard and dialog are gone", gamepad.Navigator.dialog_of(panel) is None)

    # --- B closes the front dialog, not the panel
    panel._ask_password(network)
    yield 0.8
    nav.press("b")
    yield 0.8
    check("B closes the password dialog", gamepad.Navigator.dialog_of(panel) is None)
    check("...and leaves the panel open", panel.get_visible())
    panel.close()
    yield 0.8

    # --- factory reset: the word RESET, symbols layout reachable
    reset = ctl.ResetWindow(win); reset.present()
    yield 0.8
    reset.entry.grab_focus()
    nav.press("a")
    yield 0.8
    k = osk(reset)
    check("A on the RESET field opens the keyboard", k is not None)
    if k is None:
        return
    # from q (1,0): R=(1,3)  E=(1,2)  S=(2,1)  E=(1,2)  T=(1,4)
    keys(nav, "select", "right", "right", "right", "a",       # R
              "select", "left", "a",                          # E
              "select", "down", "left", "a",                  # S (row 2, col 1)
              "select", "up", "right", "a",                   # E (back to row 1, col 2)
              "select", "right", "right", "a")                # T
    yield 0.5
    check(f"typed RESET ({reset.entry.get_text()!r})", reset.entry.get_text() == "RESET")
    check("the Reset button unlocks", reset.reset_button.get_sensitive())
    # the symbols layout: down to the bottom row, ?123
    keys(nav, "down", "down", "down")
    pos = k._position()
    check("bottom row reached", pos is not None and pos[0] == len(k.rows) - 1)
    keys(nav, "left", "a")  # Space -> ?123
    yield 0.5
    check("?123 switches to symbols", k.layout == "symbols")
    check("the cursor is still on ?123's key after the new layout", k.get_focus() is k.rows[-1][1])
    subprocess.run(["grim", "/out/osk-symbols.png"])
    nav.press("b")
    yield 0.5
    check("B closes the keyboard, the text stays", osk(reset) is None and reset.entry.get_text() == "RESET")
    check("...and the reset window stays", reset.get_visible())
    reset.close()

def activate(a):
    win = Adw.ApplicationWindow(application=a); win.present()
    nav = gamepad.Navigator(win)
    it = steps(win, nav)
    def tick():
        try: GLib.timeout_add(int(next(it) * 1000), tick)
        except StopIteration:
            print(f"RESULT pass={sum(results)} fail={len(results)-sum(results)}", flush=True); a.quit()
        return False
    tick()
app.connect("activate", activate)
app.run([])
