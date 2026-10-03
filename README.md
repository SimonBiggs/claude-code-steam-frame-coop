# Duo Arena

A neon co-op arena shooter made in Godot 4.7. Players fight waves of enemies together, either in
split screen or with one player in VR on a **Steam Frame** and others on the TV, connected over
the home network.

The family designed it while playing: most features started as spoken requests ("Hey Claude,
bigger explosions!") that were built and hot-reloaded into the running game.

## Features

- **First-person co-op** for 2 players in split screen, or **VR + TV** over the network. A third
  player can join on the TV with a second controller or keyboard and mouse.
- **VR player** (Steam Frame, OpenXR): aim with the right controller, use the left-hand shield to
  reflect orbs, and check the wrist radar and status. The menu button pauses everyone.
- **Enemies:** grunts, runners, brutes, spitters, splitters, T-rex dinosaurs and a ground-slamming boss.
- **Fishwort:** a giant flying fish in the sky that spits fireballs. You can shoot the fireballs,
  or the fish itself.
- **Co-op beam** between nearby players that zaps enemies, plus revives and shared wave upgrades.
- **Skill map** on the arena floor: earn your own XP, shoot nodes to buy upgrades, and build turrets.
- **16 achievements**, floating score popups, big explosions, procedural sound effects and three
  procedural synthwave music tracks.

Everything is generated in code: no imported models, textures or audio files.

## Running

```sh
godot --path .                 # split screen (keyboard + mouse and/or controllers)
DUO_HOST=1 godot --path .      # host a networked game (automatic when a VR headset is found)
DUO_JOIN=<host> godot --path . # join a host as the TV player(s)
```

Use the Mobile renderer for VR on standalone headsets: `godot --rendering-method mobile --path .`.

### Controls

| | Controller | Keyboard + mouse |
|---|---|---|
| Move | Left stick | WASD (P2 in split screen: arrows) |
| Look | Right stick | Mouse |
| Shoot | RT / RB | Click / Space |
| Dash | A / LB / LT | Shift |
| Menu | Start | Esc |

VR: left stick moves, right stick snap-turns, trigger shoots, A dashes, and the left menu button pauses.

## Project layout

- `scripts/main.gd`: game setup, waves, networking glue, HUD
- `scripts/player.gd`: first-person, VR, remote and ghost players
- `scripts/net.gd`: ENet host/client (snapshots + events)
- `scripts/enemy.gd`, `fish.gd`, `skill_map.gd`, `turret.gd`, `achievements.gd`, `music.gd`, `world.gd`, …
- `addons/gdev/bridge.gd`: development helper (hot reload, frame recording, live view on :8090)
- `tests/`: headless bot tests (`godot --headless --path . res://tests/bot.tscn`)

## License

Apache License 2.0. See [LICENSE](LICENSE).
