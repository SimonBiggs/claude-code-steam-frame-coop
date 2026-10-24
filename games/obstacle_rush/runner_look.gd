extends RefCounted
## OBSTACLE RUSH: how a jelly-bean runner looks. Everything is baked with core/mesh_kit.gd into a few
## cached meshes, so a whole runner (body, face, pattern and costume) is ONE draw call, plus small
## limb meshes that wobble on their own. Origin at the feet, front = -Z (Godot forward).
## Costumes are hats and add-ons; patterns are stripes or spots; colours come from the player colour
## (TV players) or the CPU palette.

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

const VERSION := "v2"
const HEIGHT := 1.12
const RADIUS := 0.36
const COSTUMES: Array[String] = ["party_hat", "bunny", "chef", "top_hat", "viking", "propeller", "cat",
	"antenna", "flower", "dino", "unicorn", "cap", "pirate"]
## Display names for the costumes (title screen / lobby).
const COSTUME_NAMES := {"party_hat": "PARTY HAT", "bunny": "BUNNY EARS", "chef": "CHEF", "top_hat": "TOP HAT",
	"viking": "VIKING", "propeller": "PROPELLER", "cat": "KITTY", "antenna": "ALIEN", "flower": "FLOWER",
	"dino": "DINO", "unicorn": "UNICORN", "cap": "SPORTY", "pirate": "PIRATE"}
const PATTERNS: Array[String] = ["plain", "stripes", "spots", "belly"]
const CPU_NAMES: Array[String] = ["BLOBBY", "ZIPPY", "WOBBLES", "BEANO", "BOING", "SQUISHY", "NOODLE", "PUDDING"]
const CPU_COLORS: Array[Color] = [Color(1.0, 0.55, 0.3), Color(0.55, 0.9, 0.45), Color(0.95, 0.4, 0.45),
	Color(0.6, 0.5, 1.0), Color(1.0, 0.85, 0.35), Color(0.35, 0.85, 0.85), Color(1.0, 0.6, 0.8), Color(0.75, 0.75, 0.8)]
const SKIN_DARK := Color(0.08, 0.07, 0.12)
const EYE_WHITE := Color(0.98, 0.98, 1.0)
const CHEEK := Color(1.0, 0.55, 0.6)


## The body: bean, belly, face, pattern and costume, baked into one mesh (cached per look).
static func body_mesh(color: Color, costume: String, pattern: String) -> ArrayMesh:
	var key := "or_body_%s_%s_%s_%s" % [color.to_html(false), costume, pattern, VERSION]
	return ResCache.get_or_make(key, func() -> Resource: return _build_body(color, costume, pattern))


static func _build_body(color: Color, costume: String, pattern: String) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var light := color.lightened(0.45)
	# The bean: a capsule, a little wider at the bottom (a squashed sphere under it).
	b.capsule(RADIUS, HEIGHT, MeshKit.at(Vector3(0, HEIGHT * 0.5, 0)), color, 14)
	b.ellipsoid(Vector3(RADIUS * 1.04, 0.3, RADIUS * 1.04), MeshKit.at(Vector3(0, 0.32, 0)), color, 14)
	match pattern:
		"stripes":
			for y in [0.3, 0.52]:
				b.torus(RADIUS * 1.0, 0.045, MeshKit.at(Vector3(0, float(y), 0), Vector3(1.03, 1.0, 1.03)), light, 16, 6)
		"spots":
			var spots: Array[Vector3] = [Vector3(0.7, 0.25, 0.3), Vector3(-0.8, 0.45, 0.2), Vector3(0.5, 0.6, 0.75),
				Vector3(-0.3, 0.2, 0.9), Vector3(0.9, 0.5, -0.1), Vector3(-0.85, 0.75, 0.5)]
			for s in spots:
				var dir := Vector3(s.x, 0.0, s.z).normalized()
				var pos := dir * RADIUS * 0.98 + Vector3(0, 0.22 + s.y * 0.7, 0)
				b.ellipsoid(Vector3(0.08, 0.08, 0.025), MeshKit.aim(pos, Vector3.UP, Vector3.ONE) * Transform3D(Basis.looking_at(dir), Vector3.ZERO), light, 8)
		"belly":
			b.ellipsoid(Vector3(0.25, 0.3, 0.1), MeshKit.at(Vector3(0, 0.42, -RADIUS * 0.82)), light, 12)
		_:
			pass
	# Face (front = -Z): big shiny eyes, pupils, a smile and pink cheeks.
	for side in [-1.0, 1.0]:
		var sx: float = side
		b.ellipsoid(Vector3(0.1, 0.12, 0.06), MeshKit.at(Vector3(sx * 0.12, 0.84, -0.31)), EYE_WHITE, 10)
		b.sphere(0.055, MeshKit.at(Vector3(sx * 0.115, 0.83, -0.36)), SKIN_DARK, 8)
		b.sphere(0.018, MeshKit.at(Vector3(sx * 0.1, 0.86, -0.405)), Color.WHITE, 6)
		b.ellipsoid(Vector3(0.06, 0.035, 0.02), MeshKit.at(Vector3(sx * 0.22, 0.71, -0.29)), CHEEK, 8)
	b.ellipsoid(Vector3(0.07, 0.03, 0.025), MeshKit.at(Vector3(0, 0.69, -0.345)), SKIN_DARK, 8)
	_costume(b, costume, color)
	return b.build()


