#!/usr/bin/env python3
"""
Gamebian: listen for gamepad hotkeys and show a fullscreen quick-launcher.
Reads USB / Bluetooth controllers through evdev (no exclusive grab).
"""
from __future__ import annotations

import configparser
import os
import select
import subprocess
import sys
import time
from pathlib import Path

try:
    import evdev
    from evdev import ecodes
except ImportError:
    print("gamebian-controller-menu: install python3-evdev", file=sys.stderr)
    sys.exit(1)

try:
    import tkinter as tk
except ImportError:
    print("gamebian-controller-menu: install python3-tk", file=sys.stderr)
    sys.exit(1)


def _config_paths() -> list[Path]:
    """Read system defaults first; user file overrides (configparser.read order)."""
    xdg = os.environ.get("XDG_CONFIG_HOME", "").strip()
    user_base = Path(xdg) if xdg else (Path.home() / ".config")
    return [
        Path("/etc/gamebian/controller-menu.ini"),
        user_base / "gamebian" / "controller-menu.ini",
    ]


def load_config() -> configparser.ConfigParser:
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.optionxform = str
    cfg.read([str(p) for p in _config_paths() if p.is_file()])
    if not cfg.has_section("trigger"):
        cfg.add_section("trigger")
    if not cfg.has_option("trigger", "mode"):
        cfg.set("trigger", "mode", "guide")
    if not cfg.has_section("programs"):
        cfg.add_section("programs")
    return cfg


def _is_joystick_capabilities(dev: evdev.InputDevice) -> bool:
    caps = dev.capabilities()
    keys = caps.get(evdev.ecodes.EV_KEY, [])
    if not keys:
        return False
    gamepad_markers = (
        ecodes.BTN_GAMEPAD,
        ecodes.BTN_JOYSTICK,
        ecodes.BTN_SOUTH,
        ecodes.BTN_EAST,
        ecodes.BTN_START,
    )
    return any(k in keys for k in gamepad_markers)


def discover_devices(opened: dict[str, evdev.InputDevice]) -> None:
    for path in evdev.list_devices():
        if path in opened:
            continue
        try:
            dev = evdev.InputDevice(path)
        except OSError:
            continue
        if not _is_joystick_capabilities(dev):
            dev.close()
            continue
        try:
            dev.nonblocking = True
        except OSError:
            dev.close()
            continue
        opened[path] = dev


def close_removed(opened: dict[str, evdev.InputDevice]) -> None:
    dead = [p for p in opened if not os.path.exists(p)]
    for p in dead:
        try:
            opened.pop(p, None).close()
        except OSError:
            pass


class TriggerState:
    def __init__(self, mode: str) -> None:
        self.mode = (mode or "guide").strip().lower()
        self.select_down = False
        self.start_down = False
        self._last_fire = 0.0

    def reset_combo(self) -> None:
        self.select_down = False
        self.start_down = False

    def _debounced(self) -> bool:
        now = time.monotonic()
        if now - self._last_fire < 0.65:
            return False
        self._last_fire = now
        return True

    def process(self, event: evdev.InputEvent) -> bool:
        """Return True if the menu should open."""
        if event.type != ecodes.EV_KEY:
            return False
        key = event.code
        val = event.value

        if self.mode == "select_start":
            if key == ecodes.BTN_SELECT:
                if val == 1:
                    self.select_down = True
                    if self.start_down and self._debounced():
                        self.reset_combo()
                        return True
                else:
                    self.select_down = False
                return False
            if key == ecodes.BTN_START:
                if val == 1:
                    self.start_down = True
                    if self.select_down and self._debounced():
                        self.reset_combo()
                        return True
                else:
                    self.start_down = False
                return False
            return False

        guide_keys = (ecodes.BTN_MODE, ecodes.KEY_HOMEPAGE)
        if key in guide_keys and val == 1 and self._debounced():
            self.reset_combo()
            return True
        return False


def programs_from_config(cfg: configparser.ConfigParser) -> list[tuple[str, str]]:
    if not cfg.has_section("programs"):
        return []
    out: list[tuple[str, str]] = []
    for label in cfg.options("programs"):
        cmd = cfg.get("programs", label, fallback="").strip()
        if cmd:
            out.append((label, cmd))
    return out


