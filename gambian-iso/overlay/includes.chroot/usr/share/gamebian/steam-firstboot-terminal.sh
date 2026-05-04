#!/usr/bin/env bash
# First disk-login helper: Steam script output stays in this terminal while the launcher runs.

set +e

if ! command -v steam >/dev/null 2>&1; then
	echo "Steam is not installed. Trying apt install steam-installer (needs admin password + network)." >&2
	if command -v pkexec >/dev/null 2>&1; then
		pkexec env DEBIAN_FRONTEND=noninteractive bash -c 'apt-get update && (apt-get install -y steam-installer || apt-get install -y steam-launcher)' \
			|| {
				echo "Install failed — run manually: sudo apt update && sudo apt install -y steam-installer" >&2
				read -r -p "$(printf '\nPress Enter to close.')" || true
				exit 1
			}
	else
		echo "pkexec unavailable — run manually: sudo apt update && sudo apt install -y steam-installer" >&2
		read -r -p "$(printf '\nPress Enter to close.')" || true
		exit 1
	fi
fi

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
