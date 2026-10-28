#!/usr/bin/env python3
"""org.freedesktop.FileManager1 implemented with yazi.

D-Bus starts this (see ~/.local/share/dbus-1/services/org.freedesktop.FileManager1.service)
when an app asks the session's file manager to show a file: Chrome's
"Show in folder", xdg-desktop-portal's OpenDirectory, Telegram, Slack, ...
It opens yazi in alacritty on the file's folder with the file hovered, and
exits after a minute without requests; D-Bus starts it again on the next one.
"""

import os
import sys
from urllib.parse import urlparse

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BUS_NAME = "org.freedesktop.FileManager1"
OBJECT_PATH = "/org/freedesktop/FileManager1"
IDLE_SECONDS = 60

INTROSPECTION = """
<node>
  <interface name="org.freedesktop.FileManager1">
    <method name="ShowFolders">
      <arg type="as" name="URIs" direction="in"/>
      <arg type="s" name="StartupId" direction="in"/>
    </method>
    <method name="ShowItems">
      <arg type="as" name="URIs" direction="in"/>
      <arg type="s" name="StartupId" direction="in"/>
    </method>
    <method name="ShowItemProperties">
      <arg type="as" name="URIs" direction="in"/>
      <arg type="s" name="StartupId" direction="in"/>
    </method>
  </interface>
</node>
"""

# dbus-daemon starts this with its own activation environment, which gets the
# PATH from ~/.config/environment.d (with ~/.local/bin, where setup.sh installs
# yazi) only at login; make sure yazi is found regardless.
os.environ["PATH"] = ":".join(
    [os.path.expanduser("~/.local/bin"), "/usr/local/bin", os.environ.get("PATH", "/usr/bin:/bin")]
)

loop = GLib.MainLoop()
idle_timer = None


def on_idle():
    global idle_timer
    idle_timer = None  # this source is gone once it has fired
    loop.quit()
    return GLib.SOURCE_REMOVE


def reset_idle_timer():
    global idle_timer
    if idle_timer is not None:
        GLib.source_remove(idle_timer)
    idle_timer = GLib.timeout_add_seconds(IDLE_SECONDS, on_idle)


def to_uri(item):
    """file:// URI as is, a plain path (some apps send those) as a file:// URI,
    None for other schemes: nothing local to show."""
    scheme = urlparse(item).scheme
    if scheme == "file":
        return item
    if not scheme:
        return Gio.File.new_for_path(item).get_uri()
    return None


def on_method_call(_conn, _sender, _path, _iface, _method, params, invocation):
    # Always answer: an unanswered call keeps the app waiting for the D-Bus
    # timeout. On an error the app falls back to opening the parent folder.
    items = params.unpack()[0]
    uris = [u for u in (to_uri(i) for i in items) if u]
    try:
        if items and not uris:
            raise ValueError(f"nothing local to show in {items}")
        # yazi can hover one entry, so one window on the first item is what we
        # show. Launched through yazi.desktop (the inode/directory handler), so
        # the terminal command line lives in one place.
        if uris:
            app = Gio.DesktopAppInfo.new("yazi.desktop")
            if app is None:
                raise RuntimeError("yazi.desktop not found")
            app.launch_uris([uris[0]], None)
    except Exception as e:  # noqa: BLE001 - whatever failed, reply
        print(f"filemanager1-yazi: {e}", file=sys.stderr, flush=True)
        invocation.return_dbus_error("org.freedesktop.DBus.Error.Failed", str(e))
    else:
        invocation.return_value(None)
    reset_idle_timer()


def on_bus_acquired(conn, _name):
    node = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION)
    conn.register_object(OBJECT_PATH, node.interfaces[0], on_method_call, None, None)


def on_name_lost(_conn, _name):
    loop.quit()


Gio.bus_own_name(
    Gio.BusType.SESSION, BUS_NAME, Gio.BusNameOwnerFlags.NONE, on_bus_acquired, None, on_name_lost
)
reset_idle_timer()
loop.run()
