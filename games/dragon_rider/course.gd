extends Node3D
## One level's sky route, built from a seed so the host and the TV machine build exactly the same
## thing: glowing rings to fly through, stars to scoop up on the way, balloons for the gunners and
## floating sky islands (with blossom trees) to fly around.
## Item ids: stars 1000+, balloons 2000+. `gone` holds the ids that were collected or popped.

const SPACING := 74.0
const FIRST := 95.0
const RING_R := 6.5
const BALLOON_COLORS: Array[Color] = [Color(1.0, 0.35, 0.4), Color(1.0, 0.8, 0.25), Color(0.4, 0.8, 1.0),
	Color(0.55, 0.95, 0.45), Color(0.95, 0.5, 1.0)]

var main
var seed_value := 0
var level := 1
var rings: Array = []  # {pos: Vector3, normal: Vector3, radius: float, node: MeshInstance3D, final: bool}
var stars: Array = []  # {id, node, pos}
var balloons: Array = []  # {id, node, pos}
var gone := {}
var t := 0.0
var shown_ring := -2
var ring_next_mat: StandardMaterial3D
var ring_later_mat: StandardMaterial3D
var ring_done_mat: StandardMaterial3D
var ring_final_mat: StandardMaterial3D


static func ring_count(lv: int) -> int:
	return mini(6 + (lv - 1) * 2, 14)


func build(seed_v: int, origin: Vector3, yaw: float, lv: int) -> void:
	seed_value = seed_v
	level = lv
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	ring_next_mat = main.color_mat(Color(1.0, 0.85, 0.3), 2.2)
	ring_later_mat = main.color_mat(Color(0.55, 0.85, 1.0), 0.7)
	ring_done_mat = main.color_mat(Color(0.5, 1.0, 0.6), 0.5)
	ring_final_mat = main.color_mat(Color(1.0, 0.5, 0.75), 2.5)
	var rock: StandardMaterial3D = main.color_mat(Color(0.55, 0.42, 0.5), 0.0)
	var grass: StandardMaterial3D = main.color_mat(Color(0.5, 0.78, 0.4), 0.0)
	var trunk: StandardMaterial3D = main.color_mat(Color(0.45, 0.3, 0.22), 0.0)
	var blossom: StandardMaterial3D = main.color_mat(Color(1.0, 0.6, 0.75), 0.15)
	var star_mat: StandardMaterial3D = main.color_mat(Color(1.0, 0.88, 0.3), 2.5)
	var string_mat: StandardMaterial3D = main.color_mat(Color(0.95, 0.95, 0.95), 0.0)
	var count := ring_count(lv)
	var heading := yaw
	var pos := origin
	var prev := origin
	for k in count:
		var dist := FIRST if k == 0 else SPACING
		if k > 0:
			heading += rng.randf_range(-0.55, 0.55) * minf(1.0, 0.5 + lv * 0.15)
		var y := clampf(pos.y + rng.randf_range(-12.0, 12.0), 22.0, 85.0)
		pos = pos + Basis(Vector3.UP, heading) * Vector3.FORWARD * dist
		pos.y = y
		var normal := (pos - prev).normalized()
		var final := k == count - 1
		var radius := RING_R * (1.3 if final else 1.0)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = radius - 0.45
		tm.outer_radius = radius + 0.45
		tm.rings = 28
		tm.ring_segments = 8
		ring.mesh = tm
		ring.material_override = ring_later_mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		ring.global_position = pos
		ring.basis = main.basis_y_to(normal)
		rings.append({"pos": pos, "normal": normal, "radius": radius, "node": ring, "final": final})
		# Stars along the way from the previous ring to this one.
		var side := normal.cross(Vector3.UP).normalized()
		for j in 2:
			var f := 0.35 + j * 0.3
			var sp := prev.lerp(pos, f) + side * rng.randf_range(-3.0, 3.0) + Vector3.UP * rng.randf_range(-2.0, 2.0)
			if k == 0:
				sp = origin.lerp(pos, 0.55 + j * 0.2)
			var star := MeshInstance3D.new()
			star.mesh = main.gem_mesh()
			star.material_override = star_mat
			star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(star)
			star.global_position = sp
			stars.append({"id": 1000 + stars.size(), "node": star, "pos": sp})
		# Balloons off to the sides for the gunners.
		var nb := 2 if lv < 3 else 3
		for j in nb:
			var s := -1.0 if rng.randf() < 0.5 else 1.0
			var bp := prev.lerp(pos, rng.randf_range(0.2, 0.9)) + side * s * rng.randf_range(9.0, 22.0) \
				+ Vector3.UP * rng.randf_range(-5.0, 9.0)
			var b := Node3D.new()
			add_child(b)
			b.global_position = bp
			var c: Color = BALLOON_COLORS[rng.randi() % BALLOON_COLORS.size()]
			var bm := MeshInstance3D.new()
			bm.mesh = main.sphere_mesh(1.1)
			bm.material_override = main.color_mat(c, 0.35)
			bm.scale = Vector3(1.0, 1.2, 1.0)
			bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			b.add_child(bm)
			var st := MeshInstance3D.new()
			st.mesh = main.cyl_mesh(0.02, 0.02, 2.0, 4)
			st.material_override = string_mat
			st.position = Vector3(0, -2.3, 0)
			st.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			b.add_child(st)
			var id := 2000 + balloons.size()
			b.set_meta("kind", "balloon")
			b.set_meta("id", id)
			b.set_meta("radius", 1.7)
			b.set_meta("color", c)
			b.add_to_group("dr_targets")
			balloons.append({"id": id, "node": b, "pos": bp})
		# A sky island beside the route, and a big one far off as scenery.
		var isl_side := -1.0 if rng.randf() < 0.5 else 1.0
		_island(prev.lerp(pos, 0.5) + side * isl_side * rng.randf_range(32.0, 55.0) + Vector3.UP * rng.randf_range(-22.0, -6.0),
			rng.randf_range(6.0, 12.0), rng, rock, grass, trunk, blossom, 1 + rng.randi() % 2)
		var far_pos := prev.lerp(pos, 0.5) - side * isl_side * rng.randf_range(110.0, 190.0) + Vector3.UP * rng.randf_range(-40.0, 10.0)
		var far_r := rng.randf_range(18.0, 34.0)
		if k % 2 == 0:
			_island(far_pos, far_r, rng, rock, grass, trunk, blossom, 0)
		prev = pos
	# The finish: a big island just past the last ring.
	var last: Dictionary = rings[rings.size() - 1]
	var lp: Vector3 = last.pos
	var ln: Vector3 = last.normal
	_island(lp + ln * 70.0 + Vector3.UP * -30.0, 22.0, rng, rock, grass, trunk, blossom, 3)
	# Draw distance: the Frame's GPU only draws what is near enough to matter.
	_cull(self)
	update_rings(0)


