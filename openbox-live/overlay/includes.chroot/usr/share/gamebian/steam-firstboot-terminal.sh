#!/usr/bin/env bash
# First disk-login helper: Steam script output stays in this terminal while the launcher runs.

set +e
echo "Starting Steam… output below is from Valve’s launcher script."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
steam
code=$?

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Steam launcher exited with code ${code}."
echo "If the graphical Steam window is installing updates, let it finish there."
echo "Full log may also be written to: ~/.steam/steam/logs/console-linux.txt"

read -r -p "$(printf '\nPress Enter to close this window when you are done. ')"

mkdir -p "${HOME}/.config"
touch "${HOME}/.config/gamebian-firstboot-steam.done"
