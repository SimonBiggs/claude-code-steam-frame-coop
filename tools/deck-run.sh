#!/bin/bash
# Duo Arena on a Steam Deck. Default: join the family game hosted by the VR player on the Steam Frame as
# another TV-style player (DUO_MACHINE_KIND=deck, so games can treat Deck players specially).
# --solo, or the Frame not answering within a second: play straight away on the Deck alone (local mode,
# the Deck's own controls; more pads can drop in). Log: game/.dev/game.log
cd "$(dirname "$0")"
pkill -f 'DuoArena/godot' && sleep 1
mkdir -p game/.dev
[ -f game/.dev/game.log ] && mv game/.dev/game.log game/.dev/game.log.1
export DUO_MACHINE_KIND=deck
FRAME="${DUO_FRAME:-192.168.0.229}"  # the Steam Frame (its LAN name doesn't always resolve)
if [ "$1" != "--solo" ] && ping -c1 -W1 "$FRAME" >/dev/null 2>&1; then
  export DUO_JOIN="${DUO_JOIN:-$FRAME}"
else
  unset DUO_JOIN
fi
[ "$1" = "--solo" ] && shift
# The Deck's own screen size (1280x800, 16:10), fullscreen: the games stretch to any aspect ("expand"), so no black
# bars or scaling. An external display can override with DUO_RESOLUTION=1920x1080.
exec ./godot --path ./game --fullscreen --resolution "${DUO_RESOLUTION:-1280x800}" "$@" > game/.dev/game.log 2>&1
