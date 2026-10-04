# Engine systems

Shared building blocks for new games. Each is a plain script (no `class_name`):
`const Party := preload("res://core/party.gd")`, then `Party.new()`.
**Start from `games/engine_template/`** (a complete little game using all of them, with
`tests/engine_template_bot.gd`), then read the module you need below.

| Module | What it does |
|---|---|
| `core/party.gd` | Who plays on the TV and with which controller: drop-in seats, per-slot input |
| `core/split_view.gd` | The TV picture: per-player views in a grid, or one shared view; VR bubble |
| `core/camera_rig.gd` | TV cameras: third-person follow, group framing, cinematic shots, shake |
| `core/vr_rig.gd` | The VR player: rig, gloves, height fit, locomotion, guarded trigger, mirror, avatar |
| `core/net.gd` | Networking (existing API) + state store, `request()`, shared pause, `just_unpaused()` |
| `core/save.gd` | Persistent saves per game (versioned, atomic), test saves kept apart |
| `tests/bot_kit.gd` | Bot test helpers: ignore real pads, virtual pads, fake VR driver, asserts |

Slots everywhere: **slot 0 = the VR player ("P1")**, slots 1..6 = TV players ("P2".."P7").
Colours: `Party.COLORS[slot]` (same palette as the first 17 games).

## The game contract (engine style)

`main.gd` is a Node3D named `Main`, with `net` as a child named `Net` (RPC paths match on both
machines). Name these members exactly so core/ finds them: `net`, `party`, `vr_rig`,
`ready_to_play`. Everything else is optional (core/net.gd checks `has_method`):

| Member on main | Called on | When |
|---|---|---|
| `on_request(slot, action, args)` | host / local | `net.request()` from any machine |
| `on_remote_state(slot, pos, yaw, pitch)` | host | the TV machine's `net.send_state(pos, yaw, pitch, slot)` |
| `make_snapshot() -> Array` | host, 30 Hz | while the TV machine is connected |
| `apply_snapshot(s)` / `apply_event(kind, args)` | TV machine | snapshots / `net.event()` |
| `on_pause_changed(paused, by_slot)` | every machine | shared pause: wrist MENU (slot 0) or a TV pause menu (the slot that pressed Start / Esc); nothing else runs while paused, so show banners here |
| `on_client_joined()` / `on_client_left()` | host | also signals `net.client_connected` / `client_disconnected` |
| `toggle_vr_pause()` | host | optional override of the default wrist-MENU pause |

Classic games (a `players` array + `on_p2_action`) keep the old routing unchanged.
Modes are decided like before (`DUO_JOIN` = TV machine, headset or `DUO_HOST` = host, else local);
copy `_ready()` / `_setup()` from the template.

## core/party.gd: PartyManager

```gdscript
party = Party.new(); party.name = "Party"; add_child(party)        # as main.party
party.player_joined.connect(func(slot: int, device: int) -> void: spawn(slot))
party.player_left.connect(func(slot: int) -> void: despawn(slot))
# every frame, per local slot:
var mv := party.stick(slot, "move")            # Vector2, y DOWN (like Input.get_vector)
if party.just_pressed(slot, "accept"): ...     # A (keyboard: Space / Enter / click)
var step := party.nav(slot)                     # Vector2i menu step with key repeat
```

- **Joining**: A on an unowned pad (never Start), or Space/Enter for keyboard+mouse
  (`allow_keyboard`). At start the roster from the previous scene is restored (restart, reconnect,
  next game), else the first pad joins by itself (`auto_join_first_pad`). On the TV machine joins
  are sent to the host, which confirms (`is_pending(slot)` meanwhile); on the host the TV's players
  appear with `device == Party.REMOTE`. Host-side rules: `accept_joins = false`, or
  `join_filter = func(slot: int) -> bool`; refusals emit `join_refused(device, reason)` on the TV.
- **Leaving**: a controller that disconnects keeps its seat for `leave_after` s (`device_lost`,
  `device_restored`); then the player leaves; plugging it back in rejoins the same seat.
  `leave(slot)` frees a seat (a "quit" menu item, kicking; `leave(slot, true)` lets that pad
  rejoin by being plugged in again). When the TV machine disconnects, the
  host's REMOTE seats leave; they come back when it reconnects.
- **Roster**: `owner_of(device) -> slot|-1`, `device_of(slot)`, `active_slots()`, `local_slots()`
  (seats driven on THIS machine: the ones needing a view), `player_count()`, `is_active/is_local/
  is_remote/is_pending/is_lost(slot)`, `name_of(slot)` ("P3" or `set_player_name`), `color_of(slot)`.
