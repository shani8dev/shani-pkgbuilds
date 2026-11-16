# SPDX-License-Identifier: GPL-3.0-only
"""Native settings panels for the Shani Console's Control Center.

Network, Bluetooth, Audio and Display, each a libadwaita window that talks to
the system service directly: NetworkManager through libnm, BlueZ over D-Bus,
PipeWire through pactl (pipewire-pulse) and sway through swaymsg. They replace
nmtui, blueman, pavucontrol and wdisplays, which looked different from
everything else and could not be driven with a controller.

Every panel follows the same rules as the Control Center: one window, rows
that are focusable and activatable (so the D-pad and A button work), state
read from the service rather than cached, and every failure said in words.
"""

import json
import os
import subprocess
import threading

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio, GLib, Gtk  # noqa: E402

try:
    gi.require_version("NM", "1.0")
    from gi.repository import NM  # noqa: E402
except (ImportError, ValueError):
    NM = None


def run(argv, done=None, input_text=None):
    """Run argv off the GTK thread; done(rc, stdout, stderr) on the main loop."""

    def worker():
        try:
            proc = subprocess.run(argv, input=input_text, text=True,
                                  capture_output=True, timeout=60)
            result = (proc.returncode, proc.stdout, proc.stderr)
        except (OSError, subprocess.SubprocessError) as exc:
            result = (127, "", str(exc))
        if done:
            GLib.idle_add(lambda: done(*result) and False)

    threading.Thread(target=worker, daemon=True).start()


def run_json(argv):
    """Run argv now and parse its JSON output, or None."""
    try:
        out = subprocess.run(argv, text=True, capture_output=True, timeout=10).stdout
        return json.loads(out)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return None


class Panel(Adw.Window):
    """A settings window: header bar, a toast overlay and a preferences page."""

    def __init__(self, parent, title, width=640, height=720):
        super().__init__(transient_for=parent, modal=True, title=title)
        self.set_default_size(width, height)
        self.add_css_class("shani-glass")
        # a TV remote's Back closes the panel, OK on a text field types
        import gamepad
        gamepad.remote_keys(self)
        self.toasts = Adw.ToastOverlay()
        self.page = Adw.PreferencesPage()
        self.toasts.set_child(self.page)
        view = Adw.ToolbarView()
        self.header = Adw.HeaderBar()
        view.add_top_bar(self.header)
        view.set_content(self.toasts)
        self.set_content(view)
        self._timers = []
        self.connect("close-request", self._stop_timers)

    def every(self, seconds, callback):
        self._timers.append(GLib.timeout_add_seconds(seconds, callback))

    def _stop_timers(self, *_):
        for timer in self._timers:
            GLib.source_remove(timer)
        self._timers = []
        return False

    def toast(self, text):
        self.toasts.add_toast(Adw.Toast(title=GLib.markup_escape_text(text), timeout=4))

    def unavailable(self, icon, title, body):
        """Show a whole-window status page instead of the settings."""
        self.toasts.set_child(Adw.StatusPage(icon_name=icon, title=title, description=body))

    def replace_group(self, old, new):
        """Swap a preferences group in place, keeping its position."""
        if old is not None:
            self.page.remove(old)
        self.page.add(new)
        return new


def signal_icon(strength):
    for limit, name in ((80, "excellent"), (55, "good"), (30, "ok"), (5, "weak")):
        if strength >= limit:
            return f"network-wireless-signal-{name}-symbolic"
    return "network-wireless-signal-none-symbolic"


# ---------------------------------------------------------------- Network


