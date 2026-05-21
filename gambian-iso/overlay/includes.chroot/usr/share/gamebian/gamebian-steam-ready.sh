# shellcheck shell=sh
# Shared Steam install / setup checks (Openbox autostart, gamescope session, notices).

gamebian_steam_binary_present() {
	command -v steam >/dev/null 2>&1 \
		|| [ -x /usr/games/steam ] \
		|| [ -x /usr/bin/steam ] \
		|| [ -x /usr/local/bin/steam ]
}

gamebian_steam_process_busy() {
	# Active Steam client / bootstrap only (not unrelated "steam" substrings).
	if pgrep -u "$(id -un)" -x steam >/dev/null 2>&1; then
		return 0
	fi
	if pgrep -u "$(id -un)" -x steam.sh >/dev/null 2>&1; then
		return 0
	fi
	if pgrep -u "$(id -un)" -f '/usr/(games|bin)/steam ' >/dev/null 2>&1; then
		return 0
	fi
	if pgrep -u "$(id -un)" -f '[s]team.*bootstrap' >/dev/null 2>&1; then
		return 0
	fi
	if [ -f "${HOME}/.steam/debian-installation/.needs-steam-bootstrap" ] \
		|| [ -f "${HOME}/.steam/root/.needs-steam-bootstrap" ]; then
		return 0
	fi
	return 1
}

gamebian_steam_kiosk_ready() {
	if [ -f "${HOME}/.config/gamebian-firstboot-steam.done" ]; then
		return 0
	fi
	if [ -f "${HOME}/.config/gamebian-firstboot-steam.run-finished" ]; then
		return 0
	fi
	if command -v gamebian_have_loginusers_vdf >/dev/null 2>&1 && gamebian_have_loginusers_vdf; then
		return 0
	fi
	_steam_data="${XDG_DATA_HOME:-${HOME}/.local/share}/Steam"
	if [ -f "${_steam_data}/config/loginusers.vdf" ] \
		|| [ -f "${HOME}/.steam/debian-installation/config/loginusers.vdf" ]; then
		return 0
	fi
	return 1
}

gamebian_steam_setup_complete() {
	gamebian_steam_kiosk_ready
}

gamebian_steam_needs_reboot_notice() {
	gamebian_steam_kiosk_ready
}

gamebian_steam_install_idle() {
	! gamebian_steam_process_busy
}

# True when gamescope runs (not just a broken partial install from dpkg -i).
gamebian_gamescope_binary_works() {
	if [ -f /etc/gamebian/steam-without-gamescope ]; then
		return 1
	fi
	if command -v gamescope >/dev/null 2>&1 && gamescope --help >/dev/null 2>&1; then
		return 0
	fi
	if [ -x /usr/games/gamescope ] && /usr/games/gamescope --help >/dev/null 2>&1; then
		return 0
	fi
	return 1
}

gamebian_use_steam_without_gamescope() {
	[ -f /etc/gamebian/steam-without-gamescope ] \
		|| [ -f "${HOME}/.config/gamebian/steam-without-gamescope" ] \
		|| ! gamebian_gamescope_binary_works
}
