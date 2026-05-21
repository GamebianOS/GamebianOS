#!/usr/bin/env python3
"""Generate ~/.themes color variants for Gamebian skel overlay."""
from __future__ import annotations

import re
from pathlib import Path

# From TODO/Gamescope- Kernel Optimizations (branding palette)
PALETTE: dict[str, str] = {
    "green": "#55f201",
    "yellow": "#f2ae01",
    "blue": "#0145f2",
    "red": "#f20135",
    "black": "#000000",
    "purple": "#6e01a8",
}

SKEL_THEMES = Path(__file__).resolve().parents[2] / (
    "gambian-iso/overlay/includes.chroot/etc/skel/.themes"
)


def _hex_to_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
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


def palette_for(name: str, accent: str) -> dict[str, str]:
    accent = accent.lower()
    if name == "black":
        return {
            "bg": "#151515",
            "fg": "#ebebeb",
            "base": "#202020",
            "hover": "#2d2d2d",
            "selected_bg": "#3a3a3a",
            "selected_fg": "#ffffff",
            "insensitive_bg": "#141414",
            "insensitive_fg": "#888888",
            "borders": "#2a2a2a",
            "accent": accent,
            "view_text": "#ebebeb",
            "header_bg": "#0d0d0d",
            "dark_ui": True,
        }
    lum = _luminance(accent)
    dark_ui = lum < 0.55 or name == "purple"
    bg = accent
    hover = _darken(accent, 0.12)
    borders = _darken(accent, 0.22)
    selected_bg = _lighten(accent, 0.08) if dark_ui else _darken(accent, 0.08)
    if name == "yellow":
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
        "bg": bg,
        "fg": fg,
        "base": base,
        "hover": hover,
        "selected_bg": selected_bg,
        "selected_fg": selected_fg,
        "insensitive_bg": borders,
        "insensitive_fg": insensitive_fg,
        "borders": borders,
        "accent": accent,
        "view_text": view_text,
        "header_bg": hover,
        "dark_ui": dark_ui,
    }


def gtk3_css(name: str, p: dict[str, str]) -> str:
    return f"""/* Gamebian theme: {name} ({p["accent"]}) */

@define-color theme_bg_color {p["bg"]};
@define-color theme_fg_color {p["fg"]};
@define-color theme_text_color {p["fg"]};
@define-color theme_base_color {p["base"]};
@define-color theme_view_hover_color {p["hover"]};
@define-color theme_selected_bg_color {p["selected_bg"]};
@define-color theme_selected_fg_color {p["selected_fg"]};
@define-color insensitive_bg_color {p["insensitive_bg"]};
@define-color insensitive_fg_color {p["insensitive_fg"]};
@define-color borders {p["borders"]};
@define-color wm_title {p["fg"]};
@define-color wm_unfocused_title {p["insensitive_fg"]};

.background,
window.background {{
  background-color: @theme_bg_color;
  color: @theme_fg_color;
}}

headerbar.titlebar {{
  background: linear-gradient(180deg, @theme_view_hover_color 0%, @theme_bg_color 100%);
  color: @theme_fg_color;
  border-bottom: 1px solid @borders;
}}

button {{
  background-color: @theme_view_hover_color;
  color: @theme_fg_color;
  border: 1px solid @borders;
}}

button:hover {{
  background-color: @theme_selected_bg_color;
  color: @theme_selected_fg_color;
}}

notebook header {{
  background-color: @theme_bg_color;
  color: @theme_fg_color;
}}

notebook header tabs tab {{
  padding: 8px 16px;
  margin: 0 3px;
  min-height: 1.2em;
}}

notebook header tabs tab label {{
  padding: 2px 4px;
}}

notebook header tabs tab:checked {{
  background-color: @theme_view_hover_color;
  color: @theme_selected_fg_color;
}}

scrollbar slider {{
  background-color: @theme_view_hover_color;
  border: 1px solid @borders;
}}

scrollbar trough {{
  background-color: @theme_bg_color;
}}

popover,
popover.background,
menu {{
  background-color: @theme_bg_color;
  color: @theme_fg_color;
}}

menuitem:hover,
menu menuitem:hover {{
  background-color: @theme_view_hover_color;
  color: @theme_selected_fg_color;
}}

menubar {{
  padding: 2px 4px;
}}

menubar > menuitem {{
  padding: 6px 12px;
}}

menubar > menuitem:hover {{
  background-color: @theme_view_hover_color;
  color: @theme_fg_color;
}}

menu menuitem {{
  padding: 6px 16px;
  min-height: 1.5em;
}}

.view,
viewport view {{
  background-color: @theme_base_color;
  color: {p["view_text"]};
}}

.view:selected,
.view:selected:focus {{
  background-color: @theme_selected_bg_color;
  color: @theme_selected_fg_color;
}}

calendar {{
  background-color: @theme_base_color;
  color: {p["view_text"]};
}}

calendar.header {{
  background-color: @theme_bg_color;
  color: @theme_fg_color;
}}

calendar.button {{
  background-color: @theme_view_hover_color;
  color: @theme_fg_color;
}}

calendar:selected {{
  background-color: @theme_selected_bg_color;
  color: @theme_selected_fg_color;
}}

calendar:indeterminate {{
  color: @insensitive_fg_color;
}}
"""


