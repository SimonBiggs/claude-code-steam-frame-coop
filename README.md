# claude-code-steam-frame-coop

**Build co-op games live with Claude Code while your family plays them**: one player in VR on a
Steam Frame, others on the TV, everyone in the same game. Just say what you want ("Hey Claude,
bigger explosions!") and Claude builds it and hot-reloads it into the running game, usually
within a minute.

This repo contains the games built this way, plus the tooling that makes the loop work.

## The loop

```
 Steam Frame (VR host)                 Steam Machine / PC (TV + Claude Code)
 ┌──────────────────────┐   ENet/LAN   ┌────────────────────────────────────┐
 │ Godot game, OpenXR   │◄────────────►│ Godot game client (TV players)     │
 │ simulates the world  │  snapshots   │                                    │
 │ headset mic ─────────┼──── SSH ────►│ voice-bridge: Whisper + speaker ID │
 │                      │              │   → "Simon: Hey Claude, ..."       │
 │ gdev bridge:         │              │ Claude Code                        │
 │  hot reload, frames, │◄── rsync ────┤   edits scripts, tests headless,   │
 │  live MJPEG view     │              │   deploys (both machines reload)   │
 │ "Claude:" captions ◄─┼── frame-say ─┤   watches screenshots/mirror       │
 └──────────────────────┘              └────────────────────────────────────┘
```

1. **Talk.** The Frame's microphone streams to `voice-bridge`, which transcribes with
   faster-whisper, works out who's speaking by voiceprint ("This is Simon" teaches it a name), and
   tags requests addressed to Claude.
2. **Claude builds.** Claude Code watches the transcript, edits the game, runs headless bot tests
   (including a local host + client), and deploys.
3. **Hot reload.** The `gdev` bridge inside the game reloads changed scripts in place on the VR
   host and the TV client, so nobody restarts and the wave keeps going.
4. **Claude watches.** Recorded frames and a live MJPEG mirror of the VR view (`frame-mirror`) let
   Claude see what the players see. `gdev at 17:42:10` shows the frames around a moment with
   change highlights.
5. **Claude replies.** `frame-say "..."` puts a message in the headset and on the TV.

## What's in the box

| Path | What it does |
|---|---|
| `scripts/` | **Duo Arena**, the first game (see below) |
| `scripts/net.gd` | VR host + TV client networking: 30 Hz snapshots, events, client-side movement |
| `addons/gdev/bridge.gd` | In-game dev helper: hot reload, frame recording, commands, live view on `:8090` |
| `tools/gdev` | CLI: start/stop/restart the game, logs, screenshots, `gdev at TIME` timelines |
| `tools/voice-bridge` | Headset mic → Whisper (`medium.en`) + speaker identification → transcript log |
| `tools/frame-say` | Show a "Claude:" message in VR and on the TV |
| `tools/frame-mirror` | Open the live view of what the VR player sees |
| `tools/duo-deploy`, `tools/duo-deploy-frame` | Ship changes to both machines (hot reload) and commit |

## The games

Pick from the arcade lobby: the TV shows a picker, and the VR player can choose with the right stick + trigger.

| Game | Theme | VR player | TV players |
|---|---|---|---|
| **Duo Arena** | neon arena shooter | gun, shield parry, wrist radar | shoot, dash, build turrets |
| **Ghost Lantern** | spooky-cute haunted mansion | spirit lantern reveals and stuns ghosts, bell scares them | ghost vacuums catch revealed ghosts |
| **Snowball Blitz** | cosy winter snow fort | scoop, pack and really throw snowballs, pan-lid shield | lob snowballs, rebuild the fort walls |
| **Cannon Cove** | pirates at sunset | grab and swing the cannons, spyglass | haul cannonballs, patch leaks, musket boarders |
| **Kitchen Rush** | cartoon cooking chaos | chop with a real knife swing, plate up orders | fetch ingredients, serve customers, fight fires |
| **Giant's Table** | cosy fantasy tabletop village | a giant: grab and throw goblins, ogres and boulders | tiny knights with sword and crossbow, carry embers home |
| **Rocket Workshop** | cartoon launch pad, talk-it-through puzzles | works the desk: buttons, plugs, dials, the launch lever | find the blueprints and read them out, carry fuel, fix pipes |
| **Marble Maze** | toy ball racing | tilts a giant tabletop maze by its handles | race through the maze as marbles |
| **Hide and Seek** | cosy cartoon house | the seeker, with a torch | hide, or disguise as a lamp, plant or box |
| **Block Builders** | floating sky course | a giant builder placing planks, stairs, springs, fans | tiny runners racing to the flag |
| **Dragon Rider** | sunset sky islands | steers a friendly dragon with the reins | gunners on its back popping balloons and storm sprites |
| **Bee Garden** | sunny garden, no fighting | plants, waters, shoos wasps | bees collecting pollen to fill the honey jars |

Every game takes up to 6 TV players: plug in another controller and press A to join.

## Duo Arena (game #1)

A neon first-person co-op arena shooter, designed out loud by a family during one evening's play.

- **VR + TV co-op over the network**, or split screen. A third player can join on the TV with a
  second controller or keyboard and mouse.
- **VR player:** aim with the right controller, use the left-hand shield to reflect orbs, and check
  the wrist radar and stats. The menu button pauses everyone. Runs at 72 fps on the Frame (Mobile renderer).
- **Enemies:** grunts, runners, brutes, spitters, splitters, T-rex dinosaurs and a ground-slamming
  boss that enrages if you farm it.
- **Fishwort**, a giant flying fish that spits fireballs. You can shoot the fireballs, or the fish.
- **Skill map** on the arena floor: earn your own XP, shoot nodes to buy upgrades, and build turrets.
- **Co-op beam** between nearby players, revives, 16 achievements, score popups, big explosions,
  procedural sound effects and three procedural synthwave tracks.

Everything is generated in code: no imported models, textures or audio.

### Running

```sh
godot --path .                     # split screen
DUO_HOST=1 godot --path .          # host (automatic when an OpenXR headset is found)
DUO_JOIN=<host> godot --path .     # join as the TV player(s)
```

On a Steam Frame, run the Linux Arm64 Godot with `--rendering-method mobile`, installed as a
devkit title (SteamOS Devkit Client, user `steamos`; the game id must not contain `-`).

| | Controller | Keyboard + mouse | VR |
|---|---|---|---|
| Move | Left stick | WASD | Left stick |
| Look / turn | Right stick | Mouse | Head / right stick snap turn |
| Shoot | RT / RB | Click / Space | Trigger |
| Dash | A / LB / LT | Shift | A |
| Menu | Start | Esc | Left menu button |

## Notes from building it

- Streaming VR from a Steam Machine to the Steam Frame wasn't supported yet, so the game runs
  natively on the Frame and the TV joins over the network.
- OpenXR must render on the **main** viewport (a SubViewport gave a "theatre" view). Move the XR
  origin in `_process`, not physics, or it judders.
- Under hot reload, static variables keep old values, and nodes built in `_ready` need replacing.
  An error in `_process` silently skips the rest of the frame, so check the logs.
- WorkerThreadPool tasks must be waited on, or their memory leaks.

## License

Apache License 2.0. See [LICENSE](LICENSE).
