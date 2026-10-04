# Ghost Lantern

A spooky-but-cute co-op ghost hunt in a haunted mansion with three rooms: library, hall and ballroom.
Cheeky ghosts steal the family photos and say BOO to players. Ghosts are **invisible** except
inside the spirit lantern's light.

## Simple mode (`SIMPLE_MODE := true` in main.gd, the default)

The family found the games too complicated and too wordy, so by default it's just: **the lantern lights
the friendly ghosts up and makes them dizzy; the TV players vacuum them.**

- **Practice first.** The lantern-bearer gets a sleepy ghost floating in front of them (it only shows in
  the light); in VR a see-through ghost hand sweeps a lantern onto it. Keep the light on it until it wakes
  up, giggles and pops; then a second one. Each TV player gets one glowing ghost right in front of them
  to vacuum ("HOLD RT!" until their first catch).
- **Gentle nights, one new thing each:** 1 three slow plain ghosts, 2 little fast sprites, 3 witch hats,
  4 the golden ghost, 5 the Ghost King (vacuum him together), 6 a mix and the sunrise, then more nights.
- **Nothing goes wrong:** no photo stealing, no spooking, no game over. Bump into a ghost and it giggles
  and floats off; a ghost nobody catches giggles away through the ceiling after a while.
- **Solo VR** (no TV players): a dizzy ghost held in the light gets slurped into the lantern.
- **Touch everything** near the start (props.gd): two candles (light / puff out), a music box with a
  tiny ghost dancer, a bubbling cauldron that changes colour, a cuckoo clock, a winking portrait, a
  cobweb whose spider abseils down, a creaky cupboard with a grinning pumpkin. TV players bump them.
- Off: photos / LAST CHANCE, courage and cheering up, shy and snuffer ghosts, storms / parties / treats,
  the bell scaring ghosts (it just jingles), score and readouts, popups, hint panels, awards.
  Text: one short headline ("NIGHT 2", "HOORAY!").

Everything below describes the full game (`SIMPLE_MODE := false`).

## Roles

- **P1, lantern-bearer (VR, or keyboard + mouse in split screen)**: points the spirit lantern.
  Ghosts in its light cone show up for everyone. A ghost that stays in the beam gets stunned and drops
  its photo. Focusing the beam makes it narrower and longer, and it stuns twice as fast. The hand bell
  scares every ghost within 9 m away for a few seconds, and they drop their photos. It has a 6 s cooldown.
- **P2..P7, ghost vacuums (TV, up to six)**: hold fire to suck in a ghost **that the lantern is lighting**.
  A capture bar fills while the ghost struggles. Stunned ghosts are easier to catch. Their torches only
  light the room. They can't reveal ghosts, so shout to P1 where you need the light!

When a ghost touches you, you lose courage. With no courage left you're spooked: stand next to a
spooked friend to cheer them up. Nights get busier. Survive **night 6** to see the sunrise (then bonus
nights). The game ends if everyone is spooked (once a night the lantern flickers back to life first) or the
ghosts carry every photo away - but before that, the **LAST CHANCE**: the Ghost King grabs every lost photo
and you have 50 seconds to catch him.

## Ghosts and events

- **Thief** (bandit mask) and **Shy** ghost (blushing, hides its face) steal photos. Shy ghosts only show
  up in a **focused** beam (VR: hold the trigger).
- **Spooker** (witch hat) says BOO, **Sprite** (bow) is tiny and fast.
- **Snuffer**: its brass snuffer hat is always visible. If it reaches the lantern-bearer the lantern goes
  out for 4 s - TV players, vacuum it first!
- **Golden ghost**: rare, flees, leaves a sparkle trail, worth 500.
- **GHOST KING** (nights 3 and 6): golden crown always visible, carries every lost photo (each stun drops
  one; catching him returns them all), calls thieves to help, needs several vacuums at once.
- Events from night 2: **thunderstorm** (lightning shows every ghost), **ghost party** (dizzy dancing ghosts
  in the ballroom, easy to catch), **treat time** (candy = courage + points).
- End screens show **awards** (GHOSTBUSTER, PHOTO HERO, CHEERLEADER, LIGHT BRINGER, ...).

## Controls

| | VR | Flat screen |
|---|---|---|
| Lantern (P1) | right hand aims, right trigger focuses | mouse aims, Space / left click focuses |
| Bell (P1) | shake the left controller (or left trigger / X) | E / right click |
| Move | left stick, right stick snap-turns | WASD |
| Vacuum (P2/P3) | | RT / RB, Space / click (P3), Enter (P2 on arrows) |
| Restart after game over | A / X | A / Enter |

## Party mode (up to 6 TV players)

- P2 plays on the arrow keys + Enter and/or the first controller; on the TV, P3 joins on WASD + mouse
  (hold Space / click) or the second controller, as before. In local split screen the second controller drives P1.
- **Any other controller: press A (or Start) to drop in** as the next free player (P3..P7). Each controller
  drives exactly one player.
- Unplugged controller: that player idles for 20 s; plug it back in to carry on, otherwise they leave
  (press A again to rejoin).
- Split screen: 1 view full, 2 side by side, 3-4 as 2x2, 5-6 as 3x2 (local 7 as 4x2), at lower render
  scale for 3+ views. Each extra hunter past three adds a few ghosts per night.

Test (simple mode: the bot checks practice, ghost hand, props, a ghost floating away and no game over,
printing `BOT: SIMPLE OK`): `BOT_PLAYERS=6` makes the bot join that many TV players; `BOT_VR=1` fake VR lantern;
`BOT_NIGHT=6 BOT_GOD=1` plays the last night to the sunrise. `godot --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/ghost_lantern_bot.tscn`
