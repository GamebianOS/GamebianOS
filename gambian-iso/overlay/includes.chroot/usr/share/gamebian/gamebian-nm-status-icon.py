#!/usr/bin/env python3
# GTK3 XEmbed status icon for NetworkManager (works in lxpanel's legacy tray).
# Qt6 nm-tray often shows white squares in lxpanel even when icon themes are correct.
from __future__ import annotations

import os
import shutil
import subprocess
import sys


def _require_gi():
    try:
        import gi

        gi.require_version("Gtk", "3.0")
        gi.require_version("NM", "1.0")
        from gi.repository import Gtk, NM

        return Gtk, NM
    except Exception as exc:  # pragma: no cover
        print(f"gamebian-nm-status-icon: need python3-gi + gir1.2-nm-1.0: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc


def _wifi_icon(strength: int) -> str:
    strength = max(0, min(100, int(strength)))
    if strength <= 0:
        return "network-wireless-signal-none"
    if strength <= 25:
        return "network-wireless-signal-weak"
    if strength <= 50:
        return "network-wireless-signal-ok"
    if strength <= 75:
        return "network-wireless-signal-good"
    return "network-wireless-signal-excellent"


def _icon_for_device(device, nm: type) -> str:
    dtype = device.get_device_type()
    if dtype == nm.DeviceType.ETHERNET:
        return "network-wired"
    if dtype == nm.DeviceType.WIFI:
        ap = device.get_active_access_point()
        if ap is not None:
            return _wifi_icon(ap.get_strength())
        return "network-wireless-signal-none"
    return "network-wired"


def _icon_for_client(client, nm: type) -> str:
    active = client.get_primary_connection()
    if active is None:
        return "network-offline"
    state = active.get_state()
    if state in (nm.ActiveConnectionState.DEACTIVATED, nm.ActiveConnectionState.DEACTIVATING):
        return "network-offline"
    if active.get_vpn():
        return "network-vpn"
    devices = active.get_devices()
    if not devices:
        return "network-offline"
    return _icon_for_device(devices[0], nm)


def main() -> None:
    Gtk, NM = _require_gi()

    os.environ.setdefault("DISPLAY", ":0")
    client = NM.Client.new(None)
    icon = Gtk.StatusIcon()
    icon.set_visible(True)

    def refresh(*_args) -> None:
        name = _icon_for_client(client, NM)
        icon.set_from_icon_name(name)
        active = client.get_primary_connection()
        if active is not None:
            icon.set_tooltip_text(active.get_id() or "Network")
        else:
            icon.set_tooltip_text("No network connection")

    def on_activate(_icon) -> None:
        for cmd in ("nm-connection-editor", "nm-tray"):
            if shutil.which(cmd):
                subprocess.Popen([cmd], start_new_session=True)
                return

    def watch_device(_client, device) -> None:
        try:
            device.connect("notify::state", refresh)
        except TypeError:
            pass
        refresh()

    icon.connect("activate", on_activate)
    client.connect("notify::primary-connection", refresh)
    client.connect("active-connection-added", refresh)
    client.connect("active-connection-removed", refresh)
    client.connect("device-added", watch_device)
    client.connect("device-removed", refresh)
    for device in client.get_devices():
        watch_device(client, device)
    refresh()
    Gtk.main()


if __name__ == "__main__":
    main()
