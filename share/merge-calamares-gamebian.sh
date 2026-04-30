#!/usr/bin/env bash
# Merge Gamebian Calamares YAML + branding into a live-build includes.chroot tree.
# Usage: merge-calamares-gamebian.sh <includes.chroot-absolute-path> <design-dir-with-png>

set -euo pipefail
TARGET="${1:?target includes dir}"
DESIGN="${2:-}"
_here="$(cd "$(dirname "$0")" && pwd)"
ROOT="$_here/calamares-gamebian"

mkdir -p "$TARGET/etc/calamares"
cp -a "$ROOT/etc/calamares/." "$TARGET/etc/calamares/"

if [[ -d "$ROOT/usr" ]]; then
  mkdir -p "$TARGET/usr/share/applications" "$TARGET/usr/share/pixmaps"
  cp -a "$ROOT/usr/." "$TARGET/usr/"
fi

br="$TARGET/etc/calamares/branding/gamebian"
mkdir -p "$br"

pick_bg() {
  if [[ -f "$DESIGN/background.png" ]]; then
    echo "$DESIGN/background.png"
  elif [[ -f "$DESIGN/menu-icon.png" ]]; then
    echo "$DESIGN/menu-icon.png"
  fi
}

pick_logo() {
  if [[ -f "$DESIGN/console.png" ]]; then
    echo "$DESIGN/console.png"
  elif [[ -f "$DESIGN/menu-icon.png" ]]; then
    echo "$DESIGN/menu-icon.png"
  fi
}

_logo="$(pick_logo)"
if [[ -n "$_logo" ]]; then
  cp -a "$_logo" "$br/gamebian-logo.png"
  mkdir -p "$TARGET/usr/share/pixmaps"
  cp -a "$_logo" "$TARGET/usr/share/pixmaps/gamebian-console.png"
elif [[ ! -f "$br/gamebian-logo.png" ]]; then
  echo "merge-calamares-gamebian: warning: missing $DESIGN/console.png or menu-icon.png (installer logo)." >&2
fi

_bg="$(pick_bg)"
if [[ -n "$_bg" ]]; then
  cp -a "$_bg" "$br/welcome.png"
  cp -a "$_bg" "$br/slide1.png"
elif [[ ! -f "$br/welcome.png" ]]; then
  echo "merge-calamares-gamebian: warning: missing background / images for slideshow." >&2
fi
