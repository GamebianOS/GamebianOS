# shellcheck shell=sh
# Native monitor mode via xrandr (Openbox + gamescope kiosk).

gamebian_xrandr_primary_output() {
	command -v xrandr >/dev/null 2>&1 || return 1
	DISPLAY="${DISPLAY:-:0}"
	export DISPLAY
	_xr="$(xrandr --query 2>/dev/null)" || return 1
	_out="$(printf '%s\n' "${_xr}" | awk '/ connected / && / primary / { print $1; exit }')"
	if [ -z "${_out}" ]; then
		_out="$(printf '%s\n' "${_xr}" | awk '/ connected / { print $1; exit }')"
	fi
	[ -n "${_out}" ] || return 1
	printf '%s' "${_out}"
}

# Set the primary output to its preferred (native) mode.
gamebian_ensure_native_resolution() {
	_out="$(gamebian_xrandr_primary_output)" || return 1
	if xrandr --output "${_out}" --preferred 2>/dev/null; then
		return 0
	fi
	xrandr --output "${_out}" --auto 2>/dev/null
}

# Print "-W W -H H" for gamescope bare compositor (no -e). Uses current/preferred mode.
gamebian_detect_gamescope_wh() {
	command -v xrandr >/dev/null 2>&1 || return 1
	command -v sed >/dev/null 2>&1 || return 1
	gamebian_ensure_native_resolution 2>/dev/null || true
	DISPLAY="${DISPLAY:-:0}"
	export DISPLAY
	_xr="$(xrandr --query 2>/dev/null)" || return 1
	_out="$(gamebian_xrandr_primary_output)" || return 1
	_cline="$(printf '%s\n' "${_xr}" | grep -E "^${_out} connected")"
	[ -n "${_cline}" ] || return 1
	_gw=""
	_gh=""
	_dim="$(printf '%s\n' "${_cline}" | sed -n 's/.* \([0-9][0-9]*\)x\([0-9][0-9]*\)+[0-9][0-9]*+[0-9][0-9]*.*/\1 \2/p')"
	if [ -n "${_dim}" ]; then
		# shellcheck disable=SC2086
		set -- ${_dim}
		_gw="$1"
		_gh="$2"
	else
		_mode="$(printf '%s\n' "${_xr}" | sed -n "/^${_out} connected/,/^[^ \t]/p" \
			| grep '\*' | head -n 1 | awk '{ print $1 }')"
		[ -n "${_mode}" ] || return 1
		_gw="${_mode%x*}"
		_gh="${_mode#*x}"
	fi
	[ "${_gw}" -ge 640 ] 2>/dev/null || return 1
	[ "${_gh}" -ge 480 ] 2>/dev/null || return 1
	printf '%s\n' "-W ${_gw} -H ${_gh}"
}
