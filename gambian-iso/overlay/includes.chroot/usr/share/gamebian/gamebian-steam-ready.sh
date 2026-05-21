# shellcheck shell=sh
# Steam / first-boot state (sourced by session scripts, Openbox autostart, installers).

gamebian_export_session_env() {
	export DISPLAY="${DISPLAY:-:0}"
	export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games${PATH:+:$PATH}"
	export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
	export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
}

gamebian_firstboot_done() {
	[ -f "${HOME}/.config/gamebian-firstboot-steam.done" ]
}

gamebian_firstboot_markers_path() {
	printf '%s' "${HOME}/.config/gamebian-firstboot-steam.done"
}

gamebian_steam_session_enabled() {
	[ -f /etc/lightdm/lightdm.conf.d/99-gamebian-autologin-steam.conf ]
}

gamebian_have_loginusers_vdf() {
	for _gf in "${XDG_DATA_HOME:-${HOME}/.local/share}/Steam/config/loginusers.vdf" \
		"${HOME}/.steam/debian-installation/config/loginusers.vdf" \
		"${HOME}/.steam/root/config/loginusers.vdf"; do
		[ -f "$_gf" ] && return 0
	done
	return 1
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

gamebian_steam_kiosk_ready() {
	gamebian_firstboot_done && return 0
	[ -f "${HOME}/.config/gamebian-firstboot-steam.run-finished" ] && return 0
	gamebian_steam_session_enabled && return 0
	gamebian_have_loginusers_vdf
}

gamebian_steam_install_idle() {
	! gamebian_steam_process_busy
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

