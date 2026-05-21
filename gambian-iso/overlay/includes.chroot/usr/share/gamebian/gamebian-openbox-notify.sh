#!/bin/sh
# Installed Openbox (Desktop session): welcome + Steam logout + gamebian-web tips.
# Only while Steam is not installed; after steam-installer is on disk this script exits immediately.

export DISPLAY="${DISPLAY:-:0}"
_uid="$(id -u)"

if [ -r /usr/share/gamebian/gamebian-steam-ready.sh ]; then
	# shellcheck disable=SC1091
	. /usr/share/gamebian/gamebian-steam-ready.sh
	gamebian_export_session_env
else
	export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games${PATH:+:$PATH}"
	export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${_uid}}"
	export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
fi

LOG="${XDG_CACHE_HOME:-${HOME}/.cache}/gamebian/openbox-notify.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

log() {
	printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)" "$*" >>"$LOG" 2>/dev/null || true
}

gamebian_ensure_notifyd() {
	_i=0
	while [ "${_i}" -lt 60 ]; do
		if ! pgrep -u "$(id -un)" -x xfce4-notifyd >/dev/null 2>&1; then
			command -v xfce4-notifyd >/dev/null 2>&1 \
				&& xfce4-notifyd >>"$LOG" 2>&1 &
		fi
		if [ -S "${XDG_RUNTIME_DIR}/bus" ] && pgrep -u "$(id -un)" -x xfce4-notifyd >/dev/null 2>&1; then
			return 0
		fi
		sleep 1
		_i=$((_i + 1))
	done
	log "notify daemon not ready (${_i}s)"
	return 1
}

gamebian_notify() {
	_title="$1"
	_body="$2"
	_urgency="${3:-normal}"
	if ! command -v notify-send >/dev/null 2>&1; then
		log "notify-send missing: ${_title}"
		return 1
	fi
	if notify-send -a Gamebian -u "${_urgency}" -t 45000 "${_title}" "${_body}" 2>>"$LOG"; then
		log "sent: ${_title}"
		return 0
	fi
	log "notify-send failed: ${_title}"
	return 1
}

gamebian_primary_ip() {
	_ip=""
	if command -v ip >/dev/null 2>&1; then
		_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}')"
	fi
	if [ -z "${_ip}" ] && command -v hostname >/dev/null 2>&1; then
		_ip="$(hostname -I 2>/dev/null | awk '{ print $1 }')"
	fi
	printf '%s' "${_ip}"
}

gamebian_show_desktop_welcome_notices() {
	gamebian_ensure_notifyd || true

	gamebian_notify "Welcome to the Gamebian desktop" \
		"You are in the Desktop (Openbox) session. Install and sign in to Steam here if needed." \
		normal

	gamebian_notify "Steam session" \
		'When Steam is ready, logout and choose "Steam" at the login screen (or reboot) for the gamescope kiosk.' \
		normal

	_ip="$(gamebian_primary_ip)"
	if [ -n "${_ip}" ] && [ "${_ip}" != "127.0.0.1" ]; then
		_web="Open http://127.0.0.1:8844 or http://${_ip}:8844 in a browser to install games, storefronts, and Flatpak images."
	else
		_web='Open http://127.0.0.1:8844 in a browser to install games, storefronts, and Flatpak images.'
	fi
	gamebian_notify "Gamebian web" "${_web}" normal
}

# --- main ---
grep -qw boot=live /proc/cmdline 2>/dev/null && exit 0

if command -v gamebian_steam_binary_present >/dev/null 2>&1 \
	&& gamebian_steam_binary_present; then
	log "skip: Steam installed"
	exit 0
fi

log "start DISPLAY=${DISPLAY}"
gamebian_show_desktop_welcome_notices
log "done"
