# shellcheck shell=sh
# Source at the top of Openbox autostart (before lxpanel / tray applets).
# Qt nm-tray reads GTK icon settings via QT_QPA_PLATFORMTHEME=gtk3.

gamebian_openbox_session_env() {
	export DISPLAY="${DISPLAY:-:0}"
	export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
	export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
	export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games${PATH:+:$PATH}"

	export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
	export QT_QPA_PLATFORMTHEME=gtk3
	export QT_AUTO_SCREEN_SCALE_FACTOR=0
	export QT_IM_MODULE=

	if grep -qw boot=live /proc/cmdline 2>/dev/null; then
		export GTK_THEME="${GTK_THEME:-gamebian}"
		export GTK_ICON_THEME="${GTK_ICON_THEME:-Papirus}"
		return 0
	fi

	if [ -r "${HOME}/.config/gamebian/desktop-theme" ]; then
		read -r _gb_theme <"${HOME}/.config/gamebian/desktop-theme" 2>/dev/null || _gb_theme=""
		[ -n "${_gb_theme}" ] && export GTK_THEME="${_gb_theme}"
	fi
	export GTK_THEME="${GTK_THEME:-gamebian-installed}"
	# Dark GTK + lxpanel: Papirus-Dark tray icons; plain Papirus often shows white squares.
	export GTK_ICON_THEME="${GTK_ICON_THEME:-Papirus-Dark}"
}
