# Cannon Cove

Pirate co-op: one VR gunner on a Steam Frame plus 1–6 deckhands on the TV (split screen when there's no headset).

- **Gunner (P1, VR, host):** grab a cannon's glowing handle (grip, or trigger) and swing it to aim.
  With a grip grab, pull the trigger to fire. With a trigger grab, let go of the trigger to fire.
  A dotted arc and a ring on the sea show where the ball will land. A/B or a left-stick flick moves you
  to the next/previous of the four cannons (2 port, 2 starboard). Right stick snap-turns. Hold the
  spyglass (left hand) up to your eye to zoom. Menu button pauses.
  Flat gunner: sticks / WASD+mouse / arrows aim, RT / A / Space / Enter fire, LB/RB / Q/E / , . switch cannon.
- **Deckhands (P2–P7, TV, client):** drop-in: P2 is keyboard+mouse and the first controller; press A on any
  other controller (or Enter/Shift on the TV's arrow-key set) to join as the next free player. Unplugging a
  drop-in player's controller takes their deckhand off the deck; plugging it back in rejoins them. Split
  screen: 1 view full, 2 side by side, 3–4 as 2x2, 5–6 as 3x2. Bigger crews face a few more ships, boarders
  and tentacles.
  move with the stick or WASD and look with the stick or mouse.
  Use (A / E / Space; P3 keyboard: Shift) grabs a cannonball from the pile at the bow, loads a cannon
  (or just walk up to it), and patches a leak while you hold it. Musket (RT / click / F; P3: Enter)
  knocks boarding pirates overboard and hurts tentacles. You can't fire while carrying a ball.
- Pirate ships fire at the deck and every hit makes a leak. Leaks fill the hold (the sea rises up the
  hull). Raiders send boarders who steal cannonballs or chop holes. From wave 3 a sea-monster tentacle
  slams the deck. The ship sinks at 100% water. Gold for sinking ships, boarders, tentacles and patches.

Test: `godot --headless --path . --fixed-fps 60 --quit-after 9000 res://tests/cannon_cove_bot.tscn`
(`BOT_PLAYERS=6` brings six deckhands aboard; set `CC_BOT_RANGE=24` to make the bot gunner wait for close range, which brings boarders and leaks into play).