class MenuApp:
    def __init__(self, items: list[tuple[str, str]], devices: dict[str, evdev.InputDevice]) -> None:
        self.items = items
        self.devices = devices
        self.root = tk.Tk()
        self.root.title("Gamebian")
        self.root.configure(bg="#141428")
        self.root.attributes("-fullscreen", True)
        self.root.lift()
        self.root.focus_force()
        self.root.bind("<Escape>", lambda e: self.dismiss())
        self.root.bind("<Return>", lambda e: self.activate())
        self.root.bind("<Up>", lambda e: self.move(-1))
        self.root.bind("<Down>", lambda e: self.move(1))

        tk.Label(
            self.root,
            text="Quick launch (Guide / Mode, or Select+Start)",
            fg="#a8b2d1",
            bg="#141428",
            font=("Sans", 16),
        ).pack(pady=(24, 8))

        self.listbox = tk.Listbox(
            self.root,
            activestyle="dotbox",
            bg="#1a1a2e",
            fg="#eaeaea",
            selectbackground="#3d5a80",
            selectforeground="#ffffff",
            highlightthickness=0,
            borderwidth=0,
            font=("Sans", 22),
            height=min(16, max(4, len(items))),
        )
        self.listbox.pack(fill=tk.BOTH, expand=True, padx=48, pady=12)
        for label, _cmd in items:
            self.listbox.insert(tk.END, f"  {label}")
        self.listbox.selection_set(0)
        self.listbox.activate(0)
        self.listbox.focus_set()

        tk.Label(
            self.root,
            text="D-pad: navigate   A / Start: launch   B / Guide: close",
            fg="#8892b0",
            bg="#141428",
            font=("Sans", 14),
        ).pack(pady=(8, 24))

        self._hat_repeat_at = 0.0
        self.root.after(16, self._poll_evdev)

    def move(self, delta: int) -> None:
        if not self.items:
            return
        i = int(self.listbox.curselection()[0]) if self.listbox.curselection() else 0
        i = (i + delta) % len(self.items)
        self.listbox.selection_clear(0, tk.END)
        self.listbox.selection_set(i)
        self.listbox.activate(i)
        self.listbox.see(i)

    def activate(self) -> None:
        sel = self.listbox.curselection()
        if not sel:
            return
        _label, cmd = self.items[int(sel[0])]
        self.dismiss()
        subprocess.Popen(["/bin/sh", "-c", cmd], start_new_session=True)

    def dismiss(self) -> None:
        self.root.destroy()

    def _poll_evdev(self) -> None:
        if not self.root.winfo_exists():
            return
        for dev in list(self.devices.values()):
            try:
                for ev in dev.read():
                    self.handle_menu_evdev(ev)
            except OSError:
                pass
        self.root.after(16, self._poll_evdev)

    def handle_menu_evdev(self, event: evdev.InputEvent) -> None:
        if event.type == ecodes.EV_KEY and event.value == 1:
            if event.code == ecodes.BTN_SOUTH:
                self.activate()
            elif event.code in (ecodes.BTN_EAST, ecodes.BTN_MODE):
                self.dismiss()
            elif event.code == ecodes.BTN_START:
                self.activate()
            return
        if event.type != ecodes.EV_ABS:
            return
        if event.code not in (ecodes.ABS_HAT0X, ecodes.ABS_HAT0Y):
            return
        now = time.monotonic()
        if now < self._hat_repeat_at:
            return
        moved = False
        if event.code == ecodes.ABS_HAT0X:
            if event.value < 0:
                self.move(-1)
                moved = True
            elif event.value > 0:
                self.move(1)
                moved = True
        else:
            if event.value < 0:
                self.move(-1)
                moved = True
            elif event.value > 0:
                self.move(1)
                moved = True
        if moved:
            self._hat_repeat_at = now + 0.18


def run() -> None:
    cfg = load_config()
    items = programs_from_config(cfg)
    if not items:
        print(
            "gamebian-controller-menu: no [programs] in config; "
            "see /etc/gamebian/controller-menu.ini",
            file=sys.stderr,
        )

    trigger = TriggerState(cfg.get("trigger", "mode", fallback="guide"))
    opened: dict[str, evdev.InputDevice] = {}
    discover_devices(opened)

    while True:
        close_removed(opened)
        discover_devices(opened)
        fds = [d.fd for d in opened.values()]
        if not fds:
            time.sleep(0.75)
            continue
        try:
            readable, _, _ = select.select(fds, [], [], 0.5)
        except OSError:
            time.sleep(0.2)
            continue

        fired = False
        for dev in list(opened.values()):
            if dev.fd not in readable:
                continue
            try:
                for ev in dev.read():
                    if ev.type == ecodes.EV_SYN:
                        continue
                    if trigger.process(ev) and items:
                        fired = True
                        break
            except OSError:
                pass
            if fired:
                break

        if fired and items:
            MenuApp(items, opened).root.mainloop()
            trigger = TriggerState(cfg.get("trigger", "mode", fallback="guide"))


if __name__ == "__main__":
    run()
