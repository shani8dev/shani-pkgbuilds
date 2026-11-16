# SPDX-License-Identifier: GPL-3.0-only
"""Controller support for the Shani Console's Control Center.

watch(press) reads every connected gamepad (evdev) and calls press(action) on
the GTK main loop, with action one of up, down, left, right, a, b, x, y,
start, select. The D-pad works both as buttons and as the hat axes most
Xbox-style pads report it with, the left stick moves one step per push, and a
pad connected later is picked up.

Navigator(window).press(action) turns those into what a keyboard would do:
move focus, activate, close the front dialog or window. A on a text field
opens OnScreenKeyboard, so a console with only a controller can still type a
Wi-Fi password or the factory-reset confirmation.

remote_keys(window) does the same for a TV remote (Bluetooth, USB, an air
mouse): those arrive as keys - arrows, OK/Enter, Back/Escape, Home - and get
the controller's meanings, the way an Android TV is driven: everything with
the arrows and OK, Back one level up (never out of the home), OK on an empty
text field brings up the on-screen keyboard.

Buttons follow the Linux gamepad layout (Documentation/input/gamepad.rst):
south = A, east = B, west = X, north = Y, by position, which is what the
hints on screen name.
"""

import threading

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, GLib, GObject, Gtk  # noqa: E402

# ------------------------------------------------------------------ input


def _actions(ecodes):
    """evdev key codes -> action names (both the old and the positional names)."""
    table = {}
    for names, action in (
        (("BTN_SOUTH", "BTN_A"), "a"),
        (("BTN_EAST", "BTN_B"), "b"),
        (("BTN_WEST",), "x"),
        (("BTN_NORTH",), "y"),
        (("BTN_START",), "start"),
        (("BTN_SELECT",), "select"),
        (("BTN_DPAD_UP", "KEY_UP"), "up"),
        (("BTN_DPAD_DOWN", "KEY_DOWN"), "down"),
        (("BTN_DPAD_LEFT", "KEY_LEFT"), "left"),
        (("BTN_DPAD_RIGHT", "KEY_RIGHT"), "right"),
    ):
        for name in names:
            if hasattr(ecodes, name):
                table[getattr(ecodes, name)] = action
    return table


class Stick:
    """One analog axis -> one step per push: past 60% of the travel fires,
    back under 30% re-arms. Hat axes (-1, 0, 1) go through the same code."""

    def __init__(self, lo, hi, negative, positive):
        self.mid = (lo + hi) / 2
        self.half = max(1, (hi - lo) / 2)
        self.negative, self.positive = negative, positive
        self.armed = True

    def feed(self, value):
        pos = (value - self.mid) / self.half
        if self.armed and abs(pos) >= 0.6:
            self.armed = False
            return self.positive if pos > 0 else self.negative
        if abs(pos) < 0.3:
            self.armed = True
        return None


def watch(press):
    """Read every gamepad in a daemon thread; press(action) on the main loop.
    Returns False when python-evdev is missing (no controller support)."""
    try:
        import evdev
        from evdev import ecodes
    except ImportError:
        return False
    keys = _actions(ecodes)
    watched = set()

    def is_pad(device):
        caps = device.capabilities().get(ecodes.EV_KEY, [])
        return ecodes.BTN_SOUTH in caps or ecodes.BTN_A in caps

    def read(device):
        sticks = {}
        for code, (neg, pos) in ((ecodes.ABS_HAT0X, ("left", "right")),
                                 (ecodes.ABS_HAT0Y, ("up", "down")),
                                 (ecodes.ABS_X, ("left", "right")),
                                 (ecodes.ABS_Y, ("up", "down"))):
            try:
                info = device.absinfo(code)
            except (OSError, KeyError, TypeError):
                continue
            if info is not None:
                sticks[code] = Stick(info.min, info.max, neg, pos)
        try:
            for ev in device.read_loop():
                action = None
                if ev.type == ecodes.EV_KEY and ev.value == 1:
                    action = keys.get(ev.code)
                elif ev.type == ecodes.EV_ABS and ev.code in sticks:
                    action = sticks[ev.code].feed(ev.value)
                if action:
                    GLib.idle_add(lambda a=action: press(a) and False)
        except OSError:
            pass  # unplugged
        finally:
            watched.discard(device.path)

    def scan():
        while True:
            for path in evdev.list_devices():
                if path in watched:
                    continue
                try:
                    device = evdev.InputDevice(path)
                    if not is_pad(device):
                        device.close()
                        continue
                except OSError:
                    continue
                watched.add(path)
                threading.Thread(target=read, args=(device,), daemon=True).start()
            threading.Event().wait(3)

    threading.Thread(target=scan, daemon=True).start()
    return True


# ------------------------------------------------------------- navigation


