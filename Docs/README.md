# Gamebian build scripts reference

Short descriptions of Gamebian overlay scripts under `Build/gambian-iso/overlay/includes.chroot/`. These files are copied into the live ISO squashfs and onto disk after Calamares install.

For the full boot → Openbox → Steam first-boot → gamescope flow, see [STEAM-BOOT-AND-SESSIONS.md](../gambian-iso/docs/STEAM-BOOT-AND-SESSIONS.md). For gamescope/apt on trixie, see [DEBIAN-STEAM-GAMESCOPE.md](../gambian-iso/docs/DEBIAN-STEAM-GAMESCOPE.md).

**Live USB GRUB** uses the same `grub-16x9.png` as installed systems (`overlay/bootloaders/grub-pc|efi/splash.png`, title “Welcome to Gamebian”). Refresh assets with `Build/share/gamebian/install-grub-branding.sh` (also run from `setup.sh`).

Paths below are **on the image** (overlay paths omit `Build/gambian-iso/overlay/includes.chroot`).

---

## Session and LightDM (`/usr/local/bin`, `/usr/sbin`)

| Path | Description |
|------|-------------|
| `/usr/local/bin/gamebian-autologin-session` | **Main autologin dispatcher.** Live ISO (`boot=live`) → Openbox. Installed disk → Openbox until Steam first-boot is complete, then gamescope. |
| `/usr/local/bin/gamebian-lightdm-session` | **Legacy** hidden dispatcher (similar rules, not used for normal autologin). |
| `/usr/local/bin/gamebian-steam-gamescope-session` | LightDM **Steam** session: kiosk env, polkit agent, then `gamebian-steam-bigpicture`. |
| `/usr/local/bin/gamebian-steam-bigpicture` | Runs gamescope + Steam (`-gamepadui`, `-steamos3`); Openbox fallback; “Switch to Desktop” handoff. |
| `/usr/sbin/gamebian-enable-steam-lightdm-session` | **Root:** write `99-gamebian-autologin-steam.conf`, set first-boot markers for gamescope autologin. |
| `/usr/sbin/gamebian-enable-openbox-lightdm-session` | **Root:** prefer Desktop on next boot (`prefer-openbox-desktop` marker). |
| `/usr/sbin/gamebian-enter-steam-kiosk-session` | Start gamescope+Steam on current display; enable Steam session for next boot. |
| `/usr/sbin/gamebian-steam-switch-to-desktop` | Steam power menu “Switch to Desktop”: stop Steam/gamescope, Openbox in same login (no boot change). |
| `/usr/bin/steamos-session-select` | SteamOS API shim: `desktop` → switch-to-desktop; `gamescope` → enable Steam LightDM for next boot. |

---

## User tools (`/usr/local/bin`)

| Path | Description |
|------|-------------|
| `/usr/local/bin/gamebian-controller-menu` | Quick launcher (Super, Guide / Home, Select+Start); theme switcher (`~/.themes`: gamebian, gamebian-installed, green, yellow, blue, red, black, purple). |
| `/usr/local/bin/gamebian-debug-boot-session` | Prints LightDM config, markers, gamescope status, logs; repair hints. |
| `/usr/local/bin/gamebian-debug-lightdm-steam` | Alias for `gamebian-debug-boot-session --full`. |
| `/usr/local/bin/gamebian-fix-steam-boot` | **Root repair:** enable Steam session, set markers, queue reboot notify. |
| `/usr/local/bin/steam-installer` | Thin wrapper: `exec /usr/bin/steam`. |

---

## System install helpers (`/usr/local/sbin`)

| Path | Description |
|------|-------------|
| `/usr/local/sbin/gamebian-ensure-apt-sources` | Calamares: enable **i386** + **contrib/non-free** on install target (Steam, libretro). |
| `/usr/local/sbin/gamebian-install-gamescope` | Install gamescope from sid (apt pins / pool .deb); fallback `steam-without-gamescope` on failure. |
| `/usr/local/sbin/gamebian-install-steam` | Install `steam-installer`; disables sid mix first so apt does not break on `libgpg-error0`. |

