#!/usr/bin/env python3
"""
Gamebian: listen for gamepad hotkeys and show a fullscreen quick-launcher.
Reads USB / Bluetooth controllers through evdev (no exclusive grab).
"""
from __future__ import annotations

import configparser
import os
import re
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

# Matches gamebian-installed GTK (black / white-grey); live session uses blue accent variant.
THEME_INSTALLED = {
    "window": "#0d0d0d",
    "panel": "#151515",
    "list_bg": "#202020",
    "list_fg": "#ebebeb",
    "select_bg": "#3a3a3a",
    "select_fg": "#ffffff",
    "title": "#ffffff",
    "subtitle": "#a8a8a8",
    "hint": "#888888",
    "border": "#2a2a2a",
}
THEME_LIVE = {
    "window": "#0a1628",
    "panel": "#141428",
    "list_bg": "#1a1a2e",
    "list_fg": "#eaeaea",
    "select_bg": "#3d5a80",
    "select_fg": "#ffffff",
    "title": "#ffffff",
    "subtitle": "#a8b2d1",
    "hint": "#8892b0",
    "border": "#2a3a5c",
}
ICON_CANDIDATES_INSTALLED = (
    "/usr/share/pixmaps/menu-icon-default.png",
    "/usr/share/gamebian/controller-menu-icon.png",
    "/usr/share/pixmaps/menu-icon.png",
)
ICON_CANDIDATES_LIVE = (
    "/usr/share/pixmaps/menu-icon.png",
    "/usr/share/pixmaps/menu-icon-default.png",
    "/usr/share/gamebian/controller-menu-icon.png",
)
DESKTOP_DIRS = (
    Path("/usr/share/applications"),
    Path("/usr/local/share/applications"),
    Path.home() / ".local/share/applications",
)
ICON_THEME_DIRS = (Path("/usr/share/icons"), Path.home() / ".icons")
ICON_SIZE_DIRS = ("48x48", "32x32", "64x64", "24x24", "22x22", "16x16")
ICON_SUBDIRS = ("apps", "places", "devices", "mimetypes", "status", "actions", "categories")
# Fallback Papirus / Freedesktop names when .desktop lookup fails.
PROGRAM_ICON_HINTS: dict[str, str] = {
    "steam": "steam",
    "files": "thunar",
    "terminal": "utilities-terminal",
    "applications": "view-grid",
    "browser": "web-browser",
}
COMMAND_ICON_HINTS: dict[str, str] = {
    "steam": "steam",
    "gamebian-enter-steam-kiosk-session": "steam",
    "thunar": "thunar",
    "xfce4-terminal": "utilities-terminal",
    "rofi": "view-grid",
    "x-www-browser": "web-browser",
    "epiphany": "epiphany",
    "firefox": "firefox",
}


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
    if not cfg.has_section("ui"):
        cfg.add_section("ui")
    return cfg


def _boot_live() -> bool:
    try:
        with open("/proc/cmdline", encoding="utf-8") as f:
            return "boot=live" in f.read()
    except OSError:
        return False


def theme_from_config(cfg: configparser.ConfigParser) -> dict[str, str]:
    mode = cfg.get("ui", "theme", fallback="auto").strip().lower()
    if mode in ("installed", "mono", "monochrome", "bw", "blackwhite"):
        return dict(THEME_INSTALLED)
    if mode in ("live", "blue"):
        return dict(THEME_LIVE)
    if _boot_live():
        return dict(THEME_LIVE)
    return dict(THEME_INSTALLED)


def resolve_menu_icon(cfg: configparser.ConfigParser) -> Path | None:
    custom = cfg.get("ui", "icon", fallback="auto").strip()
    if custom and custom.lower() != "auto":
        p = Path(custom).expanduser()
        if p.is_file():
            return p
    candidates = ICON_CANDIDATES_LIVE if _boot_live() else ICON_CANDIDATES_INSTALLED
    icon_mode = cfg.get("ui", "icon", fallback="auto").strip().lower()
    if icon_mode == "live":
        candidates = ICON_CANDIDATES_LIVE
    elif icon_mode in ("installed", "default", "mono"):
        candidates = ICON_CANDIDATES_INSTALLED
    for path in candidates:
        if Path(path).is_file():
            return Path(path)
    return None


