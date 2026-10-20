# Shared by gamebian-steam-gamescope-session and gamebian-steam-bigpicture.
# Steam's child processes often lack GAMEBIAN_GAMESCOPE_SESSION / DESKTOP_SESSION; use a marker file.

GAMEBIAN_KIOSK_MARKER="${HOME}/.config/gamebian/in-gamescope-kiosk-session"
GAMEBIAN_REQUEST_GAMESCOPE_KIOSK="${HOME}/.config/gamebian/request-gamescope-kiosk"

gamebian_kiosk_marker_set() {
	mkdir -p "${HOME}/.config/gamebian"
	: >"${GAMEBIAN_KIOSK_MARKER}"
	rm -f "${HOME}/.config/gamebian/switch-to-openbox" \
		"${HOME}/.config/gamebian/kiosk-openbox-handoff" \
		"${HOME}/.config/gamebian/prefer-openbox-desktop" 2>/dev/null || true
}

gamebian_kiosk_marker_clear() {
	rm -f "${GAMEBIAN_KIOSK_MARKER}" \
		"${HOME}/.config/gamebian/switch-to-openbox" \
		"${HOME}/.config/gamebian/kiosk-openbox-handoff" 2>/dev/null || true
}

gamebian_gamescope_session_supervisor_running() {
	pgrep -u "$(id -un)" -f '[g]amebian-steam-gamescope-session' >/dev/null 2>&1
}

gamebian_request_gamescope_kiosk() {
	mkdir -p "${HOME}/.config/gamebian"
	: >"${GAMEBIAN_REQUEST_GAMESCOPE_KIOSK}"
}

gamebian_request_gamescope_kiosk_clear() {
	rm -f "${GAMEBIAN_REQUEST_GAMESCOPE_KIOSK}" 2>/dev/null || true
}

gamebian_request_gamescope_kiosk_pending() {
	[ -f "${GAMEBIAN_REQUEST_GAMESCOPE_KIOSK}" ]
}

# Stop listening for Guide/Home while gamescope+Steam own the gamepad.
gamebian_controller_menu_pause() {
	_u="$(id -un)"
	if command -v systemctl >/dev/null 2>&1; then
		systemctl --user stop gamebian-controller-menu.service 2>/dev/null || true
	fi
	pkill -u "$_u" -TERM -f '[g]amebian-controller-menu' 2>/dev/null || true
	sleep 0.2
	pkill -u "$_u" -KILL -f '[g]amebian-controller-menu' 2>/dev/null || true
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
