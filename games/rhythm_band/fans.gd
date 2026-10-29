extends Node3D
## The story you can see: DOODLE the frog singing on top of the left speaker stack, and the FAN CLUB
## stands left and right of the stage, where every song the band finishes brings a new animal fan
## (saved; songgen.gd fan_slot / fan_stage). Fans grow a little each day the family plays (a glow stick
## at full size); fans from TODAY'S SONG are golden with a crown. Everyone bounces on the beat.
## Cheap: each fan is one merged mesh (mesh_kit.gd); a few dozen nodes moved per frame at most.
##   var fc := FanClub.new(); fc.main = main; add_child(fc); fc.build()
##   fc.set_fans(list, days)    # list: [[kind, joined_day, golden], ...] (oldest first)
##   fc.update(delta, beat_pos, energy, golden_song)   # every frame
##   fc.cheer()                 # Doodle hops (a new fan)

const MeshKit := preload("res://games/rhythm_band/mesh_kit.gd")
const G := preload("res://games/rhythm_band/songgen.gd")

const FAN_COLORS := {
	"bunny": [Color(0.97, 0.95, 0.95), Color(1.0, 0.7, 0.8)],
	"puppy": [Color(0.78, 0.55, 0.32), Color(0.45, 0.28, 0.15)],
	"penguin": [Color(0.12, 0.12, 0.18), Color(1.0, 0.65, 0.15)],
	"polarbear": [Color(0.95, 0.96, 1.0), Color(0.2, 0.2, 0.25)],
	"toucan": [Color(0.1, 0.1, 0.12), Color(1.0, 0.55, 0.1)],
	"sheep": [Color(0.96, 0.95, 0.9), Color(0.18, 0.15, 0.15)],
}
const GLOW: Array[Color] = [Color(0.3, 1.0, 0.5), Color(1.0, 0.35, 0.8), Color(0.35, 0.8, 1.0), Color(1.0, 0.9, 0.3)]

var main
var t := 0.0
var fans: Array[Node3D] = []
var fan_base: Array[float] = []
var doodle: Node3D
var doodle_hop := 0.0
var crown: Node3D
var stands: MeshInstance3D
var _key := ""


func build() -> void:
	_build_stands()
	_build_doodle()


## The two FAN CLUB stands: three steps each, beside the stage.
func _build_stands() -> void:
	var parts: Array = []
	var wood := Color(0.32, 0.22, 0.4)
	for side in [-1.0, 1.0]:
		var sd: float = side
		for row in 3:
			var x := sd * (G.STAND_X + row * G.ROW_STEP.x)
			var h := 0.25 + row * G.ROW_STEP.y
			parts.append([MeshKit.box(Vector3(G.ROW_STEP.x, h, 3.2)), MeshKit.at(Vector3(x, h * 0.5, -1.27)), wood.lightened(0.08 * row)])
			parts.append([MeshKit.box(Vector3(G.ROW_STEP.x + 0.02, 0.04, 3.22)), MeshKit.at(Vector3(x, h, -1.27)), Color(1.0, 0.45, 0.8) if row % 2 == 0 else Color(0.4, 0.8, 1.0)])
	stands = MeshInstance3D.new()
	stands.mesh = MeshKit.merge(parts)
	stands.material_override = MeshKit.vertex_material(main.mats)
	stands.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stands)