def _icon_theme_name() -> str:
    return (
        os.environ.get("GTK_ICON_THEME", "").strip()
        or os.environ.get("XDG_ICON_THEME", "").strip()
        or "Papirus"
    )


def resolve_icon_file(icon_name: str) -> Path | None:
    """Resolve an icon theme name or absolute path to a PNG/XPM file."""
    if not icon_name or icon_name.lower() in ("none", "false", "0"):
        return None
    raw = icon_name.strip()
    if "/" in raw or raw.startswith("."):
        p = Path(raw).expanduser()
        if p.is_file():
            return p
    names = [raw, raw.lower(), raw.replace("-", "_")]
    themes = [_icon_theme_name(), "Papirus", "Adwaita", "hicolor"]
    seen: set[str] = set()
    for name in names:
        if not name or name in seen:
            continue
        seen.add(name)
        for base in (Path("/usr/share/pixmaps"),):
            for ext in ("png", "xpm", "PNG"):
                p = base / f"{name}.{ext}"
                if p.is_file():
                    return p
        for theme in themes:
            if not theme:
                continue
            for icon_root in ICON_THEME_DIRS:
                root = icon_root / theme
                if not root.is_dir():
                    continue
                for size in ICON_SIZE_DIRS:
                    for sub in ICON_SUBDIRS:
                        for ext in ("png", "xpm"):
                            p = root / size / sub / f"{name}.{ext}"
                            if p.is_file():
                                return p
    return None


def _exec_binary(exec_line: str) -> str:
    clean = re.sub(r"%[fFuUdDnNickvm]", "", exec_line).strip()
    if not clean:
        return ""
    return Path(clean.split()[0]).name


def _parse_desktop_icon(path: Path) -> tuple[str | None, str | None, str | None]:
    icon = exec_line = name = None
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None, None, None
    for line in text.splitlines():
        if line.startswith("Icon="):
            icon = line.split("=", 1)[1].strip()
        elif line.startswith("Exec=") and exec_line is None:
            exec_line = line.split("=", 1)[1].strip()
        elif line.startswith("Name=") and name is None:
            name = line.split("=", 1)[1].strip()
    return icon, exec_line, name


def icon_name_from_desktop(binary: str, label: str) -> str | None:
    binary = Path(binary).name
    label_l = label.strip().lower()
    for desk_dir in DESKTOP_DIRS:
        if not desk_dir.is_dir():
            continue
        try:
            entries = sorted(desk_dir.glob("*.desktop"))
        except OSError:
            continue
        for desk in entries:
            icon, exec_line, name = _parse_desktop_icon(desk)
            if not icon:
                continue
            exe_bin = _exec_binary(exec_line or "")
            if binary and exe_bin == binary:
                return icon
            if name and name.strip().lower() == label_l:
                return icon
    return None


def resolve_program_icon(
    label: str,
    command: str,
    cfg: configparser.ConfigParser,
    icon_override: str | None = None,
) -> Path | None:
    icon_name = icon_override
    if not icon_name and cfg.has_section("icons") and cfg.has_option("icons", label):
        icon_name = cfg.get("icons", label, fallback="").strip()
    binary = _exec_binary(command)
    if not icon_name:
        icon_name = COMMAND_ICON_HINTS.get(binary) or PROGRAM_ICON_HINTS.get(label.strip().lower())
    if not icon_name:
        icon_name = icon_name_from_desktop(binary, label)
    if not icon_name:
        return None
    return resolve_icon_file(icon_name)