def editable_of(widget):
    """The text field a focused widget belongs to (Gtk.Text inside an
    Adw.EntryRow or a Gtk.Entry), or None."""
    while widget is not None:
        if isinstance(widget, Gtk.Text):
            return widget
        if isinstance(widget, Gtk.Editable):
            delegate = widget.get_delegate()
            return delegate if isinstance(delegate, Gtk.Text) else widget
        widget = widget.get_parent()
    return None


def _centre(widget, window):
    from gi.repository import Graphene
    ok, point = widget.compute_point(window, Graphene.Point().init(widget.get_width() / 2,
                                                                   widget.get_height() / 2))
    return (point.x, point.y) if ok else None


def move_by_position(window, action):
    """Focus the nearest item in a direction: up/down - the nearest row above
    or below, then the item in it closest across; left/right - the next item
    in the same row. At an edge nothing moves."""
    items = [w for w in window.focus_candidates()
             if w.get_mapped() and w.is_sensitive() and w.get_focusable()]
    current = window.get_focus()
    if current not in items:
        if items:
            items[0].grab_focus()
        return
    here = _centre(current, window)
    if here is None:
        return
    others = []
    for w in items:
        if w is current:
            continue
        c = _centre(w, window)
        if c is not None:
            others.append((w, c[0] - here[0], c[1] - here[1]))
    row = max(12, current.get_height() / 3)
    if action in ("up", "down"):
        sign = 1 if action == "down" else -1
        ahead = [(w, dx, dy) for w, dx, dy in others if dy * sign > row]
        if not ahead:
            return
        nearest = min(abs(dy) for _, _, dy in ahead)
        line = [(w, dx, dy) for w, dx, dy in ahead if abs(dy) - nearest < row]
        target = min(line, key=lambda t: abs(t[1]))[0]
    else:
        sign = 1 if action == "right" else -1
        ahead = [(w, dx, dy) for w, dx, dy in others if abs(dy) < row and dx * sign > 0]
        if not ahead:
            return
        target = min(ahead, key=lambda t: abs(t[1]))[0]
    target.grab_focus()


# keys a remote sends -> the controller's action names
REMOTE_MOVES = {Gdk.KEY_Up: "up", Gdk.KEY_Down: "down", Gdk.KEY_Left: "left", Gdk.KEY_Right: "right"}
REMOTE_BACK = {Gdk.KEY_Escape, Gdk.KEY_Back}
REMOTE_OK = {Gdk.KEY_Return, Gdk.KEY_KP_Enter, Gdk.KEY_ISO_Enter, Gdk.KEY_Select}


def remote_keys(window):
    """Drive WINDOW (and what opens over it) with a remote's keys.

    Arrows move like the d-pad where the window moves by position (the home)
    or the on-screen keyboard is open; elsewhere GTK's own arrow keys already
    do the right thing and are left alone. Back closes what is in front (never
    the home). OK on an EMPTY text field opens the on-screen keyboard - typed
    text and Enter still submit, as with a keyboard. Returns the handler, for
    the tests."""
    nav = Navigator(window)

    def handle(keyval):
        handled = act(keyval)
        if hasattr(window, "on_input") and (handled or keyval in REMOTE_MOVES or keyval in REMOTE_OK):
            window.on_input("remote")     # after the press, which says "pad"
        return handled

    def act(keyval):
        front = nav.target()
        dialog = Navigator.dialog_of(front)
        if keyval in REMOTE_MOVES:
            if isinstance(dialog, OnScreenKeyboard) or (dialog is None and hasattr(front, "focus_candidates")):
                nav.press(REMOTE_MOVES[keyval])
                return True
            return False
        if keyval in REMOTE_BACK:
            nav.press("b")
            return True
        if keyval in REMOTE_OK and not isinstance(dialog, OnScreenKeyboard):
            field = editable_of(front.get_focus())
            if field is not None and field.get_text() == "":
                OnScreenKeyboard(field).present(front)
                return True
        return False

    controller = Gtk.EventControllerKey()
    controller.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
    controller.connect("key-pressed", lambda _c, keyval, _code, _state: handle(keyval))
    window.add_controller(controller)
    return handle


