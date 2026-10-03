# Ghost Lantern

A spooky-but-cute co-op ghost hunt in a haunted mansion with three rooms: library, hall and ballroom.
Cheeky ghosts steal the family photos and say BOO to players. Ghosts are **invisible** except
inside the spirit lantern's light.

## Roles

- **P1, lantern-bearer (VR, or keyboard + mouse in split screen)**: points the spirit lantern.
  Ghosts in its light cone show up for everyone. A ghost that stays in the beam gets stunned and drops
  its photo. Focusing the beam makes it narrower and longer, and it stuns twice as fast. The hand bell
  scares every ghost within 9 m away for a few seconds, and they drop their photos. It has a 6 s cooldown.
- **P2 / P3, ghost vacuums (TV)**: hold fire to suck in a ghost **that the lantern is lighting**.
  A capture bar fills while the ghost struggles. Stunned ghosts are easier to catch. Their torches only
  light the room. They can't reveal ghosts, so shout to P1 where you need the light!

When a ghost touches you, you lose courage. With no courage left you're spooked: stand next to a
spooked friend to cheer them up. Nights get busier. The game ends if everyone is spooked or the ghosts
carry every photo out of the mansion.

## Controls

| | VR | Flat screen |
|---|---|---|
| Lantern (P1) | right hand aims, right trigger focuses | mouse aims, Space / left click focuses |
| Bell (P1) | shake the left controller (or left trigger / X) | E / right click |
| Move | left stick, right stick snap-turns | WASD |
| Vacuum (P2/P3) | | RT / RB, Space / click (P3), Enter (P2 on arrows) |
| Restart after game over | A / X | A / Enter |

Test: `godot --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/ghost_lantern_bot.tscn`