func _cull(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).visibility_range_end = 480.0
		_cull(c)


func _island(at: Vector3, r: float, rng: RandomNumberGenerator, rock: Material, grass: Material,
		trunk: Material, blossom: Material, trees: int) -> void:
	var n := Node3D.new()
	add_child(n)
	n.global_position = at
	n.rotation.y = rng.randf() * TAU
	var base := MeshInstance3D.new()
	base.mesh = main.cyl_mesh(r, r * 0.12, r * 1.5, 9)
	base.material_override = rock
	base.position = Vector3(0, -r * 0.75, 0)
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(base)
	var top := MeshInstance3D.new()
	top.mesh = main.cyl_mesh(r * 1.04, r * 1.04, 0.8, 9)
	top.material_override = grass
	top.position = Vector3(0, 0.3, 0)
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(top)
	for k in trees:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, r * 0.55)
		var tp := Vector3(cos(a) * d, 0.7, sin(a) * d)
		var h := rng.randf_range(2.5, 4.5) * (1.0 + r * 0.03)
		var tr := MeshInstance3D.new()
		tr.mesh = main.cyl_mesh(0.25, 0.4, h, 6)
		tr.material_override = trunk
		tr.position = tp + Vector3(0, h * 0.5, 0)
		tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(tr)
		var crown := MeshInstance3D.new()
		crown.mesh = main.sphere_mesh(1.0)
		crown.material_override = blossom
		crown.scale = Vector3.ONE * h * 0.6
		crown.position = tp + Vector3(0, h + h * 0.2, 0)
		crown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(crown)


## Highlight the ring to fly through next (gold), later ones in blue, passed ones in green.
func update_rings(next_i: int) -> void:
	if next_i == shown_ring:
		return
	shown_ring = next_i
	for i in rings.size():
		var r: Dictionary = rings[i]
		var node: MeshInstance3D = r.node
		if i < next_i:
			node.material_override = ring_done_mat
			node.scale = Vector3.ONE * 0.9
		elif i == next_i:
			node.material_override = ring_final_mat if r.final else ring_next_mat
			node.scale = Vector3.ONE
		else:
			node.material_override = ring_later_mat
			node.scale = Vector3.ONE


func next_ring(next_i: int) -> Dictionary:
	if next_i >= 0 and next_i < rings.size():
		return rings[next_i]
	return {}


func animate(delta: float) -> void:
	t += delta
	for s in stars:
		var node: MeshInstance3D = s.node
		if node.visible:
			node.rotation.y = t * 2.0 + float(s.id)
	for b in balloons:
		var node: Node3D = b.node
		if node.visible:
			var p: Vector3 = b.pos
			node.global_position = p + Vector3(0, sin(t * 1.2 + float(b.id)) * 0.6, 0)
	if shown_ring >= 0 and shown_ring < rings.size():
		var r: Dictionary = rings[shown_ring]
		var node: MeshInstance3D = r.node
		node.scale = Vector3.ONE * (1.0 + sin(t * 4.0) * 0.04)


func remove_item(id: int) -> void:
	if gone.has(id):
		return
	gone[id] = true
	for list in [stars, balloons]:
		for it in list:
			if int(it.id) == id:
				var node: Node3D = it.node
				node.visible = false
				if node.is_in_group("dr_targets"):
					node.remove_from_group("dr_targets")


func gone_ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in gone.keys():
		out.append(int(k))
	return out


func remaining_balloons() -> int:
	var n := 0
	for b in balloons:
		if not gone.has(int(b.id)):
			n += 1
	return n
