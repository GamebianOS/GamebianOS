#!/bin/sh
# Start nm-tray, blueman-applet, and optional Steam systray after lxpanel's tray plugin exists.
# Poll quickly (100ms); retry embed briefly instead of a long fixed sleep.

gamebian_tray_env() {
	export DISPLAY="${DISPLAY:-:0}"
	export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
	export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
	export GTK_ICON_THEME="${GTK_ICON_THEME:-Papirus}"
	if [ -r "${HOME}/.config/gamebian/desktop-theme" ]; then
		read -r _gb_theme < "${HOME}/.config/gamebian/desktop-theme" || _gb_theme=""
		[ -n "${_gb_theme}" ] && export GTK_THEME="${_gb_theme}"
	fi
	if [ -z "${GTK_THEME:-}" ]; then
		export GTK_THEME=gamebian-installed
	fi
	if grep -qw boot=live /proc/cmdline 2>/dev/null \
		&& [ ! -r "${HOME}/.config/gamebian/desktop-theme" ]; then
		export GTK_THEME=gamebian
	fi
	export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
	export QT_QPA_PLATFORMTHEME=gtk3
	export QT_AUTO_SCREEN_SCALE_FACTOR=0
	export QT_IM_MODULE=
}

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

gamebian_retry_tray_embed() {
	_pass=0
	while [ "${_pass}" -lt 6 ]; do
		sleep 0.5
		_pass=$((_pass + 1))
		gamebian_start_nm_tray
		if command -v blueman-applet >/dev/null 2>&1 \
			&& ! pgrep -f '[b]lueman-applet' >/dev/null 2>&1; then
			blueman-applet >/dev/null 2>&1 &
		fi
		if pgrep -x nm-tray >/dev/null 2>&1; then
			return 0
		fi
	done
	return 1
}

gamebian_tray_env

# Wait for NetworkManager dbus while lxpanel registers the systray host (overlap work).
gamebian_wait_for_nm &
_nm_wait_pid=$!

_wait_loops=80
if ! grep -qw boot=live /proc/cmdline 2>/dev/null; then
	_wait_loops=100
fi

# Warm nm-tray once lxpanel has had a moment to start (helps Qt + NM connect early).
(
	sleep 0.4
	wait "${_nm_wait_pid}" 2>/dev/null || gamebian_wait_for_nm
	gamebian_start_nm_tray
) &

if gamebian_wait_for_tray "${_wait_loops}"; then
	wait "${_nm_wait_pid}" 2>/dev/null || gamebian_wait_for_nm
	gamebian_start_tray_apps
	gamebian_retry_tray_embed
else
	wait "${_nm_wait_pid}" 2>/dev/null || true
	gamebian_start_tray_apps
	gamebian_retry_tray_embed
fi
