extends Node3D
## One snowman: a stack of 1-3 snowballs with a face, twig arms, carrot nose and hat, drawn from
## plain data (set_data) so the host and the TV machine build exactly the same thing.
## Wobbles when touched, pops when it grows, dances once it is finished.

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

const SNOW := Color(0.97, 0.98, 1.0)

var radii: Array[float] = []
var carrot := false
var hat := false
var done := false

var body: Node3D  # everything that wobbles / dances
var arms: Array[Node3D] = []
var ghosts: Array[MeshInstance3D] = []
var hat_node: Node3D
var t := 0.0
var wob := 0.0
var wob_dir := Vector2(1.0, 0.0)
var pop_t := 1.0
var dance_seed := 0.0


func _ready() -> void:
	dance_seed = randf() * 10.0


# --- Shapes shared with main.gd ---------------------------------------------------------------

## Height of ball i's centre above the ground.
static func center_y(r: Array[float], i: int) -> float:
	var y := r[0] * 0.9
	for k in range(1, i + 1):
		y += (r[k - 1] + r[k]) * 0.8
	return y


## Height of the very top of the stack.
static func top_y(r: Array[float]) -> float:
	return center_y(r, r.size() - 1) + r[r.size() - 1] * 0.92


static func ball_mesh() -> Mesh:
	return ResCache.get_or_make("snowman_ball_v1", func() -> Resource:
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 16
		s.rings = 8
		return s)


static func snow_material() -> Material:
	return ResCache.get_or_make("snowman_snow_v1", func() -> Resource:
		var m := StandardMaterial3D.new()
		m.albedo_color = SNOW
		m.roughness = 0.9
		m.rim_enabled = true
		m.rim = 0.4
		m.emission_enabled = true
		m.emission = Color(0.55, 0.62, 0.78)
		m.emission_energy_multiplier = 0.25
		return m)


static func ghost_material() -> StandardMaterial3D:
	return ResCache.get_or_make("snowman_ghost_v1", func() -> Resource:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.6, 0.9, 1.0, 0.35)
		m.cull_mode = BaseMaterial3D.CULL_BACK
		return m)


## A carrot nose: base at the origin, pointing along +Z.
static func carrot_mesh() -> Mesh:
	return ResCache.get_or_make("snowman_carrot_v1", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cone(0.05, 0.24, MeshKit.aim(Vector3(0.0, 0.0, 0.12), Vector3.BACK), Color(1.0, 0.5, 0.1))
		b.cone(0.03, 0.06, MeshKit.aim(Vector3(0.0, 0.0, -0.02), Vector3.FORWARD), Color(0.3, 0.75, 0.2))
		return b.build())


## A top hat: base (brim) at the origin.
static func hat_mesh() -> Mesh:
	return ResCache.get_or_make("snowman_hat_v1", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(0.25, 0.25, 0.035, MeshKit.at(Vector3(0.0, 0.017, 0.0)), Color(0.08, 0.08, 0.12))
		b.cylinder(0.155, 0.16, 0.26, MeshKit.at(Vector3(0.0, 0.16, 0.0)), Color(0.08, 0.08, 0.12))
		b.cylinder(0.165, 0.165, 0.055, MeshKit.at(Vector3(0.0, 0.065, 0.0)), Color(0.95, 0.2, 0.25))
		return b.build())


static func arm_mesh() -> Mesh:
	return ResCache.get_or_make("snowman_arm_v1", func() -> Resource:
		var b := MeshKit.Builder.new()
		var brown := Color(0.42, 0.26, 0.12)
		b.tube(Vector3.ZERO, Vector3(0.5, 0.2, 0.0), 0.028, 0.018, brown)
		b.tube(Vector3(0.38, 0.15, 0.0), Vector3(0.5, 0.32, 0.03), 0.014, 0.01, brown)
		b.tube(Vector3(0.44, 0.18, 0.0), Vector3(0.58, 0.14, -0.03), 0.014, 0.01, brown)
		return b.build())


# --- Data -> visuals --------------------------------------------------------------------------

func set_data(new_radii: Array[float], new_carrot: bool, new_hat: bool, new_done: bool) -> void:
	var grew := new_radii.size() > radii.size() or (new_carrot and not carrot) or (new_hat and not hat)
	var changed := new_radii != radii or new_carrot != carrot or new_hat != hat or new_done != done
	radii = new_radii.duplicate()
	carrot = new_carrot
	hat = new_hat
	done = new_done
	if changed:
		_rebuild()
	if grew:
		pop_t = 0.0


