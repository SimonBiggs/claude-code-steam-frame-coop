extends Node3D
## GRANNY BOO'S HOUSE: the ghost museum that grows. Every ghost the family catches is kept in a jar on
## Granny Boo's shelf in the hall (one row per kind, up to three jars each: after 1, 5 and 15 caught; a
## kind not caught yet is an empty dark jar), and the more ghosts are kept, the cosier her mansion gets
## (STEPS): fairy lights in the hall, a warm lamp in the library, bunting in the ballroom, paper lanterns
## everywhere, glowing windows with flower boxes, floating candles, then rainbow lights. Saved (main.gd
## save.data.jars / kept) and the same on every machine (the host sends kept + jars with the house).
## Granny Boo herself floats by her shelf: a friendly old ghost with spectacles, a bun and a pink shawl.
## Everything here hangs on the walls or the ceiling (nothing new on the floor: housegen.gd FIXED keeps
## the shelf clear of hiding places).

const World := preload("res://games/ghost_lantern/world.gd")

## Ghosts kept for each cosy step.
const STEPS: Array[int] = [4, 10, 18, 28, 40, 55, 75]
const KIND_ORDER: Array[String] = ["plain", "snoozy", "sprite", "spooker", "golden", "king"]
const SHELF_X := 0.0
const SHELF_Z := -7.65
const SHELF_W := 4.6
const BOARDS: Array[float] = [0.45, 1.1, 1.75]
const GRANNY_AT := Vector3(-3.0, 1.55, -6.7)

var main
var kept := 0
var jars := {}
var level := 0
var t := 0.0
var granny: Node3D
var granny_arm: Node3D
var wave_t := 0.0
var jar_ghosts: Array = []  # [Node3D, phase]
var jar_root: Node3D
var steps_built := {}
var bobbers: Array = []  # [Node3D, base_y, phase] floating candles, paper lanterns


## How many cosy steps `k` kept ghosts have unlocked.
static func cosy_level(k: int) -> int:
	var n := 0
	for s in STEPS:
		if k >= s:
			n += 1
	return n


## Jars of one kind on the shelf for `count` caught (0, then 1 / 2 / 3 after 1 / 5 / 15).
static func jars_shown(count: int) -> int:
	return 0 if count <= 0 else (1 if count < 5 else (2 if count < 15 else 3))


## How warm the house's light is (0..1), for main.gd _update_mood.
func warmth() -> float:
	return float(level) / float(STEPS.size())


func _ready() -> void:
	name = "Museum"
	_build_shelf()
	_build_granny()
	jar_root = Node3D.new()
	add_child(jar_root)
	apply(kept, jars, true)


## Show `k` kept ghosts and the jar counts. `quiet`: no sparkles (loading, joining).
func apply(k: int, j: Dictionary, quiet: bool = false) -> void:
	var new_jar := false
	for kind in KIND_ORDER:
		if jars_shown(int(j.get(kind, 0))) > jars_shown(int(jars.get(kind, 0))):
			new_jar = true
	var changed := k != kept or var_to_str(j) != var_to_str(jars) or jar_root.get_child_count() == 0
	kept = k
	jars = j.duplicate()
	if changed:
		_build_jars()
	var lv := cosy_level(kept)
	for i in lv:
		if not steps_built.has(i):
			steps_built[i] = true
			_build_step(i)
			if not quiet and main != null:
				main.burst(_step_spot(i), Color(1.0, 0.85, 0.5), 30, 0.08)
	level = lv
	if new_jar and not quiet:
		wave_t = 2.5
		if main != null:
			main.burst(Vector3(SHELF_X, 1.4, SHELF_Z + 0.4), Color(1.0, 0.9, 0.6), 24, 0.06)


func _process(delta: float) -> void:
	t += delta
	if granny != null:
		granny.position = GRANNY_AT + Vector3(sin(t * 0.7) * 0.15, sin(t * 1.6) * 0.08, 0.0)
		granny.rotation.z = sin(t * 0.9) * 0.06
		wave_t -= delta
		if granny_arm != null:
			granny_arm.rotation.z = (0.9 + sin(t * 10.0) * 0.5) if wave_t > 0.0 else 0.3 + sin(t * 1.2) * 0.1
	for jg in jar_ghosts:
		var n: Node3D = jg[0]
		n.position.y = float(jg[2]) + sin(t * 2.2 + float(jg[1])) * 0.025
		n.rotation.y = sin(t * 0.8 + float(jg[1])) * 0.6
	for b in bobbers:
		var n2: Node3D = b[0]
		n2.position.y = float(b[1]) + sin(t * 1.3 + float(b[2])) * 0.06


