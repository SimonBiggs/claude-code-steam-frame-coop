extends Node3D
## The hiding places of this visit's house (housegen.gd data -> furniture): wardrobes, trunks, big vases,
## laundry baskets and curtains, plus the wallpaper tint. A hiding place with a ghost inside wobbles now
## and then (and a snoozy ghost blows bubbles, a peekaboo ghost peeks: ghost.gd), so even the little ones
## can spot where to shine the lantern. Built the same on every machine from [seed, level, daily].

const World := preload("res://games/ghost_lantern/world.gd")
const HouseGen := preload("res://games/ghost_lantern/housegen.gd")

var main
var data := {}
var pieces: Array = []  # Node3D per hiding place (null for the fixed ones: clock, piano, fireplace)
var wobble: Array = []  # seconds of wobble left per hiding place
var t := 0.0


func build(house: Dictionary) -> void:
	data = house
	for c in get_children():
		c.queue_free()
	pieces.clear()
	wobble.clear()
	for s in house.spots:
		var n: Node3D = null
		if not bool(HouseGen.KINDS[s.kind].get("fixed", false)):
			n = Node3D.new()
			n.position = s.pos
			n.rotation.y = float(s.yaw)
			add_child(n)
			_furniture(n, String(s.kind))
		pieces.append(n)
		wobble.append(0.0)
	_tint(house.get("tint", Color.WHITE))


## Where a ghost hides inside hiding place i, where its eyes peek out, and where it comes out.
func hide_point(i: int) -> Vector3:
	return HouseGen.hide_point(data.spots[i])


func eyes_point(i: int) -> Vector3:
	return HouseGen.eyes_point(data.spots[i])


func peek_point(i: int) -> Vector3:
	return Vector3(data.spots[i].peek)


func yaw(i: int) -> float:
	return float(data.spots[i].yaw)


func count() -> int:
	return pieces.size()


## Give hiding place i a little shake (a ghost inside giggles, wakes up or pops out).
func shake(i: int, secs: float = 0.6) -> void:
	if i >= 0 and i < wobble.size():
		wobble[i] = maxf(float(wobble[i]), secs)


func _process(delta: float) -> void:
	t += delta
	# Hiding places with a ghost inside give a little wobble every couple of seconds.
	var occupied := {}
	for g in get_tree().get_nodes_in_group("ghosts"):
		if g.hiding and g.hide_spot >= 0:
			occupied[g.hide_spot] = true
	for i in pieces.size():
		var n: Node3D = pieces[i]
		if n == null:
			continue
		wobble[i] = maxf(0.0, float(wobble[i]) - delta)
		var w: float = float(wobble[i])
		if occupied.has(i) and fmod(t + float(i) * 0.7, 2.6) < 0.45:
			w = maxf(w, 0.25)
		var base := float(data.spots[i].yaw)
		n.rotation = Vector3(0.0, base, sin(t * 26.0) * 0.04 * minf(w * 2.0, 1.0))


func _tint(c: Color) -> void:
	var wall: ShaderMaterial = main.world_refs.get("wall", null) if main != null else null
	if wall == null:
		return
	wall.set_shader_parameter("paper_a", Color(0.30, 0.17, 0.40) * c)
	wall.set_shader_parameter("paper_b", Color(0.24, 0.13, 0.33) * c)


func _solid(n: Node3D, size: Vector3, y: float) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = Vector3(0, y, 0)
	n.add_child(body)


