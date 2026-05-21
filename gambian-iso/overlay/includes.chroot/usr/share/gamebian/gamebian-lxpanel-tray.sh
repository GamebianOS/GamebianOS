#!/bin/sh
# Start nm-tray, blueman-applet, and optional Steam systray after lxpanel's tray plugin exists.

if [ -r /usr/share/gamebian/gamebian-openbox-session-env.sh ]; then
	# shellcheck disable=SC1091
	. /usr/share/gamebian/gamebian-openbox-session-env.sh
	gamebian_openbox_session_env
elif [ -r /usr/share/gamebian/gamebian-steam-ready.sh ]; then
	# shellcheck disable=SC1091
	. /usr/share/gamebian/gamebian-steam-ready.sh
	gamebian_export_session_env
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

gamebian_start_nm_tray() {
	if command -v nm-tray >/dev/null 2>&1 && ! pgrep -x nm-tray >/dev/null 2>&1; then
		nm-tray >/dev/null 2>&1 &
		return 0
	fi
	return 1
}

gamebian_restart_nm_tray() {
	if ! command -v nm-tray >/dev/null 2>&1; then
		return 1
	fi
	pkill -x nm-tray 2>/dev/null || true
	sleep 0.25
	nm-tray >/dev/null 2>&1 &
	return 0
}

gamebian_start_tray_apps() {
	_started=0
	gamebian_start_nm_tray && _started=1
	if command -v blueman-applet >/dev/null 2>&1; then
		if ! pgrep -f '[b]lueman-applet' >/dev/null 2>&1; then
			blueman-applet >/dev/null 2>&1 &
			_started=1
		fi
	fi
	if ! grep -qw boot=live /proc/cmdline 2>/dev/null \
		&& [ -f "${HOME}/.config/gamebian-firstboot-steam.done" ] \
		&& command -v steam >/dev/null 2>&1 \
		&& ! pgrep -u "$(id -un)" -x steam >/dev/null 2>&1 \
		&& ! pgrep -u "$(id -un)" -x gamescope >/dev/null 2>&1; then
		steam -silent >/dev/null 2>&1 &
		_started=1
	fi
	return "${_started}"
}

gamebian_refresh_tray_icons() {
	# Installed disk: early nm-tray warm-up can embed before icons resolve → white squares.
	if grep -qw boot=live /proc/cmdline 2>/dev/null; then
		return 0
	fi
	gamebian_restart_nm_tray
	if command -v blueman-applet >/dev/null 2>&1; then
		pkill -f '[b]lueman-applet' 2>/dev/null || true
		sleep 0.15
		blueman-applet >/dev/null 2>&1 &
	fi
}

gamebian_wait_for_nm &
_nm_wait_pid=$!

_wait_loops=80
if ! grep -qw boot=live /proc/cmdline 2>/dev/null; then
	_wait_loops=100
fi

if gamebian_wait_for_tray "${_wait_loops}"; then
	wait "${_nm_wait_pid}" 2>/dev/null || gamebian_wait_for_nm
	gamebian_start_tray_apps
	gamebian_refresh_tray_icons
else
	wait "${_nm_wait_pid}" 2>/dev/null || true
	gamebian_start_tray_apps
fi
