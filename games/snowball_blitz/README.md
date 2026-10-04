# Snowball Blitz

Cosy co-op snowball fight. Defend your snow fort in a village square at dusk from waves of
mischievous snowmen (top hats, carrot noses, giants, sled riders, and the Snow King every 4th wave).

## Simple mode (default: `SIMPLE_MODE := true` in main.gd)

The family found the games too complicated and too wordy, so by default it's just: **defend the fort
from waddling snowmen by throwing snowballs.** Everything below "Full mode" is behind that one flag.

- **Practice first:** the VR player gets glowing target snowmen close by, one at a time, and a
  see-through ghost hand that reaches down, scoops, winds up and throws. Each TV player gets one
  glowing target in front of them (and "PRESS RT!" until they throw). Then the snowmen come. A solo
  VR player gets extra targets for ~40 s, then the waves start anyway (TV players can drop in).
- **One new thing per wave:** 1 a few slow plain snowmen that don't throw, 2 they throw (harmless
  splats; the pan lid blocks them), 3 sled riders, 4 snow bunnies, 5 giants (they can drop a MEGA
  SNOWBALL), 6 balloon snowmen, 7 the SNOW KING, 8-9 a mix, 10 the YETI finale (VICTORY, sunrise),
  then endless.
- **Touch everything (VR):** snow piles at your feet (squeeze there for a big snowball), icicles
  on a little rack (tinkle; squeeze one to snap it off and throw it), a snowy pine (dumps its snow),
  a sled (shove it), a bell (DING), and the fort wall puffs and packs up a little when you pat it.
- **TV:** press throw to throw (hold to keep throwing); a gentle aim assist helps.
- **Off:** warmth, freezing and hot cocoa; wall packing (the walls snow back up by themselves);
  charged lobs; shield snowmen; weather; fort upgrades; streaks; score / warmth / fort readouts, the
  minimap and popups; hint panels; awards. Text is one headline ("WAVE 2!", "SNOW KING!", "HOORAY!",
  "OH NO!"); the VR wrist shows "WAVE n". Game over restarts by itself after 7 s.

## Full mode (`SIMPLE_MODE := false`)

- **VR player (host, Steam Frame), the sniper:** squeeze grip or trigger with your right hand down low
  (reach toward the snow) to scoop a snowball. Keep squeezing to pack it bigger and harder. Throw for
  real and let go: the launch velocity comes from your hand's motion, with a gentle aim assist.
  Your left hand holds a pan lid that blocks the snowmen's icy blue snowballs. Left stick moves you
  inside the fort, right stick snap-turns. Haptics fire on scoop, packing, throw, hit and block.
- **TV players (first person), the builders:** hold throw to charge a lobbed snowball (a ring on the
  snow shows where it will land) and release to throw. Hold repair next to a crumbling fort wall to
  pack it back up. Walk over hot cocoa to warm up.
- Snowballs make you colder. At 0 warmth you freeze into an ice block until a friend stands next to
  you. The game ends when everyone is frozen or every fort wall is down.
- **Easier VR throwing** (tired arms): squeeze the trigger anywhere for a snowball (reaching down to the
  snow gives a bigger, half-packed one), packing takes 0.7 s, gentle flicks are boosted, and a stronger
  aim assist bends throws onto a lob that reaches the snowman you were throwing at.
- **MEGA SNOWBALL** (glowing blue ball, sometimes dropped by giants, every 3rd wave, cocoa parties):
  your next throw is giant and splashes every snowman nearby.
- New snowmen: **snow bunnies** (tiny, in threes), **balloon snowmen** (float over the walls - pop the
  balloons), **shield snowmen** (an ice shield blocks flat throws from the front - lob over it, hit from
  the side, or break it), and the **YETI** finale boss on wave 12 (stomps walls, calls bunnies).
- **Fort upgrades**: snowball catapult (after wave 2), ice walls (wave 5), campfire that warms you
  (wave 8). **Weather**: blizzard (snowmen slow), sunshine (snowmen melt), cocoa party. Dusk turns into
  an aurora night; beat the yeti for a sunrise VICTORY, then endless waves.
- Hit streaks give bonus points; the end screen shows **awards** (SNOW SNIPER, FORT BUILDER, ...).

| | Throw | Repair (pack wall) | Move / look |
|---|---|---|---|
| Controller | hold RT / RB | X / LB / LT | sticks |
| Keyboard P1 | hold click / Space | E / right-click | WASD + mouse |
| Keyboard P2 | hold Enter | Ctrl | arrows (turn) |

**Party mode (up to 6 TV players + VR):** players 2-3 on the TV work as before (first controller =
P2, keyboard+mouse / second controller = P3, hold throw to join). Any other controller presses
**A / Start** to join as the next free player (P4-P7; in split screen without VR, P3-P6). Each
controller belongs to one player; unplugging a controller-only player makes them leave, plugging the
same controller back in rejoins them. Split screen: 1 full, 2 side by side, 3-4 as 2x2, 5-6 as 3x2
(lower 3D resolution and a smaller HUD with more views). Waves grow a little with more than 3 players.

Restart after game over: A / Enter (VR: trigger).
Test (`BOT_PLAYERS=N` joins N TV players, `BOT_PAD_TEST=1` checks controller join/unplug/replug,
`BOT_VR=1` fake VR thrower, `BOT_WAVE=12 BOT_GOD=1 BOT_END=380` plays the yeti finale): `godot --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/snowball_blitz_bot.tscn`
