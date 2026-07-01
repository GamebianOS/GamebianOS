#!/usr/bin/env bash
# Copy Gamebian GRUB/isolinux artwork into live-build bootloaders + chroot branding paths.
# Sources: Build/images/grub/ (setup.sh sets GAMEBIAN_ISO_ROOT and optional BUILD config arg).
set -euo pipefail

_here="$(cd "$(dirname "$0")" && pwd)"
if [[ -z "${GAMEBIAN_ISO_ROOT:-}" ]]; then
  echo "install-grub-branding: GAMEBIAN_ISO_ROOT not set (export from setup.sh)" >&2
  exit 1
fi
ISO_ROOT="$(cd "$GAMEBIAN_ISO_ROOT" && pwd)"
OVERLAY="$ISO_ROOT/overlay"
IMAGES_GRUB="$(cd "$_here/../../images/grub" && pwd)"
PROFILE="${GAMEBIAN_CALAMARES_PROFILE:-debian}"

pick_grub_16x9() {
  if [[ -f "$IMAGES_GRUB/grub-16x9.png" ]]; then
    echo "$IMAGES_GRUB/grub-16x9.png"
  fi
}

pick_grub_4x3() {
  if [[ -f "$IMAGES_GRUB/grub-4x3.png" ]]; then
    echo "$IMAGES_GRUB/grub-4x3.png"
  fi
}

write_grub_theme_txt() {
  local _dest="$1"
  local _desktop_image="${2:-../splash.png}"
  mkdir -p "$(dirname "$_dest")"
  local _src="$OVERLAY/includes.chroot/usr/share/gamebian/branding/grub/theme.txt"
  local _tmp
  _tmp="$(mktemp)"
  if [[ -s "$_src" ]]; then
    sed "s|desktop-image: \"wallpaper.png\"|desktop-image: \"${_desktop_image}\"|" "$_src" >"$_tmp"
  elif [[ -s "$_dest" ]]; then
    cp -a "$_dest" "$_tmp"
  else
    cat >"$_tmp" <<EOF
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
  if [[ ! -s "$_tmp" ]]; then
    rm -f "$_tmp"
    echo "install-grub-branding: refused to write empty theme.txt at $_dest" >&2
    exit 1
  fi
  mv -f "$_tmp" "$_dest"
  chmod 0644 "$_dest"
}

write_theme_cfg() {
  local _dest="$1"
  cat >"$_dest" <<'EOF'
# Gamebian live ISO GRUB — GFX theme (splash.png + live-theme/theme.txt).
set color_normal=light-gray/black
set color_highlight=white/dark-gray
if [ -e /boot/grub/splash.png ]; then
	set theme=/boot/grub/live-theme/theme.txt
else
	set menu_color_normal=cyan/blue
	set menu_color_highlight=white/blue
fi
EOF
}

install_isolinux_splash() {
  local _dest="$1"
  local _src="${2:-}"
  mkdir -p "$_dest"
  if [[ -z "$_src" ]]; then
    _src="$(pick_grub_4x3 || true)"
  fi
  if [[ -z "$_src" ]]; then
    _src="$GRUB16"
  fi
  if command -v convert >/dev/null 2>&1; then
    convert "$_src" -resize 640x480^ -gravity center -extent 640x480 PNG:"$_dest/splash.png"
  elif command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w 640 -h 480 -o "$_dest/splash.png" "$_src" 2>/dev/null \
      || cp -a "$_src" "$_dest/splash.png"
  else
    cp -a "$_src" "$_dest/splash.png"
  fi
}

install_bootloader() {
  local _dest="$1"
  mkdir -p "$_dest/live-theme"
  cp -a "$GRUB16" "$_dest/splash.png"
  write_grub_theme_txt "$_dest/live-theme/theme.txt" "../splash.png"
  write_theme_cfg "$_dest/theme.cfg"
}

install_installed_branding() {
  local _prefix="$1"
  local _gb_grub="$_prefix/includes.chroot/usr/share/gamebian/branding/grub"
  mkdir -p "$_gb_grub"
  cp -a "$GRUB16" "$_gb_grub/wallpaper.png"
  write_grub_theme_txt "$_gb_grub/theme.txt" "wallpaper.png"
  cp -a "$GRUB16" "$_prefix/includes.chroot/usr/share/gamebian/branding/grub-16x9.png"
  if [[ -n "$GRUB43" && -f "$GRUB43" ]]; then
    cp -a "$GRUB43" "$_prefix/includes.chroot/usr/share/gamebian/branding/grub-4x3.png"
  fi
  if [[ "$PROFILE" == debian ]]; then
    local _cer_grub="$_prefix/includes.chroot/usr/share/desktop-base/ceratopsian-theme/grub"
    mkdir -p "$_cer_grub"
    cp -a "$GRUB16" "$_cer_grub/grub-16x9.png"
    if [[ -n "$GRUB43" && -f "$GRUB43" ]]; then
      cp -a "$GRUB43" "$_cer_grub/grub-4x3.png"
    fi
  fi
}

GRUB16="$(pick_grub_16x9 || true)"
if [[ -z "$GRUB16" ]]; then
  echo "install-grub-branding: missing grub-16x9.png under $IMAGES_GRUB" >&2
  exit 1
fi
GRUB43="$(pick_grub_4x3 || true)"

install_bootloader "$OVERLAY/bootloaders/grub-pc"
install_bootloader "$OVERLAY/bootloaders/grub-efi"
install_isolinux_splash "$OVERLAY/bootloaders/isolinux" "${GRUB43:-$GRUB16}"
install_installed_branding "$OVERLAY"

if [[ -n "${1:-}" ]]; then
  _cfg="${1%/}"
  install_bootloader "$_cfg/bootloaders/grub-pc"
  install_bootloader "$_cfg/bootloaders/grub-efi"
  install_isolinux_splash "$_cfg/bootloaders/isolinux" "${GRUB43:-$GRUB16}"
  install_installed_branding "$_cfg"
fi

echo "install-grub-branding: OK ($GRUB16 → live USB isolinux + GRUB + installed branding)"