## The furniture, facing +z (into the room); sizes match housegen.gd KINDS.
func _furniture(n: Node3D, kind: String) -> void:
	var k: Dictionary = HouseGen.KINDS[kind]
	var w := float(k.w)
	var d := float(k.d)
	var h := float(k.h)
	var brass := World.mat(Color(0.95, 0.75, 0.35), 0.8, 0.3)
	match kind:
		"wardrobe":
			var wood := World.mat(Color(0.42, 0.24, 0.18))
			World.box(n, Vector3(w, h, d), Vector3(0, h / 2.0, 0), wood, false)
			World.box(n, Vector3(w + 0.1, 0.1, d + 0.08), Vector3(0, h + 0.05, 0), World.mat(Color(0.3, 0.16, 0.12)), false)
			for sx in [-1.0, 1.0]:
				World.box(n, Vector3(w / 2.0 - 0.08, h - 0.3, 0.03), Vector3(sx * w / 4.0, h / 2.0 + 0.05, d / 2.0 + 0.01), World.mat(Color(0.5, 0.3, 0.22)), false)
				World.ball(n, 0.04, Vector3(sx * 0.07, h * 0.52, d / 2.0 + 0.05), brass)
			World.box(n, Vector3(0.03, h - 0.3, 0.035), Vector3(0, h / 2.0 + 0.05, d / 2.0 + 0.02), World.mat(Color(0.05, 0.03, 0.06)), false)  # the dark crack between the doors
			_solid(n, Vector3(w, h, d), h / 2.0)
		"trunk":
			var leather := World.mat(Color(0.35, 0.2, 0.4))
			World.box(n, Vector3(w, h * 0.75, d), Vector3(0, h * 0.375, 0), leather, false)
			var lid := World.cyl(n, d / 2.0, d / 2.0, w, Vector3(0, h * 0.75, 0), World.mat(Color(0.42, 0.25, 0.48)), 10)
			lid.rotation.z = PI / 2.0
			lid.scale = Vector3(1.0, 1.0, 0.6)
			for sx in [-0.3, 0.3]:
				World.box(n, Vector3(0.06, h * 0.78, d + 0.02), Vector3(sx * w, h * 0.39, 0), brass, false)
			World.box(n, Vector3(0.12, 0.12, 0.04), Vector3(0, h * 0.7, d / 2.0 + 0.02), brass, false)
			_solid(n, Vector3(w, h, d), h / 2.0)
		"vase":
			var china := World.mat(Color(0.55, 0.75, 0.95), 0.2, 0.3)
			World.cyl(n, 0.2, 0.18, 0.15, Vector3(0, 0.075, 0), china, 14)
			World.ball(n, 0.3, Vector3(0, 0.5, 0), china, 1.3)
			World.cyl(n, 0.2, 0.14, 0.35, Vector3(0, 0.92, 0), china, 14)
			World.cyl(n, 0.24, 0.24, 0.05, Vector3(0, 1.08, 0), World.mat(Color(0.95, 0.95, 1.0), 0.3), 14)
			World.cyl(n, 0.305, 0.305, 0.06, Vector3(0, 0.5, 0), World.mat(Color(1.0, 0.85, 0.4), 0.5), 16)  # a gold band
			_solid(n, Vector3(0.5, h, 0.5), h / 2.0)
		"basket":
			var wicker := World.mat(Color(0.75, 0.55, 0.3))
			World.cyl(n, 0.4, 0.32, h, Vector3(0, h / 2.0, 0), wicker, 14)
			World.cyl(n, 0.42, 0.42, 0.05, Vector3(0, h, 0), World.mat(Color(0.65, 0.45, 0.25)), 14)
			# Laundry spilling over the top: socks and a sheet in soft colours.
			World.ball(n, 0.22, Vector3(0.08, h + 0.05, 0.02), World.mat(Color(0.95, 0.95, 1.0)), 0.5)
			World.ball(n, 0.12, Vector3(-0.2, h + 0.06, 0.12), World.mat(Color(1.0, 0.6, 0.7)), 0.6)
			World.ball(n, 0.1, Vector3(0.22, h + 0.05, -0.15), World.mat(Color(0.6, 0.85, 1.0)), 0.6)
			var sock := World.box(n, Vector3(0.08, 0.3, 0.08), Vector3(0.36, h - 0.1, 0.12), World.mat(Color(1.0, 0.85, 0.3)), false)
			sock.rotation.z = -0.6
			_solid(n, Vector3(w, h, d), h / 2.0)
		"curtain":
			var velvet := World.mat(Color(0.6, 0.15, 0.3))
			var rod := World.cyl(n, 0.03, 0.03, w + 0.4, Vector3(0, h - 0.05, 0), brass, 6)
			rod.rotation.z = PI / 2.0
			for sx in [-1.0, 1.0]:
				for f in 3:
					var fold := World.cyl(n, 0.09, 0.11, h - 0.1, Vector3(sx * (w / 2.0 - 0.1 - f * 0.17), (h - 0.1) / 2.0, 0.02 * f), velvet, 8)
					fold.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# The bottom bulges where a ghost could be standing behind.
			World.ball(n, 0.3, Vector3(0, 0.6, -0.02), velvet, 1.8)
			World.cyl(n, 0.06, 0.06, 0.3, Vector3(-w / 2.0 + 0.25, 1.1, 0.1), World.mat(Color(1.0, 0.8, 0.3), 0.6), 6)  # a tie-back