def gtk2_rc(name: str, p: dict[str, str]) -> str:
    sid = name.replace("-", "_")
    return f"""# Gamebian GTK2 — {name}

style "{sid}-default" {{
  fg[NORMAL]       = "{p["fg"]}"
  fg[PRELIGHT]     = "{p["fg"]}"
  fg[ACTIVE]       = "{p["selected_fg"]}"
  fg[SELECTED]     = "{p["selected_fg"]}"
  fg[INSENSITIVE]  = "{p["insensitive_fg"]}"

  bg[NORMAL]       = "{p["bg"]}"
  bg[PRELIGHT]     = "{p["hover"]}"
  bg[ACTIVE]       = "{p["selected_bg"]}"
  bg[SELECTED]     = "{p["selected_bg"]}"
  bg[INSENSITIVE]  = "{p["insensitive_bg"]}"

  base[NORMAL]     = "{p["base"]}"
  base[PRELIGHT]   = "{p["base"]}"
  base[ACTIVE]     = "{p["selected_bg"]}"
  base[SELECTED]   = "{p["selected_bg"]}"
  base[INSENSITIVE]= "{p["insensitive_bg"]}"

  text[NORMAL]     = "{p["view_text"]}"
  text[PRELIGHT]   = "{p["view_text"]}"
  text[ACTIVE]     = "{p["selected_fg"]}"
  text[SELECTED]   = "{p["selected_fg"]}"
  text[INSENSITIVE]= "{p["insensitive_fg"]}"

  font_name = "Sans 9"
}}

class "GtkWidget" style "{sid}-default"

style "{sid}-notebook" = "{sid}-default" {{
  GtkNotebook::tab-hborder = 12
  GtkNotebook::tab-vborder = 6
}}

class "GtkNotebook" style "{sid}-notebook"

gtk-icon-theme-name = "Papirus"
"""


