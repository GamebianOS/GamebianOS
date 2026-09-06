# shellcheck shell=sh
# Source steam-gamescope.env, apply hybrid-GPU defaults, clear stale fallback markers.

gamebian_find_radv_vk_icd() {
	for _icd in /usr/share/vulkan/icd.d/radeon_icd*.json; do
		[ -r "${_icd}" ] || continue
		printf '%s' "${_icd}"
		return 0
	done
	return 1
}

gamebian_detect_hybrid_nvidia_amd_gpu() {
	command -v lspci >/dev/null 2>&1 || return 1
	_pci="$(lspci 2>/dev/null | grep -iE 'VGA|3D|Display')" || return 1
	echo "${_pci}" | grep -iq 'nvidia' || return 1
	echo "${_pci}" | grep -iqE 'amd/ati|radeon' || return 1
	return 0
}

# When NVIDIA + AMD iGPU are both present, gamescope often fails on Mesa NVK — prefer RADV.
gamebian_apply_hybrid_gpu_gamescope_defaults() {
	case "${GAMEBIAN_VK_ICD_FILENAMES:-}" in
		?*) return 0 ;;
	esac
	case "${GAMEBIAN_NO_HYBRID_GPU_AUTO:-}" in
		1|yes|true|YES|TRUE) return 0 ;;
	esac
	gamebian_detect_hybrid_nvidia_amd_gpu || return 0
	_icd="$(gamebian_find_radv_vk_icd)" || return 0
	export GAMEBIAN_VK_ICD_FILENAMES="${_icd}"
}

gamebian_clear_steam_without_gamescope_markers() {
	case "${GAMEBIAN_SKIP_GAMESCOPE:-}" in
		1|yes|true|YES|TRUE) return 0 ;;
	esac
	if [ -r /usr/share/gamebian/gamebian-steam-ready.sh ]; then
		# shellcheck disable=SC1091
		. /usr/share/gamebian/gamebian-steam-ready.sh
	fi
	# Probe even when a skip marker exists — missing Vulkan/render group was a
	# one-shot failure that used to stick forever (rm below was unreachable).
	if command -v gamebian_gamescope_binary_works >/dev/null 2>&1 \
		&& gamebian_gamescope_binary_works 2>/dev/null \
		&& command -v gamescope >/dev/null 2>&1 \
		&& DISPLAY="${DISPLAY:-:0}" timeout 5 gamescope -- true >/dev/null 2>&1; then
		rm -f /etc/gamebian/steam-without-gamescope \
			"${HOME}/.config/gamebian/steam-without-gamescope" 2>/dev/null || true
	fi
}

# Gamescope WSI breaks Steam Input in many titles; disable unless HDR needs it.
gamebian_apply_gamescope_steam_input_defaults() {
	case "${GAMEBIAN_GAMESCOPE_ENABLE_WSI:-}" in
		1|yes|true|YES|TRUE) ;;
		*) export ENABLE_GAMESCOPE_WSI=0 ;;
	esac
	case "${GAMEBIAN_GAMESCOPE_NO_STEAM:-}" in
		1|yes|true|YES|TRUE) return 0 ;;
	esac
	export STEAM_MULTIPLE_XWAYLANDS="${STEAM_MULTIPLE_XWAYLANDS:-1}"
}

# Source /etc/default + ~/.config/gamebian/steam-gamescope.env; optional hybrid auto-tune.
gamebian_source_steam_gamescope_env() {
	if [ -r /etc/default/gamebian-steam-gamescope ]; then
		set -a
		# shellcheck disable=SC1091
		. /etc/default/gamebian-steam-gamescope
		set +a
	fi
	if [ -r "${HOME}/.config/gamebian/steam-gamescope.env" ]; then
		set -a
		# shellcheck disable=SC1091
		. "${HOME}/.config/gamebian/steam-gamescope.env"
		set +a
	fi
	gamebian_apply_hybrid_gpu_gamescope_defaults
	gamebian_apply_gamescope_steam_input_defaults
	gamebian_clear_steam_without_gamescope_markers
}
