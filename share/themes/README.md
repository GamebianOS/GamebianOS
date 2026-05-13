# Gamebian theme (wallpaper + color presets)

Small **Python 3 + Tkinter** utility to set **desktop wallpaper** and switch between the two Gamebian **GTK / Openbox** looks (`gamebian` blue vs `gamebian-installed` dark).

## Requirements

- **Python 3** with **Tkinter**: on Debian, `sudo apt install python3-tk`
- **feh** (wallpaper): `sudo apt install feh` (already on Gamebian Openbox images)
- **openbox** and config at `~/.config/openbox/rc.xml` (for window-border theme)

## Try without installing

From the GamebianOS repository root:

```bash
cd Build/share/themes
PYTHONPATH=. python3 -m gamebian_theme
```

Or:

```bash
cd Build/share/themes
./bin/gamebian-theme
```

## Install (optional)

```bash
cd Build/share/themes
pip install --user .
```

Then run `gamebian-theme` if `~/.local/bin` is on your `PATH`.

## Menu shortcut (.desktop)

Copy `data/gamebian-theme.desktop` to `~/.local/share/applications/`. If you are not using `pip install`, set **`Exec=`** to the full path of `bin/gamebian-theme`, or:

`Exec=env PYTHONPATH=/path/to/GamebianOS/Build/share/themes python3 -m gamebian_theme`

## What it writes

| Path | Purpose |
|------|---------|
| `~/.config/gamebian/theme.json` | Last choices (paths + theme ids) |
| `~/.config/gamebian/wallpaper` | One line: image path (for autostart; see below) |
| `~/.config/gamebian/session-env.sh` | `export GTK_THEME=…` for your Openbox session |
| `~/.config/gtk-3.0/settings.ini` | `gtk-theme-name` (GTK 3) |
| `~/.gtkrc-2.0` | GTK 2 / lxpanel |
| `~/.config/openbox/rc.xml` | `<theme><name>…</name>` Openbox window theme |

**Apply** runs `feh --no-fehbg --bg-fill`, `openbox --reconfigure`, and `lxpanelctl restart` when available.

## Persist wallpaper + GTK theme across login

Openbox runs `~/.config/openbox/autostart` as **one shell script**, so exports at the **top** affect `lxpanel` and other lines below.

1. **Theme / GTK** — add as the **first** lines of `~/.config/openbox/autostart`:

   ```sh
   # Gamebian theme (GTK_THEME before lxpanel / tray apps)
   if [ -r "${HOME}/.config/gamebian/session-env.sh" ]; then
   	. "${HOME}/.config/gamebian/session-env.sh"
   fi
   ```

2. **Wallpaper** — either keep your existing `feh` line and point it at the same file this app writes, or prefer the saved path. Example replacement for the stock wallpaper block:

   ```sh
   if [ -r "${HOME}/.config/gamebian/wallpaper" ]; then
   	_w=$(head -1 "${HOME}/.config/gamebian/wallpaper" | tr -d '\r\n')
   	if [ -n "${_w}" ] && [ -r "${_w}" ]; then
   		feh --no-fehbg --bg-fill "${_w}" &
   	fi
   elif [ -r "${HOME}/.local/share/gamebian/background.png" ]; then
   	feh --no-fehbg --bg-fill "${HOME}/.local/share/gamebian/background.png" &
   # …else fall back to /usr/share/backgrounds/… as before
   fi
   ```

After editing autostart, log out and back in (or reboot) once to verify order.

## Note on `/etc/X11/Xsession.d/`

Some installs export `GTK_THEME` before Openbox starts. Gamebian’s `45gamebian-live-gtktheme` only sets `GTK_THEME` when it is **unset**. If your session always forces a theme, either adjust that snippet or set `GTK_THEME` in `~/.xprofile` **before** the session starts so it matches this app’s choice.
