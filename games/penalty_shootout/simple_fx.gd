extends Node3D
## Simple mode: the things that teach and keep score without words.
##  - GLOVE SPOT (keeper practice): a glowing ghost glove with a ring where the next gentle ball will
##    arrive. Put a glove there and the ball lands in it.
##  - TARGET (striker practice): a glowing ring in the goal mouth. Kick the ball through it: it lights
##    up, bursts and the next one appears somewhere else.
##  - TALLY on both big scoreboards (no numbers): a GLOVE for every save, a FOOTBALL for every goal.
##  - ARROWS (no how-to words): a glowing arrow bobs over the ghost glove (until the keeper has saved
##    two practice balls) and, in the strikers' views (layer 2, which the keeper's cameras skip), over
##    the practice ring; after a miss one points into the goal / at the ring from where the ball went
##    for a moment (show_miss, sent to the TV machine as an "fx" event).
## Everything reads main's state (practice, pspot, ptarget, saves, goals_total), so the TV machine
## draws the same from the snapshot. Cheap: a few meshes plus two MultiMeshes for the tally.

const MeshKit := preload("res://games/penalty_shootout/mesh_kit.gd")
const TALLY_MAX := 15
const BOARDS: Array = [
	# centre, facing yaw (the board's +z looks at its viewers), icon size
	[Vector3(0, 14, 64.8), PI, 1.6],  # far end: faces the keeper
	[Vector3(0, 12, -14.9), 0.0, 1.35],  # behind the goal: faces the strikers' cameras
]

var main
var spot: Node3D
var spot_mat: StandardMaterial3D
var target: Node3D
var target_mat: StandardMaterial3D
var target_flash := 0.0
var gloves_mm: MultiMesh
var balls_mm: MultiMesh
var shown_saves := -1
var shown_goals := -1
var t := 0.0
var ring_arrow: Node3D
var glove_arrow: Node3D
var miss_arrow: Node3D
var miss_t := 0.0
var arrow_mat: StandardMaterial3D


func build() -> void:
	# Ghost glove + ring for the keeper's practice balls.
	spot = Node3D.new()
	spot.top_level = true
	add_child(spot)
	spot_mat = StandardMaterial3D.new()
	spot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spot_mat.albedo_color = Color(0.4, 1.0, 0.55, 0.45)
	var glove := MeshInstance3D.new()
	glove.mesh = main.sphere_mesh(0.12)
	glove.scale = Vector3(1.0, 1.15, 0.6)
	glove.material_override = spot_mat
	glove.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spot.add_child(glove)
	var ring := MeshInstance3D.new()
	ring.mesh = _torus(0.2, 0.24)
	ring.rotation.x = PI * 0.5
	ring.material_override = main.make_material(Color(0.4, 1.0, 0.55), 1.5)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spot.add_child(ring)
	spot.visible = false
	# The striker practice target: a big glowing ring with a see-through middle.
	target = Node3D.new()
	target.top_level = true
	add_child(target)
	var tr := MeshInstance3D.new()
	tr.mesh = _torus(0.55, 0.68)
	tr.rotation.x = PI * 0.5
	target_mat = StandardMaterial3D.new()
	target_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	target_mat.albedo_color = Color(1.0, 0.85, 0.2)
	tr.material_override = target_mat
	tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	target.add_child(tr)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.55
	dm.bottom_radius = 0.55
	dm.height = 0.01
	dm.radial_segments = 20
	dm.rings = 1
	disc.mesh = dm
	disc.rotation.x = PI * 0.5
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.albedo_color = Color(1.0, 0.9, 0.3, 0.22)
	disc.material_override = dmat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	target.add_child(disc)
	target.visible = false
	arrow_mat = StandardMaterial3D.new()
	arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arrow_mat.albedo_color = Color(1.0, 0.92, 0.35, 0.9)
	ring_arrow = _arrow(2)  # layer 2: the strikers' views only (it would fill the keeper's view)
	glove_arrow = _arrow(1)
	miss_arrow = _arrow(2)
	# Tally icons: one MultiMesh of gloves, one of footballs, for both boards.
	gloves_mm = _tally_mm(MeshKit.merge([
		[MeshKit.sphere(0.5, 12), MeshKit.at(Vector3.ZERO, Vector3(1.0, 1.15, 0.6)), Color(0.35, 1.0, 0.5)],
		[MeshKit.box(Vector3(0.7, 0.2, 0.12)), MeshKit.at(Vector3(0, -0.12, 0.3)), Color(1.0, 1.0, 1.0)],
		[MeshKit.sphere(0.2, 8), MeshKit.at(Vector3(0.48, 0.1, 0.0)), Color(0.35, 1.0, 0.5)],
	]))
	balls_mm = _tally_mm(MeshKit.merge([
		[MeshKit.sphere(0.5, 12), MeshKit.at(Vector3.ZERO), Color(1.0, 1.0, 1.0)],
		[MeshKit.sphere(0.18, 6), MeshKit.at(Vector3(0, 0, 0.4), Vector3(1.0, 1.0, 0.5)), Color(0.08, 0.08, 0.1)],
		[MeshKit.sphere(0.14, 6), MeshKit.at(Vector3(0.32, 0.25, 0.25), Vector3(1.0, 1.0, 0.5)), Color(0.08, 0.08, 0.1)],
		[MeshKit.sphere(0.14, 6), MeshKit.at(Vector3(-0.3, -0.26, 0.26), Vector3(1.0, 1.0, 0.5)), Color(0.08, 0.08, 0.1)],
	]))


