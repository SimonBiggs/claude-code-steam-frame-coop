extends Node3D
## MANGO'S FESTIVAL (SIMPLE_MODE story): Mango the toucan throws the parties on Party Island. After every
## party the winner picks what Mango builds next for the island's big festival (two pictures: bonk / point
## at one), and it stays for good (saved): bunting, a balloon arch over START, lanterns round the coast,
## a music stage, a candy fountain, a fireworks tower, a giant trophy, a party cake. Every party's winner
## also plants a flag in their colour by START (the last FLAGS winners). After all eight pieces the
## festival is complete and the flags keep coming. More pieces built = a slightly trickier board
## (partygen.gd level). The host owns the save and publishes {built, flags}; every machine draws it.
## Lives under main.stage (board units). Cheap: one merged mesh for everything built, one for the flags.

const MeshKit := preload("res://core/mesh_kit.gd")
const BD := preload("res://games/party_board/board_data.gd")

const FLAGS := 12
const MANGO_COLOR := Color(1.0, 0.6, 0.15)
## The festival pieces: id, the menu word and icon (core/ui_kit.gd icons), Mango's line when built.
const DECOS: Array[Dictionary] = [
	{"id": "bunting", "word": "FLAGS", "icon": "flag", "line": "FLAGS!"},
	{"id": "arch", "word": "BALLOONS", "icon": "heart", "line": "BALLOONS!"},
	{"id": "lanterns", "word": "LANTERNS", "icon": "bolt", "line": "LANTERNS!"},
	{"id": "stage", "word": "MUSIC", "icon": "music", "line": "MUSIC!"},
	{"id": "fountain", "word": "FOUNTAIN", "icon": "gem", "line": "FOUNTAIN!"},
	{"id": "fireworks", "word": "FIREWORKS", "icon": "star", "line": "FIREWORKS!"},
	{"id": "trophy", "word": "TROPHY", "icon": "trophy", "line": "TROPHY!"},
	{"id": "cake", "word": "CAKE", "icon": "crown", "line": "CAKE! YUM!"},
]
## Where each piece stands: angle round the island (degrees, 0 = south / START, 90 = east) and radius.
const SPOTS := {"stage": [252.0, 12.25], "fountain": [104.0, 12.4], "fireworks": [150.0, 12.6], "trophy": [206.0, 13.0],
	"cake": [300.0, 12.6]}
const BALLOON_COLS: Array[Color] = [Color(1.0, 0.35, 0.4), Color(1.0, 0.85, 0.3), Color(0.35, 0.65, 1.0),
	Color(0.5, 0.9, 0.45), Color(0.85, 0.5, 1.0)]

var main: Node
var built: Array = []
var flags: Array = []  # colour html strings, oldest first
var deco_mi: MeshInstance3D
var flag_mi: MeshInstance3D
var _t := 0.0
var _boom_t := 0.0


static func deco(id: String) -> Dictionary:
	for d in DECOS:
		if d.id == id:
			return d
	return {}


## The two pieces the winner may pick next (not built yet, in order; [] when the festival is complete).
static func offers(built_ids: Array) -> Array:
	var out: Array = []
	for d in DECOS:
		if not built_ids.has(d.id):
			out.append(d.id)
		if out.size() == 2:
			break
	return out


func _ready() -> void:
	deco_mi = MeshInstance3D.new()
	deco_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(deco_mi)
	flag_mi = MeshInstance3D.new()
	flag_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flag_mi)


## The festival from the host: {built: [ids], flags: [colour html]}. A new piece pops in with confetti.
func apply(s: Dictionary) -> void:
	var nb: Array = s.get("built", [])
	var nf: Array = s.get("flags", [])
	var grew := nb.size() > built.size() and _t > 1.0  # (not when a save loads)
	if var_to_str(nb) != var_to_str(built):
		built = nb.duplicate()
		deco_mi.mesh = _deco_mesh(built) if not built.is_empty() else null
		if grew:
			deco_mi.scale = Vector3(1.0, 0.2, 1.0)
			create_tween().tween_property(deco_mi, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if var_to_str(nf) != var_to_str(flags):
		flags = nf.duplicate()
		flag_mi.mesh = _flag_mesh(flags) if not flags.is_empty() else null


## Where a piece stands (board units, on the ground).
static func spot(id: String) -> Vector3:
	var s: Array = SPOTS.get(id, [0.0, 12.0])
	var a := deg_to_rad(float(s[0]))
	var x := sin(a) * float(s[1])
	var z := cos(a) * float(s[1])
	return Vector3(x, maxf(BD.height(x, z), 0.1), z)


static func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, maxf(BD.height(x, z), 0.1), z)


