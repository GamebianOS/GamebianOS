#!/usr/bin/env bash
# Run from Build/openbox-live; live-build cwd is GAMEBIANOS_BUILD_ROOT.

set -euo pipefail
SCRIPT_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_ROOT="${GAMEBIANOS_BUILD_ROOT:-/home/khinds/gamebianos-build-iso}"

if [[ ! -d "$BUILD_ROOT/config" ]]; then
  echo "No live-build config — run first: cd $SCRIPT_ROOT && ./setup.sh" >&2
  exit 1
fi

if [[ ! -f "$BUILD_ROOT/.build/config" ]]; then
  echo "Missing stage file $BUILD_ROOT/.build/config." >&2
  echo "Fix: cd $SCRIPT_ROOT && ./setup.sh" >&2
  exit 1
fi

# Drop all binary stage markers so binary_chroot/binary_rootfs/iso always match
# the current chroot. Stale binary_chroot (after ./setup.sh reset chroot, or a
# failed build) caused: mksquashfs "Cannot stat source directory \"chroot\"".
shopt -s nullglob
_stale=( "$BUILD_ROOT"/.build/binary_* )
shopt -u nullglob
for _f in "${_stale[@]}"; do
  rm -f "$_f" 2>/dev/null || sudo rm -f "$_f"
done

cd "$BUILD_ROOT"
exec sudo lb build "$@"
