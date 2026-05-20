# Shared by gamebian-steam-gamescope-session, gamebian-steam-switch-to-desktop, gamebian-steam-bigpicture.
# Steam's child processes often lack GAMEBIAN_GAMESCOPE_SESSION / DESKTOP_SESSION; use a marker file.

GAMEBIAN_KIOSK_MARKER="${HOME}/.config/gamebian/in-gamescope-kiosk-session"
GAMEBIAN_SWITCH_OPENBOX="${HOME}/.config/gamebian/switch-to-openbox"
GAMEBIAN_LIGHTDM_GAMESCOPE="/etc/lightdm/lightdm.conf.d/99-gamebian-steam-session.conf"

gamebian_kiosk_marker_set() {
	mkdir -p "${HOME}/.config/gamebian"
	: >"${GAMEBIAN_KIOSK_MARKER}"
}

gamebian_kiosk_marker_clear() {
	rm -f "${GAMEBIAN_KIOSK_MARKER}" "${GAMEBIAN_SWITCH_OPENBOX}" 2>/dev/null || true
}

# True when this login is the LightDM gamescope kiosk (not only when env vars are set).
gamebian_in_steam_kiosk_session() {
	case "${GAMEBIAN_GAMESCOPE_SESSION:-}${DESKTOP_SESSION:-}${XDG_SESSION_DESKTOP:-}" in
		*gamebian-steam-gamescope*) return 0 ;;
	esac
	if [ -f "${GAMEBIAN_KIOSK_MARKER}" ]; then
		return 0
	fi
	if [ -f "${GAMEBIAN_LIGHTDM_GAMESCOPE}" ] \
		&& grep -q 'autologin-session=gamebian-steam-gamescope' "${GAMEBIAN_LIGHTDM_GAMESCOPE}" 2>/dev/null; then
		return 0
	fi
	if pgrep -u "$(id -un)" -x gamescope >/dev/null 2>&1 \
		&& ! pgrep -u "$(id -un)" -x openbox >/dev/null 2>&1; then
		return 0
	fi
	return 1
}

gamebian_request_switch_to_openbox() {
	mkdir -p "${HOME}/.config/gamebian"
	: >"${GAMEBIAN_SWITCH_OPENBOX}"
}

gamebian_prefer_openbox_at_boot() {
	mkdir -p "${HOME}/.config/gamebian"
	: >"${HOME}/.config/gamebian/prefer-openbox-desktop"
}

gamebian_clear_openbox_boot_preference() {
	rm -f "${HOME}/.config/gamebian/prefer-openbox-desktop" 2>/dev/null || true
}
