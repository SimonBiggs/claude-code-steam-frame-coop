extends Node3D
## Giant's Table story things in 3D (every machine builds its own from the host's compact description):
##  - SPARKY's face in the campfire (two eyes and a smile that look at the Giant, shrink with the fire, bounce on a
##    cheer, a gold crown after RaidGen.CROWN_NIGHTS saved nights)
##  - the goblin LADDERS of this wave leaning on the table edge, each with a little red flag (RaidGen.ladders)
##  - the villagers' GIFTS on the far rim (one per saved night, gold sparkle on TODAY'S RAID) and a LANTERN on a
##    post round the rim for every play-day
## Repeated meshes are merged by colour (world.gd Batch), so all of it is a handful of draw calls (Deck / VR 60 fps).

const W := preload("res://games/giants_table/world.gd")
const RaidGen := preload("res://games/giants_table/raidgen.gd")
const UiKit := preload("res://core/ui_kit.gd")

const WOOD := Color(0.72, 0.47, 0.24)
const FLAG := Color(0.95, 0.25, 0.2)
const GOLD := Color(1.0, 0.8, 0.25)
const GIFT_SIZE := 1.6  # gifts read from the VR seat (20x) and the knights' views

var main
var face: Node3D
var crown: Node3D
var ladder_root: Node3D
var keep_root: Node3D
var ladder_key := ""
var keep_key := ""
var gift_count := -1
var cheer_t := 0.0
var t := 0.0
var sparkles: Array = []
var ladder_nodes: Array = []


func _ready() -> void:
	ladder_root = Node3D.new()
	add_child(ladder_root)
	keep_root = Node3D.new()
	add_child(keep_root)
	_build_face()


# --- Sparky ---------------------------------------------------------------------------------------

func _build_face() -> void:
	face = Node3D.new()
	add_child(face)
	var white := _unshaded(Color(1.0, 1.0, 0.97))
	var dark := _unshaded(Color(0.18, 0.05, 0.03))
	for sx in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = W.sphere(0.1, 10)
		eye.material_override = white
		eye.position = Vector3(sx * 0.13, 0.08, 0.0)
		eye.scale = Vector3(1.0, 1.2, 0.5)
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		face.add_child(eye)
		var pupil := MeshInstance3D.new()
		pupil.mesh = W.sphere(0.055, 8)
		pupil.material_override = dark
		pupil.position = Vector3(sx * 0.13, 0.07, 0.05)
		pupil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		face.add_child(pupil)
	var mouth := MeshInstance3D.new()
	mouth.mesh = W.sphere(0.07, 10)
	mouth.material_override = dark
	mouth.position = Vector3(0.0, -0.1, 0.02)
	mouth.scale = Vector3(1.4, 0.7, 0.4)
	mouth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	face.add_child(mouth)
	crown = Node3D.new()
	add_child(crown)
	var gold := W.mat(GOLD, 1.2, 0.3)
	var band := MeshInstance3D.new()
	band.mesh = W.cyl(0.24, 0.22, 0.14, 12)
	band.material_override = gold
	crown.add_child(band)
	for i in 5:
		var a := TAU * i / 5.0
		var pt := MeshInstance3D.new()
		pt.mesh = W.cyl(0.0, 0.06, 0.16, 6)
		pt.material_override = gold
		pt.position = Vector3(cos(a) * 0.2, 0.14, sin(a) * 0.2)
		crown.add_child(pt)
	crown.visible = false