---

## Shared libraries (`/usr/share/gamebian`)

Sourced by session scripts, Openbox autostart, and installers — not usually run directly.

| Path | Description |
|------|-------------|
| `/usr/share/gamebian/ensure-apt-contrib-nonfree.sh` | Add **i386**; enable **contrib/non-free** in apt sources (classic + deb822). |
| `/usr/share/gamebian/gamebian-apt-unmix-sid.sh` | Stash sid pins/sources; align `libgpg-error0` amd64/i386 for Steam after gamescope install. |
| `/usr/share/gamebian/gamebian-fix-steam-share.sh` | Symlink `~/.local/share/Steam` → `~/.steam/debian-installation`. |
| `/usr/share/gamebian/gamebian-lightdm-user.sh` | Resolve autologin username and home (root enable-* scripts). |
| `/usr/share/gamebian/gamebian-steam-ready.sh` | Markers, sign-in poll, `gamebian_queue_reboot_notify`, `gamebian_reboot_notice_ready_to_show` (no idle wait on login screen). |
| `/usr/share/gamebian/gamebian-steam-kiosk-env.sh` | Kiosk marker, in-gamescope detection, `switch-to-openbox` flag. |
| `/usr/share/gamebian/gamebian-session-log.sh` | Append to `~/.cache/gamebian/lightdm-login.log`. |

---

## Desktop session helpers (`/usr/share/gamebian`)

| Path | Description |
|------|-------------|
| `/usr/share/gamebian/steam-firstboot-terminal.sh` | First-boot wizard: install/run Steam, enable LightDM Steam session, reboot notifications. |
| `/usr/share/gamebian/gamebian-openbox-notify.sh` | Reboot for gamescope (`--force` skips Steam-idle wait), controller + web tips; zenity/xmessage fallback. |
| `/usr/share/gamebian/gamebian-lxpanel-tray.sh` | Fast systray poll (100ms); NM + nm-tray in parallel; quick embed retries (no 8s delay). |

---

## USB gamepad wake (related)

| Path | Description |
|------|-------------|
| `/usr/libexec/gamebian/enable-usb-wakeup` | Enable `power/wakeup` on USB ancestors of one input device (udev `%p`). |
| `/usr/libexec/gamebian/enable-usb-wakeup-all` | All gamepads + USB root wakeup nodes; used at boot and before suspend. |
| `/usr/lib/systemd/system-sleep/gamebian-usb-wakeup` | Re-apply USB wakeup before suspend. |

---

## How they connect

```text
LightDM autologin
  → gamebian-autologin-session
       → openbox-session (live / first-boot)
            → autostart → steam-firstboot-terminal.sh
            → gamebian-openbox-notify.sh (reboot when ready)
       → gamebian-steam-gamescope-session (after reboot + markers)
            → gamebian-steam-bigpicture
                 → gamescope + steam
```

**Install time (Calamares):** `gamebian-ensure-apt-sources` → `gamebian-install-steam` / `gamebian-install-gamescope` (shellprocess hooks).

---

## Quick commands (installed system)

```bash
gamebian-debug-boot-session          # why am I on Openbox vs Steam?
sudo gamebian-fix-steam-boot         # repair LightDM + markers
sudo gamebian-install-gamescope      # missing gamescope
sudo gamebian-install-steam          # missing steam-installer
/usr/share/gamebian/gamebian-openbox-notify.sh --no-wait --force   # show reboot notice now
```

**Logs:** `~/.cache/gamebian/session.log`, `steam-bigpicture.log`, `openbox-notify.log`, `/var/log/gamebian-install-gamescope.log`

---

## Login credentials

| Boot | Username | Password |
|------|----------|----------|
| Live ISO | `live` | `live` (usually autologin) |
| Installed disk | Calamares **Users** page | Password you set there |

See `/usr/share/gamebian/LOGIN-CREDENTIALS.txt` on the image.
