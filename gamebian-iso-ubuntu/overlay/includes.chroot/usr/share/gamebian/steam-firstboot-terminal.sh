#!/usr/bin/env bash
# First disk-login: run Steam, enable Steam autologin, show reboot notifications.

set +e

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games${PATH:+:$PATH}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Steam setup — this can take several minutes"
echo ""
echo "  • Installing steam-installer (apt, multiverse) may take a few minutes."
echo "  • After Steam starts, it often downloads updates in the background."
echo "  • Keep this window open and watch the output below."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -r /usr/share/gamebian/gamebian-steam-ready.sh ]; then
	# shellcheck disable=SC1091
	. /usr/share/gamebian/gamebian-steam-ready.sh
fi

_enable_steam_lightdm_session() {
	if gamebian_finish_steam_firstboot; then
		return 0
	fi
	echo >&2 ""
	echo >&2 "To boot into the Steam (gamescope) session you need sudo once:"
	echo >&2 "  sudo /usr/sbin/gamebian-enable-steam-lightdm-session"
	echo >&2 "  sudo gamebian-fix-steam-boot"
	echo >&2 ""
	return 1
}

_queue_openbox_notify() {
	export DISPLAY="${DISPLAY:-:0}"
	export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
	export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
	if [ -x /usr/share/gamebian/gamebian-openbox-notify.sh ]; then
		/usr/share/gamebian/gamebian-openbox-notify.sh --no-wait --desktop-session 2>/dev/null \
			|| true
	fi
}

_find_steam_bin() {
	steam_bin=""
	for _c in /usr/bin/steam /usr/local/bin/steam /usr/games/steam; do
		if [ -x "${_c}" ]; then
			steam_bin="${_c}"
			return 0
		fi
	done
	return 1
}

_try_install_steam() {
	if _find_steam_bin; then
		return 0
	fi
	echo "Steam is not installed. Installing steam-installer (i386 + multiverse)…"
	echo "This may take several minutes — apt output will appear below."
	echo ""

	if [ "$(id -u)" -eq 0 ]; then
		if [ -x /usr/local/sbin/gamebian-install-steam ]; then
			/usr/local/sbin/gamebian-install-steam && _find_steam_bin && return 0
		fi
	else
		if sudo -n /usr/local/sbin/gamebian-install-steam 2>/dev/null; then
			_find_steam_bin && return 0
		fi
		echo "Enter your password to install steam-installer:"
		if sudo /usr/local/sbin/gamebian-install-steam 2>/dev/null; then
			_find_steam_bin && return 0
		fi
	fi

	# Fallback when overlay helper is not on disk yet (older install / VM).
	_as_root() {
		if [ "$(id -u)" -eq 0 ]; then
			"$@"
		else
			sudo "$@"
		fi
	}
	if [ -r /usr/share/gamebian/ensure-apt-gaming-repos.sh ]; then
		_as_root sh -c '. /usr/share/gamebian/ensure-apt-gaming-repos.sh
			ensure_apt_i386
			ensure_apt_gaming_repos'
	fi
	if ! _as_root dpkg --print-foreign-architectures 2>/dev/null | grep -qx i386; then
		_as_root dpkg --add-architecture i386
	fi
	echo "Running apt update and steam-installer…"
	if _as_root apt-get update \
		&& _as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y steam-installer; then
		if [ -x /usr/games/steam ] && [ ! -e /usr/bin/steam ]; then
			_as_root ln -sf ../games/steam /usr/bin/steam 2>/dev/null || true
		fi
		_find_steam_bin && return 0
	fi
	return 1
}

_find_steam_bin || _try_install_steam

if [ -z "${steam_bin}" ]; then
	echo ""
	echo "Steam install failed." >&2
	echo "Repair apt (multiverse / i386) and retry:" >&2
	echo "  sudo gamebian-install-steam" >&2
	echo "Or manually:" >&2
	echo "  sudo dpkg --add-architecture i386 && sudo apt update" >&2
	echo "  sudo apt install -y steam-installer" >&2
	read -r -p "$(printf '\nPress Enter to close.')" || true
	exit 1
fi

if [ -x /usr/share/gamebian/gamebian-steam-reboot-notify-watcher.sh ]; then
	/usr/share/gamebian/gamebian-steam-reboot-notify-watcher.sh &
fi

echo "Starting Steam… output below is from Valve’s launcher script."
echo "Steam may sit in the background while it downloads updates — that is normal."
echo "Install updates if prompted, then sign in to your Steam account and quit Steam."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"${steam_bin}"
code=$?

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Steam launcher exited with code ${code}."
echo "Full log may also be at: ~/.steam/steam/logs/console-linux.txt"

mkdir -p "${HOME}/.config"

_steam_session_enabled=0
if gamebian_have_loginusers_vdf 2>/dev/null; then
	if _enable_steam_lightdm_session; then
		_steam_session_enabled=1
	else
		read -r -p "$(printf '\nPress Enter after running the sudo command above, then we will retry... ')" || true
		if _enable_steam_lightdm_session; then
			_steam_session_enabled=1
		fi
	fi
fi

if [ "${_steam_session_enabled}" -eq 1 ]; then
	echo ""
	echo "Steam is installed and you are signed in."
	echo "Reboot or logout to enter your Steam/Gamescope session."
	_queue_openbox_notify
elif gamebian_have_loginusers_vdf 2>/dev/null; then
	echo ""
	echo "Signed in to Steam, but the Steam session could not be enabled. Run:" >&2
	echo "  sudo /usr/sbin/gamebian-enable-steam-lightdm-session" >&2
else
	echo ""
	echo "Sign in to Steam in this window, then quit Steam and run this setup again" >&2
	echo "  (or reboot after you see the desktop notification)." >&2
fi

read -r -p "$(printf '\nPress Enter to close this terminal.')" || true
