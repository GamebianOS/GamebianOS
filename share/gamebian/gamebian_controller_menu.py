#!/usr/bin/env python3
"""
Gamebian: listen for gamepad hotkeys and show a fullscreen quick-launcher.
Reads USB / Bluetooth controllers through evdev (no exclusive grab).
"""
from __future__ import annotations

import configparser
import fcntl
import os
import re
import select
import shutil
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

# Branding accents — keep in sync with Build/share/gamebian/generate-color-themes.py PALETTE.
THEME_ACCENTS: dict[str, str] = {
    "green": "#0B441D",
    "yellow": "#F89917",
    "blue": "#021C4A",
    "red": "#9E1720",
    "black": "#1C1C24",
    "purple": "#340E39",
}

# GTK-derived presets (gamebian live / gamebian-installed skel themes).
_GTK_PRESET_GAMEBIAN: dict[str, str | bool] = {
    "bg": "#0145F2",
    "fg": "#FFFFFF",
    "base": "#0238C9",
    "hover": "#056EDB",
    "selected_bg": "#056EDB",
    "selected_fg": "#F9F8F4",
    "insensitive_fg": "#9EB4F0",
    "borders": "#0238C9",
    "header_bg": "#056EDB",
    "view_text": "#FFFFFF",
    "dark_ui": True,
}
_GTK_PRESET_GAMEBIAN_INSTALLED: dict[str, str | bool] = {
    "bg": "#151515",
    "fg": "#ebebeb",
    "base": "#202020",
    "hover": "#2d2d2d",
    "selected_bg": "#3a3a3a",
    "selected_fg": "#ffffff",
    "insensitive_fg": "#888888",
    "borders": "#2a2a2a",
    "header_bg": "#2d2d2d",
    "view_text": "#ebebeb",
    "dark_ui": True,
}
ICON_CANDIDATES_INSTALLED = (
    "/usr/share/gamebian/controller-menu-icon.png",
    str(Path.home() / ".local/share/gamebian/menu-icon-default.png"),
    "/usr/share/pixmaps/menu-icon-default.png",
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
THEME_COMMAND_PREFIX = "__gamebian_theme__:"
THEMES_SUBMENU_CMD = "__gamebian_themes_submenu__"
DESKTOP_THEME_FILE = Path.home() / ".config" / "gamebian" / "desktop-theme"
STEAM_KIOSK_CMD = "/usr/sbin/gamebian-enter-steam-kiosk-session"
STEAM_LOGINUSERS_CANDIDATES = (
    Path(".local/share/Steam/config/loginusers.vdf"),
    Path(".steam/debian-installation/config/loginusers.vdf"),
    Path(".steam/root/config/loginusers.vdf"),
)
THEME_ICON = "preferences-desktop-theme"
COLOR_THEME_IDS = frozenset({"green", "yellow", "blue", "red", "black", "purple"})
COLOR_THEME_ORDER = ("green", "yellow", "blue", "red", "purple", "black")
COLOR_THEME_LABELS = {
    "green": "Green",
    "yellow": "Yellow",
    "blue": "Blue",
    "red": "Red",
    "purple": "Purple",
    "black": "Black",
}
INSTALLED_WALLPAPER_DIR = Path("/usr/share/backgrounds/gamebian-installed")
# Fallback Papirus / Freedesktop names when .desktop lookup fails.
PROGRAM_ICON_HINTS: dict[str, str] = {
    "steam": "steam",
    "themes": "preferences-desktop-theme",
    "log out": "system-log-out",
    "logout": "system-log-out",
    "reboot": "system-reboot",
    "shut down": "system-shutdown",
    "shutdown": "system-shutdown",
}
COMMAND_ICON_HINTS: dict[str, str] = {
    "steam": "steam",
    "gamebian-enter-steam-kiosk-session": "steam",
    THEMES_SUBMENU_CMD: "preferences-desktop-theme",
    "gamebian-session-action": "system-shutdown",
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
    if not cfg.has_section("themes"):
        cfg.add_section("themes")
    return cfg


def _boot_live() -> bool:
    try:
        with open("/proc/cmdline", encoding="utf-8") as f:
            return "boot=live" in f.read()
    except OSError:
        return False


def _hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    h = hex_color.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def _rgb_to_hex(r: int, g: int, b: int) -> str:
    return f"#{max(0, min(255, r)):02x}{max(0, min(255, g)):02x}{max(0, min(255, b)):02x}"


def _darken(hex_color: str, factor: float) -> str:
    r, g, b = _hex_to_rgb(hex_color)
    return _rgb_to_hex(int(r * (1 - factor)), int(g * (1 - factor)), int(b * (1 - factor)))


def _lighten(hex_color: str, factor: float) -> str:
    r, g, b = _hex_to_rgb(hex_color)
    return _rgb_to_hex(
        int(r + (255 - r) * factor),
        int(g + (255 - g) * factor),
        int(b + (255 - b) * factor),
    )


def _luminance(hex_color: str) -> float:
    r, g, b = _hex_to_rgb(hex_color)
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255.0


def gtk_palette_for(theme_id: str) -> dict[str, str | bool]:
    """GTK color set for a theme id (mirrors generate-color-themes.py palette_for)."""
    if theme_id == "gamebian":
        return dict(_GTK_PRESET_GAMEBIAN)
    if theme_id in ("gamebian-installed", "installed", "mono"):
        return dict(_GTK_PRESET_GAMEBIAN_INSTALLED)
    accent = THEME_ACCENTS.get(theme_id, "#151515").lower()
    if theme_id == "black":
        return {
            "bg": accent,
            "fg": "#ebebeb",
            "base": _lighten(accent, 0.06),
            "hover": _lighten(accent, 0.12),
            "selected_bg": _lighten(accent, 0.18),
            "selected_fg": "#ffffff",
            "insensitive_fg": "#888888",
            "borders": _lighten(accent, 0.08),
            "header_bg": _darken(accent, 0.15),
            "view_text": "#ebebeb",
            "dark_ui": True,
        }
    lum = _luminance(accent)
    dark_ui = lum < 0.55 or theme_id == "purple"
    hover = _darken(accent, 0.12)
    borders = _darken(accent, 0.22)
    selected_bg = _lighten(accent, 0.08) if dark_ui else _darken(accent, 0.08)
    if theme_id == "yellow":
        fg = "#1a1a1a"
        base = "#fff8e6"
        selected_fg = "#1a1a1a"
        view_text = "#5a4200"
        insensitive_fg = "#6a5a30"
    else:
        fg = "#ffffff"
        base = "#f9f8f4" if lum > 0.4 else "#1e1e28"
        selected_fg = "#f9f8f4" if not dark_ui else "#ffffff"
        view_text = accent if lum > 0.4 else "#ebebeb"
        insensitive_fg = _lighten(accent, 0.45) if lum < 0.5 else _darken(accent, 0.35)
    return {
        "bg": accent,
        "fg": fg,
        "base": base,
        "hover": hover,
        "selected_bg": selected_bg,
        "selected_fg": selected_fg,
        "insensitive_fg": insensitive_fg,
        "borders": borders,
        "header_bg": hover,
        "view_text": view_text,
        "dark_ui": dark_ui,
    }


def menu_theme_from_gtk_palette(p: dict[str, str | bool]) -> dict[str, str]:
    """Map GTK palette keys to controller menu colors."""
    bg = str(p["bg"])
    dark = bool(p.get("dark_ui", True))
    base = str(p["base"])
    list_bg = base
    if dark and _luminance(base) > 0.55:
        list_bg = _darken(bg, 0.1)
    list_fg = str(p["view_text"]) if dark else str(p["fg"])
    accent = str(p["selected_bg"]) if dark else str(p["hover"])
    url_fg = "#ffffff" if _luminance(base) < 0.5 else "#1a1a1a"
    return {
        "window": _darken(bg, 0.08) if dark else bg,
        "panel": str(p["header_bg"]),
        "info_bg": base,
        "list_bg": list_bg,
        "list_fg": list_fg,
        "select_bg": str(p["selected_bg"]),
        "select_fg": str(p["selected_fg"]),
        "title": str(p["fg"]),
        "subtitle": str(p["insensitive_fg"]),
        "hint": str(p["insensitive_fg"]),
        "url_fg": url_fg,
        "accent": accent,
        "border": str(p["borders"]),
    }


def read_active_desktop_theme_id() -> str:
    """Theme id from ~/.config/gamebian/desktop-theme or gtk-3.0 settings."""
    if DESKTOP_THEME_FILE.is_file():
        try:
            tid = DESKTOP_THEME_FILE.read_text(encoding="utf-8").strip()
            if tid:
                return tid
        except OSError:
            pass
    gtk_ini = Path.home() / ".config" / "gtk-3.0" / "settings.ini"
    if gtk_ini.is_file():
        gtk_cfg = configparser.ConfigParser()
        try:
            gtk_cfg.read(gtk_ini, encoding="utf-8")
            if gtk_cfg.has_option("Settings", "gtk-theme-name"):
                tid = gtk_cfg.get("Settings", "gtk-theme-name", fallback="").strip()
                if tid:
                    return tid
        except OSError:
            pass
    if _boot_live():
        return "gamebian"
    return "gamebian-installed"


def menu_theme_for_id(theme_id: str) -> dict[str, str]:
    tid = (theme_id or "").strip().lower()
    if tid in ("live",):
        tid = "gamebian"
    if tid in ("installed", "mono", "monochrome", "bw", "blackwhite"):
        tid = "gamebian-installed"
    return menu_theme_from_gtk_palette(gtk_palette_for(tid))


def theme_from_config(cfg: configparser.ConfigParser) -> dict[str, str]:
    mode = cfg.get("ui", "theme", fallback="auto").strip().lower()
    if mode in ("installed", "mono", "monochrome", "bw", "blackwhite"):
        return menu_theme_for_id("gamebian-installed")
    if mode in ("live", "blue"):
        return menu_theme_for_id("gamebian")
    if mode in COLOR_THEME_IDS:
        return menu_theme_for_id(mode)
    if mode not in ("auto", ""):
        return menu_theme_for_id(mode)
    if _boot_live():
        return menu_theme_for_id("gamebian")
    return menu_theme_for_id(read_active_desktop_theme_id())


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
    elif icon_mode in ("mono", "default", "grey", "gray"):
        candidates = ICON_CANDIDATES_INSTALLED
    elif icon_mode in ("color", "blue", "live"):
        candidates = ICON_CANDIDATES_LIVE
    elif icon_mode == "installed":
        candidates = ICON_CANDIDATES_INSTALLED
    elif icon_mode == "auto" and not _boot_live():
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


def _tk_photo_from_path(path: Path) -> tk.PhotoImage | None:
    try:
        return tk.PhotoImage(file=str(path))
    except tk.TclError:
        return None


def load_tk_icon(path: Path | None, max_px: int = 96) -> tk.PhotoImage | None:
    if path is None or not path.is_file():
        return None
    img = _tk_photo_from_path(path)
    if img is None and shutil.which("convert"):
        tmp = Path.home() / ".cache/gamebian/menu-icon-resize.png"
        try:
            tmp.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(
                [
                    "convert",
                    str(path),
                    "-resize",
                    f"{max_px}x{max_px}>",
                    str(tmp),
                ],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            img = _tk_photo_from_path(tmp)
        except (OSError, subprocess.CalledProcessError):
            img = None
    if img is None:
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


def _is_trigger_capable_device(dev: evdev.InputDevice) -> bool:
    """Gamepads (Guide / Select+Start) and keyboards (Super / Home)."""
    caps = dev.capabilities()
    keys = caps.get(evdev.ecodes.EV_KEY, [])
    if not keys:
        return False
    if _is_joystick_capabilities(dev):
        return True
    keyboard_triggers = (
        ecodes.KEY_LEFTMETA,
        ecodes.KEY_RIGHTMETA,
        ecodes.KEY_HOMEPAGE,
    )
    return any(k in keys for k in keyboard_triggers)


def _theme_display_name(theme_dir: Path) -> str:
    idx = theme_dir / "index.theme"
    if idx.is_file():
        try:
            for line in idx.read_text(encoding="utf-8", errors="replace").splitlines():
                if line.startswith("Name="):
                    return line.split("=", 1)[1].strip()
        except OSError:
            pass
    return theme_dir.name.replace("-", " ").title()


def discover_user_themes() -> list[tuple[str, str]]:
    """GTK/Openbox theme ids under ~/.themes (from skel: gamebian, gamebian-installed)."""
    themes_dir = Path.home() / ".themes"
    if not themes_dir.is_dir():
        return []
    found: list[tuple[str, str]] = []
    for theme_dir in sorted(themes_dir.iterdir()):
        if not theme_dir.is_dir():
            continue
        theme_id = theme_dir.name
        if theme_id.startswith("."):
            continue
        has_gtk = (theme_dir / "gtk-3.0").is_dir() or (theme_dir / "gtk-2.0").is_dir()
        has_ob = (theme_dir / "openbox-3").is_dir()
        if not has_gtk and not has_ob:
            continue
        found.append((theme_id, _theme_display_name(theme_dir)))
    return found


def _icon_theme_for_gtk(theme_id: str) -> str:
    """Installed: Papirus (full NM tray names). Live: Papirus-Dark on blue branding."""
    if theme_id == "yellow":
        return "Papirus"
    if _boot_live():
        return "Papirus-Dark"
    return "Papirus"


def _write_gtk3_theme(theme_id: str, icon_theme: str | None = None) -> None:
    path = Path.home() / ".config" / "gtk-3.0" / "settings.ini"
    path.parent.mkdir(parents=True, exist_ok=True)
    cfg = configparser.ConfigParser()
    if path.is_file():
        cfg.read(path, encoding="utf-8")
    if not cfg.has_section("Settings"):
        cfg.add_section("Settings")
    cfg.set("Settings", "gtk-theme-name", theme_id)
    cfg.set("Settings", "gtk-icon-theme-name", icon_theme or _icon_theme_for_gtk(theme_id))
    with path.open("w", encoding="utf-8") as fh:
        cfg.write(fh)


def _write_gtk2_theme(theme_id: str, icon_theme: str | None = None) -> None:
    _icon = icon_theme or _icon_theme_for_gtk(theme_id)
    path = Path.home() / ".gtkrc-2.0"
    lines: list[str] = []
    if path.is_file():
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    out: list[str] = []
    theme_done = False
    icon_done = False
    for line in lines:
        if line.strip().startswith("gtk-theme-name"):
            out.append(f'gtk-theme-name = "{theme_id}"')
            theme_done = True
        elif line.strip().startswith("gtk-icon-theme-name"):
            out.append(f'gtk-icon-theme-name = "{_icon}"')
            icon_done = True
        else:
            out.append(line)
    if not theme_done:
        out.insert(0, f'gtk-theme-name = "{theme_id}"')
    if not icon_done:
        out.insert(0, f'gtk-icon-theme-name = "{_icon}"')
    path.write_text("\n".join(out) + "\n", encoding="utf-8")


def _write_openbox_theme(theme_id: str) -> None:
    rc = Path.home() / ".config" / "openbox" / "rc.xml"
    if not rc.is_file():
        return
    try:
        text = rc.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return
    new_text, n = re.subn(
        r"(<theme>\s*<name>)[^<]+(</name>)",
        rf"\g<1>{theme_id}\g<2>",
        text,
        count=1,
    )
    if n:
        rc.write_text(new_text, encoding="utf-8")


def _rofi_theme_name(theme_id: str) -> str:
    if theme_id == "gamebian":
        return "gamebian-live"
    if theme_id in COLOR_THEME_IDS:
        rofi_path = Path.home() / ".local" / "share" / "rofi" / "themes" / f"{theme_id}.rasi"
        if rofi_path.is_file():
            return theme_id
    return "gamebian"


def _wallpaper_path(theme_id: str) -> Path | None:
    if theme_id in COLOR_THEME_IDS:
        wall = INSTALLED_WALLPAPER_DIR / f"{theme_id}.png"
        if wall.is_file():
            return wall
    if theme_id == "black":
        for name in ("black.png", "background.png"):
            wall = INSTALLED_WALLPAPER_DIR / name
            if wall.is_file():
                return wall
    if theme_id == "gamebian-installed":
        for name in ("background.png", "black.png"):
            wall = INSTALLED_WALLPAPER_DIR / name
            if wall.is_file():
                return wall
    live = Path.home() / ".local" / "share" / "gamebian" / "background.png"
    if live.is_file():
        return live
    return None


def _write_rofi_theme(theme_id: str) -> None:
    rofi_cfg = Path.home() / ".config" / "rofi" / "config.rasi"
    rofi_cfg.parent.mkdir(parents=True, exist_ok=True)
    rofi_cfg.write_text(f'@theme "{_rofi_theme_name(theme_id)}"\n', encoding="utf-8")


def _write_qt6ct_icon_theme(icon_theme: str) -> None:
    """Qt6 nm-tray reads icon_theme from qt6ct (gtk3 platform theme alone → white squares)."""
    conf = Path.home() / ".config" / "qt6ct" / "qt6ct.conf"
    conf.parent.mkdir(parents=True, exist_ok=True)
    conf.write_text(
        "[Appearance]\n"
        f"icon_theme={icon_theme}\n"
        "style=gtk2\n"
        "standard_dialogs=default\n",
        encoding="utf-8",
    )


def _persist_desktop_theme(theme_id: str) -> None:
    DESKTOP_THEME_FILE.parent.mkdir(parents=True, exist_ok=True)
    DESKTOP_THEME_FILE.write_text(theme_id + "\n", encoding="utf-8")
    custom = Path.home() / ".config" / "gamebian" / "custom-wallpaper"
    try:
        custom.unlink(missing_ok=True)
    except OSError:
        pass


def _refresh_wallpaper(theme_id: str, env: dict[str, str]) -> None:
    wall = _wallpaper_path(theme_id)
    if wall is None or not wall.is_file():
        return
    try:
        subprocess.Popen(
            ["feh", "--no-fehbg", "--bg-fill", str(wall)],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        pass


def apply_desktop_theme(theme_id: str) -> None:
    """Apply ~/.themes/<id> to GTK, Openbox, wallpaper, and lxpanel."""
    theme_dir = Path.home() / ".themes" / theme_id
    if not theme_dir.is_dir():
        notify_user("Theme not found", theme_id)
        return
    env = _launch_env()
    env["GTK_THEME"] = theme_id
    _icon = _icon_theme_for_gtk(theme_id)
    _write_gtk3_theme(theme_id, _icon)
    _write_gtk2_theme(theme_id, _icon)
    _write_qt6ct_icon_theme(_icon)
    env["GTK_ICON_THEME"] = _icon
    env["XDG_ICON_THEME"] = _icon
    _write_openbox_theme(theme_id)
    _write_rofi_theme(theme_id)
    _persist_desktop_theme(theme_id)
    try:
        subprocess.run(
            ["openbox", "--reconfigure"],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=8,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass
    _refresh_wallpaper(theme_id, env)
    panel_apply = Path("/usr/share/gamebian/gamebian-lxpanel-apply-panel.sh")
    if panel_apply.is_file():
        try:
            subprocess.run(
                [str(panel_apply)],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=8,
            )
        except (OSError, subprocess.TimeoutExpired):
            pass
    try:
        subprocess.run(
            ["pkill", "-x", "lxpanel"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
        )
        subprocess.Popen(
            ["lxpanel"],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        if Path("/usr/share/gamebian/gamebian-lxpanel-tray.sh").is_file():
            subprocess.Popen(
                ["/usr/share/gamebian/gamebian-lxpanel-tray.sh"],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
    except OSError:
        pass
    notify_user("Theme applied", _theme_display_name(theme_dir))


def color_theme_submenu_items(cfg: configparser.ConfigParser) -> list[tuple[str, str, Path | None]]:
    if not cfg.getboolean("themes", "enabled", fallback=True):
        return []
    if _boot_live():
        return []
    themes_dir = Path.home() / ".themes"
    out: list[tuple[str, str, Path | None]] = []
    for theme_id in COLOR_THEME_ORDER:
        if theme_id not in COLOR_THEME_IDS:
            continue
        if not (themes_dir / theme_id).is_dir():
            continue
        preview = _wallpaper_path(theme_id)
        label = COLOR_THEME_LABELS.get(theme_id, theme_id.title())
        cmd = f"{THEME_COMMAND_PREFIX}{theme_id}"
        out.append((label, cmd, preview))
    return out


def is_themes_submenu_entry(label: str, command: str) -> bool:
    if command.strip() == THEMES_SUBMENU_CMD:
        return True
    return label.strip().lower() == "themes"


def discover_devices(opened: dict[str, evdev.InputDevice]) -> None:
    for path in evdev.list_devices():
        if path in opened:
            continue
        try:
            dev = evdev.InputDevice(path)
        except OSError:
            continue
        if not _is_trigger_capable_device(dev):
            dev.close()
            continue
        try:
            dev.nonblocking = True
        except OSError:
            dev.close()
            continue
        opened[path] = dev


def close_removed(opened: dict[str, evdev.InputDevice], grabbed: set[str]) -> None:
    dead = [p for p in opened if not os.path.exists(p)]
    for p in dead:
        grabbed.discard(p)
        try:
            opened.pop(p, None).close()
        except OSError:
            pass


def should_grab_guide_input(cfg: configparser.ConfigParser) -> bool:
    """Exclusive evdev grab on Openbox so Guide/Home does not also reach Steam/X."""
    if not cfg.getboolean("trigger", "grab_guide", fallback=True):
        return False
    if _boot_live() or not openbox_running():
        return False
    if in_exclusive_gamescope_kiosk() or retroarch_running():
        return False
    if cfg.getboolean("trigger", "skip_when_steam_running", fallback=True) and steam_bigpicture_on_openbox():
        return False
    return True


def sync_guide_grabs(
    opened: dict[str, evdev.InputDevice],
    grabbed: set[str],
    cfg: configparser.ConfigParser,
) -> None:
    want = should_grab_guide_input(cfg)
    for path, dev in list(opened.items()):
        try:
            if want:
                if path not in grabbed:
                    dev.grab()
                    grabbed.add(path)
            elif path in grabbed:
                dev.ungrab()
                grabbed.discard(path)
        except OSError:
            grabbed.discard(path)
            try:
                dev.close()
            except OSError:
                pass
            opened.pop(path, None)


def acquire_daemon_lock() -> int | None:
    """One listener per user (autostart + systemd must not double-fire Guide)."""
    lock_path = Path.home() / ".cache/gamebian/controller-menu.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    except OSError:
        return None
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        os.close(fd)
        return None
    os.ftruncate(fd, 0)
    os.write(fd, str(os.getpid()).encode())
    return fd


class TriggerState:
    def __init__(self, mode: str, keyboard_super: bool = True) -> None:
        self.mode = (mode or "guide").strip().lower()
        self.keyboard_super = keyboard_super
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
        if self.keyboard_super and key in (
            ecodes.KEY_LEFTMETA,
            ecodes.KEY_RIGHTMETA,
        ) and val == 1 and self._debounced():
            self.reset_combo()
            return True
        return False


def retroarch_running() -> bool:
    """True while a libretro game session is active (RetroArch frontend)."""
    uid = os.getuid()
    try:
        proc = subprocess.run(
            ["pgrep", "-u", str(uid), "-x", "retroarch"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
        )
        return proc.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
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


def openbox_running() -> bool:
    """True when the Openbox desktop session is active for this user."""
    uid = os.getuid()
    try:
        proc = subprocess.run(
            ["pgrep", "-u", str(uid), "-x", "openbox"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
        )
        return proc.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def _primary_ip() -> str:
    try:
        proc = subprocess.run(
            ["ip", "-4", "route", "get", "1.1.1.1"],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if proc.returncode == 0:
            parts = proc.stdout.split()
            for i, part in enumerate(parts):
                if part == "src" and i + 1 < len(parts):
                    return parts[i + 1]
    except (OSError, subprocess.TimeoutExpired):
        pass
    try:
        proc = subprocess.run(
            ["hostname", "-I"],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            return proc.stdout.split()[0]
    except (OSError, subprocess.TimeoutExpired):
        pass
    return ""


def _steam_process_uses_gamepadui() -> bool:
    """Steam launched with -gamepadui / tenfoot (Big Picture on the desktop)."""
    uid = os.getuid()
    try:
        proc = subprocess.run(
            ["pgrep", "-u", str(uid), "-af", "steam"],
            capture_output=True,
            text=True,
            timeout=3,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    if proc.returncode != 0 or not proc.stdout.strip():
        return False
    for line in proc.stdout.splitlines():
        low = line.lower()
        if "gamepadui" in low or "-tenfoot" in low or "tenfoot_enable" in low:
            return True
    return False


def _steam_bigpicture_window_visible() -> bool:
    env = _launch_env()
    try:
        proc = subprocess.run(
            ["wmctrl", "-l"],
            capture_output=True,
            text=True,
            timeout=3,
            env=env,
        )
        if proc.returncode == 0:
            for line in proc.stdout.splitlines():
                if "big picture" in line.lower() or "steam big picture" in line.lower():
                    return True
    except (OSError, subprocess.TimeoutExpired):
        pass
    try:
        proc = subprocess.run(
            ["xdotool", "search", "--name", "Big Picture"],
            capture_output=True,
            text=True,
            timeout=3,
            env=env,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            return True
    except (OSError, subprocess.TimeoutExpired):
        pass
    return False


def steam_bigpicture_on_openbox() -> bool:
    """Steam Big Picture on the Openbox desktop (conflicts with the controller menu)."""
    if _boot_live() or not openbox_running():
        return False
    if in_exclusive_gamescope_kiosk():
        return False
    if not steam_is_running():
        return False
    return _steam_process_uses_gamepadui() or _steam_bigpicture_window_visible()


def _web_port_from_config(cfg: configparser.ConfigParser | None) -> int:
    if cfg is None or not cfg.has_option("ui", "web_port"):
        return 8844
    try:
        port = cfg.getint("ui", "web_port")
        return port if 1 <= port <= 65535 else 8844
    except (ValueError, TypeError):
        return 8844


def desktop_welcome_panel(cfg: configparser.ConfigParser | None) -> dict[str, object] | None:
    """Structured welcome content for the Openbox desktop menu header."""
    if _boot_live():
        return {
            "tagline": "Live session",
            "intro": "Install Gamebian to disk with Calamares, then reboot.",
            "url_line": "",
            "url_hint": "",
            "steam_title": None,
            "steam_body": None,
        }
    if not openbox_running():
        return None

    port = _web_port_from_config(cfg)
    local_url = f"http://127.0.0.1:{port}"
    lan_ip = _primary_ip()
    if lan_ip:
        url_line = f"{local_url}   ·   http://{lan_ip}:{port}"
        url_hint = "This device (localhost) · other devices on your network (same LAN)"
    else:
        url_line = local_url
        url_hint = "This device (localhost)"

    if steam_account_logged_in():
        steam_title = "Steam is signed in"
        steam_body = (
            "Choose Enter Steam (gamescope) below for Big Picture now. "
            "Reboot to start directly in Steam mode."
        )
    elif not steam_client_installed():
        steam_title = "Install Steam"
        steam_body = (
            "Choose Install Steam below. Package install and Steam’s first update "
            "can take several minutes — watch the setup terminal; Steam may also "
            "run in the background while it downloads."
        )
    else:
        steam_title = "Steam setup"
        steam_body = (
            "Choose Sign in to Steam below. First launch may take a while while "
            "Steam updates in the background — watch the setup terminal, then reboot "
            "(or use Enter Steam once signed in)."
        )

    return {
        "tagline": "Desktop mode",
        "intro": "Upload ROMs, storefront packs, and Flatpak images from any browser:",
        "url_line": url_line,
        "url_hint": url_hint,
        "steam_title": steam_title,
        "steam_body": steam_body,
    }


def default_menu_header_subtitle(cfg: configparser.ConfigParser | None = None) -> str:
    """One-line subtitle when the rich welcome panel is not shown."""
    if _boot_live():
        return "Install to disk · Guide / Super opens this menu"
    if openbox_running():
        return "Guide / Super opens this menu"
    return "Quick launch — Super, Guide / Mode, or Select+Start"


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


def steam_account_logged_in() -> bool:
    """True when Steam loginusers.vdf exists (signed in at least once)."""
    home = Path.home()
    return any((home / rel).is_file() for rel in STEAM_LOGINUSERS_CANDIDATES)


def steam_client_installed() -> bool:
    """True when the Steam client binary is on disk (may still need first-run setup)."""
    if shutil.which("steam"):
        return True
    return any(Path(p).is_file() for p in ("/usr/games/steam", "/usr/bin/steam", "/usr/local/bin/steam"))


def steam_menu_entry_for_user() -> tuple[str, str]:
    """Label + command for the controller menu Steam row."""
    if _boot_live():
        return ("Steam", STEAM_KIOSK_CMD)
    if steam_account_logged_in():
        return ("Enter Steam (gamescope)", STEAM_KIOSK_CMD)
    if not steam_client_installed():
        return ("Install Steam", STEAM_KIOSK_CMD)
    return ("Sign in to Steam", STEAM_KIOSK_CMD)


def is_steam_menu_entry(label: str, command: str) -> bool:
    if label.strip().lower() in (
        "steam",
        "install steam",
        "sign in to steam",
        "enter steam (gamescope)",
    ):
        return True
    cmd_l = command.lower()
    return "enter-steam-kiosk" in cmd_l or "gamebian-steam-bigpicture" in cmd_l


def launch_steam_from_controller_menu(env: dict[str, str]) -> None:
    """Signed out → Steam login on Openbox; signed in → end desktop session, gamescope kiosk."""
    if in_exclusive_gamescope_kiosk():
        notify_user("Already in Steam", "You are in the gamescope Steam session.")
        return
    if steam_account_logged_in():
        notify_user("Steam mode", "Leaving desktop — starting gamescope + Steam Big Picture…")
    elif not steam_client_installed():
        notify_user(
            "Installing Steam",
            "This may take several minutes. A setup terminal will open — "
            "watch it for apt progress. Steam can also run in the background "
            "while it downloads updates.",
        )
    else:
        notify_user(
            "Steam setup",
            "Starting Steam on the desktop. First launch may take a while — "
            "Steam often updates in the background; watch the setup terminal.",
        )
    log_dir = Path.home() / ".cache" / "gamebian"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "controller-launch.log"
    with open(log_file, "a", encoding="utf-8") as logfh:
        logfh.write(f"\n--- launch Steam: {STEAM_KIOSK_CMD}\n")
        subprocess.Popen(
            [STEAM_KIOSK_CMD],
            env=env,
            stdout=logfh,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )


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
        if _boot_live() and cmd == THEMES_SUBMENU_CMD:
            continue
        if is_steam_menu_entry(label, cmd):
            label, cmd = steam_menu_entry_for_user()
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
        *,
        cfg: configparser.ConfigParser | None = None,
        header_subtitle: str = "",
        welcome_panel: dict[str, object] | None = None,
        show_title_label: bool = True,
        footer_hint: str = "D-pad / arrows: navigate   A / Start / Enter: launch   B / Guide / Esc: close",
        item_icon_px: int = 40,
    ) -> None:
        self.items = items
        self.devices = devices
        self._theme = theme
        self._cfg = cfg
        self._item_icon_px = item_icon_px
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
        logo_paths: list[Path] = []
        if icon_path is not None:
            logo_paths.append(icon_path)
        for _extra in ICON_CANDIDATES_INSTALLED:
            _p = Path(_extra)
            if _p.is_file() and _p not in logo_paths:
                logo_paths.append(_p)
        for _logo_path in logo_paths:
            self._logo_photo = load_tk_icon(_logo_path, max_px=88)
            if self._logo_photo is not None:
                tk.Label(icon_frame, image=self._logo_photo, bg=theme["panel"]).pack()
                try:
                    self.root.iconphoto(True, self._logo_photo)
                except tk.TclError:
                    pass
                break

        title_col = tk.Frame(header, bg=theme["panel"])
        title_col.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, pady=16)
        wrap = self._wraplength()
        if show_title_label and title.strip():
            tk.Label(
                title_col,
                text=title,
                fg=theme["title"],
                bg=theme["panel"],
                font=("Sans", 26, "bold"),
                anchor="w",
            ).pack(fill=tk.X)
        if welcome_panel:
            self._pack_welcome_panel(title_col, theme, welcome_panel, wrap)
        elif header_subtitle:
            tk.Label(
                title_col,
                text=header_subtitle,
                fg=theme["subtitle"],
                bg=theme["panel"],
                font=("Sans", 14),
                anchor="w",
                justify=tk.LEFT,
                wraplength=wrap,
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
            photo = load_tk_icon(item_icon, max_px=self._item_icon_px)
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
            text=footer_hint,
            fg=theme["hint"],
            bg=theme["window"],
            font=("Sans", 14),
        ).pack(pady=(8, 28))

        self._hat_repeat_at = 0.0
        self.root.after(16, self._poll_evdev)

    def _wraplength(self) -> int:
        try:
            width = self.root.winfo_screenwidth()
            return max(520, min(1000, int(width * 0.68)))
        except tk.TclError:
            return 920

    def _pack_welcome_panel(
        self,
        parent: tk.Frame,
        theme: dict[str, str],
        panel: dict[str, object],
        wrap: int,
    ) -> None:
        info_bg = theme.get("info_bg", theme["panel"])
        box = tk.Frame(
            parent,
            bg=info_bg,
            highlightthickness=1,
            highlightbackground=theme["border"],
        )
        box.pack(fill=tk.X, pady=(14, 0))

        inner = tk.Frame(box, bg=info_bg)
        inner.pack(fill=tk.X, padx=18, pady=16)

        tagline = str(panel.get("tagline", ""))
        if tagline:
            tk.Label(
                inner,
                text=tagline,
                fg=theme["title"],
                bg=info_bg,
                font=("Sans", 17, "bold"),
                anchor="w",
            ).pack(fill=tk.X)

        intro = str(panel.get("intro", ""))
        if intro:
            tk.Label(
                inner,
                text=intro,
                fg=theme["subtitle"],
                bg=info_bg,
                font=("Sans", 13),
                anchor="w",
                justify=tk.LEFT,
                wraplength=wrap,
            ).pack(fill=tk.X, pady=(6, 0))

        url_line = str(panel.get("url_line", "")).strip()
        url_hint = str(panel.get("url_hint", "")).strip()
        if url_line:
            tk.Label(
                inner,
                text=url_line,
                fg=theme.get("url_fg", theme["title"]),
                bg=info_bg,
                font=("DejaVu Sans Mono", 16, "bold"),
                anchor="w",
                justify=tk.LEFT,
                wraplength=wrap,
            ).pack(fill=tk.X, pady=(12, 0))
        if url_hint:
            tk.Label(
                inner,
                text=url_hint,
                fg=theme["hint"],
                bg=info_bg,
                font=("Sans", 11),
                anchor="w",
                justify=tk.LEFT,
                wraplength=wrap,
            ).pack(fill=tk.X, pady=(4, 0))

        steam_title = panel.get("steam_title")
        steam_body = panel.get("steam_body")
        if steam_title and steam_body:
            sep = tk.Frame(inner, bg=theme["border"], height=1)
            sep.pack(fill=tk.X, pady=(16, 10))
            tk.Label(
                inner,
                text=str(steam_title),
                fg=theme["title"],
                bg=info_bg,
                font=("Sans", 13, "bold"),
                anchor="w",
            ).pack(fill=tk.X)
            tk.Label(
                inner,
                text=str(steam_body),
                fg=theme["subtitle"],
                bg=info_bg,
                font=("Sans", 12),
                anchor="w",
                justify=tk.LEFT,
                wraplength=wrap,
            ).pack(fill=tk.X, pady=(4, 0))

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

    def _open_themes_submenu(self) -> None:
        cfg = self._cfg
        devices = self.devices
        ui = self._theme
        if cfg is not None:
            ui = theme_from_config(cfg)
        self.dismiss()
        if cfg is None:
            return
        sub_items = color_theme_submenu_items(cfg)
        if not sub_items:
            notify_user("Themes", "Color themes are available on installed disk only.")
            return
        MenuApp(
            sub_items,
            devices,
            ui,
            None,
            "Themes",
            cfg=cfg,
            header_subtitle="Pick a desktop color — preview shows the wallpaper",
            footer_hint="D-pad / arrows: navigate   A / Start: apply   B / Esc: back",
            item_icon_px=88,
        ).root.mainloop()

    def activate(self) -> None:
        if not self.items:
            return
        label, cmd, _icon = self.items[self._selected]
        if is_themes_submenu_entry(label, cmd):
            self._open_themes_submenu()
            return
        if is_steam_menu_entry(label, cmd):
            self.dismiss()
            launch_steam_from_controller_menu(_launch_env())
            return
        self.dismiss()
        if cmd.startswith(THEME_COMMAND_PREFIX):
            theme_id = cmd[len(THEME_COMMAND_PREFIX) :].strip()
            if theme_id:
                apply_desktop_theme(theme_id)
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
    lock_fd = acquire_daemon_lock()
    if lock_fd is None:
        print("gamebian-controller-menu: already running", file=sys.stderr)
        return

    cfg = load_config()
    items = programs_from_config(cfg)
    if not items:
        print(
            "gamebian-controller-menu: no [programs] in config; "
            "see /etc/gamebian/controller-menu.ini",
            file=sys.stderr,
        )

    trigger = TriggerState(
        cfg.get("trigger", "mode", fallback="guide"),
        cfg.getboolean("trigger", "keyboard_super", fallback=True),
    )
    opened: dict[str, evdev.InputDevice] = {}
    grabbed: set[str] = set()
    discover_devices(opened)

    while True:
        close_removed(opened, grabbed)
        discover_devices(opened)
        sync_guide_grabs(opened, grabbed, cfg)
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
            skip_steam_ui = cfg.getboolean(
                "trigger",
                "skip_when_steam_running",
                fallback=True,
            )
            if skip_steam_ui and in_exclusive_gamescope_kiosk():
                trigger = TriggerState(
                    cfg.get("trigger", "mode", fallback="guide"),
                    cfg.getboolean("trigger", "keyboard_super", fallback=True),
                )
                continue
            if skip_steam_ui and steam_bigpicture_on_openbox():
                trigger = TriggerState(
                    cfg.get("trigger", "mode", fallback="guide"),
                    cfg.getboolean("trigger", "keyboard_super", fallback=True),
                )
                continue
            if skip_steam_ui and retroarch_running():
                trigger = TriggerState(
                    cfg.get("trigger", "mode", fallback="guide"),
                    cfg.getboolean("trigger", "keyboard_super", fallback=True),
                )
                continue
            ui_theme = theme_from_config(cfg)
            ui_icon = resolve_menu_icon(cfg)
            ui_title = cfg.get("ui", "title", fallback="Gamebian").strip() or "Gamebian"
            MenuApp(
                items,
                opened,
                ui_theme,
                ui_icon,
                ui_title,
                cfg=cfg,
                welcome_panel=desktop_welcome_panel(cfg),
                header_subtitle=default_menu_header_subtitle(cfg),
                show_title_label=False,
            ).root.mainloop()
            trigger = TriggerState(
                cfg.get("trigger", "mode", fallback="guide"),
                cfg.getboolean("trigger", "keyboard_super", fallback=True),
            )


if __name__ == "__main__":
    run()
