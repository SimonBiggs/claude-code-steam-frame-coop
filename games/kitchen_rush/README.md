# Kitchen Rush

Bright, cartoony co-op cooking chaos for one chef (VR) and up to six runners (TV, split screen).

## Simple mode (`SIMPLE_MODE := true` in main.gd, the default)

The family found the games too complicated and too wordy, so the core is: the **VR chef chops and stacks**
at the counter; the **TV runners fetch** ingredients to the pass and **carry plates** to customers.

- **Practice first:** one patient granny wants a TOASTIE (bun + cheese). The cheese waits on the board; a
  see-through **ghost hand** (chef's headset only) shows CHOP, then STACK onto the plate, and a glowing
  spot shows where. The runners' arrow leads to the **glowing bun crate**, the **glowing pass**, then the
  customer. Serving her starts round 1.
- **One new dish per round:** TOASTIE, then SALAD, BURGER, PIZZA. Tickets and customers show the dish as
  little 3D food, no words. "ORDER UP!" when a dish is ready; "HOORAY!" + three gold stars after a round.
- **Everything interactable** (props.gd): hanging pans CLANG, a wooden spoon to bang on pans / counter /
  bell, a bowl of veggies to juggle and throw (BOING off a runner), a pepper grinder, a cuckoo clock, the
  service bell ("ORDER UP!").
- **Solo VR:** with no TV runner connected, kitchen helpers pop missing ingredients onto the pass and whisk
  finished plates to the customers.
- **Off:** fires and the extinguisher, the food critic, the dinner rush, coins / tips / combos / star
  ratings, awards and stats, the help panel, next-step lines, popups, signs, game over (a customer who
  waits too long just leaves under a rain cloud). The raccoon comes back from round 3.
- **Text:** VR one short headline (wrist: ROUND n); TV one short prompt (PRESS A) at most.

The rest of this file describes the full game (`SIMPLE_MODE := false`).

**A day in the kitchen:** BREAKFAST, LUNCH and DINNER shifts. Each shift is rated with up to three big
stars that pop up over the counter (no grumpy customers and quick service = 3 stars, +10 coins a star).
Dinner gets a DINNER RUSH halfway through (a crowd arrives, double coins for 25 s). After dinner the day
ends with crew awards (CHOP CHAMPION, SPEEDY SERVER, VEGGIE HUNTER, FIREFIGHTER, RACCOON WRANGLER…) and the
next day starts, hungrier. Five angry customers closes the kitchen (stats and awards on the end screen).

- **Chef (player 1, VR host):** stands at the big counter. BOTH hands hold knives: swing one down through
  an ingredient to chop it (no buttons, so the left hand works on the Steam Frame too; each chop squashes
  it, sends bits flying and goes THUNK). Grab with the right trigger (the knife tucks away while you hold
  something; the left trigger/grips grab too where the headset sends them). Drop ingredients on a plate to
  build the dish on the ticket; a matching plate goes *DING!* (the service bell on the counter rings) and
  slides to a corner. Tap the bell yourself for fun. Drop things in the red BIN to throw them away. Left
  stick slides along the counter, A recenters (also automatic when someone of a different height puts the
  headset on). While waiting for the TV crew, two vegetables lie on the pass for chopping practice.
  **Guidance:** a "next step" line floats between the ticket rail and the counter ("CHOP the TOMATO: swing a
  knife DOWN through it! (2 more)", "Grab the LETTUCE and drop it on the glowing plate", "SALAD needs
  TOMATO - the runners are fetching it…"), and a bouncing arrow only the chef sees marks the ingredient or
  plate. **Tickets** hang above the counter: dish name, the customer's colour, the ingredients as little 3D
  models on a ledge (orange ring = needs chopping, green ring = already on the plate) and a patience bar.
- **Runners (players 2 to 7, TV):** first person. A "YOUR JOB" panel and a bouncing arrow only you see say
  what to do next (FETCH a TOMATO from the GARDEN, bring it to the PASS, SERVE the BURGER, FIRE! grab the
  extinguisher, shoo the RACCOON…); the jobs are shared out between the runners. Fetch raw ingredients from
  the fridge/pantry crates (patty, cheese, dough, bun) and the vegetable garden out the back door (lettuce,
  tomato, cucumber), one at a time, and drop them on the PASS (the near edge of the counter). Carry
  finished plates to the customer at the serving window who ordered them, before their patience runs out.
- **Customers** have personalities: kids (propeller hats, impatient), grannies (patient, big tips), robots,
  pirates, aliens, knights, and once a shift from lunch on a VIP FOOD CRITIC (top hat and monocle, short
  patience, triple tips, +25 bonus). They say hello, show a little 3D picture of the dish they want above
  their head, cheer when served and get a grumpy rain cloud when they leave angry.
- **Chaos (from lunch):** the stove catches fire (the chef can't chop in the smoke until a runner
  sprays it with the extinguisher), and a cheeky raccoon sneaks in to steal ingredients from
  the pass (bump into it to scare it off).
- **Recipes:** SALAD (lettuce, tomato, cucumber), TOASTIE (bun, cheese), BURGER (bun, patty,
  lettuce, tomato, from lunch), PIZZA (dough, tomato, cheese, from dinner). Lettuce, tomato, cucumber and
  cheese need chopping. The chalkboard by the back door shows today's menu.
- **Scoring:** 10 coins + a tip for fast service (bigger for grannies, pirates and critics), multiplied by
  the combo (serves within 12 s of each other) and doubled in a rush.
- **Kitchen life:** a ceiling fan, shelves of jars, bunting, potted plants, a soup pot steaming on the
  stove, flower boxes and an OPEN sign at the window, chickens pecking in the garden and butterflies.
  Repeated props are MultiMeshes.

## Controls

| Who | Controller | Keyboard |
|---|---|---|
| Runner (P2) | left stick move, right stick look, A / X / RT use | arrows (left/right turn), Enter use |
| Runner (P3, TV machine) | second controller, same | WASD + mouse, E / Space / click use |
| Button chef (split screen, no headset) | d-pad / stick move hand, A grab/place, X / RT chop | WASD move hand, Space grab/place, Shift or F chop |
| VR chef | swing either knife down to chop, right trigger grab/release, left stick slide, A recenter | - |

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
BOT_VR=1 godot --headless --path . --fixed-fps 60 --quit-after 4800 res://tests/kitchen_rush_bot.tscn   # VR chef code, bot hands
KR_START_SHIFT=3 BOT_PLAYERS=4 godot --headless --path . --fixed-fps 60 --quit-after 5400 res://tests/kitchen_rush_bot.tscn  # dinner rush + day end
KR_LAZY=1 godot --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/kitchen_rush_bot.tscn  # simple: no game over; full: game over + awards + restart
DUO_PORT=7784 DUO_HOST=1 BOT_VR=1 timeout 100 godot --headless --path . res://tests/kitchen_rush_bot.tscn  # solo VR: kitchen helpers
```
