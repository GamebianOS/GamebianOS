# shellcheck shell=sh
# Append one line block per session start (LightDM → X session → gamescope/Openbox).

gamebian_session_log() {
	_label="${1:-session}"
	_log="${XDG_CACHE_HOME:-${HOME}/.cache}/gamebian/lightdm-login.log"
	mkdir -p "$(dirname "$_log")" 2>/dev/null || true
	{
		printf '\n=== %s %s label=%s ===\n' \
			"$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)" \
			"$(id -un)" "${_label}"
		printf 'script=%s\n' "$0"
		printf 'args=%s\n' "$*"
		env | grep -iE '^(DESKTOP_SESSION|XDG_SESSION|XDG_CURRENT|DISPLAY|XAUTHORITY|HOME|USER)=' | sort || true
	} >>"$_log" 2>/dev/null || true
}