class Navigator:
    """What each controller action does in the Control Center's windows."""

    def __init__(self, window):
        self.window = window

    def target(self):
        """The window in front: a panel over the Control Center, not always
        the main window, so B closes the panel and not everything.

        It follows the modal chain (main window -> its modal panel -> that
        panel's modal child), which is where GTK sends input anyway, rather
        than the compositor's idea of the active window, which lags behind a
        window that has just opened."""
        current = self.window
        while True:
            child = next((w for w in Gtk.Window.list_toplevels()
                          if w.get_visible() and w.get_modal()
                          and w.get_transient_for() is current), None)
            if child is None:
                return current
            current = child

    @staticmethod
    def dialog_of(window):
        get = getattr(window, "get_visible_dialog", None)
        return get() if get else None

    def press(self, action):
        if hasattr(self.window, "on_input"):
            self.window.on_input("pad")
        window = self.target()
        dialog = self.dialog_of(window)
        if isinstance(dialog, OnScreenKeyboard):
            dialog.press(action)
            return False
        if action in ("up", "down", "left", "right") and hasattr(window, "focus_candidates"):
            # a window of shelves (the home): by where things are on screen.
            # GTK's own directional focus will not leave a sideways-scrolling
            # shelf for the one below it, so the move is made here
            move_by_position(window, action)
        elif action in ("up", "down", "left", "right"):
            shelves = False
            direction = {
                "up": Gtk.DirectionType.UP if shelves else Gtk.DirectionType.TAB_BACKWARD,
                "down": Gtk.DirectionType.DOWN if shelves else Gtk.DirectionType.TAB_FORWARD,
                "left": Gtk.DirectionType.LEFT,
                "right": Gtk.DirectionType.RIGHT,
            }[action]
            # the window moves focus on from where it is, as a key press would
            # (asking the focused widget itself only searches inside it - a
            # button has nothing inside, so nothing ever moved)
            window.child_focus(direction)
        elif action == "a":
            focus = window.get_focus()
            field = editable_of(focus)
            if field is not None:
                OnScreenKeyboard(field).present(window)
            elif focus is not None:
                # rows (Adw.ActionRow) and buttons both answer activate()
                focus.activate()
        elif action in ("b", "start", "select"):
            # a dialog over the window first (the Wi-Fi password, a
            # confirmation), then the window itself
            if dialog is not None:
                dialog.close()
            elif not getattr(window, "home", False):
                window.close()
        return False


# --------------------------------------------------------- the keyboard

