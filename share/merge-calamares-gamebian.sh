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

# Calamares shellprocess scripts must be executable in the target chroot.
if [[ -f "$TARGET/usr/local/sbin/gamebian-web-install" ]]; then
  chmod 0755 "$TARGET/usr/local/sbin/gamebian-web-install"
fi

br="$TARGET/etc/calamares/branding/gamebian"
mkdir -p "$br"

# Large welcome / slideshow visuals (productWelcome / show.qml slide1): prefer console.png
pick_welcome_image() {
  if [[ -f "$DESIGN/console.png" ]]; then
    echo "$DESIGN/console.png"
  elif [[ -f "$DESIGN/background.png" ]]; then
    echo "$DESIGN/background.png"
  elif [[ -f "$DESIGN/menu-icon.png" ]]; then
    echo "$DESIGN/menu-icon.png"
  fi
}

# Sidebar / window icon above the step list (productLogo / productIcon): prefer live-controller.png
pick_sidebar_logo() {
  if [[ -f "$DESIGN/live-controller.png" ]]; then
    echo "$DESIGN/live-controller.png"
  elif [[ -f "$DESIGN/console.png" ]]; then
    echo "$DESIGN/console.png"
  elif [[ -f "$DESIGN/menu-icon.png" ]]; then
    echo "$DESIGN/menu-icon.png"
  fi
}

_sidebar="$(pick_sidebar_logo)"
if [[ -n "$_sidebar" ]]; then
  cp -a "$_sidebar" "$br/gamebian-logo.png"
  mkdir -p "$TARGET/usr/share/pixmaps"
  cp -a "$_sidebar" "$TARGET/usr/share/pixmaps/gamebian-console.png"
elif [[ ! -f "$br/gamebian-logo.png" ]]; then
  echo "merge-calamares-gamebian: warning: missing $DESIGN/live-controller.png (or fallback) for sidebar logo." >&2
fi

_welcome_large="$(pick_welcome_image)"
if [[ -n "$_welcome_large" ]]; then
  cp -a "$_welcome_large" "$br/welcome.png"
  cp -a "$_welcome_large" "$br/slide1.png"
elif [[ ! -f "$br/welcome.png" ]]; then
  echo "merge-calamares-gamebian: warning: missing $DESIGN/console.png (or fallback) for welcome image." >&2
fi
