# Hide and Seek

A playful, kid-friendly round game. **Three maps take turns** (Abigail's idea): every new round, and every new
launch, moves on to the next one.

- **THE HOUSE is new every visit** (`housegen.gd` lays it out from a seed, `map_house.gd` builds it): rooms on a
  grid (3 across, 4 from the fifth house on), a random tree of doorways plus a few loops to run round, a hall
  where the seeker counts facing the front door (the jail cage in a corner), a living room, kitchen, bedroom,
  playroom, bathroom (+ bunk room and study in big houses), and a fenced BACK GARDEN on the west or east with a
  shed, hedges, trees, a slide and Pip's kennel. Furniture comes from a catalog with hiding nooks (inside the
  wardrobe, the play fort, the shed and the ball pit, under the kitchen table, behind hedges...). The first house
  each day is **TODAY'S HOUSE** (the same on every machine). The host sends `[seed, level, theme, daily]`.
- **THE CASTLE** (`map_castle.gd`) and **THE SPACESHIP** (`map_ship.gd`) are hand-made; their decoys shuffle every
  round (`world.gd round_decoys`). `world.gd` is the shared building kit.
- **PIP the puppy** (`pip.gd`, `story.gd`) hides on every map each round (further away in later houses). Whoever
  finds him first gets +20: the seeker (torch or touch) or a hider who dares to leave their spot while the seeker
  looks. Pip brings a new toy home: the toys pile up in front of his kennel for good (saved), and 3 / 6 / 9 toys
  unlock the SEASIDE, SNOWY and SPOOKY house looks. Story cards (picture + a few words) tell it.
- Saves (`core/save.gd`, id `hide_and_seek`): Pip's toys, houses explored, today's house. One telemetry `RUN:` line
  per round (map, house spec, finds, who found Pip, seconds, ...) and on quit mid-round.
