#!/usr/bin/env bash
# Run from Build/gamebian-iso-ubuntu; live-build cwd from Build/metadata/ubuntu.env.

set -euo pipefail
SCRIPT_ROOT="$(cd "$(dirname "$0")" && pwd)"
METADATA="$(cd "$SCRIPT_ROOT/../metadata" && pwd)"
# shellcheck source=/dev/null
source "$METADATA/ubuntu.env"
_build_var="${GAMEBIAN_BUILD_ROOT_VAR}"
BUILD_ROOT="${!_build_var:-$GAMEBIAN_BUILD_ROOT_DEFAULT}"

if [[ ! -d "$BUILD_ROOT/config" ]]; then
  echo "No live-build config — run first: cd $SCRIPT_ROOT && ./setup.sh" >&2
  exit 1
fi

if [[ ! -f "$BUILD_ROOT/.build/config" ]]; then
  echo "Missing stage file $BUILD_ROOT/.build/config." >&2
  echo "Fix: cd $SCRIPT_ROOT && ./setup.sh" >&2
  exit 1
fi

shopt -s nullglob
_stale=( "$BUILD_ROOT"/.build/binary_* )
shopt -u nullglob
for _f in "${_stale[@]}"; do
  rm -f "$_f" 2>/dev/null || sudo rm -f "$_f"
done

cd "$BUILD_ROOT"
exec sudo lb build "$@"
