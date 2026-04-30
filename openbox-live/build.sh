#!/usr/bin/env bash
# Run from Build/openbox-live; live-build cwd is GAMEBIANOS_BUILD_ROOT.

set -euo pipefail
SCRIPT_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_ROOT="${GAMEBIANOS_BUILD_ROOT:-/home/khinds/gamebianos-build-openbox}"

if [[ ! -d "$BUILD_ROOT/config" ]]; then
  echo "No live-build config — run first: cd $SCRIPT_ROOT && ./setup.sh" >&2
  exit 1
fi

if [[ ! -f "$BUILD_ROOT/.build/config" ]]; then
  echo "Missing stage file $BUILD_ROOT/.build/config." >&2
  echo "Fix: cd $SCRIPT_ROOT && ./setup.sh" >&2
  exit 1
fi

# Recover from stale binary stage state (common after package-list edits).
for _f in \
  "$BUILD_ROOT/.build/binary_rootfs" \
  "$BUILD_ROOT/.build/binary_manifest" \
  "$BUILD_ROOT/.build/binary_package-lists" \
  "$BUILD_ROOT/.build/binary_linux-image"; do
  if [[ -e "$_f" ]]; then
    rm -f "$_f" 2>/dev/null || sudo rm -f "$_f"
  fi
done

cd "$BUILD_ROOT"
exec sudo lb build "$@"
