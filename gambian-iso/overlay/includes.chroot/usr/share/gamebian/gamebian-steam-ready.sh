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

# Something in first-boot / Steam setup warrants the reboot notice.
gamebian_reboot_notice_eligible() {
	gamebian_firstboot_done && return 0
	[ -f "${HOME}/.config/gamebian-firstboot-steam.run-finished" ] && return 0
	[ -f "${HOME}/.config/gamebian/pending-openbox-notify" ] && return 0
	gamebian_steam_session_enabled && return 0
	gamebian_have_loginusers_vdf && return 0
	return 1
}

# Ready to show reboot notice now (do not wait for Steam to quit on login screen).
gamebian_reboot_notice_ready_to_show() {
	[ "${1:-0}" = "1" ] && return 0
	gamebian_reboot_notice_eligible || return 1
	gamebian_firstboot_done && return 0
	[ -f "${HOME}/.config/gamebian-firstboot-steam.run-finished" ] && return 0
	[ -f "${HOME}/.config/gamebian/pending-openbox-notify" ] && return 0
	gamebian_steam_session_enabled && return 0
	gamebian_have_loginusers_vdf && return 0
	gamebian_steam_install_idle
}

gamebian_steam_needs_reboot_notice() {
	gamebian_reboot_notice_eligible
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

gamebian_queue_reboot_notify() {
	mkdir -p "${HOME}/.config/gamebian" "${HOME}/.cache/gamebian"
	touch "${HOME}/.config/gamebian/pending-openbox-notify"
	if [ -x /usr/share/gamebian/gamebian-openbox-notify.sh ]; then
		gamebian_export_session_env
		/usr/share/gamebian/gamebian-openbox-notify.sh --no-wait --force \
			>>"${HOME}/.cache/gamebian/openbox-notify.log" 2>&1 &
	fi
}

# After Steam sign-in: enable LightDM Steam session, set markers, show reboot notice.
gamebian_on_steam_signed_in() {
	gamebian_firstboot_done && return 0
	gamebian_have_loginusers_vdf || return 1

	_enabled=0
	if command -v sudo >/dev/null 2>&1 \
		&& sudo -n /usr/sbin/gamebian-enable-steam-lightdm-session 2>/dev/null; then
		mkdir -p "${HOME}/.config"
		: >"${HOME}/.config/gamebian-firstboot-steam.done"
		touch "${HOME}/.config/gamebian-firstboot-steam.run-finished"
		_enabled=1
	fi

	# Show reboot notice as soon as Steam account data exists (even if Steam is still on the login UI).
	gamebian_queue_reboot_notify
	[ "${_enabled}" -eq 1 ] && return 0
	return 1
}

# Background poll while Steam is on the login screen (Openbox autostart).
gamebian_poll_steam_signin_then_notify() {
	gamebian_export_session_env
	_poll=0
	while [ "${_poll}" -lt 120 ]; do
		gamebian_firstboot_done && break
		if gamebian_have_loginusers_vdf; then
			gamebian_on_steam_signed_in || true
			break
		fi
		sleep 5
		_poll=$((_poll + 1))
	done
}