- **Input per slot** (reads only that slot's device; remote slots read as idle):
  `pressed / just_pressed / just_released(slot, action)` with actions `accept`/`a`, `back`/`b`,
  `x`, `y`, `lb`, `rb`, `lt`, `rt`, `start`, `select`, `l3`, `r3`, `up`/`down`/`left`/`right`, `dpad`;
  `any_just_pressed(action) -> slot|-1`; `stick(slot, "move"|"look"|"dpad")`;
  `trigger(slot, "lt"|"rt") -> 0..1`; `look(slot, delta) -> radians` (right stick or the mouse);
  `nav(slot) -> Vector2i`; `rumble(slot, weak, strong, s)`. Edges work in `_process` AND
  `_physics_process`, and quick taps between frames count. Buttons held when a player joins or when
  the game unpauses must be released first (the A that joined never "accepts"); call `guard(slot)`
  / `guard_all()` after your own screen changes.
- Keyboard player: move WASD, look mouse, accept Space/Enter/left click, back Backspace/right
  click, x F, y R, lb Q, rb E, lt Shift, rt Ctrl, start Tab, select M, d-pad arrows.
  Esc stays the pause menu. A keyboard join waits 0.15 s and is dropped if a pad button went down
  with it (Steam's desktop layout sends keys for pad buttons: no phantom keyboard players).
- `allow_slot0 = true` (local play without a headset) makes slot 0 a joinable TV seat.
- The pause menu (`core/pause_menu.gd`) only opens from a pad the party owns, and reports which
  slot opened it (`on_pause_changed(paused, by_slot)`).
- Bots: `add_virtual_pad() -> device` (ids from 40), `remove_virtual_pad` / `replug_virtual_pad`,
  `inject_button` / `inject_axis`, `join_device(device, slot = -1)`.

## core/split_view.gd: SplitView

```gdscript
split = SplitView.new(); add_child(split)       # TV machine and local play (not the headset host)
split.bind_party(party)                          # a view per local seat, kept in sync
var cam := split.camera(slot)                    # its own Camera3D (move it, or use CameraRig)
split.hud(slot).add_child(score_label)          # HUD root for that view, scaled to it
split.set_shared(true)                           # one view: split.shared_camera(), shared_hud()
split.set_bubble(vr_mirror)                      # round picture-in-picture of the VR view
```

- Grid: 1 full, 2 side by side, 3-4 = 2x2, 5-6 = 3x2, 7 = 4x2 (`SplitView.grid_for(n)`,
  `cell_rects(n, area)`). With 3, 5 or 7 views `empty_cell_rect()` is free (the VR bubble goes
  there with `bubble_mode = "auto"`, else the top-right corner; or put a map / scoreboard there).
- `set_slots([...])`, `add_slot`, `remove_slot`, `slots()`, `view_count()`, `view_rect(slot)`,
  `hud_scale(slot)`, `viewport(slot)`, `active_camera(slot)` (the shared one in shared mode).
- Shared mode for board games, quiz shows, RPG battles: switch any time; per-player views are kept
  (hidden views don't render) so switching back is instant. While nobody is seated on this screen
  the shared view shows too (`shared_when_empty`, `showing_shared()`): point its camera at the
  world and put "Press A to join" in `shared_hud()`.
- Performance: 3D resolution by view count (`res_scales`), MSAA only up to `msaa_max_views` (2),
  SSAO off beyond 2 views and sun shadows off beyond 4 (`manage_effects`; never touches VR).
- HUD roots are scaled by `clamp(min(w / 940, h / 900), 0.5, 1)`: design at full size, anchor to
  edges/corners. Controls in views don't get GUI focus input: read `party` instead.

## core/camera_rig.gd: CameraRig

```gdscript
var rig := CameraRig.new(); rig.camera = split.camera(slot)
rig.party = party; rig.slot = slot               # right stick / mouse orbits in follow mode
add_child(rig); rig.follow(avatar, 6.0)          # third person
rig.follow_group(avatars, -55.0)                 # top-down / isometric, zooms to fit everyone
rig.shot_look(Vector3(0, 8, 12), Vector3.ZERO, 1.2)   # cinematic, blended over 1.2 s
rig.shake(0.4)                                   # 0.2 bump .. 1 earthquake
```

Follow: `distance`, `pivot_height`, `yaw`/`pitch` (+ limits), `follow_smoothing`, `auto_behind`
(rad/s to swing behind a moving target), wall avoidance against `collision_mask` (sphere cast,
pulls in fast, eases out). Group: `set_targets(nodes)`, `group_margin`, `group_min/max_distance`,
`group_distance()`. Shot: `shot(xform, blend, drift)`. `release()` = your code drives the camera;
`snap()` = skip smoothing after a teleport; mode changes blend over `blend_time`.

## core/vr_rig.gd: VrRig (host / local only)

```gdscript
if VrRig.wanted(net.mode):                       # headset found, or a bot with BOT_VR=1
	vr_rig = VrRig.new(); add_child(vr_rig)        # as main.vr_rig (core/net.gd's wrist MENU uses it)
	vr_rig.place(Vector3(0, 0, 3), 0.0)           # feet position, facing -Z
if vr_rig.trigger_pressed(): fire()              # a fresh pull only
var hand := vr_rig.touching_any(bell.global_position, 0.12)   # VrRig.LEFT / RIGHT / -1
vr_rig.pulse(VrRig.RIGHT, 0.5, 0.06)
var throw_velocity := vr_rig.hand_velocity(VrRig.RIGHT)
```

- **Steam Frame: only the thumbsticks, the RIGHT trigger, A and controller positions reach the
  game.** No left trigger, grips, menu, X/Y: give the left hand touch jobs.
- Nodes: `camera` (XRCamera3D), `hand_l`, `hand_r` (XRController3D, "aim" pose), `gloves`,
  `mirror` (480x480 SubViewport in group `gdev_capture`, 30 fps).
- Height: `fit_mode = "eye"` lifts/lowers the player so the eyes are at `eye_height` (1.55;
  limits `fit_limits`), `"none"` keeps real height. Fits on start and re-fits when the head height
  changes by `refit_threshold` for `refit_time` s; signal `refitted(head_height)`. `refit()`,
  `real_head_height()`. Move the player with `place(feet, yaw)` / `floor_height`, not by setting y.
  `place()` is remembered: `recenter()` goes back to it, and the first fit (once tracking starts)
  recentres there too, wherever the player stands in their room (`recenter_on_first_fit`).
- Locomotion: `locomotion` (left stick, head-relative, `move_speed`), `turn_mode` "snap"
  (`snap_degrees`) / "smooth" / "none", `bounds` (Rect2 on XZ), `collision_mask` + `body_radius`
  (slide along walls), `move_filter = func(from, to) -> Vector3`.
- Inputs: `trigger_value()`, `trigger_down()`, `trigger_pressed()`, `trigger_released()`,
  `a_down()`, `a_pressed()`, `stick_left()`, `stick_right()` (**VR sticks: y UP is forward**).
  The trigger and A are guarded: held from the arcade / pause menu / before `guard_trigger()` they
  must be released first, and a pull that starts on the wrist MENU is the menu's.
- Hands: `hand(VrRig.LEFT)`, `hand_point(h)` (palm), `touching(h, point, r)`, `touching_any`,
  `hand_velocity(h)`, `hand_speed(h)` (tracking only, game time), `pulse(h, amp, s)`.
- Wrist MENU zone: `wrist_menu_position()`, `on_wrist_menu()`, `in_wrist_zone(point)`: keep grab
  targets out of it.
- `set_scale_of_world(ws)`; `XRServer.world_scale` is reset to 1.0 when the rig leaves the tree.
- VR settings applied automatically with a headset: XR on the main viewport, MSAA 2x, 90 physics
  ticks, no SSAO/SSIL/SSR/SDFGI/fog, no directional shadows (`VrRig.apply_vr_performance(root)`
  for things you add later).
- TV machine: `var avatar := VrRig.Avatar.new()` (head + gloves, on render layer 20), feed it
  `vr_rig.pack_pose()` (21 floats) from your snapshot, and `split.set_bubble(VrRig.build_mirror(
  self, avatar.head, false))` so everyone sees what the VR player sees.
- Fake mode (no headset, bots): set `fake_trigger`, `fake_a`, `fake_stick_l/r`, move `camera` /
  hands by hand (see BotKit).

## core/net.gd additions

```gdscript
# host / local: the replicated store (menus, turns, scores, inventories, board state)
net.state_set("turn", 3)                      # only changed keys are sent; null erases
net.state_changed.connect(func(key: String, value: Variant) -> void: refresh_ui(key, value))
var turn: int = net.state_get("turn", 0)      # any machine
# any machine: ask the host to do something (local/host: runs main.on_request now)
net.request(slot, "buy", [item_id])
if net.just_unpaused(): return                # ignore buttons held from the pause menu
```

- Store: `state_set(key, value)` (host/local; ignored with a warning on the TV machine),
  `state_get(key, default)`, `state_has`, `state_all()`, `state_clear()`. Deltas are reliable,
  batched per frame, at most 30 Hz; a TV machine that (re)joins gets everything. `state_changed`
  fires on every machine (host included), so UI code is identical everywhere. Arrays/dictionaries
  are copied: call `state_set` again after changing them.
- `request(slot, action, args)`, `toggle_pause(by_slot)`, `just_unpaused(window = 0.3)`.
- The old API is unchanged: `event()`, `send_state()`, `send_action()`, `go_to_arcade()`, `mode`,
  `connected`, ENet range-coder compression on both ends.
- Bandwidth: snapshots are 30 Hz, so keep them small (packed arrays, rounded floats, skip idle
  objects, bit flags in one int); one-off things are `event()`s; slow-changing shared state goes in
  the store; never put per-frame values in the store. Stay under ~1.4 KB per snapshot (one packet).

## core/save.gd

```gdscript
save = Save.new(); save.game_id = "dungeon"; save.version = 2
save.defaults = {"gold": 0, "heroes": []}; add_child(save)      # loads save.data
save.data["gold"] += 10; save.mark_dirty()                       # written ~2 s later (and on exit)
var best := Save.load_data("quiz", {"best": 0})                 # one-shot static API
Save.store("quiz", best)
```

Binary `store_var` (types preserved, objects never decoded), versioned (`migrate = func(data,
from_version) -> Dictionary`), atomic (temp file + rename, previous file kept as `.bak` and used if
the save is damaged). `save_now()`, `reload()`, `exists(id)`, `erase(id)`, signals `saved`,
`loaded`. Bots (scene under `res://tests/`, BotKit, or `SAVE_TEST=1`) use `user://test_saves/`.

## tests/bot_kit.gd

```gdscript
kit = BotKit.new(); add_child(kit)           # FIRST, before the game is instanced
main = load("res://games/<id>/main.tscn").instantiate(); add_child(main); kit.main = main
kit.at(1.0, "players join", func() -> void:
	for i in BotKit.bot_players(2): kit.join_bot(main.party))
kit.every(2.0, func() -> String: return "score %d" % main.score)
kit.slot_stick(main.party, slot, "left", Vector2(0, -1))      # pad y DOWN, like a real pad
kit.vr_reach(main.vr_rig, VrRig.RIGHT, target_pos, 2.0, delta)  # fake VR
kit.assert_true(main.score > 0, "scored"); kit.finish()
```

Real pads (device < 40) are swallowed and ignored by the party; a pause the bot didn't ask for is
undone after `resume_after` s (`allow_pause = true` while you pause on purpose). Pads:
`pad_press/pad_hold/pad_stick/pad_trigger(device, ...)`, `slot_press/slot_hold/slot_stick(party,
slot, ...)`, `join_bot(party)`. Fake VR: `vr_pose`, `vr_idle`, `vr_reach`, `vr_look_at`,
`vr_trigger`, `vr_a`, `vr_stick`, `vr_head_height`. Output: `info()`, `at()`, `every()`,
`assert_true/assert_eq/assert_near` (failures print `SCRIPT ERROR: BOT ASSERT FAILED`),
`finish()` (summary + quit).

Run: `godot --headless --path . --fixed-fps 60 --quit-after 1500 res://tests/<id>_bot.tscn`;
networked: same scene with `DUO_HOST=1` and `DUO_JOIN=127.0.0.1` (real time), see the guide.
The engine's own test: `res://tests/engine_sys_test.tscn` (local, and networked with `ENGINE_NET=1`).

## Gotchas

- `process_priority = -100` on party, rig and BotKit's timeline (-200): inputs are sampled
  before your `_process`, so `just_pressed` / `trigger_pressed` are fresh in the same frame.
- Party sticks use y DOWN (Godot pads); VR sticks use y UP (OpenXR). Both documented above.
- Don't keep Resources (meshes, materials) in `Engine` metadata: they outlive the renderer at exit
  and print leak errors. Cache them on a node; use Engine metadata for plain data.
- On the headset host there is no TV: don't create a SplitView there (`net.mode == "host"`).
- `XRServer.world_scale` is global; the rig resets it, games without the rig must too.
