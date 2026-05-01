#!/usr/bin/env bash
# Debian live-build: lightweight Openbox-based live ISO.
# Run from this directory (openbox-live). Overlay is merged into GAMEBIANOS_BUILD_ROOT.

set -euo pipefail
SCRIPT_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_ROOT="${GAMEBIANOS_BUILD_ROOT:-/home/khinds/gamebianos-build-openbox}"
OVERLAY="$SCRIPT_ROOT/overlay"
DESIGN_SHARE="$OVERLAY/includes.chroot/etc/skel/.local/share/gamebian"

mkdir -p "$BUILD_ROOT"

if [[ -d "$SCRIPT_ROOT/design" ]]; then
  mkdir -p "$DESIGN_SHARE"
  for _img in "$SCRIPT_ROOT/design"/*.png "$SCRIPT_ROOT/design"/*.jpg; do
    [[ -f "$_img" ]] || continue
    cp -a "$_img" "$DESIGN_SHARE/"
  done
fi
cd "$BUILD_ROOT"

if ! command -v lb >/dev/null 2>&1; then
  echo "lb (live-build) not found. Install: sudo apt install live-build live-boot-doc" >&2
  exit 1
fi

# No quiet/splash on kernel cmdline: full console output (no Plymouth framebuffer splash).
lb config \
  --debootstrap-options "--variant=minbase" \
  --debian-installer none \
  --archive-areas "main contrib non-free non-free-firmware" \
  --binary-image iso-hybrid \
  --bootappend-live "boot=live components username=live hostname=gamebian-openbox"

mkdir -p config/package-lists config/includes.chroot config/hooks/normal config/bootloaders
shopt -s nullglob
for f in "$OVERLAY"/package-lists/*.list.chroot; do
  cp -a "$f" config/package-lists/
done
if [[ -d "$OVERLAY/bootloaders" ]]; then
  cp -a "$OVERLAY/bootloaders/." config/bootloaders/
fi
if [[ -d "$OVERLAY/includes.chroot" ]]; then
  cp -a "$OVERLAY/includes.chroot/." config/includes.chroot/
fi

# Installed session default wallpaper (matches gamebian-installed theme). Live ISO still uses ~/.../gamebian/.
INST_BG="$SCRIPT_ROOT/design/installed-bakgrounds/background.png"
INST_BG_DEST="$BUILD_ROOT/config/includes.chroot/usr/share/backgrounds/gamebian-installed"
if [[ -f "$INST_BG" ]]; then
  mkdir -p "$INST_BG_DEST"
  cp -a "$INST_BG" "$INST_BG_DEST/background.png"
fi

GAMEBIAN_SHARE="$(cd "$SCRIPT_ROOT/../share" && pwd)"
if [[ -f "$GAMEBIAN_SHARE/merge-calamares-gamebian.sh" ]]; then
  chmod +x "$GAMEBIAN_SHARE/merge-calamares-gamebian.sh"
  if [[ -d "$SCRIPT_ROOT/design" ]]; then
    CAL_DESIGN="$(cd "$SCRIPT_ROOT/design" && pwd)"
  elif [[ -d "$SCRIPT_ROOT/../openbox-live/design" ]]; then
    CAL_DESIGN="$(cd "$SCRIPT_ROOT/../openbox-live/design" && pwd)"
  else
    CAL_DESIGN=""
  fi
  "$GAMEBIAN_SHARE/merge-calamares-gamebian.sh" "$BUILD_ROOT/config/includes.chroot" "$CAL_DESIGN"
fi

for f in "$OVERLAY"/hooks/normal/*.hook.chroot; do
  cp -a "$f" config/hooks/normal/
  chmod +x "config/hooks/normal/$(basename "$f")"
done

echo "Resetting bootstrap state (next lb build will rerun debootstrap)..."
for _p in chroot "cache/bootstrap" "cache/packages.bootstrap"; do
  if [[ -e "$_p" ]]; then
    rm -rf "$_p" 2>/dev/null || sudo rm -rf "$_p"
  fi
done
for _f in .build/bootstrap .build/bootstrap_cache.restore .build/bootstrap_cache.save; do
  if [[ -e "$_f" ]]; then
    rm -f "$_f" 2>/dev/null || sudo rm -f "$_f"
  fi
done

echo "Configured: overlay merged into $BUILD_ROOT/config"
echo "Artifacts (binary/, iso) go to: $BUILD_ROOT"
echo "From here: cd $SCRIPT_ROOT && ./build.sh"
