extends Node3D
## Soft Dodgeball's world: the park, the court, the giant's stage and ball tray, two big wobbly
## flowers, and the friendly giant's body (belly target, head and mittens for the TV / CPU giant).
## Static scenery is baked into a few vertex-coloured meshes (cheap on the headset).

const MeshKit := preload("res://core/mesh_kit.gd")
const SkyKit := preload("res://core/sky_kit.gd")

const STAGE_HALF_W := 4.0
const STAGE_H := 0.9
const STAGE_FRONT := -4.6
const STAGE_BACK := -9.2
const TRAY_Z := -5.25
const TRAY_Y := STAGE_H + 0.95

var giant_body: Node3D
var target: Node3D
var giant_head: Node3D
var giant_hands: Array[Node3D] = []
var props: Array = []  # [{node, point, radius, wob, cool}]
var belly_wob := 0.0
var _t := 0.0
var _main: Node


func build(main: Node, vr: bool) -> void:
	_main = main
	main.set("sky", SkyKit.apply(main, "day", vr))
	add_child(MeshKit.instance(_ground_mesh(), false))
	add_child(MeshKit.instance(_stage_mesh()))
	add_child(MeshKit.scatter_random(MeshKit.prop("tree"), 18, Vector3(0.0, 0.0, -1.0), 22.0, 11.5, 0.9, 1.4, PackedColorArray(), 3))
	add_child(MeshKit.scatter_random(MeshKit.prop("bush"), 14, Vector3(0.0, 0.0, -1.0), 11.0, 9.5, 0.8, 1.2, PackedColorArray(), 4))
	# The ball tray in front of the giant (wobbles when touched).
	var tray := Node3D.new()
	tray.position = Vector3(0.0, STAGE_H, TRAY_Z)
	var tb := MeshKit.Builder.new()
	tb.rounded_box(Vector3(2.7, 0.1, 0.5), 0.04, MeshKit.at(Vector3(0.0, TRAY_Y - STAGE_H - 0.26, 0.0)), Color(0.95, 0.55, 0.25))
	for x in [-1.1, 1.1]:
		tb.cylinder(0.05, 0.06, TRAY_Y - STAGE_H - 0.26, MeshKit.at(Vector3(float(x), (TRAY_Y - STAGE_H - 0.26) * 0.5, 0.0)), Color(0.75, 0.4, 0.2), 8)
	for k in 6:
		tb.torus(0.13, 0.025, MeshKit.at(Vector3(-1.0 + 0.4 * float(k), TRAY_Y - STAGE_H - 0.2, 0.0)), Color(1.0, 0.85, 0.4), 12, 6)
	tray.add_child(MeshKit.instance(tb.build()))
	add_child(tray)
	props.append({"node": tray, "point": Vector3(0.0, TRAY_Y - 0.25, TRAY_Z), "radius": 0.3, "wide": 1.35, "wob": 0.0, "cool": 0.0})
	# Two giant flowers on the stage, in reach of the giant's hands.
	for side in [-1.0, 1.0]:
		var f := Node3D.new()
		f.position = Vector3(2.0 * float(side), STAGE_H, -5.6)
		var fb := MeshKit.Builder.new()
		fb.cylinder(0.04, 0.05, 1.3, MeshKit.at(Vector3(0.0, 0.65, 0.0)), Color(0.3, 0.7, 0.3), 8)
		var petal := Color(1.0, 0.45, 0.7) if side < 0.0 else Color(0.6, 0.5, 1.0)
		for k in 6:
			var a := TAU * float(k) / 6.0
			fb.ellipsoid(Vector3(0.16, 0.05, 0.1), MeshKit.at(Vector3(cos(a) * 0.17, 1.35, sin(a) * 0.17), Vector3.ONE, Vector3(0.0, -a, 0.0)), petal, 10)
		fb.sphere(0.1, MeshKit.at(Vector3(0.0, 1.37, 0.0)), Color(1.0, 0.85, 0.2), 10)
		f.add_child(MeshKit.instance(fb.build()))
		add_child(f)
		props.append({"node": f, "point": f.position + Vector3(0.0, 1.3, 0.0), "radius": 0.3, "wide": 0.0, "wob": 0.0, "cool": 0.0})
	_build_giant()