static func _costume(b: MeshKit.Builder, costume: String, color: Color) -> void:
	var top := HEIGHT - 0.02
	match costume:
		"party_hat":
			var hc := Color(0.35, 0.8, 1.0) if color.h > 0.5 or color.s < 0.3 else Color(1.0, 0.4, 0.7)
			b.cone(0.17, 0.4, MeshKit.at(Vector3(0, top + 0.17, 0), Vector3.ONE, Vector3(0, 0, 0.15)), hc, 12)
			b.torus(0.15, 0.03, MeshKit.at(Vector3(0, top + 0.02, 0)), Color(1.0, 0.95, 0.4), 12, 6)
			b.sphere(0.07, MeshKit.at(Vector3(0.055, top + 0.38, 0)), Color(1.0, 0.95, 0.4), 8)
		"bunny":
			for side in [-1.0, 1.0]:
				var sx: float = side
				var ear := MeshKit.at(Vector3(sx * 0.12, top + 0.2, 0.02), Vector3.ONE, Vector3(0, 0, -sx * 0.25))
				b.ellipsoid(Vector3(0.07, 0.24, 0.04), ear, Color(0.98, 0.96, 0.98), 10)
				b.ellipsoid(Vector3(0.035, 0.18, 0.02), ear * MeshKit.at(Vector3(0, 0.0, -0.03)), Color(1.0, 0.65, 0.75), 8)
		"chef":
			b.cylinder(0.2, 0.19, 0.18, MeshKit.at(Vector3(0, top + 0.05, 0)), Color.WHITE, 14)
			for k in 4:
				var a := TAU * k / 4.0
				b.sphere(0.13, MeshKit.at(Vector3(cos(a) * 0.1, top + 0.22, sin(a) * 0.1)), Color(0.98, 0.98, 0.98), 10)
			b.sphere(0.14, MeshKit.at(Vector3(0, top + 0.27, 0)), Color.WHITE, 10)
		"top_hat":
			b.cylinder(0.3, 0.3, 0.03, MeshKit.at(Vector3(0, top - 0.02, 0)), Color(0.12, 0.12, 0.16), 16)
			b.cylinder(0.17, 0.18, 0.34, MeshKit.at(Vector3(0, top + 0.16, 0)), Color(0.14, 0.14, 0.18), 14)
			b.cylinder(0.185, 0.185, 0.06, MeshKit.at(Vector3(0, top + 0.05, 0)), Color(0.9, 0.2, 0.3), 14)
		"viking":
			b.dome(0.3, MeshKit.at(Vector3(0, top - 0.17, 0)), Color(0.7, 0.72, 0.78), 14)
			b.torus(0.29, 0.035, MeshKit.at(Vector3(0, top - 0.16, 0)), Color(0.9, 0.75, 0.3), 14, 6)
			for side in [-1.0, 1.0]:
				var sx: float = side
				b.cone(0.07, 0.3, MeshKit.aim(Vector3(sx * 0.33, top, 0), Vector3(sx, 0.8, 0)), Color(0.98, 0.93, 0.8), 8)
		"propeller":
			b.dome(0.25, MeshKit.at(Vector3(0, top - 0.1, 0)), Color(0.3, 0.5, 1.0), 12)
			for k in 4:
				var a := TAU * k / 4.0
				b.dome(0.252, MeshKit.at(Vector3(0, top - 0.1, 0), Vector3(0.3, 1.0, 1.0), Vector3(0, a, 0)), Color(1.0, 0.9, 0.3), 12, false, false)
			b.cylinder(0.02, 0.02, 0.12, MeshKit.at(Vector3(0, top + 0.19, 0)), Color(0.3, 0.3, 0.35), 6)
			b.box(Vector3(0.5, 0.02, 0.07), MeshKit.at(Vector3(0, top + 0.25, 0), Vector3.ONE, Vector3(0, 0.6, 0)), Color(1.0, 0.3, 0.3))
		"cat":
			for side in [-1.0, 1.0]:
				var sx: float = side
				b.cone(0.1, 0.18, MeshKit.at(Vector3(sx * 0.16, top + 0.02, 0.0), Vector3(1, 1, 0.5), Vector3(0, 0, -sx * 0.3)), color.darkened(0.2), 8)
				b.cone(0.05, 0.1, MeshKit.at(Vector3(sx * 0.155, top + 0.0, -0.03), Vector3(1, 1, 0.4), Vector3(0, 0, -sx * 0.3)), Color(1.0, 0.7, 0.8), 6)
			for side in [-1.0, 1.0]:
				var sx2: float = side
				for k in 2:
					b.box(Vector3(0.18, 0.012, 0.012), MeshKit.at(Vector3(sx2 * 0.32, 0.72 + k * 0.04, -0.27), Vector3.ONE, Vector3(0, sx2 * 0.3, sx2 * (0.12 - k * 0.24))), SKIN_DARK)
		"antenna":
			for side in [-1.0, 1.0]:
				var sx: float = side
				var tip := Vector3(sx * 0.18, top + 0.32, 0.0)
				b.tube(Vector3(sx * 0.08, top - 0.05, 0), tip, 0.02, 0.015, Color(0.3, 0.9, 0.4), 6)
				b.sphere(0.06, MeshKit.at(tip), Color(0.6, 1.0, 0.5), 8)
		"flower":
			b.cylinder(0.015, 0.015, 0.16, MeshKit.at(Vector3(0.06, top + 0.05, 0)), Color(0.3, 0.7, 0.3), 6)
			var fc := Vector3(0.06, top + 0.16, 0)
			for k in 5:
				var a := TAU * k / 5.0
				b.ellipsoid(Vector3(0.07, 0.03, 0.05), MeshKit.at(fc + Vector3(cos(a) * 0.08, 0, sin(a) * 0.08), Vector3.ONE, Vector3(0, -a, 0)), Color(1.0, 0.55, 0.75), 8)
			b.sphere(0.05, MeshKit.at(fc + Vector3(0, 0.01, 0)), Color(1.0, 0.9, 0.3), 8)
		"dino":
			for k in 5:
				var t := float(k) / 4.0
				var ang := lerpf(-0.2, 2.0, t)
				var pos := Vector3(0, top - 0.05 - sin(ang) * 0.3 - t * 0.25, cos(ang) * 0.1 + t * 0.32)
				var dir := Vector3(0, cos(ang * 0.8), sin(ang * 0.8)).normalized()
				b.cone(0.07, 0.16, MeshKit.aim(pos, dir, Vector3(0.5, 1, 1)), Color(1.0, 0.85, 0.35), 6)
		"unicorn":
			b.cone(0.07, 0.34, MeshKit.aim(Vector3(0, top + 0.05, -0.18), Vector3(0, 1.0, -0.35)), Color(1.0, 0.85, 0.4), 10)
			b.torus(0.06, 0.012, MeshKit.aim(Vector3(0, top + 0.08, -0.19), Vector3(0, 1.0, -0.35)), Color(1.0, 0.6, 0.85), 10, 4)
			b.ellipsoid(Vector3(0.09, 0.2, 0.06), MeshKit.at(Vector3(0, top - 0.05, 0.25), Vector3.ONE, Vector3(0.5, 0, 0)), Color(0.75, 0.6, 1.0), 8)
		"cap":
			var cc := Color(0.95, 0.3, 0.3) if color.h > 0.15 and color.h < 0.85 else Color(0.25, 0.45, 1.0)
			b.dome(0.3, MeshKit.at(Vector3(0, top - 0.17, 0)), cc, 14)
			b.box(Vector3(0.36, 0.025, 0.24), MeshKit.at(Vector3(0, top - 0.15, -0.33), Vector3.ONE, Vector3(-0.15, 0, 0)), cc.darkened(0.2))
			b.sphere(0.03, MeshKit.at(Vector3(0, top + 0.13, 0)), Color.WHITE, 6)
		"pirate":
			b.dome(0.32, MeshKit.at(Vector3(0, top - 0.2, 0), Vector3(1.0, 0.95, 1.0)), Color(0.85, 0.15, 0.2), 14)
			for k in 7:
				var a := TAU * k / 7.0
				b.sphere(0.025, MeshKit.at(Vector3(cos(a) * 0.24, top - 0.06 + 0.04 * sin(a * 2.0), sin(a) * 0.24)), Color.WHITE, 6)
			b.sphere(0.07, MeshKit.at(Vector3(0.0, top - 0.12, 0.33)), Color(0.75, 0.1, 0.15), 8)
			b.ellipsoid(Vector3(0.05, 0.11, 0.03), MeshKit.at(Vector3(0.05, top - 0.25, 0.37), Vector3.ONE, Vector3(0, 0, 0.4)), Color(0.85, 0.15, 0.2), 8)
		_:
			pass


