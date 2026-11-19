extends Node3D
## SKY BOTS: builds one island (levelgen.gd's dictionary) on every machine and keeps it moving: floating platforms
## (one mesh for all the still ones), movers and lifts (AnimatableBody3D: robots ride them), bolts (one MultiMesh),
## checkpoint flags, GRUMBLE bots, ZAP PADS (their tell is a flashing warn ring on core/warn_rings.gd, from the level
## clock, so every machine shows it at the same moment), the secret room with its cracked wall and the gold gear, and
## the SPARK on its pedestal (the goal).
## The host / local machine runs the clock (t), the grumbles and the held lifts; the TV machine gets them from the
## snapshot (pack / unpack).

const G := preload("res://games/sky_bots/levelgen.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Contrast := preload("res://core/contrast.gd")
const WarnRings := preload("res://core/warn_rings.gd")
const SeasonKit := preload("res://core/season_kit.gd")

## Each theme's floors (top, sides, the rock under a floating island); meadow tops follow the season.
const THEME := {
	"meadow": {"top": Color(0.42, 0.76, 0.34), "side": Color(0.58, 0.4, 0.25), "rock": Color(0.52, 0.44, 0.4)},
	"gears": {"top": Color(0.44, 0.52, 0.66), "side": Color(0.34, 0.37, 0.45), "rock": Color(0.3, 0.32, 0.4)},
	"cove": {"top": Color(0.93, 0.82, 0.58), "side": Color(0.64, 0.53, 0.42), "rock": Color(0.5, 0.45, 0.43)},
	"snow": {"top": Color(0.68, 0.83, 0.97), "side": Color(0.42, 0.5, 0.7), "rock": Color(0.4, 0.44, 0.56)},  ## (icy blue: white snow vanished on the clouds)
	"jungle": {"top": Color(0.3, 0.58, 0.42), "side": Color(0.45, 0.32, 0.22), "rock": Color(0.36, 0.4, 0.32)},
	"clock": {"top": Color(0.62, 0.45, 0.56), "side": Color(0.72, 0.56, 0.3), "rock": Color(0.42, 0.36, 0.4)},
}
const SPRING_COLOR := Color(1.0, 0.3, 0.55)  ## spring pads: hot pink coils with a white top
const FAN_COLOR := Color(0.4, 0.85, 1.0)  ## wind fans: a sky-blue fan down in the gap, puffs rising
const BELT_TOP := Color(0.22, 0.22, 0.27)  ## belts: dark rubber with bright arrows that run the belt's way
const BELT_ARROW := Color(1.0, 0.78, 0.2)
const BOX_COLOR := Color(0.95, 0.55, 0.2)  ## bot boxes: orange crates with a window (a little bot waves inside)
const TINY_COLORS: Array[Color] = [Color(0.5, 0.85, 1.0), Color(1.0, 0.6, 0.8), Color(0.6, 1.0, 0.55), Color(1.0, 0.85, 0.35),
	Color(0.8, 0.65, 1.0), Color(1.0, 0.55, 0.4)]
const MEADOW_TOPS := {"spring": Color(0.42, 0.76, 0.34), "summer": Color(0.36, 0.66, 0.28),
	"autumn": Color(0.62, 0.64, 0.28), "winter": Color(0.86, 0.91, 0.98)}
const MOVER_TOP := Color(0.98, 0.62, 0.25)  ## movers: warm orange, so kids see they're different
const LIFT_TOP := Color(0.62, 0.45, 0.95)  ## lifts: purple with a yellow handle the VR giant grabs
const HANDLE := Color(1.0, 0.86, 0.25)
const BOLT_COLOR := Color(1.0, 0.8, 0.25)
const GEAR_COLOR := Color(1.0, 0.72, 0.12)
const SPARK_COLOR := Color(0.55, 0.95, 1.0)
const GRUMBLE_COLOR := Color(0.85, 0.3, 0.32)
const ZAP_COLOR := Color(1.0, 0.95, 0.2)
const WARN_COLOR := Color(1.0, 0.35, 0.2)  ## a grumble's charge line
const FLAG_COLOR := Color(1.0, 0.35, 0.55)
const CRACK_COLOR := Color(0.78, 0.68, 0.55)

var lv: Dictionary = {}
var theme := "meadow"
var season := "spring"
var t := 0.0  ## the level clock (host runs it, the TV machine follows the snapshot)
var host := true
var movers := {}  ## plat index -> AnimatableBody3D
var mover_pos := {}  ## plat index -> Vector3 (where it should be now)
var lift_hold := {}  ## host: plat index -> top y the giant's hand holds it at
var lift_blend := {}  ## host: plat index -> [y, weight] easing back to its own cycle after a hand lets go
var bolt_mm: MultiMeshInstance3D
var bolt_bits := PackedInt32Array()
var flags: Array[Node3D] = []
var cp_lit := 0
var grumbles: Array = []  ## [{node, x, dir, st, tt, cool, gone}]
var zap_nodes: Array[Node3D] = []
var zap_was: Array[int] = []
var rings: WarnRings
var wall: StaticBody3D
var wall_broken := false
var gear: Node3D
var gear_got := false
var goal: Node3D
var goal_on := true
var springs: Array[Node3D] = []
var spring_t: Array[float] = []  ## seconds since each spring last boinged (its squash)
var fans: Array[Node3D] = []
var belt_arrows: Array = []  ## [{node, dir, x0, len}] arrows that run along each belt
var boxes: Array[Node3D] = []
var box_bits := 0
var jobs_prog: Array = []  ## per GIANT JOB: [progress of each piece] (0 shut .. 1 open; host runs them, the snapshot carries them)
var job_btn: Array = []  ## per job: its robot BUTTON is awake (no VR giant, or the giant took too long)
var job_held: Array = []  ## per job: where the giant's hand holds it (the boulder), INF = not held
var job_open_was: Array = []  ## per job: was open last frame (a burst when it opens)
var job_nodes: Array = []  ## per job: {"pieces": [Node3D], "cols": [CollisionShape3D], "block": Node3D, "block_col": CollisionShape3D, "btn": Node3D, "crank": Node3D}
var gate_job := {}  ## gate plat index -> job index
var backdrop: Node3D
var spinners: Array = []  ## [Node3D, axis, speed]: windmill sails, factory gears, clock hands in the backdrop
var boings := 0  ## springs boinged on this island, seen here (every machine: its own robots, the others' events)  ## the bot boxes opened (host -> state "boxes")
var _static: StaticBody3D


func build(level: Dictionary, the_theme: String, the_season: String, is_host: bool) -> void:
	for c in get_children():
		c.queue_free()
	lv = level
	theme = the_theme
	season = the_season
	host = is_host
	t = 0.0
	movers.clear()
	mover_pos.clear()
	lift_hold.clear()
	lift_blend.clear()
	flags.clear()
	grumbles.clear()
	zap_nodes.clear()
	zap_was.clear()
	wall_broken = false
	gear_got = false
	cp_lit = 0
	springs.clear()
	spring_t.clear()
	fans.clear()
	belt_arrows.clear()
	boxes.clear()
	box_bits = 0
	jobs_prog.clear()
	job_btn.clear()
	job_held.clear()
	job_open_was.clear()
	job_nodes.clear()
	gate_job.clear()
	spinners.clear()
	backdrop = null
	rings = WarnRings.new()
	add_child(rings)
	if lv.is_empty():
		return
	_static = StaticBody3D.new()
	_static.collision_layer = 1
	add_child(_static)
	var b := MeshKit.Builder.new()
	var plats: Array = lv.plats
	for i in plats.size():
		var p: Dictionary = plats[i]
		if p.has("b"):
			_make_mover(i, p)
			continue
		if String(p.k) == "gate":
			continue  # (a giant job's bridge piece: its own node, _jobs)
		_floor_mesh(b, p, Vector3.INF)
		_box_shape(_static, p.c, p.s, String(p.k) == "arena")
	_secret_room(b)
	var mi := MeshKit.instance(b.build())
	add_child(mi)
	_bolts()
	_flags()
	_grumbles()
	_zaps()
	_gadgets()
	_boxes()
	_goal()
	_jobs()
	_backdrop()
	set_bolts(PackedInt32Array())


func top_color() -> Color:
	if theme == "meadow":
		return MEADOW_TOPS.get(season, MEADOW_TOPS.spring)
	return THEME[theme].top


## One floating floor: a slab with a top, then a rock cone hanging under it (a toy sky island).
func _floor_mesh(b: MeshKit.Builder, p: Dictionary, at: Vector3) -> void:
	var c: Vector3 = (p.c as Vector3) if at == Vector3.INF else at
	var s: Vector2 = p.s
	var th: Dictionary = THEME[theme]
	var top := top_color()
	var kind := String(p.k)
	if kind == "mover":
		top = MOVER_TOP
	elif kind == "lift":
		top = LIFT_TOP
	elif kind == "belt":
		top = BELT_TOP
	if kind == "arena":
		var r := s.x * 0.5
		b.cylinder(r, r, 0.25, MeshKit.at(c + Vector3(0, -0.125, 0)), top, 28)
		b.cylinder(r, r - 0.2, G.THICK - 0.25, MeshKit.at(c + Vector3(0, -0.25 - (G.THICK - 0.25) * 0.5, 0)), th.side, 28)
		b.cone(r - 0.3, 3.5, MeshKit.at(c + Vector3(0, -G.THICK - 1.75, 0), Vector3.ONE, Vector3(PI, 0, 0)), th.rock, 12)
		b.torus(r - 0.15, 0.12, MeshKit.at(c + Vector3(0, 0.02, 0)), Color(1.0, 0.9, 0.7), 28, 6)
		return
	b.box(Vector3(s.x, 0.22, s.y), MeshKit.at(c + Vector3(0, -0.11, 0)), top)
	b.box(Vector3(s.x - 0.08, G.THICK - 0.22, s.y - 0.08), MeshKit.at(c + Vector3(0, -0.22 - (G.THICK - 0.22) * 0.5, 0)), th.side)
	var cr := minf(s.x, s.y) * 0.5
	var depth := clampf(minf(s.x, s.y) * 0.7, 0.8, 3.0)
	b.cone(cr, depth, MeshKit.at(c + Vector3(0, -G.THICK - depth * 0.5, 0), Vector3(s.x / (2.0 * cr), 1.0, s.y / (2.0 * cr)), Vector3(PI, 0, 0)), th.rock, 8)
	if kind == "mover" or kind == "lift":  # a bright rim: this one moves
		for sz in [-1.0, 1.0]:
			b.box(Vector3(s.x, 0.06, 0.1), MeshKit.at(c + Vector3(0, 0.02, sz * (s.y * 0.5 - 0.05))), HANDLE)
	elif theme == "gears":
		b.box(Vector3(s.x, 0.04, 0.12), MeshKit.at(c + Vector3(0, 0.01, s.y * 0.5 - 0.1)), HANDLE)
	if kind == "solid" or kind == "side":
		_dressing(b, c, s)
	elif kind == "belt":  # rollers at both ends, bright side rails
		for e in [-1.0, 1.0]:
			b.cylinder(0.16, 0.16, s.y, MeshKit.at(c + Vector3(e * s.x * 0.5, -0.12, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.6, 0.62, 0.7), 10)
		for sz in [-1.0, 1.0]:
			b.box(Vector3(s.x, 0.08, 0.1), MeshKit.at(c + Vector3(0, 0.03, sz * (s.y * 0.5 - 0.05))), BELT_ARROW.darkened(0.2))


## A few little things on a still floor's back edge and sides (no collision): flowers (snow lumps in winter) on the
## meadow, gear wheels on the gear works' sides, shells and starfish in the cove.
func _dressing(b: MeshKit.Builder, c: Vector3, s: Vector2) -> void:
	var n := int(s.x / 2.5)
	for k in n:
		var x := c.x - s.x * 0.5 + 1.0 + (s.x - 2.0) * (float(k) + 0.5) / float(n)
		var z := c.z - s.y * 0.5 + 0.22
		var hue := fposmod(x * 0.37, 1.0)
		match theme:
			"meadow":
				if season == "winter":
					b.sphere(0.2, MeshKit.at(Vector3(x, c.y, z), Vector3(1.2, 0.5, 1.0)), Color(0.97, 0.98, 1.0), 8)
				else:
					b.cylinder(0.02, 0.02, 0.3, MeshKit.at(Vector3(x, c.y + 0.15, z)), Color(0.3, 0.6, 0.25), 4)
					b.sphere(0.09, MeshKit.at(Vector3(x, c.y + 0.32, z)), Color.from_hsv(hue, 0.55, 1.0), 8)
			"gears":
				b.cylinder(0.3, 0.3, 0.08, MeshKit.at(Vector3(x, c.y - 0.45, c.z + s.y * 0.5 + 0.04), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.75, 0.6, 0.25), 8)
			"cove":
				if k % 2 == 0:
					b.dome(0.14, MeshKit.at(Vector3(x, c.y, z)), Color(1.0, 0.75, 0.75), 8)
				else:
					b.star(5, 0.14, 0.06, 0.04, MeshKit.at(Vector3(x, c.y + 0.02, z), Vector3.ONE, Vector3(-PI * 0.5, 0, 0)), Color(1.0, 0.55, 0.35))
			"snow":  # little snowy pine trees and icicles under the edge
				if k % 2 == 0:
					b.cylinder(0.05, 0.06, 0.25, MeshKit.at(Vector3(x, c.y + 0.12, z)), Color(0.45, 0.32, 0.22), 5)
					b.cone(0.28, 0.6, MeshKit.at(Vector3(x, c.y + 0.5, z)), Color(0.25, 0.5, 0.42), 7)
					b.cone(0.16, 0.3, MeshKit.at(Vector3(x, c.y + 0.78, z)), Color(0.95, 0.97, 1.0), 7)
				b.cone(0.07, 0.35, MeshKit.at(Vector3(x + 0.4, c.y - 0.4, c.z + s.y * 0.5 - 0.05), Vector3.ONE, Vector3(PI, 0, 0)), Color(0.75, 0.9, 1.0), 5)
			"jungle":  # big leaves and a vine hanging off the front edge
				for a in [-0.6, 0.0, 0.6]:
					b.ellipsoid(Vector3(0.1, 0.03, 0.32), MeshKit.at(Vector3(x, c.y + 0.25, z), Vector3.ONE, Vector3(0.7, a, 0)), Color(0.25, 0.65, 0.3).lightened(absf(a) * 0.15), 6)
				b.cylinder(0.025, 0.025, 0.9, MeshKit.at(Vector3(x + 0.6, c.y - 0.45, c.z + s.y * 0.5 + 0.02)), Color(0.3, 0.55, 0.25), 4)
				b.sphere(0.08, MeshKit.at(Vector3(x + 0.6, c.y - 0.9, c.z + s.y * 0.5 + 0.02)), Color(1.0, 0.5, 0.3 + hue * 0.3), 6)
			"clock":  # brass cogs turning on the front edge and little clock faces at the back
				b.cylinder(0.32, 0.32, 0.08, MeshKit.at(Vector3(x, c.y - 0.45, c.z + s.y * 0.5 + 0.04), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.85, 0.68, 0.3), 10)
				if k % 2 == 0:
					b.cylinder(0.22, 0.22, 0.06, MeshKit.at(Vector3(x, c.y + 0.3, z), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.97, 0.95, 0.88), 14)
					b.box(Vector3(0.03, 0.15, 0.02), MeshKit.at(Vector3(x, c.y + 0.36, z + 0.04)), Color(0.2, 0.2, 0.25))
					b.box(Vector3(0.1, 0.03, 0.02), MeshKit.at(Vector3(x + 0.04, c.y + 0.3, z + 0.04)), Color(0.2, 0.2, 0.25))


func _box_shape(body: Node3D, c: Vector3, s: Vector2, round_one: bool) -> void:
	var cs := CollisionShape3D.new()
	if round_one:
		var cy := CylinderShape3D.new()
		cy.radius = s.x * 0.5
		cy.height = G.THICK
		cs.shape = cy
	else:
		var bs := BoxShape3D.new()
		bs.size = Vector3(s.x, G.THICK, s.y)
		cs.shape = bs
	cs.position = c + Vector3(0, -G.THICK * 0.5, 0)
	body.add_child(cs)


func _make_mover(i: int, p: Dictionary) -> void:
	var body := AnimatableBody3D.new()
	body.collision_layer = 1
	body.sync_to_physics = true
	add_child(body)
	var b := MeshKit.Builder.new()
	_floor_mesh(b, p, Vector3.ZERO)
	if String(p.k) == "lift":  # the handle the VR giant grabs (on the giant's side, +Z)
		var s: Vector2 = p.s
		b.cylinder(0.12, 0.12, 0.7, MeshKit.at(Vector3(0, 0.35, s.y * 0.5 + 0.15)), HANDLE, 8)
		b.sphere(0.26, MeshKit.at(Vector3(0, 0.8, s.y * 0.5 + 0.15)), HANDLE, 12, true)
	body.add_child(MeshKit.instance(b.build()))
	_box_shape(body, Vector3.ZERO, p.s, false)
	body.position = G.plat_at(p, 0.0)
	movers[i] = body
	mover_pos[i] = body.position


## Springs (a pink coil with a white top that squashes when it throws), wind fans (a fan in a ring down in the gap,
## its blades spinning, puffs rising to the top of the updraft) and the arrows that run along each belt.
func _gadgets() -> void:
	for sp in lv.get("springs", []):
		var n := Node3D.new()
		n.position = sp.pos
		add_child(n)
		var top := Node3D.new()
		top.name = "Top"
		n.add_child(top)
		var b := MeshKit.Builder.new()
		for k in 4:
			b.torus(G.SPRING_R * 0.7, 0.06, MeshKit.at(Vector3(0, 0.08 + k * 0.1, 0)), SPRING_COLOR, 16, 5)
		b.cylinder(G.SPRING_R, G.SPRING_R, 0.1, MeshKit.at(Vector3(0, 0.47, 0)), Color(0.97, 0.97, 1.0), 16)
		b.star(5, 0.22, 0.1, 0.03, MeshKit.at(Vector3(0, 0.53, 0), Vector3.ONE, Vector3(-PI * 0.5, 0, 0)), SPRING_COLOR, true)
		var mi := MeshKit.instance(b.build(), false)
		Contrast.outline(mi, Contrast.OUTLINE)
		top.add_child(mi)
		springs.append(n)
		spring_t.append(9.0)
	for f in lv.get("fans", []):
		var n := Node3D.new()
		var fy := float(f.y) + 0.6
		n.position = Vector3((float(f.x0) + float(f.x1)) * 0.5, fy, 0.0)
		add_child(n)
		var b := MeshKit.Builder.new()
		var r := minf(float(f.w) * 0.5, 1.3)
		b.torus(r, 0.12, MeshKit.at(Vector3.ZERO), Color(0.85, 0.87, 0.92), 20, 6)
		b.cylinder(0.12, 0.2, 1.6, MeshKit.at(Vector3(0, -0.8, 0)), Color(0.6, 0.62, 0.7), 8)
		n.add_child(MeshKit.instance(b.build(), false))
		var blades := Node3D.new()
		blades.name = "Blades"
		n.add_child(blades)
		var bb := MeshKit.Builder.new()
		for k in 4:
			bb.box(Vector3(r * 0.9, 0.04, 0.3), MeshKit.at(Vector3(cos(TAU * k / 4.0) * r * 0.45, 0, sin(TAU * k / 4.0) * r * 0.45), Vector3.ONE, Vector3(0.3, -TAU * k / 4.0, 0)), FAN_COLOR)
		bb.sphere(0.15, MeshKit.at(Vector3.ZERO), Color(1.0, 0.85, 0.3), 8)
		blades.add_child(MeshKit.instance(bb.build(), false))
		# Puffs rising through the whole updraft (so kids see where the wind is).
		var cp := CPUParticles3D.new()
		cp.amount = 24
		cp.lifetime = 1.6
		cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		cp.emission_box_extents = Vector3((float(f.x1) - float(f.x0)) * 0.5, 0.1, float(f.w) * 0.4)
		cp.direction = Vector3.UP
		cp.spread = 5.0
		cp.gravity = Vector3.ZERO
		cp.initial_velocity_min = (float(f.top) - fy) / 1.6
		cp.initial_velocity_max = cp.initial_velocity_min * 1.1
		cp.scale_amount_min = 0.6
		cp.scale_amount_max = 1.2
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		sm.radial_segments = 6
		sm.rings = 3
		sm.material = MeshKit.material(Color(1.0, 1.0, 1.0, 0.7))
		cp.mesh = sm
		n.add_child(cp)
		fans.append(n)
	for bt in lv.get("belts", []):
		var p: Dictionary = (lv.plats as Array)[int(bt.p)]
		var c: Vector3 = p.c
		var s: Vector2 = p.s
		var holder := Node3D.new()
		add_child(holder)
		var ab := MeshKit.Builder.new()
		var d := float(bt.dir)
		ab.polygon(PackedVector2Array([Vector2(0.3 * d, 0.0), Vector2(-0.1 * d, 0.35), Vector2(-0.1 * d, 0.15), Vector2(-0.3 * d, 0.15),
			Vector2(-0.3 * d, -0.15), Vector2(-0.1 * d, -0.15), Vector2(-0.1 * d, -0.35)]), 0.02, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(-PI * 0.5, 0, 0)), BELT_ARROW, true)
		var am := ab.build()
		var count := int(s.x / 1.4)
		var nodes: Array = []
		for k in count:
			var mi := MeshKit.instance(am, false)
			holder.add_child(mi)
			nodes.append(mi)
		belt_arrows.append({"nodes": nodes, "dir": d, "x0": c.x - s.x * 0.5 + 0.35, "len": s.x - 0.7, "y": c.y + 0.02, "z": c.z})


## A bot box: an orange crate with a round window, a little bot inside waving (and a sparkle on top).
func _boxes() -> void:
	for i in (lv.get("boxes", []) as Array).size():
		var bx: Dictionary = lv.boxes[i]
		var n := Node3D.new()
		n.position = bx.pos
		add_child(n)
		var b := MeshKit.Builder.new()
		b.rounded_box(Vector3(0.8, 0.8, 0.8), 0.08, MeshKit.at(Vector3(0, 0.4, 0)), BOX_COLOR)
		for e in [-1.0, 1.0]:
			b.box(Vector3(0.84, 0.08, 0.84), MeshKit.at(Vector3(0, 0.4 + e * 0.3, 0)), BOX_COLOR.darkened(0.3))
		for k in 4:  # a round window on every side (a little bot peeks out)
			var a := TAU * k / 4.0
			b.cylinder(0.24, 0.24, 0.04, MeshKit.at(Vector3(sin(a) * 0.41, 0.42, cos(a) * 0.41), Vector3.ONE, Vector3(PI * 0.5, a, 0)), Color(0.6, 0.85, 1.0), 14)
		b.sphere(0.1, MeshKit.at(Vector3(0, 0.95, 0)), Color(1.0, 0.9, 0.35), 8, true)
		var mi := MeshKit.instance(b.build(), false)
		Contrast.outline(mi, Contrast.OUTLINE)
		mi.name = "Crate"
		n.add_child(mi)
		var tiny := MeshKit.instance(tiny_mesh(TINY_COLORS[i % TINY_COLORS.size()]), false)
		tiny.name = "Tiny"
		tiny.position = Vector3(0, 0.25, 0.1)
		n.add_child(tiny)
		boxes.append(n)


## A LITTLE BOT: a round head on a tiny body, one antenna, big glowing eyes (in Gizmo Town too: hub.gd).
static func tiny_mesh(col: Color) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.rounded_box(Vector3(0.26, 0.22, 0.22), 0.07, MeshKit.at(Vector3(0, 0.12, 0)), col)
	b.sphere(0.17, MeshKit.at(Vector3(0, 0.36, 0)), Color(0.88, 0.9, 0.95), 10)
	b.rounded_box(Vector3(0.22, 0.12, 0.04), 0.03, MeshKit.at(Vector3(0, 0.37, 0.15)), Color(0.1, 0.14, 0.22))
	b.sphere(0.035, MeshKit.at(Vector3(-0.05, 0.38, 0.17)), Color(0.45, 1.0, 0.95), 6, true)
	b.sphere(0.035, MeshKit.at(Vector3(0.05, 0.38, 0.17)), Color(0.45, 1.0, 0.95), 6, true)
	b.cylinder(0.012, 0.012, 0.1, MeshKit.at(Vector3(0, 0.56, 0)), Color(0.6, 0.62, 0.66), 4)
	b.sphere(0.04, MeshKit.at(Vector3(0, 0.62, 0)), col, 6, true)
	return b.build()


func box_open(i: int) -> bool:
	return (box_bits >> i) & 1 == 1


## Every machine: which bot boxes are open (bits); a newly opened one bursts: the crate pops away, the little bot hops
## out and waves.
func set_boxes(bits: int) -> void:
	for i in boxes.size():
		var was := box_open(i)
		var now := (bits >> i) & 1 == 1
		var crate: Node3D = boxes[i].get_node("Crate")
		var tiny: Node3D = boxes[i].get_node("Tiny")
		crate.visible = not now
		if now and not was:
			tiny.position = Vector3(0, 0.0, 0.3)
			var tw := create_tween()
			tw.tween_property(tiny, "position", Vector3(0, 1.0, 0.5), 0.3).set_ease(Tween.EASE_OUT)
			tw.tween_property(tiny, "position", Vector3(0, 0.0, 0.7), 0.3).set_ease(Tween.EASE_IN)
		elif now:
			tiny.position = Vector3(0, 0.0, 0.7)
	box_bits = bits


## The bot box near point p (closed ones; -1 none).
func box_near(p: Vector3, r: float) -> int:
	var bl: Array = lv.get("boxes", [])
	for i in bl.size():
		var bp: Vector3 = (bl[i] as Dictionary).pos
		if not box_open(i) and Vector2(p.x - bp.x, p.z - bp.z).length() < r and p.y > bp.y - 0.6 and p.y < bp.y + 1.6:
			return i
	return -1


## Every machine: spring i boinged (its top squashes and springs back).
func spring_boing(i: int) -> void:
	boings += 1
	if i >= 0 and i < spring_t.size():
		spring_t[i] = 0.0


## The lift's handle (world), for the giant's hand.
func handle_point(i: int) -> Vector3:
	var p: Dictionary = (lv.plats as Array)[i]
	var s: Vector2 = p.s
	return (movers[i] as Node3D).position + Vector3(0, 0.8, s.y * 0.5 + 0.15)


func lifts() -> Array:
	var out: Array = []
	for i in movers:
		if String(((lv.plats as Array)[i] as Dictionary).k) == "lift":
			out.append(i)
	return out


## A platform's top-centre now (movers where they are this frame).
func plat_pos(i: int) -> Vector3:
	if movers.has(i):
		return (movers[i] as Node3D).position
	return ((lv.plats as Array)[i] as Dictionary).c


## The platform under point p right now (movers where they are this frame): its top within `up` above / `down`
## below p.y, -1 none.
func support(p: Vector3, up: float = 0.35, down: float = 0.6, margin: float = 0.0) -> int:
	var plats: Array = lv.get("plats", [])
	var best := -1
	var by := -INF
	for i in plats.size():
		var pl: Dictionary = plats[i]
		if gate_job.has(i) and not job_open(int(gate_job[i])):
			continue  # (a shut bridge isn't a floor yet)
		var c := plat_pos(i)
		var sz: Vector2 = pl.s
		if absf(p.x - c.x) > sz.x * 0.5 + margin or absf(p.z - c.z) > sz.y * 0.5 + margin:
			continue
		if String(pl.k) == "arena" and Vector2(p.x - c.x, p.z - c.z).length() > sz.x * 0.5 + margin:
			continue
		if c.y <= p.y + up and c.y >= p.y - down and c.y > by:
			by = c.y
			best = i
	return best


# --- Bolts, flags, the secret, the goal ------------------------------------------------------------------------

func _bolts() -> void:
	var b := MeshKit.Builder.new()
	b.prism(6, 0.2, 0.12, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), BOLT_COLOR)
	b.cylinder(0.09, 0.09, 0.14, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), BOLT_COLOR.darkened(0.45), 8)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = b.build()
	mm.instance_count = (lv.bolts as Array).size()
	bolt_mm = MultiMeshInstance3D.new()
	bolt_mm.multimesh = mm
	bolt_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolt_mm.material_override = MeshKit.vertex_material()
	Contrast.outline(bolt_mm, Contrast.OUTLINE)
	add_child(bolt_mm)


