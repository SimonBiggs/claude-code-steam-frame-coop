extends Node3D
## PARTY BOARD: a board-game party on Party Island, Mario-Party style.
## Everyone has a token on a diorama island (beach, Candy Forest, volcano, river bridges, lagoon pier).
## Each turn a player rolls the dice and hops round the board: blue spaces give coins, red ones take
## them, event spaces do something surprising, shops sell items, duel spaces start a Quick Draw, and
## the STAR (20 coins) is what everyone wants: it moves after every purchase. After every round all
## players play a MINIGAME for coins. Most stars after the last round wins (bonus stars at the end).
##  - The VR player (slot 0, the host) sees the island as a big table-top diorama: they throw a giant
##    die onto the board, point at branch arrows, and play every minigame with their hands.
##  - TV players (slots 1-6) drop in with A on a spare pad; they press A to stop their dice block, pick
##    paths with the stick and use menus. CPU players fill up to 4 seats.
##  - Local play without a headset: slot 0 is a TV seat too (core/party.gd allow_slot0).
## Files: board_data.gd (spaces + island shape), board_view.gd (the diorama), token.gd, rules.gd,
## turn_flow.gd (host game logic), dice.gd, hud.gd, menus.gd, mg_runner.gd + minigames/*.gd,
## ceremony.gd, giant_avatar.gd, sequencer.gd.
## Networking: the host decides everything and publishes board state in the net state store
## (players, turn, dice, menus, minigame phase); the TV machine draws from it, mirrors minigames from
## snapshots, sends menu choices / dice hits with net.request() and minigame sticks with send_state().
## Bot knobs (tests/party_board_bot.gd): rounds_override, mg_force / PB_MINIGAME, mg_all /
## PB_ALL_MINIGAMES, mg_time_scale, quick.

