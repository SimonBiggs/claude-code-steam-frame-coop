#!/bin/bash
# Steam launcher for Duo Arena: runs the game through gdev (hot reload + recording) and waits for it.
export PATH="$HOME/.local/bin:$PATH"
# Use SteamVR as the OpenXR runtime (Steam Frame / any SteamVR headset) when it's installed.
STEAMXR="$HOME/.local/share/Steam/steamapps/common/SteamVR/steamxr_linux64.json"
[ -f "$STEAMXR" ] && export XR_RUNTIME_JSON="$STEAMXR"
# Who to join is decided in code (core/machine.gd: "auto" = play here at once and join whatever host is found on
# the home network: the Frame, a Deck or another TV). Pinning the Frame here made the TV chase it when a Deck was
# hosting, reloading the game every 5 s (the TV flashed black, 2026-10-24).
exec gdev run "$HOME/GodotProjects/duo-arena"