func bolt_taken(k: int) -> bool:
	var w := k >> 5
	return w < bolt_bits.size() and (bolt_bits[w] >> (k & 31)) & 1 == 1


func set_bolts(bits: PackedInt32Array) -> void:
	bolt_bits = bits


## Which bolt is within reach of point p (-1 none).
func bolt_at(p: Vector3, r: float = G.TOUCH) -> int:
	var bolts: Array = lv.bolts
	for k in bolts.size():
		if not bolt_taken(k) and (bolts[k] as Vector3).distance_to(p) < r:
			return k
	return -1


func bolts_left() -> int:
	var n := 0
	for k in (lv.bolts as Array).size():
		n += 0 if bolt_taken(k) else 1
	return n


func _flags() -> void:
	var cps: Array = lv.cps
	for k in cps.size():
		var f := Node3D.new()
		f.position = (cps[k][1] as Vector3) + Vector3(0, 0, -float((((lv.plats as Array)[int(cps[k][0])] as Dictionary).s as Vector2).y) * 0.5 + 0.3)
		add_child(f)
		var b := MeshKit.Builder.new()
		b.cylinder(0.05, 0.06, 1.8, MeshKit.at(Vector3(0, 0.9, 0)), Color(0.95, 0.95, 0.98), 6)
		b.sphere(0.1, MeshKit.at(Vector3(0, 1.85, 0)), Color(1.0, 0.85, 0.3), 8)
		f.add_child(MeshKit.instance(b.build(), false))
		var cloth := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, 0.45, 0.04)
		cloth.mesh = bm
		cloth.material_override = MeshKit.material(Color(0.6, 0.62, 0.68))
		cloth.position = Vector3(0.38, 1.55, 0)
		cloth.name = "Cloth"
		f.add_child(cloth)
		flags.append(f)