const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const Party := preload("res://core/party.gd")
const SplitView := preload("res://core/split_view.gd")
const VrRig := preload("res://core/vr_rig.gd")
const CameraRig := preload("res://core/camera_rig.gd")
const Save := preload("res://core/save.gd")
const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const Hints := preload("res://core/hints.gd")
const Awards := preload("res://core/awards.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const SkyKit := preload("res://core/sky_kit.gd")
const BD := preload("res://games/party_board/board_data.gd")
const BoardView := preload("res://games/party_board/board_view.gd")
const TokenScript := preload("res://games/party_board/token.gd")
const Rules := preload("res://games/party_board/rules.gd")
const TurnFlow := preload("res://games/party_board/turn_flow.gd")
const DiceScript := preload("res://games/party_board/dice.gd")
const HudScript := preload("res://games/party_board/hud.gd")
const MenusScript := preload("res://games/party_board/menus.gd")
const MgRunner := preload("res://games/party_board/mg_runner.gd")
const GiantAvatar := preload("res://games/party_board/giant_avatar.gd")
const CeremonyScript := preload("res://games/party_board/ceremony.gd")
const UiMenu := preload("res://core/ui_menu.gd")

const GAME_ID := "party_board"
## VR: one board unit is 6.5 cm, the island sits on a table in front of the VR player.
const S_VR := 0.065
const TABLE_Y := 0.78
const TABLE_R := 1.3
const VR_FEET := Vector3(0.0, 0.0, 1.5)
## TV cameras look from the north (-Z) towards the south, so the VR giant faces the TV players.
const CAM_DIR := Vector3(0.0, 0.62, -0.78)
const INTRO := {
	"title": "PARTY BOARD",
	"goal": "Collect the most STARS! Buy one for 20 coins when you pass it. Win coins in minigames!",
	"vr": {"role": "THE GIANT PLAYER", "controls": [["TRIGGER", "Grab the dice, let go to THROW it"],
		["POINT + TRIGGER", "Choose paths and menus"], ["L-STICK", "Walk round the table"], ["R-STICK", "Turn"]]},
	"tv": {"role": "THE ISLANDERS", "controls": [["A", "Hit the dice block / choose"], ["L-STICK", "Pick a path"],
		["START", "Pause"]], "tips": ["Blue spaces give coins, red ones take some.", "Pass the STAR with 20 coins to buy it!"]},
}

# --- Bot / test knobs ---
var rounds_override := 0  ## > 0: forces the number of rounds (bots use 3)
var mg_force := ""  ## a minigame id every round (PB_MINIGAME)
var mg_all := false  ## cycle through every minigame (PB_ALL_MINIGAMES)
var mg_time_scale := 1.0  ## bots shorten minigames
var quick := false  ## bots: shorter pauses between steps

# --- The networking contract (see docs/engine/systems.md) ---
var net: Node
var ready_to_play := false
var players: Array = []  ## unused (core/net.gd looks for it); the player records are roster()
var party: Party
var split: SplitView
var vr_rig: VrRig
var save: Save
var sfx: Node
var music: Node
var hints: Hints
var awards: Awards
var sky: SkyKit.SkyRig

var S := 1.0  ## world metres per board unit on this machine
var stage: Node3D  ## board units: the board and minigame arenas live under it
var data: BD
var board: BoardView
var tokens := {}  ## pid -> token.gd
var flow: TurnFlow  ## host / local only
var dice: DiceScript
var hud: HudScript
var menus: MenusScript
var runner: MgRunner
var ceremony: CeremonyScript
var cam: CameraRig  ## the TV's shared camera
var giant: GiantAvatar  ## TV machine: the VR player seen from the TV
var tv_ui: Control  ## the shared view's UiKit root
var vr_room: Node3D
var remote_in := {}  ## host: slot -> [Vector2 move, int presses, bool held]
var _press_seen := {}  ## host: slot -> presses already counted
var _local_press := {}  ## TV machine: slot -> presses so far
var _send_t := 0.0
var _cam_from := Vector3(0, 30, -36)
var _cam_at := Vector3.ZERO
var _cam_want_from := Vector3(0, 30, -36)
var _cam_want_at := Vector3.ZERO
var _cam_speed := 2.5
var _cam_orbit := 0.0
var _pause_vr: Node3D
var _pause_tv: Control
var _synced := false


func _ready() -> void:
	var menu := PauseMenuScript.new()
	menu.main = self
	add_child(menu)
	net = NetScript.new()
	net.name = "Net"
	net.main = self
	add_child(net)
	net.state_changed.connect(_on_state_changed)
	party = Party.new()
	party.name = "Party"
	add_child(party)
	party.player_joined.connect(_on_player_joined)
	party.player_left.connect(_on_player_left)
	save = Save.new()
	save.game_id = GAME_ID
	save.version = 1
	save.defaults = {"parties": 0, "giant_wins": 0, "best_stars": 0, "most_coins": 0, "wins": {}, "mg_played": {}}
	add_child(save)
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("town")
	music.prepare(["party", "shop", "tension", "victory"])
	awards = Awards.new()
	hints = Hints.new()
	add_child(hints)
	hints.bind_party(party)
	if OS.has_environment("PB_MINIGAME"):
		mg_force = OS.get_environment("PB_MINIGAME")
	if OS.has_environment("PB_ALL_MINIGAMES"):
		mg_all = true
	if OS.has_environment("DUO_JOIN"):
		net.join_finished.connect(func(ok: bool) -> void: _setup("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if VrRig.headset_available() or OS.has_environment("DUO_HOST"):
			net.host()
		_setup(net.mode)


func _setup(mode: String) -> void:
	if VrRig.wanted(mode):
		vr_rig = VrRig.new()
		add_child(vr_rig)
		vr_rig.bounds = Rect2(-TABLE_R - 0.6, -TABLE_R - 0.6, (TABLE_R + 0.6) * 2.0, (TABLE_R + 0.6) * 2.0)
		vr_rig.place(VR_FEET, 0.0)
		hints.set_vr_rig(vr_rig, self)
	S = S_VR if vr_rig != null else 1.0
	data = BD.new()
	_build_world()
	if mode != "host":
		split = SplitView.new()
		split.camera_near = 0.05 * S
		split.camera_far = 900.0 * maxf(S, 0.2)
		add_child(split)
		split.set_shared(true)  # one view for everyone, like a real party board game
		cam = CameraRig.new()
		cam.camera = split.shared_camera()
		cam.max_shake_offset = 0.16 * S
		add_child(cam)
		tv_ui = UiKit.ui_root(split.shared_hud())
		hints.add_view(tv_ui, -1)
		if mode == "client":
			giant = GiantAvatar.new()
			giant.main = self
			stage.add_child(giant)
			split.set_bubble(VrRig.build_mirror(self, giant.head, false))
		elif vr_rig != null:
			split.set_bubble(vr_rig.mirror)
	party.allow_slot0 = mode == "local" and vr_rig == null
	dice = DiceScript.new()
	dice.main = self
	add_child(dice)
	hud = HudScript.new()
	hud.main = self
	add_child(hud)
	menus = MenusScript.new()
	menus.main = self
	add_child(menus)
	runner = MgRunner.new()
	runner.main = self
	add_child(runner)
	ceremony = CeremonyScript.new()
	ceremony.main = self
	add_child(ceremony)
	if mode != "client":
		flow = TurnFlow.new()
		flow.main = self
		add_child(flow)
	ready_to_play = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("Party Board: %s mode%s" % [mode, " with a VR player" if vr_rig != null else ""])
	if flow != null:
		flow.begin()
	_sync_all()


# --- World ------------------------------------------------------------------------------------------

func _build_world() -> void:
	sky = SkyKit.apply(self, "day", vr_rig != null)
	stage = Node3D.new()
	stage.name = "Stage"
	add_child(stage)
	if vr_rig != null:
		stage.position = Vector3(0.0, TABLE_Y, 0.0)
		stage.scale = Vector3.ONE * S
		_build_vr_room()
	board = BoardView.new()
	board.name = "Board"
	stage.add_child(board)
	board.build(data, vr_rig != null)


## The VR player's surroundings: a big round picnic table in a garden.
func _build_vr_room() -> void:
	vr_room = Node3D.new()
	vr_room.name = "VrRoom"
	add_child(vr_room)
	var b := MeshKit.Builder.new()
	var wood := Color(0.62, 0.42, 0.27)
	b.cylinder(TABLE_R, TABLE_R, 0.06, MeshKit.at(Vector3(0, TABLE_Y - 0.11, 0)), wood, 40)
	b.torus(TABLE_R, 0.035, MeshKit.at(Vector3(0, TABLE_Y - 0.08, 0)), wood.lightened(0.15), 40, 6)
	b.cylinder(0.12, 0.2, TABLE_Y - 0.12, MeshKit.at(Vector3(0, (TABLE_Y - 0.12) * 0.5, 0)), wood.darkened(0.2), 12)
	b.cylinder(0.55, 0.6, 0.06, MeshKit.at(Vector3(0, 0.03, 0)), wood.darkened(0.25), 20)
	b.disc(9.0, MeshKit.at(Vector3(0, 0.0, 0)), Color(0.42, 0.7, 0.34), 32)
	b.disc(2.4, MeshKit.at(Vector3(0, 0.005, 0)), Color(0.85, 0.3, 0.32), 24)
	for k in 12:
		var a := k * TAU / 12.0
		b.box(Vector3(0.12, 0.7, 0.12), MeshKit.at(Vector3(cos(a), 0.35, sin(a)) * Vector3(7.5, 1, 7.5)), Color(0.95, 0.95, 0.9))
	vr_room.add_child(MeshKit.instance(b.build(), false))
	vr_room.add_child(MeshKit.scatter_random(MeshKit.prop("tree"), 14, Vector3.ZERO, 16.0, 9.0, 0.8, 1.3, PackedColorArray(), 21))
	vr_room.add_child(MeshKit.scatter_random(MeshKit.prop("flower"), 40, Vector3.ZERO, 8.5, 3.0, 0.7, 1.1,
		PackedColorArray([Color(1.0, 0.5, 0.6), Color(1.0, 0.9, 0.4), Color(0.7, 0.6, 1.0)]), 22))
	vr_room.add_child(MeshKit.scatter_random(MeshKit.prop("bush"), 10, Vector3.ZERO, 9.0, 6.0, 0.8, 1.2, PackedColorArray(), 23))


## Board units -> world.
func to_world(p: Vector3) -> Vector3:
	return stage.to_global(p)


## World -> board units.
func to_board(p: Vector3) -> Vector3:
	return stage.to_local(p)


# --- Players and tokens -----------------------------------------------------------------------------

## The replicated player records (Array of Dictionaries), in seat order.
func roster() -> Array:
	return net.state_get("players", [])


func player(pid: int) -> Dictionary:
	for p in roster():
		if int((p as Dictionary)["pid"]) == pid:
			return p
	return {}


func pids() -> Array[int]:
	var out: Array[int] = []
	for p in roster():
		out.append(int((p as Dictionary)["pid"]))
	return out


func name_of(pid: int) -> String:
	var p := player(pid)
	return String(p.get("name", "P%d" % (pid + 1)))


func color_of(pid: int) -> Color:
	return Party.COLORS[posmod(pid, Party.COLORS.size())]


func is_cpu(pid: int) -> bool:
	return bool(player(pid).get("cpu", true))


## True when this machine drives `pid` with a TV controller (its menus / dice open here).
func is_local_tv(pid: int) -> bool:
	return split != null and party.is_local(pid) and not (pid == 0 and vr_rig != null)


## True when `pid` is the VR player on this machine.
func is_local_vr(pid: int) -> bool:
	return pid == 0 and vr_rig != null


## True if the VR player plays in this game (any machine).
func has_vr() -> bool:
	return bool(net.state_get("vr", false))


func token(pid: int) -> TokenScript:
	if tokens.has(pid) and is_instance_valid(tokens[pid]):
		return tokens[pid]
	var t: TokenScript = TokenScript.new()
	t.setup(pid, color_of(pid))
	stage.add_child(t)
	t.hopped.connect(func(_tk: Node3D) -> void: sfx.play("jump", -10.0, 1.3))
	tokens[pid] = t
	if split != null and vr_rig == null:
		HudKit.nameplate(t.body, name_of(pid), color_of(pid), 1.9, 0.42)
	return t


## Bring the tokens in line with the replicated records (hop to the next space, fly further).
func _sync_tokens() -> void:
	var seen := {}
	for p in roster():
		var pd: Dictionary = p
		var pid := int(pd["pid"])
		seen[pid] = true
		var t := token(pid)
		var sp := int(pd.get("space", 0))
		if t.space == sp:
			continue
		if t.space < 0 or not _synced:
			t.place(data.pos(sp))
		elif data.next_of(t.space).has(sp):
			t.hop_to(data.pos(sp))
		else:
			t.fly_to(data.pos(sp), 1.1)
			sfx.play("whoosh", -6.0)
		t.space = sp
	for pid in tokens.keys():
		if not seen.has(pid):
			(tokens[pid] as Node).queue_free()
			tokens.erase(pid)
	_spread_tokens()


## Tokens sharing a space stand in a little circle.
func _spread_tokens() -> void:
	var by_space := {}
	for pid in tokens:
		var t: TokenScript = tokens[pid]
		var list: Array = by_space.get(t.space, [])
		list.append(t)
		by_space[t.space] = list
	for sp in by_space:
		var list: Array = by_space[sp]
		for i in list.size():
			var t: TokenScript = list[i]
			if list.size() == 1:
				t.offset = Vector3.ZERO
			else:
				var a := TAU * float(i) / float(list.size()) + 0.4
				t.offset = Vector3(cos(a), 0.0, sin(a)) * 0.55


func _on_player_joined(slot: int, _device: int) -> void:
	sfx.play("ui_notify", -6.0)
	if flow != null:
		flow.on_human_joined(slot)


func _on_player_left(slot: int) -> void:
	if flow != null:
		flow.on_human_left(slot)


# --- Replicated state -------------------------------------------------------------------------------

func _on_state_changed(key: String, value: Variant) -> void:
	if not ready_to_play:
		return
	match key:
		"players":
			_sync_tokens()
		"star":
			board.set_star(int(value), _synced)
		"phase":
			_on_phase(String(value))
		"sky":
			sky.set_preset(String(value), 4.0)
		"music":
			music.play_mood(String(value), 1.2)
	hud.on_state(key, value)
	menus.on_state(key, value)
	dice.on_state(key, value)
	runner.on_state(key, value)
	ceremony.on_state(key, value)


## Rebuild everything from the store (a TV machine that joined late, or after setup).
func _sync_all() -> void:
	_synced = false
	var all: Dictionary = net.state_all()
	for k in ["players", "star", "phase", "sky", "music"]:
		if all.has(k):
			_on_state_changed(k, all[k])
	for k in all:
		var key := String(k)
		if not key in ["players", "star", "phase", "sky", "music"]:
			_on_state_changed(key, all[k])
	_synced = true


func _on_phase(phase: String) -> void:
	board.visible = phase != "minigame"
	for pid in tokens:
		(tokens[pid] as Node3D).visible = phase != "minigame"


# --- Camera (TV) ------------------------------------------------------------------------------------

## Aim the TV camera (board units); it glides there.
func cam_look(from: Vector3, at: Vector3, speed: float = 2.5, snap: bool = false) -> void:
	_cam_want_from = from
	_cam_want_at = at
	_cam_speed = speed
	if snap:
		_cam_from = from
		_cam_at = at


## Look at a spot from the TV side (north), `dist` board units away.
func cam_focus(at: Vector3, dist: float = 13.0, speed: float = 2.5) -> void:
	cam_look(at + CAM_DIR * dist, at, speed)


func _update_camera(delta: float) -> void:
	if cam == null:
		return
	var phase := String(net.state_get("phase", "title"))
	if phase == "title":
		_cam_orbit += delta * 0.12
		var r := 26.0
		cam_look(Vector3(sin(_cam_orbit) * r, 17.0, -cos(_cam_orbit) * r), Vector3(0, 1.0, 0), 1.0)
	elif phase == "board" or phase == "intro":
		var cur := int(net.state_get("cur", -1))
		if cur >= 0 and tokens.has(cur):
			var t: TokenScript = tokens[cur]
			var d := 12.5 if String(net.state_get("step", "")) != "overview" else 30.0
			cam_focus(t.position + Vector3(0, 1.0, 0), d, 3.0)
		elif String(net.state_get("step", "")) == "overview" or cur < 0:
			cam_look(Vector3(0, 24, -27), Vector3(0, 0, 1.5), 1.5)
	var k := 1.0 - exp(-_cam_speed * delta)
	_cam_from = _cam_from.lerp(_cam_want_from, k)
	_cam_at = _cam_at.lerp(_cam_want_at, k)
	cam.shot_look(to_world(_cam_from), to_world(_cam_at), 0.0)


# --- Input --------------------------------------------------------------------------------------------

## A TV player's stick as a direction on the board (camera looks from the north: stick up = +Z).
static func tv_dir(mv: Vector2) -> Vector3:
	return Vector3(-mv.x, 0.0, -mv.y)


## Host / local: this frame's input for a human TV pid {move: Vector3 (board), held: bool, pressed: bool}.
func pad_input(pid: int) -> Dictionary:
	var out := {"move": Vector3.ZERO, "held": false, "pressed": false}
	if party.is_local(pid) and not (pid == 0 and vr_rig != null):
		if get_tree().paused or UiMenu.slot_busy(pid):
			return out
		out["move"] = tv_dir(party.stick(pid, "move"))
		out["held"] = party.pressed(pid, "accept")
		out["pressed"] = party.just_pressed(pid, "accept")
	elif party.is_remote(pid) and remote_in.has(pid):
		var r: Array = remote_in[pid]
		out["move"] = tv_dir(r[0])
		out["held"] = bool(r[2])
		var presses := int(r[1])
		out["pressed"] = presses > int(_press_seen.get(pid, presses))
	return out


## Host: count remote presses as seen (call once per frame after reading pad_input).
func consume_presses() -> void:
	for pid in remote_in:
		var r: Array = remote_in[pid]
		_press_seen[pid] = int(r[1])


## Host: the TV machine's sticks and A presses for minigames (sent with send_state, 30 Hz).
func on_remote_state(slot: int, pos: Vector3, _yaw: float, _pitch: float) -> void:
	var presses := int(pos.z) >> 1
	if not remote_in.has(slot):
		_press_seen[slot] = presses
	remote_in[slot] = [Vector2(pos.x, pos.y), presses, (int(pos.z) & 1) == 1]


## TV machine / local: stream sticks to the host and send board actions for the seats here.
func _tv_input(delta: float) -> void:
	_send_t -= delta
	var send := _send_t <= 0.0
	if send:
		_send_t = 1.0 / 30.0
	for slot in party.local_slots():
		if slot == 0 and vr_rig != null:
			continue
		if net.mode == "client":
			if party.just_pressed(slot, "accept"):
				_local_press[slot] = int(_local_press.get(slot, 0)) + 1
			if send:
				var mv := party.stick(slot, "move") if not UiMenu.slot_busy(slot) else Vector2.ZERO
				var held := 1 if party.pressed(slot, "accept") else 0
				net.send_state(Vector3(mv.x, mv.y, float(int(_local_press.get(slot, 0)) * 2 + held)), 0.0, 0.0, slot)
		menus.board_input(slot)


func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if split != null:
		_tv_input(delta)
	_update_camera(delta)
	if net.mode != "client":
		runner.host_tick(delta)
		consume_presses()


# --- Effects (host plays them and sends them to the TV machine) --------------------------------------

## Host: play an effect here and on the TV machine.
func fx(kind: String, args: Array) -> void:
	_do_fx(kind, args)
	net.event(kind, args)


func apply_event(kind: String, args: Array) -> void:
	if ready_to_play:
		_do_fx(kind, args)


func _do_fx(kind: String, args: Array) -> void:
	match kind:
		"banner":
			hud.banner(String(args[0]), String(args[1]), String(args[2]) if args.size() > 2 else "default",
				float(args[3]) if args.size() > 3 else 2.4)
		"toast":
			hud.toast(String(args[0]), int(args[1]) if args.size() > 1 else -1, String(args[2]) if args.size() > 2 else "")
		"sfx":
			sfx.play(String(args[0]), float(args[1]) if args.size() > 1 else 0.0, float(args[2]) if args.size() > 2 else 1.0)
		"coins":
			_coin_fx(int(args[0]), int(args[1]))
		"star_fx":
			_star_fx(int(args[0]), int(args[1]))
		"space_fx":
			board.flash_space(int(args[0]), args[1])
		"anim":
			var pid := int(args[0])
			if tokens.has(pid):
				(tokens[pid] as TokenScript).anim().play(String(args[1]), float(args[2]) if args.size() > 2 else -1.0)
		"shake":
			if cam != null:
				cam.shake(float(args[0]))
		"mg_fx":
			runner.on_fx(String(args[0]), args[1])
		"dice_fx":
			dice.on_fx(String(args[0]), args[1])
		"intro":
			hints.intro(INTRO, {"duration": 9.0, "min_time": 1.0})
		"arrows":
			if args.is_empty():
				board.hide_arrows()
			else:
				board.show_arrows(int(args[0]), args[1], 0)


## Coins popping out of (or into) a token, with a sound.
func _coin_fx(pid: int, delta_coins: int) -> void:
	if not tokens.has(pid) or delta_coins == 0:
		return
	var t: TokenScript = tokens[pid]
	var at := to_world(t.position + Vector3(0, 2.4, 0))
	var size := 1.3 if vr_rig == null else 0.42
	HudKit.popup(self, at, ("+%d" % delta_coins) if delta_coins > 0 else str(delta_coins),
		{"style": "score" if delta_coins > 0 else "bad", "size": size, "rise": 1.2 * S * 1.5 if vr_rig != null else 1.5})
	sfx.play_at("coin" if delta_coins > 0 else "debuff", at, -2.0, 1.0 + randf() * 0.1)
	if delta_coins > 0:
		_burst(t.position + Vector3(0, 1.6, 0), Color(1.0, 0.85, 0.3), mini(14, 4 + delta_coins))
		t.anim().play("cheer", 0.7)
	else:
		t.anim().play("hurt", 0.5)


func _star_fx(pid: int, delta_stars: int) -> void:
	if not tokens.has(pid):
		return
	var t: TokenScript = tokens[pid]
	_burst(t.position + Vector3(0, 2.0, 0), Color(1.0, 0.95, 0.4), 30)
	if delta_stars > 0:
		t.anim().play("victory", 2.5)
		sfx.play("fanfare", -2.0)
	else:
		t.anim().play("hurt", 0.6)
		sfx.play("sad_trombone", -4.0)


## A burst of sparkles (board units).
func _burst(at: Vector3, color: Color, amount: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.8
	p.explosiveness = 1.0
	p.spread = 180.0
	p.direction = Vector3.UP
	p.initial_velocity_min = 3.0 * S
	p.initial_velocity_max = 6.0 * S
	p.gravity = Vector3(0, -9.0 * S, 0)
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.22 * S
	bm.material = MeshKit.material(color, 2.0)
	p.mesh = bm
	add_child(p)
	p.global_position = to_world(at)
	p.emitting = true
	get_tree().create_timer(1.2, false).timeout.connect(p.queue_free)


func burst(at_board: Vector3, color: Color, amount: int = 16) -> void:
	_burst(at_board, color, amount)


## Host / local: the last minigame is over: bonus stars, the winner, the results.
func ceremony_start(records: Dictionary) -> void:
	ceremony.run(records)


# --- Requests (any machine -> host) -------------------------------------------------------------------

func on_request(slot: int, action: String, args: Array) -> void:
	if flow != null:
		flow.on_request(slot, action, args)


func on_client_joined() -> void:
	print("Party Board: the TV machine joined")


func on_client_left() -> void:
	remote_in.clear()


# --- Snapshots ----------------------------------------------------------------------------------------

## Host, 30 Hz: the VR player's pose (board units), the VR dice and the running minigame.
func make_snapshot() -> Array:
	var pose := PackedFloat32Array()
	if vr_rig != null:
		for n: Node3D in [vr_rig.camera, vr_rig.hand_l, vr_rig.hand_r]:
			var t := n.global_transform.orthonormalized()
			var p := to_board(t.origin)
			var q := t.basis.get_rotation_quaternion()
			pose.append_array([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(q.x, 0.001),
				snappedf(q.y, 0.001), snappedf(q.z, 0.001), snappedf(q.w, 0.001)])
	return [pose, dice.snapshot(), runner.snapshot()]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 3:
		return
	if giant != null:
		giant.apply_pose(s[0])
	dice.apply_snapshot(s[1])
	runner.apply_snapshot(s[2])


# --- Pause --------------------------------------------------------------------------------------------

func on_pause_changed(paused: bool, by_slot: int) -> void:
	var who := "the Giant" if by_slot == 0 and has_vr() else party.name_of(by_slot)
	var why := "Paused by %s  -  %s" % [who, "wrist MENU: carry on" if vr_rig != null else "START: menu"]
	if vr_rig != null:
		if paused:
			_pause_vr = HudKit.vr_card(self, vr_rig.camera, "PAUSED", why, {"width": 1.1})
			_pause_vr.process_mode = Node.PROCESS_MODE_ALWAYS
		elif _pause_vr != null and is_instance_valid(_pause_vr):
			_pause_vr.call("hide_card")
	if tv_ui != null:
		if _pause_tv == null:
			var ui := UiKit.ui_root(self, 6)
			ui.process_mode = Node.PROCESS_MODE_ALWAYS
			_pause_tv = UiKit.panel("accent")
			ui.add_child(_pause_tv)
			var v := UiKit.vbox()
			_pause_tv.add_child(v)
			v.add_child(UiKit.title("PAUSED"))
			var l := UiKit.label("", "small", "dim", HORIZONTAL_ALIGNMENT_CENTER)
			l.name = "Why"
			v.add_child(l)
			_pause_tv.set_anchors_preset(Control.PRESET_CENTER)
			_pause_tv.grow_horizontal = Control.GROW_DIRECTION_BOTH
			_pause_tv.grow_vertical = Control.GROW_DIRECTION_BOTH
		(_pause_tv.find_child("Why", true, false) as Label).text = why
		_pause_tv.visible = paused
		if paused:
			UiKit.pop_in(_pause_tv)


func _exit_tree() -> void:
	XRServer.world_scale = 1.0