def openbox_themerc(name: str, p: dict[str, str]) -> str:
    acc = p["accent"]
    if p["dark_ui"]:
        title_bg = "#242424" if name != "black" else "#242424"
        client = "#242424"
        label_fg = "#eeeeec"
        label_inactive = "#929292"
        border = "#3d3d3d"
        menu_bg = "#383838"
        btn_hover = "#3d3d3d"
        btn_pressed = _darken(acc, 0.2)
    else:
        title_bg = "#ebebeb"
        client = "#fafafa"
        label_fg = "#1e1e1e"
        label_inactive = "#777777"
        border = "#bdbdbd"
        menu_bg = "#fafafa"
        btn_hover = "#d8d8d8"
        btn_pressed = acc
    close_hover = "#c01c28"
    menu_active = acc
    return f"""!# {name} — Openbox 3 ({acc})

*.font: shadow=n
window.active.label.text.font: shadow=n
window.inactive.label.text.font: shadow=n
menu.items.font: shadow=n

border.width: 1
padding.width: 4
padding.height: 3
window.handle.width: 2
window.client.padding.width: 0
menu.overlap: 2
*.justify: left

window.active.border.color: {border}
window.inactive.border.color: {border}
window.active.client.color: {client}
window.inactive.client.color: {client}

window.active.title.separator.color: {border}
window.inactive.title.separator.color: {border}

window.active.label.text.color: {label_fg}
window.inactive.label.text.color: {label_inactive}

window.active.title.bg: flat solid
window.active.title.bg.color: {title_bg}
window.active.label.bg: parentrelative
window.inactive.title.bg: flat solid
window.inactive.title.bg.color: {title_bg}
window.inactive.label.bg: parentrelative

window.active.handle.bg: flat solid
window.active.handle.bg.color: {title_bg}
window.inactive.handle.bg: flat solid
window.inactive.handle.bg.color: {title_bg}
window.active.grip.bg: flat solid
window.active.grip.bg.color: {title_bg}
window.inactive.grip.bg: flat solid
window.inactive.grip.bg.color: {title_bg}

window.active.button.unpressed.bg: parentrelative
window.active.button.unpressed.image.color: {label_fg}
window.active.button.hover.bg: flat solid
window.active.button.hover.bg.color: {btn_hover}
window.active.button.hover.image.color: {label_fg}
window.active.button.pressed.bg: flat solid
window.active.button.pressed.bg.color: {btn_pressed}
window.active.button.pressed.image.color: #ffffff
window.active.button.disabled.bg: parentrelative
window.active.button.disabled.image.color: {label_inactive}

window.inactive.button.unpressed.bg: parentrelative
window.inactive.button.unpressed.image.color: {label_inactive}
window.inactive.button.hover.bg: flat solid
window.inactive.button.hover.bg.color: {btn_hover}
window.inactive.button.hover.image.color: {label_fg}
window.inactive.button.pressed.bg: flat solid
window.inactive.button.pressed.bg.color: {btn_pressed}
window.inactive.button.pressed.image.color: #ffffff

window.active.button.close.hover.bg: flat solid
window.active.button.close.hover.bg.color: {close_hover}
window.active.button.close.hover.image.color: #ffffff

window.inactive.button.close.hover.bg: flat solid
window.inactive.button.close.hover.bg.color: #8b1922
window.inactive.button.close.hover.image.color: #eeeeec

menu.border.width: 1
menu.border.color: {border}
menu.overlap.x: 0
menu.overlap.y: 0

menu.title.bg: flat solid
menu.title.bg.color: {title_bg}
menu.title.text.color: {label_fg}

menu.items.bg: flat solid
menu.items.bg.color: {menu_bg}
menu.items.text.color: {label_fg}
menu.items.disabled.text.color: {label_inactive}

menu.items.active.bg: flat solid
menu.items.active.bg.color: {menu_active}
menu.items.active.text.color: #ffffff

menu.separator.width: 1
menu.separator.padding.width: 4
menu.separator.padding.height: 4
menu.separator.color: {border}

osd.border.width: 1
osd.border.color: {border}
osd.label.text.color: {label_fg}

osd.bg: flat solid
osd.bg.color: {title_bg}
osd.label.bg: parentrelative

osd.hilight.bg: flat solid
osd.hilight.bg.color: {menu_active}
osd.unhilight.bg: flat solid
osd.unhilight.bg.color: {btn_hover}
"""


def index_theme(name: str, accent: str) -> str:
    title = name.capitalize()
    return f"""[Desktop Entry]
Type=X-GNOME-Metatheme
Name={title}
Comment=Gamebian {title} theme ({accent})

[X-GNOME-Metatheme]
GtkTheme={name}

[X-Gnome-Metatheme]
GtkTheme={name}
"""


def write_theme(name: str, accent: str) -> None:
    p = palette_for(name, accent)
    root = SKEL_THEMES / name
    (root / "gtk-3.0").mkdir(parents=True, exist_ok=True)
    (root / "gtk-2.0").mkdir(parents=True, exist_ok=True)
    (root / "openbox-3").mkdir(parents=True, exist_ok=True)
    (root / "gtk-3.0" / "gtk.css").write_text(gtk3_css(name, p), encoding="utf-8")
    (root / "gtk-2.0" / "gtkrc").write_text(gtk2_rc(name, p), encoding="utf-8")
    (root / "openbox-3" / "themerc").write_text(openbox_themerc(name, p), encoding="utf-8")
    (root / "index.theme").write_text(index_theme(name, accent), encoding="utf-8")
    print(f"wrote {root}")


def main() -> None:
    if not SKEL_THEMES.is_dir():
        raise SystemExit(f"missing {SKEL_THEMES}")
    for name, accent in PALETTE.items():
        write_theme(name, accent)
    print("done:", ", ".join(PALETTE))


if __name__ == "__main__":
    main()
