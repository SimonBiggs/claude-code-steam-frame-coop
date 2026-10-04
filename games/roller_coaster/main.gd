extends Node3D
## COASTER CREW ("a VR roller coaster"): the VR player BUILDS a coaster with their hands on a tabletop
## theme park; the TV players RIDE it. Build a bit -> push the big green START lever -> the train rides
## round (hold A: hands up, screams, grab the stars) -> cheers and confetti, the park gets a new
## decoration -> build more. No failure state: the track always closes back into the station by itself.
## Practice first: one glowing piece in the tray and a glowing spot where it goes (3 pieces), then the
## lever glows; the first ride is a short practice ride with 3 glowing stars.
## Modes: VR host (+ TV machine), solo VR (bot riders fill the train), local split screen without a
## headset (P1 builds with the pad: the ghost piece at the end of the track shows what A adds), and a
## host without a builder (bots / networked tests) builds a demo track by itself.
## Files: track.gd (pieces -> polyline + baked mesh), park.gd (table, scenery, touch reactions),
## train.gd (cars + riders), builder.gd (the VR hands, tray, lever, opt-in VR ride).

const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const Party := preload("res://core/party.gd")
const SplitView := preload("res://core/split_view.gd")
const VrRig := preload("res://core/vr_rig.gd")
const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Creatures := preload("res://core/creatures.gd")
const SkyKit := preload("res://core/sky_kit.gd")
const Track := preload("res://games/roller_coaster/track.gd")
const ParkScript := preload("res://games/roller_coaster/park.gd")
const TrainScript := preload("res://games/roller_coaster/train.gd")
const BuilderScript := preload("res://games/roller_coaster/builder.gd")

const GAME_ID := "roller_coaster"
const PRACTICE: Array[String] = ["straight", "left", "up"]
const MAX_PIECES := 28
const MIN_CARS := 4
const G := 9.8
const VMIN := 3.0
const VMAX := 15.0
const VMAX_VR := 7.5
const LIFT_V := 3.2
const LAPS := 2
const CHEER_TIME := 4.5
const STAR_REACH := 1.1

# --- The networking contract (see docs/engine/systems.md) ---
var net: Node
var ready_to_play := false
var party: Party
var split: SplitView
var vr_rig: VrRig
var sfx: Node
var music: Node

