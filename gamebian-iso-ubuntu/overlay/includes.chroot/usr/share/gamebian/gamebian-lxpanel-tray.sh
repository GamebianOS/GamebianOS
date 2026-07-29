#!/bin/sh
# Start network + Bluetooth tray icons after lxpanel's legacy XEmbed tray exists.

if [ -r /usr/share/gamebian/gamebian-openbox-session-env.sh ]; then
	# shellcheck disable=SC1091
	. /usr/share/gamebian/gamebian-openbox-session-env.sh
	gamebian_openbox_session_env
fi
if [ -x /usr/local/sbin/gamebian-install-tray-icons ]; then
	/usr/local/sbin/gamebian-install-tray-icons 2>/dev/null || true
fi
if [ -r /usr/share/gamebian/gamebian-steam-ready.sh ]; then
	# shellcheck disable=SC1091
	. /usr/share/gamebian/gamebian-steam-ready.sh
	if ! command -v gamebian_openbox_session_env >/dev/null 2>&1 \
		&& command -v gamebian_export_session_env >/dev/null 2>&1; then
		gamebian_export_session_env
	fi
fi

gamebian_tray_host_ready() {
	command -v xprop >/dev/null 2>&1 || return 1
	xprop -root 2>/dev/null | grep '^_NET_SYSTEM_TRAY_S' | grep -q 'WINDOW'
}

gamebian_wait_for_nm() {
	_n=0
	while [ "${_n}" -lt 50 ]; do
		if command -v nmcli >/dev/null 2>&1 && nmcli general status >/dev/null 2>&1; then
			return 0
		fi
		sleep 0.1
		_n=$((_n + 1))
	done
	return 1
}

gamebian_wait_for_tray() {
	_max="${1:-80}"
	_n=0
	while [ "${_n}" -lt "${_max}" ]; do
		if gamebian_tray_host_ready; then
			sleep 0.2
			return 0
		fi
		sleep 0.1
		_n=$((_n + 1))
	done
	return 1
}

gamebian_stop_legacy_nm() {
	pkill -x nm-tray 2>/dev/null || true
	pkill -x nm-applet 2>/dev/null || true
	pkill -f '[g]amebian-nm-status-icon.py' 2>/dev/null || true
}

gamebian_start_nm_tray() {
	gamebian_stop_legacy_nm
	if command -v gamebian_openbox_session_env >/dev/null 2>&1; then
		gamebian_openbox_session_env
	fi
	export XDG_CURRENT_DESKTOP=GNOME
	if [ -x /usr/local/bin/gamebian-nm-tray ]; then
		/usr/local/bin/gamebian-nm-tray >/dev/null 2>&1 &
		return 0
	fi
	if command -v nm-applet >/dev/null 2>&1; then
		nm-applet >/dev/null 2>&1 &
		return 0
	fi
	if command -v nm-tray >/dev/null 2>&1; then
		export XDG_CURRENT_DESKTOP=LXDE
		nm-tray >/dev/null 2>&1 &
	fi
	return 0
}

gamebian_start_blueman() {
	# blueman-tray is SNI-only; lxpanel needs the legacy GtkStatusIcon applet.
	pkill -f '[b]lueman-tray' 2>/dev/null || true
	if command -v blueman-applet >/dev/null 2>&1 \
		&& ! pgrep -f '[b]lueman-applet' >/dev/null 2>&1; then
		export XDG_CURRENT_DESKTOP=LXDE
		blueman-applet >/dev/null 2>&1 &
	fi
	return 0
}

gamebian_start_tray_apps() {
	gamebian_start_nm_tray
	gamebian_start_blueman
	if ! grep -qw boot=live /proc/cmdline 2>/dev/null \
		&& command -v gamebian_steam_logged_in >/dev/null 2>&1 \
		&& gamebian_steam_logged_in 2>/dev/null \
		&& [ -f "${HOME}/.config/gamebian-firstboot-steam.done" ] \
		&& [ ! -f "${HOME}/.config/gamebian/switch-to-openbox" ] \
		&& command -v steam >/dev/null 2>&1 \
		&& ! pgrep -u "$(id -un)" -x steam >/dev/null 2>&1 \
		&& ! pgrep -u "$(id -un)" -x gamescope >/dev/null 2>&1; then
		steam -silent >/dev/null 2>&1 &
	fi
	return 0
}

gamebian_refresh_tray_icons() {
	if command -v gamebian_openbox_session_env >/dev/null 2>&1; then
		gamebian_openbox_session_env
	fi
	sleep 0.5
	gamebian_start_nm_tray
	gamebian_start_blueman
}

gamebian_wait_for_nm &
_nm_wait_pid=$!

_wait_loops=80
if ! grep -qw boot=live /proc/cmdline 2>/dev/null; then
	_wait_loops=100
fi

if gamebian_wait_for_tray "${_wait_loops}"; then
	wait "${_nm_wait_pid}" 2>/dev/null || gamebian_wait_for_nm
	sleep 0.35
	gamebian_start_tray_apps
	gamebian_refresh_tray_icons
else
	wait "${_nm_wait_pid}" 2>/dev/null || true
	gamebian_start_tray_apps
fi
exit 0
