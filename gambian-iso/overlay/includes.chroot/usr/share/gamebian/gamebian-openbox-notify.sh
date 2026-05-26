#!/bin/sh
# Installed Openbox desktop notifications — shown every time the desktop session starts.

export DISPLAY="${DISPLAY:-:0}"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games${PATH:+:$PATH}"
_uid="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${_uid}}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"

LOG="${XDG_CACHE_HOME:-${HOME}/.cache}/gamebian/openbox-notify.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

log() {
	printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)" "$*" >>"$LOG" 2>/dev/null || true
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
	log "notify-send failed (${DBUS_SESSION_BUS_ADDRESS}): ${_title}"
	return 1
}

gamebian_wait_for_notifyd() {
	_i=0
	while [ "${_i}" -lt 120 ]; do
		if ! pgrep -x xfce4-notifyd >/dev/null 2>&1; then
			if command -v xfce4-notifyd >/dev/null 2>&1; then
				xfce4-notifyd >/dev/null 2>&1 &
			fi
		fi
		if [ -S "${XDG_RUNTIME_DIR}/bus" ] && pgrep -x xfce4-notifyd >/dev/null 2>&1; then
			return 0
		fi
		sleep 1
		_i=$((_i + 1))
	done
	log "notify daemon not ready (${_i}s) dbus=${DBUS_SESSION_BUS_ADDRESS}"
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

# All three notices, every Openbox session (first boot and return visits).
gamebian_show_openbox_session_notices() {
	gamebian_wait_for_notifyd || true

	gamebian_notify "Welcome to Gamebian! [Desktop session]" \
		'Desktop mode — use the Steam setup terminal to install Steam and sign in if you have not already.' \
		normal

	_ip="$(gamebian_primary_ip)"
	if [ -n "${_ip}" ]; then
		_web=$(printf 'Visit http://127.0.0.1:8844 or http://%s:8844 in a browser to upload games, storefronts, and Flatpak images.' "${_ip}")
	else
		_web='Visit http://127.0.0.1:8844 in a browser to upload games, storefronts, and Flatpak images.'
	fi
	gamebian_notify "Gamebian web" "${_web}" normal

	if gamebian_steam_logged_in 2>/dev/null; then
		_reboot='You are signed in to Steam. Please logout or reboot to load your Steam/Gamescope session.'
	else
		_reboot='After Steam is installed and you are signed in, logout or reboot to load your Steam/Gamescope session.'
	fi
	gamebian_notify "Steam session" "${_reboot}" critical

	log "openbox session notices done"
}

if grep -qw boot=live /proc/cmdline 2>/dev/null; then
	exit 0
fi

if [ -r /usr/share/gamebian/gamebian-steam-ready.sh ]; then
	# shellcheck disable=SC1091
	. /usr/share/gamebian/gamebian-steam-ready.sh
fi

_show=0
case "${1:-} ${2:-}" in
	*--desktop-session*|*--all*|*--welcome*|*--reboot-hint*|*--steam-ready*|*--force*)
		_show=1
		;;
esac

log "start show=${_show} DISPLAY=${DISPLAY} args=${*:-}"

if [ "${_show}" -eq 1 ]; then
	gamebian_show_openbox_session_notices
fi

rm -f "${HOME}/.config/gamebian/pending-openbox-notify" 2>/dev/null || true
exit 0
