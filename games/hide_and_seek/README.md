# Hide and Seek

A playful, kid-friendly round game in a cosy cartoon house (living room, hall, kitchen, bedroom,
playroom, bathroom).

- **Player 1, the SEEKER (VR on the Steam Frame, or flat in split screen).** Counts to 20 with eyes
  covered (the view goes dark), then searches with a torch in the right hand. Tag a hider by touching
  them with either hand, or by pointing the torch at them within 3 m and pulling the trigger. Tagging a
  decoy lamp / plant / box just says "Just a lamp!". Left stick walks, right stick snap-turns. Eye height
  is fitted automatically (sitting down or a short kid is fine) and re-fitted when someone else puts the
  headset on.
- **TV players, the HIDERS (1-6, third person).** Run and hide while the seeker counts. A toggles the
  disguise (a random lamp, pot plant or box, matching the decoys all round the house; no moving while
  disguised). X / B / Y / RB / RT squeaks for +10 (positional sound, so it's a risk!). The screen edge
  glows warm when the seeker is close. Found hiders spectate (their camera follows the seeker).
- **Scores.** Hiders get 1 point per second hidden, +10 per squeak and +50 for never being found.
  The seeker gets 100 per find plus a speedy bonus (2 per second left) for finding everyone.
  Round length grows gently with the number of hiders (130 s for one, 150 s for three, 180 s for six).
- Drop-in: press A on a spare controller to join (mid-round joiners spectate until the next round).
  Results screen: A / Enter (TV) or trigger (VR) plays again; totals carry over between rounds.

Keyboard (split screen): P1 WASD + mouse, click / Space torch. P2 arrows, Enter disguise, Ctrl squeak.
On the TV client P3 can use WASD + mouse (Space disguise, E / right click squeak).

Test: `godot --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/hide_and_seek_bot.tscn`
(`BOT_PLAYERS=N` for more hiders; see the guide for the networked run).
