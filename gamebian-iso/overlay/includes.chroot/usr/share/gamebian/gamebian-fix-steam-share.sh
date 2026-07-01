# shellcheck shell=sh
# Debian steam-installer stores Steam under ~/.steam/debian-installation/.
# Some tools (and older gamebian) expect ~/.local/share/Steam/userdata/.
# If a real empty ~/.local/share/Steam directory exists, ln -sfn will not replace it.

gamebian_fix_steam_share() {
	_debian="${HOME}/.steam/debian-installation"
	_share="${XDG_DATA_HOME:-${HOME}/.local/share}/Steam"

	[ -d "${_debian}/userdata" ] || return 0
	[ -d "${_share}/userdata" ] && return 0

	if [ -e "${_share}" ] && [ ! -L "${_share}" ]; then
		_bak="${_share}.bak.$(date +%Y%m%d%H%M%S 2>/dev/null || echo 0)"
		mv "${_share}" "${_bak}" 2>/dev/null || return 0
	fi

	mkdir -p "$(dirname "${_share}")" 2>/dev/null || return 0
	ln -sfn "${_debian}" "${_share}" 2>/dev/null || true
}
