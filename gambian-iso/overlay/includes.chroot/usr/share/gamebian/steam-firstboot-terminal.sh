#!/usr/bin/env bash
# First disk-login: run Steam, enable Steam autologin, show reboot notifications.

set +e

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games${PATH:+:$PATH}"

_enable_steam_lightdm_session() {
	if [ "$(id -u)" -eq 0 ]; then
		/usr/sbin/gamebian-enable-steam-lightdm-session
		return $?
	fi

	if sudo -n /usr/sbin/gamebian-enable-steam-lightdm-session 2>/dev/null; then
		return 0
	fi

	echo >&2 ""
	echo >&2 "To boot into the Steam (gamescope) session you need sudo once:"
	echo >&2 "  sudo /usr/sbin/gamebian-enable-steam-lightdm-session"
	echo >&2 "  sudo gamebian-fix-steam-boot"
	echo >&2 ""
	if ! sudo /usr/sbin/gamebian-enable-steam-lightdm-session; then
		echo >&2 "Could not enable the Steam session automatically."
		return 1
	fi
	return 0
}

_queue_openbox_notify() {
	mkdir -p "${HOME}/.config/gamebian"
	touch "${HOME}/.config/gamebian/pending-openbox-notify"
	export DISPLAY="${DISPLAY:-:0}"
	export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
	export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
	if [ -x /usr/share/gamebian/gamebian-openbox-notify.sh ]; then
		/usr/share/gamebian/gamebian-openbox-notify.sh --no-wait --force 2>/dev/null \
			|| true
	fi
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
echo "When you are done installing updates and signing in if prompted, quit Steam."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"${steam_bin}"
code=$?

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Steam launcher exited with code ${code}."
echo "Full log may also be at: ~/.steam/steam/logs/console-linux.txt"

mkdir -p "${HOME}/.config"

_steam_session_enabled=0
if _enable_steam_lightdm_session; then
	_steam_session_enabled=1
else
	read -r -p "$(printf '\nPress Enter after running the sudo command above, then we will retry... ')" || true
	if _enable_steam_lightdm_session; then
		_steam_session_enabled=1
	fi
fi

if [ "${_steam_session_enabled}" -eq 1 ] \
	|| [ -f /etc/lightdm/lightdm.conf.d/99-gamebian-autologin-steam.conf ]; then
	touch "${HOME}/.config/gamebian-firstboot-steam.run-finished"
	touch "${HOME}/.config/gamebian-firstboot-steam.done"
	echo ""
	echo "Steam session is enabled for the next boot."
	echo "Please reboot to continue your Steam/Gamescope session."
	_queue_openbox_notify
else
	echo ""
	echo "Steam session was not enabled. Run:" >&2
	echo "  sudo /usr/sbin/gamebian-enable-steam-lightdm-session" >&2
	echo "Then reboot when that succeeds." >&2
fi

read -r -p "$(printf '\nPress Enter to close this terminal.')" || true
