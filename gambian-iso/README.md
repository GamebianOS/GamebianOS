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
- **`gamebian-web`** (Steam-first remote install/manage web utility): **source-only on the live ISO** (`/usr/src/gamebian-web/`). **`overlay/package-lists/gamebian-web.list.chroot`** pulls in all **`python3-*`** libraries the app imports (PyYAML, vdf, Bottle, Beaker, etc.) into the squashfs so the live system matches the installer. A Calamares `shellprocess` (`shellprocess@gamebian-web`, defined in `Build/share/calamares-gamebian/etc/calamares/modules/shellprocess_gamebian_web.conf`) installs it on the **target** disk after `sources-final` (so APT uses the configured mirror, not `file:/run/live/medium/…` which lacks `binary-i386` on amd64-only media): apt-installs the same deps, runs `pip install --prefix=/usr` from the staged source, and enables `gamebian-proxy.socket` / `gamebian-proxy.service` (system) plus `gamebian.service` (user, via `systemctl --global enable`). The live session itself never runs `gamebian-web`.

This profile is separate from `Build/minimal-server-live` and `Build/calamares-live`.
