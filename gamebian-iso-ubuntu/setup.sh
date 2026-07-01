#!/usr/bin/env bash
# Ubuntu live-build: Gamebian Openbox live ISO profile (26.04 LTS resolute).
# Run from Build/gamebian-iso-ubuntu/. Overlay is merged into GAMEBIANUBUNTU_BUILD_ROOT.
# Branding PNGs: edit files under Build/images/ then re-run ./setup.sh.

set -euo pipefail
SCRIPT_ROOT="$(cd "$(dirname "$0")" && pwd)"
METADATA="$(cd "$SCRIPT_ROOT/../metadata" && pwd)"
# shellcheck source=/dev/null
source "$METADATA/ubuntu.env"
IMAGES="$(cd "$SCRIPT_ROOT/../images" && pwd)"
export GAMEBIAN_ISO_ROOT="$SCRIPT_ROOT"
export GAMEBIAN_CALAMARES_PROFILE="$GAMEBIAN_PROFILE_ID"
_build_var="${GAMEBIAN_BUILD_ROOT_VAR}"
BUILD_ROOT="${!_build_var:-$GAMEBIAN_BUILD_ROOT_DEFAULT}"
OVERLAY="$SCRIPT_ROOT/overlay"
DESIGN_SHARE="$OVERLAY/includes.chroot/etc/skel/.local/share/gamebian"

mkdir -p "$BUILD_ROOT"

if [[ -f "$IMAGES/live/background.png" ]]; then
  mkdir -p "$DESIGN_SHARE"
  cp -a "$IMAGES/live/background.png" "$DESIGN_SHARE/background.png"
fi
cd "$BUILD_ROOT"

if ! command -v lb >/dev/null 2>&1; then
  echo "lb (live-build) not found. Install: sudo apt install live-build live-boot-doc" >&2
  exit 1
fi

# Building Ubuntu on a Debian host requires Ubuntu's archive signing key for debootstrap.
ensure_ubuntu_archive_keyring() {
  [[ -f /usr/share/keyrings/ubuntu-archive-keyring.gpg ]] && return 0
  echo "Missing Ubuntu archive keyring — needed to debootstrap resolute on Debian."
  if [[ "$(id -u)" -eq 0 ]]; then
    apt-get update -qq
    apt-get install -y ubuntu-keyring
  elif command -v sudo >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y ubuntu-keyring
  else
    echo "ERROR: install ubuntu-keyring on the build host:" >&2
    echo "  sudo apt install ubuntu-keyring" >&2
    exit 1
  fi
  if [[ ! -f /usr/share/keyrings/ubuntu-archive-keyring.gpg ]]; then
    echo "ERROR: ubuntu-keyring installed but keyring still missing" >&2
    exit 1
  fi
  echo "OK: $(readlink -f /usr/share/keyrings/ubuntu-archive-keyring.gpg 2>/dev/null || echo ubuntu-archive-keyring.gpg)"
}
if [[ "${LB_UBUNTU_KEYRING_CHECK:-0}" == "1" ]]; then
  ensure_ubuntu_archive_keyring
fi

# No kernel splash: Plymouth/framebuffer takeover hides printk on tty; GRUB GFX menu stays (bootloaders/splash.png).
# See Build/metadata/ubuntu.env and packaging/$GAMEBIAN_RETROARCH_LIST.
# Parent mirrors must be set explicitly — Debian live-build writes empty URIs in sources.list otherwise.
rm -f "$BUILD_ROOT/config/package-lists/live.list.chroot"
_bootappend="boot=live components username=live"
if [[ -n "${LB_LIVE_USER_PASSWORD:-}" ]]; then
  _bootappend="${_bootappend} user-password=${LB_LIVE_USER_PASSWORD}"
fi
_bootappend="${_bootappend} hostname=${GAMEBIAN_LIVE_HOSTNAME}"
lb config \
  --mode "$LB_MODE" \
  --distribution "$LB_DISTRIBUTION" \
  --parent-distribution "$LB_PARENT_DISTRIBUTION" \
  --parent-debian-installer-distribution "$LB_PARENT_DISTRIBUTION" \
  --archive-areas "$LB_ARCHIVE_AREAS" \
  --parent-mirror-bootstrap "$LB_MIRROR" \
  --parent-mirror-chroot "$LB_MIRROR" \
  --parent-mirror-binary "$LB_MIRROR" \
  --mirror-bootstrap "$LB_MIRROR" \
  --mirror-chroot "$LB_MIRROR" \
  --mirror-binary "$LB_MIRROR" \
  --keyring-packages ubuntu-keyring \
  --linux-flavours "$LB_LINUX_FLAVOURS" \
  --initramfs "$LB_INITRAMFS" \
  --checksums sha256 \
  --debootstrap-options "--variant=minbase" \
  --debian-installer none \
  --binary-image iso-hybrid \
  --bootloaders "grub-pc grub-efi" \
  --bootappend-live "$_bootappend"

if [[ "${LB_FORCE_LIVE_LIST:-0}" == "1" ]]; then
  cat > "$BUILD_ROOT/config/package-lists/live.list.chroot" <<'EOF'
live-boot
live-config
live-config-systemd
systemd-sysv
EOF
  rm -rf "$BUILD_ROOT/config/includes.chroot_before_packages/etc/dracut.conf.d" 2>/dev/null || true
fi

# GRUB: live USB (bootloaders/) + installed disk (gamebian branding PNGs).
INSTALL_GRUB="$SCRIPT_ROOT/../share/gamebian/install-grub-branding.sh"
if [[ -x "$INSTALL_GRUB" ]]; then
  "$INSTALL_GRUB"
