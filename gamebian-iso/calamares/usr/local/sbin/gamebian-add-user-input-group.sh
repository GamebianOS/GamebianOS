#!/bin/sh
# Calamares shellprocess (target chroot): add the desktop/autologin user to
# `input` (gamepads) and `render` (Vulkan /dev/dri/renderD* for gamescope).
#
# Inline shell with ${_u} cannot live in shellprocess YAML — Calamares expands
# ${var} itself and fails with "Missing variables: _u".
set -eu

. /usr/share/gamebian/gamebian-lightdm-user.sh 2>/dev/null || exit 0

_u="$(gamebian_lightdm_autologin_user 2>/dev/null || true)"
if [ -n "${_u:-}" ]; then
	usermod -aG input,render,video "${_u}" 2>/dev/null || usermod -aG input "${_u}" 2>/dev/null || true
fi
exit 0
