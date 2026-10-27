#!/usr/bin/env bash
# Build the GamebianOS (Debian trixie) live ISO.
# Scratch: /var/tmp/gamebianos-build-$USER
# ISO:     ~/gamebian.iso
# The live-build step stays in gamebian-iso/build.sh. Ubuntu is ./build-ubuntu.sh.
# Usage: ./build.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
PROFILE="GamebianOS"
ISO_DIR="${REPO_ROOT}/gamebian-iso"
METADATA="${REPO_ROOT}/metadata/debian.env"
SETUP_SH="${ISO_DIR}/setup.sh"
BUILD_SH="${ISO_DIR}/build.sh"
NEED_UBUNTU_KEYRING=0
PRODUCT_VAR="GAMEBIAN_PRODUCT_NAME"
PRODUCT_DEFAULT="Gamebian"

BUILD_HOST_PACKAGES=(
	live-build debootstrap squashfs-tools xorriso
	isolinux syslinux-common grub-pc-bin grub-efi-amd64-bin
	mtools dosfstools imagemagick
	rsync ca-certificates ncurses-bin
)

if ! command -v tput >/dev/null 2>&1; then
	echo "tput is required (install ncurses-bin)." >&2
	exit 1
fi
if ! tput cols >/dev/null 2>&1; then
	export TERM="${TERM:-xterm-256color}"
fi

_bold="$(tput bold 2>/dev/null || true)"
_dim="$(tput dim 2>/dev/null || true)"
_red="$(tput setaf 1 2>/dev/null || true)"
_green="$(tput setaf 2 2>/dev/null || true)"
_yellow="$(tput setaf 3 2>/dev/null || true)"
_cyan="$(tput setaf 6 2>/dev/null || true)"
_reset="$(tput sgr0 2>/dev/null || true)"

_msg() { printf '%s\n' "$*"; }
_info() { _msg "${_cyan}→${_reset} $*"; }
_ok() { _msg "${_green}✓${_reset} $*"; }
_warn() { _msg "${_yellow}!${_reset} $*" >&2; }
_die() { _msg "${_red}✗${_reset} $*" >&2; exit 1; }

_heading() {
	_msg ""
	_msg "${_bold}${_cyan}$*${_reset}"
	_msg "${_dim}$(printf '%.0s─' $(seq 1 "$(tput cols 2>/dev/null || echo 60)"))${_reset}"
}

