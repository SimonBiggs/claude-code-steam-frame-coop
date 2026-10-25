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
   only: [id] })` (host + 2 TV machines offscreen, sheets per machine), the bot test, a flat-host run, and the bot
   with several joining machines: `tools/multibot.ts -n 3 [--host-env DUO_FLAT_HOST=1] res://tests/<id>_bot.tscn`
   (docs/GAME_DEV_GUIDE.md "Several machines in ONE game").

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

## Deploys while playing (core/safe_apply.gd)

Deploys reach every machine straight away (duo-deploy rsync, LAN updates), but new code only **switches on at a
safe point**, so a deploy never changes a game someone is playing:
- **Mid-game** the running game's code waits: core/, tests/, the game's own folder, and anything already loaded.
  arcade/ scripts and other games' files go through, because nothing is running them. A small "• update ready" note
  shows bottom-right (no popup).
- **Leaving a game** is a safe point. Use `SafeApply.change_scene(path)` instead of `change_scene_to_file` when a
  game leaves for the arcade or follows another machine into a game (net.gd and pause_menu.gd already do).
- **In the arcade menu** changes wait until files have been quiet for 1 s, so a half-copied deploy never applies. A
  machine on its own applies right away. In a lobby every machine switches **together**: each joiner tells the host
  its disk version (a hash of every game script), and the host says "apply now" once all match (after 20 s at most).
- **Starting a game** applies everything first. The lobby host holds a start while a machine's files are still
  arriving or waiting to switch on (15 s at most), so nobody plays a mixed-version game. A machine whose code
  differs permanently (it missed a deploy) doesn't block a start: LAN updates bring it up to date.
- The menu rebuilds in place: same tab, same highlighted game, same lobby connection, no blank frame.
- Your game can mark its own safe moment (between levels): `get_tree().current_scene.set_meta("safe_to_apply",
  true)`. It only counts when the game isn't networked.
- Switch on at once: `DUO_APPLY_NOW=1 duo-deploy "msg"`, or `touch <game>/.dev/apply_now` on one machine.
  `GDEV_APPLY=now` restores the old way (offscreen godot.ts runs already apply at once).
- How it works: no gdev bridge change. SafeApply runs just before the bridge's file scan and records held files'
  new mtime/md5 in the bridge's own tables, so the bridge only reloads them when they're released.
- Test: `tools/multibot.ts --copies -n 2 --seconds 120 res://tests/safe_apply_bot.tscn`. Each machine runs its
  own copy and fake deploys reach them one after another.

## Updates over the home network (core/lan_update.gd)

Game code travels inside the arcade: whoever hosts a lobby passes its version to the machines that join, so every
machine in a lobby runs the same code, with no SSH or devkit pairing (Simon: "it updates via the host and only over the
local network"). It works with the Steam Machine switched off: any machine holding a newer signed version serves it.

- **Signed.** `tools/duo-update-bundle GAME_DIR` writes `GAME_DIR/.update/manifest.json` (timestamp, signer, content
  hash, every file's SHA-256) + `manifest.sig` (RSA-SHA256). Signers: the Steam Machine = the ROOT (public key pinned in
  `addons/lan_update/root.pub.pem`) and code signers listed in `core/lan_update/signers.json` (+ `.sig`), a list only
  the root can sign (`tools/duo-update-signers`). Private keys live only in `~/.config/duo-arena/update-key/` on their
  own machine (`tools/duo-update-keygen NAME`), never committed or copied. `duo-deploy` signs the live copy;
  a signer Deck ships with `tools/duo-update-ship`. Other machines can RELAY a signed update but not make one.
- **Newest wins**: versions compare by (timestamp, signer, content hash); a bundle stamped more than 5 minutes in the
  future is refused. A joiner takes a newer version from its lobby host; the host takes a newer version from a member
  (so a fresh deploy spreads both ways). A revoked signer's bundles are refused by every machine that has seen the root's
  newer signer list (lists are adopted only with the root's signature and only if newer).
- **Local, host only**: transfers run over the arcade lobby's ENet connection, only in the lobby, only with private
  addresses (10/8, 172.16/12, 192.168/16, link-local, loopback), and a joiner only from peer 1 (its host). Everything
  else is refused and logged (`LanUpdate: REFUSED ...`). Limits: 4000 files, 8 MB/file, 64 MB total, 1 MB/s served.
- **Only game code**: core/ games/ arcade/ tests/ arcade.tscn. Never addons/ (gdev can't hot-reload itself; the guard
  and the root key must survive a bad update), project.godot or the signer list (that travels on its own signature).
- **Safe apply**: only changed files are fetched into `res://.update/staging` and checked against the signed hashes,
  then swapped in (temp file + rename) while the arcade MENU shows, never during a game. The old files go to
  `res://.update/backup` first. Every changed script is compiled at once; an error rolls everything back and that
  version is never fetched again. `addons/lan_update/guard.gd` (autoload LanUpdateGuard) also rolls back if the arcade
  isn't running 15 s after an update or the game was started 3 times without getting healthy. The gdev bridge then
  hot-reloads the new files (through core/safe_apply.gd: all lobby machines switch together).
- Copies run from a git checkout (the TV's live copy, worktrees) are where code is made: they serve but never take
  updates (`DUO_UPDATE_RECEIVE=1` overrides). The source of truth is git: a signer Deck commits and pushes to the Steam
  Machine's repo before `duo-update-ship`.
- Tests: `godot-test --headless --path . -s res://tests/lan_update_test.gd` (addresses, paths, version order, every
  script passes the post-apply compile check) and `tools/lan-update-test` (host + joiners as separate processes with
  their own game copies and test keys on a private port: update, tampering, forged/unknown/revoked signers, wrong
  machine, public address, three Decks with no Steam Machine, rollback, boot guard, mid-game deferral, future stamps).
