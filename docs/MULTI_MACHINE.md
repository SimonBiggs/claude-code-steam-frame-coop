# Many machines: TV, Steam Decks, Frames

Since 24 Oct 2026 a game can be played by **any number of machines**: one host plus any number of
TV-style machines (the TV, Steam Decks), with or without the VR player on a Steam Frame. Seats are the
real limit (slot 0 = the host player, slots 1..6 = everyone else), not machines.

## Who hosts

- The Steam Frame with its headset on hosts as before (VR player in slot 0).
- With no Frame, the arcade lobby makes the first machine a **flat host** (`net.has_vr == false`):
  slot 0 is a normal pad/keyboard player on that machine, like local play. TV + Decks, or two Decks,
  play together.
- Launchers use `DUO_JOIN=auto`: find whoever is hosting from their LAN beacon (`net.join("auto")`).
- Each machine says what it is: env `DUO_MACHINE_KIND` (`tv`, `deck`; a Frame with a headset is `frame`).

## Opting a game in

Old games keep the old contract (one TV machine; extra machines are told the game is full and play on
their own; never flat-hosted). A converted game declares on `main`:

```gdscript
## Any number of TV machines (TV, Steam Decks) may join, and a flat host (no VR) works (docs/MULTI_MACHINE.md).
var multi_machine := true
```

and gets `"multi": true` in `arcade/arcade.gd` GAMES (so the lobby may flat-host it).

## Core API

`core/net.gd`
- `net.machines` (host): peer id -> {kind}. `net.peer_count()`, `net.my_peer_id()`, `net.machine_kind_of(peer)`.
- `net.sender_peer()`: inside `on_p2_action` / `on_request` / `on_remote_state` / sys handlers on the host,
  the peer id of the machine that sent it.
- Callbacks on `main` (optional): `on_machine_joined(peer, kind)`, `on_machine_left(peer)`.
  `on_client_joined()` still fires for every machine; `on_client_left()` fires for old games on every
  leave, but for multi_machine games only when the LAST machine leaves. Use `on_machine_left(peer)` to
  remove just that machine's players.
- Signals: `machine_joined(peer, kind)`, `machine_left(peer)` (plus the old client_connected/disconnected).
- `net.event_to(peer, kind, args)`, `net.event_except(peer, kind, args)`: one-off events for one machine /
  all but one (re-syncs for a newcomer, relaying a sound the sender already played).
- `net.connected` still means "at least one machine is connected" (host) / "joined" (client).
- `net.has_vr` (host): false on a flat host.

`core/party.gd`
- The host gives out seats: a machine asking for a taken seat is moved to the next free one.
- Every machine sees **every** seat: other machines' players are seated with device REMOTE
  (`is_local(slot) == false`, `is_remote(slot) == true`) and `player_joined` / `player_left` fire for them,
  so create avatars on `player_joined` for all seats, cameras/HUDs only for `is_local(slot)`.
- `party.machine_kind(slot)`: "host", "tv", "deck", "frame"... same answer on every machine. Use it if a
  game wants Deck players to play differently.
- `party.machine_of(slot)` (host): owning peer id. `party.slots_of(peer)` (host): that machine's seats.
- A flat host seats its own controllers like local play (allow_slot0 games: slot 0 too).

## Converting a game (checklist)

Reference: `games/engine_template/main.gd` does all of it (`net_target` + `_follow_remote` smoothing,
`on_machine_left`, `flat_host`, the Deck's single player, the VR avatar only when the host sends a pose) and
`tests/engine_template_bot.gd` runs a flat host (`DUO_FLAT_HOST=1` on the host: one bot pad in slot 0).
Name the member `flat_host`, not `flat` (games use local `flat` vectors). The Y split/shared view is shared
by every machine, so bots shouldn't assert it on a flat host (the client's presses toggle it too).

1. **Avatars of other machines** (party games, "P-AV"): `make_snapshot()` carries every TV avatar's
   slot + position + yaw (+ whatever the game shows: carry state, pitch...); `apply_snapshot()` positions
   every seat that is not `party.is_local(slot)`. Avatars already exist via `player_joined`.