func _build_shelf() -> void:
	var wood := World.mat(Color(0.36, 0.2, 0.14))
	var dark := World.mat(Color(0.22, 0.12, 0.1))
	World.box(self, Vector3(SHELF_W + 0.2, 2.3, 0.08), Vector3(SHELF_X, 1.15, -7.96), dark, false)
	for y in BOARDS:
		World.box(self, Vector3(SHELF_W, 0.06, 0.5), Vector3(SHELF_X, y - 0.03, SHELF_Z), wood, false)
	for sx in [-1.0, 1.0]:
		World.box(self, Vector3(0.08, 2.3, 0.5), Vector3(SHELF_X + sx * SHELF_W * 0.5, 1.15, SHELF_Z), wood, false)
	World.box(self, Vector3(SHELF_W + 0.3, 0.1, 0.56), Vector3(SHELF_X, 2.33, SHELF_Z), wood, false)
	# One solid body for the whole shelf (players bump it; housegen.gd FIXED has the same rectangle).
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(SHELF_W + 0.3, 2.4, 0.55)
	cs.shape = shape
	body.add_child(cs)
	body.position = Vector3(SHELF_X, 1.2, -7.68)
	add_child(body)
	# A little brass lamp on top so the shelf is never quite dark.
	World.ball(self, 0.09, Vector3(SHELF_X + 1.7, 2.48, SHELF_Z), World.mat(Color(1.0, 0.8, 0.45), 4.0))


func _build_jars() -> void:
	for c in jar_root.get_children():
		c.queue_free()
	jar_ghosts.clear()
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.9, 1.0, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	glass.metallic_specular = 0.9
	var lid := World.mat(Color(0.75, 0.55, 0.25), 0.3, 0.4)
	var empty_glass := StandardMaterial3D.new()
	empty_glass.albedo_color = Color(0.3, 0.3, 0.4, 0.35)
	empty_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var cols := KIND_ORDER.size()
	var step := (SHELF_W - 0.3) / float(cols)
	for c in cols:
		var kind := KIND_ORDER[c]
		var n := jars_shown(int(jars.get(kind, 0)))
		var x := SHELF_X - (SHELF_W - 0.3) * 0.5 + step * (c + 0.5)
		var color := _kind_color(kind)
		for row in 3:
			var base := Vector3(x, BOARDS[row], SHELF_Z + 0.02)
			if row >= maxi(n, 1):
				continue
			var full := row < n
			var jar := World.cyl(jar_root, 0.16, 0.16, 0.42, base + Vector3(0, 0.21, 0), glass if full else empty_glass, 14)
			jar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			World.cyl(jar_root, 0.17, 0.17, 0.05, base + Vector3(0, 0.44, 0), lid if full else World.mat(Color(0.2, 0.18, 0.2)), 14)
			if not full:
				continue
			var g := Node3D.new()
			g.position = base + Vector3(0, 0.22, 0)
			jar_root.add_child(g)
			_jar_ghost(g, kind, color)
			jar_ghosts.append([g, float(c * 3 + row) * 1.7, g.position.y])
	# A soft glow for the whole shelf once there's anything in it.
	var any := false
	for k in jars:
		any = any or int(jars[k]) > 0
	if any:
		var l := OmniLight3D.new()
		l.light_color = Color(0.7, 1.0, 0.85)
		l.light_energy = 0.6 + 0.15 * float(jars.size())
		l.omni_range = 4.0
		l.shadow_enabled = false
		l.position = Vector3(SHELF_X, 1.3, SHELF_Z + 0.8)
		jar_root.add_child(l)


