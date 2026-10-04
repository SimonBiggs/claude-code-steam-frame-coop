# Hide and Seek

A playful, kid-friendly round game in a cosy cartoon house (living room, hall, kitchen, bedroom,
playroom, bathroom) with a back garden (shed, hedges, trees, slide, sandpit, washing line, fairy lights)
through the living room's garden door.

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
**connectivity check**: every room, doorway, hiding spot and spawn must be walkable from the counting spot
without jumping, for both the seeker's and a hider's size (prints `CONNECTIVITY OK` / `FAIL`).
`BOT_CONN_ONLY=1` runs just that check.
