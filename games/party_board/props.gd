extends Node3D
## SIMPLE_MODE: the island reacts when the VR giant touches it (Simon's rule: everything you can reach
## does something). Child of main.stage, board units. Touch with either hand:
##   - every scattered tree, palm, pine, bush, flower, rock, lolly, candy cane, gumdrop, mushroom and
##     parasol wobbles (they are MultiMesh instances: just that instance's transform animates);
##   - the STAR spins fast and sparkles (it isn't picked up: you get it by hopping onto it);
##   - the windmill whirls, the volcano puffs, the lighthouse flashes;
##   - three little houses jiggle and puff from the chimney, boats rock and turn a circle, clouds above
##     the island puff away and drift back;
##   - the players' tokens get a gentle BOOP (a little hop).
## Cheap for the Frame: the touch test uses a coarse grid, ten small extra meshes, no physics.
## Touches are found where the VR player is (host / local); main.fx("prop", [kind, index]) plays the
## reaction there and on the TV machine.

const BD := preload("res://games/party_board/board_data.gd")
const MeshKit := preload("res://core/mesh_kit.gd")

const TOUCH := 1.3  ## board units (~8.5 cm on the VR table)
const CELL := 2.0
const WOBBLE_T := 1.1
const WINDMILL := Vector3(-6.2, 0.0, -5.8)  ## board_view._build_landmarks
const LIGHTHOUSE := Vector3(-9.6, 0.0, 8.9)
const CLOUD_SPOTS: Array[Vector3] = [Vector3(-6.0, 7.5, 5.0), Vector3(5.5, 8.0, 3.0), Vector3(0.5, 7.2, -2.5),
	Vector3(8.5, 7.6, -6.5)]
const MM_SOUNDS := {"palm": "swish", "tree": "swish", "pine": "swish", "bush": "boing", "rock": "block",
	"flower": "pop", "mushroom": "boing", "lolly": "pop", "cane": "ding", "gumdrop": "boing", "parasol": "swish"}

var main: Node
var board: Node3D
var touched := {}  ## kind -> true once ever (bots)
var _grid := {}  # Vector2i -> Array of [set index, instance index]
var _wob := {}  # set * 1000 + instance -> seconds left
var _cool := {}  # touch key -> seconds before it may react again
var clouds: Array[Node3D] = []
var _cloud_off: Array[Vector3] = []
var _cloud_vel: Array[Vector3] = []
var _cloud_puff: Array[float] = []
var boats: Array[Node3D] = []
var _boat_home: Array[Vector3] = []
var _boat_t: Array[float] = []
var houses: Array[Node3D] = []
var _house_t: Array[float] = []
var _t := 0.0
var _cloud_lift := 0.0  ## TV-only machines: clouds float higher, out of the TV camera's way


func _ready() -> void:
	board = main.board
	var sets: Array = board.prop_sets
	for si in sets.size():
		var xfs: Array = (sets[si] as Dictionary)["xfs"]
		for i in xfs.size():
			var o: Vector3 = (xfs[i] as Transform3D).origin
			var key := Vector2i(floori(o.x / CELL), floori(o.z / CELL))
			if not _grid.has(key):
				_grid[key] = []
			(_grid[key] as Array).append([si, i])
	_build_clouds()
	_build_boats()
	_build_houses()


func _shadows() -> bool:
	return main.vr_rig == null


# --- Extra toys -----------------------------------------------------------------------------------

func _build_clouds() -> void:
	_cloud_lift = 0.0 if main.vr_rig != null else 6.0
	var b := MeshKit.Builder.new()
	b.sphere(1.1, MeshKit.at(Vector3.ZERO), Color(1, 1, 1), 10)
	b.sphere(0.8, MeshKit.at(Vector3(-1.0, -0.2, 0.1)), Color(0.97, 0.98, 1.0), 10)
	b.sphere(0.85, MeshKit.at(Vector3(1.0, -0.15, -0.1)), Color(0.97, 0.98, 1.0), 10)
	b.sphere(0.6, MeshKit.at(Vector3(0.3, 0.55, 0.3)), Color(1, 1, 1), 8)
	var mesh := b.build()
	for p in CLOUD_SPOTS:
		var mi := MeshKit.instance(mesh, false)
		mi.name = "Cloud%d" % clouds.size()
		mi.position = p
		add_child(mi)
		clouds.append(mi)
		_cloud_off.append(Vector3.ZERO)
		_cloud_vel.append(Vector3.ZERO)
		_cloud_puff.append(0.0)


