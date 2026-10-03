# Kitchen Rush

Bright, cartoony co-op cooking chaos for one chef (VR) and up to six runners (TV, split screen).

- **Chef (player 1, VR host):** stands at the big counter. Grab with either hand (grip or trigger).
  The right hand holds a knife: swing it down through an ingredient to chop it (a few chops each,
  with haptics). Drop ingredients on a plate to build the dish shown on the ticket rail; a matching
  plate goes *DING!* and slides to a corner of the counter. Drop things in the red BIN to throw them
  away (a plate dropped in the bin is emptied). X / A recenters you at the counter (works seated too).
  The left menu button pauses both machines.
- **Runners (players 2 to 7, TV):** first person. Fetch raw ingredients from the fridge/pantry
  crates (patty, cheese, dough, bun) and the vegetable garden out the back door (lettuce, tomato,
  cucumber), one at a time, and drop them on the PASS (the near edge of the counter). Carry finished
  plates to the customer at the serving window who ordered them, before their patience runs out.
- **Chaos (from shift 2):** the stove catches fire (the chef can't chop in the smoke until a runner
  sprays it 3 times with the extinguisher), and a cheeky raccoon sneaks in to steal ingredients from
  the pass (bump into it to scare it off).
- **Recipes:** SALAD (lettuce, tomato, cucumber), TOASTIE (bun, cheese), BURGER (bun, patty,
  lettuce, tomato, from shift 2), PIZZA (dough, tomato, cheese, from shift 3). `*` = needs chopping.
- **Scoring:** 10 coins + a tip for fast service, multiplied by the combo (serves within 12 s of each
  other). Each shift needs more orders with hungrier customers. Five angry customers closes the kitchen.

## Controls

| Who | Controller | Keyboard |
|---|---|---|
| Runner (P2) | left stick move, right stick look, A / X / RT use | arrows (left/right turn), Enter use |
| Runner (P3, TV machine) | second controller, same | WASD + mouse, E / Space / click use |
| Button chef (split screen, no headset) | d-pad / stick move hand, A grab/place, X / RT chop | WASD move hand, Space grab/place, Shift or F chop |

| Runners P4-P7 (drop in) | any extra controller: press A or Start to join, then same as P2 | - |

Player 3 joins on the TV machine by pressing their use button. Any controller that doesn't drive a player
yet joins as the next free runner by pressing A or Start (TV machine, or split screen without a headset).
Each controller drives exactly one player. Unplugging one leaves that runner standing idle; after 15 s
they leave the kitchen (dropping what they carry), and plugging the controller back in (or pressing A on
another spare one) rejoins. Split screen: 1 view full, 2 side by side, 3-4 in a 2x2 grid, 5-6 in 3x2,
7 in 4x2, with lower render resolution and fewer effects as the screen splits further. More than two
runners make the kitchen busier: a bigger order target per shift, customers arrive a little faster, and
fires and raccoons come more often (fires need more sprays). Restart after game over: A / Enter
(VR: right trigger).

## Test

```sh
godot --headless --path . --fixed-fps 60 --quit-after 9000 res://tests/kitchen_rush_bot.tscn
BOT_PLAYERS=6 godot --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/kitchen_rush_bot.tscn
DUO_PORT=7784 DUO_HOST=1 timeout 130 godot --headless --path . res://tests/kitchen_rush_bot.tscn &
DUO_PORT=7784 DUO_JOIN=127.0.0.1 BOT_PLAYERS=4 timeout 123 godot --headless --path . res://tests/kitchen_rush_bot.tscn
```
