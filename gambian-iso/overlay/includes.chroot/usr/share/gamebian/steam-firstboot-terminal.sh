#!/usr/bin/env bash
# First disk-login helper: Steam script output stays in this terminal while the launcher runs.

set +e

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games${PATH:+:$PATH}"

steam_bin=""
for _c in /usr/bin/steam /usr/local/bin/steam /usr/games/steam; do
	if [ -x "${_c}" ]; then
		steam_bin="${_c}"
		break
	fi
done

if [ -z "${steam_bin}" ]; then
	echo "Steam is not installed (no steam executable in /usr/bin, /usr/local/bin, or /usr/games)." >&2
	echo "Install with: sudo apt update && sudo apt install -y steam-installer" >&2
	read -r -p "$(printf '\nPress Enter to close.')" || true
	exit 1
fi

echo "Starting Steam… output below is from Valve’s launcher script."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"${steam_bin}"
code=$?

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Steam launcher exited with code ${code}."
echo "If the graphical Steam window is installing updates, let it finish there."
echo "Full log may also be written to: ~/.steam/steam/logs/console-linux.txt"

read -r -p "$(printf '\nPress Enter to close this window when you are done. ')"

mkdir -p "${HOME}/.config"
touch "${HOME}/.config/gamebian-firstboot-steam.done"
echo ""
echo "First-time Steam setup is marked complete."
echo "On your next login, Steam will start inside gamescope (fullscreen) as the default session."
echo "Quit Steam from the UI to return to the login screen; pick Openbox at the greeter if you need the full desktop."
