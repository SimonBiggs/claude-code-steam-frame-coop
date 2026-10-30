extends Node3D
## Elemental Bender story things in 3D (every machine builds its own from the host's compact description):
##  - KIKO, the little temple fox, sitting in the middle of the temple: looks at the nearest player (or the VR
##    master), bounces when she talks, wags her tail with its four element tips, a gold crown after
##    WaveGen.CROWN_GENERALS Shadow Generals beaten
##  - the SHADOW PORTALS of the coming wave (WaveGen.gates): a swirling purple ring on the grass; the first glows
##  - the SPIRIT TREE beside the temple (grows with every wave cleared, over days) with a glowing fruit for every
##    General beaten, and a stone LANTERN round the temple steps for every play-day
## Static parts are merged into one mesh per group with MeshKit (a lit and a glow surface): a few draw calls (Deck / VR).

const MeshKit := preload("res://core/mesh_kit.gd")
const UiKit := preload("res://core/ui_kit.gd")
const World := preload("res://games/elemental_bender/world.gd")
const WaveGen := preload("res://games/elemental_bender/wavegen.gd")
const E := preload("res://games/elemental_bender/elem.gd")

const FUR := Color(0.95, 0.52, 0.18)
const CREAM := Color(1.0, 0.94, 0.84)
const DARK := Color(0.15, 0.08, 0.06)
const GOLD := Color(1.0, 0.8, 0.25)
const SHADOW := Color(0.35, 0.12, 0.5)
const STONE := Color(0.72, 0.7, 0.66)
const KIKO_AT := Vector3(0.0, World.DAIS_TOP, 0.0)

var main
var kiko: Node3D
var head: Node3D
var tail: Node3D
var crown: Node3D
var gate_root: Node3D
var keep_root: Node3D
var gate_key := ""
var keep_key := ""
var gate_nodes: Array = []
var fruit_count := -1
var stage_shown := -1
var cheer_t := 0.0
var t := 0.0


func _ready() -> void:
	gate_root = Node3D.new()
	add_child(gate_root)
	keep_root = Node3D.new()
	add_child(keep_root)
	_build_kiko()


# --- Kiko ---------------------------------------------------------------------------------------

func _build_kiko() -> void:
	kiko = Node3D.new()
	kiko.name = "Kiko"
	kiko.position = KIKO_AT
	add_child(kiko)
	var b := MeshKit.builder()
	b.ellipsoid(Vector3(0.26, 0.3, 0.32), MeshKit.at(Vector3(0, 0.3, 0.02)), FUR, 12)  # body (sitting)
	b.ellipsoid(Vector3(0.16, 0.2, 0.1), MeshKit.at(Vector3(0, 0.33, -0.22)), CREAM, 10)  # chest
	for sx in [-0.12, 0.12]:
		b.ellipsoid(Vector3(0.07, 0.06, 0.12), MeshKit.at(Vector3(sx, 0.05, -0.2)), FUR.darkened(0.1), 8)  # paws
	kiko.add_child(MeshKit.instance(b.build(), true))
	head = Node3D.new()
	head.position = Vector3(0, 0.72, -0.08)
	kiko.add_child(head)
	var h := MeshKit.builder()
	h.sphere(0.22, MeshKit.at(Vector3.ZERO), FUR, 12)
	h.ellipsoid(Vector3(0.12, 0.09, 0.14), MeshKit.at(Vector3(0, -0.06, -0.18)), CREAM, 10)  # muzzle
	h.sphere(0.04, MeshKit.at(Vector3(0, -0.03, -0.32)), DARK, 8)  # nose
	for sx in [-1.0, 1.0]:
		h.cone(0.09, 0.26, MeshKit.at(Vector3(sx * 0.13, 0.25, 0.0), Vector3.ONE, Vector3(0, 0, -sx * 0.3)), FUR, 8)
		h.cone(0.05, 0.16, MeshKit.at(Vector3(sx * 0.125, 0.24, -0.04), Vector3.ONE, Vector3(0, 0, -sx * 0.3)), DARK.lightened(0.15), 6)
		h.sphere(0.05, MeshKit.at(Vector3(sx * 0.085, 0.04, -0.18), Vector3(1.0, 1.15, 0.6)), Color(1, 1, 0.97), 8)
		h.sphere(0.03, MeshKit.at(Vector3(sx * 0.085, 0.035, -0.21)), DARK, 6)
		h.sphere(0.035, MeshKit.at(Vector3(sx * 0.15, -0.05, -0.15), Vector3(1.0, 0.6, 0.5)), Color(1.0, 0.55, 0.5), 6)
	head.add_child(MeshKit.instance(h.build(), false))
	tail = Node3D.new()
	tail.position = Vector3(0, 0.12, 0.3)
	kiko.add_child(tail)
	var tb := MeshKit.builder()
	tb.ellipsoid(Vector3(0.13, 0.13, 0.32), MeshKit.at(Vector3(0, 0.12, 0.22), Vector3.ONE, Vector3(-0.6, 0, 0)), FUR, 10)
	for k in 4:
		var a := k * TAU / 4.0
		tb.sphere(0.07, MeshKit.at(Vector3(cos(a) * 0.06, 0.38 + sin(a) * 0.04, 0.42 + sin(a) * 0.04)), E.COLORS[k], 8, true)
	tail.add_child(MeshKit.instance(tb.build(), false))
	crown = Node3D.new()
	crown.position = Vector3(0, 0.22, 0)
	head.add_child(crown)
	var cb := MeshKit.builder()
	cb.cylinder(0.13, 0.12, 0.08, MeshKit.at(Vector3.ZERO), GOLD, 12)
	for i in 5:
		var a := TAU * i / 5.0
		cb.cone(0.035, 0.1, MeshKit.at(Vector3(cos(a) * 0.11, 0.08, sin(a) * 0.11)), GOLD, 6)
	crown.add_child(MeshKit.instance(cb.build(MeshKit.material(GOLD, 1.0)), false))
	crown.visible = false


