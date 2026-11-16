#!/usr/bin/env python3
"""A minimal org.bluez on the system bus: one adapter, three devices.

Enough of BlueZ's API for the Control Center's Bluetooth panel: the object
manager, Adapter1 (Powered, Discovering, Start/StopDiscovery, RemoveDevice),
Device1 (Name, Alias, Icon, Paired, Connected, Trusted, Pair, Connect,
Disconnect) and Battery1. Every method call is logged to /tmp/bluez-calls.
"""
from gi.repository import Gio, GLib

XML = """
<node>
 <interface name="org.freedesktop.DBus.ObjectManager">
  <method name="GetManagedObjects"><arg type="a{oa{sa{sv}}}" direction="out"/></method>
 </interface>
 <interface name="org.freedesktop.DBus.Properties">
  <method name="Get"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="out"/></method>
  <method name="Set"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="in"/></method>
 </interface>
 <interface name="org.bluez.Adapter1">
  <method name="StartDiscovery"/><method name="StopDiscovery"/>
  <method name="RemoveDevice"><arg type="o" direction="in"/></method>
 </interface>
 <interface name="org.bluez.Device1">
  <method name="Pair"/><method name="Connect"/><method name="Disconnect"/>
 </interface>
</node>"""

A = "/org/bluez/hci0"
objects = {
    A: {"org.bluez.Adapter1": {"Powered": True, "Discovering": False, "Alias": "console"}},
    A + "/dev_AA": {"org.bluez.Device1": {"Name": "Wireless Controller", "Alias": "Wireless Controller",
                                          "Icon": "input-gaming", "Paired": False, "Connected": False,
                                          "Trusted": False}},
    A + "/dev_BB": {"org.bluez.Device1": {"Name": "Headset", "Alias": "Arctis Headset",
                                          "Icon": "audio-headset", "Paired": True, "Connected": True,
                                          "Trusted": True},
                    "org.bluez.Battery1": {"Percentage": 80}},
    A + "/dev_CC": {"org.bluez.Device1": {"Paired": False, "Connected": False}},  # nameless advertiser
}
SIG = {"Powered": "b", "Discovering": "b", "Alias": "s", "Name": "s", "Icon": "s",
       "Paired": "b", "Connected": "b", "Trusted": "b", "Percentage": "y"}


def log(text):
    with open("/tmp/bluez-calls", "a") as fh:
        fh.write(text + "\n")


def variant(key, value):
    return GLib.Variant(SIG[key], value)


def managed():
    return GLib.Variant("(a{oa{sa{sv}}})", ({
        path: {iface: {k: variant(k, v) for k, v in props.items()} for iface, props in ifaces.items()}
        for path, ifaces in objects.items()},))


def call(conn, sender, path, iface, method, params, inv):
    args = params.unpack()
    log(f"{path} {iface}.{method} {args}")
    if method == "GetManagedObjects":
        inv.return_value(managed())
    elif method == "Get":
        props = objects.get(path, {}).get(args[0])
        if props is None or args[1] not in props:
            inv.return_dbus_error("org.freedesktop.DBus.Error.InvalidArgs", "No such property")
        else:
            inv.return_value(GLib.Variant("(v)", (variant(args[1], props[args[1]]),)))
    elif method == "Set":
        objects[path][args[0]][args[1]] = args[2]
        inv.return_value(None)
    elif method == "StartDiscovery":
        objects[A]["org.bluez.Adapter1"]["Discovering"] = True
        inv.return_value(None)
    elif method == "StopDiscovery":
        objects[A]["org.bluez.Adapter1"]["Discovering"] = False
        inv.return_value(None)
    elif method == "RemoveDevice":
        objects.pop(args[0], None)
        inv.return_value(None)
    elif method == "Pair":
        objects[path]["org.bluez.Device1"]["Paired"] = True
        inv.return_value(None)
    elif method == "Connect":
        objects[path]["org.bluez.Device1"]["Connected"] = True
        inv.return_value(None)
    elif method == "Disconnect":
        objects[path]["org.bluez.Device1"]["Connected"] = False
        inv.return_value(None)
    else:
        inv.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)


bus = Gio.bus_get_sync(Gio.BusType.SYSTEM)
node = Gio.DBusNodeInfo.new_for_xml(XML)


# Register every interface on every path the panel touches.
for path in ["/"] + list(objects):
    for info in node.interfaces:
        bus.register_object(path, info, call, None, None)
Gio.bus_own_name_on_connection(bus, "org.bluez", Gio.BusNameOwnerFlags.NONE, None, None)
print("fake bluez ready", flush=True)
GLib.MainLoop().run()
