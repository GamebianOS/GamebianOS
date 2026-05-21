#!/bin/sh
# Installed Openbox: libnotify — reboot for gamescope, controller menu, gamebian-web (:8844).
# Usage: gamebian-openbox-notify.sh [--no-wait] [--force]

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
mkdir -p "$(dirname "$LOG")" "${HOME}/.config/gamebian" 2>/dev/null || true

log() {
	printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)" "$*" >>"$LOG" 2>/dev/null || true
}

gamebian_ensure_notifyd() {
	_i=0
	while [ "${_i}" -lt 120 ]; do
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
	log "notify daemon not ready (${_i}s) dbus=${DBUS_SESSION_BUS_ADDRESS}"
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
	if notify-send -a Gamebian -u "${_urgency}" -t 30000 "${_title}" "${_body}" 2>>"$LOG"; then
		log "sent: ${_title}"
		return 0
	fi
	log "notify-send failed (${DBUS_SESSION_BUS_ADDRESS}): ${_title}"
	return 1
}

gamebian_notify_reboot_critical() {
	_msg="$1"
	_ok=0
	gamebian_ensure_notifyd || true
	if gamebian_notify "Welcome to Gamebian! [Desktop session]" "${_msg}" critical; then
		_ok=1
	fi
	if [ "${_ok}" -eq 0 ] && command -v zenity >/dev/null 2>&1; then
		if zenity --info --title="Gamebian Steam" --width=440 --text="${_msg}" 2>>"$LOG"; then
			log "zenity reboot notice shown"
			_ok=1
		fi
	fi
	if [ "${_ok}" -eq 0 ] && command -v xmessage >/dev/null 2>&1; then
		if xmessage -center -buttons "OK:0" -default ok -title "Gamebian Steam" "${_msg}" 2>>"$LOG"; then
			log "xmessage reboot notice shown"
			_ok=1
		fi
	fi
	[ "${_ok}" -eq 1 ]
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

gamebian_show_openbox_notices() {
	_reboot_msg='Please reboot or logout and select "Steam" to continue your Steam/Gamescope session.'
	_reboot_ok=0
	if gamebian_notify_reboot_critical "${_reboot_msg}"; then
		_reboot_ok=1
	else
		log "reboot notice failed; leaving pending-openbox-notify"
		touch "${HOME}/.config/gamebian/pending-openbox-notify" 2>/dev/null || true
	fi

	_ip="$(gamebian_primary_ip)"
	_ctrl='Press Home (Guide / Mode) on your controller to open the Gamebian quick-launcher menu.'
	if [ -n "${_ip}" ]; then
		_web=$(printf 'Open http://%s:8844 in a browser to install games, third-party storefronts, and Flatpak images.' "${_ip}")
	else
		_web='Open http://<this computer'\''s IP>:8844 in a browser to install games, third-party storefronts, and Flatpak images.'
	fi
	gamebian_ensure_notifyd || true
	gamebian_notify "Gamebian controller" "${_ctrl}" normal
	gamebian_notify "Gamebian web" "${_web}" normal

	if [ "${_reboot_ok}" -eq 1 ]; then
		touch "${XDG_RUNTIME_DIR}/gamebian-openbox-notify.sent" 2>/dev/null || true
		rm -f "${HOME}/.config/gamebian/pending-openbox-notify" 2>/dev/null || true
	fi
	return "${_reboot_ok}"
}

# --- main (when executed, not sourced) ---
grep -qw boot=live /proc/cmdline 2>/dev/null && exit 0

_no_wait=0
_force=0
for _arg in "$@"; do
	case "${_arg}" in
		--no-wait|--now) _no_wait=1 ;;
		--force) _force=1 ;;
	esac
done

log "start DISPLAY=${DISPLAY} dbus=${DBUS_SESSION_BUS_ADDRESS} args=$* force=${_force}"

_gamebian_reboot_notice_ready() {
	if [ "${_force}" -eq 1 ]; then
		return 0
	fi
	if command -v gamebian_reboot_notice_ready_to_show >/dev/null 2>&1; then
		gamebian_reboot_notice_ready_to_show 0
		return $?
	fi
	gamebian_steam_kiosk_ready || return 1
	gamebian_steam_install_idle
}

if [ "${_no_wait}" -eq 0 ]; then
	_elapsed=0
	while [ "${_elapsed}" -lt 7200 ]; do
		if _gamebian_reboot_notice_ready; then
			log "reboot notice ready (elapsed=${_elapsed} force=${_force})"
			break
		fi
		if gamebian_steam_process_busy 2>/dev/null; then
			log "waiting: steam busy (${_elapsed}s) eligible=$(gamebian_reboot_notice_eligible 2>/dev/null; echo $?)"
		fi
		sleep 3
		_elapsed=$((_elapsed + 3))
		[ "${_elapsed}" -ge 7200 ] && exit 0
	done
fi

if ! _gamebian_reboot_notice_ready; then
	log "skip: eligible=$(gamebian_reboot_notice_eligible 2>/dev/null; echo $?) ready=$(gamebian_reboot_notice_ready_to_show 0 2>/dev/null; echo $?) idle=$(gamebian_steam_install_idle 2>/dev/null; echo $?) force=${_force}"
	exit 0
fi

_sent="${XDG_RUNTIME_DIR}/gamebian-openbox-notify.sent"
if [ -f "${_sent}" ] && [ "${_force}" -eq 0 ] && [ "${_no_wait}" -eq 0 ]; then
	log "skip: already sent this session"
	exit 0
fi

gamebian_show_openbox_notices || exit 1
log "done"