## A stubby arm (capsule) in the body colour; pivot at the shoulder (the arm hangs down -Y).
static func arm_mesh(color: Color) -> ArrayMesh:
	var key := "or_arm_%s_%s" % [color.to_html(false), VERSION]
	return ResCache.get_or_make(key, func() -> Resource:
		var b := MeshKit.Builder.new()
		b.capsule(0.075, 0.32, MeshKit.at(Vector3(0, -0.12, 0)), color, 8)
		b.sphere(0.075, MeshKit.at(Vector3(0, -0.26, 0)), color.lightened(0.2), 8)
		return b.build())


## A little oval foot; pivot at the ankle.
static func foot_mesh(color: Color) -> ArrayMesh:
	var key := "or_foot_%s_%s" % [color.to_html(false), VERSION]
	return ResCache.get_or_make(key, func() -> Resource:
		var b := MeshKit.Builder.new()
		b.ellipsoid(Vector3(0.1, 0.065, 0.15), MeshKit.at(Vector3(0, 0.05, -0.04)), color.darkened(0.35), 8)
		return b.build())


## The golden crown (the episode prize, and the champion's hat on the podium). Origin at its base.
static func crown_mesh() -> ArrayMesh:
	return ResCache.get_or_make("or_crown_" + VERSION, func() -> Resource:
		var b := MeshKit.Builder.new()
		var gold := Color(1.0, 0.82, 0.25)
		b.cylinder(0.3, 0.28, 0.2, MeshKit.at(Vector3(0, 0.1, 0)), gold, 16, false, false)
		b.cylinder(0.27, 0.25, 0.2, MeshKit.at(Vector3(0, 0.1, 0)), gold.darkened(0.25), 16, false, false)
		for k in 6:
			var a := TAU * k / 6.0
			var p := Vector3(cos(a) * 0.28, 0.27, sin(a) * 0.28)
			b.cone(0.07, 0.2, MeshKit.at(p), gold, 6)
			b.sphere(0.04, MeshKit.at(p + Vector3(0, 0.12, 0)), Color(1.0, 0.95, 0.7), 6, true)
		for k in 6:
			var a2 := TAU * (k + 0.5) / 6.0
			var gem := [Color(1.0, 0.25, 0.4), Color(0.3, 0.6, 1.0), Color(0.4, 1.0, 0.5)][k % 3] as Color
			b.sphere(0.045, MeshKit.at(Vector3(cos(a2) * 0.29, 0.1, sin(a2) * 0.29)), gem, 6, true)
		return b.build())