## Every frame: Kiko breathes, wags and looks at `at` (a player, the VR head).
func update_kiko(delta: float, at: Vector3) -> void:
	t += delta
	cheer_t = maxf(0.0, cheer_t - delta)
	var hop := absf(sin(cheer_t * 9.0)) * 0.3 * cheer_t
	kiko.position = KIKO_AT + Vector3.UP * hop
	kiko.scale = Vector3(1.0, 1.0 + sin(t * 2.4) * 0.02, 1.0) * 1.4
	var flat := Vector3(at.x, 0.0, at.z) - Vector3(KIKO_AT.x, 0.0, KIKO_AT.z)
	if flat.length() > 0.2:
		var want := atan2(-flat.x, -flat.z)
		kiko.rotation.y = lerp_angle(kiko.rotation.y, want, 1.0 - exp(-3.0 * delta))
	head.rotation.z = sin(t * 1.3) * 0.08 + sin(cheer_t * 12.0) * 0.15 * cheer_t
	tail.rotation.y = sin(t * (8.0 if cheer_t > 0.0 else 2.5)) * 0.35
	for g in gate_nodes:
		if is_instance_valid(g):
			(g as Node3D).rotation.y = t * 1.2


func cheer() -> void:
	cheer_t = 1.2


# --- Portals ------------------------------------------------------------------------------------

