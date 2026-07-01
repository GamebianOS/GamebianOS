#!/bin/sh
# Pure trixie apt: disable sid mix + fix libgpg-error0 amd64/i386 version lock for Steam.

gamebian_apt_stash_disabled_files() {
	_stash="/var/lib/gamebian/apt-disabled"
	mkdir -p "${_stash}"
	for _f in /etc/apt/sources.list.d/* /etc/apt/preferences.d/*; do
		[ -f "${_f}" ] || continue
		case "${_f}" in
			*.disabled.*|*gamebian-sid*|*gamebian-gamescope-from-sid*)
				mv "${_f}" "${_stash}/$(basename "${_f}").$(date +%s 2>/dev/null || echo 0)" 2>/dev/null \
					&& echo "[gamebian-apt] stashed $(basename "${_f}")"
				;;
		esac
	done
}

gamebian_apt_disable_sid_mix() {
	_changed=0
	_stash="/var/lib/gamebian/apt-disabled"
	mkdir -p "${_stash}"
	for _f in \
		/etc/apt/sources.list.d/gamebian-sid-install.list \
		/etc/apt/preferences.d/gamebian-gamescope-from-sid; do
		if [ -f "${_f}" ]; then
			mv "${_f}" "${_stash}/$(basename "${_f}").$(date +%s 2>/dev/null || echo 0)" 2>/dev/null \
				&& _changed=1 \
				&& echo "[gamebian-apt] disabled ${_f}"
		fi
	done
	# Old repair script left *.list.disabled.TIMESTAMP — apt still parses some; move all.
	gamebian_apt_stash_disabled_files
	if [ "${_changed}" -eq 1 ]; then
		apt-get update -qq 2>/dev/null || apt-get update || true
	fi
	return 0
}

# Debian package version from apt-cache policy (not pin priority 500/100).
gamebian_apt_policy_debian_version() {
	_pkg="$1"
	# Candidate: 1.51-4
	_v="$(apt-cache policy "${_pkg}" 2>/dev/null \
		| awk '/^[[:space:]]+candidate:/ { print $2; exit }')"
	case "${_v}" in
		*.*-*) printf '%s' "${_v}"; return 0 ;;
	esac
	# 1.51-4 500 http://... trixie/...
	_v="$(apt-cache policy "${_pkg}" 2>/dev/null \
		| awk '/trixie/ && $1 ~ /^[0-9]+\.[0-9]+-/ { print $1; exit }')"
	case "${_v}" in
		*.*-*) printf '%s' "${_v}"; return 0 ;;
	esac
	_v="$(apt-cache madison "${_pkg}" 2>/dev/null | awk '/trixie/ { print $3; exit }')"
	case "${_v}" in
		*.*-*) printf '%s' "${_v}"; return 0 ;;
	esac
	return 1
}

# Sid often leaves libgpg-error0:amd64 newer than :i386; Steam needs matching versions from trixie.
gamebian_apt_align_libgpg_error0_for_steam() {
	apt-get update -qq 2>/dev/null || apt-get update || return 1

	_amd_inst="$(dpkg-query -W -f='${Version}' libgpg-error0:amd64 2>/dev/null || true)"
	_i386_inst="$(dpkg-query -W -f='${Version}' libgpg-error0:i386 2>/dev/null || true)"

	_trixie_ver="$(gamebian_apt_policy_debian_version libgpg-error0:i386 2>/dev/null || true)"
	if [ -z "${_trixie_ver}" ]; then
		_trixie_ver="$(gamebian_apt_policy_debian_version libgpg-error0 2>/dev/null || true)"
	fi
	# Must look like 1.51-4 (reject apt pin priority 500 mistaken as a version).
	case "${_trixie_ver}" in
		[0-9]*.[0-9]*-*) ;;
		*) _trixie_ver="1.51-4" ;;
	esac

	echo "[gamebian-apt] aligning libgpg-error0 to trixie ${_trixie_ver} (installed amd64=${_amd_inst:-none} i386=${_i386_inst:-none})"

	if [ "${_amd_inst}" = "${_trixie_ver}" ] && [ "${_i386_inst}" = "${_trixie_ver}" ]; then
		return 0
	fi

	# Downgrade amd64 if sid left 1.61 while trixie i386 is 1.51, or install missing :i386.
	if apt-get install -y --allow-downgrades \
		"libgpg-error0:amd64=${_trixie_ver}" \
		"libgpg-error0:i386=${_trixie_ver}"; then
		return 0
	fi

	# Fallback: drop to trixie default candidate for both.
	apt-get install -y --allow-downgrades libgpg-error0 libgpg-error0:i386
}