## Flags up to k glow in the flag colour (the team reached them).
func light_flags(k: int) -> void:
	cp_lit = k
	for i in flags.size():
		var cloth: MeshInstance3D = flags[i].get_node("Cloth")
		cloth.material_override = MeshKit.material(FLAG_COLOR if i <= k else Color(0.6, 0.62, 0.68), 0.4 if i <= k else 0.0)


func _secret_room(b: MeshKit.Builder) -> void:
	var sec: Dictionary = lv.secret
	if sec.is_empty():
		return
	var room: Vector3 = sec.room
	var hx := G.ROOM.x * 0.5
	var hz := G.ROOM.z * 0.5
	var h := G.ROOM.y
	var wallc := Color(0.82, 0.74, 0.62) if theme != "gears" else Color(0.55, 0.6, 0.7)
	# Back, sides and roof (solid), the front is the cracked wall.
	var parts := [[Vector3(0, h * 0.5, -hz - 0.15), Vector3(G.ROOM.x + 0.6, h, 0.3)],
		[Vector3(-hx - 0.15, h * 0.5, 0), Vector3(0.3, h, G.ROOM.z + 0.6)],
		[Vector3(hx + 0.15, h * 0.5, 0), Vector3(0.3, h, G.ROOM.z + 0.6)],
		[Vector3(0, h + 0.15, 0), Vector3(G.ROOM.x + 0.9, 0.3, G.ROOM.z + 0.9)]]
	for part in parts:
		var pc: Vector3 = room + (part[0] as Vector3)
		var ps: Vector3 = part[1]
		b.box(ps, MeshKit.at(pc), wallc)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = ps
		cs.shape = bs
		cs.position = pc
		_static.add_child(cs)
	b.wedge(Vector3(G.ROOM.x + 1.0, 0.7, G.ROOM.z + 1.0), MeshKit.at(room + Vector3(0, h + 0.65, 0)), Color(0.85, 0.35, 0.3))
	# The cracked wall: its own body, gone when punched.
	wall = StaticBody3D.new()
	wall.collision_layer = 1
	wall.position = sec.wall
	add_child(wall)
	var wb := MeshKit.Builder.new()
	wb.box(Vector3(G.ROOM.x, h, 0.3), MeshKit.at(Vector3(0, h * 0.5, 0)), CRACK_COLOR)
	for k in 5:  # cracks and a few loose bricks
		var a := -0.9 + k * 0.45
		wb.box(Vector3(0.06, 0.6, 0.04), MeshKit.at(Vector3(a, 0.6 + (k % 2) * 0.5, 0.16), Vector3.ONE, Vector3(0, 0, 0.5 - (k % 3) * 0.4)), Color(0.3, 0.25, 0.2))
	wb.star(5, 0.28, 0.12, 0.04, MeshKit.at(Vector3(0, h * 0.62, 0.17)), Color(1.0, 0.9, 0.4), true)  # a sparkle: something's in there
	wall.add_child(MeshKit.instance(wb.build()))
	var ws := CollisionShape3D.new()
	var wbs := BoxShape3D.new()
	wbs.size = Vector3(G.ROOM.x, h, 0.3)
	ws.shape = wbs
	ws.position = Vector3(0, h * 0.5, 0)
	wall.add_child(ws)
	gear = Node3D.new()
	gear.position = lv.gear
	add_child(gear)
	gear.add_child(MeshKit.instance(gear_mesh(), false))


