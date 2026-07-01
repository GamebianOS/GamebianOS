# shellcheck shell=sh
# Symlink ~/.local/share/Steam to the active Steam root (Ubuntu steam package layout).
# Sourced by Openbox autostart and gamescope session — must define gamebian_fix_steam_share() only.

gamebian_fix_steam_share() {
	_share="${XDG_DATA_HOME:-${HOME}/.local/share}/Steam"

	if [ -e "${_share}" ] && [ ! -L "${_share}" ]; then
		if [ -d "${_share}/userdata" ]; then
			return 0
		fi
		_bak="${_share}.bak.$(date +%Y%m%d%H%M%S 2>/dev/null || echo 0)"
		mv "${_share}" "${_bak}" 2>/dev/null || return 0
	fi

	for _target in \
		"${HOME}/.steam/steam" \
		"${HOME}/.steam/root" \
		"${HOME}/.steam/debian-installation"; do
		[ -d "${_target}/userdata" ] || continue
		mkdir -p "$(dirname "${_share}")" 2>/dev/null || return 0
		ln -sfn "${_target}" "${_share}" 2>/dev/null || true
		return 0
	done
}