## Every frame: Sparky sits in the flames (smaller as the fire shrinks, gone when it's out) and looks at `at`.
func update_face(delta: float, strength: float, lit: bool, at: Vector3) -> void:
	t += delta
	cheer_t = maxf(0.0, cheer_t - delta)
	var s := 0.35 + 0.65 * clampf(strength, 0.0, 1.0)
	var hop := sin(cheer_t * 10.0) * 0.25 * cheer_t if cheer_t > 0.0 else 0.0
	var dir := Vector3(at.x, 0.0, at.z)
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.BACK
	face.visible = lit
	face.position = Vector3(0.0, 0.25 + 0.55 * s + absf(hop), 0.0) + dir * (0.34 * s)
	face.scale = Vector3.ONE * (0.75 + 0.45 * s) * (1.0 + sin(t * 2.2) * 0.04)
	UiKit.look(face, face.position + dir, Vector3.UP, true)
	crown.position = Vector3(0.0, 0.25 + 1.4 * s + 0.12 + absf(hop) + sin(t * 1.7) * 0.04, 0.0)
	crown.rotation.y = t * 0.4
	crown.visible = crown.has_meta("on") and lit
	for sp in sparkles:
		if is_instance_valid(sp):
			(sp as Node3D).position.y = float(sp.get_meta("y")) + sin(t * 2.0 + float(sp.get_meta("k"))) * 0.08
			(sp as Node3D).rotation.y = t * 1.5


func cheer() -> void:
	cheer_t = 1.2


# --- Ladders --------------------------------------------------------------------------------------

