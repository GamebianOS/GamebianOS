#!/usr/bin/env bash
# Debian live-build: lightweight Openbox-based live ISO.
# Run from this directory (openbox-live). Overlay is merged into GAMEBIANOS_BUILD_ROOT.

set -euo pipefail
SCRIPT_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_ROOT="${GAMEBIANOS_BUILD_ROOT:-/home/khinds/gamebianos-build-iso}"
OVERLAY="$SCRIPT_ROOT/overlay"
DESIGN_SHARE="$OVERLAY/includes.chroot/etc/skel/.local/share/gamebian"

mkdir -p "$BUILD_ROOT"

# Separate openbox profile live-build tree; remove so builds do not overlap or leave stale state.
if [[ -e /home/khinds/gamebianos-build-openbox ]]; then
  sudo rm -rf /home/khinds/gamebianos-build-openbox
fi

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

# No kernel splash: Plymouth/framebuffer takeover hides printk on tty; GRUB GFX menu stays (bootloaders/splash.png).
lb config \
  --debootstrap-options "--variant=minbase" \
  --debian-installer none \
  --archive-areas "main contrib non-free non-free-firmware" \
  --binary-image iso-hybrid \
  --bootappend-live "boot=live components username=live hostname=gamebian-openbox"

mkdir -p config/package-lists config/includes.chroot config/includes.chroot_before_packages \
  config/hooks/normal config/bootloaders
shopt -s nullglob
for f in "$OVERLAY"/package-lists/*.list.chroot; do
  cp -a "$f" config/package-lists/
done
if [[ -d "$OVERLAY/bootloaders" ]]; then
  cp -a "$OVERLAY/bootloaders/." config/bootloaders/
fi
if [[ -d "$OVERLAY/includes.chroot_before_packages" ]]; then
  cp -a "$OVERLAY/includes.chroot_before_packages/." config/includes.chroot_before_packages/
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

# Install branding: LightDM avatar + Debian ceratopsian GRUB images (sources in design/).
INST_ART="$SCRIPT_ROOT/design/installed-bakgrounds"
GAMEBIAN_PIX="$BUILD_ROOT/config/includes.chroot/usr/share/pixmaps"
if [[ -f "$INST_ART/user-installed-icon.png" ]]; then
  mkdir -p "$GAMEBIAN_PIX"
  cp -a "$INST_ART/user-installed-icon.png" "$GAMEBIAN_PIX/"
fi
GRUB_CER="$BUILD_ROOT/config/includes.chroot/usr/share/desktop-base/ceratopsian-theme/grub"
LBL_GRUB="$BUILD_ROOT/config/bootloaders/grub-pc"
GB_BR="$BUILD_ROOT/config/includes.chroot/usr/share/gamebian/branding"
if [[ -f "$INST_ART/grub-16x9.png" ]]; then
  mkdir -p "$GRUB_CER" "$GB_BR/grub" "$GB_BR" "$LBL_GRUB"
  cp -a "$INST_ART/grub-16x9.png" "$GRUB_CER/"
  cp -a "$INST_ART/grub-16x9.png" "$GB_BR/grub-16x9.png"
  cp -a "$INST_ART/grub-16x9.png" "$GB_BR/grub/wallpaper.png"
  cp -a "$INST_ART/grub-16x9.png" "$LBL_GRUB/splash.png"
fi
if [[ -f "$INST_ART/grub-4x3.png" ]]; then
  mkdir -p "$GRUB_CER" "$GB_BR"
  cp -a "$INST_ART/grub-4x3.png" "$GRUB_CER/"
  cp -a "$INST_ART/grub-4x3.png" "$GB_BR/grub-4x3.png"
fi
if [[ -f "$INST_ART/grub-square.png" ]]; then
  mkdir -p "$GB_BR"
  cp -a "$INST_ART/grub-square.png" "$GB_BR/grub-square.png"
fi

# Panel / rofi launcher icons: live ISO vs installed disk (see gamebian-menu*.desktop + lxpanel).
for _icon in menu-icon.png menu-icon-default.png; do
  if [[ -f "$SCRIPT_ROOT/design/$_icon" ]]; then
    mkdir -p "$GAMEBIAN_PIX"
    cp -a "$SCRIPT_ROOT/design/$_icon" "$GAMEBIAN_PIX/"
  fi
done

# Stage gamebian-web source into the live filesystem at /usr/src/gamebian-web.
# Live session never installs or runs it; the Calamares shellprocess
# (etc/calamares/modules/shellprocess@gamebian-web.conf) materialises it on the
# target disk during installation. Keep payload small by excluding VCS/test/CI.
GAMEBIAN_WEB_SRC="$(cd "$SCRIPT_ROOT/../../Packages/gamebian-web" 2>/dev/null && pwd || true)"
if [[ -n "$GAMEBIAN_WEB_SRC" && -f "$GAMEBIAN_WEB_SRC/setup.py" ]]; then
  GAMEBIAN_WEB_DEST="$BUILD_ROOT/config/includes.chroot/usr/src/gamebian-web"
  mkdir -p "$GAMEBIAN_WEB_DEST"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude='.git' --exclude='.github' --exclude='__pycache__' \
      --exclude='*.pyc' --exclude='tests/' --exclude='screenshots/' \
      --exclude='.markdownlint.json' --exclude='Dockerfile' \
      --exclude='requirements-container.txt' --exclude='requirements-test.txt' \
      --exclude='run-tests' \
      "$GAMEBIAN_WEB_SRC/" "$GAMEBIAN_WEB_DEST/"
  else
    # rsync not available — fall back to cp -a then prune known excludes.
    cp -a "$GAMEBIAN_WEB_SRC/." "$GAMEBIAN_WEB_DEST/"
    rm -rf \
      "$GAMEBIAN_WEB_DEST/.git" "$GAMEBIAN_WEB_DEST/.github" \
      "$GAMEBIAN_WEB_DEST/tests" "$GAMEBIAN_WEB_DEST/screenshots" \
      "$GAMEBIAN_WEB_DEST/Dockerfile" \
      "$GAMEBIAN_WEB_DEST/requirements-container.txt" \
      "$GAMEBIAN_WEB_DEST/requirements-test.txt" \
      "$GAMEBIAN_WEB_DEST/run-tests" \
      "$GAMEBIAN_WEB_DEST/.markdownlint.json" 2>/dev/null || true
  fi
  echo "Staged gamebian-web source -> $GAMEBIAN_WEB_DEST"
else
  echo "WARNING: gamebian-web source not found at $SCRIPT_ROOT/../../Packages/gamebian-web — target will not get the web utility" >&2
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