## A fat glowing arrow, 1 m long at scale 1, pointing down its -y with the tip at the node's origin.
func _arrow(layer: int) -> Node3D:
	var a := Node3D.new()
	a.top_level = true
	add_child(a)
	var head := MeshInstance3D.new()
	head.mesh = main.cyl_mesh(0.3, 0.0, 0.45, 14)
	head.position = Vector3(0.0, 0.225, 0.0)
	var shaft := MeshInstance3D.new()
	shaft.mesh = main.cyl_mesh(0.11, 0.11, 0.55, 10)
	shaft.position = Vector3(0.0, 0.72, 0.0)
	for m in [head, shaft]:
		var mi: MeshInstance3D = m
		mi.material_override = arrow_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = layer
		a.add_child(mi)
	a.visible = false
	return a


## Points the arrow `a` (scale sc) so its tip sits at `tip`, pointing along `dir`.
func _aim_arrow(a: Node3D, tip: Vector3, dir: Vector3, sc: float) -> void:
	var d := dir.normalized() if dir.length() > 0.001 else Vector3.DOWN
	var q := Quaternion(Vector3.DOWN, d) if d.dot(Vector3.DOWN) > -0.999 else Quaternion(Vector3.FORWARD, PI)
	a.global_transform = Transform3D(Basis(q).scaled(Vector3.ONE * sc), tip)


## After a miss: a big arrow pointing into the goal at `to`, its tail out towards where the ball went
## (`from`): over the bar it points down under the bar, wide it points in past the post.
func show_miss(from: Vector3, to: Vector3) -> void:
	miss_t = 1.8
	var d := to - from
	miss_arrow.set_meta("tip", to + Vector3(0.0, 0.0, 0.3))
	miss_arrow.set_meta("dir", d if d.length() > 0.01 else Vector3.DOWN)
	miss_arrow.set_meta("sc", 2.0)


func _torus(inner: float, outer: float) -> TorusMesh:
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 24
	tm.ring_segments = 6
	return tm


func _tally_mm(mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = TALLY_MAX * BOARDS.size()
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = MeshKit.vertex_material(main.mats, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mm


## Gloves fill the viewer's left half of each board, footballs the right half (5 a row, 3 rows).
func _update_tally() -> void:
	var s: int = mini(int(main.saves), TALLY_MAX)
	var g: int = mini(int(main.goals_total), TALLY_MAX)
	if s == shown_saves and g == shown_goals:
		return
	shown_saves = s
	shown_goals = g
	for b in BOARDS.size():
		var bd: Array = BOARDS[b]
		var c: Vector3 = bd[0]
		var yaw: float = bd[1]
		var size: float = bd[2]
		var basis := Basis(Vector3.UP, yaw)
		var right := basis.x  # the viewer's right (the board faces +z of its basis)
		for k in TALLY_MAX:
			var col := k % 5
			var row := k / 5
			var off := Vector3(0.0, (1 - row) * size * 1.25, 0.0)
			var gx := -(1.0 + col) * size * 1.15
			var bx := (1.0 + col) * size * 1.15
			var gt := Transform3D(basis.scaled(Vector3.ONE * (size if k < s else 0.001)), c + right * gx + off)
			var bt := Transform3D(basis.scaled(Vector3.ONE * (size if k < g else 0.001)), c + right * bx + off)
			gloves_mm.set_instance_transform(b * TALLY_MAX + k, gt)
			balls_mm.set_instance_transform(b * TALLY_MAX + k, bt)


func flash_target() -> void:
	target_flash = 1.0


func _process(delta: float) -> void:
	t += delta
	_update_tally()
	var st: String = main.state
	var kp: bool = main.practice == "keeper" and (st == "kready" or st == "flight")
	spot.visible = kp
	if kp:
		var w: float = main.keeper.ws()
		spot.global_position = main.pspot
		spot.scale = Vector3.ONE * w * (1.0 + 0.12 * sin(t * 7.0))
		spot_mat.albedo_color.a = 0.35 + 0.2 * sin(t * 7.0)
	var k := absf(sin(t * 4.0))
	arrow_mat.albedo_color.a = 0.6 + 0.35 * k
	# Over the glove spot (shrunk to the keeper's scale), until two practice saves.
	var ga: bool = kp and not main.cue_learned(main.keeper, "save")
	glove_arrow.visible = ga
	if ga:
		var w2: float = main.keeper.ws()
		_aim_arrow(glove_arrow, main.pspot + Vector3.UP * (0.2 + 0.05 * k) * w2, Vector3.DOWN, 0.22 * w2)
	miss_t = maxf(0.0, miss_t - delta)
	miss_arrow.visible = miss_t > 0.0 and miss_arrow.has_meta("tip")
	if miss_arrow.visible:
		var md: Vector3 = miss_arrow.get_meta("dir")
		var nudge := -md.normalized() * 0.25 * k  # bobs towards the goal and back
		_aim_arrow(miss_arrow, miss_arrow.get_meta("tip") + nudge, md, float(miss_arrow.get_meta("sc")))
	var sp: bool = main.practice == "striker"
	ring_arrow.visible = sp
	if sp:
		_aim_arrow(ring_arrow, target.global_position + Vector3.UP * (0.78 + 0.2 * k), Vector3.DOWN, 1.6)
	target.visible = sp
	if sp:
		target.global_position = target.global_position.lerp(main.ptarget, 1.0 - exp(-8.0 * delta)) \
			if target.global_position.distance_to(main.ptarget) < 3.0 else main.ptarget
		target_flash = maxf(0.0, target_flash - delta * 1.5)
		target.scale = Vector3.ONE * (1.0 + 0.06 * sin(t * 5.0) + target_flash * 0.5)
		target_mat.albedo_color = Color(1.0, 0.85, 0.2).lerp(Color(1, 1, 1), target_flash)