_is_scratch() {
	local p="${1%/}"
	local tmp="${TMPDIR:-/tmp}"
	tmp="${tmp%/}"
	[[ "$p" == /var/tmp || "$p" == /var/tmp/* \
		|| "$p" == /tmp || "$p" == /tmp/* \
		|| "$p" == "$tmp" || "$p" == "$tmp"/* ]]
}

ensure_root_access() {
	if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
		return 0
	fi
	if ! command -v sudo >/dev/null 2>&1; then
		_die "sudo is required to remove root-owned build artifacts and run lb build."
	fi
	_msg ""
	_warn "This build needs root access (sudo) for live-build."
	if ! sudo -v; then
		_die "Could not obtain root access."
	fi
	_ok "sudo credentials cached for this session."
}

_missing_host_packages() {
	local p
	for p in "$@"; do
		dpkg -s "$p" >/dev/null 2>&1 || printf '%s\n' "$p"
	done
}

ensure_build_tools() {
	local -a want=("${BUILD_HOST_PACKAGES[@]}")
	local -a missing=()
	if [[ "$NEED_UBUNTU_KEYRING" == "1" ]]; then
		want+=(ubuntu-keyring)
	fi
	if ! command -v dpkg >/dev/null 2>&1; then
		_warn "Not a dpkg host — skipping toolchain check."
		return 0
	fi
	mapfile -t missing < <(_missing_host_packages "${want[@]}")
	if ((${#missing[@]} == 0)); then
		_ok "Host build toolchain present (${#want[@]} packages)."
		return 0
	fi
	_warn "Missing host packages needed for live-build:"
	local p
	for p in "${missing[@]}"; do
		_msg "  ${_dim}${p}${_reset}"
	done
	if ! command -v apt-get >/dev/null 2>&1; then
		_die "Install the packages above, then re-run."
	fi
	_msg ""
	_info "Installing them now (needs sudo)…"
	ensure_root_access
	if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"; then
		_die "Could not install: ${missing[*]}"
	fi
	mapfile -t missing < <(_missing_host_packages "${want[@]}")
	((${#missing[@]})) && _die "Still missing after install: ${missing[*]}"
	_ok "Host build toolchain ready."
}

remove_build_root() {
	local dir="$1"
	if [[ ! -e "$dir" ]]; then
		_info "No existing build directory: ${_dim}${dir}${_reset}"
		return 0
	fi
	_warn "Removing existing build directory:"
	_msg "  ${_dim}${dir}${_reset}"
	rm -rf "$dir" 2>/dev/null || sudo rm -rf "$dir"
	_ok "Removed."
}

_home_iso_dest() {
	local product="$1"
	local slug
	slug="$(printf '%s' "$product" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
	case "$slug" in
	gamebianubuntu | gamebianos) slug=gamebian ;;
	esac
	printf '%s/%s.iso' "${HOME}" "$slug"
}

publish_home_iso() {
	local build_root="$1" dest="$2"
	local iso="" f
	shopt -s nullglob
	for f in "$build_root"/live-image-*.iso "$build_root"/*.iso; do
		[[ -f "$f" ]] || continue
		iso="$f"
		break
	done
	shopt -u nullglob
	if [[ -z "$iso" ]]; then
		if [[ -f "$dest" ]]; then
			_ok "ISO: ${_dim}${dest}${_reset}"
			return 0
		fi
		_warn "No ISO found under ${_dim}${build_root}${_reset}"
		return 0
	fi
	_info "Moving ${_dim}$(basename "$iso")${_reset} → ${_dim}${dest}${_reset}"
	rm -f "$dest" 2>/dev/null || sudo rm -f "$dest"
	if ! mv "$iso" "$dest" 2>/dev/null; then
		sudo mv "$iso" "$dest"
		sudo chown "$(id -u):$(id -g)" "$dest"
	fi
	_ok "ISO: ${_dim}${dest}${_reset}"
}

show_help() {
	_heading "${PROFILE} live ISO builder"
	_msg "Build this live ISO. Scratch files stay under /var/tmp."
	_msg "The finished ISO is moved to your home folder."
	_msg ""
	_msg "${_bold}Usage:${_reset}  ./build.sh"
	_msg ""
	_msg "  Scratch:  ${_dim}/var/tmp/gamebianos-build-\$USER${_reset}"
	_msg "  ISO:      ${_dim}~/gamebian.iso${_reset}"
	exit 0
}

main() {
	local arg build_root dest product
	for arg in "$@"; do
		case "$arg" in
		-h|--help|help) show_help ;;
		--lists-only|-l)
			_warn "${PROFILE} has no package-list step; building the ISO."
			;;
		--clean|-c) ;;
		*) _warn "Extra argument ignored: ${arg}" ;;
		esac
	done

	if [[ ! -x "$SETUP_SH" || ! -x "$BUILD_SH" ]]; then
		_die "${PROFILE} is not set up yet — missing gamebian-iso/setup.sh or build.sh"
	fi
	if [[ ! -f "$METADATA" ]]; then
		_die "Metadata not found: ${METADATA}"
	fi

	# shellcheck source=/dev/null
	source "$METADATA"
	build_root="${GAMEBIAN_BUILD_ROOT_DEFAULT:-}"
	if [[ -n "${GAMEBIAN_BUILD_ROOT_VAR:-}" ]]; then
		local named="${!GAMEBIAN_BUILD_ROOT_VAR:-}"
		if [[ -n "$named" ]] && _is_scratch "$named"; then
			build_root="$named"
		fi
	fi
	[[ -n "$build_root" ]] || _die "No build root in metadata."
	_is_scratch "$build_root" || _die "Build root must be under /var/tmp (got ${build_root})"
	if [[ -n "${GAMEBIAN_BUILD_ROOT_VAR:-}" ]]; then
		export "${GAMEBIAN_BUILD_ROOT_VAR}=${build_root}"
	fi

	product="${!PRODUCT_VAR:-$PRODUCT_DEFAULT}"
	dest="$(_home_iso_dest "$product")"

	_heading "Preflight: host build tools"
	ensure_build_tools
	ensure_root_access

	_heading "Building ${PROFILE}"
	_msg "  ISO scripts:  ${_dim}gamebian-iso${_reset}"
	_msg "  Build output: ${_dim}${build_root}${_reset}"
	_msg "  Home ISO:     ${_dim}${dest}${_reset}"
	_msg ""

	remove_build_root "$build_root"

	_info "Running setup.sh …"
	( cd "$ISO_DIR" && ./setup.sh )
	_ok "setup.sh finished."

	_info "Running build.sh …"
	( cd "$ISO_DIR" && ./build.sh )
	_ok "build.sh finished."

	publish_home_iso "$build_root" "$dest"

	_msg ""
	_ok "${_bold}${PROFILE}${_reset} build complete."
	_msg "  Output: ${_dim}${build_root}${_reset}"
	_msg "  ISO:    ${_dim}${dest}${_reset}"
}

main "$@"