class NetworkPanel(Panel):
    """Wi-Fi and wired networks through NetworkManager (libnm)."""

    def __init__(self, parent):
        super().__init__(parent, "Network")
        self.client = None
        self.signature = None
        if NM is not None:
            try:
                self.client = NM.Client.new(None)
            except GLib.Error:
                self.client = None
        if self.client is None:
            self.unavailable("network-offline-symbolic", "Network settings are unavailable",
                             "NetworkManager is not running.")
            return

        top = Adw.PreferencesGroup()
        self.wifi_top = top
        self.wifi_switch = Adw.SwitchRow(title="Wi-Fi")
        self.wifi_switch.set_active(self.client.wireless_get_enabled())
        self.wifi_switch.connect("notify::active", self._toggle_wifi)
        top.add(self.wifi_switch)
        self.page.add(top)

        self.wired_group = None
        self.wifi_group = None
        refresh = Gtk.Button(icon_name="view-refresh-symbolic", tooltip_text="Scan again")
        refresh.connect("clicked", lambda _b: self.scan())
        self.header.pack_end(refresh)
        self.actions_group = self._actions()
        self.scan()
        self.refresh()
        self.every(3, self._tick)

    def _wifi_devices(self):
        return [d for d in self.client.get_devices()
                if d.get_device_type() == NM.DeviceType.WIFI]

    def scan(self):
        for device in self._wifi_devices():
            device.request_scan_async(None, None, None)

    def _toggle_wifi(self, row, _pspec):
        run(["nmcli", "radio", "wifi", "on" if row.get_active() else "off"],
            lambda rc, out, err: rc == 0 or self.toast(err.strip() or "Could not switch Wi-Fi"))

    def _tick(self):
        self.refresh()
        return True

    def _saved(self):
        saved = {}
        for connection in self.client.get_connections():
            setting = connection.get_setting_wireless()
            if setting and setting.get_ssid():
                saved[NM.utils_ssid_to_utf8(setting.get_ssid().get_data())] = connection
        return saved

    def _networks(self):
        best = {}
        for device in self._wifi_devices():
            active_ap = device.get_active_access_point()
            for ap in device.get_access_points():
                raw = ap.get_ssid()
                if not raw:
                    continue
                ssid = NM.utils_ssid_to_utf8(raw.get_data())
                secured = bool(ap.get_wpa_flags() or ap.get_rsn_flags()
                               or ap.get_flags() & getattr(NM, "80211ApFlags").PRIVACY)
                entry = {"ssid": ssid, "strength": ap.get_strength(), "secured": secured,
                         "ap": ap, "device": device,
                         "active": active_ap is not None and active_ap.get_path() == ap.get_path()}
                old = best.get(ssid)
                if old is None or entry["active"] or (not old["active"] and old["strength"] < entry["strength"]):
                    best[ssid] = entry
        return sorted(best.values(), key=lambda n: (not n["active"], -n["strength"]))

    def refresh(self):
        wired = [d for d in self.client.get_devices()
                 if d.get_device_type() == NM.DeviceType.ETHERNET]
        networks = self._networks() if self.client.wireless_get_enabled() else []
        saved = self._saved()
        # Rebuild only when something a person would see changed, so the
        # focused row (and the controller's place in the list) stays put.
        signature = (
            tuple((d.get_iface(), int(d.get_state())) for d in wired),
            tuple((n["ssid"], n["active"], n["strength"] // 20, n["ssid"] in saved) for n in networks),
            self.client.wireless_get_enabled(),
        )
        if signature == self.signature:
            return
        self.signature = signature
        if self.wifi_switch.get_active() != self.client.wireless_get_enabled():
            self.wifi_switch.set_active(self.client.wireless_get_enabled())
        # A Wi-Fi switch with no Wi-Fi adapter is a control that does nothing.
        self.wifi_top.set_visible(bool(self._wifi_devices()))

        group = None
        if wired:
            group = Adw.PreferencesGroup(title="Wired")
            for device in wired:
                up = device.get_state() == NM.DeviceState.ACTIVATED
                row = Adw.ActionRow(
                    title=device.get_iface(),
                    subtitle="Connected" if up else ("Cable unplugged"
                                                      if device.get_state() == NM.DeviceState.UNAVAILABLE
                                                      else "Not connected"))
                row.add_prefix(Gtk.Image.new_from_icon_name("network-wired-symbolic"))
                group.add(row)
        if self.wired_group is not None:
            self.page.remove(self.wired_group)
        self.wired_group = group
        if group is not None:
            self.page.add(group)

        group = Adw.PreferencesGroup(title="Wi-Fi networks")
        if not self._wifi_devices():
            group.set_title("Wi-Fi")
            group.add(Adw.ActionRow(title="No Wi-Fi adapter",
                                    subtitle="Plug in an Ethernet cable, or a USB Wi-Fi adapter."))
        elif not self.client.wireless_get_enabled():
            group.add(Adw.ActionRow(title="Wi-Fi is off"))
        elif not networks:
            group.add(Adw.ActionRow(title="Looking for networks…"))
        for network in networks:
            group.add(self._network_row(network, saved.get(network["ssid"])))
        if self.wifi_group is not None:
            self.page.remove(self.wifi_group)
        self.wifi_group = group
        self.page.add(group)
        # the actions stay last, under the list a rescan rebuilds
        self.page.remove(self.actions_group)
        self.page.add(self.actions_group)

    def _actions(self):
        """Rescan as a row (where the d-pad goes, not only the header's icon)
        and an escape hatch for what a list of networks cannot do - a hidden
        network, enterprise Wi-Fi, a static address: nmtui, every
        NetworkManager setting. (Both from the console's first Wi-Fi page.)"""
        group = Adw.PreferencesGroup(title="More")
        rescan = Adw.ActionRow(title="Scan again", subtitle="Look for networks again", activatable=True)
        rescan.add_prefix(Gtk.Image.new_from_icon_name("view-refresh-symbolic"))
        rescan.connect("activated", lambda _r: (self.scan(), self.toast("Looking for networks…")))
        group.add(rescan)
        advanced = Adw.ActionRow(title="Advanced",
                                 subtitle="Hidden networks, enterprise Wi-Fi, fixed addresses (nmtui)",
                                 activatable=True)
        advanced.add_prefix(Gtk.Image.new_from_icon_name("preferences-system-symbolic"))
        advanced.connect("activated", lambda _r: self._advanced())
        group.add(advanced)
        self.page.add(group)
        return group

    def _advanced(self):
        try:
            subprocess.Popen(["foot", "-e", "nmtui"])
        except OSError as exc:
            self.toast(f"Could not open nmtui: {exc.strerror}")

    def _network_row(self, network, saved):
        if network["active"]:
            subtitle = "Connected"
        elif saved is not None:
            subtitle = "Saved"
        else:
            subtitle = "Secured" if network["secured"] else "Open"
        row = Adw.ActionRow(title=GLib.markup_escape_text(network["ssid"]), subtitle=subtitle)
        row.add_prefix(Gtk.Image.new_from_icon_name(signal_icon(network["strength"])))
        if network["secured"]:
            lock = Gtk.Image.new_from_icon_name("system-lock-screen-symbolic")
            lock.add_css_class("dim-label")
            row.add_suffix(lock)
        if network["active"]:
            button = Gtk.Button(label="Disconnect", valign=Gtk.Align.CENTER)
            button.connect("clicked", lambda _b, d=network["device"]: self._disconnect(d))
            row.add_suffix(button)
        if saved is not None:
            forget = Gtk.Button(icon_name="user-trash-symbolic", valign=Gtk.Align.CENTER,
                                tooltip_text="Forget this network")
            forget.add_css_class("flat")
            forget.connect("clicked", lambda _b, c=saved: self._forget(c))
            row.add_suffix(forget)
        if not network["active"]:
            row.set_activatable(True)
            row.connect("activated", lambda _r, n=network, s=saved: self._connect(n, s))
        return row

    def _done(self, what):
        def finished(source, result):
            try:
                getattr(source, what)(result)
            except GLib.Error as error:
                self.toast(error.message)
            self.signature = None
            self.refresh()
        return finished

    def _disconnect(self, device):
        device.disconnect_async(None, self._done("disconnect_finish"))

    def _forget(self, connection):
        connection.delete_async(None, self._done("delete_finish"))

    def _connect(self, network, saved):
        if saved is not None:
            self.toast(f"Connecting to {network['ssid']}…")
            self.client.activate_connection_async(
                saved, network["device"], network["ap"].get_path(), None,
                self._done("activate_connection_finish"))
            return
        if not network["secured"]:
            self._add_and_activate(network, None)
            return
        self._ask_password(network)

    def _ask_password(self, network):
        dialog = Adw.AlertDialog(heading=f"Join “{network['ssid']}”",
                                 body="Enter the network's password. With a controller, "
                                      "press A on the field for the keyboard.")
        entry = Adw.PasswordEntryRow(title="Password")
        box = Gtk.ListBox()
        box.add_css_class("boxed-list")
        box.append(entry)
        dialog.set_extra_child(box)
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("join", "Join")
        dialog.set_response_appearance("join", Adw.ResponseAppearance.SUGGESTED)
        dialog.set_default_response("join")
        dialog.set_response_enabled("join", False)
        entry.connect("changed", lambda e: dialog.set_response_enabled("join", len(e.get_text()) >= 8))

        def submit(row):
            if len(row.get_text()) >= 8:
                dialog.close()
                self._add_and_activate(network, row.get_text())

        entry.connect("entry-activated", submit)

        def responded(_d, response):
            if response == "join":
                self._add_and_activate(network, entry.get_text())

        dialog.connect("response", responded)
        dialog.present(self)
        entry.grab_focus()

    def _add_and_activate(self, network, password):
        connection = NM.SimpleConnection.new()
        if password is not None:
            security = NM.SettingWirelessSecurity.new()
            security.set_property(NM.SETTING_WIRELESS_SECURITY_KEY_MGMT, "wpa-psk")
            security.set_property(NM.SETTING_WIRELESS_SECURITY_PSK, password)
            connection.add_setting(security)
        self.toast(f"Connecting to {network['ssid']}…")
        self.client.add_and_activate_connection_async(
            connection, network["device"], network["ap"].get_path(), None,
            self._done("add_and_activate_connection_finish"))


# -------------------------------------------------------------- Bluetooth

BLUEZ = "org.bluez"


class BluetoothPanel(Panel):
    """Controllers, headsets and speakers through BlueZ's D-Bus API."""

    KIND = {
        "input-gaming": "Controller", "audio-headset": "Headset",
        "audio-headphones": "Headphones", "audio-card": "Speaker",
        "input-keyboard": "Keyboard", "input-mouse": "Mouse",
        "phone": "Phone", "computer": "Computer",
    }

    def __init__(self, parent):
        super().__init__(parent, "Bluetooth")
        self.signature = None
        self.devices_group = None
        try:
            self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        except GLib.Error:
            self.bus = None
        self.adapter = self._adapter() if self.bus else None
        if self.adapter is None:
            self.unavailable("bluetooth-disabled-symbolic", "No Bluetooth",
                             "This machine has no Bluetooth adapter, or it is switched off "
                             "in the firmware. A USB Bluetooth dongle works too.")
            return

        top = Adw.PreferencesGroup(
            description="To pair a controller, put it in pairing mode, then pick it below.")
        self.power = Adw.SwitchRow(title="Bluetooth")
        self.power.set_active(bool(self._prop(self.adapter, "org.bluez.Adapter1", "Powered")))
        self.power.connect("notify::active", self._toggle_power)
        top.add(self.power)
        self.page.add(top)
        self._discover(True)
        self.refresh()
        self.every(2, self._tick)
        self.connect("close-request", lambda *_: self._discover(False) or False)

    # --- D-Bus plumbing

    def _call(self, path, iface, method, args=None, done=None, timeout=30000):
        def finished(bus, result):
            try:
                bus.call_finish(result)
                error = None
            except GLib.Error as exc:
                error = exc.message.split(":")[-1].strip()
            if done:
                done(error)
            self.signature = None
            self.refresh()

        self.bus.call(BLUEZ, path, iface, method, args, None,
                      Gio.DBusCallFlags.NONE, timeout, None, finished)

    def _objects(self):
        try:
            reply = self.bus.call_sync(BLUEZ, "/", "org.freedesktop.DBus.ObjectManager",
                                       "GetManagedObjects", None, None,
                                       Gio.DBusCallFlags.NONE, 5000, None)
            return reply.unpack()[0]
        except GLib.Error:
            return {}

    def _adapter(self):
        for path, ifaces in self._objects().items():
            if "org.bluez.Adapter1" in ifaces:
                return path
        return None

    def _prop(self, path, iface, name):
        try:
            reply = self.bus.call_sync(BLUEZ, path, "org.freedesktop.DBus.Properties", "Get",
                                       GLib.Variant("(ss)", (iface, name)), None,
                                       Gio.DBusCallFlags.NONE, 5000, None)
            return reply.unpack()[0]
        except GLib.Error:
            return None

    def _set(self, path, iface, name, value, done=None):
        self._call(path, "org.freedesktop.DBus.Properties", "Set",
                   GLib.Variant("(ssv)", (iface, name, value)), done)

    # --- actions

    def _toggle_power(self, row, _pspec):
        on = row.get_active()
        self._set(self.adapter, "org.bluez.Adapter1", "Powered", GLib.Variant("b", on),
                  lambda error: (self.toast(error) if error else self._discover(on)))

    def _discover(self, on):
        if self.adapter is None:
            return
        powered = self._prop(self.adapter, "org.bluez.Adapter1", "Powered")
        discovering = self._prop(self.adapter, "org.bluez.Adapter1", "Discovering")
        if on and powered and not discovering:
            self._call(self.adapter, "org.bluez.Adapter1", "StartDiscovery")
        elif not on and discovering:
            self.bus.call(BLUEZ, self.adapter, "org.bluez.Adapter1", "StopDiscovery",
                          None, None, Gio.DBusCallFlags.NONE, 5000, None, None)

    def _tick(self):
        self.refresh()
        return True

    def _connect(self, path, device):
        name = device.get("Alias") or device.get("Name") or "device"
        if not device.get("Paired"):
            self.toast(f"Pairing {name}…")

            def paired(error):
                if error:
                    self.toast(f"Could not pair {name}: {error}")
                    return
                self._set(path, "org.bluez.Device1", "Trusted", GLib.Variant("b", True))
                self._call(path, "org.bluez.Device1", "Connect",
                           done=lambda e: self.toast(e and f"Could not connect: {e}" or f"{name} connected"))

            self._call(path, "org.bluez.Device1", "Pair", done=paired, timeout=60000)
        else:
            self.toast(f"Connecting {name}…")
            self._call(path, "org.bluez.Device1", "Connect",
                       done=lambda e: self.toast(e and f"Could not connect: {e}" or f"{name} connected"))

    def _disconnect(self, path):
        self._call(path, "org.bluez.Device1", "Disconnect")

    def _forget(self, path):
        self._call(self.adapter, "org.bluez.Adapter1", "RemoveDevice", GLib.Variant("(o)", (path,)))

    # --- view

    def refresh(self):
        devices = []
        for path, ifaces in self._objects().items():
            device = ifaces.get("org.bluez.Device1")
            if device is None or not path.startswith(self.adapter + "/"):
                continue
            if not (device.get("Name") or device.get("Paired")):
                continue  # nameless advertisers: nobody can tell what they are
            devices.append((path, device))
        devices.sort(key=lambda pd: (not pd[1].get("Connected"), not pd[1].get("Paired"),
                                     (pd[1].get("Alias") or "").lower()))
        powered = bool(self._prop(self.adapter, "org.bluez.Adapter1", "Powered"))
        signature = (powered, tuple((p, d.get("Connected"), d.get("Paired"), d.get("Alias"))
                                    for p, d in devices))
        if signature == self.signature:
            return
        self.signature = signature
        if self.power.get_active() != powered:
            self.power.set_active(powered)

        mine = Adw.PreferencesGroup(title="My devices")
        nearby = Adw.PreferencesGroup(title="Nearby")
        if powered:
            spinner = Adw.Spinner()
            nearby.set_header_suffix(spinner)
        for path, device in devices:
            (mine if device.get("Paired") else nearby).add(self._device_row(path, device))
        if not powered:
            mine.add(Adw.ActionRow(title="Bluetooth is off"))
        group = Adw.PreferencesGroup()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
        box.append(mine)
        if powered:
            box.append(nearby)
        group.add(box)
        self.devices_group = self.replace_group(self.devices_group, group)

    def _device_row(self, path, device):
        icon = device.get("Icon") or "bluetooth"
        kind = self.KIND.get(icon, "")
        if device.get("Connected"):
            state = "Connected"
            battery = self._prop(path, "org.bluez.Battery1", "Percentage")
            if battery is not None:
                state += f" · battery {battery}%"
        elif device.get("Paired"):
            state = "Not connected"
        else:
            state = "Select to pair"
        subtitle = " · ".join(x for x in (kind, state) if x)
        row = Adw.ActionRow(title=GLib.markup_escape_text(device.get("Alias") or device.get("Name")),
                            subtitle=subtitle)
        row.add_prefix(Gtk.Image.new_from_icon_name(f"{icon}-symbolic"))
        if device.get("Connected"):
            button = Gtk.Button(label="Disconnect", valign=Gtk.Align.CENTER)
            button.connect("clicked", lambda _b, p=path: self._disconnect(p))
            row.add_suffix(button)
        else:
            row.set_activatable(True)
            row.connect("activated", lambda _r, p=path, d=device: self._connect(p, d))
        if device.get("Paired"):
            forget = Gtk.Button(icon_name="user-trash-symbolic", valign=Gtk.Align.CENTER,
                                tooltip_text="Forget this device")
            forget.add_css_class("flat")
            forget.connect("clicked", lambda _b, p=path: self._forget(p))
            row.add_suffix(forget)
        return row


# ------------------------------------------------------------------ Audio


class AudioPanel(Panel):
    """Output and input devices and their volume, through pactl (PipeWire)."""

    def __init__(self, parent):
        super().__init__(parent, "Audio", height=640)
        self.groups = {}
        self.signature = None
        advanced = Gtk.Button(icon_name="emblem-system-symbolic",
                              tooltip_text="Per-app volume (pavucontrol)")
        advanced.connect("clicked", lambda _b: subprocess.Popen(["pavucontrol"]))
        self.header.pack_end(advanced)
        self.refresh()
        self.every(2, self._tick)

    def _tick(self):
        self.refresh()
        return True

    def _list(self, kind):
        items = run_json(["pactl", "-f", "json", "list", kind]) or []
        if kind == "sources":
            items = [s for s in items if not s.get("name", "").endswith(".monitor")]
        return items

    def _default(self, kind):
        try:
            return subprocess.run(["pactl", f"get-default-{kind}"], text=True,
                                  capture_output=True, timeout=5).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return ""

    @staticmethod
    def _percent(item):
        volume = item.get("volume") or {}
        values = [int(str(ch.get("value_percent", "0")).rstrip("%") or 0)
                  for ch in volume.values()]
        return max(values) if values else 0

    def refresh(self):
        sinks, sources = self._list("sinks"), self._list("sources")
        dsink, dsource = self._default("sink"), self._default("source")
        signature = (tuple(s["name"] for s in sinks), tuple(s["name"] for s in sources), dsink, dsource)
        if signature == self.signature:
            # Same devices: only follow volume/mute changes made elsewhere.
            for item, kind in [(s, "sink") for s in sinks] + [(s, "source") for s in sources]:
                widgets = self.groups.get(("vol", kind))
                if widgets and item["name"] == (dsink if kind == "sink" else dsource):
                    scale, mute = widgets
                    if not scale.has_focus() and abs(scale.get_value() - self._percent(item)) > 1:
                        scale.set_value(self._percent(item))
                    if mute.get_active() != bool(item.get("mute")):
                        mute.set_active(bool(item.get("mute")))
            return
        self.signature = signature
        for key in ("sink", "source"):
            if key in self.groups:
                self.page.remove(self.groups.pop(key))
        self.groups["sink"] = self._group("Output", "sink", sinks, dsink,
                                          "audio-speakers-symbolic", "No output device")
        self.groups["source"] = self._group("Input", "source", sources, dsource,
                                            "audio-input-microphone-symbolic", "No microphone")
        self.page.add(self.groups["sink"])
        self.page.add(self.groups["source"])

    def _group(self, title, kind, items, default, icon, empty):
        group = Adw.PreferencesGroup(title=title)
        if not items:
            group.add(Adw.ActionRow(title=empty))
            return group
        current = next((i for i in items if i["name"] == default), items[0])

        row = Adw.ActionRow(title="Volume")
        row.add_prefix(Gtk.Image.new_from_icon_name(icon))
        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 150, 5)
        scale.set_hexpand(True)
        scale.set_size_request(260, -1)
        scale.set_valign(Gtk.Align.CENTER)
        scale.add_mark(100, Gtk.PositionType.BOTTOM, None)
        scale.set_value(self._percent(current))
        scale.connect("value-changed", lambda s: run(
            ["pactl", f"set-{kind}-volume", f"@DEFAULT_{kind.upper()}@", f"{int(s.get_value())}%"]))
        row.add_suffix(scale)
        mute = Gtk.ToggleButton(icon_name="audio-volume-muted-symbolic", valign=Gtk.Align.CENTER,
                                tooltip_text="Mute")
        mute.set_active(bool(current.get("mute")))
        mute.connect("toggled", lambda b: run(
            ["pactl", f"set-{kind}-mute", f"@DEFAULT_{kind.upper()}@", "1" if b.get_active() else "0"]))
        row.add_suffix(mute)
        group.add(row)
        self.groups[("vol", kind)] = (scale, mute)

        for item in items:
            choice = Adw.ActionRow(title=GLib.markup_escape_text(item.get("description") or item["name"]))
            if item["name"] == default:
                check = Gtk.Image.new_from_icon_name("object-select-symbolic")
                check.add_css_class("accent")
                choice.add_suffix(check)
            else:
                choice.set_activatable(True)
                choice.connect("activated", lambda _r, n=item["name"]: run(
                    ["pactl", f"set-default-{kind}", n],
                    lambda rc, out, err: self._after_switch(rc, err)))
            group.add(choice)
        return group

    def _after_switch(self, rc, err):
        if rc != 0:
            self.toast(err.strip() or "Could not switch the device")
        self.signature = None
        self.refresh()


# ---------------------------------------------------------------- Display


KANSHI = os.path.expanduser("~/.config/kanshi/config")
SCALES = (1.0, 1.25, 1.5, 1.75, 2.0)


class DisplayPanel(Panel):
    """Resolution, refresh rate and scale of each screen, through sway.

    A change applies at once and is written to kanshi's config (kanshi runs in
    the console's sway session), so it is also what the next session uses.
    Game mode sets its own resolution through gamescope; this is the desktop.
    """

    def __init__(self, parent):
        super().__init__(parent, "Display", height=560)
        outputs = run_json(["swaymsg", "-r", "-t", "get_outputs"]) or []
        outputs = [o for o in outputs if o.get("active")]
        if not outputs:
            self.unavailable("video-display-symbolic", "No screens found",
                             "Display settings work in the console's desktop mode. "
                             "In game mode, Steam sets the resolution.")
            return
        self.settings = {}
        for output in outputs:
            self.page.add(self._output_group(output))

    @staticmethod
    def _mode_label(mode):
        return f"{mode['width']} × {mode['height']} · {mode['refresh'] / 1000:.0f} Hz"

    def _output_group(self, output):
        name = output["name"]
        title = " ".join(x for x in (output.get("make"), output.get("model")) if x and x != "Unknown") or name
        group = Adw.PreferencesGroup(title=GLib.markup_escape_text(title), description=name)

        modes = []
        for mode in output.get("modes", []):
            if mode not in modes:
                modes.append(mode)
        modes.sort(key=lambda m: (-m["width"] * m["height"], -m["refresh"]))
        current = output.get("current_mode") or (modes[0] if modes else None)
        mode_row = Adw.ComboRow(title="Resolution",
                                model=Gtk.StringList.new([self._mode_label(m) for m in modes]))
        if current in modes:
            mode_row.set_selected(modes.index(current))
        group.add(mode_row)

        scale = float(output.get("scale") or 1.0)
        scale_row = Adw.ComboRow(title="Scale",
                                 model=Gtk.StringList.new([f"{int(s * 100)} %" for s in SCALES]))
        scale_row.set_selected(min(range(len(SCALES)), key=lambda i: abs(SCALES[i] - scale)))
        group.add(scale_row)

        self.settings[name] = {"mode": current, "scale": scale}

        def apply(*_):
            mode = modes[mode_row.get_selected()] if modes else None
            new_scale = SCALES[scale_row.get_selected()]
            self.settings[name] = {"mode": mode, "scale": new_scale}
            argv = ["swaymsg", "output", name, "scale", str(new_scale)]
            if mode:
                argv[3:3] = ["mode", f"{mode['width']}x{mode['height']}@{mode['refresh'] / 1000:.3f}Hz"]
            run(argv, lambda rc, out, err: self._applied(rc, out, err))

        mode_row.connect("notify::selected", apply)
        scale_row.connect("notify::selected", apply)
        return group

    def _applied(self, rc, out, err):
        if rc != 0:
            self.toast((err or out).strip() or "The screen refused that setting")
            return
        try:
            os.makedirs(os.path.dirname(KANSHI), exist_ok=True)
            lines = ["# Written by the Shani Console's Display settings.", "profile shani-console {"]
            for name, s in self.settings.items():
                mode = s["mode"]
                spec = f"  output {name} enable scale {s['scale']}"
                if mode:
                    spec += f" mode {mode['width']}x{mode['height']}@{mode['refresh'] / 1000:.3f}Hz"
                lines.append(spec)
            lines.append("}")
            with open(KANSHI, "w", encoding="utf-8") as fh:
                fh.write("\n".join(lines) + "\n")
            self.toast("Saved")
        except OSError as exc:
            self.toast(f"Applied, but not saved: {exc}")