var park: Node3D
var train: Node3D
var builder: Node3D
var track_mi: MeshInstance3D
var ghost_mi: MeshInstance3D
var pad_ghost: MeshInstance3D
var pad_ghost_type := ""
var track: Dictionary = {}
var pieces: Array = []
var closed := false
var phase := "build"
var practice := 0  # host: pieces placed during the practice (3 = done)
var train_s := 0.0
var train_v := 0.0
var ride_d := 0.0
var ride_len := 0.0
var ride_s0 := 0.0
var energy := 0.0
var cheer_t := 0.0
var rides_done := 0  # host: rides finished (bots)
var hands := {}  # host: slot -> bool
var my_hands := {}  # this machine's local seats: slot -> bool (sent on change)
var hand_bits := 0
var star_nodes := {}  # id -> Node3D
var next_star := 0
var vr_stars: Array = []  # host: distances of the stars the builder placed
var guest_state: Array = []  # host: "walk" / "held" / "fall" / "ride"
var guest_vel: Array = []
var guest_goal: Array = []
var guest_car: Array = []  # host: the car a riding guest was plopped into
var auto_t := 0.0
var pick := 0  # local pad builder: which piece the ghost shows
var cams := {}  # slot -> Camera3D
var huds := {}  # slot -> UiKit root (-1 = shared)
var star_labels := {}
var ride_prompts := {}
var build_prompt: Control
var join_prompt: Control
var tv_banner: Control
var vr_avatar: VrRig.Avatar
var giant: Node3D  # TV: the builder's big head and hands peeking over the table
var cam_t := 0.0
var fx_lift_t := 0.0
var fx_fast := false
var fx_splash := -1
var fx_scream := {}
var send_t := 0.0
var snap_s := 0.0
var snap_ws := 1.0
var bot_hands_t := 0.0
var _rng := RandomNumberGenerator.new()


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
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.add_recipe("clack", {"len": 0.06, "peak": 0.35, "jit": 0.05, "layers": [
		{"w": "noise", "f": 1.0, "len": 0.04, "dec": 70.0, "hp": 1400.0}, {"w": "square", "f": 190.0, "len": 0.03, "dec": 90.0, "vol": 0.6}]})
	sfx.add_recipe("scream", {"len": 1.0, "peak": 0.4, "jit": 0.15, "layers": [
		{"w": "saw", "f": 850.0, "f1": 1250.0, "len": 0.9, "vib": [7.0, 1.5], "atk": 0.05, "rel": 0.45, "lp": 2800.0, "vol": 0.6},
		{"w": "tri", "f": 1300.0, "f1": 1700.0, "len": 0.8, "vib": [6.0, 1.0], "atk": 0.08, "rel": 0.4, "vol": 0.4}]})
	sfx.add_recipe("wee", {"len": 0.7, "peak": 0.4, "jit": 0.1, "layers": [
		{"w": "tri", "f": 520.0, "f1": 1150.0, "len": 0.6, "vib": [8.0, 0.8], "atk": 0.03, "rel": 0.2}]})
	sfx.add_recipe("snap", {"len": 0.18, "peak": 0.55, "jit": 0.03, "layers": [
		{"w": "noise", "f": 1.0, "len": 0.05, "dec": 60.0, "hp": 900.0}, {"w": "square", "f": 520.0, "f1": 780.0, "len": 0.12, "dec": 25.0, "vol": 0.5}]})
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("town")
	_rng.randomize()
	if OS.has_environment("DUO_JOIN"):
		net.join_finished.connect(func(ok: bool) -> void: _setup("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if VrRig.headset_available() or OS.has_environment("DUO_HOST"):
			net.host()
		_setup(net.mode)


func _setup(mode: String) -> void:
	_build_world(VrRig.wanted(mode))
	if VrRig.wanted(mode):
		vr_rig = VrRig.new()
		add_child(vr_rig)
		builder = BuilderScript.new()
		builder.name = "Builder"
		add_child(builder)
		builder.setup(self, vr_rig)
	if mode != "host":
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		var shared := split.shared_camera()
		shared.position = Vector3(0, 13, 19)
		shared.look_at(Vector3(0, 0, 0))
		_make_hud(-1, split.shared_hud())
		if mode == "client":
			vr_avatar = VrRig.Avatar.new()
			add_child(vr_avatar)
			vr_avatar.visible = false
			split.set_bubble(VrRig.build_mirror(self, vr_avatar.head, false))
			_build_giant()
		elif vr_rig != null:
			split.set_bubble(vr_rig.mirror)
	party.allow_slot0 = mode == "local" and vr_rig == null
	if mode != "client":
		net.state_set("track", [])
		net.state_set("closed", false)
		net.state_set("practice", 0)
		net.state_set("decor", 0)
		net.state_set("score", 0)
		net.state_set("stars", [])
		net.state_set("vr_ride", false)
		_set_phase("build")
		_refresh_cars()
	_rebuild_track()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Coaster Crew: %s mode%s" % [mode, " with a VR builder" if vr_rig != null else ""])


# --- World --------------------------------------------------------------------------------

func _build_world(vr: bool) -> void:
	SkyKit.apply(self, "day", vr)
	# The living room the table stands in (far below, for the riders' and the giant's views).
	var floor_y := -BuilderScript.TABLE_H * BuilderScript.WS
	var b := MeshKit.builder()
	b.cylinder(140.0, 140.0, 0.5, Transform3D(Basis(), Vector3(0, floor_y - 0.25, 0)), Color(0.55, 0.42, 0.5), 32)
	b.cylinder(50.0, 50.0, 0.3, Transform3D(Basis(), Vector3(0, floor_y + 0.05, 0)), Color(0.85, 0.75, 0.55), 32)
	b.cylinder(1.6, 2.2, -floor_y - 0.7, Transform3D(Basis(), Vector3(0, floor_y * 0.5 - 0.35, 0)), Color(0.55, 0.36, 0.22), 12)
	var room := MeshKit.instance(b.build(), false)
	room.name = "Room"
	add_child(room)
	park = ParkScript.new()
	park.name = "Park"
	add_child(park)
	track_mi = MeshInstance3D.new()
	track_mi.name = "TrackMesh"
	track_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	park.add_child(track_mi)
	ghost_mi = MeshInstance3D.new()
	ghost_mi.name = "TrackGhost"
	ghost_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	park.add_child(ghost_mi)
	train = TrainScript.new()
	train.name = "Train"
	park.add_child(train)
	for i in park.guests.size():
		guest_state.append("walk")
		guest_vel.append(Vector3.ZERO)
		guest_goal.append(park.guests[i].position)
		guest_car.append(-1)


## TV machine: the builder's big friendly head and mittens above the table.
func _build_giant() -> void:
	giant = Node3D.new()
	add_child(giant)
	var hb := MeshKit.builder()
	hb.sphere(0.12, Transform3D(), Color(1.0, 0.82, 0.68), 14)
	hb.sphere(0.022, Transform3D(Basis(), Vector3(-0.045, 0.02, -0.105)), Color(0.1, 0.1, 0.15), 8)
	hb.sphere(0.022, Transform3D(Basis(), Vector3(0.045, 0.02, -0.105)), Color(0.1, 0.1, 0.15), 8)
	hb.ellipsoid(Vector3(0.03, 0.012, 0.01), Transform3D(Basis(), Vector3(0, -0.045, -0.11)), Color(0.85, 0.3, 0.35), 8)
	hb.dome(0.125, Transform3D(Basis(), Vector3(0, 0.03, 0.01)), Color(0.45, 0.3, 0.2), 14)
	var head := MeshKit.instance(hb.build(), false)
	head.name = "Head"
	giant.add_child(head)
	for i in 2:
		var gb := MeshKit.builder()
		gb.ellipsoid(Vector3(0.05, 0.035, 0.07), Transform3D(), Color(1.0, 0.86, 0.6), 10)
		var h := MeshKit.instance(gb.build(), false)
		h.name = "Hand%d" % i
		giant.add_child(h)


# --- Track ----------------------------------------------------------------------------------

func _rebuild_track() -> void:
	track = Track.build(pieces)
	var meshes := Track.bake(track, closed)
	track_mi.mesh = meshes[0]
	ghost_mi.mesh = meshes[1]
	if phase != "ride":
		train_s = _station_s()
		train.place(track, train_s)
	_place_stars()


func _station_s() -> float:
	return Track.STATION_LEN - 0.4


## The piece the practice wants next ("" when the practice is over).
func practice_piece() -> String:
	var p := int(net.state_get("practice", 0))
	return PRACTICE[p] if p < PRACTICE.size() else ""


func lever_glows() -> bool:
	return phase == "build" and (int(net.state_get("practice", 0)) == PRACTICE.size() or (practice_piece() == "" and pieces.size() > 0))


func can_add(t: String) -> bool:
	if phase != "build" or pieces.size() >= MAX_PIECES:
		return false
	var want := practice_piece()
	if want != "" and t != want:
		return false
	var end: Array = track.get("end", [Track.station_end(), 0.0])
	return Track.fits(t, 0.0, end[0], float(end[1]))


## Host / local: snap a piece onto the end of the track (VR hands, the pad builder, the bots).
func add_piece(t: String) -> bool:
	if net.mode == "client" or not can_add(t):
		if net.mode != "client":
			sound("ui_error", -8.0)
		return false
	pieces.append([t, 0.0])
	closed = false
	if practice < PRACTICE.size():
		practice += 1
		net.state_set("practice", practice)
	_store_track()
	var end: Array = track["end"]
	_click_fx(end[0])
	net.event("click", [end[0]])
	return true


func undo_piece() -> void:
	if net.mode == "client" or phase != "build" or pieces.is_empty():
		return
	if practice < PRACTICE.size():
		practice = maxi(0, practice - 1)
		net.state_set("practice", practice)
	pieces.pop_back()
	closed = false
	_store_track()
	sound("pop", -4.0, 0.8)


func last_height() -> float:
	return float((pieces.back() as Array)[1]) if not pieces.is_empty() else 0.0


## Pull the end of the track up or down (the last piece's extra height).
func set_end_height(h: float) -> void:
	if net.mode == "client" or phase != "build" or pieces.is_empty():
		return
	(pieces.back() as Array)[1] = clampf(h, -3.0, 4.0)
	_store_track()
	sound("clack", -2.0, 1.0 + h * 0.08)


func close_loop() -> void:
	if net.mode == "client" or closed:
		return
	closed = true
	_store_track()
	sound("sparkle", -2.0)
	net.event("sound", ["sparkle"])


func _store_track() -> void:
	net.state_set("track", pieces.duplicate(true))
	net.state_set("closed", closed)
	_rebuild_track()


func turn_table(d: float) -> void:
	park.rotation.y = wrapf(park.rotation.y + d, -PI, PI)


func set_vr_ride(on: bool) -> void:
	net.state_set("vr_ride", on)


func pull_lever() -> void:
	if net.mode == "client" or phase != "build":
		return
	var p := int(net.state_get("practice", 0))
	if p < PRACTICE.size():
		sound("ui_error", -10.0)
		return
	_start_ride()


## Drop a star near the track: it waits there for the riders (true when it found the track).
func place_star_at(local: Vector3) -> bool:
	var best := -1.0
	var bd := 3.0
	var pts: PackedVector3Array = track["pts"]
	var dist: PackedFloat32Array = track["dist"]
	for i in pts.size():
		var d := (pts[i] + Vector3.UP * 1.6).distance_to(local)
		if d < bd and dist[i] > Track.STATION_LEN:
			bd = d
			best = dist[i]
	if best < 0.0 or vr_stars.size() >= 12:
		sound("ui_error", -10.0)
		return false
	vr_stars.append(best)
	_publish_stars(vr_stars.map(func(s: float) -> Array: return [_new_star_id(), s, "star"]))
	sound("sparkle", -3.0, 1.3)
	return true


func _new_star_id() -> int:
	next_star += 1
	return next_star


func _publish_stars(list: Array) -> void:
	net.state_set("stars", list)
	_sync_stars(list)


# --- Phases -----------------------------------------------------------------------------------

func _set_phase(p: String) -> void:
	phase = p
	net.state_set("phase", p)


func _start_ride() -> void:
	if not closed:
		closed = true
		_store_track()
	var practice_ride := rides_done == 0 and practice >= PRACTICE.size() and not bool(net.state_get("practiced", false))
	net.state_set("practiced", true)
	var list: Array = []
	var length: float = track["length"]
	if practice_ride:
		for f in [0.35, 0.55, 0.78]:
			list.append([_new_star_id(), length * f, "star"])
	else:
		for k in 4:
			list.append([_new_star_id(), length * _rng.randf_range(0.25, 0.92), "balloon" if k % 2 == 1 else "star"])
		for s in vr_stars:
			list.append([_new_star_id(), float(s), "star"])
	vr_stars.clear()
	_publish_stars(list)
	ride_s0 = _station_s()
	ride_d = 0.0
	ride_len = length * (1 if practice_ride else LAPS)
	train_s = ride_s0
	train_v = 5.0
	energy = 0.5 * train_v * train_v + G * Track.STATION_Y
	_set_phase("ride")
	sound("go", -2.0)
	net.event("sound", ["go"])
	if builder != null and bool(net.state_get("vr_ride", false)):
		builder.start_ride()


func _end_ride() -> void:
	rides_done += 1
	net.state_set("rides", rides_done)
	_set_phase("cheer")
	cheer_t = CHEER_TIME
	_publish_stars([])
	var decor := int(net.state_get("decor", 0)) + 1
	net.state_set("decor", decor)
	# Guests hop out at the station and wander off again.
	for g in guest_state.size():
		if guest_state[g] == "ride":
			guest_state[g] = "walk"
			var gn: Node3D = park.guests[g]
			gn.visible = true
			gn.position = Track.station_start() + Vector3(1.0 + g * 0.6, -Track.STATION_Y, 1.4)
	_refresh_cars()


# --- Game loop --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	cam_t += delta
	_local_input(delta)
	if net.mode != "client":
		_simulate(delta)
	else:
		snap_s += train_v * delta
		train_s = lerpf(train_s + train_v * delta, snap_s, 0.2) if phase == "ride" else snap_s
		if phase == "ride":
			train.place(track, train_s)
	train.set_hands(hand_bits, delta)
	_effects(delta)
	_spin_stars(delta)
	_update_cameras(delta)
	_update_giant()
	_animate_guests(delta)


func _simulate(delta: float) -> void:
	if builder != null:
		builder.tick(delta)
	_guests(delta)
	_bot_hands(delta)
	match phase:
		"build":
			if not _has_builder():
				_auto_build(delta)
		"ride":
			_ride(delta)
		"cheer":
			cheer_t -= delta
			if cheer_t <= 0.0:
				_set_phase("build")


func _has_builder() -> bool:
	return vr_rig != null or (net.mode == "local" and party.is_active(0))


## Nobody to build (a host without a headset, or nobody on P1's pad yet): build a demo coaster.
func _auto_build(delta: float) -> void:
	auto_t += delta
	if auto_t < (6.0 if pieces.is_empty() else 1.0):  # give P1 a moment to pick up a pad
		return
	auto_t = 0.0
	var want := practice_piece()
	if want != "":
		add_piece(want)
		return
	if pieces.size() < 7 + rides_done % 3:
		var order: Array[String] = ["down", "straight", "right", "up", "loop", "down", "splash", "left", "straight", "right"]
		for k in order.size():
			var t := order[(pieces.size() + k) % order.size()]
			if can_add(t):
				add_piece(t)
				return
	pull_lever()


func _ride(delta: float) -> void:
	var xf := Track.sample(track, train_s - TrainScript.GAP)
	var y := xf.origin.y
	var slope := -xf.basis.z.y
	var v := sqrt(maxf(0.0, 2.0 * (energy - G * y)))
	var vmax := VMAX_VR if (builder != null and builder.riding) else VMAX
	if slope > 0.08 and v < LIFT_V:
		v = LIFT_V  # the chain lift: clickety-clack
	v = clampf(v, VMIN, vmax)
	var remaining := ride_len - ride_d
	if remaining < 9.0:
		v = minf(v, maxf(0.8, remaining * 0.8))
	energy = 0.5 * v * v + G * y - 0.15 * delta
	train_v = v
	ride_d += v * delta
	train_s = ride_s0 + ride_d
	train.place(track, train_s)
	_collect_stars()
	if ride_d >= ride_len - 0.05:
		train_s = ride_s0 + ride_len
		train_v = 0.0
		_end_ride()


## Hands up near a star (it hovers above the track): grab it.
func _collect_stars() -> void:
	var list: Array = net.state_get("stars", [])
	if list.is_empty():
		return
	var length: float = track["length"]
	var cars: Array = net.state_get("cars", [])
	var left: Array = []
	var got := false
	for st in list:
		var a: Array = st
		var taken := -1
		for i in cars.size():
			if (hand_bits >> i) & 1 == 0:
				continue
			var ds := absf(wrapf(train.car_s(train_s, i) - float(a[1]), -length * 0.5, length * 0.5))
			if ds < STAR_REACH:
				taken = i
				break
		if taken >= 0:
			got = true
			var pos := _star_pos(float(a[1]))
			_got_fx(pos, taken)
			net.event("got", [pos, taken])
			net.state_set("score", int(net.state_get("score", 0)) + 1)
		else:
			left.append(a)
	if got:
		_publish_stars(left)


func _star_pos(s: float) -> Vector3:
	var xf := Track.sample(track, s)
	return xf.origin + xf.basis.y * 1.9


# --- Riders' hands ----------------------------------------------------------------------------

func _local_input(delta: float) -> void:
	send_t -= delta
	for slot in party.local_slots():
		var up := party.pressed(slot, "accept")
		if slot == 0 and net.mode == "local" and vr_rig == null and phase == "build":
			_pad_builder(slot)
			up = false
		if bool(my_hands.get(slot, false)) != up:
			my_hands[slot] = up
			net.request(slot, "hands", [up])
	if net.mode == "local" or vr_rig == null:
		_pad_ghost_update()


func on_request(slot: int, action: String, args: Array) -> void:
	match action:
		"hands":
			var up := bool(args[0]) if args.size() > 0 else false
			if up and not bool(hands.get(slot, false)) and phase == "ride" and train_v > 7.0:
				sound("scream", -6.0, 0.9 + 0.05 * slot)
			hands[slot] = up


## Bot riders (and the VR player's car when they're not in it) put their hands up on the fast bits
## and when a star is coming, so a solo builder still sees stars get grabbed.
func _bot_hands(delta: float) -> void:
	var cars: Array = net.state_get("cars", [])
	var bits := 0
	var length: float = track.get("length", 1.0)
	var list: Array = net.state_get("stars", [])
	bot_hands_t += delta
	for i in cars.size():
		var code := int(cars[i])
		var up := false
		if code >= 0 and party.is_active(code) and not (code == 0 and vr_rig != null):
			up = bool(hands.get(code, false))
		elif code == 0 and builder != null and builder.riding:
			var hy := minf(vr_rig.hand_l.global_position.y, vr_rig.hand_r.global_position.y)
			up = hy > vr_rig.camera.global_position.y
		elif phase == "ride":
			up = train_v > 10.0 or fmod(bot_hands_t + i * 1.7, 7.0) < 1.2
			if not up and _humans_riding() == 0:
				for st in list:
					var ds := wrapf(float((st as Array)[1]) - train.car_s(train_s, i), -length * 0.5, length * 0.5)
					if ds > -1.0 and ds < 4.0:
						up = true
		if up:
			bits |= 1 << i
	hand_bits = bits


func _humans_riding() -> int:
	var n := 0
	for slot in party.active_slots():
		if slot > 0 or vr_rig == null:
			n += 1
	return n


# --- Cars ------------------------------------------------------------------------------------

## Host: who sits in which car. Car 0 is P1's (the builder's own car), then every TV player, then bot
## riders / plopped-in guests so there are always a few cars.
func _refresh_cars() -> void:
	if net.mode == "client":
		return
	var occ: Array = []
	occ.append(0 if (vr_rig != null or party.is_active(0)) else -1)
	for slot in party.active_slots():
		if slot > 0:
			occ.append(slot)
	var n := maxi(MIN_CARS, occ.size() + 2)  # always a couple of bot riders (seats for guests too)
	while occ.size() < n:
		occ.append(-1)
	for g in guest_state.size():
		if guest_state[g] == "ride":
			var want: int = guest_car[g]
			if want >= 0 and want < occ.size() and int(occ[want]) == -1:
				occ[want] = -2 - g
				continue
			var put := false
			for i in occ.size():
				if int(occ[i]) == -1:
					occ[i] = -2 - g
					guest_car[g] = i
					put = true
					break
			if not put:
				guest_state[g] = "walk"
				(park.guests[g] as Node3D).visible = true
	net.state_set("cars", occ)
	train.set_cars(occ)
	train.place(track, train_s)


func _on_player_joined(slot: int, _device: int) -> void:
	if party.is_local(slot) and split != null:
		cams[slot] = split.camera(slot)
		_make_hud(slot, split.hud(slot))
	_refresh_cars()
	sound("ui_notify", -6.0)


func _on_player_left(slot: int) -> void:
	cams.erase(slot)
	if huds.has(slot):
		var h: Control = huds[slot]
		if is_instance_valid(h):
			h.queue_free()
		huds.erase(slot)
	star_labels.erase(slot)
	ride_prompts.erase(slot)
	hands.erase(slot)
	my_hands.erase(slot)
	_refresh_cars()


# --- Guests -------------------------------------------------------------------------------------

func nearest_guest(world_pos: Vector3, r: float) -> int:
	var best := -1
	var bd := r
	for g in park.guests.size():
		if guest_state[g] == "ride":
			continue
		var gn: Node3D = park.guests[g]
		var d := park.to_global(gn.position + Vector3.UP * 0.6).distance_to(world_pos)
		if d < bd:
			bd = d
			best = g
	return best


func hold_guest(g: int, world_pos: Vector3) -> void:
	if guest_state[g] != "held":
		guest_state[g] = "held"
		sound("wee", -4.0, 1.2)
		Creatures.anim(park.guests[g]).play("cheer", 1.0)
	(park.guests[g] as Node3D).position = park.to_local(world_pos) - Vector3.UP * 0.9


## Let go of a guest: over a car in the station, they hop in (WHEE); anywhere else they float down.
func drop_guest(g: int, world_vel: Vector3) -> void:
	var gn: Node3D = park.guests[g]
	if phase != "ride":
		for i in train.cars.size():
			var c: Node3D = train.cars[i]
			if c.position.distance_to(gn.position + Vector3.UP * 0.5) < 1.8:
				var cars: Array = net.state_get("cars", [])
				if i < cars.size() and int(cars[i]) == -1:
					guest_state[g] = "ride"
					guest_car[g] = i
					gn.visible = false
					_refresh_cars()
					sound("wee", 0.0, 1.4)
					net.event("sound", ["wee"])
					return
	guest_state[g] = "fall"
	guest_vel[g] = (park.global_basis.inverse() * world_vel).limit_length(8.0)
	sound("wee", -2.0, 1.0)


func _guests(delta: float) -> void:
	for g in park.guests.size():
		var gn: Node3D = park.guests[g]
		match String(guest_state[g]):
			"walk":
				var goal: Vector3 = guest_goal[g]
				var to := goal - gn.position
				to.y = 0.0
				if to.length() < 0.3 or _rng.randf() < 0.002:
					var a := _rng.randf() * TAU
					var r := _rng.randf_range(1.0, 9.5)
					guest_goal[g] = Vector3(cos(a) * r, 0.0, sin(a) * r)
				else:
					gn.position += to.normalized() * 0.9 * delta
					gn.position.y = 0.0
			"fall":
				var v: Vector3 = guest_vel[g]
				v.y -= G * 0.6 * delta
				v *= 0.995
				gn.position += v * delta
				guest_vel[g] = v
				var flat := Vector2(gn.position.x, gn.position.z)
				if flat.length() > Track.TABLE_R - 0.5:
					flat = flat.normalized() * (Track.TABLE_R - 0.5)
					gn.position.x = flat.x
					gn.position.z = flat.y
				if gn.position.y <= 0.0:
					gn.position.y = 0.0
					guest_state[g] = "walk"
					guest_goal[g] = gn.position
					Creatures.anim(gn).play("jump")
					park.poke("guest", g, Vector3.ZERO, sfx)


## Every machine: walking legs from how far each guest moved.
var _guest_prev: Array = []


func _animate_guests(delta: float) -> void:
	if _guest_prev.size() != park.guests.size():
		_guest_prev.clear()
		for gn in park.guests:
			_guest_prev.append((gn as Node3D).position)
	for g in park.guests.size():
		var gn: Node3D = park.guests[g]
		var d: Vector3 = gn.position - (_guest_prev[g] as Vector3)
		d.y = 0.0
		var sp := d.length() / maxf(delta, 0.001)
		var an := Creatures.anim(gn)
		an.walk(sp if sp > 0.2 and sp < 5.0 else 0.0)
		if sp > 0.2 and sp < 5.0:
			an.face(d)
		_guest_prev[g] = gn.position


# --- Touches (host: the VR hands) ---------------------------------------------------------------

var _touch_cool := {}


func vr_touch(h: int, hp: Vector3) -> void:
	for k in _touch_cool.keys():
		if Time.get_ticks_msec() > int(_touch_cool[k]):
			_touch_cool.erase(k)
	var local := park.to_local(hp)
	var vel := park.global_basis.inverse() * vr_rig.hand_velocity(h)
	for tp in park.touch_points():
		var a: Array = tp
		if (a[0] as Vector3).distance_to(local) < float(a[1]):
			_poke(String(a[2]), int(a[3]), vel, h)
	for g in park.guests.size():
		if guest_state[g] == "walk" and (park.guests[g] as Node3D).position.distance_to(local - Vector3.UP * 0.5) < 0.8:
			_poke("guest", g, vel, h)
	if phase != "ride":
		for i in train.cars.size():
			if (train.cars[i] as Node3D).position.distance_to(local) < 0.9:
				_poke("car", i, vel, h)


func _poke(kind: String, idx: int, vel: Vector3, h: int) -> void:
	var key := "%s%d" % [kind, idx]
	if _touch_cool.has(key):
		_touch_cool[key] = Time.get_ticks_msec() + 500
		return
	_touch_cool[key] = Time.get_ticks_msec() + 500
	poke_fx(kind, idx, vel)
	net.event("poke", [kind, idx, vel])
	if vr_rig != null:
		vr_rig.pulse(h, 0.35, 0.05)


func poke_fx(kind: String, idx: int, vel: Vector3) -> void:
	if kind == "car":
		if idx < train.cars.size():
			sfx.play_at("honk", (train.cars[idx] as Node3D).global_position, -2.0, 1.0 + idx * 0.08)
			var c: Node3D = train.cars[idx]
			var tw := create_tween()
			tw.tween_property(c, "scale", Vector3(1.15, 0.85, 1.15), 0.08)
			tw.tween_property(c, "scale", Vector3.ONE, 0.2)
		return
	park.poke(kind, idx, vel, sfx)


# --- Effects (every machine, from the train's distance and speed) -------------------------------

func _effects(delta: float) -> void:
	if phase != "ride" or track.is_empty():
		fx_fast = false
		return
	var xf := Track.sample(track, train_s - TrainScript.GAP)
	var slope := -xf.basis.z.y
	if slope > 0.08 and train_v < LIFT_V + 0.3:
		fx_lift_t -= delta
		if fx_lift_t <= 0.0:
			fx_lift_t = 0.16
			sfx.play_at("clack", park.to_global(xf.origin), -3.0, 1.0)
	var fast := train_v > 10.0
	if fast and not fx_fast:
		sfx.play_at("whoosh", park.to_global(xf.origin), 0.0, 0.8)
	fx_fast = fast
	for i in train.cars.size():
		if (hand_bits >> i) & 1 == 1 and train_v > 8.0:
			var t: float = fx_scream.get(i, 0.0)
			if t <= 0.0:
				fx_scream[i] = 1.6 + _rng.randf()
				sfx.play_at("scream", (train.cars[i] as Node3D).global_position, -6.0, _rng.randf_range(0.85, 1.25))
			else:
				fx_scream[i] = t - delta
	var length: float = track["length"]
	var sp := -1
	var splashes: Array = track.get("splashes", [])
	for k in splashes.size():
		var r: Array = splashes[k]
		var s := fposmod(train_s, length)
		if s >= float(r[0]) and s <= float(r[1]):
			sp = k
	if sp >= 0 and sp != fx_splash:
		var r: Array = splashes[sp]
		var pos := Track.sample(track, float(r[1])).origin
		_burst(pos, Color(0.6, 0.85, 1.0), 30, 6.0)
		sfx.play_at("splash", park.to_global(pos), 2.0, 0.9)
	fx_splash = sp


func _click_fx(pos: Vector3) -> void:
	sfx.play_at("snap", park.to_global(pos), 0.0, 1.0)
	_burst(pos + Vector3.UP * 0.8, Color(1.0, 0.9, 0.4), 12, 3.0)


func _got_fx(pos: Vector3, car: int) -> void:
	_burst(pos, Color(1.0, 0.9, 0.3), 16, 4.0)
	sfx.play_at("coin", park.to_global(pos), 0.0, 1.0 + randf() * 0.15)
	var slot := _car_slot(car)
	if slot >= 0 and star_labels.has(slot) and is_instance_valid(star_labels[slot]):
		UiKit.pulse(star_labels[slot] as Control)


func _car_slot(car: int) -> int:
	var cars: Array = net.state_get("cars", [])
	return int(cars[car]) if car < cars.size() else -1


## Confetti / sparkle burst in park-local space.
func _burst(pos: Vector3, color: Color, amount: int, speed: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 1.0
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector3(0, -6.0, 0)
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.16
	bm.material = MeshKit.material(color, 1.5)
	p.mesh = bm
	park.add_child(p)
	p.position = pos
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func _confetti() -> void:
	var at := (Track.station_start() + Track.station_end()) * 0.5 + Vector3.UP * 2.5
	for c in [Color(1, 0.35, 0.4), Color(1, 0.85, 0.3), Color(0.4, 0.75, 1.0), Color(0.5, 0.95, 0.5)]:
		_burst(at, c, 18, 7.0)
	sfx.play("applause", -4.0)
	sfx.play("party_horn", -2.0)


# --- Stars --------------------------------------------------------------------------------------

func _sync_stars(list: Array) -> void:
	var seen := {}
	for st in list:
		var a: Array = st
		var id := int(a[0])
		seen[id] = true
		if not star_nodes.has(id):
			var n := Node3D.new()
			var mi: MeshInstance3D
			if String(a[2]) == "balloon":
				var b := MeshKit.builder()
				b.ellipsoid(Vector3(0.35, 0.42, 0.35), Transform3D(), [Color(1, 0.35, 0.4), Color(0.4, 0.75, 1), Color(0.6, 0.95, 0.4)][id % 3], 10)
				b.cylinder(0.015, 0.015, 0.8, Transform3D(Basis(), Vector3(0, -0.8, 0)), Color.WHITE, 3)
				mi = MeshKit.instance(b.build(), false)
			else:
				mi = MeshKit.instance(MeshKit.prop("star"), false)
				mi.material_override = MeshKit.glow_material()
				mi.scale = Vector3.ONE * 1.4
				mi.position.y = -0.4
			n.add_child(mi)
			park.add_child(n)
			n.set_meta("s", float(a[1]))
			star_nodes[id] = n
	for id in star_nodes.keys():
		if not seen.has(id):
			(star_nodes[id] as Node).queue_free()
			star_nodes.erase(id)
	_place_stars()


func _place_stars() -> void:
	if track.is_empty():
		return
	for id in star_nodes:
		var n: Node3D = star_nodes[id]
		n.position = _star_pos(float(n.get_meta("s")))


func _spin_stars(delta: float) -> void:
	for id in star_nodes:
		var n: Node3D = star_nodes[id]
		n.rotation.y += delta * 2.5
		n.scale = Vector3.ONE * (1.0 + 0.12 * sin(cam_t * 6.0 + int(id)))


# --- The pad builder (local play without a headset) --------------------------------------------

func _pad_builder(slot: int) -> void:
	var step := party.nav(slot)
	var want := practice_piece()
	if want != "":
		pick = Track.TYPES.find(want)
	elif step.x != 0:
		pick = posmod(pick + step.x, Track.TYPES.size())
		sound("ui_move", -6.0)
	if step.y != 0 and not pieces.is_empty():
		set_end_height(last_height() - step.y * 0.5)
	if party.just_pressed(slot, "accept"):
		add_piece(Track.TYPES[pick])
	if party.just_pressed(slot, "back"):
		undo_piece()
	if party.just_pressed(slot, "x"):
		close_loop()
	if party.just_pressed(slot, "y") or party.just_pressed(slot, "rt"):
		pull_lever()


func _pad_ghost_update() -> void:
	var show: bool = net.mode == "local" and vr_rig == null and party.is_active(0) and phase == "build"
	if pad_ghost == null:
		if not show:
			return
		pad_ghost = MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pad_ghost.material_override = m
		park.add_child(pad_ghost)
	pad_ghost.visible = show
	if not show:
		return
	var t := Track.TYPES[pick]
	if t != pad_ghost_type:
		pad_ghost_type = t
		pad_ghost.mesh = Track.piece_mesh(t, 0.0, Color.WHITE)
	var end: Array = track.get("end", [Track.station_end(), 0.0])
	var ep: Vector3 = end[0]
	pad_ghost.transform = Transform3D(Basis(Vector3.UP, float(end[1])), ep - Vector3.UP)
	var ok := can_add(t)
	(pad_ghost.material_override as StandardMaterial3D).albedo_color = (Color(0.5, 1.0, 0.65) if ok else Color(1.0, 0.55, 0.3)) * Color(1, 1, 1, 0.35 + 0.25 * absf(sin(cam_t * 5.0)))


# --- TV cameras and HUD -------------------------------------------------------------------------

func _update_cameras(delta: float) -> void:
	if split == null:
		return
	var k := 1.0 - exp(-5.0 * delta)
	for slot in cams:
		var cam: Camera3D = cams[slot]
		if not is_instance_valid(cam):
			continue
		var car := _car_of(slot)
		var target: Transform3D
		if phase == "ride" and car >= 0 and car < train.cars.size():
			var cx: Transform3D = (train.cars[car] as Node3D).global_transform
			var pos := cx.origin + cx.basis.z * 3.4 + cx.basis.y * 1.5
			target = Transform3D(Basis.looking_at(cx.origin - cx.basis.z * 3.0 + cx.basis.y * 0.6 - pos, cx.basis.y.lerp(Vector3.UP, 0.4).normalized()), pos)
			k = 1.0 - exp(-9.0 * delta)
		elif slot == 0 and net.mode == "local" and vr_rig == null:
			var end: Array = track.get("end", [Track.station_end(), 0.0])
			var focus := park.to_global((end[0] as Vector3) * 0.5)
			var pos := focus + Vector3(0, 13.0, 13.0)
			target = Transform3D(Basis.looking_at(focus - pos, Vector3.UP), pos)
		else:
			var a: float = cam_t * 0.12 + slot * 0.9
			var pos := Vector3(sin(a) * 15.0, 9.0, cos(a) * 15.0)
			target = Transform3D(Basis.looking_at(-pos + Vector3(0, 1.0, 0), Vector3.UP), pos)
		cam.global_transform = cam.global_transform.interpolate_with(target, k)


func _car_of(slot: int) -> int:
	var cars: Array = net.state_get("cars", [])
	return cars.find(slot)


func _update_giant() -> void:
	if giant == null or vr_avatar == null:
		return
	var ws := snap_ws
	var parts: Array = [vr_avatar.head]
	for h in vr_avatar.hands:
		parts.append(h)
	for i in 3:
		var n: Node3D = parts[i] if i < parts.size() else null
		var m: Node3D = giant.get_child(i)
		if n == null:
			continue
		m.global_transform = Transform3D(n.global_basis.orthonormalized().scaled(Vector3.ONE * ws), n.global_position)
	giant.visible = phase != "ride" or ws > 2.0


func _make_hud(slot: int, parent: Control) -> void:
	var ui := UiKit.ui_root(parent)
	huds[slot] = ui
	var card := UiKit.panel("card")
	ui.add_child(card)
	card.position = Vector2(24.0, 20.0)
	var row := UiKit.hbox()
	card.add_child(row)
	if slot >= 0:
		row.add_child(UiKit.badge(party.name_of(slot), slot))
	row.add_child(UiKit.icon("star", "gold", 34.0))
	var l := UiKit.label(str(int(net.state_get("score", 0))), "number")
	row.add_child(l)
	star_labels[slot] = l
	var pill := UiKit.panel("pill")
	ui.add_child(pill)
	pill.add_child(UiKit.prompts([["A", "Hands up!"]]) if slot != 0 or vr_rig != null or net.mode == "client" else UiKit.prompts([["A", "Add"], ["B", "Undo"], ["Y", "Ride!"]]))
	pill.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pill.offset_top = -40.0
	pill.offset_bottom = -40.0
	ride_prompts[slot] = pill
	if slot < 0:
		join_prompt = UiKit.panel("pill")
		join_prompt.add_child(UiKit.prompts([["A", "Join"]]))
		ui.add_child(join_prompt)
		join_prompt.set_anchors_preset(Control.PRESET_CENTER_TOP)
		join_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
		join_prompt.offset_top = 30.0
		pill.visible = false
	_refresh_hud()


func _refresh_hud() -> void:
	var score := int(net.state_get("score", 0))
	for slot in star_labels:
		var l: Label = star_labels[slot]
		if is_instance_valid(l):
			l.text = str(score)
	for slot in ride_prompts:
		var p: Control = ride_prompts[slot]
		if not is_instance_valid(p) or int(slot) < 0:
			continue
		var builder_pad: bool = int(slot) == 0 and net.mode == "local" and vr_rig == null
		p.visible = (phase == "build") if builder_pad else (phase == "ride")
	if join_prompt != null:
		join_prompt.visible = party.local_slots().is_empty()


func _all_huds() -> Array:
	var out: Array = []
	for k in huds:
		if is_instance_valid(huds[k]):
			out.append(huds[k])
	return out


func sound(n: String, db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play(n, db, pitch)


# --- Replicated state --------------------------------------------------------------------------

func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"track", "closed":
			if net.mode == "client":
				pieces = (net.state_get("track", []) as Array).duplicate(true)
				closed = bool(net.state_get("closed", false))
				_rebuild_track()
		"phase":
			var was := phase
			phase = String(value)
			_refresh_hud()
			if phase == "ride":
				music.play_mood("race")
				if not _all_huds().is_empty():
					HudKit.banner(_all_huds(), "RIDE!", "", {"duration": 1.6})
			elif phase == "cheer":
				music.play_mood("victory")
				_confetti()
				train_v = 0.0
			elif phase == "build":
				music.play_mood("town")
				if was == "cheer":
					train_s = _station_s()
					snap_s = train_s
					train.place(track, train_s)
		"cars":
			if net.mode == "client":
				train.set_cars(value as Array)
				train.place(track, train_s)
		"stars":
			if net.mode == "client":
				_sync_stars(value as Array)
		"score":
			_refresh_hud()
		"decor":
			park.set_decor(int(value), true)
			if int(value) > 0:
				sfx.play("achievement", -4.0)


func on_pause_changed(paused: bool, _by_slot: int) -> void:
	if builder != null:
		if paused:
			builder.process_mode = Node.PROCESS_MODE_ALWAYS
			builder.show_headline("PAUSED")
			builder.headline_t = 9999.0
		else:
			builder.headline_t = 0.0
			builder.process_mode = Node.PROCESS_MODE_INHERIT
	if split != null:
		if tv_banner == null:
			var ui := UiKit.ui_root(self, 6)
			ui.process_mode = Node.PROCESS_MODE_ALWAYS
			tv_banner = UiKit.panel("accent")
			ui.add_child(tv_banner)
			tv_banner.add_child(UiKit.title("PAUSED"))
			tv_banner.set_anchors_preset(Control.PRESET_CENTER)
			tv_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
			tv_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
		tv_banner.visible = paused


# --- Networking ---------------------------------------------------------------------------------

func make_snapshot() -> Array:
	var gp := PackedVector3Array()
	for g in park.guests.size():
		var gn: Node3D = park.guests[g]
		gp.append(gn.position if gn.visible else Vector3(0, -50, 0))
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	var ws := float(vr_rig.world_scale) if vr_rig != null else 1.0
	return [pose, snappedf(park.rotation.y, 0.001), snappedf(train_s, 0.01), snappedf(train_v, 0.01), hand_bits, gp, ws]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 7:
		return
	var pose: PackedFloat32Array = s[0]
	if vr_avatar != null and pose.size() > 0:
		vr_avatar.apply_pose(pose)
	park.rotation.y = float(s[1])
	snap_s = float(s[2])
	train_v = float(s[3])
	if phase != "ride":
		train_s = snap_s
		train.place(track, train_s)
	hand_bits = int(s[4])
	var gp: PackedVector3Array = s[5]
	for g in mini(gp.size(), park.guests.size()):
		var gn: Node3D = park.guests[g]
		gn.visible = gp[g].y > -10.0
		if gn.visible:
			gn.position = gn.position.lerp(gp[g], 0.5)
	snap_ws = float(s[6])


func apply_event(kind: String, args: Array) -> void:
	match kind:
		"click":
			_click_fx(args[0])
		"got":
			_got_fx(args[0], int(args[1]))
		"poke":
			poke_fx(String(args[0]), int(args[1]), args[2])
		"sound":
			sound(String(args[0]), -2.0)