def load_tk_icon(path: Path | None, max_px: int = 96) -> tk.PhotoImage | None:
    if path is None:
        return None
    try:
        img = tk.PhotoImage(file=str(path))
    except tk.TclError:
        return None
    w, h = img.width(), img.height()
    if w <= 0 or h <= 0:
        return img
    factor = max((w + max_px - 1) // max_px, (h + max_px - 1) // max_px, 1)
    if factor > 1:
        img = img.subsample(factor, factor)
    return img


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


def steam_is_running() -> bool:
    """True if the Steam client process is active for this user (desktop or Big Picture)."""
    uid = os.getuid()
    try:
        proc = subprocess.run(
            ["pgrep", "-u", str(uid), "-x", "steam"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
        )
        return proc.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def in_exclusive_gamescope_kiosk() -> bool:
    """True when fullscreen gamescope is active without Openbox (Steam kiosk session)."""
    uid = os.getuid()
    try:
        gs = subprocess.run(
            ["pgrep", "-u", str(uid), "-x", "gamescope"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
        )
        ob = subprocess.run(
            ["pgrep", "-u", str(uid), "-x", "openbox"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
        )
        return gs.returncode == 0 and ob.returncode != 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def _launch_env() -> dict[str, str]:
    env = os.environ.copy()
    env.setdefault("DISPLAY", ":0")
    xauth = Path.home() / ".Xauthority"
    if xauth.is_file():
        env.setdefault("XAUTHORITY", str(xauth))
    return env


def notify_user(summary: str, body: str = "") -> None:
    args = ["notify-send", "-a", "Gamebian", summary]
    if body:
        args.append(body)
    try:
        subprocess.Popen(
            args,
            env=_launch_env(),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        pass


def is_steam_menu_entry(label: str, command: str) -> bool:
    if label.strip().lower() == "steam":
        return True
    cmd_l = command.lower()
    return "enter-steam-kiosk" in cmd_l or "gamebian-steam-bigpicture" in cmd_l


def programs_from_config(
    cfg: configparser.ConfigParser,
) -> list[tuple[str, str, Path | None]]:
    if not cfg.has_section("programs"):
        return []
    out: list[tuple[str, str, Path | None]] = []
    for label in cfg.options("programs"):
        cmd = cfg.get("programs", label, fallback="").strip()
        if not cmd:
            continue
        icon_path = resolve_program_icon(label, cmd, cfg)
        out.append((label, cmd, icon_path))
    return out


class MenuApp:
    def __init__(
        self,
        items: list[tuple[str, str, Path | None]],
        devices: dict[str, evdev.InputDevice],
        theme: dict[str, str],
        icon_path: Path | None,
        title: str,
    ) -> None:
        self.items = items
        self.devices = devices
        self._theme = theme
        self._selected = 0
        self._row_frames: list[tk.Frame] = []
        self._row_text_labels: list[tk.Label] = []
        self._item_photos: list[tk.PhotoImage | None] = []
        self._logo_photo: tk.PhotoImage | None = None
        self.root = tk.Tk()
        self.root.title(title)
        self.root.configure(bg=theme["window"])
        self.root.attributes("-fullscreen", True)
        self.root.lift()
        self.root.focus_force()
        self.root.bind("<Escape>", lambda e: self.dismiss())
        self.root.bind("<Return>", lambda e: self.activate())
        self.root.bind("<Up>", lambda e: self.move(-1))
        self.root.bind("<Down>", lambda e: self.move(1))

        header = tk.Frame(self.root, bg=theme["panel"], highlightthickness=1, highlightbackground=theme["border"])
        header.pack(fill=tk.X, padx=32, pady=(28, 12))

        icon_frame = tk.Frame(header, bg=theme["panel"])
        icon_frame.pack(side=tk.LEFT, padx=(20, 16), pady=16)
        if icon_path is not None:
            self._logo_photo = load_tk_icon(icon_path)
            if self._logo_photo is not None:
                tk.Label(icon_frame, image=self._logo_photo, bg=theme["panel"]).pack()
                try:
                    self.root.iconphoto(True, self._logo_photo)
                except tk.TclError:
                    pass

        title_col = tk.Frame(header, bg=theme["panel"])
        title_col.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, pady=16)
        tk.Label(
            title_col,
            text=title,
            fg=theme["title"],
            bg=theme["panel"],
            font=("Sans", 26, "bold"),
            anchor="w",
        ).pack(fill=tk.X)
        tk.Label(
            title_col,
            text="Quick launch — Guide / Mode, or Select+Start",
            fg=theme["subtitle"],
            bg=theme["panel"],
            font=("Sans", 14),
            anchor="w",
        ).pack(fill=tk.X, pady=(4, 0))

        list_wrap = tk.Frame(
            self.root,
            bg=theme["list_bg"],
            highlightthickness=1,
            highlightbackground=theme["border"],
        )
        list_wrap.pack(fill=tk.BOTH, expand=True, padx=48, pady=8)

        list_inner = tk.Frame(list_wrap, bg=theme["list_bg"])
        list_inner.pack(fill=tk.BOTH, expand=True, padx=4, pady=4)

        for label, _cmd, item_icon in items:
            row = tk.Frame(list_inner, bg=theme["list_bg"])
            row.pack(fill=tk.X, pady=3)
            photo = load_tk_icon(item_icon, max_px=40)
            self._item_photos.append(photo)
            if photo is not None:
                tk.Label(row, image=photo, bg=theme["list_bg"]).pack(
                    side=tk.LEFT, padx=(16, 10), pady=10
                )
            else:
                tk.Label(row, text="▪", bg=theme["list_bg"], fg=theme["hint"], font=("Sans", 18)).pack(
                    side=tk.LEFT, padx=(20, 14), pady=10
                )
            text_lbl = tk.Label(
                row,
                text=label,
                font=("Sans", 22),
                anchor="w",
                bg=theme["list_bg"],
                fg=theme["list_fg"],
            )
            text_lbl.pack(side=tk.LEFT, fill=tk.X, expand=True, pady=10, padx=(0, 16))
            self._row_frames.append(row)
            self._row_text_labels.append(text_lbl)

        self._paint_selection()
        self.root.focus_set()

        tk.Label(
            self.root,
            text="D-pad: navigate   A / Start: launch   B / Guide: close",
            fg=theme["hint"],
            bg=theme["window"],
            font=("Sans", 14),
        ).pack(pady=(8, 28))

        self._hat_repeat_at = 0.0
        self.root.after(16, self._poll_evdev)

    def _paint_selection(self) -> None:
        t = self._theme
        for i, (row, text_lbl) in enumerate(zip(self._row_frames, self._row_text_labels)):
            sel = i == self._selected
            bg = t["select_bg"] if sel else t["list_bg"]
            fg = t["select_fg"] if sel else t["list_fg"]
            row.configure(bg=bg)
            text_lbl.configure(bg=bg, fg=fg)
            for child in row.winfo_children():
                if child is text_lbl:
                    continue
                try:
                    child.configure(bg=bg)
                except tk.TclError:
                    pass

    def move(self, delta: int) -> None:
        if not self.items:
            return
        self._selected = (self._selected + delta) % len(self.items)
        self._paint_selection()

    def activate(self) -> None:
        if not self.items:
            return
        label, cmd, _icon = self.items[self._selected]
        self.dismiss()
        if is_steam_menu_entry(label, cmd) and in_exclusive_gamescope_kiosk():
            notify_user("Please Wait", "Steam will not load in gamescope session")
            return
        launch_env = _launch_env()
        log_dir = Path.home() / ".cache" / "gamebian"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_file = log_dir / "controller-launch.log"
        with open(log_file, "a", encoding="utf-8") as logfh:
            logfh.write(f"\n--- launch {label!r}: {cmd}\n")
            subprocess.Popen(
                ["/bin/sh", "-c", cmd],
                start_new_session=True,
                env=launch_env,
                stdout=logfh,
                stderr=subprocess.STDOUT,
            )

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
            skip_if_steam = cfg.getboolean(
                "trigger",
                "skip_when_steam_running",
                fallback=True,
            )
            if not skip_if_steam or not steam_is_running():
                ui_theme = theme_from_config(cfg)
                ui_icon = resolve_menu_icon(cfg)
                ui_title = cfg.get("ui", "title", fallback="Gamebian").strip() or "Gamebian"
                MenuApp(items, opened, ui_theme, ui_icon, ui_title).root.mainloop()
            trigger = TriggerState(cfg.get("trigger", "mode", fallback="guide"))


if __name__ == "__main__":
    run()
