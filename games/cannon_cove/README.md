# Cannon Cove

Pirate co-op: one VR gunner on a Steam Frame plus 1–6 deckhands on the TV (split screen when there's no headset).

**The voyage:** target practice (while the TV crew joins), then five waves and the KRAKEN:
1. CALM SEAS – two slow pirate ships that barely shoot (no boarders): learn the ropes.
2. RAIDERS! – raiders swing boarders over on ropes.
3. FIRE SHIPS! – little bomb boats try to ram us (cannon them, or musket their powder keg up close:
   KABOOM, and it takes nearby pirates with it).
4. MONSTER WATERS – sea-monster tentacles, plus a TREASURE SHIP that never shoots but runs away
   after a lap: sink it for a GOLDEN CANNONBALL.
5. THE STORM – night falls, lightning, everything at once.
6. THE KRAKEN – a giant head rises beside the ship. While it has tentacles its eyes stay shut and
   cannonballs go CLANG: the deckhands musket the tentacles away, then its eyes open and the gunner has
   a few seconds to hit it. Three rounds (it dives and comes up on the other side) and the cove is safe:
   fireworks, +500 gold, crew awards, then BONUS SEAS go on forever.
The sky changes through the voyage (sunset, dusk, storm, night, dawn after the Kraken).

- **Gunner (P1, VR, host):** reach for the glowing, pulsing handle behind the cannon and HOLD the trigger
  to grab it (or move a hand that's already squeezing onto it), swing it to put the gold ring on the
  target, LET GO to fire. A dotted arc and a ring on the sea show where the ball lands. A or a left-stick
  flick hops to the next cannon. Right stick snap-turns. Hold the spyglass (left hand) up to your eye to
  zoom. The game lifts or lowers you so the handle sits at a comfy height (kids, grown-ups, sitting down)
  and re-fits when someone new puts the headset on.
  **Coaching:** a hint panel below the banner says what to do next ("Reach out to the glowing HANDLE…",
  "Swing the handle to move the gold RING onto the TARGET", "LET GO to FIRE!", "This cannon is EMPTY! Press
  A to hop…", "The PIRATE SHIP is on the STARBOARD side…") and a bouncing arrow only the gunner sees points
  at the handle / next cannon / target. Pulling the trigger away from the handle draws a dotted line to it.
  Practice misses say "TOO SHORT! Push the handle DOWN a little" etc.
  Flat gunner: sticks / WASD+mouse / arrows aim, RT / A / Space / Enter fire, LB/RB / Q/E / , . switch cannon.
- **Deckhands (P2–P7, TV, client):** drop-in: P2 is keyboard+mouse and the first controller; press A on any
  other controller (or Enter/Shift on the TV's arrow-key set) to join as the next free player. Unplugging a
  drop-in player's controller takes their deckhand off the deck; plugging it back in rejoins them. Split
  screen: 1 view full, 2 side by side, 3–4 as 2x2, 5–6 as 3x2. Bigger crews face a few more ships and tentacles.
  Move with the stick or WASD and look with the stick or mouse. Everyone gets their own bouncing ARROW over
  the next job (cannonball pile → the cannon that needs it most → leaks → boarders; odd players are sent to
  leaks first, even players to boarders).
  Use (A / E / Space; P3 keyboard: Shift) grabs a cannonball from the pile at the bow, loads a cannon
  (or just walk up to it), and patches a leak while you hold it. Musket (RT / click / F; P3: Enter)
  knocks boarding pirates overboard, hurts tentacles and pops bomb boats. You can't fire while carrying a ball.
- **Rewards:** gold for ships, boarders, tentacles, patches (SPEEDY PATCH bonus), hot streaks of hits,
  DOUBLE SINKS, chain blasts, floating SUPPLY BARRELS (free ball for every cannon) and TREASURE CHESTS.
  The golden cannonball makes a MEGA SHOT (a huge golden blast; it also stuns the Kraken's eyes open).
  The treasure chest by the stern fills up with the crew's gold. End screen: stats and a fun award per player
  (EAGLE EYE, HOT SHOT, CANNONBALL COURIER, MASTER CARPENTER, BOARDER BOUNCER, MONSTER TICKLER, BOMB SQUASHER…).
- **Scenery:** Polly the parrot hops along the rail to the gunner's cannon and squawks cheers and warnings;
  dolphins leap past between waves; a lighthouse sweeps the bay; billowing sails, flapping flags, rigging,
  barrels, a golden sea-dragon figurehead and glowing portholes. Islands, rocks, clouds and stars are
  MultiMeshes, so the scene has fewer draw calls than before.

Test: `godot --headless --path . --fixed-fps 60 --quit-after 9000 res://tests/cannon_cove_bot.tscn`
(`BOT_PLAYERS=6` brings six deckhands aboard; `CC_BOT_RANGE=24` makes the bot gunner wait for close range,
which brings boarders and leaks into play; `CC_START_WAVE=6` skips to the Kraken; `CC_FAKE_VR=1` runs the real
VR gunner code with bot-driven hands: it misses the handle once, then reaches, squeezes, swings and lets go).