## A tiny glowing ghost in a jar, dressed like its kind.
func _jar_ghost(g: Node3D, kind: String, color: Color) -> void:
	var glow := World.mat(color, 2.2)
	var r := 0.09 if kind != "king" else 0.11
	World.ball(g, r, Vector3.ZERO, glow)
	World.cyl(g, r * 0.95, r * 0.35, r * 1.6, Vector3(0, -r * 0.8, 0), glow, 10)
	var eye := World.mat(Color(0.08, 0.06, 0.12))
	for sx in [-0.035, 0.035]:
		World.ball(g, 0.018, Vector3(sx, 0.015, r * 0.85), eye)
	match kind:
		"snoozy":  # nightcap
			var cap := World.cyl(g, 0.0, r * 0.9, r * 1.4, Vector3(0.02, r * 1.05, 0), World.mat(Color(0.35, 0.45, 1.0), 0.5), 10)
			cap.rotation.z = -0.5
		"sprite":  # bow
			for sx in [-1.0, 1.0]:
				World.ball(g, 0.035, Vector3(sx * 0.04, r * 0.9, 0), World.mat(Color(1.0, 0.35, 0.65), 0.8))
		"spooker":  # witch hat
			World.cyl(g, 0.0, r * 0.75, r * 1.5, Vector3(0, r * 1.4, 0), World.mat(Color(0.25, 0.12, 0.35), 0.3), 10)
			World.cyl(g, r * 1.3, r * 1.3, 0.012, Vector3(0, r * 0.75, 0), World.mat(Color(0.25, 0.12, 0.35), 0.3), 12)
		"golden":
			World.ball(g, 0.02, Vector3(0.1, 0.08, 0.05), World.mat(Color(1.0, 1.0, 0.7), 5.0))
		"king":  # crown
			World.cyl(g, r * 0.7, r * 0.7, r * 0.6, Vector3(0, r * 1.1, 0), World.mat(Color(1.0, 0.82, 0.25), 1.5), 8)


func _kind_color(kind: String) -> Color:
	var gk: Dictionary = preload("res://games/ghost_lantern/ghost.gd").KINDS
	return Color(gk[kind].color) if gk.has(kind) else Color(0.6, 1.0, 0.75)


## Granny Boo: a round old ghost with spectacles, a grey bun and a pink shawl, one arm to wave.
func _build_granny() -> void:
	granny = Node3D.new()
	granny.position = GRANNY_AT
	add_child(granny)
	var body := World.mat(Color(0.93, 0.92, 1.0), 0.7)
	World.ball(granny, 0.38, Vector3.ZERO, body)
	var skirt := World.cyl(granny, 0.37, 0.16, 0.75, Vector3(0, -0.4, 0), body, 16)
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	World.ball(granny, 0.15, Vector3(0, 0.38, -0.05), World.mat(Color(0.75, 0.75, 0.8), 0.2))  # the bun
	var shawl := World.cyl(granny, 0.4, 0.42, 0.18, Vector3(0, -0.12, 0), World.mat(Color(1.0, 0.55, 0.7), 0.3), 16)
	shawl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var eye := World.mat(Color(0.08, 0.06, 0.12))
	var rim := World.mat(Color(0.85, 0.65, 0.25), 1.0, 0.3)
	for sx in [-0.12, 0.12]:
		World.ball(granny, 0.045, Vector3(sx, 0.06, 0.34), eye)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.07
		tm.outer_radius = 0.09
		ring.mesh = tm
		ring.material_override = rim
		ring.rotation.x = PI / 2.0
		ring.position = Vector3(sx, 0.06, 0.36)
		granny.add_child(ring)
	World.box(granny, Vector3(0.08, 0.02, 0.02), Vector3(0, 0.07, 0.37), rim, false)
	var smile := MeshInstance3D.new()
	var sm := TorusMesh.new()
	sm.inner_radius = 0.05
	sm.outer_radius = 0.065
	smile.mesh = sm
	smile.material_override = World.mat(Color(0.5, 0.2, 0.3))
	smile.rotation.x = PI / 2.0
	smile.scale = Vector3(1.0, 1.0, 0.5)
	smile.position = Vector3(0, -0.07, 0.33)
	granny.add_child(smile)
	for sx in [-0.2, 0.2]:
		World.ball(granny, 0.05, Vector3(sx, -0.03, 0.3), World.mat(Color(1.0, 0.6, 0.65), 0.4))
	World.ball(granny, 0.09, Vector3(-0.38, -0.15, 0.05), body)  # the other hand, holding knitting
	World.ball(granny, 0.07, Vector3(-0.42, -0.2, 0.16), World.mat(Color(0.5, 0.75, 1.0), 0.5))
	granny_arm = Node3D.new()
	granny_arm.position = Vector3(0.33, -0.05, 0.0)
	granny.add_child(granny_arm)
	World.ball(granny_arm, 0.09, Vector3(0.14, 0.0, 0.05), body)
	var l := OmniLight3D.new()
	l.light_color = Color(0.85, 0.85, 1.0)
	l.light_energy = 0.5
	l.omni_range = 2.5
	l.shadow_enabled = false
	granny.add_child(l)


