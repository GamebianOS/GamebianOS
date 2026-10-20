#!/bin/sh
# Drop the live installer window-manager config from the installed system.
# Calamares copies /etc/skel into the new user's home before this runs.
set -eu

_rm_desktop() {
	_root="$1"
	[ -n "${_root}" ] || return 0
	[ -d "${_root}" ] || return 0
	rm -rf \
		"${_root}/.config/openbox" \
		"${_root}/.config/lxpanel" \
		"${_root}/.config/rofi" \
		"${_root}/.config/gtk-3.0" \
		"${_root}/.config/qt6ct" \
		"${_root}/.themes" \
		"${_root}/.local/share/rofi"
	rm -f \
		"${_root}/.config/systemd/user/gamebian-controller-menu.service" \
		"${_root}/.local/share/applications/gamebian-menu.desktop" \
		"${_root}/.local/share/applications/gamebian-menu-live.desktop" \
		"${_root}/.local/share/applications/gamebian-steam-bigpicture.desktop"
}

_rm_desktop /etc/skel

if [ -r /usr/share/gamebian/gamebian-lightdm-user.sh ]; then
	# shellcheck disable=SC1091
	. /usr/share/gamebian/gamebian-lightdm-user.sh
	_home="$(gamebian_lightdm_user_home 2>/dev/null || true)"
	if [ -n "${_home}" ] && [ "${_home}" != /etc/skel ]; then
		_rm_desktop "${_home}"
	fi
fi

rm -f /usr/share/gamebian/xsessions/gamebian-desktop.desktop \
	/etc/lightdm/lightdm.conf.d/88-gamebian-openbox-session.conf

exit 0
