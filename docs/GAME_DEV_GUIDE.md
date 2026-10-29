# Making a game for claude-code-steam-frame-coop

Each game is a co-op game for **one VR player on a Steam Frame plus 1–2 players on a TV**,
connected over the home network. There's also a split-screen fallback when no headset is present.
`games/duo_arena/` is the reference implementation: read it before starting.

**New games: build on the shared engine systems** instead of copying a game's party, split-screen,
VR-rig and bot code: `core/party.gd` (drop-in seats + per-player input), `core/split_view.gd`,
`core/camera_rig.gd`, `core/vr_rig.gd`, `core/save.gd`, the state store / `request()` in
`core/net.gd`, and `tests/bot_kit.gd`. Start from `games/engine_template/` (a small complete game
using all of them, with `tests/engine_template_bot.gd`); the API is in `docs/engine/systems.md`.
For how it looks and sounds, use the shared **presentation** modules instead of hand-made labels,
meshes and beeps: `core/ui_kit.gd` (theme, panels, icons, bars), `core/ui_menu.gd` / `core/vr_menu.gd`
(per-player menus), `core/dialogue.gd`, `core/hud_kit.gd` (banners, toasts, damage popups, 3D HP bars,
scoreboards, timers), `core/hints.gd`, `core/awards.gd` (results screens), `core/mesh_kit.gd`,
`core/creatures.gd`, `core/sky_kit.gd`, and the extended `core/sfx.gd` / `core/music.gd` (moods);
the API is in `docs/engine/presentation.md`.

## Layout

```
arcade/arcade.gd        launcher (register your game in GAMES)
core/net.gd             ENet host/client: snapshots + events (shared, don't fork)
core/sfx.gd             procedural sound effects: sfx.play(name, volume_db, pitch), sfx.add_sound(name, def)
core/music.gd           procedural synthwave tracks: play_track(i)
core/pause_menu.gd      Esc/Start pause menu (shares pause over the network)
games/<id>/main.tscn    root node MUST be a Node3D named "Main" with games/<id>/main.gd
games/<id>/*.gd         everything else for your game
tests/<id>_bot.gd/.tscn headless bot test for your game
```

All content is generated in code: primitive meshes, `StandardMaterial3D`, `CPUParticles3D`,
`Label3D`, shaders as strings. Don't import models, textures or audio.

## Modes (copy `_ready()` from duo_arena/main.gd)

- `DUO_JOIN=<host>` → **client**: the TV machine. Its players are local; the world is mirrored
  from snapshots. If no host answers within 5 s, it falls back to **local** split screen.
- OpenXR headset initialised, or `DUO_HOST=1` → **host**: the Steam Frame, where player 1 is in VR.
  The host simulates everything.
- otherwise → **local**: 2-player split screen (keyboard+mouse and controller).

`DUO_PORT` overrides the port (default 7777); use a unique one for parallel tests.

## Networking contract (what core/net.gd calls on `main`)

`net` is a child node named `Net` of `Main`, so RPCs resolve to `/root/Main/Net` on both machines.
Your `main.gd` must provide:

| Member | Purpose |
|---|---|
| `var players: Array` | player nodes, index 0 = VR/host player |
| `var ready_to_play: bool` | snapshots are ignored until true |
| `func make_snapshot() -> Array` | host, 30 Hz: everything the client must draw |
| `func apply_snapshot(s: Array)` | client: mirror it (interpolate positions!) |
| `func apply_event(kind: String, args: Array)` | client: one-off events (sounds, bursts, text) |
| `func on_p2_action(action: String, args: Array, index: int)` | host: a TV player did something |
| `func on_client_joined()` / `on_client_left()` | host |
| `func toggle_vr_pause()` | host: VR left menu button pressed (net.gd polls it) |
| `players[i].apply_remote_state(pos, yaw, pitch)` | host: TV player i moved |
| `players[0].vr`, `players[0].hand_l` | used by net.gd's VR menu-button check |

Senders: `net.event(kind, args)` (host → client, reliable), `net.send_state(pos, yaw, pitch, index)`
and `net.send_action(action, args, index)` (client → host). `net.mode` is
`"local" | "host" | "client"` and `net.connected` is a bool.
Pattern: the TV player's **own movement is client-side** (instant). The host decides hits, damage,
score and game over. Use visual-only "ghost" copies of host objects on the client.