static func gear_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.cylinder(0.32, 0.32, 0.12, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), GEAR_COLOR, 16, true)
	for k in 8:
		var a := TAU * k / 8.0
		b.box(Vector3(0.14, 0.14, 0.12), MeshKit.at(Vector3(cos(a) * 0.38, sin(a) * 0.38, 0), Vector3.ONE, Vector3(0, 0, a)), GEAR_COLOR, true)
	b.cylinder(0.1, 0.1, 0.14, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.55, 0.35, 0.1), 10)
	return b.build()


## Every machine: the cracked wall bursts open.
func break_wall() -> void:
	if wall_broken or wall == null:
		return
	wall_broken = true
	wall.queue_free()
	wall = null


func set_gear(got: bool) -> void:
	gear_got = got
	if gear != null:
		gear.visible = not got


## Is point p near the cracked wall (punch reach / a VR finger)?
func near_wall(p: Vector3, r: float) -> bool:
	if wall_broken or (lv.secret as Dictionary).is_empty():
		return false
	var w: Vector3 = (lv.secret as Dictionary).wall
	return absf(p.x - w.x) < G.ROOM.x * 0.5 + r and absf(p.z - w.z) < r + 0.15 and p.y > w.y - 0.5 and p.y < w.y + G.ROOM.y + r


func _goal() -> void:
	goal = Node3D.new()
	goal.position = lv.goal
	add_child(goal)
	var b := MeshKit.Builder.new()
	b.cylinder(0.7, 0.85, 0.4, MeshKit.at(Vector3(0, 0.2, 0)), Color(0.95, 0.95, 0.98), 16)
	b.torus(0.7, 0.08, MeshKit.at(Vector3(0, 0.42, 0)), Color(1.0, 0.85, 0.3), 16, 6)
	goal.add_child(MeshKit.instance(b.build()))
	var sp := MeshInstance3D.new()
	sp.name = "Spark"
	sp.mesh = spark_mesh()
	sp.position = Vector3(0, 1.3, 0)
	goal.add_child(sp)
	var light := OmniLight3D.new()
	light.light_color = SPARK_COLOR
	light.omni_range = 5.0
	light.light_energy = 1.4
	light.position = Vector3(0, 1.3, 0)
	goal.add_child(light)
	set_goal(not (lv.boss as Dictionary).size() > 0)


## The spark: a glowing lightning crystal.
static func spark_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.polygon(PackedVector2Array([Vector2(0.1, 0.55), Vector2(-0.3, 0.0), Vector2(-0.02, 0.0), Vector2(-0.12, -0.55),
		Vector2(0.3, 0.08), Vector2(0.02, 0.08)]), 0.16, Transform3D.IDENTITY, SPARK_COLOR, true)
	b.sphere(0.32, Transform3D.IDENTITY, SPARK_COLOR.lightened(0.3), 12, true)
	return b.build()


func set_goal(on: bool) -> void:
	goal_on = on
	if goal != null:
		goal.visible = on


func _grumbles() -> void:
	for gd in lv.grumbles:
		var n := Node3D.new()
		add_child(n)
		n.add_child(MeshKit.instance(grumble_mesh(), false))
		Contrast.outline(n.get_child(0), Contrast.OUTLINE)
		var x0 := float(gd.x0)
		n.position = Vector3(x0, float(gd.y), 0.0)
		var big := bool(gd.get("big", false))
		if big:  # the MEGA GRUMBLE: twice as big, in its island's colours, waiting up in the sky till a robot comes
			n.get_child(0).queue_free()
			var mi := MeshKit.instance(grumble_mesh(MEGA_COLORS.get(theme, GRUMBLE_COLOR), true), false)
			n.add_child(mi)
			Contrast.outline(mi, Contrast.OUTLINE)
			n.scale = Vector3.ONE * MEGA_SCALE
			n.visible = false
		grumbles.append({"node": n, "x": x0, "dir": 1.0, "st": "sky" if big else "walk", "tt": 0.0, "cool": 1.0, "gone": false, "d": gd,
			"to": x0, "z": 0.0, "big": big, "hp": int(gd.get("hp", 1))})


const GR_STATES: Array[String] = ["walk", "tell", "dash", "sky", "drop"]
const DROP_TIME := 0.9  ## the MEGA GRUMBLE falls out of the sky this long
const MEGA_SCALE := 2.0
const MEGA_R := 1.5  ## a robot this near the MEGA GRUMBLE bumps it (a little grumble: 0.8)
## The MEGA GRUMBLE's colours: an orange farmer on the meadow, a steel boiler at the gear works, a snowy yeti, a
## leafy jungle one.
const MEGA_COLORS := {"meadow": Color(0.95, 0.5, 0.2), "gears": Color(0.5, 0.55, 0.65), "snow": Color(0.92, 0.95, 1.0),
	"jungle": Color(0.3, 0.6, 0.3), "cove": Color(1.0, 0.45, 0.4), "clock": Color(0.6, 0.4, 0.7)}


## A GRUMBLE: a grumpy red wind-up box bot with a key on its back and cross eyebrows (the MEGA one: a crown of
## spikes and big teeth).
static func grumble_mesh(col: Color = GRUMBLE_COLOR, mega: bool = false) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	if mega:
		for k in 5:
			b.cone(0.07, 0.22, MeshKit.at(Vector3(-0.24 + k * 0.12, 0.76, 0.0)), Color(1.0, 0.85, 0.3), 5)
		for k in 4:
			b.box(Vector3(0.06, 0.07, 0.03), MeshKit.at(Vector3(-0.1 + k * 0.067, 0.3, 0.32)), Color(0.97, 0.97, 0.97))
	b.rounded_box(Vector3(0.7, 0.6, 0.6), 0.12, MeshKit.at(Vector3(0, 0.38, 0)), col)
	b.box(Vector3(0.5, 0.18, 0.04), MeshKit.at(Vector3(0, 0.46, 0.31)), Color(0.12, 0.1, 0.12))
	b.sphere(0.05, MeshKit.at(Vector3(-0.12, 0.47, 0.33)), Color(1.0, 0.9, 0.3), 6, true)
	b.sphere(0.05, MeshKit.at(Vector3(0.12, 0.47, 0.33)), Color(1.0, 0.9, 0.3), 6, true)
	b.box(Vector3(0.16, 0.04, 0.03), MeshKit.at(Vector3(-0.12, 0.58, 0.33), Vector3.ONE, Vector3(0, 0, -0.4)), Color(0.12, 0.1, 0.12))
	b.box(Vector3(0.16, 0.04, 0.03), MeshKit.at(Vector3(0.12, 0.58, 0.33), Vector3.ONE, Vector3(0, 0, 0.4)), Color(0.12, 0.1, 0.12))
	b.cylinder(0.04, 0.04, 0.25, MeshKit.at(Vector3(0, 0.4, -0.42), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.8, 0.8, 0.85), 6)
	b.box(Vector3(0.3, 0.16, 0.04), MeshKit.at(Vector3(0, 0.4, -0.55)), Color(0.8, 0.8, 0.85))
	for s in [-0.22, 0.22]:
		b.cylinder(0.1, 0.1, 0.08, MeshKit.at(Vector3(s, 0.08, 0.15), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.2, 0.2, 0.22), 10)
		b.cylinder(0.1, 0.1, 0.08, MeshKit.at(Vector3(s, 0.08, -0.15), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.2, 0.2, 0.22), 10)
	return b.build()


func grumble_pos(i: int) -> Vector3:
	return (grumbles[i].node as Node3D).position


func _zaps() -> void:
	for z in lv.zaps:
		var n := Node3D.new()
		n.position = z.pos
		add_child(n)
		var b := MeshKit.Builder.new()
		var r := float(z.r)
		b.cylinder(r, r, 0.06, MeshKit.at(Vector3(0, 0.03, 0)), Color(0.32, 0.34, 0.4), 20)
		b.torus(r * 0.75, 0.05, MeshKit.at(Vector3(0, 0.07, 0)), ZAP_COLOR.darkened(0.3), 20, 6)
		b.torus(r * 0.4, 0.05, MeshKit.at(Vector3(0, 0.07, 0)), ZAP_COLOR.darkened(0.3), 16, 6)
		n.add_child(MeshKit.instance(b.build(), false))
		var glow := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 0.05
		cm.radial_segments = 20
		glow.mesh = cm
		glow.material_override = MeshKit.material(ZAP_COLOR, 3.0)
		glow.position.y = 0.1
		glow.visible = false
		glow.name = "Glow"
		n.add_child(glow)
		zap_nodes.append(n)
		zap_was.append(-1)


# --- Every frame ---------------------------------------------------------------------------------------------------

## Every machine, physics: movers / lifts where the clock (host) or the snapshot (TV machine) says.
func physics(delta: float) -> void:
	if lv.is_empty():
		return
	if host:
		t += delta
		for i in movers:
			var p: Dictionary = (lv.plats as Array)[i]
			var want := G.plat_at(p, t)
			if lift_hold.has(i):
				want.y = clampf(float(lift_hold[i]), float((p.c as Vector3).y), float((p.b as Vector3).y))
			elif lift_blend.has(i):
				var bl: Array = lift_blend[i]
				bl[1] = float(bl[1]) - delta / 1.6
				if float(bl[1]) <= 0.0:
					lift_blend.erase(i)
				else:
					want.y = lerpf(want.y, float(bl[0]), float(bl[1]))
			mover_pos[i] = want
	for i in movers:
		var body: AnimatableBody3D = movers[i]
		var to: Vector3 = mover_pos[i]
		body.position = to if host else body.position.lerp(to, 1.0 - exp(-14.0 * delta))


## The giant's hand holds lift i at top y (or lets go: y = NAN).
func hold_lift(i: int, y: float) -> void:
	if is_nan(y):
		if lift_hold.has(i):
			lift_blend[i] = [float(lift_hold[i]), 1.0]
			lift_hold.erase(i)
	else:
		lift_hold[i] = y


