#!/usr/bin/env bash
# First disk-login helper: terminal shows Debian / Valve Steam launcher output; completes LightDM tilt to gamescope.

set +e

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games${PATH:+:$PATH}"

_show_installed_notice() {
	if [ -x /usr/share/gamebian/gamebian-installed-openbox-notice.sh ]; then
		/usr/share/gamebian/gamebian-installed-openbox-notice.sh --no-wait
	elif [ -x /usr/share/gamebian/gamebian-steam-reboot-notice.sh ]; then
		/usr/share/gamebian/gamebian-steam-reboot-notice.sh
	fi
}

_enable_steam_lightdm_session() {
	if [ "$(id -u)" -eq 0 ]; then
		/usr/sbin/gamebian-enable-steam-lightdm-session
		return $?
	fi

	if sudo -n /usr/sbin/gamebian-enable-steam-lightdm-session 2>/dev/null; then
		return 0
	fi

	echo >&2 ""
	echo >&2 "To use the fullscreen Steam (gamescope) session next boot you need sudo once:"
	echo >&2 "  sudo /usr/sbin/gamebian-enable-steam-lightdm-session"
	echo >&2 ""
	if ! sudo /usr/sbin/gamebian-enable-steam-lightdm-session; then
		echo >&2 "Could not enable the Steam kiosk session automatically."
		return 1
	fi
	return 0
}

steam_bin=""
for _c in /usr/bin/steam /usr/local/bin/steam /usr/games/steam; do
	if [ -x "${_c}" ]; then
		steam_bin="${_c}"
		break
	fi
done

if [ -z "${steam_bin}" ]; then
	echo "Steam is not installed (no steam executable in /usr/bin, /usr/local/bin, or /usr/games)." >&2
	echo "Install with: sudo apt update && sudo apt install -y steam-installer" >&2
	read -r -p "$(printf '\nPress Enter to close.')" || true
	exit 1
fi

echo "Starting Steam… output below is from Valve’s launcher script."
echo "When you are done installing updates and signing in if prompted, quit Steam,"
echo "then press Enter in this terminal to finish (we will prompt you to reboot for the kiosk session)."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"${steam_bin}"
code=$?

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Steam launcher exited with code ${code}."
echo "Full log may also be at: ~/.steam/steam/logs/console-linux.txt"

mkdir -p "${HOME}/.config"
touch "${HOME}/.config/gamebian-firstboot-steam.run-finished"

export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
if [ -x /usr/share/gamebian/gamebian-openbox-notify.sh ]; then
	/usr/share/gamebian/gamebian-openbox-notify.sh --no-wait
fi

read -r -p "$(printf '\nPress Enter when you are finished (enables Steam session after reboot)... ')"

mkdir -p "${HOME}/.config"
if ! _enable_steam_lightdm_session; then
	read -r -p "$(printf '\nPress Enter after saving the sudo output above.')" || true
	exit 1
fi

touch "${HOME}/.config/gamebian-firstboot-steam.done"
echo ""
echo "Please reboot, then log in with the Steam session (gamescope) at the greeter."

read -r -p "$(printf '\nPress Enter to close this terminal.')" || true
