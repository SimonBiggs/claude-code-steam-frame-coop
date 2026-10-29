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