## Doodle: a round green frog with a bow tie and a microphone, on the left speaker stack.
func _build_doodle() -> void:
	doodle = Node3D.new()
	doodle.name = "Doodle"
	doodle.position = G.DOODLE_POS
	doodle.rotation.y = PI + 0.5  # face the crowd, turned a little to the middle
	add_child(doodle)
	var green := Color(0.35, 0.8, 0.3)
	var parts: Array = [
		[MeshKit.sphere(0.24, 14), MeshKit.at(Vector3(0, 0.22, 0), Vector3(1.0, 0.85, 0.9)), green],
		[MeshKit.sphere(0.16, 12), MeshKit.at(Vector3(0, 0.2, 0.12), Vector3(1.0, 0.9, 0.5)), Color(0.78, 0.95, 0.6)],
		[MeshKit.sphere(0.2, 14), MeshKit.at(Vector3(0, 0.5, 0.02), Vector3(1.1, 0.8, 0.95)), green],
		[MeshKit.sphere(0.075, 10), MeshKit.at(Vector3(-0.1, 0.64, 0.06)), green],
		[MeshKit.sphere(0.075, 10), MeshKit.at(Vector3(0.1, 0.64, 0.06)), green],
		[MeshKit.sphere(0.055, 10), MeshKit.at(Vector3(-0.1, 0.66, 0.11)), Color.WHITE],
		[MeshKit.sphere(0.055, 10), MeshKit.at(Vector3(0.1, 0.66, 0.11)), Color.WHITE],
		[MeshKit.sphere(0.03, 8), MeshKit.at(Vector3(-0.1, 0.665, 0.155)), Color(0.08, 0.08, 0.1)],
		[MeshKit.sphere(0.03, 8), MeshKit.at(Vector3(0.1, 0.665, 0.155)), Color(0.08, 0.08, 0.1)],
		[MeshKit.sphere(0.06, 8), MeshKit.at(Vector3(0, 0.45, 0.17), Vector3(1.6, 0.5, 0.5)), Color(0.75, 0.15, 0.25)],
		[MeshKit.box(Vector3(0.16, 0.07, 0.04)), MeshKit.at(Vector3(0, 0.33, 0.19)), Color(1.0, 0.3, 0.5)],
		[MeshKit.sphere(0.07, 8), MeshKit.at(Vector3(-0.15, 0.04, 0.12), Vector3(1.3, 0.5, 1.4)), green.darkened(0.1)],
		[MeshKit.sphere(0.07, 8), MeshKit.at(Vector3(0.15, 0.04, 0.12), Vector3(1.3, 0.5, 1.4)), green.darkened(0.1)],
		[MeshKit.cyl(0.012, 0.012, 0.22, 6), MeshKit.at(Vector3(0.16, 0.3, 0.22), Vector3.ONE, Vector3(0.5, 0, 0)), Color(0.4, 0.4, 0.45)],
		[MeshKit.sphere(0.045, 8), MeshKit.at(Vector3(0.16, 0.41, 0.28), Vector3(1, 1.3, 1)), Color(0.22, 0.22, 0.26)],
	]
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = MeshKit.merge(parts)
	mi.material_override = MeshKit.vertex_material(main.mats)
	mi.scale = Vector3.ONE * 1.3
	doodle.add_child(mi)
	crown = _crown(Vector3(0, 0.98, 0.0), 1.3)
	crown.visible = false
	doodle.add_child(crown)


func _crown(at: Vector3, s: float) -> Node3D:
	var parts: Array = [[MeshKit.cyl(0.09, 0.09, 0.06, 10), MeshKit.at(Vector3.ZERO), Color(1.0, 0.8, 0.2)]]
	for k in 5:
		var a := TAU * k / 5.0
		parts.append([MeshKit.sphere(0.03, 6), MeshKit.at(Vector3(cos(a) * 0.08, 0.06, sin(a) * 0.08)), Color(1.0, 0.85, 0.3)])
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.merge(parts)
	mi.material_override = main.make_material(Color(1.0, 0.8, 0.25), 0.8)
	mi.position = at
	mi.scale = Vector3.ONE * s
	return mi


## (Re)build the fans when the list or the day changes.
func set_fans(list: Array, days: int) -> void:
	var key := var_to_str([list, days])
	if key == _key:
		return
	_key = key
	for f in fans:
		f.queue_free()
	fans.clear()
	fan_base.clear()
	for i in mini(list.size(), G.FAN_SLOTS):
		var e: Array = list[i]
		var at := G.fan_slot(i)
		var stage_n := G.fan_stage(int(e[1]), days)
		var f := _fan(G.FAN_KINDS[posmod(int(e[0]), G.FAN_KINDS.size())], stage_n, bool(e[2]) if e.size() > 2 else false, i)
		f.position = at
		f.rotation.y = -PI * 0.5 * signf(at.x) + (at.z + 1.2) * 0.25 * signf(at.x)  # face the stage
		add_child(f)
		fans.append(f)
		fan_base.append(at.y)