## Every machine, process: bolts spin, the gear and spark bob, zaps tell / buzz, grumbles waddle.
func animate(delta: float) -> void:
	if lv.is_empty():
		return
	if not host:
		t += delta
	var now := Time.get_ticks_msec() * 0.001
	_animate_jobs(delta)
	var bolts: Array = lv.bolts
	var mm := bolt_mm.multimesh
	for k in bolts.size():
		if bolt_taken(k):
			mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, -50, 0)))
		else:
			var y := sin(now * 2.0 + k) * 0.08
			mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, now * 2.5 + k * 0.4), (bolts[k] as Vector3) + Vector3(0, y, 0)))
	if gear != null and gear.visible:
		gear.rotation.y = now * 2.0
		gear.position.y = float((lv.gear as Vector3).y) + sin(now * 2.4) * 0.08
	if goal != null and goal.visible:
		var sp: Node3D = goal.get_node("Spark")
		sp.rotation.y = now * 1.6
		sp.position.y = 1.3 + sin(now * 2.0) * 0.12
	for i in springs.size():
		spring_t[i] += delta
		var k := clampf(spring_t[i] / 0.35, 0.0, 1.0)
		var top: Node3D = springs[i].get_node("Top")
		top.scale = Vector3(1.0, 0.55 + 0.45 * (1.0 - cos(k * PI * 2.5) * (1.0 - k)), 1.0) if k < 1.0 else Vector3.ONE
	for f in fans:
		(f.get_node("Blades") as Node3D).rotation.y = now * 9.0
	for ba in belt_arrows:
		var nodes: Array = ba.nodes
		var length := float(ba.len)
		for j in nodes.size():
			var off := fposmod(float(j) * length / nodes.size() + t * G.BELT * float(ba.dir), length)
			(nodes[j] as Node3D).position = Vector3(float(ba.x0) + off, float(ba.y), float(ba.z))
	for i in boxes.size():
		var crate: Node3D = boxes[i].get_node("Crate")
		crate.rotation.y = sin(now * 1.6 + i) * 0.35  # (it rattles: someone's inside)
		crate.position.y = maxf(0.0, sin(now * 5.0 + i * 2.0)) * 0.06
		var tiny: Node3D = boxes[i].get_node("Tiny")
		tiny.rotation.z = sin(now * (8.0 if box_open(i) else 3.0) + i) * (0.3 if box_open(i) else 0.1)
	var zaps: Array = lv.zaps
	for i in zaps.size():
		var st := G.zap_state(zaps[i], t)
		if st != zap_was[i]:
			if st == 1:  # the tell: a flashing disc that turns hot when it buzzes
				var z: Dictionary = zaps[i]
				rings.shape("circle", (z.pos as Vector3) + Vector3(0, 0.12, 0), Vector3.FORWARD, Vector2(float(z.r), 0.0), ZAP_COLOR,
					G.ZAP_TELL * G.ZAP_PERIOD, {"style": "flash", "stay": G.ZAP_HOT * G.ZAP_PERIOD, "hot": Color(1.0, 1.0, 0.85), "y": 0.0})
			zap_was[i] = st
		(zap_nodes[i].get_node("Glow") as Node3D).visible = st == 2 and fmod(now * 12.0, 1.0) < 0.6
	for gr in grumbles:
		var n: Node3D = gr.node
		if bool(gr.gone):
			n.scale = n.scale.lerp(Vector3.ONE * 0.01, 1.0 - exp(-10.0 * delta))
			continue
		if bool(gr.big):
			_animate_mega(gr, delta)
			if String(gr.st) == "sky" or String(gr.st) == "drop":
				continue
		var tell := String(gr.st) == "tell"
		n.rotation.z = sin(now * 30.0) * 0.12 if tell else sin(now * 8.0) * 0.05
		n.rotation.y = lerp_angle(n.rotation.y, atan2(float(gr.dir), 0.0), 1.0 - exp(-10.0 * delta))


## Is a zap pad buzzing on point p (owned robots check themselves)?
func zapped(p: Vector3) -> int:
	var zaps: Array = lv.zaps
	for i in zaps.size():
		var z: Dictionary = zaps[i]
		var zp: Vector3 = z.pos
		if G.zap_state(z, t) == 2 and Vector2(p.x - zp.x, p.z - zp.z).length() < float(z.r) + 0.15 and absf(p.y - zp.y) < 0.6:
			return i
	return -1


## Host: the grumbles waddle along their floors; one winds up (a warn line on the floor) then charges a robot ahead.
## robots: Array of Node3D. Returns tells to show [[pos, dir, length]] (main sends them to every machine).
func host_grumbles(delta: float, robots: Array) -> Array:
	var told: Array = []
	for gr in grumbles:
		if bool(gr.gone):
			continue
		var d: Dictionary = gr.d
		var n: Node3D = gr.node
		gr.cool = maxf(0.0, float(gr.cool) - delta)
		var x := float(gr.x)
		match String(gr.st):
			"sky":  # (the MEGA GRUMBLE waits up there till a robot comes onto its floor)
				for r in robots:
					var rp: Vector3 = (r as Node3D).position
					if absf(rp.y - float(d.y)) < 1.5 and rp.x > float(d.x0) - 3.5 and rp.x < float(d.x1) + 1.0:
						gr.st = "drop"
						gr.tt = DROP_TIME
						gr.cool = 1.6
						told.append(["drop", Vector3(x, float(d.y), 0.0)])
						break
			"drop":
				gr.tt = float(gr.tt) - delta
				if float(gr.tt) <= 0.0:
					gr.st = "walk"
					told.append(["thud", Vector3(x, float(d.y), 0.0)])
			"walk":
				x += float(gr.dir) * float(d.speed) * delta
				if x > float(d.x1):
					x = float(d.x1)
					gr.dir = -1.0
				elif x < float(d.x0):
					x = float(d.x0)
					gr.dir = 1.0
				if float(gr.cool) <= 0.0:
					for r in robots:
						var rp: Vector3 = (r as Node3D).position
						var ahead := (rp.x - x) * float(gr.dir)
						var big := bool(gr.big)
						if ahead > 0.6 and ahead < (5.5 if big else 4.0) and absf(rp.y - float(d.y)) < 0.8 and absf(rp.z - n.position.z) < (2.4 if big else 1.6):
							var to := clampf(x + float(gr.dir) * (4.4 if big else 3.2), float(d.x0) - 1.0, float(d.x1) + 1.0)
							gr.st = "tell"
							gr.tt = 0.9
							gr.to = to
							told.append([Vector3(x, float(d.y), n.position.z), Vector3(float(gr.dir), 0, 0), absf(to - x) + (1.4 if bool(gr.big) else 0.0)])
							break
			"tell":
				gr.tt = float(gr.tt) - delta
				if float(gr.tt) <= 0.0:
					gr.st = "dash"
			"dash":
				var to := float(gr.to)
				x = move_toward(x, to, float(d.dash) * delta)
				if absf(x - to) < 0.01:
					gr.st = "walk"
					gr.cool = 2.2
		gr.x = x
		n.position = Vector3(x, float(d.y), n.position.z)
	return told


## Every machine: the MEGA GRUMBLE drops out of the sky (shown from its state: hidden up there, then falling).
func _animate_mega(gr: Dictionary, delta: float) -> void:
	var n: Node3D = gr.node
	var d: Dictionary = gr.d
	match String(gr.st):
		"sky":
			n.visible = false
		"drop":
			if not host:
				gr.tt = float(gr.tt) - delta
			n.visible = true
			var k := clampf(1.0 - float(gr.tt) / DROP_TIME, 0.0, 1.0)
			n.position.y = float(d.y) + 16.0 * (1.0 - k * k)
			n.rotation.y += delta * 9.0
		_:
			n.visible = true
			n.position.y = float(d.y)


## Every machine: grumble i is popped (punched, hopped on, flicked by the giant).
func pop_grumble(i: int) -> void:
	if i >= 0 and i < grumbles.size():
		grumbles[i].gone = true


func grumble_alive(i: int) -> bool:
	return i >= 0 and i < grumbles.size() and not bool(grumbles[i].gone) and String(grumbles[i].st) != "sky" and String(grumbles[i].st) != "drop"


## Is a MEGA GRUMBLE on floor p still up in the sky or falling (robots wait for it)?
func grumble_dropping(p: int) -> bool:
	for gr in grumbles:
		if bool(gr.big) and int((gr.d as Dictionary).p) == p and (String(gr.st) == "drop" or (String(gr.st) == "sky" and not bool(gr.gone))):
			return String(gr.st) == "drop"
	return false


func grumble_big(i: int) -> bool:
	return i >= 0 and i < grumbles.size() and bool(grumbles[i].big)


## Host: a hit on a MEGA GRUMBLE (a punch, a hop, a pound): true when it's popped now (its hits are used up).
func mega_hit(i: int, away: float) -> bool:
	var gr: Dictionary = grumbles[i]
	gr.hp = int(gr.hp) - 1
	if int(gr.hp) <= 0:
		return true
	gr.st = "walk"
	gr.cool = 1.4
	gr.x = clampf(float(gr.x) + away * 1.2, float(gr.d.x0), float(gr.d.x1))
	return false


func grumble_charging(i: int) -> bool:
	return String(grumbles[i].st) == "dash"


# --- Snapshots ----------------------------------------------------------------------------------------------------

## Host: the clock, the movers, the grumbles ([x, state, dir] each: 0 walk 1 tell 2 dash 3 gone).
func pack() -> Array:
	var mp := PackedVector3Array()
	var keys := movers.keys()
	keys.sort()
	for i in keys:
		mp.append(mover_pos[i])
	var gs := PackedFloat32Array()
	for gr in grumbles:
		gs.append(snappedf(float(gr.x), 0.01))
		gs.append(GR_STATES.find(String(gr.st)) + (10 if bool(gr.gone) else 0))
		gs.append(float(gr.dir))
	return [snappedf(t, 0.01), mp, gs, pack_jobs()]


func unpack(a: Array) -> void:
	if a.size() < 3 or lv.is_empty():
		return
	var ht := float(a[0])
	if absf(ht - t) > 0.25:
		t = ht
	else:
		t = lerpf(t, ht, 0.1)
	var mp: PackedVector3Array = a[1]
	var keys := movers.keys()
	keys.sort()
	for k in mini(keys.size(), mp.size()):
		mover_pos[keys[k]] = mp[k]
	if a.size() >= 4 and a[3] is PackedFloat32Array:
		unpack_jobs(a[3])
	var gs: PackedFloat32Array = a[2]
	for i in mini(grumbles.size(), gs.size() / 3):
		var gr: Dictionary = grumbles[i]
		var stv := int(gs[i * 3 + 1])
		gr.gone = stv >= 10
		var was := String(gr.st)
		gr.st = GR_STATES[stv % 10]
		if gr.st == "drop" and was == "sky":
			gr.tt = DROP_TIME
		gr.dir = gs[i * 3 + 2]
		gr.x = gs[i * 3]
		var n: Node3D = gr.node
		n.position.x = lerpf(n.position.x, float(gr.x), 0.5)


# --- GIANT JOBS (levelgen.gd _job) -----------------------------------------------------------------------------------

const BUTTON_COLOR := Color(1.0, 0.3, 0.35)
const ICE_COLOR := Color(0.7, 0.9, 1.0)
const ROCK_COLOR := Color(0.55, 0.5, 0.48)
const PLANK_COLOR := Color(0.72, 0.5, 0.3)
const CLOCK_HAND := Color(0.22, 0.2, 0.28)


