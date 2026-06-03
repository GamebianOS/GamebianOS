# Shared by gamebian-steam-gamescope-session, gamebian-steam-switch-to-desktop, gamebian-steam-bigpicture.
# Steam's child processes often lack GAMEBIAN_GAMESCOPE_SESSION / DESKTOP_SESSION; use a marker file.

GAMEBIAN_KIOSK_MARKER="${HOME}/.config/gamebian/in-gamescope-kiosk-session"
GAMEBIAN_SWITCH_OPENBOX="${HOME}/.config/gamebian/switch-to-openbox"
GAMEBIAN_KIOSK_OPENBOX_HANDOFF="${HOME}/.config/gamebian/kiosk-openbox-handoff"

gamebian_kiosk_marker_set() {
	mkdir -p "${HOME}/.config/gamebian"
	: >"${GAMEBIAN_KIOSK_MARKER}"
}

gamebian_kiosk_marker_clear() {
	rm -f "${GAMEBIAN_KIOSK_MARKER}" "${GAMEBIAN_SWITCH_OPENBOX}" \
		"${GAMEBIAN_KIOSK_OPENBOX_HANDOFF}" 2>/dev/null || true
}

gamebian_kiosk_openbox_handoff_set() {
	mkdir -p "${HOME}/.config/gamebian"
	: >"${GAMEBIAN_KIOSK_OPENBOX_HANDOFF}"
}

gamebian_kiosk_openbox_handoff_clear() {
	rm -f "${GAMEBIAN_KIOSK_OPENBOX_HANDOFF}" 2>/dev/null || true
}

# True when Openbox is the in-session desktop after Switch to Desktop (same LightDM login).
gamebian_kiosk_openbox_handoff_active() {
	[ -f "${GAMEBIAN_KIOSK_OPENBOX_HANDOFF}" ]
}

gamebian_gamescope_session_supervisor_running() {
	pgrep -u "$(id -un)" -f '[g]amebian-steam-gamescope-session' >/dev/null 2>&1
}

gamebian_request_switch_to_openbox() {
	mkdir -p "${HOME}/.config/gamebian"
	: >"${GAMEBIAN_SWITCH_OPENBOX}"
}

# Stop gamescope kiosk + Steam (including gamescopereaper children).
gamebian_kill_steam_kiosk_tree() {
	_u="$(id -un)"
	pkill -u "$_u" -TERM -f 'gamescopereaper' 2>/dev/null || true
	pkill -u "$_u" -TERM -f '/usr/games/gamescope' 2>/dev/null || true
	pkill -u "$_u" -TERM -x gamescope 2>/dev/null || true
	pkill -u "$_u" -TERM -x steam 2>/dev/null || true
	sleep 0.4
	pkill -u "$_u" -KILL -f 'gamescopereaper' 2>/dev/null || true
	pkill -u "$_u" -KILL -f '/usr/games/gamescope' 2>/dev/null || true
	pkill -u "$_u" -KILL -x gamescope 2>/dev/null || true
	pkill -u "$_u" -KILL -x steam 2>/dev/null || true
}

gamebian_wait_steam_kiosk_stopped() {
	_u="$(id -un)"
	_i=0
	while [ "${_i}" -lt 80 ]; do
		if ! pgrep -u "$_u" -x gamescope >/dev/null 2>&1 \
			&& ! pgrep -u "$_u" -f 'gamescopereaper' >/dev/null 2>&1 \
			&& ! pgrep -u "$_u" -x steam >/dev/null 2>&1; then
			return 0
		fi
		sleep 0.15
		_i=$((_i + 1))
	done
	return 1
}

# Replace gamescope kiosk with Openbox on the current LightDM X session (same login).
gamebian_handoff_to_openbox_desktop() {
	_u="$(id -un)"
	_log="${XDG_CACHE_HOME:-${HOME}/.cache}/gamebian/handoff-openbox.log"
	mkdir -p "$(dirname "$_log")" 2>/dev/null || true
	_ts="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)"
	printf '%s handoff start (user=%s display=%s)\n' "$_ts" "$_u" "${DISPLAY:-unset}" >>"$_log" 2>/dev/null || true

	gamebian_kill_steam_kiosk_tree
	gamebian_wait_steam_kiosk_stopped || gamebian_kill_steam_kiosk_tree

	rm -f "${GAMEBIAN_SWITCH_OPENBOX}" "${GAMEBIAN_KIOSK_MARKER}" 2>/dev/null || true
	gamebian_kiosk_openbox_handoff_set
	unset GAMEBIAN_GAMESCOPE_SESSION
	export DISPLAY="${DISPLAY:-:0}"
	export DESKTOP_SESSION=gamebian-desktop
	export XDG_SESSION_DESKTOP=gamebian-desktop
	# Qt nm-tray / lxpanel systray need a known desktop id (custom names → white icon squares).
	export XDG_CURRENT_DESKTOP=LXDE

	if pgrep -u "$_u" -x openbox >/dev/null 2>&1; then
		printf '%s openbox already running\n' "$_ts" >>"$_log" 2>/dev/null || true
		gamebian_kiosk_openbox_handoff_set
		return 0
	fi

	# Do not exec: gamebian-steam-gamescope-session must keep supervising (desktop → Steam).
	printf '%s start openbox-session (background, same LightDM login)\n' "$_ts" >>"$_log" 2>/dev/null || true
	gamebian_kiosk_openbox_handoff_set
	/usr/bin/openbox-session >>"$_log" 2>&1 &
	return 0
}