## Where the sparkles go when step i lights up.
func _step_spot(i: int) -> Vector3:
	return [Vector3(0, 3.4, -7.5), Vector3(-14.0, 1.4, -2.0), Vector3(14.0, 3.3, 0.5), Vector3(0, 3.3, 0.5),
		Vector3(0, 2.0, -7.6), Vector3(-14.0, 2.6, -2.0), Vector3(0, 3.5, 0)][clampi(i, 0, 6)]


const BULB_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
varying float tw;
void vertex() {
	tw = 0.65 + 0.35 * sin(TIME * 3.0 + float(INSTANCE_ID) * 1.7);
}
void fragment() {
	ALBEDO = COLOR.rgb * (1.6 + 1.4 * tw);
}
"""

var _bulb_x: Array[Transform3D] = []
var _bulb_c: Array[Color] = []


## A twinkling fairy light (collected into one MultiMesh per cosy step: one draw call).
func _bulb(_parent: Node3D, pos: Vector3, color: Color, r: float = 0.05) -> void:
	_bulb_x.append(Transform3D(Basis().scaled(Vector3.ONE * r * 2.0), pos))
	_bulb_c.append(color)


func _flush_bulbs(parent: Node3D) -> void:
	if _bulb_x.is_empty():
		return
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	parent.add_child(World._multimesh(sm, World.shader_mat(BULB_SHADER), _bulb_x, _bulb_c, []))
	_bulb_x = []
	_bulb_c = []


func _garland(parent: Node3D, a: Vector3, b: Vector3, colors: Array, count: int, sag: float = 0.35) -> void:
	for i in count:
		var f := float(i) / float(maxi(1, count - 1))
		var p := a.lerp(b, f)
		p.y -= sin(f * PI) * sag
		_bulb(parent, p, colors[i % colors.size()])


func _warm_light(parent: Node3D, pos: Vector3, energy: float, rng: float, color: Color = Color(1.0, 0.75, 0.45)) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	l.position = pos
	parent.add_child(l)


func _build_step(i: int) -> void:
	var root := Node3D.new()
	root.name = "Cosy%d" % i
	add_child(root)
	var warm: Array = [Color(1.0, 0.8, 0.4), Color(1.0, 0.6, 0.35), Color(1.0, 0.9, 0.6)]
	match i:
		0:  # fairy lights over Granny Boo's shelf and along the hall
			_garland(root, Vector3(-6.6, 3.9, -7.8), Vector3(6.6, 3.9, -7.8), warm, 28, 0.5)
			_garland(root, Vector3(-2.5, 2.7, -7.75), Vector3(2.5, 2.7, -7.75), warm, 11, 0.15)
			_warm_light(root, Vector3(0, 2.6, -6.6), 0.9, 6.0)
		1:  # a warm reading lamp and a rug in the library
			World.cyl(root, 0.02, 0.06, 0.45, Vector3(-13.4, 1.05, -2.2), World.mat(Color(0.75, 0.55, 0.25)), 8)
			World.cyl(root, 0.12, 0.22, 0.22, Vector3(-13.4, 1.35, -2.2), World.mat(Color(1.0, 0.8, 0.45), 2.0), 12)
			World.cyl(root, 2.4, 2.4, 0.02, Vector3(-11.5, 0.015, 1.5), World.mat(Color(0.6, 0.25, 0.2)), 24)
			World.cyl(root, 1.7, 1.7, 0.025, Vector3(-11.5, 0.018, 1.5), World.mat(Color(0.9, 0.7, 0.35)), 24)
			_warm_light(root, Vector3(-13.4, 1.6, -2.2), 1.6, 7.0)
		2:  # bunting across the ballroom
			var flags: Array = [Color(1.0, 0.4, 0.45), Color(1.0, 0.85, 0.35), Color(0.45, 0.85, 1.0), Color(0.6, 1.0, 0.55)]
			for line in [[Vector3(7.3, 3.8, -7.8), Vector3(20.8, 3.8, 7.8)], [Vector3(7.3, 3.8, 7.8), Vector3(20.8, 3.8, -7.8)]]:
				for k in 18:
					var f := float(k) / 17.0
					var p: Vector3 = (line[0] as Vector3).lerp(line[1], f)
					p.y -= sin(f * PI) * 0.6
					var flag := World.box(root, Vector3(0.28, 0.32, 0.02), p + Vector3(0, -0.16, 0), World.mat(flags[k % 4], 0.8), false)
					flag.rotation.y = atan2((line[1] - line[0]).x, (line[1] - line[0]).z) + PI / 2.0
					flag.rotation.z = PI / 4.0
			_warm_light(root, Vector3(14.0, 3.0, 0.0), 1.0, 9.0, Color(1.0, 0.85, 0.6))
		3:  # paper lanterns in every room
			var pl: Array = [Color(1.0, 0.45, 0.35), Color(1.0, 0.75, 0.3), Color(0.55, 0.8, 1.0), Color(0.9, 0.55, 1.0)]
			var k := 0
			for x in [-17.5, -10.5, -3.5, 3.5, 10.5, 17.5]:
				for z in [-3.5, 3.5]:
					var holder := Node3D.new()
					holder.position = Vector3(x, 3.4, z)
					root.add_child(holder)
					World.cyl(holder, 0.005, 0.005, 0.6, Vector3(0, 0.45, 0), World.mat(Color(0.2, 0.2, 0.2)), 4)
					var lan := World.ball(holder, 0.22, Vector3.ZERO, World.mat(pl[k % 4], 1.8), 1.2)
					lan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					bobbers.append([holder, 3.4, float(k)])
					k += 1
		4:  # the windows glow warm, with flower boxes
			for x in [-17.0, -11.0, -3.5, 3.5, 11.0, 17.0]:
				World.box(root, Vector3(1.3, 1.9, 0.02), Vector3(x, 2.2, -7.94), World.mat(Color(1.0, 0.75, 0.4), 1.2), false)
				World.box(root, Vector3(1.4, 0.18, 0.22), Vector3(x, 1.3, -7.78), World.mat(Color(0.45, 0.28, 0.18)), false)
				for f in 5:
					World.ball(root, 0.07, Vector3(x - 0.5 + f * 0.25, 1.44, -7.78), World.mat([Color(1.0, 0.4, 0.5), Color(1.0, 0.9, 0.3), Color(0.8, 0.5, 1.0)][f % 3], 0.8))
		5:  # floating candles in the library and the hall
			var k2 := 0
			for c in [[-15.5, -2.5], [-14.0, -1.2], [-12.5, -2.6], [-16.0, 1.0], [-12.0, 1.2], [-1.5, -1.5], [1.5, -1.5], [0.0, -3.0]]:
				var cn := Node3D.new()
				cn.position = Vector3(c[0], 2.7, c[1])
				root.add_child(cn)
				World.cyl(cn, 0.04, 0.045, 0.24, Vector3.ZERO, World.mat(Color(0.98, 0.95, 0.85)), 8)
				var fl := World.ball(cn, 0.035, Vector3(0, 0.16, 0), World.mat(Color(1.0, 0.75, 0.35), 6.0), 1.6)
				fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				bobbers.append([cn, 2.7, float(k2) * 1.3])
				k2 += 1
			_warm_light(root, Vector3(-14.0, 2.6, -1.0), 0.8, 6.0)
		6:  # rainbow fairy lights everywhere
			var rb: Array = [Color(1.0, 0.35, 0.35), Color(1.0, 0.65, 0.25), Color(1.0, 0.95, 0.35), Color(0.4, 0.9, 0.4), Color(0.4, 0.65, 1.0), Color(0.7, 0.45, 1.0)]
			_garland(root, Vector3(-20.8, 3.95, 7.8), Vector3(-7.3, 3.95, 7.8), rb, 22, 0.4)
			_garland(root, Vector3(-6.7, 3.95, 7.8), Vector3(6.7, 3.95, 7.8), rb, 22, 0.4)
			_garland(root, Vector3(7.3, 3.95, 7.8), Vector3(20.8, 3.95, 7.8), rb, 22, 0.4)
			_garland(root, Vector3(-20.8, 3.95, -7.8), Vector3(-7.3, 3.95, -7.8), rb, 22, 0.4)
			_garland(root, Vector3(7.3, 3.95, -7.8), Vector3(20.8, 3.95, -7.8), rb, 22, 0.4)
	_flush_bulbs(root)
