# shellcheck shell=sh
# Shared Steam install / setup checks (Openbox autostart, gamescope session, notices).

gamebian_have_loginusers_vdf_for_home() {
	_home="$1"
	[ -n "${_home}" ] || return 1
	for _gf in "${_home}/.local/share/Steam/config/loginusers.vdf" \
		"${_home}/.steam/debian-installation/config/loginusers.vdf" \
		"${_home}/.steam/root/config/loginusers.vdf"; do
		[ -f "${_gf}" ] && return 0
	done
	return 1
}

gamebian_have_loginusers_vdf() {
	gamebian_have_loginusers_vdf_for_home "${HOME}"
}

gamebian_steam_binary_present() {
	command -v steam >/dev/null 2>&1 \
		|| [ -x /usr/games/steam ] \
		|| [ -x /usr/bin/steam ] \
		|| [ -x /usr/local/bin/steam ]
}

gamebian_steam_process_busy() {
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

gamebian_steam_bootstrap_pending() {
	if pgrep -u "$(id -un)" -f '[s]team.*bootstrap' >/dev/null 2>&1; then
		return 0
	fi
	if [ -f "${HOME}/.steam/debian-installation/.needs-steam-bootstrap" ] \
		|| [ -f "${HOME}/.steam/root/.needs-steam-bootstrap" ]; then
		return 0
	fi
	return 1
}

gamebian_steam_client_installed() {
	if ! gamebian_steam_binary_present; then
		return 1
	fi
	if gamebian_steam_bootstrap_pending; then
		return 1
	fi
	if gamebian_have_loginusers_vdf; then
		return 0
	fi
	if [ -f "${HOME}/.steam/debian-installation/ubuntu12_32/steam" ] \
		|| [ -f "${HOME}/.local/share/Steam/ubuntu12_32/steam" ] \
		|| [ -x "${HOME}/.steam/debian-installation/steam.sh" ] \
		|| [ -x "${HOME}/.local/share/Steam/steam.sh" ]; then
		return 0
	fi
	return 1
}

# Signed in to Steam (loginusers.vdf).
gamebian_steam_logged_in() {
	gamebian_have_loginusers_vdf
}

# LightDM autologin → gamescope when Steam is installed and the user is signed in.
gamebian_steam_kiosk_ready() {
	if ! gamebian_steam_client_installed; then
		return 1
	fi
	gamebian_steam_logged_in
}

gamebian_steam_install_idle() {
	! gamebian_steam_bootstrap_pending
}

gamebian_finish_steam_firstboot() {
	if gamebian_steam_kiosk_ready; then
		return 0
	fi
	if ! gamebian_have_loginusers_vdf; then
		return 1
	fi
	if [ "$(id -u)" -eq 0 ]; then
		/usr/sbin/gamebian-enable-steam-lightdm-session || return 1
	elif command -v sudo >/dev/null 2>&1; then
		if ! sudo -n /usr/sbin/gamebian-enable-steam-lightdm-session 2>/dev/null \
			&& ! sudo /usr/sbin/gamebian-enable-steam-lightdm-session 2>/dev/null; then
			return 1
		fi
	else
		return 1
	fi
	mkdir -p "${HOME}/.config"
	touch "${HOME}/.config/gamebian-firstboot-steam.run-finished"
	: >"${HOME}/.config/gamebian-firstboot-steam.done"
	return 0
}

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
