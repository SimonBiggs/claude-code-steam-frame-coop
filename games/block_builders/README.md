# Block Builders

A co-op puzzle platformer on a floating obstacle course in the sky.

- **Player 1, the BUILDER (VR, host).** `XROrigin3D.world_scale = 8`, so the course is a tabletop
  diorama in front of you (a block is 12.5 cm). A tray of colourful blocks floats beside your right
  hand: planks, stairs, springs and fans. Pick one up with the right trigger, hold it over the course
  (it snaps to the grid: green means it fits) and let go to place it. Each level has a limited number
  of blocks, so it's a puzzle.
- **Players 2 to 7, the RUNNERS (TV).** Up to six tiny third-person runners who must reach the flag.
  Gaps, lava, gusts of wind and rising water send you back to your last safe spot. A level clears
  when every active runner is at the flag, with a big burst of confetti.

Levels: First Bridge (planks), Lava Steps (stairs), Bounce House (springs), Windy Ridge (railings and
fans), Rising Tide (rising water), Sky Castle (all of it). The timer gets 8% longer for each runner
beyond two, and a party of 4 or more gets a spare plank.

## Controls

| Who | Controls |
|---|---|
| Builder (VR) | Right trigger near a tray block: pick it up. Let go over the course: place it (let go near the tray, or where it doesn't fit, to put it back). Right trigger near a placed block: pick it up again. A: turn the held block (stairs, fans). Left stick: walk around the course. Right stick left/right: snap turn; up/down: raise or lower yourself. Trigger: start / next level / try again. MENU on the left wrist: pause. |
| Builder (flat, split screen) | Mouse or the 2nd controller's left stick: move the glove. Left click / A / RT: place. Right click / B / LT: remove. Q E / LB RB / 1-4: pick a block. Wheel / D-pad / Z X: change the height. R / Y: turn. |
| Runners | Left stick / WASD: run. A / RB / RT / Space: jump. Right stick / arrow keys (or the mouse on the TV): turn the camera. Press A on any spare controller to drop in as the next runner (Start is the pause menu). Each controller drives one runner: unplug it and that runner leaves, plug it back in and they rejoin. A / Enter: start / next level / try again. |

The VR builder's left-hand buttons and grip don't reach the game on the Steam Frame, so everything
uses the right trigger, A, the sticks and hand positions. The headset is fitted to whoever wears it
(sitting, standing or a short kid) and re-fitted when the head height changes a lot for a few seconds.

## Modes

As in `docs/GAME_DEV_GUIDE.md`: headset or `DUO_HOST=1` is the host (builder in VR, or flat without a
headset), `DUO_JOIN=<host>` is the TV (runners in a split-screen grid: 1 full, 2 side by side, 3-4 as
2x2, 5-6 as 3x2), otherwise local split screen (flat builder plus runners).

## Files

`main.gd` (modes, joining, views, level flow, snapshots, HUD), `course.gd` (level geometry, blocks,
collision spans, hazards), `levels.gd` (level data plus the bot's known solutions), `builder.gd`
(VR / flat / TV ghost builder and the tray), `runner.gd` (runners), `art.gd` (procedural meshes).

## Tests

```sh
godot --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/block_builders_bot.tscn
BOT_PLAYERS=6 godot --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/block_builders_bot.tscn
DUO_PORT=7912 DUO_HOST=1 timeout 45 godot --headless --path . res://tests/block_builders_bot.tscn &
DUO_PORT=7912 DUO_JOIN=127.0.0.1 BOT_PLAYERS=3 timeout 38 godot --headless --path . res://tests/block_builders_bot.tscn
```

Bot options: `BB_FAKE_VR=1` runs the VR builder code without a headset (the bot moves the right
controller node to the tray and over the course), `BB_START_LEVEL=n` starts at level n, and
`BOT_PLAYERS=n` (2-6) joins n runners (the last one through a fake controller that is unplugged at
22 s and plugged back in at 28 s).