func _deco_mesh(ids: Array) -> ArrayMesh:
	var b := MeshKit.builder()
	var start: Vector3 = main.data.pos(0) if main != null and main.data != null else Vector3(0, 0.6, 10.2)
	for id in ids:
		match String(id):
			"bunting":  # two lines of little flags on poles either side of START
				for side in [-1.0, 1.0]:
					var a := deg_to_rad(side * 9.0)
					var p1 := _ground(sin(a) * 12.0, cos(a) * 12.0)
					var p2 := _ground(sin(a * 2.6) * 12.0, cos(a * 2.6) * 12.0)
					for p in [p1, p2]:
						b.cylinder(0.08, 0.1, 3.0, MeshKit.at(p + Vector3(0, 1.5, 0)), Color(0.95, 0.95, 0.9), 6)
					for k in 7:
						var f := (k + 0.5) / 7.0
						var q: Vector3 = p1.lerp(p2, f) + Vector3(0, 2.9 - sin(f * PI) * 0.6, 0)
						b.cone(0.22, 0.45, MeshKit.at(q + Vector3(0, -0.2, 0), Vector3(1, 1, 0.2), Vector3(PI, 0, 0)), BALLOON_COLS[k % BALLOON_COLS.size()], 4)
			"arch":  # a rainbow balloon arch over START
				var dir := Vector3(start.x, 0, start.z).normalized()
				var side := Vector3(dir.z, 0, -dir.x)
				for k in 15:
					var f := float(k) / 14.0
					var ang := f * PI
					var q := start + side * cos(ang) * 1.6 + Vector3(0, sin(ang) * 2.4 + 0.2, 0)
					b.sphere(0.36, MeshKit.at(q), BALLOON_COLS[k % BALLOON_COLS.size()], 10)
			"lanterns":  # glowing lantern posts round the coast
				for k in 10:
					var a := deg_to_rad(18.0 + k * 36.0)
					var p := _ground(sin(a) * 12.0, cos(a) * 12.0)
					b.cylinder(0.06, 0.08, 1.9, MeshKit.at(p + Vector3(0, 0.95, 0)), Color(0.3, 0.25, 0.25), 6)
					b.sphere(0.3, MeshKit.at(p + Vector3(0, 2.05, 0), Vector3(1, 1.25, 1)), Color(1.0, 0.75, 0.3), 10, true)
			"stage":
				var p := spot("stage")
				b.rounded_box(Vector3(2.4, 0.5, 1.6), 0.1, MeshKit.at(p + Vector3(0, 0.25, 0)), Color(0.7, 0.45, 0.3))
				b.box(Vector3(2.4, 2.2, 0.15), MeshKit.at(p + Vector3(0, 1.6, 0.75)), Color(0.85, 0.25, 0.35))
				for sx in [-1.0, 0.0, 1.0]:
					b.sphere(0.25, MeshKit.at(p + Vector3(sx, 2.9, 0.75)), Color(1.0, 0.9, 0.4), 8, true)
				b.cylinder(0.25, 0.3, 0.5, MeshKit.at(p + Vector3(-0.6, 0.75, 0)), Color(0.35, 0.55, 1.0), 10)  # a drum
				b.cylinder(0.04, 0.04, 1.0, MeshKit.at(p + Vector3(0.6, 1.0, 0)), Color(0.2, 0.2, 0.2), 6)  # a mic stand
				b.sphere(0.1, MeshKit.at(p + Vector3(0.6, 1.55, 0)), Color(0.25, 0.25, 0.3), 8)
			"fountain":
				var p := spot("fountain")
				b.cylinder(1.3, 1.4, 0.45, MeshKit.at(p + Vector3(0, 0.22, 0)), Color(1.0, 0.75, 0.85), 18)
				b.cylinder(1.1, 1.1, 0.06, MeshKit.at(p + Vector3(0, 0.44, 0)), Color(0.55, 0.85, 1.0), 18)
				b.cylinder(0.2, 0.25, 1.4, MeshKit.at(p + Vector3(0, 1.1, 0)), Color(0.95, 0.6, 0.8), 10)
				b.dome(0.6, MeshKit.at(p + Vector3(0, 1.8, 0), Vector3(1, -0.5, 1)), Color(0.55, 0.85, 1.0), 14)
				b.sphere(0.25, MeshKit.at(p + Vector3(0, 2.0, 0)), Color(1.0, 0.45, 0.7), 10, true)
			"fireworks":
				var p := spot("fireworks")
				for k in 4:
					var a := k * TAU / 4.0
					b.cylinder(0.07, 0.07, 3.2, MeshKit.at(p + Vector3(cos(a) * 0.6, 1.6, sin(a) * 0.6)), Color(0.55, 0.4, 0.3), 6)
				b.box(Vector3(1.6, 0.15, 1.6), MeshKit.at(p + Vector3(0, 3.2, 0)), Color(0.45, 0.32, 0.25))
				for k in 3:
					b.cylinder(0.14, 0.14, 0.8, MeshKit.at(p + Vector3(-0.4 + k * 0.4, 3.7, 0)), BALLOON_COLS[k], 8)
					b.cone(0.16, 0.3, MeshKit.at(p + Vector3(-0.4 + k * 0.4, 4.25, 0)), Color(1, 1, 1), 8)
			"trophy":
				var p := spot("trophy")
				b.rounded_box(Vector3(1.4, 0.6, 1.4), 0.08, MeshKit.at(p + Vector3(0, 0.3, 0)), Color(0.35, 0.3, 0.4))
				b.cylinder(0.18, 0.3, 0.8, MeshKit.at(p + Vector3(0, 1.0, 0)), Color(1.0, 0.8, 0.25), 12, true)
				b.dome(0.75, MeshKit.at(p + Vector3(0, 2.4, 0), Vector3(1, -1.1, 1)), Color(1.0, 0.82, 0.25), 16, true)
				for sx in [-1.0, 1.0]:
					b.torus(0.3, 0.07, MeshKit.at(p + Vector3(sx * 0.8, 2.0, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.8, 0.25), 12, 5, true)
			"cake":
				var p := spot("cake")
				var layers: Array[Color] = [Color(1.0, 0.75, 0.85), Color(1.0, 0.95, 0.85), Color(0.75, 0.55, 0.4)]
				for k in 3:
					var r := 1.2 - k * 0.32
					b.cylinder(r, r, 0.6, MeshKit.at(p + Vector3(0, 0.3 + k * 0.6, 0)), layers[k], 18)
					b.torus(r, 0.08, MeshKit.at(p + Vector3(0, 0.6 + k * 0.6, 0)), Color(1, 1, 1), 18, 5)
				for k in 5:
					var a := k * TAU / 5.0
					b.cylinder(0.05, 0.05, 0.4, MeshKit.at(p + Vector3(cos(a) * 0.3, 2.0, sin(a) * 0.3)), BALLOON_COLS[k], 6)
					b.sphere(0.07, MeshKit.at(p + Vector3(cos(a) * 0.3, 2.25, sin(a) * 0.3)), Color(1.0, 0.85, 0.3), 6, true)
	return b.build()


func _flag_mesh(cols: Array) -> ArrayMesh:
	var b := MeshKit.builder()
	for k in cols.size():
		var a := deg_to_rad(-26.0 + 52.0 * (float(k) + 0.5) / float(FLAGS))
		var p := _ground(sin(a) * 12.5, cos(a) * 12.5)
		b.cylinder(0.05, 0.06, 1.8, MeshKit.at(p + Vector3(0, 0.9, 0)), Color(0.95, 0.95, 0.9), 6)
		b.box(Vector3(0.7, 0.45, 0.05), MeshKit.at(p + Vector3(0.36, 1.55, 0)), Color.html(String(cols[k])))
		b.sphere(0.08, MeshKit.at(p + Vector3(0, 1.84, 0)), Color(1.0, 0.85, 0.3), 6)
	return b.build()


func _process(delta: float) -> void:
	_t += delta
	if built.has("fireworks") and main != null:
		_boom_t -= delta
		if _boom_t <= 0.0:
			_boom_t = randf_range(4.0, 8.0)
			_firework()


## A little firework over the tower now and then.
func _firework() -> void:
	var p := spot("fireworks") + Vector3(0, randf_range(7.0, 9.0), 0)
	var c := CPUParticles3D.new()
	c.one_shot = true
	c.amount = 28
	c.lifetime = 1.0
	c.explosiveness = 1.0
	c.spread = 180.0
	c.gravity = Vector3(0, -3.0, 0)
	c.initial_velocity_min = 2.0
	c.initial_velocity_max = 3.5
	var m := SphereMesh.new()
	m.radius = 0.12
	m.height = 0.24
	m.radial_segments = 6
	m.rings = 3
	m.material = MeshKit.material(BALLOON_COLS[randi() % BALLOON_COLS.size()], 2.0)
	c.mesh = m
	add_child(c)
	c.position = p
	c.emitting = true
	get_tree().create_timer(1.5).timeout.connect(c.queue_free)