## One animal fan: body, head, the kind's ears / beak, arms up; bigger each stage, a glow stick at the top.
func _fan(kind: String, stage_n: int, golden: bool, i: int) -> Node3D:
	var cols: Array = FAN_COLORS.get(kind, [Color.WHITE, Color.GRAY])
	var c: Color = cols[0]
	var c2: Color = cols[1]
	var parts: Array = [
		[MeshKit.sphere(0.17, 10), MeshKit.at(Vector3(0, 0.2, 0), Vector3(1.0, 1.15, 0.9)), c],
		[MeshKit.sphere(0.14, 10), MeshKit.at(Vector3(0, 0.47, 0)), c],
		[MeshKit.sphere(0.035, 6), MeshKit.at(Vector3(-0.05, 0.5, 0.12)), Color(0.08, 0.08, 0.1)],
		[MeshKit.sphere(0.035, 6), MeshKit.at(Vector3(0.05, 0.5, 0.12)), Color(0.08, 0.08, 0.1)],
		[MeshKit.sphere(0.045, 6), MeshKit.at(Vector3(-0.17, 0.4, 0.02), Vector3(0.8, 1.6, 0.8)), c],  # arms up
		[MeshKit.sphere(0.045, 6), MeshKit.at(Vector3(0.17, 0.4, 0.02), Vector3(0.8, 1.6, 0.8)), c],
	]
	match kind:
		"bunny":
			parts.append([MeshKit.sphere(0.05, 6), MeshKit.at(Vector3(-0.06, 0.66, 0), Vector3(0.7, 2.6, 0.5)), c])
			parts.append([MeshKit.sphere(0.05, 6), MeshKit.at(Vector3(0.06, 0.66, 0), Vector3(0.7, 2.6, 0.5)), c])
			parts.append([MeshKit.sphere(0.025, 6), MeshKit.at(Vector3(0, 0.45, 0.14)), c2])
		"puppy":
			parts.append([MeshKit.sphere(0.06, 6), MeshKit.at(Vector3(-0.13, 0.47, 0), Vector3(0.6, 1.5, 0.8)), c2])
			parts.append([MeshKit.sphere(0.06, 6), MeshKit.at(Vector3(0.13, 0.47, 0), Vector3(0.6, 1.5, 0.8)), c2])
			parts.append([MeshKit.sphere(0.03, 6), MeshKit.at(Vector3(0, 0.45, 0.14)), Color(0.1, 0.08, 0.08)])
		"penguin":
			parts.append([MeshKit.sphere(0.12, 8), MeshKit.at(Vector3(0, 0.2, 0.07), Vector3(1.0, 1.2, 0.6)), Color(0.96, 0.96, 0.96)])
			parts.append([MeshKit.sphere(0.035, 6), MeshKit.at(Vector3(0, 0.45, 0.14), Vector3(1.2, 0.6, 1.4)), c2])
		"polarbear":
			parts.append([MeshKit.sphere(0.045, 6), MeshKit.at(Vector3(-0.1, 0.59, 0)), c])
			parts.append([MeshKit.sphere(0.045, 6), MeshKit.at(Vector3(0.1, 0.59, 0)), c])
			parts.append([MeshKit.sphere(0.028, 6), MeshKit.at(Vector3(0, 0.45, 0.14)), c2])
		"toucan":
			parts.append([MeshKit.sphere(0.06, 8), MeshKit.at(Vector3(0, 0.44, 0.17), Vector3(0.8, 0.7, 1.9)), c2])
			parts.append([MeshKit.sphere(0.09, 8), MeshKit.at(Vector3(0, 0.3, 0.09), Vector3(1.0, 0.8, 0.5)), Color(1.0, 0.95, 0.6)])
		"sheep":
			for k in 6:
				var a := TAU * k / 6.0
				parts.append([MeshKit.sphere(0.07, 6), MeshKit.at(Vector3(cos(a) * 0.12, 0.25 + sin(a) * 0.1, 0.0)), c])
			parts.append([MeshKit.sphere(0.1, 8), MeshKit.at(Vector3(0, 0.47, 0.05), Vector3(0.9, 1.0, 0.9)), c2])
			parts.append([MeshKit.sphere(0.03, 6), MeshKit.at(Vector3(-0.05, 0.5, 0.13)), Color.WHITE])
			parts.append([MeshKit.sphere(0.03, 6), MeshKit.at(Vector3(0.05, 0.5, 0.13)), Color.WHITE])
	if stage_n >= G.FAN_STAGES - 1:  # grown up: a glow stick
		parts.append([MeshKit.cyl(0.018, 0.018, 0.22, 6), MeshKit.at(Vector3(0.19, 0.6, 0.03)), GLOW[i % GLOW.size()]])
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.merge(parts)
	mi.material_override = MeshKit.vertex_material(main.mats)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	root.scale = Vector3.ONE * (0.75 + 0.2 * stage_n)
	if golden:
		var cr := _crown(Vector3(0, 0.62, 0), 0.8)
		root.add_child(cr)
	return root


## A new fan: Doodle hops.
func cheer() -> void:
	doodle_hop = 1.0


func update(delta: float, beat_pos: float, energy: float, golden_song: bool) -> void:
	t += delta
	doodle_hop = maxf(0.0, doodle_hop - delta * 1.2)
	if doodle != null:
		var b := absf(sin(PI * beat_pos))
		doodle.position.y = G.DOODLE_POS.y + b * (0.04 + 0.06 * energy) + sin(doodle_hop * PI) * 0.35
		doodle.rotation.z = sin(PI * beat_pos * 0.5) * 0.08
		crown.visible = golden_song
	for i in fans.size():
		var f := fans[i]
		var ph := beat_pos + (i % 3) * 0.17
		f.position.y = fan_base[i] + absf(sin(PI * ph)) * (0.03 + 0.08 * energy)
