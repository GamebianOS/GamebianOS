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
- Thin base: **`sudo`**, **`systemd-sysv`**, kernel metapackage, **`network-manager`**, **`nm-tray`**, **`blueman`** (Bluetooth tray via **`blueman-applet`**; **`GTK_ICON_THEME`** from **`/etc/X11/Xsession.d/45gamebian-live-gtktheme`** + Papirus in skel), **`qt5-gtk-platformtheme`**, **`qt6-gtk-platformtheme`**, **`hicolor-icon-theme`**, **`nm-connection-editor`**, **`mate-polkit`** (PolKit GUI agent started from autostart — replaces removed **`policykit-1-gnome`** on Trixie so Wi‑Fi/password dialogs accept keyboard input), **`openssh-client`**, **`openssh-server`**, **`iproute2`**; **`epiphany-browser`** (GNOME Web) for **`x-www-browser`** (chroot hook sets alternatives). **`nm-tray`** starts **from Openbox autostart immediately after **`lxpanel`**** (embedded systray must exist first; avoids Qt **`No Icon set`**). Uses **`QT_QPA_PLATFORMTHEME=gtk3`** so Qt picks up GTK icon settings from **`lxappearance`**. After Calamares (**`services-systemd.conf`** runs **after** **`packages`**), **`ssh.socket`** is **`systemctl enable`d** on the target and **`/etc/ssh/sshd_not_to_be_run`** is removed (**`shellprocess@gamebian-sshprep`**). **`sudo systemctl status ssh.socket`** / **`ss -tlnp | grep :22`** on first boot; **`Connection refused`** usually means the listener is still off or a firewall blocks port 22.
- Installer: **`calamares`** on the ISO only; **`calamares` / live-\* stacks are purged** on installed disk (**`packages`** job + APT autoremove). On the target, **`shellprocess@gamebian-sshprep`** removes live-only LightDM config and legacy session drop-ins; **Openbox-first autologin** is handled by **`gamebian-autologin-session`** plus user markers until **`steam-firstboot-terminal.sh`** runs **`gamebian-enable-steam-lightdm-session`** (writes **`99-gamebian-autologin-steam.conf`**). See **[`docs/STEAM-BOOT-AND-SESSIONS.md`](docs/STEAM-BOOT-AND-SESSIONS.md)** for the full flow. **`Build/share/calamares-gamebian/etc/calamares/modules/welcome.conf`** requires **internet** (HTTP checks on debian.org + fallbacks): you cannot proceed until the live session can reach the network mirror, avoiding silent APT **404**/offline failures during **`gamebian-web-install`**.
- **`gamebian-web`** (Steam-first remote install/manage web utility): **source-only on the live ISO** (`/usr/src/gamebian-web/`). **`overlay/package-lists/gamebian-web.list.chroot`** pulls in all **`python3-*`** libraries the app imports (PyYAML, vdf, Bottle, Beaker, etc.) into the squashfs so the live system matches the installer. A Calamares `shellprocess` (`shellprocess@gamebian-web`, defined in `Build/share/calamares-gamebian/etc/calamares/modules/shellprocess_gamebian_web.conf`) installs it on the **target** disk after `sources-final` (so APT uses the configured mirror, not `file:/run/live/medium/…` which lacks `binary-i386` on amd64-only media): apt-installs the same deps, runs `pip install --prefix=/usr` from the staged source, and enables `gamebian-proxy.socket` / `gamebian-proxy.service` (system) plus `gamebian.service` (user, via `systemctl --global enable`). The live session itself never runs `gamebian-web`.
- **Steam (installed disk):** LightDM autologins **`gamebian-autologin-session`**, which starts **Openbox** until Steam first-boot is complete (`~/.config/gamebian-firstboot-steam.done` and related markers in **`gamebian-steam-ready.sh`**). **Openbox autostart** launches **xfce4-terminal** with **`steam-firstboot-terminal.sh`** once (install/sign-in, then quit Steam). That script runs **`/usr/sbin/gamebian-enable-steam-lightdm-session`** (**`sudo NOPASSWD`** for **`%sudo`**) and sets greeter default **`user-session=gamebian-steam`** via **`99-gamebian-autologin-steam.conf`**. **`notify-send`** reminds you **to reboot** (manual reboot required). After reboot, autologin runs **`gamebian-steam-gamescope-session`** → **`gamebian-steam-bigpicture`** (fullscreen **gamescope** + **Steam**). Greeter offers **Desktop** (Openbox) and **Steam**; under Openbox use **`gamebian-steam-bigpicture`** (**`Super+Shift+S`** / menu). Full script reference: **[`docs/STEAM-BOOT-AND-SESSIONS.md`](docs/STEAM-BOOT-AND-SESSIONS.md)**. **Hybrid GPU / Vulkan:** **`~/.config/gamebian/steam-gamescope.env`** (see **`steam-gamescope.env.example`**). **`STEAM_BIGPICTURE_UI=classic`** maps to **`-bigpicture`**. **`GAMEBIAN_GAMESCOPE_*`** flags are documented atop **`gamebian-steam-bigpicture`**.
- **Hybrid laptop (AMD iGPU + NVIDIA, Mesa NVK):** **gamescope** often **fails or never shows** the Steam kiosk when Vulkan picks **NVK**, because the compositor expects a working DRM-capable device path. Typical fix: force **AMD RADV** for the kiosk only — create **`~/.config/gamebian/steam-gamescope.env`** with **`GAMEBIAN_VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json`** (filename varies by Mesa; **`ls /usr/share/vulkan/icd.d/`**) (see skel **`steam-gamescope.env.example`**), or install the **proprietary NVIDIA driver** stack if you require the dGPU for the whole session. **`gamebian-steam-gamescope-session`** also sources **`/etc/default/gamebian-steam-gamescope`** machine-wide. **`GAMEBIAN_GAMESCOPE_EXTRA_ARGS`** and **`gamescope --help`** cover **`--prefer-vk-device`**. Setting **`GAMEBIAN_VK_ICD_FILENAMES`** applies to **Steam and child games** as well (not only gamescope).

This profile is separate from `Build/minimal-server-live` and `Build/calamares-live`.
