"""Tkinter UI for wallpaper + preset themes."""

from __future__ import annotations

import sys
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from gamebian_theme import persist


PRESETS = [
    ("gamebian", "Blue (Gamebian / live-style)"),
    ("gamebian-installed", "Dark (installed-style)"),
]
PRESET_LABELS = [f"{label}  —  [{tid}]" for tid, label in PRESETS]
PRESET_IDS = [p[0] for p in PRESETS]


def _label_for_id(tid: str) -> str:
    for i, (pid, _) in enumerate(PRESETS):
        if pid == tid:
            return PRESET_LABELS[i]
    return PRESET_LABELS[1]


def _id_from_label(label: str) -> str | None:
    for i, pl in enumerate(PRESET_LABELS):
        if pl == label:
            return PRESET_IDS[i]
    # allow raw id pasted
    if label in PRESET_IDS:
        return label
    return None


def _apply_dark_window_style(root: tk.Tk) -> None:
    """Dark window chrome for the theme utility (matches gamebian-installed feel)."""
    bg = "#1e1e1e"
    fg = "#e8e8e8"
    mid = "#2d2d2d"
    field = "#3c3c3c"
    border = "#555555"
    accent = "#4a8fd9"

    root.configure(background=bg)
    style = ttk.Style(root)
    try:
        style.theme_use("clam")
    except tk.TclError:
        return

    style.configure(".", background=bg, foreground=fg, fieldbackground=field, troughcolor=mid)
    style.configure("TFrame", background=bg)
    style.configure("TLabel", background=bg, foreground=fg)
    style.configure(
        "TButton",
        background=mid,
        foreground=fg,
        bordercolor=border,
        lightcolor=mid,
        darkcolor=mid,
    )
    style.map("TButton", background=[("active", "#3a3a3a"), ("pressed", "#505050")])
    style.configure("TCheckbutton", background=bg, foreground=fg, focuscolor=accent)
    style.map("TCheckbutton", background=[("active", bg)])
    style.configure("TEntry", fieldbackground=field, foreground=fg, insertcolor=fg, bordercolor=border)
    style.configure(
        "TCombobox",
        fieldbackground=field,
        background=mid,
        foreground=fg,
        arrowcolor=fg,
        bordercolor=border,
        lightcolor=mid,
        darkcolor=mid,
    )
    style.map("TCombobox", fieldbackground=[("readonly", field)], background=[("readonly", mid)])


def main() -> None:
    try:
        _run()
    except tk.TclError as e:
        print("gamebian-theme: Tkinter failed to start.", e, file=sys.stderr)
        print("On Debian: sudo apt install python3-tk", file=sys.stderr)
        sys.exit(1)


def _run() -> None:
    saved = persist.load_saved()
    default_theme = saved.get("gtk_theme") or "gamebian-installed"
    if default_theme not in dict(PRESETS):
        default_theme = "gamebian-installed"
    default_wall = saved.get("wallpaper") or ""

    root = tk.Tk()
    _apply_dark_window_style(root)
    root.title("Gamebian theme")
    root.minsize(420, 220)
    frm = ttk.Frame(root, padding=12)
    frm.grid(row=0, column=0, sticky="nsew")
    root.columnconfigure(0, weight=1)
    root.rowconfigure(0, weight=1)

    wall_var = tk.StringVar(value=default_wall)
    theme_var = tk.StringVar(value=_label_for_id(default_theme))
    sync_ob_var = tk.BooleanVar(value=True)

    ttk.Label(frm, text="Wallpaper image").grid(row=0, column=0, sticky="w")
    row = ttk.Frame(frm)
    row.grid(row=1, column=0, sticky="ew", pady=(0, 8))
    row.columnconfigure(0, weight=1)
    ent = ttk.Entry(row, textvariable=wall_var)
    ent.grid(row=0, column=0, sticky="ew", padx=(0, 6))
    ttk.Label(frm, text="Color scheme (GTK + Openbox borders)").grid(row=2, column=0, sticky="w")
    combo = ttk.Combobox(
        frm,
        textvariable=theme_var,
        values=PRESET_LABELS,
        state="readonly",
        width=48,
    )
    combo.grid(row=3, column=0, sticky="ew", pady=(0, 4))
    # Show friendly labels in a separate static hint
    hint = ttk.Label(
        frm,
        text="gamebian = blue UI · gamebian-installed = dark grey UI",
        font=("Sans", 8),
        foreground="#9aa0a6",
    )
    hint.grid(row=4, column=0, sticky="w", pady=(0, 8))

    ttk.Checkbutton(
        frm,
        text="Also set Openbox window theme (same name as GTK theme)",
        variable=sync_ob_var,
    ).grid(row=5, column=0, sticky="w", pady=(0, 12))

    status = tk.StringVar(value="")
    ttk.Label(frm, textvariable=status, wraplength=400, justify="left").grid(
        row=7, column=0, sticky="ew"
    )

    def browse() -> None:
        p = filedialog.askopenfilename(
            title="Choose wallpaper",
            filetypes=[
                ("Images", "*.png *.jpg *.jpeg *.webp *.bmp *.gif"),
                ("All files", "*"),
            ],
        )
        if p:
            wall_var.set(p)

    ttk.Button(row, text="Browse…", command=browse).grid(row=0, column=1)

    def apply_theme() -> None:
        tid = _id_from_label(theme_var.get().strip())
        wall = wall_var.get().strip() or None
        if not tid:
            messagebox.showerror("Theme", "Pick a valid color scheme.")
            return
        if wall and not Path(wall).is_file():
            messagebox.showerror("Wallpaper", f"File not found:\n{wall}")
            return

        prev = persist.load_saved()
        if sync_ob_var.get():
            ob_theme = tid
        else:
            ob_theme = prev.get("openbox_theme") or tid

        notes: list[str] = []
        try:
            persist.write_session_env(tid)
            persist.write_gtk3_settings(tid)
            persist.write_gtk2_rc(tid)
            persist.save_theme_json(wall, tid, ob_theme)
            if wall:
                persist.write_wallpaper_path(wall)
            else:
                persist.write_wallpaper_path(None)

            if sync_ob_var.get() and persist.OB_RC.is_file():
                if persist.patch_openbox_theme_name(persist.OB_RC, tid):
                    ok, err = persist.reconfigure_openbox()
                    if ok:
                        notes.append("Openbox reconfigured.")
                    else:
                        notes.append(f"Openbox: {err}")
                else:
                    notes.append("Openbox: could not patch theme name in rc.xml.")
            elif sync_ob_var.get():
                notes.append(f"No {persist.OB_RC} — skipped Openbox.")

            if wall:
                ok, err = persist.apply_feh(wall)
                if ok:
                    notes.append("Wallpaper applied (feh).")
                else:
                    notes.append(f"Wallpaper: {err}")

            persist.restart_lxpanel()
            notes.append("lxpanel restarted if lxpanelctl was available.")
        except OSError as e:
            messagebox.showerror("Write failed", str(e))
            return

        status.set(" ".join(notes))
        messagebox.showinfo(
            "Applied",
            "Settings saved.\n\n"
            "For GTK_THEME on every login, source ~/.config/gamebian/session-env.sh\n"
            "at the top of ~/.config/openbox/autostart (see Build/share/themes/README.md).",
        )

    btns = ttk.Frame(frm)
    btns.grid(row=6, column=0, sticky="ew", pady=(0, 6))
    ttk.Button(btns, text="Apply", command=apply_theme).pack(side="left", padx=(0, 8))
    ttk.Button(btns, text="Quit", command=root.destroy).pack(side="left")

    root.mainloop()


if __name__ == "__main__":
    main()