## The coming wave's portals ([] takes them away). Rebuilt only when they change.
func set_gates(points: Array) -> void:
	var key := str(points)
	if key == gate_key:
		return
	gate_key = key
	for c in gate_root.get_children():
		c.queue_free()
	gate_nodes.clear()
	for i in points.size():
		var p: Vector3 = points[i]
		var n := Node3D.new()
		n.position = p + Vector3.UP * 0.05
		gate_root.add_child(n)
		var b := MeshKit.builder()
		b.disc(1.6, MeshKit.at(Vector3.UP * 0.02), SHADOW.darkened(0.5), 20)
		b.torus(1.6, 0.14, MeshKit.at(Vector3.UP * 0.1), SHADOW.lightened(0.35 if i == 0 else 0.15), 20, 6, true)
		b.torus(1.25, 0.12, MeshKit.at(Vector3.UP * 1.45, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), SHADOW.lightened(0.3), 20, 6, true)
		b.disc(1.15, MeshKit.at(Vector3.UP * 1.45, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), SHADOW.darkened(0.3), 20, false, true)
		for k in 3:
			var a := k * TAU / 3.0
			b.sphere(0.16, MeshKit.at(Vector3(cos(a) * 0.9, 0.25, sin(a) * 0.9)), Color(0.75, 0.5, 1.0), 6, true)
		var mi := MeshKit.instance(b.build(), false)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
		n.scale = Vector3.ONE * 0.01
		create_tween().tween_property(n, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		gate_nodes.append(n)


# --- Spirit Tree, fruit and lanterns -------------------------------------------------------------

## waves: waves cleared over all days (the tree's size), fruit: [element of each General beaten] (oldest first),
## days: play-days (lanterns), crowned: Kiko's crown.
func set_keepsakes(waves: int, fruit: Array, days: int, crowned: bool) -> void:
	var key := "%d|%s|%d|%s" % [waves, str(fruit), days, crowned]
	if key == keep_key:
		return
	keep_key = key
	crown.visible = crowned
	for c in keep_root.get_children():
		c.queue_free()
	var stage := WaveGen.tree_stage(waves)
	var b := MeshKit.builder()
	var at := WaveGen.TREE_AT
	b.dome(1.2 + stage * 0.25, MeshKit.at(at, Vector3(1.0, 0.35, 1.0)), Color(0.3, 0.52, 0.24), 12)  # its mound
	var h := WaveGen.tree_height(stage)
	var cr := WaveGen.crown_r(stage)
	if stage == 0:
		b.sphere(0.18, MeshKit.at(at + Vector3.UP * 0.3), Color(0.5, 0.33, 0.18), 8)  # a seed
		b.cone(0.05, 0.2, MeshKit.at(at + Vector3.UP * 0.5), Color(0.4, 0.75, 0.3), 6)
	else:
		var trunk := 0.06 + stage * 0.06
		b.cylinder(trunk * 0.7, trunk, h - cr * 0.6, MeshKit.at(at + Vector3.UP * (h - cr * 0.6) * 0.5), Color(0.45, 0.3, 0.17), 8)
		var pink := Color(1.0, 0.68, 0.8)
		b.sphere(cr, MeshKit.at(at + Vector3.UP * h), pink if stage >= 3 else Color(0.35, 0.68, 0.3), 12)
		if stage >= 2:
			for k in 3:
				var a := k * TAU / 3.0 + 0.5
				b.sphere(cr * 0.62, MeshKit.at(at + Vector3(cos(a) * cr * 0.75, h - cr * 0.35, sin(a) * cr * 0.75)),
					(pink if stage >= 3 else Color(0.35, 0.68, 0.3)).darkened(0.06), 10)
	for i in WaveGen.lanterns(days):
		var p := WaveGen.lantern_slot(i)
		b.cylinder(0.22, 0.26, 0.2, MeshKit.at(p + Vector3.UP * 0.1), STONE.darkened(0.1), 8)
		b.cylinder(0.08, 0.1, 0.55, MeshKit.at(p + Vector3.UP * 0.47), STONE, 6)
		b.cylinder(0.0, 0.32, 0.22, MeshKit.at(p + Vector3.UP * 1.08), STONE.darkened(0.15), 6)  # roof
		b.box(Vector3(0.26, 0.24, 0.26), MeshKit.at(p + Vector3.UP * 0.86), Color(1.0, 0.8, 0.4), true)  # the light
	var mi := MeshKit.instance(b.build(), true)
	mi.name = "Tree"
	keep_root.add_child(mi)
	if stage >= 1 and not fruit.is_empty():
		var fb := MeshKit.builder()
		var shown := fruit.slice(maxi(0, fruit.size() - WaveGen.FRUIT_MAX))
		for i in shown.size():
			var fp := WaveGen.fruit_slot(i, stage)
			fb.sphere(0.16 + stage * 0.02, MeshKit.at(at + fp), E.COLORS[clampi(int(shown[i]), 0, 3)], 8, true)
		var fm := MeshKit.instance(fb.build(), false)
		fm.name = "Fruit"
		keep_root.add_child(fm)
	if main != null and ((fruit_count >= 0 and fruit.size() > fruit_count) or (stage_shown >= 0 and stage > stage_shown)):
		main.call("tree_burst", at + Vector3.UP * h)
	fruit_count = fruit.size()
	stage_shown = stage
