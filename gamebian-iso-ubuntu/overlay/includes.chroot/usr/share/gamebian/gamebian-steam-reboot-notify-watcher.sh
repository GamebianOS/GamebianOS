#!/bin/sh
# When the user signs in to Steam, enable the gamescope session and show the reboot hint.

export DISPLAY="${DISPLAY:-:0}"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games${PATH:+:$PATH}"
_uid="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${_uid}}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"

LOG="${XDG_CACHE_HOME:-${HOME}/.cache}/gamebian/steam-reboot-notify-watcher.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

log() {
	printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)" "$*" >>"$LOG" 2>/dev/null || true
}

grep -qw boot=live /proc/cmdline 2>/dev/null && exit 0

if [ -r /usr/share/gamebian/gamebian-steam-ready.sh ]; then
	# shellcheck disable=SC1091
	. /usr/share/gamebian/gamebian-steam-ready.sh
else
	exit 0
fi

if gamebian_steam_logged_in 2>/dev/null; then
	log "already logged in to Steam"
	if gamebian_finish_steam_firstboot 2>>"$LOG"; then
		log "enabled Steam session"
	fi
	if [ -x /usr/share/gamebian/gamebian-openbox-notify.sh ]; then
		/usr/share/gamebian/gamebian-openbox-notify.sh --no-wait --desktop-session >>"$LOG" 2>&1 || true
	fi
	exit 0
fi

log "watching for Steam sign-in (loginusers.vdf)"

_elapsed=0
_max=7200
while [ "${_elapsed}" -lt "${_max}" ]; do
	if gamebian_steam_logged_in 2>/dev/null; then
		log "Steam sign-in detected (elapsed=${_elapsed}s)"
		if gamebian_finish_steam_firstboot 2>>"$LOG"; then
			log "enabled Steam session + markers"
		else
			log "could not enable Steam session (sudo?)"
		fi
		if [ -x /usr/share/gamebian/gamebian-openbox-notify.sh ]; then
			/usr/share/gamebian/gamebian-openbox-notify.sh --no-wait --desktop-session >>"$LOG" 2>&1 \
				|| true
		fi
		exit 0
	fi
	if gamebian_steam_bootstrap_pending 2>/dev/null; then
		log "Steam bootstrap in progress (${_elapsed}s)"
	fi
	sleep 2
	_elapsed=$((_elapsed + 2))
done

log "timeout waiting for Steam sign-in"
exit 1
