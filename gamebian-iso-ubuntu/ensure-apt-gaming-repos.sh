#!/bin/sh
# Ubuntu: enable universe + multiverse (+ restricted) and i386 (Steam on amd64).
# Safe to run repeatedly. Handles classic sources.list and deb822 *.sources files.

ensure_apt_i386() {
	if dpkg --print-foreign-architectures 2>/dev/null | grep -qx i386; then
		return 0
	fi
	dpkg --add-architecture i386
	echo "[ensure-apt] enabled foreign architecture i386 (required for steam)"
	return 0
}

_ensure_components_in_line() {
	_line="$1"
	_need="$2"
	case "$_line" in
		\#*|"") printf '%s\n' "$_line"; return 0 ;;
		deb*|deb-src*) ;;
		*) printf '%s\n' "$_line"; return 0 ;;
	esac
	_out="$_line"
	for _c in $_need; do
		if ! printf '%s' "$_out" | grep -qE "[[:space:]]${_c}([[:space:]]|$)"; then
			_out="${_out} ${_c}"
		fi
	done
	printf '%s\n' "$_out"
}

ensure_apt_gaming_repos() {
	_changed=0
	_components="universe multiverse restricted"

	if [ -f /etc/apt/sources.list ]; then
		_tmp="$(mktemp)"
		# shellcheck disable=SC2162
		while IFS= read -r _line || [ -n "$_line" ]; do
			case "$_line" in
				\#*|""|deb-src*) printf '%s\n' "$_line" >>"$_tmp"; continue ;;
				deb*)
					_new="$(_ensure_components_in_line "$_line" "$_components")"
					printf '%s\n' "$_new" >>"$_tmp"
					[ "$_new" != "$_line" ] && _changed=1
					;;
				*) printf '%s\n' "$_line" >>"$_tmp" ;;
			esac
		done </etc/apt/sources.list
		if [ "$_changed" -eq 1 ]; then
			cp -a /etc/apt/sources.list "/etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
			mv "$_tmp" /etc/apt/sources.list
			echo "[ensure-apt-gaming-repos] updated /etc/apt/sources.list"
		else
			rm -f "$_tmp"
		fi
	fi

	for _deb822 in /etc/apt/sources.list.d/*.sources; do
		[ -f "$_deb822" ] || continue
		if ! grep -q '^Components:' "$_deb822"; then
			continue
		fi
		if grep '^Components:' "$_deb822" | grep -q multiverse \
			&& grep '^Components:' "$_deb822" | grep -q universe; then
			continue
		fi
		cp -a "$_deb822" "${_deb822}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
		sed -i -E \
			'/^Components:/{
				s/^Components:[[:space:]]*/Components: main restricted universe multiverse /
			}' \
			"$_deb822"
		_changed=1
		echo "[ensure-apt-gaming-repos] updated $_deb822"
	done

	return 0
}

# Compatibility alias for shared scripts that still call ensure_apt_contrib_nonfree.
ensure_apt_contrib_nonfree() {
	ensure_apt_gaming_repos
}
