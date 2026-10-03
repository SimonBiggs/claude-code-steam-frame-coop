# Snowball Blitz

Cosy co-op snowball fight. Defend your snow fort in a village square at dusk from waves of
mischievous snowmen (top hats, carrot noses, giants, sled riders, and the Snow King every 4th wave).

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

| | Throw | Repair (pack wall) | Move / look |
|---|---|---|---|
| Controller | hold RT / RB | X / LB / LT | sticks |
| Keyboard P1 | hold click / Space | E / right-click | WASD + mouse |
| Keyboard P2 | hold Enter | Ctrl | arrows (turn) |

Restart after game over: A / Enter (VR: trigger).
Test: `godot --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/snowball_blitz_bot.tscn`
