#!/bin/bash
# Steam launcher "Arcade VR": the arcade, asking for VR. It only adds DUO_VR_WANT=1; core/vr_watch.gd does the rest
# (starts SteamVR if needed, shows "Put the Frame on and choose Steam Machine" on the TV, restarts into VR when the
# headset is there). Same game, same gdev supervisor as launch.sh (Simon's rule: launchers decide nothing).
export DUO_VR_WANT=1
exec "$(dirname "$(readlink -f "$0")")/launch.sh" "$@"