func _rebuild() -> void:
	if body != null:
		body.queue_free()
	arms.clear()
	ghosts.clear()
	hat_node = null
	body = Node3D.new()
	add_child(body)
	if radii.is_empty():
		return
	for i in radii.size():
		var mi := MeshInstance3D.new()
		mi.mesh = ball_mesh()
		mi.material_override = snow_material()
		mi.scale = Vector3.ONE * radii[i]
		mi.position.y = center_y(radii, i)
		body.add_child(mi)
	var n := radii.size()
	var deco := MeshKit.Builder.new()
	var coal := Color(0.06, 0.06, 0.08)
	if n >= 2:
		var r1 := radii[1]
		var y1 := center_y(radii, 1)
		for k in 3:  # buttons
			var a := -0.45 + k * 0.42
			deco.sphere(r1 * 0.09, MeshKit.at(Vector3(0.0, y1 + sin(a) * r1, cos(a) * r1 * 0.98)), coal, 8)
		for side in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(side * r1 * 0.85, y1 + r1 * 0.25, 0.0)
			pivot.rotation.y = 0.0 if side > 0.0 else PI
			var arm := MeshInstance3D.new()
			arm.mesh = arm_mesh()
			arm.scale = Vector3.ONE * clampf(r1 / 0.3, 0.7, 1.3)
			pivot.add_child(arm)
			body.add_child(pivot)
			arms.append(pivot)
	if n >= 3:
		var r2 := radii[2]
		var y2 := center_y(radii, 2)
		for side in [-1.0, 1.0]:  # eyes
			deco.sphere(r2 * 0.13, MeshKit.at(Vector3(side * r2 * 0.36, y2 + r2 * 0.3, r2 * 0.88)), coal, 8)
		for k in 5:  # smile
			var a := (k - 2) * 0.28
			deco.sphere(r2 * 0.07, MeshKit.at(Vector3(sin(a) * r2 * 0.5, y2 - r2 * 0.3 + absf(a) * r2 * 0.18, r2 * 0.9)), coal, 6)
		var nose := MeshInstance3D.new()
		nose.mesh = carrot_mesh()
		nose.position = Vector3(0.0, y2 + r2 * 0.02, r2 * 0.92)
		nose.scale = Vector3.ONE * clampf(r2 / 0.22, 0.8, 1.4)
		body.add_child(nose)
		var top := MeshInstance3D.new()
		top.mesh = hat_mesh()
		top.position = Vector3(0.0, y2 + r2 * 0.78, 0.0)
		top.rotation.z = -0.12
		top.scale = Vector3.ONE * clampf(r2 / 0.22, 0.8, 1.4)
		body.add_child(top)
		hat_node = top
		if not carrot:
			nose.material_override = ghost_material()
			ghosts.append(nose)
		if not hat:
			top.material_override = ghost_material()
			ghosts.append(top)
	elif n == 2 and not done:  # where the head goes
		var g := MeshInstance3D.new()
		g.mesh = ball_mesh()
		g.material_override = ghost_material()
		var gr := radii[1] * 0.75
		g.scale = Vector3.ONE * gr
		g.position.y = center_y(radii, 1) + (radii[1] + gr) * 0.8
		body.add_child(g)
		ghosts.append(g)
	if deco.vertex_count() > 0:
		body.add_child(MeshKit.instance(deco.build(), false))


## Head centre in world space (n == 3), for attaching the carrot and hat.
func head_world() -> Vector3:
	if radii.is_empty():
		return global_position
	return global_transform * Vector3(0.0, center_y(radii, radii.size() - 1), 0.0)


func wobble(dir: Vector2, amount: float = 1.0) -> void:
	wob = maxf(wob, amount)
	if dir.length() > 0.01:
		wob_dir = dir.normalized()


func _process(delta: float) -> void:
	if body == null:
		return
	t += delta
	wob = maxf(0.0, wob - delta * 1.6)
	pop_t = minf(1.0, pop_t + delta * 1.8)
	var w := wob * 0.22 * sin(t * 17.0)
	var tilt_x := wob_dir.y * w
	var tilt_z := -wob_dir.x * w
	var s := sin(pop_t * PI * 3.0) * (1.0 - pop_t) * 0.35
	var bounce := 0.0
	var spin := 0.0
	if done:
		var d := t * 1.0 + dance_seed
		bounce = absf(sin(d * 5.0)) * 0.14
		spin = sin(d * 2.5) * 0.45
		tilt_z += sin(d * 5.0) * 0.12
		for i in arms.size():
			arms[i].rotation.z = 0.5 + sin(d * 10.0 + i * PI) * 0.6
		if hat_node != null:
			hat_node.position.y = center_y(radii, 2) + radii[2] * 0.78 + absf(sin(d * 5.0 + 0.6)) * 0.08
	body.position.y = bounce
	body.rotation = Vector3(tilt_x, spin, tilt_z)
	body.scale = Vector3(1.0 + s, 1.0 - s, 1.0 + s)
	if not ghosts.is_empty():
		ghost_material().albedo_color.a = 0.22 + 0.18 * sin(Time.get_ticks_msec() * 0.006)