2. **Per-machine leave**: implement `on_machine_left(peer)`: drop only `party.slots_of(peer)` state
   (inputs, carries); keep "waiting for the TV" / solo logic for when `net.peer_count() == 0`.
3. **Per-machine join**: re-syncs go to the newcomer (`event_to`), restarts only on the first machine.
4. **Flat host**: with `net.mode == "host" and not net.has_vr`, slot 0 is a pad/keyboard player on the host
   (set `party.allow_slot0 = true` there, give it a camera/HUD like local play, no VR rig).
5. **Classic games** (players array + on_p2_action): use `core/classic_seats.gd` (below), never a copy.
6. Opt in (`multi_machine`, arcade `"multi": true`), then test: `dev.sweep({ net: true, clients: 2,
   only: [id] })` (host + 2 TV machines offscreen, sheets per machine), the bot test, and a flat-host run.

## Classic games: core/classic_seats.gd

One shared home for seat ownership in classic games (a `players` array + `on_p2_action`). The game makes
one helper and passes only what is special about it; everything else (owners in the state store, join
arbitration, ghosts, per-machine leave, Deck solo) lives in the helper. The API is at the top of the file.

```gdscript
const ClassicSeats := preload("res://core/classic_seats.gd")
var seats: ClassicSeats  # core/net.gd finds it here
# in _ready, right after add_child(net):
seats = ClassicSeats.new(self, {"no_keys": PlayerScript.NO_KEYS, "free_actions": ["pause", "restart"],
	"full": func() -> void: _show_center("All seats are taken!", 1.5, false)})
```

- Host: `on_p2_action` starts with `index = seats.host_action(action, args, index)` / `if index < 0: return`
  (grants "join" or redirects it to a free seat, frees on "leave", drops other machines' actions).
  core/net.gd also drops TV state / actions for seats the sender doesn't own (`seats.remote_ok`), so
  player scripts need no owner checks. `on_machine_left(peer)`: `seats.machine_left(peer)` (returns the
  freed seats); `on_client_left()`: `seats.all_left()`; `on_client_joined()`: start / restart only
  `if seats.first_machine()`.
- TV machine: `seats.sync()` every frame, `seats.request_joins(delta)` for seats marked `want_join`
  (cleared only when `seats.joined(p)`: active AND ours), `if seats.handle_event(kind, args): return` at
  the top of `apply_event`, `seats.foreign(i)` (another machine's seat: a ghost here), `seats.free_index()`.
- Local: `if seats.deck_alone(): seats.deck_solo(0)`: a Deck on its own is one full-screen player on
  its built-in controls.
- Game specifics go in as options: `player(i)`, `is_local(p)`, `keys(p)`, `seat_free(p)`, `seat_limit()`,
  `ghost(p, on)`, `moved(from, to)`, `full()`, `deactivate(p)`, `save()`, `layout()`, `ensure_view(p)`.
- Other machines' players must be MIRRORED on every TV machine: the snapshot carries each active seat's
  position + yaw, and `apply_net_state` moves a seat when it is a ghost here. Games whose players already
  glide to `net_target` when `remote` (bee garden, block builders, giant's table, kitchen rush) set
  `p.remote = on` in the `ghost(p, on)` option; games with their own `ghost` mirror (ghost lantern, hide and
  seek, snowball blitz) only snap (`net_started = false`).
- A TV machine's first seat (P2) starts playing locally, so it must still ask: mark it `want_join` in
  `_setup_game` for client mode (the host may hand out another seat). Never clear `want_join` just because
  the seat is active (`seats.joined(p)` = active AND ours).
- A flat host's slot-0 player needs a controller too (`_auto_bind_pad` / base slots: host and not VR).
- Check: `godot-test --headless --path . -s res://tests/classic_seats_test.gd` (every multi_machine classic
  game uses the helper, no seat-code copies, arcade `"multi"` matches, the helper's arbitration).