func _ground_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.cylinder(30.0, 30.0, 0.2, MeshKit.at(Vector3(0.0, -0.1, 0.0)), Color(0.45, 0.75, 0.38), 32)
	# The court: a sandy rectangle with white lines and a little fence.
	b.box(Vector3(14.0, 0.02, 11.6), MeshKit.at(Vector3(0.0, 0.01, 1.2)), Color(0.98, 0.85, 0.6))
	b.box(Vector3(14.0, 0.03, 0.12), MeshKit.at(Vector3(0.0, 0.02, 7.0)), Color.WHITE)
	b.box(Vector3(14.0, 0.03, 0.12), MeshKit.at(Vector3(0.0, 0.02, -4.55)), Color.WHITE)
	b.box(Vector3(0.12, 0.03, 11.6), MeshKit.at(Vector3(-7.0, 0.02, 1.2)), Color.WHITE)
	b.box(Vector3(0.12, 0.03, 11.6), MeshKit.at(Vector3(7.0, 0.02, 1.2)), Color.WHITE)
	b.disc(1.2, MeshKit.at(Vector3(0.0, 0.025, 1.2)), Color(1.0, 0.7, 0.45), 24)
	for i in 15:
		var x := -7.0 + float(i)
		b.cylinder(0.06, 0.06, 0.7, MeshKit.at(Vector3(x, 0.35, 7.6)), Color(1.0, 0.95, 0.85), 6)
	b.box(Vector3(14.2, 0.08, 0.08), MeshKit.at(Vector3(0.0, 0.6, 7.6)), Color(1.0, 0.5, 0.4))
	for side in [-1.0, 1.0]:
		for i in 13:
			var z := -4.6 + float(i)
			b.cylinder(0.06, 0.06, 0.7, MeshKit.at(Vector3(7.6 * float(side), 0.35, z)), Color(1.0, 0.95, 0.85), 6)
		b.box(Vector3(0.08, 0.08, 12.4), MeshKit.at(Vector3(7.6 * float(side), 0.6, 1.4)), Color(1.0, 0.5, 0.4))
	return b.build()


func _stage_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var depth := STAGE_FRONT - STAGE_BACK
	var cz := (STAGE_FRONT + STAGE_BACK) * 0.5
	b.box(Vector3(STAGE_HALF_W * 2.0, STAGE_H, depth), MeshKit.at(Vector3(0.0, STAGE_H * 0.5, cz)), Color(0.75, 0.5, 0.3))
	b.box(Vector3(STAGE_HALF_W * 2.0 + 0.1, 0.06, depth + 0.1), MeshKit.at(Vector3(0.0, STAGE_H - 0.02, cz)), Color(0.9, 0.7, 0.45))
	# Bright stripes on the front so it reads as a stage from the court.
	for i in 8:
		var col := Color(1.0, 0.4, 0.4) if i % 2 == 0 else Color(1.0, 0.85, 0.35)
		b.box(Vector3(1.0, STAGE_H - 0.12, 0.04), MeshKit.at(Vector3(-3.5 + float(i), STAGE_H * 0.5 - 0.03, STAGE_FRONT + 0.01)), col)
	# A rainbow arch behind the giant.
	var arch := [Color(1.0, 0.4, 0.4), Color(1.0, 0.75, 0.3), Color(0.45, 0.85, 0.45), Color(0.4, 0.65, 1.0)]
	for k in arch.size():
		b.torus(3.6 - 0.3 * float(k), 0.15, MeshKit.at(Vector3(0.0, STAGE_H, STAGE_BACK + 0.3), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), arch[k], 28, 6)
	return b.build()


