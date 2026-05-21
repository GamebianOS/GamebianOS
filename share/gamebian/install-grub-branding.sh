#!/usr/bin/env bash
# Copy Gamebian GRUB artwork into live-build bootloaders + chroot branding paths.
# Sources: Build/gambian-iso/design/installed-backgrounds/ (or design/grub-16x9.png fallback).
set -euo pipefail

_here="$(cd "$(dirname "$0")" && pwd)"
ISO_ROOT="$(cd "$_here/../../gambian-iso" && pwd)"
OVERLAY="$ISO_ROOT/overlay"
DESIGN_INST="$ISO_ROOT/design/installed-backgrounds"
DESIGN_TOP="$ISO_ROOT/design"

pick_grub_16x9() {
	if [[ -f "$DESIGN_INST/grub-16x9.png" ]]; then
		echo "$DESIGN_INST/grub-16x9.png"
	elif [[ -f "$DESIGN_TOP/grub-16x9.png" ]]; then
		echo "$DESIGN_TOP/grub-16x9.png"
	fi
}

pick_grub_4x3() {
	if [[ -f "$DESIGN_INST/grub-4x3.png" ]]; then
		echo "$DESIGN_INST/grub-4x3.png"
	elif [[ -f "$DESIGN_TOP/grub-4x3.png" ]]; then
		echo "$DESIGN_TOP/grub-4x3.png"
	fi
}

GRUB16="$(pick_grub_16x9 || true)"
if [[ -z "$GRUB16" ]]; then
	echo "install-grub-branding: missing grub-16x9.png under $DESIGN_INST or $DESIGN_TOP" >&2
	exit 1
fi
GRUB43="$(pick_grub_4x3 || true)"

install_bootloader() {
	local _dest="$1"
	local _ref_pc="$OVERLAY/bootloaders/grub-pc"
	mkdir -p "$_dest/live-theme"
	cp -a "$GRUB16" "$_dest/splash.png"
	if [[ "$(readlink -f "$_dest")" != "$(readlink -f "$_ref_pc")" ]]; then
		[[ -f "$_ref_pc/live-theme/theme.txt" ]] \
			&& cp -a "$_ref_pc/live-theme/theme.txt" "$_dest/live-theme/theme.txt"
		[[ -f "$_ref_pc/theme.cfg" ]] && cp -a "$_ref_pc/theme.cfg" "$_dest/theme.cfg"
	fi
}

# Live ISO: BIOS + UEFI GRUB both use the same Gamebian GFX theme.
install_bootloader "$OVERLAY/bootloaders/grub-pc"
install_bootloader "$OVERLAY/bootloaders/grub-efi"

# Installed system + Calamares target (update-grub reads these paths).
GB_GRUB="$OVERLAY/includes.chroot/usr/share/gamebian/branding/grub"
CER_GRUB="$OVERLAY/includes.chroot/usr/share/desktop-base/ceratopsian-theme/grub"
mkdir -p "$GB_GRUB" "$CER_GRUB"
cp -a "$GRUB16" "$GB_GRUB/wallpaper.png"
cp -a "$GRUB16" "$OVERLAY/includes.chroot/usr/share/gamebian/branding/grub-16x9.png"
cp -a "$GRUB16" "$CER_GRUB/grub-16x9.png"
if [[ -n "$GRUB43" ]]; then
	cp -a "$GRUB43" "$OVERLAY/includes.chroot/usr/share/gamebian/branding/grub-4x3.png"
	cp -a "$GRUB43" "$CER_GRUB/grub-4x3.png"
fi

# Optional live-build tree (setup.sh passes BUILD_ROOT/config as second arg).
if [[ -n "${1:-}" ]]; then
	_cfg="${1%/}"
	install_bootloader "$_cfg/bootloaders/grub-pc"
	install_bootloader "$_cfg/bootloaders/grub-efi"
	mkdir -p "$_cfg/includes.chroot/usr/share/gamebian/branding/grub"
	mkdir -p "$_cfg/includes.chroot/usr/share/desktop-base/ceratopsian-theme/grub"
	cp -a "$GRUB16" "$_cfg/includes.chroot/usr/share/gamebian/branding/grub/wallpaper.png"
	cp -a "$GRUB16" "$_cfg/includes.chroot/usr/share/gamebian/branding/grub-16x9.png"
	cp -a "$GRUB16" "$_cfg/includes.chroot/usr/share/desktop-base/ceratopsian-theme/grub/grub-16x9.png"
	if [[ -n "$GRUB43" ]]; then
		cp -a "$GRUB43" "$_cfg/includes.chroot/usr/share/gamebian/branding/grub-4x3.png"
		cp -a "$GRUB43" "$_cfg/includes.chroot/usr/share/desktop-base/ceratopsian-theme/grub/grub-4x3.png"
	fi
fi

echo "install-grub-branding: OK ($GRUB16 → live USB + installed branding)"
