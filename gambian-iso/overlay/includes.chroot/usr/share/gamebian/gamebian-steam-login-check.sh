# shellcheck shell=sh
# Shared by gamebian-steam-gamescope-session, gamebian-steam-bigpicture, Openbox autostart.
# Debian steam-installer uses ~/.steam/debian-installation/; ~/.local/share/Steam is the common Valve layout.

gamebian_have_loginusers_vdf() {
	for _gf in "${XDG_DATA_HOME:-${HOME}/.local/share}/Steam/config/loginusers.vdf" \
		"${HOME}/.steam/debian-installation/config/loginusers.vdf" \
		"${HOME}/.steam/root/config/loginusers.vdf"; do
		[ -f "$_gf" ] && return 0
	done
	return 1
}