func _build_boats() -> void:
	var b := MeshKit.Builder.new()
	b.box(Vector3(0.7, 0.3, 1.6), MeshKit.at(Vector3(0, 0.15, 0)), Color(0.75, 0.45, 0.28))
	b.box(Vector3(0.6, 0.06, 1.4), MeshKit.at(Vector3(0, 0.31, 0)), Color(0.9, 0.75, 0.55))
	b.cylinder(0.04, 0.04, 1.5, MeshKit.at(Vector3(0, 1.0, 0.1)), Color(0.5, 0.33, 0.2), 6)
	b.wedge(Vector3(0.06, 1.1, 0.8), MeshKit.at(Vector3(0, 1.05, -0.32)), Color(1, 1, 1))
	b.box(Vector3(0.08, 0.2, 0.3), MeshKit.at(Vector3(0, 1.7, 0.1)), Color(1.0, 0.35, 0.35))
	var mesh := b.build()
	for a in [0.55, 2.35, 4.1]:
		var dir := Vector3(sin(float(a)), 0, cos(float(a)))
		var r := 13.0
		while r < 15.5 and BD.height(dir.x * r, dir.z * r) > -0.05:
			r += 0.3
		var mi := MeshKit.instance(mesh, _shadows())
		mi.name = "Boat%d" % boats.size()
		mi.position = dir * r
		mi.rotation.y = float(a) + PI * 0.5
		add_child(mi)
		boats.append(mi)
		_boat_home.append(mi.position)
		_boat_t.append(0.0)


func _build_houses() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var palette := [Color(1.0, 0.45, 0.4), Color(0.4, 0.6, 1.0), Color(0.5, 0.8, 0.4)]
	var spots: Array[Vector3] = []
	for k in 400:
		if spots.size() >= 3:
			break
		var p := Vector2(rng.randf_range(-9.0, 9.0), rng.randf_range(-1.0, 9.5))
		var h := BD.height(p.x, p.y)
		if h < 0.4 or p.distance_to(Vector2(BD.LAGOON.x, BD.LAGOON.y)) < BD.LAGOON_R + 1.0 or not board.call("_clear", p, 1.7, 1.1):
			continue
		var far := true
		for q in spots:
			if Vector2(q.x, q.z).distance_to(p) < 4.0:
				far = false
		if far:
			spots.append(Vector3(p.x, h - 0.02, p.y))
	for i in spots.size():
		var b := MeshKit.Builder.new()
		var wall := Color(0.98, 0.94, 0.85)
		b.box(Vector3(1.1, 0.8, 0.9), MeshKit.at(Vector3(0, 0.4, 0)), wall)
		b.cone(0.95, 0.7, MeshKit.at(Vector3(0, 1.15, 0), Vector3.ONE, Vector3(0, PI * 0.25, 0)), palette[i % palette.size()], 4)
		b.box(Vector3(0.26, 0.42, 0.05), MeshKit.at(Vector3(0, 0.21, 0.46)), Color(0.5, 0.32, 0.2))
		b.box(Vector3(0.22, 0.22, 0.05), MeshKit.at(Vector3(0.32, 0.5, 0.46)), Color(0.6, 0.85, 1.0))
		b.box(Vector3(0.16, 0.4, 0.16), MeshKit.at(Vector3(-0.3, 1.3, -0.1)), Color(0.6, 0.35, 0.3))
		var mi := MeshKit.instance(b.build(), _shadows())
		mi.name = "House%d" % i
		mi.position = spots[i]
		mi.rotation.y = atan2(-spots[i].x, -spots[i].z) + PI  # door towards the coast
		add_child(mi)
		houses.append(mi)
		_house_t.append(0.0)


# --- Touch (where the VR player is) -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	for k in _cool.keys():
		_cool[k] = float(_cool[k]) - delta
		if float(_cool[k]) <= 0.0:
			_cool.erase(k)
	var rig: Node = main.vr_rig
	if rig == null or get_tree().paused or not main.ready_to_play:
		return
	var phase := String(main.net.state_get("phase", ""))
	if phase == "minigame" or not board.visible:
		return
	for hand in 2:
		var hp: Vector3 = main.to_board(rig.hand_point(hand))
		if Vector2(hp.x, hp.z).length() > 18.0 or hp.y > 14.0 or hp.y < -2.0:
			continue
		_touch_props(hand, hp)
		_touch_spots(hand, hp)


