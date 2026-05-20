#!/bin/sh
# Installed Openbox: libnotify only (no dialog). Reboot + controller + gamebian-web tips.

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
	if notify-send -a Gamebian -u "${_urgency}" -t 30000 "${_title}" "${_body}" 2>>"$LOG"; then
		log "sent: ${_title}"
		return 0
	fi
	log "notify-send failed: ${_title}"
	return 1
}

gamebian_wait_for_notifyd() {
	_i=0
	while [ "${_i}" -lt 90 ]; do
		if ! pgrep -x xfce4-notifyd >/dev/null 2>&1; then
			if command -v xfce4-notifyd >/dev/null 2>&1; then
				xfce4-notifyd >/dev/null 2>&1 &
			fi
		fi
		if pgrep -x xfce4-notifyd >/dev/null 2>&1 && [ -S "${XDG_RUNTIME_DIR}/bus" ]; then
			return 0
		fi
		sleep 1
		_i=$((_i + 1))
	done
	log "notify daemon not ready after ${_i}s"
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

if grep -qw boot=live /proc/cmdline 2>/dev/null; then
	exit 0
fi

if [ -r /usr/share/gamebian/gamebian-steam-login-check.sh ]; then
	# shellcheck disable=SC1091
	. /usr/share/gamebian/gamebian-steam-login-check.sh
fi
if [ -r /usr/share/gamebian/gamebian-steam-ready.sh ]; then
	# shellcheck disable=SC1091
	. /usr/share/gamebian/gamebian-steam-ready.sh
fi

_no_wait=0
case "${1:-}" in
	--no-wait|--now) _no_wait=1 ;;
esac

log "start DISPLAY=${DISPLAY} user=$(id -un) arg=${1:-}"

_wait_for_steam_ready() {
	_elapsed=0
	_max=7200
	while [ "${_elapsed}" -lt "${_max}" ]; do
		if gamebian_steam_needs_reboot_notice && gamebian_steam_install_idle; then
			log "steam ready (elapsed=${_elapsed})"
			return 0
		fi
		if gamebian_steam_process_busy; then
			log "waiting: steam still busy (${_elapsed}s)"
		fi
		sleep 3
		_elapsed=$((_elapsed + 3))
	done
	log "timeout waiting for steam"
	return 1
}

if [ "${_no_wait}" -eq 0 ]; then
	_wait_for_steam_ready || exit 0
fi

if ! gamebian_steam_needs_reboot_notice || ! gamebian_steam_install_idle; then
	log "skip: kiosk_ready=$(gamebian_steam_kiosk_ready 2>/dev/null; echo $?) idle=$(gamebian_steam_install_idle 2>/dev/null; echo $?)"
	exit 0
fi

gamebian_wait_for_notifyd || true

_sent="${XDG_RUNTIME_DIR}/gamebian-openbox-notify.sent"
if [ -f "${_sent}" ] && [ "${_no_wait}" -eq 0 ]; then
	log "skip: already sent this session"
	exit 0
fi

gamebian_notify "Please reboot" \
	'Please reboot to continue your Steam/Gamescope session.' \
	critical

_ip="$(gamebian_primary_ip)"
_ctrl='Press Home (Guide / Mode) on your controller to open the Gamebian quick-launcher menu.'
if [ -n "${_ip}" ]; then
	_web=$(printf 'Open http://%s:8844 in a browser to install games, third-party storefronts, and Flatpak images.' "${_ip}")
else
	_web='Open http://<this computer'\''s IP>:8844 in a browser to install games, third-party storefronts, and Flatpak images.'
fi

gamebian_notify "Gamebian controller" "${_ctrl}" normal
gamebian_notify "Gamebian web" "${_web}" normal

touch "${_sent}" 2>/dev/null || true
log "done"
