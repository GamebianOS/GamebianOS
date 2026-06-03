#!/bin/sh
# Write ~/.config/lxpanel/.../panel from Gamebian templates (transparent tint follows theme).
# shellcheck source=/usr/share/gamebian/gamebian-openbox-session-env.sh
set -e

PANEL_DIR="${HOME}/.config/lxpanel/default/panels"
PANEL_FILE="${PANEL_DIR}/panel"

gamebian_lxpanel_resolve_theme_id() {
	if grep -qw boot=live /proc/cmdline 2>/dev/null; then
		printf '%s' live
		return 0
	fi
	if [ -r "${HOME}/.config/gamebian/desktop-theme" ]; then
		_tid="$(tr '[:upper:]' '[:lower:]' <"${HOME}/.config/gamebian/desktop-theme" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
		[ -n "${_tid}" ] && printf '%s' "${_tid}" && return 0
	fi
	if [ -r /usr/share/gamebian/gamebian-openbox-session-env.sh ]; then
		# shellcheck disable=SC1091
		. /usr/share/gamebian/gamebian-openbox-session-env.sh
		if _tid="$(gamebian_gtk_settings_value gtk-theme-name 2>/dev/null)"; then
			_tid="$(printf '%s' "${_tid}" | tr '[:upper:]' '[:lower:]')"
			printf '%s' "${_tid}"
			return 0
		fi
	fi
	printf '%s' black
}

gamebian_lxpanel_theme_tint() {
	_theme="$1"
	case "${_theme}" in
		gamebian-installed | installed | mono | monochrome | bw | blackwhite)
			_theme=black
			;;
		gamebian | live)
			_theme=blue
			;;
	esac
	case "${_theme}" in
		green) _tint="#0B441D"; _font="#ffffff"; _alpha=120 ;;
		yellow) _tint="#F89917"; _font="#1a1a1a"; _alpha=135 ;;
		blue) _tint="#021C4A"; _font="#ffffff"; _alpha=120 ;;
		red) _tint="#9E1720"; _font="#ffffff"; _alpha=120 ;;
		black) _tint="#1C1C24"; _font="#ffffff"; _alpha=120 ;;
		purple) _tint="#340E39"; _font="#ffffff"; _alpha=120 ;;
		*) _tint="#1C1C24"; _font="#ffffff"; _alpha=120 ;;
	esac
}

gamebian_lxpanel_patch_global() {
	_file="$1"
	_tint="$2"
	_font="$3"
	_alpha="$4"
	_tmp="${_file}.$$"
	awk -v tint="${_tint}" -v font="${_font}" -v alpha="${_alpha}" '
BEGIN { in_global = 0; saw_tint = 0; saw_alpha = 0 }
/^[[:space:]]*Global[[:space:]]*\{/ { in_global = 1 }
in_global && /^[[:space:]]*\}/ {
  if (!saw_tint) print "  tintcolor=" tint
  if (!saw_alpha) print "  alpha=" alpha
  print
  in_global = 0
  next
}
in_global && /^[[:space:]]*transparent=/ { print "  transparent=1"; next }
in_global && /^[[:space:]]*tintcolor=/ { print "  tintcolor=" tint; saw_tint = 1; next }
in_global && /^[[:space:]]*alpha=/ { print "  alpha=" alpha; saw_alpha = 1; next }
in_global && /^[[:space:]]*fontcolor=/ { print "  fontcolor=" font; next }
in_global && /^[[:space:]]*background=/ { print "  background=0"; next }
in_global && /^[[:space:]]*bgcolor=/ { next }
{ print }
' "${_file}" >"${_tmp}"
	mv -f "${_tmp}" "${_file}"
}

gamebian_lxpanel_remove_batt_plugin() {
	_file="$1"
	_tmp="${_file}.$$"
	awk '
function brace_delta(line,    i, c, d) {
	d = 0
	for (i = 1; i <= length(line); i++) {
		c = substr(line, i, 1)
		if (c == "{") d++
		else if (c == "}") d--
	}
	return d
}
BEGIN { buf = ""; depth = 0; drop = 0 }
/^Plugin[[:space:]]*\{/ {
	if (depth == 0 && buf != "" && !drop) printf "%s", buf
	buf = $0 "\n"
	drop = 0
	depth = brace_delta($0)
	next
}
depth > 0 {
	buf = buf $0 "\n"
	if ($0 ~ /^[[:space:]]*type=batt[[:space:]]*$/) drop = 1
	depth += brace_delta($0)
	if (depth == 0) {
		if (!drop) printf "%s", buf
		buf = ""
		drop = 0
	}
	next
}
{ print }
END { if (depth == 0 && buf != "" && !drop) printf "%s", buf }
' "${_file}" >"${_tmp}" && mv -f "${_tmp}" "${_file}"
}

gamebian_lxpanel_patch_batt_plugin() {
	_file="$1"
	if [ -r /usr/share/gamebian/gamebian-power-battery.sh ]; then
		# shellcheck disable=SC1091
		. /usr/share/gamebian/gamebian-power-battery.sh
	fi
	if command -v gamebian_sysfs_has_usable_battery >/dev/null 2>&1 \
		&& ! gamebian_sysfs_has_usable_battery 2>/dev/null; then
		gamebian_lxpanel_remove_batt_plugin "${_file}"
		return 0
	fi
	# Real battery: keep icon but disable lxpanel low-battery popups (AlarmCommand empty).
	_tmp="${_file}.$$"
	awk '
BEGIN { in_batt = 0; in_cfg = 0; patched = 0 }
/^[[:space:]]*type=batt[[:space:]]*$/ { in_batt = 1 }
in_batt && /^[[:space:]]*Config[[:space:]]*\{/ {
	print
	print "    HideIfNoBattery=1"
	print "    AlarmCommand="
	print "    AlarmTime=0"
	in_cfg = 1
	patched = 1
	next
}
in_batt && in_cfg && /^[[:space:]]*HideIfNoBattery=/ { next }
in_batt && in_cfg && /^[[:space:]]*AlarmCommand=/ { next }
in_batt && in_cfg && /^[[:space:]]*AlarmTime=/ { next }
in_batt && in_cfg && /^[[:space:]]*\}/ { in_cfg = 0 }
in_batt && /^[[:space:]]*\}/ && !in_cfg { in_batt = 0 }
{ print }
' "${_file}" >"${_tmp}" && mv -f "${_tmp}" "${_file}"
}

gamebian_lxpanel_apply_panel() {
	mkdir -p "${PANEL_DIR}"
	if grep -qw boot=live /proc/cmdline 2>/dev/null; then
		cp -f /usr/share/gamebian/lxpanel/panel-live "${PANEL_FILE}"
		gamebian_lxpanel_patch_batt_plugin "${PANEL_FILE}"
		return 0
	fi
	_theme="$(gamebian_lxpanel_resolve_theme_id)"
	gamebian_lxpanel_theme_tint "${_theme}"
	cp -f /usr/share/gamebian/lxpanel/panel-installed "${PANEL_FILE}"
	gamebian_lxpanel_patch_global "${PANEL_FILE}" "${_tint}" "${_font}" "${_alpha}"
	gamebian_lxpanel_patch_batt_plugin "${PANEL_FILE}"
}

gamebian_lxpanel_apply_panel
