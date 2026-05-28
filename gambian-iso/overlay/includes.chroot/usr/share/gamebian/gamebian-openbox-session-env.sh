# shellcheck shell=sh
# Source at the top of Openbox autostart (before lxpanel / tray applets).
# Qt6 nm-tray needs qt6ct for icon themes; gtk3 platform theme alone yields white squares.

gamebian_gtk_settings_value() {
	_key="$1"
	_file="${HOME}/.config/gtk-3.0/settings.ini"
	[ -r "${_file}" ] || return 1
	_val="$(grep -E "^${_key}=" "${_file}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
	[ -n "${_val}" ] || return 1
	printf '%s' "${_val}"
	return 0
}

# Installed: Papirus has full NetworkManager panel icon names; Papirus-Dark often misses them.
# Live: Papirus-Dark on blue branding works in practice.
gamebian_tray_icon_theme() {
	if grep -qw boot=live /proc/cmdline 2>/dev/null; then
		printf '%s' Papirus-Dark
	else
		printf '%s' Papirus
	fi
}

gamebian_icon_theme_for_gtk() {
	_gtk_theme="$1"
	case "${_gtk_theme}" in
		yellow) printf '%s' Papirus ;;
		*) printf '%s' Papirus-Dark ;;
	esac
}

gamebian_write_qt6ct_conf() {
	_icon="${1:-Papirus-Dark}"
	_conf="${HOME}/.config/qt6ct/qt6ct.conf"
	mkdir -p "$(dirname "${_conf}")"
	# Qt6 nm-tray reads icon_theme from qt6ct when QT_QPA_PLATFORMTHEME=qt6ct.
	cat >"${_conf}" <<EOF
[Appearance]
icon_theme=${_icon}
style=gtk2
standard_dialogs=default
EOF
}

gamebian_apply_gtk2_rc_files() {
	_gtk="${GTK_THEME:-gamebian-installed}"
	_gtk2_rc="${HOME}/.themes/${_gtk}/gtk-2.0/gtkrc"
	if [ -r "${_gtk2_rc}" ]; then
		export GTK2_RC_FILES="${_gtk2_rc}:${HOME}/.gtkrc-2.0"
	else
		export GTK2_RC_FILES="${HOME}/.gtkrc-2.0"
	fi
}

gamebian_openbox_session_env() {
	export DISPLAY="${DISPLAY:-:0}"
	export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
	export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
	export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games${PATH:+:$PATH}"

	export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
	export QT_AUTO_SCREEN_SCALE_FACTOR=0
	export QT_IM_MODULE=

	if command -v qt6ct >/dev/null 2>&1; then
		export QT_QPA_PLATFORMTHEME=qt6ct
	else
		export QT_QPA_PLATFORMTHEME=gtk3
	fi

	if grep -qw boot=live /proc/cmdline 2>/dev/null; then
		export GTK_THEME="${GTK_THEME:-gamebian}"
		export GTK_ICON_THEME="${GTK_ICON_THEME:-$(gamebian_tray_icon_theme)}"
		export XDG_CURRENT_DESKTOP=LXDE
		gamebian_write_qt6ct_conf "${GTK_ICON_THEME}"
		gamebian_apply_gtk2_rc_files
		export XDG_ICON_THEME="${GTK_ICON_THEME}"
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

	_icon_theme="$(gamebian_tray_icon_theme)"
	export GTK_ICON_THEME="${_icon_theme}"
	export XDG_ICON_THEME="${_icon_theme}"
	export XDG_CURRENT_DESKTOP=LXDE

	gamebian_write_qt6ct_conf "${_icon_theme}"
	gamebian_apply_gtk2_rc_files
}