func job_open(j: int) -> bool:
	if j < 0 or j >= jobs_prog.size():
		return true
	for k in jobs_prog[j]:
		if float(k) < 1.0:
			return false
	return true


## How far job j is open (0..1: the least open piece).
func job_progress(j: int) -> float:
	var lo := 1.0
	for k in jobs_prog[j]:
		lo = minf(lo, float(k))
	return lo


func _jobs() -> void:
	var jobs: Array = lv.get("jobs", [])
	for j in jobs.size():
		var job: Dictionary = jobs[j]
		var kind := String(job.kind)
		var nodes := {"pieces": [], "cols": [], "block": null, "block_col": null, "btn": null, "crank": null, "cracks": []}
		var prog: Array = []
		for i in maxi(1, (job.plats as Array).size()):
			prog.append(0.0)
		for i in (job.plats as Array).size():
			var pi := int(job.plats[i])
			gate_job[pi] = j
			var pl: Dictionary = (lv.plats as Array)[pi]
			var n := Node3D.new()
			add_child(n)
			n.add_child(MeshKit.instance(_piece_mesh(kind, pl, float(job.dirs[i])), false))
			(nodes.pieces as Array).append(n)
			# Its floor (only there once the job's open): a still body where the piece lies open.
			var body := StaticBody3D.new()
			body.collision_layer = 1
			add_child(body)
			_box_shape(body, pl.c, pl.s, false)
			var col: CollisionShape3D = body.get_child(0)
			col.disabled = true
			(nodes.cols as Array).append(col)
		match kind:
			"boulder", "ice":
				var bc: Vector3 = job.block.c
				var bs: Vector3 = job.block.s
				var bn := Node3D.new()
				bn.position = bc
				add_child(bn)
				var b := MeshKit.Builder.new()
				if kind == "boulder":
					b.sphere(bs.y * 0.5, MeshKit.at(Vector3(0, bs.y * 0.5, 0), Vector3(bs.x / bs.y, 1.0, bs.z / bs.y)), ROCK_COLOR, 14)
					for k in 5:  # moss and a grumpy face (it's a sleepy boulder)
						b.sphere(0.35, MeshKit.at(Vector3(cos(k * 1.3) * bs.x * 0.35, bs.y * 0.82, sin(k * 1.3) * bs.z * 0.3), Vector3(1.2, 0.4, 1.0)), Color(0.4, 0.62, 0.3), 6)
					for e in [-0.4, 0.4]:
						b.box(Vector3(0.35, 0.08, 0.05), MeshKit.at(Vector3(e, bs.y * 0.62, bs.z * 0.5 - 0.02)), Color(0.15, 0.13, 0.13))
					b.sphere(0.32, MeshKit.at(Vector3(0, bs.y + 0.1, 0)), HANDLE, 10, true)  # (the giant's grab spot glows)
				else:
					b.box(bs, MeshKit.at(Vector3(0, bs.y * 0.5, 0)), ICE_COLOR)
					for k in 4:  # icicles and frosty blobs on top
						b.cone(0.18, 0.5, MeshKit.at(Vector3(0, bs.y + 0.2, (k - 1.5) * bs.z * 0.25)), Color(0.92, 0.97, 1.0), 6)
					b.box(Vector3(bs.x + 0.06, 0.25, bs.z + 0.06), MeshKit.at(Vector3(0, bs.y * 0.6, 0)), Color(0.55, 0.8, 1.0))
					b.star(5, 0.35, 0.15, 0.05, MeshKit.at(Vector3(0, bs.y * 0.6, bs.z * 0.5 + 0.04)), HANDLE, true)
				var mi := MeshKit.instance(b.build(), false)
				Contrast.outline(mi, Contrast.OUTLINE)
				bn.add_child(mi)
				if kind == "ice":  # cracks, one more for every smash
					for k in 3:
						var cb := MeshKit.Builder.new()
						for q in 3:
							cb.box(Vector3(0.07, 0.9, 0.04), MeshKit.at(Vector3((k - 1) * 0.45 + q * 0.12, bs.y * (0.3 + 0.2 * q), bs.z * 0.5 + 0.03), Vector3.ONE, Vector3(0, 0, 0.6 - q * 0.5 + k * 0.3)), Color(0.2, 0.35, 0.55))
						var cm := MeshKit.instance(cb.build(), false)
						cm.visible = false
						bn.add_child(cm)
						(nodes.cracks as Array).append(cm)
				nodes.block = bn
				var body := StaticBody3D.new()
				body.collision_layer = 1
				add_child(body)
				var cs := CollisionShape3D.new()
				var bx := BoxShape3D.new()
				bx.size = bs
				cs.shape = bx
				cs.position = bc + Vector3(0, bs.y * 0.5, 0)
				body.add_child(cs)
				nodes.block_col = cs
			"crank":
				var cn := Node3D.new()
				cn.position = job.crank
				add_child(cn)
				var b := MeshKit.Builder.new()
				b.cylinder(0.12, 0.16, 1.6, MeshKit.at(Vector3(0, -0.8, -0.2)), Color(0.5, 0.52, 0.6), 8)  # its post
				b.cylinder(0.25, 0.25, 0.3, MeshKit.at(Vector3(0, 0, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.75, 0.6, 0.25), 10)
				cn.add_child(MeshKit.instance(b.build(), false))
				var wheel := Node3D.new()
				wheel.name = "Wheel"
				cn.add_child(wheel)
				var wb := MeshKit.Builder.new()
				wb.torus(1.0, 0.1, MeshKit.at(Vector3(0, 0, 0.2), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.85, 0.68, 0.3), 20, 6)
				for k in 4:
					wb.box(Vector3(2.0, 0.1, 0.08), MeshKit.at(Vector3(0, 0, 0.2), Vector3.ONE, Vector3(0, 0, k * PI * 0.25)), Color(0.75, 0.6, 0.25))
				wb.cylinder(0.1, 0.1, 0.5, MeshKit.at(Vector3(1.0, 0, 0.45), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), HANDLE, 8)
				wb.sphere(0.24, MeshKit.at(Vector3(1.0, 0, 0.7)), HANDLE, 10, true)
				var wm := MeshKit.instance(wb.build(), false)
				Contrast.outline(wm, Contrast.OUTLINE)
				wheel.add_child(wm)
				nodes.crank = cn
			"clock":  # the clock face the hand swings over, down under the gap, and its post
				var pv: Vector3 = job.pivots[0]
				var b := MeshKit.Builder.new()
				b.cylinder(4.4, 4.4, 0.2, MeshKit.at(pv + Vector3(0, -2.6, 0)), Color(0.97, 0.94, 0.85), 32)
				b.torus(4.4, 0.18, MeshKit.at(pv + Vector3(0, -2.5, 0)), Color(0.85, 0.68, 0.3), 32, 6)
				for k in 12:
					var a := TAU * k / 12.0
					b.box(Vector3(0.18, 0.06, 0.6 if k % 3 == 0 else 0.3), MeshKit.at(pv + Vector3(sin(a) * 3.8, -2.45, cos(a) * 3.8), Vector3.ONE, Vector3(0, a, 0)), CLOCK_HAND)
				b.cylinder(0.3, 0.4, 2.6, MeshKit.at(pv + Vector3(0, -1.3, 0)), Color(0.85, 0.68, 0.3), 10)
				b.cone(4.0, 3.5, MeshKit.at(pv + Vector3(0, -4.5, 0), Vector3.ONE, Vector3(PI, 0, 0)), THEME[theme].rock, 12)
				add_child(MeshKit.instance(b.build()))
		# The robot BUTTON (asleep while the giant's job is the giant's).
		var btn := Node3D.new()
		btn.position = job.btn
		add_child(btn)
		var bb := MeshKit.Builder.new()
		bb.cylinder(G.BUTTON_R + 0.1, G.BUTTON_R + 0.15, 0.12, MeshKit.at(Vector3(0, 0.06, 0)), Color(0.3, 0.3, 0.36), 18)
		var cap := MeshKit.Builder.new()
		cap.cylinder(G.BUTTON_R, G.BUTTON_R, 0.16, MeshKit.at(Vector3(0, 0.14, 0)), BUTTON_COLOR, 18, true)
		btn.add_child(MeshKit.instance(bb.build(), false))
		var capn := MeshKit.instance(cap.build(), false)
		capn.name = "Cap"
		btn.add_child(capn)
		btn.visible = false
		nodes.btn = btn
		job_nodes.append(nodes)
		jobs_prog.append(prog)
		job_btn.append(false)
		job_held.append(Vector3.INF)
		job_open_was.append(false)
		_pose_job(j)


## A gate piece's look: a drawbridge plank with rails and a handle knob at its tip, a palm tree (its trunk is the
## bridge, leaves at the crown), the crank's bridge (a metal girder), the clock's long minute hand.
func _piece_mesh(kind: String, pl: Dictionary, d: float) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var s: Vector2 = pl.s
	var half := s.x * 0.5
	match kind:
		"bridge":
			b.box(Vector3(s.x, 0.25, s.y), MeshKit.at(Vector3(0, -0.125, 0)), PLANK_COLOR)
			for k in int(s.x / 0.6):
				b.box(Vector3(0.06, 0.03, s.y), MeshKit.at(Vector3(-half + 0.3 + k * 0.6, 0.01, 0)), PLANK_COLOR.darkened(0.35))
			for sz in [-1.0, 1.0]:
				b.box(Vector3(s.x, 0.12, 0.12), MeshKit.at(Vector3(0, 0.35, sz * (s.y * 0.5 - 0.06))), PLANK_COLOR.darkened(0.2))
			b.cylinder(0.1, 0.1, 1.1, MeshKit.at(Vector3(d * (half - 0.2), 0.0, s.y * 0.5 + 0.5), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), HANDLE, 8)
			b.sphere(0.3, MeshKit.at(Vector3(d * (half - 0.2), 0.0, s.y * 0.5 + 1.05)), HANDLE, 12, true)
		"tree":
			b.cylinder(0.42, 0.55, s.x, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.55, 0.38, 0.22), 10)
			b.box(Vector3(s.x, 0.12, 1.0), MeshKit.at(Vector3(0, 0.38, 0)), Color(0.5, 0.36, 0.22))  # (a flat walking top)
			for k in int(s.x / 0.8):
				b.torus(0.5, 0.05, MeshKit.at(Vector3(-half + 0.4 + k * 0.8, 0, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.42, 0.28, 0.16), 10, 4)
			for k in 6:  # the crown: big leaves, and coconuts (the giant pushes here)
				var a := TAU * k / 6.0
				b.ellipsoid(Vector3(1.3, 0.12, 0.45), MeshKit.at(Vector3(d * half + d * cos(a) * 0.9, 0.3 + sin(a) * 0.4, sin(a) * 0.9), Vector3.ONE, Vector3(0, a, 0.3)), Color(0.25, 0.7, 0.3), 6)
			b.sphere(0.25, MeshKit.at(Vector3(d * (half - 0.2), -0.3, 0.3)), Color(0.45, 0.3, 0.15), 8)
			b.sphere(0.35, MeshKit.at(Vector3(d * half, 0.0, 0.0)), HANDLE, 10, true)
		"crank":
			b.box(Vector3(s.x, 0.3, s.y), MeshKit.at(Vector3(0, -0.15, 0)), Color(0.5, 0.55, 0.66))
			for k in int(s.x / 1.2):
				b.box(Vector3(0.1, 0.5, s.y + 0.1), MeshKit.at(Vector3(-half + 0.6 + k * 1.2, -0.45, 0)), Color(0.75, 0.6, 0.25))
			for sz in [-1.0, 1.0]:
				b.box(Vector3(s.x, 0.08, 0.12), MeshKit.at(Vector3(0, 0.03, sz * (s.y * 0.5 - 0.06))), HANDLE)
		"clock":
			b.box(Vector3(s.x, 0.25, s.y), MeshKit.at(Vector3(0, -0.125, 0)), CLOCK_HAND)
			b.cone(s.y * 0.8, 1.2, MeshKit.at(Vector3(half + 0.4, -0.125, 0), Vector3(1.0, 0.2, 1.0), Vector3(0, 0, -PI * 0.5)), CLOCK_HAND)
			b.cylinder(0.5, 0.5, 0.35, MeshKit.at(Vector3(0, 0.05, 0)), Color(0.85, 0.68, 0.3), 14)
			b.sphere(0.32, MeshKit.at(Vector3(half - 0.3, 0.5, 0)), HANDLE, 12, true)  # (the giant grabs the tip)
	return b.build()


## Every machine: job j's pieces where its progress says (bridges swing / rise, the boulder in the giant's hand, the
## ice cracks), its floor solid once open, the wall gone, the button lit while awake.
func _pose_job(j: int) -> void:
	var job: Dictionary = (lv.jobs as Array)[j]
	var nodes: Dictionary = job_nodes[j]
	var prog: Array = jobs_prog[j]
	var open := job_open(j)
	for i in (nodes.pieces as Array).size():
		var pl: Dictionary = (lv.plats as Array)[int(job.plats[i])]
		(nodes.pieces[i] as Node3D).transform = G.gate_pose(job, i, pl, float(prog[i]))
		(nodes.cols[i] as CollisionShape3D).disabled = not open
	if nodes.crank != null:
		((nodes.crank as Node3D).get_node("Wheel") as Node3D).rotation.z = float(prog[0]) * TAU * 2.0
	if nodes.block != null:
		var bn: Node3D = nodes.block
		var bc: Vector3 = job.block.c
		(nodes.block_col as CollisionShape3D).disabled = open
		if String(job.kind) == "boulder":
			var held: Vector3 = job_held[j]
			if open:
				bn.visible = bn.position.y > bc.y - 30.0
			elif held != Vector3.INF:
				bn.position = held - Vector3(0, (job.block.s as Vector3).y * 0.6, 0)
			else:
				bn.position = bn.position.lerp(bc, 0.2)
		else:
			for k in (nodes.cracks as Array).size():
				(nodes.cracks[k] as Node3D).visible = float(prog[0]) >= (k + 1) / 3.0 - 0.01
			bn.visible = not open
	(nodes.btn as Node3D).visible = bool(job_btn[j]) and not open


## Host: set job j's piece progress (the giant's hands, the button), and the boulder's held point.
func set_job(j: int, piece: int, k: float) -> void:
	if j < 0 or j >= jobs_prog.size():
		return
	var prog: Array = jobs_prog[j]
	if piece < 0:
		for i in prog.size():
			prog[i] = clampf(k, 0.0, 1.0)
	elif piece < prog.size():
		prog[piece] = clampf(k, 0.0, 1.0)


## Every frame (every machine): pose the jobs; a job that just opened bursts (the boulder flies off, ice shatters).
func _animate_jobs(delta: float) -> void:
	for j in jobs_prog.size():
		var open := job_open(j)
		var nodes: Dictionary = job_nodes[j]
		if open and not bool(job_open_was[j]):
			job_open_was[j] = true
			if nodes.block != null and String((lv.jobs[j] as Dictionary).kind) == "boulder":
				var bn: Node3D = nodes.block
				var tw := create_tween()
				tw.tween_property(bn, "position", bn.position + Vector3(0, 6.0, -14.0), 0.6).set_ease(Tween.EASE_OUT)
				tw.tween_property(bn, "position", bn.position + Vector3(0, -40.0, -22.0), 1.2).set_ease(Tween.EASE_IN)
		var btn: Node3D = nodes.btn
		if btn.visible:
			(btn.get_node("Cap") as Node3D).position.y = -0.08 if bool(btn.get_meta("down", false)) else sin(Time.get_ticks_msec() * 0.008) * 0.03
		_pose_job(j)
	for sp in spinners:
		(sp[0] as Node3D).rotate_object_local(sp[1], float(sp[2]) * delta)


## The job whose robots wait at point `to` (a route step's), -1 none.
func job_index_at(to: Vector3) -> int:
	var jobs: Array = lv.get("jobs", [])
	for j in jobs.size():
		if ((jobs[j] as Dictionary).wait as Vector3).distance_to(to) < 0.01:
			return j
	return -1


## Every machine: a button looks pushed while a robot stands on it.
func press_buttons(robots: Array) -> void:
	for j in job_nodes.size():
		var down := false
		for r in robots:
			down = down or on_button(j, (r as Node3D).position)
		(job_nodes[j].btn as Node3D).set_meta("down", down)


## Is a robot's feet at p on job j's awake button?
func on_button(j: int, p: Vector3) -> bool:
	if j < 0 or j >= job_btn.size() or not bool(job_btn[j]) or job_open(j):
		return false
	var bp: Vector3 = (lv.jobs[j] as Dictionary).btn
	return Vector2(p.x - bp.x, p.z - bp.z).length() < G.BUTTON_R + 0.25 and absf(p.y - bp.y) < 0.5


## Snapshot part: per job [least progress of piece 0, piece 1, button awake, held x, y, z].
func pack_jobs() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for j in jobs_prog.size():
		var prog: Array = jobs_prog[j]
		out.append(float(prog[0]))
		out.append(float(prog[1]) if prog.size() > 1 else float(prog[0]))
		out.append(1.0 if bool(job_btn[j]) else 0.0)
		var h: Vector3 = job_held[j]
		var has := h != Vector3.INF
		out.append(h.x if has else 0.0)
		out.append(h.y if has else -999.0)
		out.append(h.z if has else 0.0)
	return out


func unpack_jobs(a: PackedFloat32Array) -> void:
	for j in mini(jobs_prog.size(), a.size() / 6):
		var prog: Array = jobs_prog[j]
		prog[0] = a[j * 6]
		if prog.size() > 1:
			prog[1] = a[j * 6 + 1]
		job_btn[j] = a[j * 6 + 2] > 0.5
		job_held[j] = Vector3.INF if a[j * 6 + 4] < -900.0 else Vector3(a[j * 6 + 3], a[j * 6 + 4], a[j * 6 + 5])


# --- Each island's own scenery (behind it and below, no collision) ---------------------------------------------------

## MEADOW HOP: green hills, a windmill turning, a rainbow. GEAR WORKS: giant gears turning, chimneys puffing smoke.
## CRAB COVE: the sea under the islands, a lighthouse, a sailing boat. SNOWY PEAKS: big snowy mountains, falling snow.
## JUNGLE JUMBLE: giant trees with hanging vines and a waterfall. CLOCKWORK KEEP: a huge clock tower whose hands go round.
func _backdrop() -> void:
	backdrop = Node3D.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	var b := MeshKit.Builder.new()
	var r := RandomNumberGenerator.new()
	r.seed = hash(theme)
	var fy := -8.0  # (the cloud floor)
	match theme:
		"meadow":
			for k in 7:
				var x := -60.0 + k * 20.0 + r.randf_range(-4, 4)
				b.dome(r.randf_range(12, 18), MeshKit.at(Vector3(x, fy, -34.0 - r.randf() * 8.0), Vector3(1.4, r.randf_range(0.6, 0.9), 1.0)), Color(0.4, 0.72, 0.32).lightened(r.randf() * 0.15), 16)
			for k in 10:  # trees on the hills
				var x := -55.0 + k * 12.0 + r.randf_range(-3, 3)
				var z := -26.0 - r.randf() * 6.0
				b.cylinder(0.5, 0.7, 4.0, MeshKit.at(Vector3(x, fy + 2.0, z)), Color(0.5, 0.35, 0.2), 6)
				b.sphere(2.6, MeshKit.at(Vector3(x, fy + 5.5, z)), Color(0.3, 0.6, 0.28), 8)
			b.cylinder(1.6, 2.6, 16.0, MeshKit.at(Vector3(22.0, fy + 8.0, -24.0)), Color(0.95, 0.9, 0.82), 10)  # the windmill
			b.cone(3.0, 4.0, MeshKit.at(Vector3(22.0, fy + 18.0, -24.0)), Color(0.85, 0.35, 0.3), 10)
			for k in 7:  # a rainbow
				var cols := [Color(1, 0.3, 0.3), Color(1, 0.6, 0.2), Color(1, 0.9, 0.3), Color(0.4, 0.85, 0.4), Color(0.3, 0.6, 1), Color(0.5, 0.4, 0.9), Color(0.8, 0.5, 1)]
				b.torus(40.0 - k * 1.2, 0.6, MeshKit.at(Vector3(-15.0, fy - 6.0, -60.0), Vector3(1, 1, 0.2), Vector3(PI * 0.5, 0, 0)), cols[k], 40, 4)
			var sails := _spinner(Vector3(22.0, fy + 14.0, -21.2), Vector3(0, 0, 1), 0.8)
			var sb := MeshKit.Builder.new()
			for k in 4:
				sb.box(Vector3(1.4, 9.0, 0.2), MeshKit.at(Vector3(0, 4.5, 0).rotated(Vector3(0, 0, 1), k * PI * 0.5), Vector3.ONE, Vector3(0, 0, k * PI * 0.5)), Color(0.98, 0.96, 0.9))
			sb.sphere(0.9, MeshKit.at(Vector3.ZERO), Color(0.6, 0.4, 0.25), 8)
			sails.add_child(MeshKit.instance(sb.build(), false))
		"gears":
			for k in 6:
				var x := -50.0 + k * 20.0 + r.randf_range(-3, 3)
				var gr := r.randf_range(5.0, 9.0)
				var g := _spinner(Vector3(x, fy + gr + r.randf_range(2, 10), -30.0 - r.randf() * 6.0), Vector3(0, 0, 1), (0.4 + r.randf() * 0.4) * (1.0 if k % 2 == 0 else -1.0))
				var gb := MeshKit.Builder.new()
				gb.cylinder(gr, gr, 1.2, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.62, 0.55, 0.42), 24)
				gb.cylinder(gr * 0.3, gr * 0.3, 1.4, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.35, 0.33, 0.36), 12)
				for t in 12:
					var a := TAU * t / 12.0
					gb.box(Vector3(1.6, 1.6, 1.2), MeshKit.at(Vector3(cos(a), sin(a), 0) * (gr + 0.6), Vector3.ONE, Vector3(0, 0, a)), Color(0.62, 0.55, 0.42))
				g.add_child(MeshKit.instance(gb.build(), false))
			for k in 4:  # chimneys, smoke puffs
				var x := -40.0 + k * 26.0
				b.cylinder(1.8, 2.4, 22.0, MeshKit.at(Vector3(x, fy + 11.0, -42.0)), Color(0.55, 0.32, 0.28), 10)
				b.torus(1.9, 0.3, MeshKit.at(Vector3(x, fy + 21.0, -42.0)), Color(0.3, 0.3, 0.32), 12, 4)
				_puffs(Vector3(x, fy + 22.5, -42.0), Color(0.75, 0.75, 0.78, 0.8), 2.4)
			for k in 3:  # pipes
				b.cylinder(0.8, 0.8, 120.0, MeshKit.at(Vector3(0, fy + 3.0 + k * 3.0, -24.0 - k * 4.0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.45, 0.5, 0.6), 10)
		"cove":
			# The sea under the islands (up to a sandy beach before the giant's feet).
			b.box(Vector3(200.0, 0.4, 90.0), MeshKit.at(Vector3(0, -2.2, -42.0)), Color(0.25, 0.6, 0.85))
			b.box(Vector3(200.0, 0.5, 4.0), MeshKit.at(Vector3(0, -2.3, 4.5)), Color(0.95, 0.86, 0.6))
			for k in 40:  # wave caps
				b.ellipsoid(Vector3(1.6, 0.12, 0.4), MeshKit.at(Vector3(r.randf_range(-80, 80), -1.95, r.randf_range(-70, 0))), Color(0.9, 0.97, 1.0), 6)
			b.cylinder(1.8, 2.4, 14.0, MeshKit.at(Vector3(-30.0, 5.0, -26.0)), Color(0.97, 0.97, 0.97), 12)  # the lighthouse
			for k in 3:
				b.cylinder(2.0 - k * 0.15, 2.1 - k * 0.15, 1.6, MeshKit.at(Vector3(-30.0, 0.5 + k * 4.0, -26.0)), Color(0.9, 0.25, 0.25), 12)
			b.sphere(1.6, MeshKit.at(Vector3(-30.0, 13.0, -26.0)), Color(1.0, 0.95, 0.5), 10, true)
			b.cone(2.2, 2.0, MeshKit.at(Vector3(-30.0, 15.0, -26.0)), Color(0.9, 0.25, 0.25), 12)
			b.dome(8.0, MeshKit.at(Vector3(-30.0, -2.0, -26.0), Vector3(1, 0.4, 1)), Color(0.6, 0.55, 0.5), 12)
			for k in 3:  # palm islets
				var px := 10.0 + k * 18.0
				b.dome(4.0, MeshKit.at(Vector3(px, -2.0, -30.0 - k * 5.0), Vector3(1, 0.4, 1)), Color(0.95, 0.86, 0.6), 12)
				b.cylinder(0.3, 0.45, 7.0, MeshKit.at(Vector3(px, 1.5, -30.0 - k * 5.0), Vector3.ONE, Vector3(0, 0, 0.15)), Color(0.55, 0.38, 0.22), 6)
				for q in 5:
					b.ellipsoid(Vector3(2.4, 0.15, 0.7), MeshKit.at(Vector3(px - 0.5, 5.0, -30.0 - k * 5.0), Vector3.ONE, Vector3(0, q * TAU / 5.0, 0.35)), Color(0.25, 0.65, 0.3), 6)
			var boat := _spinner(Vector3(0, -1.8, -40.0), Vector3.UP, 0.05)
			var bb := MeshKit.Builder.new()
			bb.box(Vector3(7.0, 1.4, 2.4), MeshKit.at(Vector3(30.0, 0.5, 0)), Color(0.6, 0.35, 0.2))
			bb.polygon(PackedVector2Array([Vector2(0, 0), Vector2(4.0, 0), Vector2(0, 7.0)]), 0.1, MeshKit.at(Vector3(30.0, 1.4, 0)), Color(0.97, 0.97, 0.97))
			boat.add_child(MeshKit.instance(bb.build(), false))
		"snow":
			for k in 8:
				var x := -70.0 + k * 20.0 + r.randf_range(-4, 4)
				var h := r.randf_range(22.0, 38.0)
				var z := -36.0 - r.randf() * 14.0
				var rad := h * 0.6
				b.cone(rad, h, MeshKit.at(Vector3(x, fy + h * 0.5, z)), Color(0.5, 0.56, 0.7), 10)
				b.cone(rad * 0.4, h * 0.4, MeshKit.at(Vector3(x, fy + h * 0.8, z)), Color(0.97, 0.98, 1.0), 10)
			for k in 14:  # pine trees down on the clouds
				var x := -60.0 + k * 9.0 + r.randf_range(-2, 2)
				var z := -20.0 - r.randf() * 8.0
				b.cone(2.0, 6.0, MeshKit.at(Vector3(x, fy + 3.0, z)), Color(0.2, 0.45, 0.38), 7)
				b.cone(1.0, 2.4, MeshKit.at(Vector3(x, fy + 5.4, z)), Color(0.97, 0.98, 1.0), 7)
			var snow := CPUParticles3D.new()
			snow.amount = 160
			snow.lifetime = 7.0
			snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			snow.emission_box_extents = Vector3(55.0, 1.0, 20.0)
			snow.position = Vector3(0, 22.0, -8.0)
			snow.direction = Vector3.DOWN
			snow.gravity = Vector3(0.4, -3.5, 0)
			snow.initial_velocity_min = 1.0
			snow.initial_velocity_max = 2.0
			var sm := SphereMesh.new()
			sm.radius = 0.12
			sm.height = 0.24
			sm.radial_segments = 4
			sm.rings = 2
			sm.material = MeshKit.material(Color(1, 1, 1))
			snow.mesh = sm
			backdrop.add_child(snow)
		"jungle":
			for k in 9:
				var x := -64.0 + k * 16.0 + r.randf_range(-3, 3)
				var z := -24.0 - r.randf() * 12.0
				var h := r.randf_range(24.0, 34.0)
				b.cylinder(1.6, 2.4, h, MeshKit.at(Vector3(x, fy + h * 0.5, z)), Color(0.45, 0.32, 0.2), 8)
				for q in 4:
					b.sphere(r.randf_range(4.0, 6.0), MeshKit.at(Vector3(x + r.randf_range(-3, 3), fy + h + r.randf_range(-2, 2), z + r.randf_range(-3, 3)), Vector3(1.3, 0.7, 1.3)), Color(0.2, 0.5 + r.randf() * 0.15, 0.25), 8)
				for q in 3:  # vines with flowers
					var vx := x + r.randf_range(-4, 4)
					b.cylinder(0.12, 0.12, 12.0, MeshKit.at(Vector3(vx, fy + h - 6.0, z + 3.0)), Color(0.3, 0.55, 0.25), 4)
					b.sphere(0.6, MeshKit.at(Vector3(vx, fy + h - 12.0, z + 3.0)), Color.from_hsv(r.randf(), 0.6, 1.0), 6)
			b.box(Vector3(6.0, 30.0, 0.4), MeshKit.at(Vector3(-8.0, fy + 15.0, -38.0)), Color(0.6, 0.85, 1.0))  # a waterfall
			b.box(Vector3(14.0, 18.0, 6.0), MeshKit.at(Vector3(-8.0, fy + 24.0, -42.0)), Color(0.42, 0.45, 0.4))
			_puffs(Vector3(-8.0, fy + 1.0, -37.0), Color(1, 1, 1, 0.7), 3.0)
		"clock":
			b.box(Vector3(26.0, 50.0, 10.0), MeshKit.at(Vector3(0, fy + 25.0, -44.0)), Color(0.62, 0.45, 0.56))  # the tower
			b.wedge(Vector3(30.0, 12.0, 14.0), MeshKit.at(Vector3(0, fy + 56.0, -44.0)), Color(0.42, 0.28, 0.4))
			b.cylinder(10.0, 10.0, 1.0, MeshKit.at(Vector3(0, fy + 36.0, -38.8), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.97, 0.95, 0.88), 32)
			b.torus(10.0, 0.6, MeshKit.at(Vector3(0, fy + 36.0, -38.3), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.85, 0.68, 0.3), 32, 6)
			for k in 12:
				var a := TAU * k / 12.0
				b.box(Vector3(0.6, 1.8, 0.3), MeshKit.at(Vector3(sin(a) * 8.5, fy + 36.0 + cos(a) * 8.5, -38.2), Vector3.ONE, Vector3(0, 0, -a)), Color(0.2, 0.2, 0.25))
			for side in [-1.0, 1.0]:  # side towers
				b.box(Vector3(10.0, 34.0, 8.0), MeshKit.at(Vector3(side * 26.0, fy + 17.0, -46.0)), Color(0.55, 0.4, 0.5))
				b.cone(7.0, 10.0, MeshKit.at(Vector3(side * 26.0, fy + 39.0, -46.0)), Color(0.42, 0.28, 0.4), 4)
			for k in 2:  # the hands
				var hnd := _spinner(Vector3(0, fy + 36.0, -37.9), Vector3(0, 0, 1), -0.5 if k == 0 else -0.06)
				var hb := MeshKit.Builder.new()
				hb.box(Vector3(0.8, 8.0 if k == 0 else 5.5, 0.3), MeshKit.at(Vector3(0, (8.0 if k == 0 else 5.5) * 0.5, 0)), Color(0.2, 0.2, 0.25))
				hnd.add_child(MeshKit.instance(hb.build(), false))
			for k in 5:  # floating cogs
				var g := _spinner(Vector3(-45.0 + k * 22.0, fy + 12.0 + r.randf() * 14.0, -26.0), Vector3(0, 0, 1), 0.6 * (1.0 if k % 2 == 0 else -1.0))
				var gb := MeshKit.Builder.new()
				gb.cylinder(3.0, 3.0, 0.6, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.85, 0.68, 0.3), 16)
				for t in 8:
					var a := TAU * t / 8.0
					gb.box(Vector3(1.0, 1.0, 0.6), MeshKit.at(Vector3(cos(a), sin(a), 0) * 3.3, Vector3.ONE, Vector3(0, 0, a)), Color(0.85, 0.68, 0.3))
				g.add_child(MeshKit.instance(gb.build(), false))
	var mi := MeshKit.instance(b.build(), false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	backdrop.add_child(mi)


func _spinner(at: Vector3, axis: Vector3, speed: float) -> Node3D:
	var n := Node3D.new()
	n.position = at
	backdrop.add_child(n)
	spinners.append([n, axis.normalized(), speed])
	return n


func _puffs(at: Vector3, col: Color, size: float) -> void:
	var cp := CPUParticles3D.new()
	cp.amount = 10
	cp.lifetime = 4.0
	cp.position = at
	cp.direction = Vector3.UP
	cp.spread = 12.0
	cp.gravity = Vector3(0.6, 0.5, 0)
	cp.initial_velocity_min = 1.5
	cp.initial_velocity_max = 2.5
	cp.scale_amount_min = size * 0.6
	cp.scale_amount_max = size
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = MeshKit.material(col)
	cp.mesh = sm
	backdrop.add_child(cp)
