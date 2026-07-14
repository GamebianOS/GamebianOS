# shellcheck shell=sh
# Native / maximum monitor mode via xrandr (Openbox desktop + gamescope kiosk).

_RES_LOG="${XDG_CACHE_HOME:-${HOME}/.cache}/gamebian/display-resolution.log"

gamebian_display_res_log() {
	mkdir -p "$(dirname "${_RES_LOG}")" 2>/dev/null || true
	printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)" "$*" >>"${_RES_LOG}" 2>/dev/null || true
}

gamebian_xrandr_query() {
	DISPLAY="${DISPLAY:-:0}"
	export DISPLAY
	xrandr --query 2>/dev/null
}

gamebian_xrandr_primary_output() {
	command -v xrandr >/dev/null 2>&1 || return 1
	_xr="$(gamebian_xrandr_query)" || return 1
	_out="$(printf '%s\n' "${_xr}" | awk '/ connected / && / primary / { print $1; exit }')"
	if [ -z "${_out}" ]; then
		_out="$(printf '%s\n' "${_xr}" | awk '/ connected / { print $1; exit }')"
	fi
	[ -n "${_out}" ] || return 1
	printf '%s' "${_out}"
}

# Returns "W H mode" for the largest listed mode (stdout: "3840 2160 3840x2160").
gamebian_xrandr_largest_mode_dims() {
	_out="$1"
	_xr="$2"
	[ -n "${_out}" ] && [ -n "${_xr}" ] || return 1
	awk -v out="${_out}" '
		$0 ~ "^" out " connected" { inblk=1; next }
		inblk && $0 ~ / connected / { exit }
		inblk && $1 ~ /^[0-9]+x[0-9]+$/ {
			split($1, a, "x")
			w=a[1]+0; h=a[2]+0
			if (w >= 640 && h >= 480 && w*h > best) { best=w*h; bw=w; bh=h; bm=$1 }
		}
		END { if (bm != "") printf "%d %d %s\n", bw, bh, bm }
	' <<EOF
${_xr}
EOF
}

# Current WxH on an output's connected line (stdout: "W H"), or empty.
gamebian_xrandr_current_dims() {
	_out="$1"
	_xr="$2"
	_cline="$(printf '%s\n' "${_xr}" | grep -E "^${_out} connected")"
	[ -n "${_cline}" ] || return 1
	_dim="$(printf '%s\n' "${_cline}" | sed -n 's/.* \([0-9][0-9]*\)x\([0-9][0-9]*\)+[0-9][0-9]*+[0-9][0-9]*.*/\1 \2/p')"
	[ -n "${_dim}" ] || return 1
	printf '%s\n' "${_dim}"
}

# Set primary/default connected output to its maximum listed mode.
gamebian_ensure_native_resolution() {
	command -v xrandr >/dev/null 2>&1 || return 1
	DISPLAY="${DISPLAY:-:0}"
	export DISPLAY

	_out="$(gamebian_xrandr_primary_output)" || return 1
	_xr="$(gamebian_xrandr_query)" || return 1
	_before="$(printf '%s\n' "${_xr}" | grep -E "^${_out} connected" | head -1)"

	_largest="$(gamebian_xrandr_largest_mode_dims "${_out}" "${_xr}")"
	if [ -n "${_largest}" ]; then
		# shellcheck disable=SC2086
		set -- ${_largest}
		_lw="$1"
		_lh="$2"
		_lmode="$3"
		_cur="$(gamebian_xrandr_current_dims "${_out}" "${_xr}" 2>/dev/null || true)"
		if [ "${_cur}" = "${_lw} ${_lh}" ]; then
			gamebian_display_res_log "already max ${_out}: ${_lmode}"
			return 0
		fi
		if xrandr --output "${_out}" --mode "${_lmode}" 2>/dev/null; then
			gamebian_display_res_log "max ${_out}: ${_lmode} (was: ${_before})"
			return 0
		fi
		gamebian_display_res_log "max mode ${_lmode} rejected for ${_out}; trying preferred/auto"
	fi

	if xrandr --output "${_out}" --preferred 2>/dev/null; then
		_xr="$(gamebian_xrandr_query)" || true
		_after="$(printf '%s\n' "${_xr}" | grep -E "^${_out} connected" | head -1)"
		gamebian_display_res_log "preferred ${_out}: ${_after}"
		return 0
	fi

	if xrandr --output "${_out}" --auto 2>/dev/null; then
		gamebian_display_res_log "auto ${_out}"
		return 0
	fi

	gamebian_display_res_log "failed ${_out} (was: ${_before})"
	return 1
}

# Print "-W W -H H" using the largest mode on the default connected output.
# Prefer listed max (not gamescope's internal 1280x720 default).
gamebian_detect_gamescope_wh() {
	command -v xrandr >/dev/null 2>&1 || return 1
	gamebian_ensure_native_resolution 2>/dev/null || true
	DISPLAY="${DISPLAY:-:0}"
	export DISPLAY
	_xr="$(gamebian_xrandr_query)" || return 1
	_out="$(gamebian_xrandr_primary_output)" || return 1

	_largest="$(gamebian_xrandr_largest_mode_dims "${_out}" "${_xr}")"
	if [ -n "${_largest}" ]; then
		# shellcheck disable=SC2086
		set -- ${_largest}
		_gw="$1"
		_gh="$2"
	else
		_dim="$(gamebian_xrandr_current_dims "${_out}" "${_xr}")" || return 1
		# shellcheck disable=SC2086
		set -- ${_dim}
		_gw="$1"
		_gh="$2"
	fi
	[ "${_gw}" -ge 640 ] 2>/dev/null || return 1
	[ "${_gh}" -ge 480 ] 2>/dev/null || return 1
	printf '%s\n' "-W ${_gw} -H ${_gh}"
}
