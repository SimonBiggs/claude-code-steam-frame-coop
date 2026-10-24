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

1. **Avatars of other machines** (party games, "P-AV"): `make_snapshot()` carries every TV avatar's
   slot + position + yaw (+ whatever the game shows: carry state, pitch...); `apply_snapshot()` positions
   every seat that is not `party.is_local(slot)`. Avatars already exist via `player_joined`.
2. **Per-machine leave**: implement `on_machine_left(peer)`: drop only `party.slots_of(peer)` state
   (inputs, carries); keep "waiting for the TV" / solo logic for when `net.peer_count() == 0`.
3. **Per-machine join**: re-syncs go to the newcomer (`event_to`), restarts only on the first machine.
4. **Flat host**: with `net.mode == "host" and not net.has_vr`, slot 0 is a pad/keyboard player on the host
   (set `party.allow_slot0 = true` there, give it a camera/HUD like local play, no VR rig).
5. **Classic games** (players array + on_p2_action): the host owns seat assignment. Keep owners in the
   state store (`net.state_set("owners", {index: peer})`), accept "join" via `net.sender_peer()`, treat seats
   owned by other machines as ghosts (mirrors) on clients, give pads only to owned seats, and free only
   the leaving machine's seats in `on_machine_left`.
6. Opt in (`multi_machine`, arcade `"multi": true`), then test: `dev.sweep({ net: true, clients: 2,
   only: [id] })` (host + 2 TV machines offscreen, sheets per machine), the bot test, and a flat-host run.
