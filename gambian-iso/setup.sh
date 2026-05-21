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
# trixie: full libretro-* set in non-free (Debian testing lacks many cores — see packaging/debian-retroarch.list).
lb config \
  --distribution trixie \
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
# Branding palette color themes (green, yellow, blue, red, black, purple) under etc/skel/.themes/
GEN_COLOR_THEMES="$SCRIPT_ROOT/../share/gamebian/generate-color-themes.py"
if [[ -f "$GEN_COLOR_THEMES" ]] && command -v python3 >/dev/null 2>&1; then
  python3 "$GEN_COLOR_THEMES"
fi
if [[ -d "$OVERLAY/includes.chroot" ]]; then
  cp -a "$OVERLAY/includes.chroot/." config/includes.chroot/
fi

# APT contrib + non-free helper (libretro-snes9x and other cores).
ENSURE_APT_SRC="$SCRIPT_ROOT/../share/gamebian/ensure-apt-contrib-nonfree.sh"
ENSURE_APT_DST="$BUILD_ROOT/config/includes.chroot/usr/share/gamebian/ensure-apt-contrib-nonfree.sh"
if [[ -f "$ENSURE_APT_SRC" ]]; then
  mkdir -p "$(dirname "$ENSURE_APT_DST")"
  cp -a "$ENSURE_APT_SRC" "$ENSURE_APT_DST"
  chmod 0644 "$ENSURE_APT_DST"
fi

# RetroArch package names for post-install hook + Calamares (not live-build *.list.chroot — see 997 hook).
RETRO_PKG_SRC="$SCRIPT_ROOT/../../Packages/gamebian-web/packaging/debian-retroarch.list"
RETRO_PKG_SHARE="$BUILD_ROOT/config/includes.chroot/usr/share/gamebian/debian-retroarch.list"
if [[ -f "$RETRO_PKG_SRC" ]]; then
  mkdir -p "$(dirname "$RETRO_PKG_SHARE")"
  cp -a "$RETRO_PKG_SRC" "$RETRO_PKG_SHARE"
fi

# Controller menu: source lives under Build/share/gamebian/ (same path on ISO as before).
GAMEBIAN_CTRL_SRC="$SCRIPT_ROOT/../share/gamebian/gamebian_controller_menu.py"
GAMEBIAN_CTRL_DST="$BUILD_ROOT/config/includes.chroot/usr/share/gamebian/gamebian_controller_menu.py"
if [[ -f "$GAMEBIAN_CTRL_SRC" ]]; then
  mkdir -p "$(dirname "$GAMEBIAN_CTRL_DST")"
  cp -a "$GAMEBIAN_CTRL_SRC" "$GAMEBIAN_CTRL_DST"
  chmod 0644 "$GAMEBIAN_CTRL_DST"
else
  echo "WARNING: missing $GAMEBIAN_CTRL_SRC — ISO will lack gamebian_controller_menu.py" >&2
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
  # LightDM / AccountsService: adduser copies /etc/skel into the new user's home on Calamares install.
  SKEL="$BUILD_ROOT/config/includes.chroot/etc/skel"
  mkdir -p "$SKEL"
  _uicon="$INST_ART/user-installed-icon.png"
  if command -v convert >/dev/null 2>&1; then
    convert "$_uicon" -resize '512x512^' -gravity center -extent 512x512 PNG:"$SKEL/.face"
    convert "$_uicon" -resize '96x96^' -gravity center -extent 96x96 PNG:"$SKEL/.face.icon"
  else
    echo "warning: ImageMagick convert not found; install imagemagick on the build host for sized .face / .face.icon (using full-size copies)." >&2
    cp -a "$_uicon" "$SKEL/.face"
    cp -a "$_uicon" "$SKEL/.face.icon"
  fi
  chmod 0644 "$SKEL/.face" "$SKEL/.face.icon"
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
# Controller quick-launcher header (monochrome icon on installed disk).
if [[ -f "$GAMEBIAN_PIX/menu-icon-default.png" ]]; then
  mkdir -p "$BUILD_ROOT/config/includes.chroot/usr/share/gamebian"
  cp -a "$GAMEBIAN_PIX/menu-icon-default.png" \
    "$BUILD_ROOT/config/includes.chroot/usr/share/gamebian/controller-menu-icon.png"
fi

# Stage gamebian-web source into the live filesystem at /usr/src/gamebian-web (from
# <repo>/Packages/gamebian-web — sibling of Build/, own git checkout).
# Live session never installs or runs it; the Calamares shellprocess
# (etc/calamares/modules/shellprocess@gamebian-web.conf) materialises it on the
# target disk during installation. Keep payload small by excluding VCS/test/CI.
GAMEBIAN_REPO_ROOT="$(cd "$SCRIPT_ROOT/../.." && pwd)"
GAMEBIAN_WEB_SRC="${GAMEBIAN_REPO_ROOT}/Packages/gamebian-web"
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
  echo "WARNING: gamebian-web source not found at ${GAMEBIAN_REPO_ROOT}/Packages/gamebian-web — target will not get the web utility" >&2
fi

# Theme utility: Build/share/themes -> skel ~/.local/share/themes/ on ISO.
GAMEBIAN_THEMES_SRC="$(cd "$SCRIPT_ROOT/../share/themes" 2>/dev/null && pwd || true)"
GAMEBIAN_THEMES_DEST="$BUILD_ROOT/config/includes.chroot/etc/skel/.local/share/themes"
if [[ -n "$GAMEBIAN_THEMES_SRC" && -f "$GAMEBIAN_THEMES_SRC/pyproject.toml" ]]; then
  mkdir -p "$GAMEBIAN_THEMES_DEST"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude='.git' --exclude='.github' --exclude='__pycache__' \
      --exclude='*.pyc' --exclude='.venv' --exclude='venv/' \
      --exclude='*.egg-info' --exclude='dist/' --exclude='build/' \
      "$GAMEBIAN_THEMES_SRC/" "$GAMEBIAN_THEMES_DEST/"
  else
    rm -rf "${GAMEBIAN_THEMES_DEST:?}/"*
    cp -a "$GAMEBIAN_THEMES_SRC/." "$GAMEBIAN_THEMES_DEST/"
    rm -rf "$GAMEBIAN_THEMES_DEST/.git" "$GAMEBIAN_THEMES_DEST/.github" "$GAMEBIAN_THEMES_DEST/.venv" "$GAMEBIAN_THEMES_DEST/venv" 2>/dev/null || true
  fi
  echo "Synced Build/share/themes -> $GAMEBIAN_THEMES_DEST"
else
  echo "WARNING: Build/share/themes not found at $SCRIPT_ROOT/../share/themes — skipping themes sync" >&2
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
echo "gamescope: hook 997 builds ValveSoftware/gamescope @ 3.16.22 during lb build (needs network)."
echo "From here: cd $SCRIPT_ROOT && ./build.sh"
