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

- Window manager: `openbox`
- File manager: `thunar`
- Settings UI: `obconf`, `lxappearance`
- Panel: `lxpanel` (Debian *testing* currently has no `tint2` binary package; menu button uses `design/menu-icon.png` via rofi)
- App launcher: `rofi`
- Wallpaper: `feh` + art from `design/` (applied on login)
- Installer: `calamares` (`~/Desktop/Install Gamebian.desktop`; Debian’s duplicate Calamares desktop icon autostart is disabled)

This profile is separate from `Build/minimal-server-live` and `Build/calamares-live`.