## VR (Steam Frame, OpenXR via SteamVR)

- **VR-only world UI goes on ONE render layer** (`core/vr_layer.gd`, `UiKit.VR_LAYER`, bit 18): the TV split views share
  the VR world, so a VR card on layer 1 shows its dark back on the TV. Core VR helpers (HudKit.vr_*, VrMenu, StoryCard.show_vr,
  dialogue, awards, UiKit.vr_place/vr_follow, VrText.follow) do it already; for anything else call `VrLayer.mark(node)`.
  The VrLayerGuard service fixes every camera's cull_mask each frame. Never use bits 18-19 for a game's own layers
  (tests/engine_ui/vr_layer_test.gd lints games/).
- Put XR on the **main viewport**: `get_viewport().use_xr = true`. A SubViewport gives a flat "theatre" view.
- `XROrigin3D` > `XRCamera3D` + `XRController3D` (`tracker = "left_hand" / "right_hand"`, `pose = "aim"`).
- Actions (default map): `get_vector2("primary")` (thumbstick), `get_float("trigger")`,
  `is_button_pressed("ax_button")`, `"menu_button"`, and `trigger_haptic_pulse("haptic", 0, amp, dur, 0)`.
- Move the XR origin in `_process` (per frame), not `_physics_process`, or it judders.
  Snap-turn on the right stick. The player may be **sitting down**.
- 2D UI doesn't show in VR. Use a world-space `Label3D` about 1.8 m ahead with a thick black outline
  (`outline_size` around 26), or put it on the wrist. Don't attach text to the XR camera, and don't
  billboard it: players want to turn their head to read it. Let it glide back in front only when they
  turn well away (see `_lazy_follow` in duo_arena/main.gd).