LAYOUTS = {
    "lower": ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"],
    "upper": ["1234567890", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"],
    "symbols": ["1234567890", "!@#$%^&*()", "-_=+[]{}\\|", ";:'\",.<>/?", "`~"],
}
CSS = """
.shani-osk { padding: 18px; }
.shani-osk-preview { font-size: 1.4em; padding: 10px 14px; border-radius: 10px;
  background: alpha(currentColor, 0.08); min-height: 1.6em; }
.shani-osk button { min-width: 24px; min-height: 52px; padding: 0; font-size: 1.2em; }
.shani-osk button:focus-visible, .shani-osk button:focus {
  outline: 3px solid @accent_color; outline-offset: 1px; }
.shani-osk-hint { opacity: 0.7; }
"""


class OnScreenKeyboard(Adw.Dialog):
    """A keyboard for a controller: the D-pad picks a key, A types it,
    X deletes, Y is a space, Select switches case, Start is Enter and B
    closes. Every key is a button, so touch and a mouse work as well.

    Keys go straight into the field, the way a hardware keyboard would, so
    closing never loses what was typed; Done also presses Enter (which joins
    the network in the Wi-Fi dialog)."""

    def __init__(self, field):
        super().__init__(title="Keyboard")
        # as wide as a television wants, narrower on a small window: the
        # grid's keys share whatever width there is
        self.set_content_width(900)
        self.field = field
        self.secret = not field.get_visibility() if isinstance(field, Gtk.Text) else False
        self.layout = "lower"
        self.rows = []
        self.pos = (1, 0)  # q: the cursor, (row, key)
        provider = Gtk.CssProvider()
        provider.load_from_string(CSS)
        Gtk.StyleContext.add_provider_for_display(
            field.get_display(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.add_css_class("shani-osk")
        self.preview = Gtk.Label(xalign=0)
        self.preview.add_css_class("shani-osk-preview")
        self.preview.set_ellipsize(3)  # Pango.EllipsizeMode.START
        box.append(self.preview)
        self.keys = Gtk.Box()
        box.append(self.keys)
        hint = Gtk.Label(label="A type · X delete · Y space · Select shift · Start done · B close")
        hint.add_css_class("shani-osk-hint")
        hint.add_css_class("caption")
        box.append(hint)
        self.set_child(box)
        self._build()
        self._update_preview()
        self.connect("map", lambda *_: self._focus(1, 0))

    # ----------------------------------------------------------- building

    def _build(self):
        """The keys on a 20-column grid, each letter two columns wide: rows
        of 10, 9 and 7 keys sit staggered like a real keyboard, and the grid
        takes whatever width the window has."""
        old = self.keys.get_first_child()
        grid = Gtk.Grid(column_homogeneous=True, row_spacing=6, column_spacing=6)
        self.rows = []
        for r, chars in enumerate(LAYOUTS[self.layout]):
            # a letter key types its own label, so Shift only relabels
            row = [self._key(c, lambda b: self.type(b.get_label())) for c in chars]
            start = 10 - len(chars)  # centred: (20 - 2 * len) / 2
            for c, button in enumerate(row):
                grid.attach(button, start + 2 * c, r, 2, 1)
            self.rows.append(row)
        special = [
            self._key(self._special_labels()[0], lambda _b: self.shift()),
            self._key(self._special_labels()[1], lambda _b: self.symbols()),
            self._key("Space", lambda _b: self.type(" ")),
            self._key("⌫", lambda _b: self.backspace()),
            self._key("Done", lambda _b: self.done(), suggested=True),
        ]
        for c, button in enumerate(special):
            grid.attach(button, 4 * c, len(self.rows), 4, 1)
        self.rows.append(special)
        # the cursor follows touch and the mouse too
        for r, row in enumerate(self.rows):
            for c, button in enumerate(row):
                button.connect("notify::has-focus", self._focused, (r, c))
        self.keys.append(grid)
        # focus moves to the new grid BEFORE the old one goes: removing the
        # focused key would make GTK hunt for a new focus by itself
        if old is not None:
            self._focus(*self.pos)
            self.keys.remove(old)

    def _focused(self, button, _pspec, where):
        if button.has_focus():
            self.pos = where

    def _special_labels(self):
        return ("⇧ Shift", "abc" if self.layout == "symbols" else "?123")

    @staticmethod
    def _key(label, callback, suggested=False):
        button = Gtk.Button(label=label, hexpand=True)
        if suggested:
            button.add_css_class("suggested-action")
        button.connect("clicked", callback)
        return button

    # ------------------------------------------------------------ editing

    def _update_preview(self):
        text = self.field.get_text()
        shown = "•" * len(text) if self.secret else text
        self.preview.set_label(shown + "▏")

    def type(self, text):
        position = len(self.field.get_text())
        self.field.insert_text(text, position)
        self.field.set_position(-1)
        if self.layout == "upper":
            # one capital, like a phone keyboard
            self.layout = "lower"
            self._relabel()
        self._update_preview()

    def backspace(self):
        text = self.field.get_text()
        if text:
            self.field.delete_text(len(text) - 1, len(text))
        self._update_preview()

    def shift(self):
        self.layout = {"lower": "upper", "upper": "lower", "symbols": "upper"}[self.layout]
        self._relabel()

    def symbols(self):
        self.layout = "lower" if self.layout == "symbols" else "symbols"
        self._relabel()

    def _relabel(self):
        """Show the current layout. Same shape (lower/upper): new labels on
        the same buttons, so focus never moves. Otherwise a new grid, with
        the cursor kept where it was."""
        chars = LAYOUTS[self.layout]
        if [len(row) for row in chars] == [len(row) for row in self.rows[:-1]]:
            for row, text in zip(self.rows, chars):
                for button, char in zip(row, text):
                    button.set_label(char)
            for button, label in zip(self.rows[-1], self._special_labels()):
                button.set_label(label)
            return
        r, c = self.pos
        if r == len(self.rows) - 1:
            # the special keys stay under the cursor, whatever row they are on
            self.pos = (len(chars), c)
        self._build()

    def done(self):
        field = self.field
        self.close()
        field.grab_focus()
        field.set_position(-1)
        # Enter: GtkText/GtkEntry's own "activate" signal, which is what
        # Adw.EntryRow's entry-activated and activates-default listen to
        # (Gtk.Widget.activate() does not emit it on a GtkText)
        if GObject.signal_lookup("activate", type(field)):
            field.emit("activate")

    # ---------------------------------------------------------- the pad

    def _position(self):
        return self.pos

    def _focus(self, r, c):
        """Move the cursor."""
        r = max(0, min(r, len(self.rows) - 1))
        c = max(0, min(c, len(self.rows[r]) - 1))
        self.pos = (r, c)
        self.rows[r][c].grab_focus()

    def press(self, action):
        r, c = self.pos
        if action in ("left", "right"):
            row = self.rows[r]
            self._focus(r, (c + (1 if action == "right" else -1)) % len(row))
        elif action in ("up", "down"):
            to = (r + (1 if action == "down" else -1)) % len(self.rows)
            # the key above/below in proportion, since rows differ in length
            span_from = max(1, len(self.rows[r]) - 1)
            span_to = max(1, len(self.rows[to]) - 1)
            self._focus(to, round(c * span_to / span_from))
        elif action == "a":
            self.rows[r][c].emit("clicked")
        elif action == "x":
            self.backspace()
        elif action == "y":
            self.type(" ")
        elif action == "select":
            self.shift()
        elif action == "start":
            self.done()
        elif action == "b":
            self.close()