## A soft round shadow for a ball.
func make_blob(r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 0.005
	c.radial_segments = 12
	c.rings = 1
	mi.mesh = c
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.0, 0.0, 0.0, 0.3)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _build_giant() -> void:
	giant_body = Node3D.new()
	giant_body.name = "GiantBody"
	add_child(giant_body)
	var b := MeshKit.Builder.new()
	b.ellipsoid(Vector3(0.46, 0.44, 0.34), MeshKit.at(Vector3.ZERO), Color(1.0, 0.6, 0.25), 18)  # orange jumper
	b.ellipsoid(Vector3(0.47, 0.2, 0.35), MeshKit.at(Vector3(0.0, -0.25, 0.0)), Color(0.3, 0.45, 0.9), 18)  # blue shorts
	for side in [-1.0, 1.0]:
		b.capsule_between(Vector3(0.2 * float(side), -0.35, 0.0), Vector3(0.22 * float(side), -0.9, 0.0), 0.13, Color(0.3, 0.45, 0.9))
		b.ellipsoid(Vector3(0.15, 0.1, 0.24), MeshKit.at(Vector3(0.22 * float(side), -0.95, 0.07)), Color(0.95, 0.95, 1.0), 10)
	giant_body.add_child(MeshKit.instance(b.build()))
	target = Node3D.new()
	target.position = Vector3(0.0, 0.04, 0.3)
	var tb := MeshKit.Builder.new()
	var rot := Vector3(PI * 0.5, 0.0, 0.0)
	tb.disc(0.3, MeshKit.at(Vector3(0.0, 0.0, 0.0), Vector3.ONE, rot), Color(1.0, 0.2, 0.25), 24)
	tb.disc(0.21, MeshKit.at(Vector3(0.0, 0.0, 0.01), Vector3.ONE, rot), Color.WHITE, 24)
	tb.disc(0.11, MeshKit.at(Vector3(0.0, 0.0, 0.02), Vector3.ONE, rot), Color(1.0, 0.2, 0.25), 20, true)
	tb.torus(0.31, 0.025, MeshKit.at(Vector3(0.0, 0.0, 0.0), Vector3.ONE, rot), Color(1.0, 0.9, 0.3), 24, 6, true)
	target.add_child(MeshKit.instance(tb.build()))
	giant_body.add_child(target)
	giant_head = Node3D.new()
	var hb := MeshKit.Builder.new()
	hb.sphere(0.3, MeshKit.at(Vector3.ZERO), Color(1.0, 0.82, 0.68), 16)
	for side in [-1.0, 1.0]:
		hb.sphere(0.055, MeshKit.at(Vector3(0.11 * float(side), 0.06, 0.26)), Color(0.1, 0.1, 0.15), 8)
		hb.sphere(0.06, MeshKit.at(Vector3(0.19 * float(side), -0.06, 0.22)), Color(1.0, 0.6, 0.6), 8)
		hb.sphere(0.08, MeshKit.at(Vector3(0.3 * float(side), 0.0, 0.0)), Color(1.0, 0.78, 0.62), 8)
	hb.sphere(0.06, MeshKit.at(Vector3(0.0, -0.02, 0.3)), Color(1.0, 0.65, 0.5), 8)
	hb.ellipsoid(Vector3(0.1, 0.03, 0.03), MeshKit.at(Vector3(0.0, -0.13, 0.26)), Color(0.6, 0.15, 0.2), 8)
	hb.ellipsoid(Vector3(0.31, 0.16, 0.31), MeshKit.at(Vector3(0.0, 0.17, -0.03)), Color(0.55, 0.3, 0.15), 14)  # hair
	giant_head.add_child(MeshKit.instance(hb.build()))
	add_child(giant_head)
	for i in 2:
		var h := Node3D.new()
		var mb := MeshKit.Builder.new()
		mb.ellipsoid(Vector3(0.12, 0.1, 0.14), MeshKit.at(Vector3.ZERO), Color(1.0, 0.86, 0.6), 12)
		mb.ellipsoid(Vector3(0.04, 0.07, 0.04), MeshKit.at(Vector3(0.11 * (1.0 if i == 1 else -1.0), 0.04, 0.03)), Color(1.0, 0.86, 0.6), 8)
		h.add_child(MeshKit.instance(mb.build()))
		add_child(h)
		giant_hands.append(h)


## The VR player has a real head and real gloves: hide the drawn ones on their own machine.
func show_giant_head(on: bool) -> void:
	giant_head.visible = on
	for h in giant_hands:
		h.visible = on


func update_giant(head: Vector3, yaw: float, hands: Array[Vector3], delta: float) -> void:
	_t += delta
	giant_body.position = head + Vector3(0.0, -0.72, 0.0)
	giant_body.rotation.y = yaw + PI
	giant_head.position = head
	giant_head.rotation.y = yaw + PI
	for i in 2:
		giant_hands[i].position = hands[i]
		giant_hands[i].rotation.y = yaw + PI
	belly_wob = move_toward(belly_wob, 0.0, delta * 1.5)
	var s := 1.0 + 0.04 * sin(_t * 4.0) + 0.25 * belly_wob * sin(_t * 22.0)
	target.scale = Vector3(s, s, 1.0)
	var bs := 1.0 + 0.08 * belly_wob * sin(_t * 18.0)
	giant_body.scale = Vector3(bs, 2.0 - bs, bs)
	for p: Dictionary in props:
		p["wob"] = move_toward(float(p["wob"]), 0.0, delta * 1.2)
		p["cool"] = float(p["cool"]) - delta
		var n: Node3D = p["node"]
		n.rotation.z = 0.25 * float(p["wob"]) * sin(_t * 12.0)
		n.rotation.x = 0.15 * float(p["wob"]) * sin(_t * 9.0)


func wobble_belly() -> void:
	belly_wob = 1.0


## Host with a VR giant: hands touching the tray or a flower make it wobble and boing.
func touch_props(main: Node, hands: Array, speeds: Array) -> void:
	for p: Dictionary in props:
		if float(p["cool"]) > 0.0:
			continue
		var c: Vector3 = p["point"]
		var wide: float = p["wide"]
		for i in hands.size():
			var h: Vector3 = hands[i]
			var d := h - c
			d.x = maxf(0.0, absf(d.x) - wide)
			if d.length() < float(p["radius"]) and float(speeds[i]) > 0.3:
				p["wob"] = clampf(float(speeds[i]) * 0.5, 0.4, 1.0)
				p["cool"] = 0.4
				main.call("sound_at", "boing", c, -6.0, randf_range(0.7, 1.0))
				var rig: Node = main.get("vr_rig")
				if rig != null:
					rig.call("pulse", i, 0.3, 0.05)
				break