- **PIP'S STREET** (`street.gd`, second pass): the family's houses are a street of neighbours, 6 houses a street. Each
  house has a NEIGHBOUR FRIEND (`friend.gd`: Bun the bunny, Kit the kitten, Spike the hedgehog, Hoot the owl, Tess the
  tortoise, Fizz the frog, Nutmeg the squirrel, Pom the hamster) hiding with Pip (+25 to whoever finds them: the
  seeker's torch or touch, or a hider bumping into them). A found friend comes to **PIP'S GARDEN PARTY** in every
  house's garden for good (saved `party`), which grows bunting, balloons, a cake and lanterns (2 / 4 / 6 / 8 friends).
  Friends not at the party yet come first. TWISTS rise along the street: SNEAKY (the friend pops off to a new spot
  once, when the seeker comes close or half way through), DARK ROOM (no lamp, curtains shut, the friend shows only
  glowing eyes: use the torch), TWINS (two friends). Later streets add more. A hiding friend squeaks now and then (a
  sound to follow; no sparkles). Picture-first story cards: who hides here, the twist, "To the party!", "Find me
  next time!", "STREET DONE!". **TODAY'S STREET** (the daily house) has two friends and a twist; `daily_done` when
  finished. `HNS_TRY=street|dark|sneaky|twins` starts on a house with that twist (What's New "try").
  housegen.gd places the friends, the dark room and the party (own random stream) and `check_street()` proves them
  fair. The host's spec array carries `[seed, level, theme, daily, friends, twist, street, slot]`; the snapshot
  carries `[friend_state, party]` (TV machines rebuild everything from those).
- **SECOND PASS** (`deep.gd` data + generators, `deep_play.gd` in the game; test `tests/hide_and_seek_deep_test.gd`):
  - **GENTLE / BRAVE / HARD** before the first round, on pick orbs (`core/pick_orbs.gd`) floating over the counting
    room: hiders and a flat seeker stand under one, the VR seeker walks up and reaches a hand into one (DWELL 0.5 s);
    most picked wins, nobody in time = the middle (the family's last mode). GENTLE: +20 s, one surprise, 4.5 s tells,
    sniff every 10 s. HARD: a 15 s count, -10 s, three surprises, 3 s tells.
  - **PIP'S GIFTS** before every later round, for the side that LOST the last one (alone: the seeker): BIG TORCH
    (longer, wider beam), SUPER NOSE (sniff 7 m, every 6 s), BIG HANDS (bigger touch), ZOOMY SHOES (either side),
    EXTRA BELL (one more jailbreak), BUBBLE (every hider's first tag pops a bubble instead and gives 2.5 s to run),
    HANKY (no sneezing from sniffs or pepper). Three offered, seeded per round.
  - **RUMBLE'S SURPRISES** (never in round 1, never alone): RUMBLE the robot hoover rolls along a band through a hider's
    room (stops at walls and furniture) and bumps hiders in it out of their disguise; the PEPPER POT puffs round a hider
    and everyone in the ring sneezes ACHOO (heard by the seeker). Each is TOLD first by a steady warn ring on the floor
    (`core/warn_rings.gd`: deep blue band / berry-pink disc) for the mode's tell time, so a hider can step out. Times come
    from `Deep.plan()` (house seed + round), never before 18 s into the seek, never in the last 12 s, 14 s apart.
  - **SEASONS** (`Seeded.season`, `core/season_kit.gd`): props along the garden fence clear of everything in the
    garden, the castle courtyard's corners, the spaceship's mess hall, with blossom / leaves / snow drifting over the
    garden and the courtyard.
  - **PIP'S KENNEL grows**: every finished round counts (save `kennel`); `KENNEL_STEPS` add a flag, a bowl, flowers, a
    bone sign, a porch, lights, a tower and a gold roof (a story card each time). The Trophy Hall counts the pieces.
  - Snapshot item 18 = `deep_play.pack()` (mode, gift, side, pick stage, choices, takes, season, kennel, bubbles);
    events `deep_tell`, `deep_go`, `deep_bump`: all machines must update together. Telemetry adds mode, gift,
    surprises, bumps, sneezes, pops, kennel, season. The host sets net state `phase` (bots count phases with
    `BotKit.watch_state`).
- **Validator** `tests/hide_and_seek_gen_test.gd` (`godot-test --headless --path . -s res://tests/hide_and_seek_gen_test.gd`,
  `SEEDS=300` for more): over many seeds and sizes, every room, doorway, spawn, star spot and the jail bell is
  walkable for a hider and the seeker, every hiding spot is reachable by a hider AND touchable by the seeker (so
  every hider can be found), no walled-off pockets; same seed same house; TODAY'S HOUSE fixed all day.

- **Player 1, the SEEKER (VR on the Steam Frame, or flat in split screen).** Counts to 20 with eyes
  covered (the view goes dark), then searches with a torch in the right hand. Tag a hider by touching
  them with either hand, or by pointing the torch at them within 3 m and pulling the trigger. Tagging a
  decoy just says "Just a lamp!". **SNIFF** (VR: hold your left hand on your nose; flat: Q / LB): every
  hider within 4.5 m sneezes "ACHOO!" (15 s cooldown). Left stick walks, right stick snap-turns. Eye height
  is fitted automatically and re-fitted when someone else puts the headset on. After 30 s a gold sparkle
  hints at a hider every 15 s.
- **TV players, the HIDERS (1-6, third person).** Run and hide while the seeker counts. A toggles a
  disguise that fits the room (lamp, pot plant, box, teddy or beach ball, matching the decoys nearby; no
  moving while disguised). X / Y / RB / RT squeaks for +10 (positional sound, so it's a risk!). B jumps.
  Pushing against something for 2 s slides you free. The screen edge glows warm when the seeker is close.
- **JAIL.** Found hiders go to the cage in the hall (and watch the seeker). A free hider who rings the
  **bell** by the cage lets everyone out (+25 per friend; once a round, twice with 4+ hiders).
- **Rounds take turns:** CLASSIC, **STAR HUNT** (golden stars to grab for +15 while hiding) and
  **NIGHT TIME** (lights low, glowing critter eyes, extra-bright torch).
- **Scores.** Hiders get 1 point per second hidden, +10 per squeak, +15 per star, +25 per friend freed and
  +50 for never being found. The seeker gets 100 per find plus a speedy bonus (2 per second left) for
  finding everyone. Awards each round: SNEAKIEST, SQUEAKIEST, JAIL HERO, STAR CATCHER, EAGLE EYES,
  SUPER SNIFFER. Round length grows gently with the number of hiders (140 s for one, 190 s for six).
- Drop-in: press A on a spare controller to join (mid-round joiners spectate until the next round).
  Results screen: A / Enter (TV) or trigger (VR) plays again; totals carry over between rounds.

Keyboard (split screen): P1 WASD + mouse, click / Space torch, Q sniff. P2 arrows, Enter disguise, Ctrl squeak.
On the TV client P3 can use WASD + mouse (Space disguise, E / right click squeak).

Test: `godot --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/hide_and_seek_bot.tscn`
(`BOT_PLAYERS=N` for more hiders; see the guide for the networked run). The bot starts with a
**connectivity check** with real physics on the castle, the ship and four houses: every room, doorway, hiding
spot and spawn must be walkable from the counting spot without jumping, for both the seeker's and a hider's size
(prints `CONNECTIVITY OK` / `SCRIPT ERROR ... FAIL`). In round 2 a hider runs to Pip (`BOT: PIP OK`).
`BOT_CONN_ONLY=1` runs just that check.

## Visual teaching

No how-to text: each TV view shows a big word at most (HIDE!, SEEK!, the countdown) and a picture cue
low down (`cue.gd`, built in `hud.gd`): the player's own button glyph plus a torch, a critter turning
into a box, a squeak, a sniffing nose or the jail bell, and a glowing pointer to the bell (friends in
jail) or the nearest star. Each action cue retires once that player has done it twice. The VR seeker
gets 3D cues (TRIGGER over the torch while a hider is in the beam, a nose ball on the left mitten).
