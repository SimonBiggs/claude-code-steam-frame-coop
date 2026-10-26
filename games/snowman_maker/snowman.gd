extends Node3D
## One snowman: a stack of 1-3 snowballs with a face, twig arms, carrot nose and hat, drawn from
## plain data (set_data) so the host and the TV machine build exactly the same thing.
## Wobbles when touched, pops when it grows, dances once it is finished.

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

const SNOW := Color(0.97, 0.98, 1.0)

var radii: Array[float] = []
var carrot := false
var hat := false  # wearing any hat
var hat_kind := 0  # 0 none, 1 top hat, 2 woolly hat, 3 crown (story.gd)
var ghost_kind := 1  # the hat the see-through guide shows (the visitor's wish)
var style: Array = []  # unlocked looks (story.gd UNLOCKS ids): scarf, buttons, gold_carrot, rainbow
var tint := Color.WHITE  # rainbow snow: a soft colour per snowman
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
	tint = Color.from_hsv(randf(), 0.22, 1.0)


## Rainbow snow: a soft pastel snow material (cached per hue step).
static func tinted_snow(c: Color) -> Material:
	var step := int(c.h * 8.0) % 8
	return ResCache.get_or_make("snowman_snow_tint_%d_v1" % step, func() -> Resource:
		var m := (snow_material() as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.albedo_color = Color.from_hsv(step / 8.0, 0.22, 1.0)
		m.emission = Color.from_hsv(step / 8.0, 0.35, 0.75)
		return m)


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


## A woolly hat with a bobble: base at the origin.
static func beanie_mesh() -> Mesh:
	return ResCache.get_or_make("snowman_beanie_v1", func() -> Resource:
		var b := MeshKit.Builder.new()
		var red := Color(0.9, 0.22, 0.28)
		b.cylinder(0.2, 0.21, 0.07, MeshKit.at(Vector3(0.0, 0.035, 0.0)), Color(0.97, 0.97, 1.0), 14)
		b.dome(0.19, MeshKit.at(Vector3(0.0, 0.06, 0.0), Vector3(1.0, 1.05, 1.0)), red)
		b.sphere(0.07, MeshKit.at(Vector3(0.0, 0.27, 0.0)), Color(0.97, 0.97, 1.0), 8)
		return b.build())


## A golden crown with jewels: base at the origin.
static func crown_mesh() -> Mesh:
	return ResCache.get_or_make("snowman_crown_v1", func() -> Resource:
		var b := MeshKit.Builder.new()
		var gold := Color(1.0, 0.8, 0.2)
		b.cylinder(0.17, 0.17, 0.1, MeshKit.at(Vector3(0.0, 0.05, 0.0)), gold, 14)
		for i in 5:
			var a := TAU * i / 5.0
			b.cone(0.05, 0.13, MeshKit.at(Vector3(cos(a) * 0.15, 0.16, sin(a) * 0.15)), gold, 6)
			b.sphere(0.025, MeshKit.at(Vector3(cos(a) * 0.15, 0.24, sin(a) * 0.15)), gold.lightened(0.3), 6)
		for i in 3:
			var a := -0.6 + i * 0.6 + PI * 0.5
			b.sphere(0.03, MeshKit.at(Vector3(cos(a) * 0.17, 0.05, sin(a) * 0.17)), [Color(0.9, 0.15, 0.3), Color(0.2, 0.5, 1.0), Color(0.2, 0.85, 0.4)][i], 6)
		return b.build())


## The hat mesh of a kind (1 top hat, 2 woolly hat, 3 crown).
static func hat_of(kind: int) -> Mesh:
	match kind:
		2:
			return beanie_mesh()
		3:
			return crown_mesh()
	return hat_mesh()


## The golden carrot (an unlock).
static func gold_carrot_mesh() -> Mesh:
	return ResCache.get_or_make("snowman_gcarrot_v1", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cone(0.05, 0.24, MeshKit.aim(Vector3(0.0, 0.0, 0.12), Vector3.BACK), Color(1.0, 0.82, 0.2), 8, true)
		b.cone(0.03, 0.06, MeshKit.aim(Vector3(0.0, 0.0, -0.02), Vector3.FORWARD), Color(0.3, 0.75, 0.2))
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

## new_hat: 0 none, else the hat kind. ghost: the hat kind the guide shows. looks: unlocked styles.
func set_data(new_radii: Array[float], new_carrot: bool, new_hat: int, new_done: bool, ghost: int = 1, looks: Array = []) -> void:
	var grew := new_radii.size() > radii.size() or (new_carrot and not carrot) or (new_hat > 0 and hat_kind == 0)
	var changed := new_radii != radii or new_carrot != carrot or new_hat != hat_kind or new_done != done \
		or (new_hat == 0 and ghost != ghost_kind) or looks != style
	radii = new_radii.duplicate()
	carrot = new_carrot
	hat_kind = new_hat
	hat = new_hat > 0
	ghost_kind = maxi(1, ghost)
	style = looks.duplicate()
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
		mi.material_override = snow_material() if not style.has("rainbow") else tinted_snow(tint)
		mi.scale = Vector3.ONE * radii[i]
		mi.position.y = center_y(radii, i)
		body.add_child(mi)
	var n := radii.size()
	var deco := MeshKit.Builder.new()
	var coal := Color(0.06, 0.06, 0.08)
	if n >= 2:
		var r1 := radii[1]
		var y1 := center_y(radii, 1)
		var sweets: Array[Color] = [Color(1.0, 0.3, 0.45), Color(1.0, 0.85, 0.2), Color(0.3, 0.75, 1.0)]
		for k in 3:  # buttons (sweeties once unlocked)
			var a := -0.45 + k * 0.42
			var bc: Color = sweets[k] if style.has("buttons") else coal
			deco.sphere(r1 * (0.12 if style.has("buttons") else 0.09), MeshKit.at(Vector3(0.0, y1 + sin(a) * r1, cos(a) * r1 * 0.98)), bc, 8)
		if style.has("scarf") and n >= 3:  # a scarf where the head meets the body
			var sy := center_y(radii, 1) + r1 * 0.8
			var sc := Color.from_hsv(fmod(tint.h + 0.5, 1.0) if style.has("rainbow") else 0.0, 0.75, 0.95)
			deco.torus(r1 * 0.62, r1 * 0.12, MeshKit.at(Vector3(0.0, sy, 0.0)), sc)
			deco.box(Vector3(r1 * 0.22, r1 * 0.7, r1 * 0.08), MeshKit.at(Vector3(r1 * 0.35, sy - r1 * 0.35, r1 * 0.62), Vector3.ONE, Vector3(0.3, 0.0, 0.15)), sc)
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
		nose.mesh = gold_carrot_mesh() if style.has("gold_carrot") else carrot_mesh()
		nose.position = Vector3(0.0, y2 + r2 * 0.02, r2 * 0.92)
		nose.scale = Vector3.ONE * clampf(r2 / 0.22, 0.8, 1.4)
		body.add_child(nose)
		var top := MeshInstance3D.new()
		top.mesh = hat_of(hat_kind if hat_kind > 0 else ghost_kind)
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