## A fluffy striped tail for TAIL TAG. Origin where it attaches; it sticks out along +Z (the back).
static func tail_mesh() -> ArrayMesh:
	return ResCache.get_or_make("or_tail_" + VERSION, func() -> Resource:
		var b := MeshKit.Builder.new()
		var cols: Array[Color] = [Color(1.0, 0.55, 0.15), Color(1.0, 0.95, 0.85)]
		for k in 5:
			var t := float(k) / 4.0
			var p := Vector3(0, 0.05 + sin(t * 2.2) * 0.25, 0.08 + t * 0.42)
			b.sphere(0.11 - t * 0.02, MeshKit.at(p, Vector3(1.0, 1.0, 1.25)), cols[k % 2], 8)
		b.sphere(0.1, MeshKit.at(Vector3(0, 0.33, 0.55)), Color(1.0, 0.98, 0.95), 8)
		return b.build())


## A floating marker (diamond) above a runner, seen from the Game Master's booth (VR only).
static func marker_mesh(color: Color) -> ArrayMesh:
	var key := "or_marker_%s_%s" % [color.to_html(false), VERSION]
	return ResCache.get_or_make(key, func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cone(0.28, 0.45, MeshKit.at(Vector3(0, -0.22, 0), Vector3.ONE, Vector3(PI, 0, 0)), color, 4, true)
		b.cone(0.28, 0.2, MeshKit.at(Vector3(0, 0.1, 0)), color.lightened(0.3), 4, true)
		return b.build())


## A random look for a CPU runner (deterministic per index).
static func cpu_look(index: int) -> Dictionary:
	var k := absi(index)
	return {"name": CPU_NAMES[k % CPU_NAMES.size()], "color": CPU_COLORS[k % CPU_COLORS.size()],
		"costume": COSTUMES[(k * 5 + 3) % COSTUMES.size()], "pattern": PATTERNS[(k * 3 + 1) % PATTERNS.size()], "cpu": true}


## The look for a TV player's seat (player colour, a costume per slot; `pick` cycles costumes).
static func player_look(slot: int, player_name: String, color: Color, pick: int = 0) -> Dictionary:
	return {"name": player_name, "color": color, "costume": COSTUMES[(slot * 3 + pick) % COSTUMES.size()],
		"pattern": PATTERNS[(slot + pick) % PATTERNS.size()], "cpu": false}
