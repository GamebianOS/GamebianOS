# shellcheck shell=sh
# Resolve and apply Openbox desktop wallpaper (feh).

CUSTOM_WALLPAPER_FILE="${HOME}/.config/gamebian/custom-wallpaper"
DESKTOP_THEME_FILE="${HOME}/.config/gamebian/desktop-theme"
INSTALLED_WALLPAPER_DIR="/usr/share/backgrounds/gamebian-installed"

gamebian_wallpaper_apply() {
	_img="$1"
	[ -n "${_img}" ] && [ -r "${_img}" ] || return 1
	export DISPLAY="${DISPLAY:-:0}"
	if command -v feh >/dev/null 2>&1; then
		feh --no-fehbg --bg-fill "${_img}" &
		return 0
	fi
	return 1
}

gamebian_wallpaper_set_custom() {
	_img="$1"
	[ -n "${_img}" ] && [ -r "${_img}" ] || return 1
	mkdir -p "${HOME}/.config/gamebian"
	printf '%s\n' "${_img}" >"${CUSTOM_WALLPAPER_FILE}"
	gamebian_wallpaper_apply "${_img}"
}

gamebian_wallpaper_clear_custom() {
	rm -f "${CUSTOM_WALLPAPER_FILE}" 2>/dev/null || true
}

gamebian_wallpaper_resolve() {
	if [ -r "${CUSTOM_WALLPAPER_FILE}" ]; then
		_custom=""
		read -r _custom <"${CUSTOM_WALLPAPER_FILE}" 2>/dev/null || _custom=""
		if [ -n "${_custom}" ] && [ -r "${_custom}" ]; then
			printf '%s' "${_custom}"
			return 0
		fi
	fi

	if ! grep -qw boot=live /proc/cmdline 2>/dev/null; then
		_theme="gamebian-installed"
		if [ -r "${DESKTOP_THEME_FILE}" ]; then
			_theme="$(head -n1 "${DESKTOP_THEME_FILE}" | tr -d '[:space:]')"
		fi
		case "${_theme}" in
			green|yellow|blue|red|black|purple)
				if [ -r "${INSTALLED_WALLPAPER_DIR}/${_theme}.png" ]; then
					printf '%s' "${INSTALLED_WALLPAPER_DIR}/${_theme}.png"
					return 0
				fi
				;;
		esac
		if [ -r "${INSTALLED_WALLPAPER_DIR}/background.png" ]; then
			printf '%s' "${INSTALLED_WALLPAPER_DIR}/background.png"
			return 0
		fi
	fi

	if [ -r "${HOME}/.local/share/gamebian/background.png" ]; then
		printf '%s' "${HOME}/.local/share/gamebian/background.png"
		return 0
	fi
	return 1
}

gamebian_wallpaper_apply_resolved() {
	_wall=""
	_wall="$(gamebian_wallpaper_resolve)" || return 1
	gamebian_wallpaper_apply "${_wall}"
}