- **VR text and depth** (it hurt the family's eyes when wrong):
  - Never set `Label3D.no_depth_test = true`. Far text drawn over nearer things (hands, a fishing rod)
    looks wrong in stereo. `duo-deploy` refuses code that sets it.
  - No billboards in VR: each eye turns the label differently, which looks cross-eyed. To face the
    player, turn it on Y only. A Label3D reads from its **+Z** side, so with `d = label - head`, use
    `Basis(Vector3.UP, atan2(-d.x, -d.z))`. The other sign mirrors the text.
  - `core/vr_text_guard.gd` (started by `core/net.gd`) enforces both at runtime for every Label3D while
    a VR camera is active, but write it correctly anyway.
  - Keep VR text short: a headline and at most one more line. Instructions meant for the TV players
    belong on the TV only.
  - `frame-say` captions ("Claude: …") are drawn by addons/gdev/caption.gd in every game.
- On the Steam Frame, the **left controller's buttons (menu, Y, grip) and the left trigger don't reach
  the game**; only the sticks, the right trigger, A and both hands' positions do. Give the left hand
  touch-based jobs. `core/net.gd` adds a MENU button beside the left wrist (touch and hold, or point and
  pull the trigger) that calls `toggle_vr_pause()`. While paused, HOLDING the trigger for 1.5 s returns
  everyone to the arcade.
- Lessons from playtesting with kids:
  - Never base an input on a calibrated "rest pose": it drifts between kids and got a dragon stuck at
    the ceiling. Measure hands relative to the head/eyes or to a held object, with generous dead zones.
  - No gaze steering (it annoyed them). Let the VR player move with the left stick; kids hate being
    stuck in one spot.
  - Fit the height on start and re-fit when the head height changes a lot for a few seconds (the
    headset gets handed to a smaller kid, or someone sits down).
  - Keep text far from the eyes (use `core/vr_text.gd`); never put grab zones where reaching for them
    means hitting your own face.
  - A trigger still held from the previous screen (the pause menu, the arcade) must not act on the next
    one: wait for a release.
  - Put what the VR player needs (health, the word to draw) where they always look, e.g. on the held tool.
  - Show a how-to banner and short contextual hints: kids constantly ask "how do I…?".
- `XRServer.world_scale` is global. If a game scales the world, reset it to 1.0 in `_exit_tree`.
- Give the VR player a role that uses their **hands**, different from the TV players' role.
- **Keep it simple** (Simon: "all of the games have become too complicated"): one core idea a
  kid gets in 10 seconds. Start with only that; add mechanics one at a time in later rounds, never all
  at once. Cut anything that needs explaining. Fewer HUD readouts, fewer modes, fewer special rules.
- **Show, don't tell** (Simon: "everything's being driven by text"): teach with the world, not
  paragraphs: glowing targets, arrows, a ghost hand doing the move, icons, sounds and short spoken
  lines. Text is a last resort: one short headline at a time, never instructions for the other team.
  Start every game with a short PRACTICE moment that teaches by doing (Simon's favourite: Cannon
  Cove's practice targets): one safe target per skill, it lights up, you hit it, the next one appears.
- **Everything should be interactable** (Simon's rule): if the VR player can reach it, touching it
  should do something: trees sway or can be picked up, rocks can be thrown, houses wobble, water
  splashes. Prefer grab-and-throw over abstract buttons; picking things up and throwing them is the
  most fun part of VR.
- `Engine.physics_ticks_per_second = 90` in VR.

## Performance (the Frame has a phone-class GPU, target 72 fps)

- The Frame runs with `--rendering-method mobile`. In VR turn off SSAO, fog and directional shadows,
  and use MSAA 2x.
- Keep draw calls low: use few meshes per object, sphere segments around 12–20 (not the default
  64), and avoid hundreds of nodes. Bake static, vertex-coloured shapes into one mesh, and use
  `MultiMeshInstance3D` for crowds and repeated props (several games have a `mesh_kit.gd` to copy).
- Godot's built-in font has no symbols like ♥ ★ ▶ ✓ →; the headset may not have a fallback font. Use
  plain text ("HP 80", "* AWARDS *", "> <").
- Snapshots go over the network ~30 times a second; `core/net.gd` compresses them, but keep them
  small and send one-off things as events.
- No sync GPU readbacks every frame. The gdev bridge records the group `gdev_capture` viewport
  (add a small mirror SubViewport like duo_arena's `_build_vr_mirror` so people can watch the VR view).

## GDScript pitfalls (Godot 4.7)

- `var x := <Variant expression>` is a **parse error**: untyped vars, array elements, dictionary
  values and calls on untyped objects need explicit types (`var x: float = arr[i]`).
- No `class_name`: use `const Foo := preload("res://games/<id>/foo.gd")` and `Foo.new()`.
- The scripts hot-reload while the game runs, so prefer lazily created nodes. Setup that only runs in `_ready`
  goes stale after a reload: define `func _on_hot_reload()` on that node to redo it (gdev calls it after reloading
  the node's script), or check it lazily in `_process`. Static vars keep
  stale values across reloads (use `Engine` metadata for caches). An error in `_process` skips the
  rest of that frame.
- `WorkerThreadPool` tasks must be waited on, or their memory leaks.
- After `add_child`, `set_anchors_preset(P)` keeps the old offsets, so a centred / right / bottom
  HUD panel lands half off screen. Use `set_anchors_and_offsets_preset(P, Control.PRESET_MODE_KEEP_SIZE)`
  (48 HUD panels had this bug; `dev.sweep()` flags text off screen or overlapping).
- Never `pkill -f` with a pattern that also matches your own command line.

## Testing (headless only; never open windows on this machine, it's the family's TV)

```sh
godot-test --headless --path . --import                      # once, in a fresh checkout
godot-test --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/<id>_bot.tscn
# networked: same bot scene on both sides (so node paths match), real time (no --fixed-fps)
DUO_PORT=78xx DUO_HOST=1 timeout 40 godot-test --headless --path . res://tests/<id>_bot.tscn &
DUO_PORT=78xx DUO_JOIN=127.0.0.1 timeout 33 godot-test --headless --path . res://tests/<id>_bot.tscn
```

The bot should load the game (`load("res://games/<id>/main.tscn").instantiate()`), drive the
players (press keys with `Input.parse_input_event`, or set their aim directly) and print progress.
Done means **zero `SCRIPT ERROR`s** locally, with `BOT_PLAYERS=6`, and networked. Also:
- This machine has real controllers attached (the family's pads). **Always run test Godots through
  `godot-test`** (same arguments as `godot`; it hides /dev/input and /dev/hidraw* in a bwrap sandbox and
  turns SDL's HIDAPI off), or through brepl's `godot.launch` / `dev.bots`. A test Godot that can see the
  real controllers is stopped by the test-throttle guard. Bots should still ignore real pads and resume if
  something pauses the game.
- Add a fake-VR mode that moves the XR hands, so the VR code path runs headless too.
- **Steam Deck**: a Deck alone is ONE full-screen player on its own controls (party games: core/party.gd drops the
  keyboard seat; classic games: `seats.deck_solo()` in core/classic_seats.gd, which also claims a Deck pad that
  connects late); friends' pads still drop in. `tests/deck_bot.tscn` (+ deck2..deck4) plays every game as a Deck
  and checks it; `tests/arcade_bot.tscn` checks the arcade menu and pause menu at Deck and TV size.
- For games with walls and furniture, check that every room, doorway and spawn can be reached on
  foot (see `tests/hide_and_seek_bot.gd`).

### Several machines in ONE game (host + joining bots)

Bugs between machines only show with several of them (2026-10-24: in the arcade lobby a choice received from another
machine was sent back out, so with a few Decks connected the selection bounced forever). `tools/multibot.ts` runs
**one shared test game or lobby**: a host plus N joining machines (N = 1..6), each its own `godot-test` process with
its own user data, all on one private random `DUO_PORT` (also used for the lobby (+1) and the LAN beacons (+2)), every
one running the same bot scene:

```sh
tools/multibot.ts res://tests/arcade_lobby_bot.tscn                  # host + 3 joiners in one arcade lobby
tools/multibot.ts -n 3 --seconds 150 res://tests/balloon_pop_bot.tscn
tools/multibot.ts -n 3 --host-env DUO_FLAT_HOST=1 res://tests/engine_template_bot.tscn
#   --env K=V (all machines)  --join-env K=V  --stagger MS  --json  --project DIR
```

It prints ok / FAIL per machine (exit 0 from the bot itself, no `SCRIPT ERROR`, no `BOT ASSERT FAILED` /
`BOT RESULT: FAIL`) with each log (`/tmp/multibot-<port>/m<k>.log`), and exits non-zero if anything failed. From brepl:
`dev.bots.run(id, {net: true, joiners: 3})`. Keep N at 3–4 while the family is playing.
Every bot must **end by itself** in a networked run, or multibot reports "timed out: the bot never ended by itself": call
`bot_kit` `finish()`, `quit()`, or arm `preload("res://tests/bot_end.gd").arm(self)` in `_ready` (quits after `BOT_END`
seconds when networked; default host 150 s, joiners 140 s). `godot-test --headless --path . -s res://tests/bot_end_test.gd`
checks every bot.

What a bot gets: `BOT_MACHINE` (0 = host, 1.. = joiners), `BOT_MACHINES` (how many in all) and `BOT_GROUP_T0` (a
shared clock in unix ms, after every machine has started: schedule inputs on it so machines press at chosen moments,
see `tests/arcade_lobby_bot.gd`). Group checks: print `BOT AGREE <key>=<value>` and every machine must print the same
value (the game everyone settled on, the round they are in...). Writing bots that work with several joiners:
- The host sees EVERY joining machine's players: assert `kit.seated_want(want, host_p)`, not `want`.
- Whole-game toggles (Start = pause for all, Y = shared view) are tested by one machine only:
  `if not host and BotKit.lead_machine():`. Another machine may still pause the game under you: a check that needs
  movement should skip while paused (see the jump check in `tests/balloon_pop_bot.gd`).
- `tests/arcade_lobby_bot.gd` (host + 3): joiners press LB/RB/d-pad one after another, then all at the same moment;
  every machine must settle on the same game, rebuild its menu / send / receive selections no more than the presses
  explain (`arcade.stats`), stay quiet once settled, and all start the same game when one presses A. Run it after
  any change to the arcade lobby.
