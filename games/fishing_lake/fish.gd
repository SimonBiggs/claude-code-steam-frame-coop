extends Node3D
## One fish slot in the lake (also used for the boots and treasure chests that get hooked off the bottom).
## The host steers it; on the TV machine it's a ghost gliding to the snapshot positions.
## Fish wander in shoals, flee from boats (so the TV players can herd them), swim up to a lure in the
## water, nibble, then bite. The angler (angler.gd) takes over once it's hooked.

const Lake := preload("res://games/fishing_lake/lake.gd")

const MINNOW := 0
const PERCH := 1
const TROUT := 2
const CATFISH := 3
const PIKE := 4
const GOLDEN := 5
const BOOT := 6
const CHEST := 7
# len: body length (m), pts: points, pull: how hard it fights (0..1), kg: weight range,
# speed: cruising m/s, notice: how far it spots a lure, spawn: weight in the spawn lottery.
const TYPES := [
	{"name": "Minnow", "col": Color(0.72, 0.82, 0.95), "len": 0.22, "pts": 5, "pull": 0.2, "kg": [0.05, 0.2], "speed": 1.3, "notice": 4.5, "spawn": 30, "shoal": 3},
	{"name": "Stripy Perch", "col": Color(0.55, 0.75, 0.25), "len": 0.32, "pts": 10, "pull": 0.4, "kg": [0.2, 0.8], "speed": 1.1, "notice": 4.0, "spawn": 26, "shoal": 2},
	{"name": "Rainbow Trout", "col": Color(1.0, 0.55, 0.65), "len": 0.42, "pts": 20, "pull": 0.55, "kg": [0.6, 2.0], "speed": 1.2, "notice": 3.5, "spawn": 18, "shoal": 1},
	{"name": "Lazy Catfish", "col": Color(0.45, 0.4, 0.35), "len": 0.55, "pts": 30, "pull": 0.65, "kg": [2.0, 6.0], "speed": 0.7, "notice": 3.0, "spawn": 11, "shoal": 1},
	{"name": "BIG PIKE", "col": Color(0.4, 0.55, 0.3), "len": 0.8, "pts": 45, "pull": 0.85, "kg": [3.0, 9.0], "speed": 1.4, "notice": 3.0, "spawn": 8, "shoal": 1},
	{"name": "GOLDEN FISH", "col": Color(1.0, 0.8, 0.15), "len": 0.45, "pts": 100, "pull": 0.9, "kg": [1.0, 3.0], "speed": 1.6, "notice": 4.0, "spawn": 0, "shoal": 1},
	{"name": "Old Boot", "col": Color(0.4, 0.27, 0.15), "len": 0.3, "pts": 2, "pull": 0.15, "kg": [0.5, 0.9], "speed": 0.0, "notice": 0.0, "spawn": 0, "shoal": 1, "junk": true},
	{"name": "TREASURE CHEST", "col": Color(0.6, 0.38, 0.18), "len": 0.45, "pts": 60, "pull": 0.35, "kg": [8.0, 15.0], "speed": 0.0, "notice": 0.0, "spawn": 0, "shoal": 1, "junk": true},
]

var main
var slot := 0
var kind := -1  # -1: empty slot
var ghost := false
var state := "swim"  # swim, approach, nibble, bite, hooked, flee, landed
var state_t := 0.0
var nibble_time := 1.5
var vel := Vector3.ZERO
var wander := Vector3.ZERO
var shoal := -1
var depth := -0.4
var weight := 1.0
var called_t := 0.0
var called_by := -1
var herded_by := -1
var herded_t := 0.0
var flee_from := Vector3.ZERO
var wiggle := 0.0

var net_pos := Vector3.ZERO
var net_yaw := 0.0
var net_flags := 0

var built_kind := -2
var body: Node3D
var tail: MeshInstance3D
var icon: Label3D


func info() -> Dictionary:
	return TYPES[maxi(kind, 0)]


func is_junk() -> bool:
	return kind >= 0 and bool(info().get("junk", false))


func free_to_bite() -> bool:
	return kind >= 0 and not is_junk() and (state == "swim" or state == "flee")


## Fill this slot with a new fish (host).
func spawn(k: int, pos: Vector3, shoal_id: int) -> void:
	kind = k
	shoal = shoal_id
	var d := info()
	var kg: Array = d["kg"]
	weight = snappedf(randf_range(float(kg[0]), float(kg[1])), 0.01)
	depth = -0.25 - float(d["len"]) * 0.45
	state = "swim"
	state_t = 0.0
	called_t = 0.0
	called_by = -1
	herded_by = -1
	herded_t = 0.0
	position = pos
	position.y = depth
	vel = Vector3.ZERO
	wander = pos
	_rebuild()
	visible = true