func _hit(hand: int, key: String, kind: String, idx: int) -> void:
	var fresh := not _cool.has(key)
	_cool[key] = 0.6  # still touching: no new reaction until the hand has been away a moment
	if not fresh:
		return
	touched[kind] = true
	main.vr_rig.pulse(hand, 0.3, 0.04)
	main.fx("prop", [kind, idx])


func _touch_props(hand: int, hp: Vector3) -> void:
	var sets: Array = board.prop_sets
	var c := Vector2i(floori(hp.x / CELL), floori(hp.z / CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var list: Array = _grid.get(Vector2i(c.x + dx, c.y + dz), [])
			for e in list:
				var si: int = e[0]
				var i: int = e[1]
				var xf: Transform3D = ((sets[si] as Dictionary)["xfs"] as Array)[i]
				var mid := xf.origin + Vector3(0, 0.9 * xf.basis.get_scale().y, 0)
				if hp.distance_to(mid) < TOUCH:
					_hit(hand, "mm%d" % (si * 1000 + i), "mm", si * 1000 + i)


func _touch_spots(hand: int, hp: Vector3) -> void:
	var star: Node3D = board.star_node
	if star != null and star.visible and hp.distance_to(board.star_top()) < 1.6:
		_hit(hand, "star", "star", 0)
	var mill := WINDMILL + Vector3(0, BD.height(WINDMILL.x, WINDMILL.z) + 2.4, 0.75)
	if hp.distance_to(mill) < 1.8:
		_hit(hand, "mill", "mill", 0)
	var top := Vector3(BD.VOLCANO.x, BD.height(BD.VOLCANO.x, BD.VOLCANO.y) + 0.3, BD.VOLCANO.y)
	if hp.distance_to(top) < 2.2:
		_hit(hand, "volcano", "volcano", 0)
	var lamp := LIGHTHOUSE + Vector3(0, maxf(BD.height(LIGHTHOUSE.x, LIGHTHOUSE.z), 0.2) + 3.3, 0)
	if hp.distance_to(lamp) < 1.5:
		_hit(hand, "light", "light", 0)
	for i in clouds.size():
		if hp.distance_to(clouds[i].position) < 1.9:
			_hit(hand, "cloud%d" % i, "cloud", i)
	for i in boats.size():
		if hp.distance_to(boats[i].position + Vector3(0, 0.7, 0)) < 1.4:
			_hit(hand, "boat%d" % i, "boat", i)
	for i in houses.size():
		if hp.distance_to(houses[i].position + Vector3(0, 0.7, 0)) < 1.4:
			_hit(hand, "house%d" % i, "house", i)
	for pid in main.tokens:
		var t: Node3D = main.tokens[pid]
		if t.visible and hp.distance_to(t.position + Vector3(0, 1.0, 0)) < 1.2:
			_hit(hand, "token%d" % int(pid), "token", int(pid))


# --- Reactions (every machine) -------------------------------------------------------------------------

func react(kind: String, idx: int) -> void:
	var sfx: Node = main.sfx
	match kind:
		"mm":
			var si := idx / 1000
			var sets: Array = board.prop_sets
			if si >= sets.size():
				return
			_wob[idx] = WOBBLE_T
			sfx.play(String(MM_SOUNDS.get(String((sets[si] as Dictionary)["kind"]), "boing")), -9.0, randf_range(1.1, 1.4))
		"star":
			board.set("star_boost", 1.6)
			main.burst(board.star_top(), Color(1.0, 0.92, 0.4), 14)
			sfx.play("sparkle", -4.0)
		"mill":
			board.set("sails_boost", 2.5)
			sfx.play("whoosh", -6.0, 0.8)
		"volcano":
			var top := Vector3(BD.VOLCANO.x, BD.height(BD.VOLCANO.x, BD.VOLCANO.y) + 0.6, BD.VOLCANO.y)
			main.burst(top, Color(1.0, 0.5, 0.15), 18)
			main.burst(top + Vector3(0, 0.5, 0), Color(0.45, 0.42, 0.4), 10)
			sfx.play("explosion", -14.0, 1.4)
			if main.cam != null:
				main.cam.shake(0.15)
		"light":
			main.burst(LIGHTHOUSE + Vector3(0, maxf(BD.height(LIGHTHOUSE.x, LIGHTHOUSE.z), 0.2) + 3.3, 0), Color(1.0, 0.95, 0.5), 14)
			sfx.play("bell", -6.0, 1.2)
		"cloud":
			if idx < clouds.size():
				var away := Vector3(randf_range(-1.0, 1.0), 0.3, randf_range(-1.0, 1.0)).normalized()
				_cloud_vel[idx] = away * 5.0
				_cloud_puff[idx] = 1.0
				sfx.play("pop", -8.0, 0.7)
		"boat":
			if idx < boats.size():
				_boat_t[idx] = 2.4
				sfx.play("splash", -6.0, 1.2)
		"house":
			if idx < houses.size():
				_house_t[idx] = 0.9
				var h := houses[idx]
				main.burst(h.position + h.basis * Vector3(-0.3, 1.6, -0.1), Color(0.85, 0.85, 0.88), 8)
				sfx.play("door", -8.0, 1.3)
		"token":
			if main.tokens.has(idx):
				var t: Node3D = main.tokens[idx]
				if not t.call("busy"):
					t.call("hop_to", main.data.pos(int(t.get("space"))), 0.35)
				t.call("anim").play("cheer", 0.5)
				sfx.play("boing", -6.0, 1.5)


func _process(delta: float) -> void:
	_t += delta
	_animate_wobbles(delta)
	for i in clouds.size():
		var c := clouds[i]
		_cloud_off[i] += _cloud_vel[i] * delta
		_cloud_vel[i] = _cloud_vel[i] * exp(-2.0 * delta) - _cloud_off[i] * 0.6 * delta  # drift back home
		_cloud_puff[i] = maxf(0.0, _cloud_puff[i] - delta * 1.5)
		var drift := Vector3(sin(_t * 0.2 + i * 1.7), 0.15 * sin(_t * 0.6 + i), cos(_t * 0.17 + i)) * 0.6
		c.position = CLOUD_SPOTS[i] + drift + _cloud_off[i] + Vector3(0, _cloud_lift, 0)
		var puff := 1.0 + 0.35 * _cloud_puff[i] * absf(sin(_cloud_puff[i] * 12.0))
		c.scale = Vector3(puff, 1.0 / sqrt(puff), puff)
	for i in boats.size():
		var b := boats[i]
		_boat_t[i] = maxf(0.0, _boat_t[i] - delta)
		var k := _boat_t[i] / 2.4
		var home := _boat_home[i]
		var around := Vector3.ZERO
		if k > 0.0:
			var a := (1.0 - k) * TAU
			around = Vector3(sin(a), 0, 1.0 - cos(a)) * 0.9 * minf(1.0, k * 4.0)
		b.position = home + around + Vector3(0, 0.08 * sin(_t * 1.8 + i), 0)
		b.rotation.z = 0.06 * sin(_t * 1.3 + i) + 0.45 * k * sin(_t * 9.0)
	for i in houses.size():
		var h := houses[i]
		_house_t[i] = maxf(0.0, _house_t[i] - delta)
		var k2 := _house_t[i] / 0.9
		var sq := 0.18 * k2 * sin((1.0 - k2) * TAU * 2.5)
		h.scale = Vector3(1.0 + sq, 1.0 - sq, 1.0 + sq)


func _animate_wobbles(delta: float) -> void:
	if _wob.is_empty():
		return
	var sets: Array = board.prop_sets
	for code in _wob.keys():
		var si: int = int(code) / 1000
		var i: int = int(code) % 1000
		var st: Dictionary = sets[si]
		var mm: MultiMesh = st["mm"]
		var base: Transform3D = (st["xfs"] as Array)[i]
		var left := float(_wob[code]) - delta
		if left <= 0.0:
			_wob.erase(code)
			mm.set_instance_transform(i, base)
			continue
		_wob[code] = left
		var k := left / WOBBLE_T
		var tilt := sin((1.0 - k) * TAU * 3.0) * 0.4 * k
		var axis := Vector3(cos(float(i)), 0, sin(float(i)))
		var sq := 1.0 + 0.15 * k * sin((1.0 - k) * TAU * 4.0)
		var bs := Basis(axis, tilt) * base.basis * Basis.from_scale(Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq)))
		mm.set_instance_transform(i, Transform3D(bs, base.origin))
