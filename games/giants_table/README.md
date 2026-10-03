# Giant's Table

A cosy co-op game. A little village sits on a big wooden table: cottages with glowing windows,
trees, hills, a river with a bridge, and the village campfire in the middle. Waves of goblins
climb up over the table edge to steal the campfire's embers.

- **Player 1, the GIANT (VR, host).** `XROrigin3D.world_scale = 20`, so the village is a miniature
  on a table in front of you (20 units = 1 m). Use your hands to grab goblins, boulders,
  embers and even the knights, then drop or throw them.
- **Players 2 to 7, the KNIGHTS (TV).** Up to six tiny third-person knights on the tabletop with a sword and
  a crossbow. They carry dropped embers home and revive each other.

The co-op twist: **armoured goblins** are too spiky for the giant to hold (and boulders only stun
them), so the knights have to beat them. **Ogres** shrug off the knights, so the giant has to lift
them and throw them off the table (or slam them down hard twice). Boulders the giant sets down
block goblins and work as **stepping stones** over the river. The giant can also carry a downed
knight to the campfire to revive them.

You lose when the campfire has no embers left and none can be won back, or when every knight stays
down for 20 seconds.

## Controls

| Who | Controls |
|---|---|
| Giant (VR) | Grip or trigger near something: grab. Let go: drop or throw. Right stick: walk round the table (45° snaps). Left stick up/down: lean in or back. B/Y: re-centre the table. A/X: restart after game over. Menu: pause. |
| Giant (flat, local split screen) | Mouse or 2nd controller's left stick: move the hand. Hold left click / RT / A: grab. Flick and let go: throw. |
| Knights | Left stick / W S: move. Right stick / A D: turn. RT/RB/B or Space: sword. LT/LB/X or F/E: crossbow. A or Shift: jump. Player 3 (2nd controller or arrows + Enter, Right Ctrl or `.`, `/`) presses attack to join. Players 4-7: press A (or attack) on any spare controller to drop in as the next free knight. Each controller drives one knight; unplug it and that knight leaves, plug it back in and they rejoin. |

## Modes

The modes are the ones in `docs/GAME_DEV_GUIDE.md`:

- headset, or `DUO_HOST=1`: host. Player 1 is the giant (VR, or the flat hand without a headset).
- `DUO_JOIN=<host>`: TV client. Knights 2-7 play in split screen (1 full, 2 side by side, 3-4 as 2x2,
  5-6 as 3x2, with lower 3D resolution and cheaper shadows for more views), and the giant shows up as a
  big friendly face and hands.
- otherwise: local split screen. The flat giant is on the left and one knight is on the right;
  more knights can drop in the same way.

Waves grow with the party: from the 3rd knight on, each extra knight adds about 30% more goblins and
35% more armoured goblins, a higher on-table cap and faster spawns (1-2 knights play as before).

## Files

`main.gd` handles modes, waves, campfire, rules, snapshots and HUD. `world.gd` builds the terrain,
river, props and room, and has the height, obstacle and flow-field helpers. `giant.gd`, `knight.gd`,
`goblin.gd`, `boulder.gd`, `ember.gd` and `bolt.gd` are the entities. `toss.gd` is the shared flight
code for anything the giant can throw.

## Tests

```sh
godot --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/giants_table_bot.tscn
DUO_PORT=7781 DUO_HOST=1 timeout 75 godot --headless --path . res://tests/giants_table_bot.tscn &
DUO_PORT=7781 DUO_JOIN=127.0.0.1 timeout 68 godot --headless --path . res://tests/giants_table_bot.tscn
```

Bot options: `GT_FAKE_VR=1` runs the VR giant code without a headset (the bot moves the controller
nodes), `BOT_LAZY_GIANT=1` makes the giant only rescue knights, `BOT_DOWN=1` knocks P2 down at 25 s,
`START_WAVE=n` starts at a later wave, and `BOT_PLAYERS=n` (2-6) joins n TV knights (the last one
through a fake controller that is unplugged at 22 s and plugged back in at 28 s).