func clear() -> void:
	kind = -1
	state = "swim"
	visible = false
	called_t = 0.0


func set_state(s: String) -> void:
	state = s
	state_t = 0.0


# --- Looks -------------------------------------------------------------------------

func _rebuild() -> void:
	if built_kind == kind:
		return
	built_kind = kind
	if body != null:
		body.queue_free()
	body = Node3D.new()
	add_child(body)
	if kind < 0:
		return
	var d := info()
	var col: Color = d["col"]
	var l: float = d["len"]
	var glow := 0.9 if kind == GOLDEN else 0.0
	var mat: StandardMaterial3D = main.make_material(col, glow)
	if kind == BOOT:
		var leg := MeshInstance3D.new()
		leg.mesh = main.box_mesh(Vector3(0.12, 0.22, 0.12))
		leg.material_override = mat
		leg.position = Vector3(0, 0.08, -0.05)
		body.add_child(leg)
		var foot := MeshInstance3D.new()
		foot.mesh = main.box_mesh(Vector3(0.12, 0.08, 0.26))
		foot.material_override = mat
		foot.position = Vector3(0, -0.04, 0.03)
		body.add_child(foot)
		tail = null
		return
	if kind == CHEST:
		var box := MeshInstance3D.new()
		box.mesh = main.box_mesh(Vector3(0.45, 0.28, 0.3))
		box.material_override = mat
		body.add_child(box)
		var band := MeshInstance3D.new()
		band.mesh = main.box_mesh(Vector3(0.47, 0.06, 0.32))
		band.material_override = main.make_material(Color(1.0, 0.8, 0.2), 0.6)
		band.position = Vector3(0, 0.06, 0)
		body.add_child(band)
		tail = null
		return
	var b := MeshInstance3D.new()
	b.mesh = main.sphere_mesh(0.5)
	b.material_override = mat
	var thin := 0.22 if kind == PIKE else 0.32
	b.scale = Vector3(l * thin, l * 0.4, l)
	body.add_child(b)
	tail = MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(l * 0.45, l * 0.35, 0.02)
	tail.mesh = pm
	tail.material_override = mat
	tail.rotation = Vector3(deg_to_rad(90.0), 0.0, deg_to_rad(90.0))
	tail.position = Vector3(0, 0, -l * 0.55)
	body.add_child(tail)
	var fin := MeshInstance3D.new()
	fin.mesh = pm
	fin.material_override = main.make_material(col.darkened(0.3), glow)
	fin.scale = Vector3(0.6, 0.6, 1.0)
	fin.rotation = Vector3(0.0, deg_to_rad(90.0), 0.0)
	fin.position = Vector3(0, l * 0.2, -l * 0.05)
	body.add_child(fin)
	if kind == PERCH or kind == TROUT:
		var stripe := MeshInstance3D.new()
		stripe.mesh = main.sphere_mesh(0.5)
		stripe.material_override = main.make_material(Color(0.25, 0.3, 0.15) if kind == PERCH else Color(1.0, 0.35, 0.45), 0.2)
		stripe.scale = Vector3(l * thin * 1.04, l * 0.12, l * 0.75)
		body.add_child(stripe)


func _update_icon() -> void:
	var show := called_t > 0.0 and kind >= 0 and state != "landed"
	if show and icon == null:
		icon = Label3D.new()
		icon.font_size = 96
		icon.pixel_size = 0.012
		icon.outline_size = 24
		icon.modulate = Color(1.0, 0.9, 0.2)
		icon.no_depth_test = true
		icon.render_priority = 4
		add_child(icon)
	if icon != null:
		icon.visible = show
		if show:
			icon.text = "!! %s !!" % str(info()["name"]).to_upper() if kind >= TROUT else "!! FISH !!"
			icon.global_position = global_position + Vector3(0, 1.6 + 0.15 * sin(wiggle * 2.0), 0)
			main.face_label(icon)


func _process(delta: float) -> void:
	if kind < 0:
		visible = false
		return
	if ghost:
		_ghost_follow(delta)
	wiggle += delta * (4.0 + vel.length() * 6.0)
	if tail != null:
		var amp := 0.5 if state == "hooked" or state == "landed" else 0.25
		tail.rotation.y = sin(wiggle * 2.2) * amp
		body.rotation.y = sin(wiggle * 2.2 + 1.5) * amp * 0.25
	if state == "landed" and body != null:
		body.rotation.z = sin(wiggle * 3.0) * 0.6
	elif body != null:
		body.rotation.z = 0.0
	if called_t > 0.0:
		called_t -= delta
	_update_icon()


