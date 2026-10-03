#!/bin/bash
# Steam launcher for Duo Arena: runs the game through gdev (hot reload + recording) and waits for it.
export PATH="$HOME/.local/bin:$PATH"
# Use SteamVR as the OpenXR runtime (Steam Frame / any SteamVR headset) when it's installed.
STEAMXR="$HOME/.local/share/Steam/steamapps/common/SteamVR/steamxr_linux64.json"
[ -f "$STEAMXR" ] && export XR_RUNTIME_JSON="$STEAMXR"
# Join the VR player's game on the Steam Frame as player 2 (falls back to split screen if it isn't running).
export DUO_JOIN="${DUO_JOIN:-frame}"
exec gdev run "$HOME/GodotProjects/duo-arena"
