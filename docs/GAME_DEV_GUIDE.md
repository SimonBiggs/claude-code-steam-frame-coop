# Making a game for claude-code-steam-frame-coop

Each game is a co-op game for **one VR player on a Steam Frame plus 1–2 players on a TV**,
connected over the home network. There's also a split-screen fallback when no headset is present.
`games/duo_arena/` is the reference implementation: read it before starting.

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

- Put XR on the **main viewport**: `get_viewport().use_xr = true`. A SubViewport gives a flat "theatre" view.
- `XROrigin3D` > `XRCamera3D` + `XRController3D` (`tracker = "left_hand" / "right_hand"`, `pose = "aim"`).
- Actions (default map): `get_vector2("primary")` (thumbstick), `get_float("trigger")`,
  `is_button_pressed("ax_button")`, `"menu_button"`, and `trigger_haptic_pulse("haptic", 0, amp, dur, 0)`.
- Move the XR origin in `_process` (per frame), not `_physics_process`, or it judders.
  Snap-turn on the right stick. The player may be **sitting down**.
- 2D UI doesn't show in VR. Use `Label3D` attached to the XR camera (about 1.7 m ahead) with a thick
  black outline (`outline_size` around 26), or on the wrist.
- Give the VR player a role that uses their **hands**, different from the TV players' role.
- `Engine.physics_ticks_per_second = 90` in VR.

## Performance (the Frame has a phone-class GPU, target 72 fps)

- The Frame runs with `--rendering-method mobile`. In VR turn off SSAO, fog and directional shadows,
  and use MSAA 2x.
- Keep draw calls low: use few meshes per object, sphere segments around 12–20 (not the default
  64), and avoid hundreds of nodes.
- No sync GPU readbacks every frame. The gdev bridge records the group `gdev_capture` viewport
  (add a small mirror SubViewport like duo_arena's `_build_vr_mirror` so people can watch the VR view).

## GDScript pitfalls (Godot 4.7)

- `var x := <Variant expression>` is a **parse error**: untyped vars, array elements, dictionary
  values and calls on untyped objects need explicit types (`var x: float = arr[i]`).
- No `class_name`: use `const Foo := preload("res://games/<id>/foo.gd")` and `Foo.new()`.
- The scripts hot-reload while the game runs, so prefer lazily created nodes. Static vars keep
  stale values across reloads (use `Engine` metadata for caches). An error in `_process` skips the
  rest of that frame.
- `WorkerThreadPool` tasks must be waited on, or their memory leaks.
- Never `pkill -f` with a pattern that also matches your own command line.

## Testing (headless only; never open windows on this machine, it's the family's TV)

```sh
godot --headless --path . --import                      # once, in a fresh checkout
godot --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/<id>_bot.tscn
# networked: same bot scene on both sides (so node paths match), real time (no --fixed-fps)
DUO_PORT=78xx DUO_HOST=1 timeout 40 godot --headless --path . res://tests/<id>_bot.tscn &
DUO_PORT=78xx DUO_JOIN=127.0.0.1 timeout 33 godot --headless --path . res://tests/<id>_bot.tscn
```

The bot should load the game (`load("res://games/<id>/main.tscn").instantiate()`), drive the
players (press keys with `Input.parse_input_event`, or set their aim directly) and print progress.
Done means **zero `SCRIPT ERROR`s** locally and networked.