func _ghost_follow(delta: float) -> void:
	if position.distance_to(net_pos) > 4.0:
		position = net_pos
	else:
		position = position.lerp(net_pos, 1.0 - exp(-10.0 * delta))
	rotation.y = lerp_angle(rotation.y, net_yaw, 1.0 - exp(-10.0 * delta))
	called_t = 1.0 if net_flags & 1 else 0.0
	if net_flags & 2:
		state = "hooked"
	elif net_flags & 4:
		state = "landed"
	else:
		state = "swim"


# --- Host AI -------------------------------------------------------------------------

func sim(delta: float) -> void:
	if kind < 0 or ghost:
		return
	state_t += delta
	if herded_t > 0.0:
		herded_t -= delta
		if herded_t <= 0.0:
			herded_by = -1
	if state == "hooked" or state == "landed":
		return  # the angler moves us
	var d := info()
	var speed: float = d["speed"]
	var want := Vector3.ZERO
	var lure: Vector3 = main.lure_position()
	var lure_wet: bool = main.lure_in_water()
	match state:
		"swim":
			if Vector2(position.x - wander.x, position.z - wander.z).length() < 1.0 or state_t > 9.0:
				_pick_wander()
			want = _flat(wander - position).normalized() * speed * 0.6
		"flee":
			want = _flat(position - flee_from).normalized() * speed * 2.2
			if state_t > 2.2:
				set_state("swim")
				_pick_wander()
		"approach":
			if not lure_wet:
				set_state("swim")
			else:
				var to := _flat(lure - position)
				want = to.normalized() * clampf(to.length() * 0.35, maxf(speed, 0.9), 3.0) * (1.4 if called_t > 0.0 else 1.0)
				if to.length() < 0.45:
					set_state("nibble")
					nibble_time = randf_range(1.0, 2.6)
					main.on_fish_nibble(self)
		"nibble":
			if not lure_wet:
				set_state("swim")
			else:
				var ang := state_t * 2.5
				var around := lure + Vector3(cos(ang), 0, sin(ang)) * 0.3
				want = _flat(around - position) * 3.0
				if state_t > nibble_time:
					set_state("bite")
					main.on_fish_bite(self)
		"bite":
			want = _flat(lure - position) * 4.0
	# Boats scare fish: they swim away from any boat that comes close (that's how you herd them).
	if state == "swim" or state == "approach" or state == "flee":
		for b in main.active_boats():
			var away := _flat(position - b.global_position)
			var dist := away.length()
			if dist < 3.2 and dist > 0.01:
				want += away / dist * (3.2 - dist) * (0.4 if state == "approach" else 1.3)
				herded_by = b.index
				herded_t = 8.0
	vel = vel.move_toward(want, 2.5 * delta)
	position += vel * delta
	_keep_in_lake()
	position.y = lerpf(position.y, depth * (0.5 if state == "nibble" or state == "bite" else 1.0), 1.0 - exp(-2.0 * delta))
	if vel.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(vel.x, vel.z), 1.0 - exp(-6.0 * delta))


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _pick_wander() -> void:
	state_t = 0.0
	# Shoals share a target so they swim together.
	if shoal >= 0:
		for f in main.fish:
			if f != self and f.kind >= 0 and f.shoal == shoal and f.state == "swim" and f.wander != Vector3.ZERO and randf() < 0.8:
				wander = f.wander + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
				return
	var a := randf() * TAU
	var r := sqrt(randf()) * (Lake.LAKE_R - 3.0)
	wander = Lake.LAKE_C + Vector3(sin(a) * r, 0.0, cos(a) * r)
	if wander.z > Lake.JETTY_END_Z - 1.0:
		wander.z = Lake.JETTY_END_Z - 1.0 - randf() * 4.0


func _keep_in_lake() -> void:
	var off := _flat(position - Lake.LAKE_C)
	var lim := Lake.LAKE_R - 1.5
	if off.length() > lim:
		position = Lake.LAKE_C + off.normalized() * lim + Vector3(0, position.y, 0)
		vel *= 0.3
	# Not under the jetty.
	if position.z > Lake.JETTY_END_Z - 0.6 and absf(position.x) < 1.6:
		position.z = Lake.JETTY_END_Z - 0.6


## Scare this fish away from a point (boat splash, missed bite).
func scare(from: Vector3, by: int) -> void:
	if state == "hooked" or state == "landed" or kind < 0:
		return
	if state == "nibble" or state == "bite" or state == "approach":
		main.on_fish_scared(self)
	flee_from = from
	set_state("flee")
	if by > 0:
		herded_by = by
		herded_t = 8.0
