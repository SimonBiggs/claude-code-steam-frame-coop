# Block Builders

A co-op puzzle platformer on a floating obstacle course in the sky.

## SIMPLE_MODE (on: `const SIMPLE_MODE := true` in main.gd)

The family found the games too complicated and Block Builders "a wall of text" in VR, so by default it's
just: **the builder grabs blocks from the tray and makes a path, the runners run to the flag.**

- No timer, score, stars, gift balloons, high-five rules, tips or awards; you can't fail. Falling just
  pops you back up with a boing. Clearing a level is a HOORAY and confetti, then the next one starts.
- Eight short levels (`levels.gd` SIMPLE_LEVELS): one gap to bridge, two bridges, then ONE new block
  per level: stairs, crates, a spring, a fan, a launch pad, and a rainbow finale.
- Practice: level 1 is one gap. A glowing see-through block shows where the plank goes, and the VR
  builder sees a ghost hand (`ghost_hand.gd`) take a plank from the tray and drop it in. The runners
  get a glowing ring to jump through over the new bridge, then the flag. On later levels the glowing
  block shows where the first block goes straight away. The tray shows what's left as little cubes.
- Everything in reach reacts (`props.gd`): toy blocks on a little cloud by your left hip (knock them
  over, stack them, grab one with the trigger and throw it), balloons that pop and grow back, birds
  that flap away, fluffy clouds that puff, the flag waves, and touching a runner gives them a boop.
- Solo VR: with no TV machine, P2 is a buddy runner who waits at the gap for your bridge.
- Text: only a short headline (BLOCK BUILDERS, the level name, HOORAY!); one line of controls on the TV.

Everything below describes the full game (SIMPLE_MODE = false).

- **Player 1, the BUILDER (VR, host).** `XROrigin3D.world_scale = 8`, so the course is a tabletop
  diorama in front of you (a block is 12.5 cm). A tray of colourful blocks sits low in front of your
  right hip (fitted to your height, well away from your face; it glides after you if you walk away
  from it): only the blocks this level uses. Pick one up with the right trigger, hold it over the
  course (it snaps to the grid: green means it fits) and let go to place it. Each level has a limited
  number of blocks, so it's a puzzle. A bouncing arrow shows the tray until you grab your first block,
  and if you seem stuck a glowing see-through HINT block shows where a block could go.
- **Players 2 to 7, the RUNNERS (TV).** Up to six tiny third-person runners who must reach the flag.
  Gaps, lava, gusts of wind and rising water send you back to your last safe spot. A level clears
  when every active runner is at the flag, with a big burst of confetti.

Blocks: PLANK (bridges), STAIRS, CRATE (full blocks: stack them, jump up them), SPRING (boing!), FAN
(updraft), SPEED PAD (zoom along its arrow: jump at the edge for a long jump), LAUNCH PAD (flings
runners over a gap along its arrow). A turns the held block.

Ten themed levels, each introducing one idea: First Bridge (meadow), Lava Steps (volcano), Crate
Canyon (desert canyon), Bounce House (candy land), Windy Ridge (snowy peaks), Zoom Zone (night sky with
glowing crystals), Rising Tide (beach), Launch Pad (autumn), Sky Castle (castle) and the Rainbow Summit
finale (fireworks, a rainbow, crowns for everyone and an awards screen).

Co-op extras:
- **Stars**: three per level (some need a jump or a bounce). Each one gives the builder a spare block.
- **Gift balloon**: from level 2 a balloon with a present drifts across. Runners jump into it, or the
  builder grabs it with their hand and carries it down to a runner (SPECIAL DELIVERY): +2 blocks.
- **High fives**: touch a runner who reached the flag with the giant hand.
- **Bonuses**: team finish (everyone at the flag within 6 s), no tumbles (with a streak), all stars.
- **Awards** at the end: Star Catcher, Speedy Sneakers, Bouncy Bunny, High-Five Hero, Gift Grabber,
  Bravest Tumbler and Master Builder.

The timer gets 8% longer for each runner beyond two, and a party of 4 or more gets a spare plank.
Islands are solid cliffs (you can't walk under a high ledge).

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

`main.gd` (modes, joining, views, level flow, stars / gift / high fives / hints, bonuses, awards,
snapshots, HUD), `course.gd` (level geometry, themed decoration, blocks, collision spans, hazards),
`levels.gd` (level data plus the bot's known solutions), `themes.gd` (sky, colours, props, music per
theme), `builder.gd` (VR / flat / TV ghost builder and the tray), `runner.gd` (runners), `art.gd`
(procedural meshes).

## Tests

```sh
godot --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/block_builders_bot.tscn
BOT_PLAYERS=6 godot --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/block_builders_bot.tscn
DUO_PORT=7912 DUO_HOST=1 timeout 45 godot --headless --path . res://tests/block_builders_bot.tscn &
DUO_PORT=7912 DUO_JOIN=127.0.0.1 BOT_PLAYERS=3 timeout 38 godot --headless --path . res://tests/block_builders_bot.tscn
```

Bot options: `BB_FAKE_VR=1` runs the VR builder code without a headset (the bot moves the right
controller node to the tray and over the course; it also grabs the gift balloon on level 2, carries it
to P2, and high-fives runners at the flag), `BB_START_LEVEL=n` starts at level n, and
`BOT_PLAYERS=n` (2-6) joins n runners (the last one through a fake controller that is unplugged at
22 s and plugged back in at 28 s).
