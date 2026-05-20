#!/bin/sh
# Start nm-tray, blueman-applet, and optional Steam systray after lxpanel's tray plugin exists.
# Installed-disk boots are slower than the live squashfs; a single short delay often loses the race.

gamebian_tray_env() {
	export DISPLAY="${DISPLAY:-:0}"
	export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
	export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
	export GTK_ICON_THEME="${GTK_ICON_THEME:-Papirus}"
	export GTK_THEME="${GTK_THEME:-gamebian-installed}"
	if grep -qw boot=live /proc/cmdline 2>/dev/null; then
		export GTK_THEME=gamebian
	fi
	export QT_QPA_PLATFORMTHEME=gtk3
	export QT_AUTO_SCREEN_SCALE_FACTOR=0
	export QT_IM_MODULE=
}

gamebian_wait_for_tray() {
	_max="${1:-200}"
	_n=0
	if ! command -v xprop >/dev/null 2>&1; then
		sleep 4
		return 0
	fi
	while [ "${_n}" -lt "${_max}" ]; do
		if xprop -root 2>/dev/null | grep '^_NET_SYSTEM_TRAY_S' | grep -q 'WINDOW'; then
			sleep 0.6
			return 0
		fi
		sleep 0.25
		_n=$((_n + 1))
	done
	return 1
}

gamebian_start_tray_apps() {
	_started=0
	if command -v nm-tray >/dev/null 2>&1; then
		if ! pgrep -x nm-tray >/dev/null 2>&1; then
			nm-tray >/dev/null 2>&1 &
			_started=1
		fi
	fi
	if command -v blueman-applet >/dev/null 2>&1; then
		if ! pgrep -f '[b]lueman-applet' >/dev/null 2>&1; then
			blueman-applet >/dev/null 2>&1 &
			_started=1
		fi
	fi
	# Openbox desktop: Steam systray (Wi‑Fi/BT are nm-tray + blueman). Skip live ISO / gamescope kiosk.
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

gamebian_tray_env
_wait_loops=200
if ! grep -qw boot=live /proc/cmdline 2>/dev/null; then
	_wait_loops=240
fi

if gamebian_wait_for_tray "${_wait_loops}"; then
	gamebian_start_tray_apps
	sleep 8
	# Second pass: applets started before the tray existed never embed; restart if missing.
	if command -v nm-tray >/dev/null 2>&1 && ! pgrep -x nm-tray >/dev/null 2>&1; then
		nm-tray >/dev/null 2>&1 &
	fi
	if command -v blueman-applet >/dev/null 2>&1 && ! pgrep -f '[b]lueman-applet' >/dev/null 2>&1; then
		blueman-applet >/dev/null 2>&1 &
	fi
else
	# Tray never appeared — still try (icons may show after lxpanel catches up).
	gamebian_start_tray_apps
fi
