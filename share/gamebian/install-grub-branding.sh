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

write_live_theme_txt() {
	local _dest="$1"
	local _desktop_image="${2:-../splash.png}"
	mkdir -p "$(dirname "$_dest")"
	local _src="$OVERLAY/includes.chroot/usr/share/gamebian/branding/grub/theme.txt"
	if [[ -f "$_src" ]]; then
		sed "s|desktop-image: \"wallpaper.png\"|desktop-image: \"${_desktop_image}\"|" "$_src" >"$_dest"
	else
		cat >"$_dest" <<EOF
desktop-image: "${_desktop_image}"
title-color: "#ffffff"
title-font: "Unifont Regular 16"
title-text: "Welcome to Gamebian"
message-font: "Unifont Regular 16"
terminal-font: "Unifont Regular 16"

+ label {
	top = 100%-50
	left = 0
	width = 100%
	height = 20
	text = "@KEYMAP_SHORT@"
	align = "center"
	color = "#ffffff"
	font = "Unifont Regular 16"
}

+ boot_menu {
	left = 8%
	width = 84%
	top = 50%
	height = 48%-80
	item_color = "#cfcfcf"
	item_font = "Unifont Regular 16"
	selected_item_color = "#ffffff"
	selected_item_font = "Unifont Regular 16"
	item_height = 20
	item_padding = 0
	item_spacing = 6
	icon_width = 0
	icon_heigh = 0
	item_icon_space = 0
}

+ progress_bar {
	id = "__timeout__"
	left = 12%
	top = 100%-72
	height = 16
	width = 76%
	font = "Unifont Regular 16"
	text_color = "#000000"
	fg_color = "#ffffff"
	bg_color = "#5a5a5a"
	border_color = "#ffffff"
	text = "@TIMEOUT_NOTIFICATION_LONG@"
}
EOF
	fi
}

write_theme_cfg() {
	local _dest="$1"
	cat >"$_dest" <<'EOF'
# Gamebian live ISO GRUB — GFX theme (splash.png + live-theme/theme.txt).
set color_normal=light-gray/black
set color_highlight=white/dark-gray
set theme=/boot/grub/live-theme/theme.txt
EOF
}

install_bootloader() {
	local _dest="$1"
	mkdir -p "$_dest/live-theme"
	cp -a "$GRUB16" "$_dest/splash.png"
	write_live_theme_txt "$_dest/live-theme/theme.txt" "../splash.png"
	write_theme_cfg "$_dest/theme.cfg"
}

GRUB16="$(pick_grub_16x9 || true)"
if [[ -z "$GRUB16" ]]; then
	echo "install-grub-branding: missing grub-16x9.png under $DESIGN_INST or $DESIGN_TOP" >&2
	exit 1
fi
GRUB43="$(pick_grub_4x3 || true)"

# Live ISO: BIOS + UEFI GRUB both use the same Gamebian GFX theme.
install_bootloader "$OVERLAY/bootloaders/grub-pc"
install_bootloader "$OVERLAY/bootloaders/grub-efi"

# Installed system + Calamares target (update-grub reads these paths).
GB_GRUB="$OVERLAY/includes.chroot/usr/share/gamebian/branding/grub"
CER_GRUB="$OVERLAY/includes.chroot/usr/share/desktop-base/ceratopsian-theme/grub"
mkdir -p "$GB_GRUB" "$CER_GRUB"
cp -a "$GRUB16" "$GB_GRUB/wallpaper.png"
write_live_theme_txt "$GB_GRUB/theme.txt" "wallpaper.png"
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
	write_live_theme_txt "$_cfg/includes.chroot/usr/share/gamebian/branding/grub/theme.txt" "wallpaper.png"
	cp -a "$GRUB16" "$_cfg/includes.chroot/usr/share/gamebian/branding/grub-16x9.png"
	cp -a "$GRUB16" "$_cfg/includes.chroot/usr/share/desktop-base/ceratopsian-theme/grub/grub-16x9.png"
	if [[ -n "$GRUB43" ]]; then
		cp -a "$GRUB43" "$_cfg/includes.chroot/usr/share/gamebian/branding/grub-4x3.png"
		cp -a "$GRUB43" "$_cfg/includes.chroot/usr/share/desktop-base/ceratopsian-theme/grub/grub-4x3.png"
	fi
fi

echo "install-grub-branding: OK ($GRUB16 → live USB + installed branding)"
