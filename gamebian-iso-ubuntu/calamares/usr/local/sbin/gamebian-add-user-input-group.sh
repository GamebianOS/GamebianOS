#!/bin/sh
# Calamares shellprocess (target chroot): add the desktop/autologin user to `input`.
#
# Inline shell with ${_u} cannot live in shellprocess YAML — Calamares expands
# ${var} itself and fails with "Missing variables: _u".
set -eu

. /usr/share/gamebian/gamebian-lightdm-user.sh 2>/dev/null || exit 0

_u="$(gamebian_lightdm_autologin_user 2>/dev/null || true)"
[ -n "${_u:-}" ] && usermod -aG input "${_u}" 2>/dev/null || true
exit 0
