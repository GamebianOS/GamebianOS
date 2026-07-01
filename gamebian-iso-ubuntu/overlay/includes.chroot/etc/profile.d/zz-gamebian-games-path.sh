# Steam and gamescope may install under /usr/games (not always on default PATH).
if [ -d /usr/games ]; then
	PATH="/usr/games:${PATH}"
	export PATH
fi
