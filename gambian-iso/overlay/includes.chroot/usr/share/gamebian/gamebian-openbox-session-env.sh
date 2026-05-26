# shellcheck shell=sh
# Source at the top of Openbox autostart (before lxpanel / tray applets).
# Qt nm-tray reads GTK icon settings via QT_QPA_PLATFORMTHEME=gtk3.

gamebian_gtk_settings_value() {
	_key="$1"
	_file="${HOME}/.config/gtk-3.0/settings.ini"
	[ -r "${_file}" ] || return 1
	_val="$(grep -E "^${_key}=" "${_file}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
	[ -n "${_val}" ] || return 1
	printf '%s' "${_val}"
	return 0
}

gamebian_icon_theme_for_gtk() {
	_gtk_theme="$1"
	case "${_gtk_theme}" in
		gamebian|blue|yellow) printf '%s' Papirus ;;
		*) printf '%s' Papirus-Dark ;;
	esac
}

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

	_gtk_theme=""
	if _gtk_theme="$(gamebian_gtk_settings_value gtk-theme-name)"; then
		:
	elif [ -r "${HOME}/.config/gamebian/desktop-theme" ]; then
		read -r _gtk_theme <"${HOME}/.config/gamebian/desktop-theme" 2>/dev/null || _gtk_theme=""
	fi
	[ -n "${_gtk_theme}" ] || _gtk_theme="gamebian-installed"
	export GTK_THEME="${_gtk_theme}"

	_icon_theme=""
	if _icon_theme="$(gamebian_gtk_settings_value gtk-icon-theme-name)"; then
		case "${_gtk_theme}" in
			gamebian-installed|red|black|purple|green)
				[ "${_icon_theme}" = Papirus ] && _icon_theme=Papirus-Dark
				;;
		esac
	else
		_icon_theme="$(gamebian_icon_theme_for_gtk "${_gtk_theme}")"
	fi
	# Dark GTK + lxpanel: Papirus on gamebian-installed shows white squares in nm-tray/blueman.
	export GTK_ICON_THEME="${_icon_theme}"
}
