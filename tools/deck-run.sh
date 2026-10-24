#!/bin/bash
# The one arcade launcher (any Steam Deck; the same idea everywhere): it only starts Godot. What this machine is,
# how it networks (play locally at once and keep looking for other devices on the home network) and the screen
# size are decided by the game itself (core/machine.gd, net.gd), so changes hot-reload instead of needing a relaunch.
# Log: game/.dev/game.log
cd "$(dirname "$0")"
unset LD_PRELOAD  # Steam's 32-bit overlay preload only spams errors into a 64-bit game
# Close an older copy of this arcade (match by its working directory: the command line is just ./godot).
for p in $(pgrep -x godot); do [ "$(readlink /proc/$p/cwd)" = "$PWD" ] && kill "$p"; done; sleep 0.5
mkdir -p game/.dev
[ -f game/.dev/game.log ] && mv game/.dev/game.log game/.dev/game.log.1
[ "$1" = "--solo" ] && export DUO_SOLO=1 && shift  # (old Steam entries; normally not needed)
exec ./godot --path ./game --fullscreen "$@" > game/.dev/game.log 2>&1