## This wave's ladders (angles); [] takes them away. Rebuilt only when they change.
func set_ladders(angles: Array) -> void:
	var key := str(angles)
	if key == ladder_key:
		return
	ladder_key = key
	for c in ladder_root.get_children():
		c.queue_free()
	ladder_nodes.clear()
	var wood := W.mat(WOOD)
	var flag := W.mat(FLAG, 0.6)
	for a in angles:
		var n := Node3D.new()
		ladder_root.add_child(n)
		var d := Vector3(cos(float(a)), 0.0, sin(float(a)))
		n.position = d * (W.EDGE + 0.22)
		n.basis = Basis(Vector3.UP, atan2(d.x, d.z))  # +Z points out from the table
		var b := W.Batch.new()
		var rail := W.box(Vector3(0.09, 4.0, 0.09))
		var lean := Basis(Vector3.RIGHT, -0.07)  # the top leans in onto the table edge
		for sx in [-0.32, 0.32]:
			b.add(rail, Transform3D(lean, lean * Vector3(sx, -1.3, 0.0)))
		var rung := W.box(Vector3(0.7, 0.07, 0.07))
		for k in 7:
			b.add(rung, Transform3D(lean, lean * Vector3(0.0, -3.0 + k * 0.5, 0.0)))
		b.build(n, wood)
		var pole := MeshInstance3D.new()
		pole.mesh = W.cyl(0.03, 0.03, 1.0, 6)
		pole.material_override = wood
		pole.position = lean * Vector3(0.32, 1.1, 0.0)
		n.add_child(pole)
		var fl := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.5, 0.6, 0.03)
		fl.mesh = pm
		fl.material_override = flag
		fl.rotation.z = -PI / 2.0
		fl.position = pole.position + Vector3(0.22, 0.35, 0.0)
		n.add_child(fl)
		n.scale = Vector3.ONE * 0.01
		create_tween().tween_property(n, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ladder_nodes.append(n)


# --- Gifts and lanterns -----------------------------------------------------------------------------

## gifts: [[kind, play-day, golden], ...] (oldest first), days: play-days so far, crowned: Sparky's crown.
func set_keepsakes(gifts: Array, days: int, crowned: bool) -> void:
	var key := "%s|%d|%s" % [str(gifts), days, crowned]
	if key == keep_key:
		return
	keep_key = key
	if crowned:
		crown.set_meta("on", true)
	elif crown.has_meta("on"):
		crown.remove_meta("on")
	for c in keep_root.get_children():
		c.queue_free()
	sparkles.clear()
	var parts := {}  # colour -> Batch
	var shown := gifts.slice(maxi(0, gifts.size() - RaidGen.GIFT_KEEP))
	for i in shown.size():
		var g: Array = shown[i]
		var pos := RaidGen.gift_slot(i)
		var xf := Transform3D(Basis(Vector3.UP, atan2(-pos.x, -pos.z)).scaled(Vector3.ONE * GIFT_SIZE), pos)
		_gift(parts, String(g[0]), xf)
		if g.size() > 2 and bool(g[2]):
			var sp := MeshInstance3D.new()
			sp.mesh = W.sphere(0.09, 8)
			sp.material_override = _unshaded(GOLD)
			sp.scale = Vector3(1.0, 1.4, 1.0)
			sp.position = pos + Vector3.UP * 1.05 * GIFT_SIZE
			sp.set_meta("y", sp.position.y)
			sp.set_meta("k", i)
			keep_root.add_child(sp)
			sparkles.append(sp)
	for i in RaidGen.lanterns(days):
		var pos := RaidGen.lantern_slot(i)
		_add(parts, WOOD.darkened(0.2), W.cyl(0.045, 0.055, 1.6, 6), Transform3D(Basis(), pos + Vector3.UP * 0.8))
		_add(parts, WOOD.darkened(0.3), W.cyl(0.19, 0.19, 0.05, 8), Transform3D(Basis(), pos + Vector3.UP * 1.93))
		_add(parts, Color(1.0, 0.78, 0.35), W.sphere(0.24, 10), Transform3D(Basis().scaled(Vector3(1.0, 1.25, 1.0)), pos + Vector3.UP * 1.65))
	for c in parts:
		var glow := 2.5 if c == Color(1.0, 0.78, 0.35) else 0.0
		var mi: MeshInstance3D = parts[c].build(keep_root, W.mat(c, glow) if glow == 0.0 else _unshaded(c))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if glow > 0.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if gift_count >= 0 and gifts.size() > gift_count and main != null:
		var p := RaidGen.gift_slot(mini(shown.size() - 1, RaidGen.GIFT_KEEP - 1))
		main.burst(p + Vector3.UP * 0.6, GOLD, 24, 0.12, false)
	gift_count = gifts.size()


func _gift(parts: Dictionary, kind: String, xf: Transform3D) -> void:
	match kind:
		"pie":
			_add(parts, Color(0.85, 0.6, 0.3), W.cyl(0.34, 0.28, 0.16, 14), xf * Transform3D(Basis(), Vector3(0, 0.08, 0)))
			_add(parts, Color(0.95, 0.75, 0.45), W.cyl(0.31, 0.33, 0.05, 14), xf * Transform3D(Basis(), Vector3(0, 0.18, 0)))
			for k in 3:
				var a := TAU * k / 3.0
				_add(parts, Color(0.85, 0.12, 0.15), W.sphere(0.06, 8), xf * Transform3D(Basis(), Vector3(cos(a) * 0.12, 0.23, sin(a) * 0.12)))
		"cake":
			_add(parts, Color(0.72, 0.48, 0.3), W.cyl(0.3, 0.3, 0.22, 14), xf * Transform3D(Basis(), Vector3(0, 0.11, 0)))
			_add(parts, Color(1.0, 0.72, 0.85), W.cyl(0.31, 0.31, 0.05, 14), xf * Transform3D(Basis(), Vector3(0, 0.23, 0)))
			_add(parts, Color(0.72, 0.48, 0.3), W.cyl(0.2, 0.2, 0.16, 12), xf * Transform3D(Basis(), Vector3(0, 0.33, 0)))
			_add(parts, Color(1.0, 0.72, 0.85), W.cyl(0.21, 0.21, 0.04, 12), xf * Transform3D(Basis(), Vector3(0, 0.42, 0)))
			_add(parts, Color(0.4, 0.65, 1.0), W.cyl(0.03, 0.03, 0.16, 6), xf * Transform3D(Basis(), Vector3(0, 0.52, 0)))
			_add(parts, Color(1.0, 0.85, 0.3), W.sphere(0.05, 6), xf * Transform3D(Basis(), Vector3(0, 0.64, 0)))
		"teddy":
			var c := Color(0.66, 0.44, 0.25)
			_add(parts, c, W.sphere(0.22, 12), xf * Transform3D(Basis(), Vector3(0, 0.22, 0)))
			_add(parts, c, W.sphere(0.17, 12), xf * Transform3D(Basis(), Vector3(0, 0.52, 0)))
			for sx in [-0.12, 0.12]:
				_add(parts, c, W.sphere(0.06, 8), xf * Transform3D(Basis(), Vector3(sx, 0.67, 0)))
				_add(parts, c, W.sphere(0.08, 8), xf * Transform3D(Basis(), Vector3(sx * 1.7, 0.28, 0.06)))
				_add(parts, Color(0.1, 0.07, 0.05), W.sphere(0.025, 6), xf * Transform3D(Basis(), Vector3(sx * 0.5, 0.56, 0.15)))
			_add(parts, Color(0.85, 0.7, 0.5), W.sphere(0.07, 8), xf * Transform3D(Basis(), Vector3(0, 0.48, 0.14)))
			_add(parts, Color(0.9, 0.25, 0.3), W.sphere(0.06, 8), xf * Transform3D(Basis().scaled(Vector3(1.8, 0.8, 0.8)), Vector3(0, 0.38, 0.12)))
		"scarf":
			var tm := TorusMesh.new()
			tm.inner_radius = 0.1
			tm.outer_radius = 0.24
			tm.rings = 12
			tm.ring_segments = 8
			_add(parts, Color(0.9, 0.2, 0.25), tm, xf * Transform3D(Basis(), Vector3(0, 0.08, 0)))
			_add(parts, Color(0.95, 0.95, 0.95), W.box(Vector3(0.14, 0.05, 0.3)), xf * Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.12, 0.04, 0.3)))
			_add(parts, Color(0.9, 0.2, 0.25), W.box(Vector3(0.14, 0.05, 0.28)), xf * Transform3D(Basis(Vector3.UP, -0.3), Vector3(-0.1, 0.04, 0.32)))
		"bunting":
			for sx in [-0.45, 0.45]:
				_add(parts, WOOD, W.cyl(0.025, 0.025, 0.9, 6), xf * Transform3D(Basis(), Vector3(sx, 0.45, 0)))
			var cols := [Color(0.95, 0.3, 0.3), Color(0.3, 0.6, 1.0), Color(1.0, 0.85, 0.25), Color(0.4, 0.85, 0.45)]
			for k in 4:
				var pm := PrismMesh.new()
				pm.size = Vector3(0.18, 0.22, 0.02)
				_add(parts, cols[k], pm, xf * Transform3D(Basis(Vector3.FORWARD, PI), Vector3(-0.33 + k * 0.22, 0.72 - absf(k - 1.5) * -0.02, 0)))
		"daisy":
			_add(parts, Color(0.8, 0.42, 0.25), W.cyl(0.17, 0.12, 0.22, 10), xf * Transform3D(Basis(), Vector3(0, 0.11, 0)))
			_add(parts, Color(0.3, 0.65, 0.25), W.cyl(0.025, 0.025, 0.4, 6), xf * Transform3D(Basis(), Vector3(0, 0.42, 0)))
			for k in 6:
				var a := TAU * k / 6.0
				_add(parts, Color(1.0, 1.0, 0.97), W.sphere(0.07, 8), xf * Transform3D(Basis().scaled(Vector3(1.0, 0.5, 1.0)), Vector3(cos(a) * 0.11, 0.64, sin(a) * 0.11)))
			_add(parts, Color(1.0, 0.8, 0.15), W.sphere(0.06, 8), xf * Transform3D(Basis(), Vector3(0, 0.65, 0)))
		_:
			_add(parts, Color(0.9, 0.3, 0.4), W.box(Vector3(0.4, 0.4, 0.4)), xf * Transform3D(Basis(), Vector3(0, 0.2, 0)))


static func _add(parts: Dictionary, c: Color, mesh: Mesh, xf: Transform3D) -> void:
	if not parts.has(c):
		parts[c] = W.Batch.new()
	parts[c].add(mesh, xf)


static func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
