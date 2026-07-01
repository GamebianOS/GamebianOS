#!/usr/bin/env bash
# Merge Gamebian Calamares YAML + branding into a live-build includes.chroot tree.
# Usage: calamares/merge.sh <includes.chroot-abs> <Build/images-abs>
# Run from gamebian-iso-ubuntu/ via setup.sh.

set -euo pipefail
TARGET="${1:?target includes dir}"
IMAGES="${2:?Images directory (Build/images/)}"
ROOT="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$TARGET/etc/calamares"
cp -a "$ROOT/etc/calamares/." "$TARGET/etc/calamares/"

if [[ -d "$ROOT/usr" ]]; then
  mkdir -p "$TARGET/usr/share/applications" "$TARGET/usr/share/pixmaps"
  cp -a "$ROOT/usr/." "$TARGET/usr/"
fi

for _sbin in \
  "$TARGET/usr/local/sbin/gamebian-web-install" \
  "$TARGET/usr/local/sbin/gamebian-nm-user-perms.sh" \
  "$TARGET/usr/local/sbin/gamebian-add-user-input-group.sh"; do
  if [[ -f "$_sbin" ]]; then
    chmod 0755 "$_sbin"
  fi
done

br="$TARGET/etc/calamares/branding/gamebian"
mkdir -p "$br"

pick_welcome_image() {
  if [[ -f "$IMAGES/calamares/image.png" ]]; then
    echo "$IMAGES/calamares/image.png"
  elif [[ -f "$IMAGES/live/background.png" ]]; then
    echo "$IMAGES/live/background.png"
  elif [[ -f "$IMAGES/icons/menu-icon.png" ]]; then
    echo "$IMAGES/icons/menu-icon.png"
  fi
}

pick_sidebar_logo() {
  if [[ -f "$IMAGES/calamares/user-icon.png" ]]; then
    echo "$IMAGES/calamares/user-icon.png"
  elif [[ -f "$IMAGES/calamares/image.png" ]]; then
    echo "$IMAGES/calamares/image.png"
  elif [[ -f "$IMAGES/icons/menu-icon.png" ]]; then
    echo "$IMAGES/icons/menu-icon.png"
  fi
}

_sidebar="$(pick_sidebar_logo)"
if [[ -n "$_sidebar" ]]; then
  cp -a "$_sidebar" "$br/gamebian-logo.png"
  cp -a "$_sidebar" "$TARGET/usr/share/pixmaps/gamebian-console.png"
elif [[ ! -f "$br/gamebian-logo.png" ]]; then
  echo "calamares/merge.sh: warning: missing calamares user-icon (or fallback) under $IMAGES." >&2
fi

_welcome_large="$(pick_welcome_image)"
if [[ -n "$_welcome_large" ]]; then
  cp -a "$_welcome_large" "$br/welcome.png"
  cp -a "$_welcome_large" "$br/slide1.png"
elif [[ ! -f "$br/welcome.png" ]]; then
  echo "calamares/merge.sh: warning: missing calamares image (or fallback) under $IMAGES." >&2
fi