else
  echo "WARNING: missing $INSTALL_GRUB — live ISO may show ${GAMEBIAN_GRUB_FALLBACK_MSG}." >&2
fi

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

if [[ -f "$METADATA/$GAMEBIAN_DISTRO_CONF" ]]; then
  mkdir -p "$BUILD_ROOT/config/includes.chroot/etc/gamebian"
  cp -a "$METADATA/$GAMEBIAN_DISTRO_CONF" \
    "$BUILD_ROOT/config/includes.chroot/etc/gamebian/distro.conf"
fi

# APT gaming-repo helper — canonical copy in gamebian-iso-ubuntu/ (see Build/metadata/ubuntu.env).
ENSURE_APT_SRC="$SCRIPT_ROOT/$GAMEBIAN_ENSURE_APT_SCRIPT"
ENSURE_APT_DST="$BUILD_ROOT/config/includes.chroot/usr/share/gamebian/$GAMEBIAN_ENSURE_APT_SCRIPT"
if [[ -f "$ENSURE_APT_SRC" ]]; then
  mkdir -p "$(dirname "$ENSURE_APT_DST")"
  cp -a "$ENSURE_APT_SRC" "$ENSURE_APT_DST"
  chmod 0644 "$ENSURE_APT_DST"
fi

# RetroArch package names for post-install hook + Calamares (not live-build *.list.chroot — see 997 hook).
RETRO_PKG_SRC="$SCRIPT_ROOT/../../Packages/gamebian-web/packaging/$GAMEBIAN_RETROARCH_LIST"
RETRO_PKG_SHARE="$BUILD_ROOT/config/includes.chroot/usr/share/gamebian/$GAMEBIAN_RETROARCH_LIST"
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

# Installed session wallpapers: background.png + per-color PNGs (green.png, …).
INST_ART="$IMAGES/installed"
INST_BG="$INST_ART/background.png"
INST_BG_DEST="$BUILD_ROOT/config/includes.chroot/usr/share/backgrounds/gamebian-installed"
if [[ -d "$INST_ART" ]]; then
  mkdir -p "$INST_BG_DEST"
  if [[ -f "$INST_BG" ]]; then
    cp -a "$INST_BG" "$INST_BG_DEST/background.png"
  fi
  for _color in green yellow blue red black purple; do
    if [[ -f "$INST_ART/${_color}.png" ]]; then
      cp -a "$INST_ART/${_color}.png" "$INST_BG_DEST/${_color}.png"
    fi
  done
fi

# Install branding: LightDM avatar + Gamebian GRUB images (sources in Build/images/).
GAMEBIAN_PIX="$BUILD_ROOT/config/includes.chroot/usr/share/pixmaps"
if [[ -f "$IMAGES/icons/user-installed-icon.png" ]]; then
  mkdir -p "$GAMEBIAN_PIX"
  cp -a "$IMAGES/icons/user-installed-icon.png" "$GAMEBIAN_PIX/"
  SKEL="$BUILD_ROOT/config/includes.chroot/etc/skel"
  mkdir -p "$SKEL"
  _uicon="$IMAGES/icons/user-installed-icon.png"
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
if [[ -x "$INSTALL_GRUB" ]]; then
  "$INSTALL_GRUB" "$BUILD_ROOT/config"
fi

for _icon in menu-icon.png menu-icon-default.png; do
  if [[ -f "$IMAGES/icons/$_icon" ]]; then
    mkdir -p "$GAMEBIAN_PIX"
    cp -a "$IMAGES/icons/$_icon" "$GAMEBIAN_PIX/"
  fi
done
if [[ -f "$GAMEBIAN_PIX/menu-icon-default.png" ]]; then
  mkdir -p "$BUILD_ROOT/config/includes.chroot/usr/share/gamebian"
  cp -a "$GAMEBIAN_PIX/menu-icon-default.png" \
    "$BUILD_ROOT/config/includes.chroot/usr/share/gamebian/controller-menu-icon.png"
fi

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

if [[ -x "$SCRIPT_ROOT/calamares/merge.sh" ]]; then
  "$SCRIPT_ROOT/calamares/merge.sh" "$BUILD_ROOT/config/includes.chroot" "$IMAGES"
fi

for f in "$OVERLAY"/hooks/normal/*.hook.chroot "$OVERLAY"/hooks/normal/*.hook.binary; do
  [[ -f "$f" ]] || continue
  cp -a "$f" config/hooks/normal/
  chmod +x "config/hooks/normal/$(basename "$f")"
done

echo "Resetting build state (next lb build reruns bootstrap + chroot includes)..."
for _p in chroot cache/bootstrap cache/packages.bootstrap cache/chroot; do
  if [[ -e "$_p" ]]; then
    rm -rf "$_p" 2>/dev/null || sudo rm -rf "$_p"
  fi
done
shopt -s nullglob
for _f in .build/bootstrap .build/bootstrap_cache.restore .build/bootstrap_cache.save .build/chroot_* .build/binary_*; do
  if [[ -e "$_f" ]]; then
    rm -f "$_f" 2>/dev/null || sudo rm -f "$_f"
  fi
done
shopt -u nullglob

echo "Configured: overlay merged into $BUILD_ROOT/config"
echo "Artifacts (binary/, iso) go to: $BUILD_ROOT"
echo "gamescope: hook 997 installs from Ubuntu apt (fallback: source build). Needs network for retroarch extras."
echo "N64 core: hook 997 runs gamebian-install-libretro-mupen64plus-next after apt retroarch packages (needs network)."
echo "From here: cd $SCRIPT_ROOT && ./build.sh"
