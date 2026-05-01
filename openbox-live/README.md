# Openbox Live Profile

This profile builds a lightweight Openbox live ISO.
It now includes Calamares so the live session can install to disk.

## Build output directory

Default output root:

`/home/khinds/gamebianos-build-openbox`

Override with:

`GAMEBIANOS_BUILD_ROOT=/some/path`

## Commands

```bash
cd Build/openbox-live
./setup.sh
./build.sh
```

## Included starter kit

- Display manager / login: `lightdm` + `lightdm-gtk-greeter`; session **`openbox`** (`openbox-session`, autostart + XDG autostart as in skel).
- Panel: `lxpanel` (launcher uses **`/usr/share/pixmaps/menu-icon-default.png`** for rofi).
- Appearance: **lxappearance** + **lxappearance-obconf** (GTK + Openbox from one tool).
- Apps: **rofi**, **feh** (wallpaper from `design/`), **Thunar**, **xfce4-terminal**.
- Thin base: **`sudo`**, **`systemd-sysv`**, kernel metapackage, **`network-manager`**, **`iproute2`**; **`netsurf-gtk`** for **`x-www-browser`** (chroot hook sets alternatives).
- Installer: **`calamares`** on the ISO only; **`calamares` / live-\* stacks are purged** on installed disk (**`packages`** job + APT autoremove), with **LightDM** forced to **`openbox`**.

This profile is separate from `Build/minimal-server-live` and `Build/calamares-live`.
