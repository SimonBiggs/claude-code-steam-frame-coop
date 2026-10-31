extends Node3D
## MECH TITANS pods: a choice you make with your feet. Two or three glowing PODS land in front of the Titan,
## each a tall beam of coloured light with a picture spinning on top and a name of one or two words:
##   "frame"   (the session's start, once the family has two or more frames: frames.gd)
##   "mode"    (before the first made round, once BRAVE is open: GENTLE / BRAVE / MEGA, roundgen.gd MODES)
##   "upgrade" (after every made round while there are upgrades left: upgrades.gd)
## Walk the Titan into one (or punch it), or fly / drive a support vehicle through it: that's the choice, for
## everyone. Nobody chooses? After WAIT seconds the pod that's glowing brightest (the default: the frame you had,
## GENTLE, the middle upgrade) is taken by itself, so little ones are never stuck.
## Every machine builds the pods from the host's net store "pick": {n, kind, ids, at: [Vector3], def, wait}.

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Data := preload("res://games/mech_titans/data.gd")
const Upgrades := preload("res://games/mech_titans/upgrades.gd")
const Frames := preload("res://games/mech_titans/frames.gd")
const RoundGen := preload("res://games/mech_titans/roundgen.gd")

const WAIT := 20.0
const TOUCH_TITAN := 7.0  ## m from the pod's middle to the Titan's middle
const TOUCH_FIST := 4.5
const TOUCH_VEH := 6.5
const POD_H := 7.0  ## the light column's height (the picture spins just above: about the pilot's eye height)
const SPREAD := 14.0  ## m between pods
const AHEAD := 20.0  ## m in front of the Titan
const MODE_COLORS := {"gentle": Color(0.45, 1.0, 0.55), "brave": Color(1.0, 0.65, 0.25), "mega": Color(1.0, 0.3, 0.35)}

var main: Node
var pods: Array[Node3D] = []
var info := {}  ## the "pick" state these pods were built from
var t := 0.0  ## host: seconds since the pods landed
var taken := false


## Where the pods land: in a row in front of the Titan, out of the buildings and inside the city.
static func places(mech_pos: Vector3, fwd: Vector3, n: int, city: Node) -> Array:
	var f := Vector3(fwd.x, 0.0, fwd.z).normalized()
	if f.length() < 0.5:
		f = Vector3(0, 0, -1)
	var right := Vector3(-f.z, 0.0, f.x)
	var out: Array = []
	for i in n:
		var p := mech_pos + f * AHEAD + right * (float(i) - (n - 1) * 0.5) * SPREAD
		p.x = clampf(p.x, -Data.MAP + 10.0, Data.MAP - 10.0)
		p.z = clampf(p.z, -Data.MAP + 10.0, Data.MAP - 10.0)
		if city != null:
			p = city.push_out(p, 3.0)
		p.y = 0.0
		out.append(p)
	return out


static func pod_name(kind: String, id: String) -> String:
	match kind:
		"upgrade":
			return String(Upgrades.info(id).get("name", id.to_upper()))
		"frame":
			return String(Frames.info(id)["name"])
		"mode":
			return String(RoundGen.MODES.get(id, RoundGen.MODES["gentle"])["name"])
	return id.to_upper()


static func pod_color(kind: String, id: String) -> Color:
	match kind:
		"upgrade":
			return Upgrades.info(id).get("color", Color.WHITE)
		"frame":
			return Data.PAINTS[String(Frames.info(id)["paint"])]["main"]
		"mode":
			return MODE_COLORS.get(id, Color.WHITE)
	return Color.WHITE


## Every machine: (re)build the pods for the host's "pick" state ({} = none).
func sync(p: Variant) -> void:
	var d: Dictionary = p if p is Dictionary else {}
	if int(d.get("n", -1)) == int(info.get("n", -2)) and not d.is_empty():
		return
	clear()
	info = d
	t = 0.0
	taken = false
	if d.is_empty():
		return
	var ids: Array = d.get("ids", [])
	var at: Array = d.get("at", [])
	for i in ids.size():
		if i >= at.size():
			break
		var pod := _make_pod(String(d.get("kind", "upgrade")), String(ids[i]), i == int(d.get("def", 0)))
		add_child(pod)
		pod.global_position = at[i]
		pods.append(pod)


func clear() -> void:
	for p in pods:
		if is_instance_valid(p):
			p.queue_free()
	pods.clear()
	info = {}


## Host: who touched a pod this frame? Returns [pod index, slot] or [] (slot 0 = the Titan).
func touched(mech: Node3D, vehicles: Dictionary) -> Array:
	if taken or pods.is_empty():
		return []
	for i in pods.size():
		var pp := pods[i].global_position
		var flat := Vector2(mech.global_position.x - pp.x, mech.global_position.z - pp.z).length()
		if flat < TOUCH_TITAN:
			return [i, 0]
		for h in 2:
			var f: Vector3 = mech.fist_world(h)
			if Vector2(f.x - pp.x, f.z - pp.z).length() < TOUCH_FIST:
				return [i, 0]
		for id in vehicles:
			var v: Node3D = vehicles[id]
			if int(id) >= 10 or v == null or bool(v.get("ai")):
				continue
			if Vector2(v.global_position.x - pp.x, v.global_position.z - pp.z).length() < TOUCH_VEH:
				return [i, int(id)]
	return []


func _process(delta: float) -> void:
	t += delta
	for i in pods.size():
		var pod := pods[i]
		var icon := pod.get_node_or_null("Icon") as Node3D
		if icon != null:
			icon.rotation.y += delta * 1.4
			icon.position.y = POD_H + 1.6 + sin(t * 2.0 + i) * 0.35
		var glow := pod.get_node_or_null("Column") as Node3D
		if glow != null:
			var s := 1.0 + 0.06 * sin(t * 4.0 + i * 1.3)
			glow.scale = Vector3(s, 1.0, s)


func _make_pod(kind: String, id: String, is_default: bool) -> Node3D:
	var pod := Node3D.new()
	pod.name = "Pod_%s" % id
	var col := pod_color(kind, id)
	var base := MeshKit.instance(_base_mesh(), false)
	pod.add_child(base)
	var column := MeshInstance3D.new()
	column.name = "Column"
	var cm := CylinderMesh.new()
	cm.top_radius = 2.2
	cm.bottom_radius = 2.6
	cm.height = POD_H
	cm.radial_segments = 20
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	column.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(col.r, col.g, col.b, 0.5 if is_default else 0.32)
	column.material_override = m
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	column.position.y = POD_H * 0.5
	pod.add_child(column)
	var icon := MeshKit.instance(icon_mesh(kind, id), false)
	icon.name = "Icon"
	icon.scale = Vector3.ONE * 2.6
	icon.position.y = POD_H + 1.6
	pod.add_child(icon)
	var label := Label3D.new()
	label.name = "Name"
	label.text = pod_name(kind, id).replace(" ", "\n")  # two short lines: the pods stand side by side
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.022
	label.font_size = 64
	label.outline_size = 14
	label.modulate = col.lightened(0.35)
	label.outline_modulate = Color(0.05, 0.05, 0.1)
	label.position.y = POD_H + 4.4
	label.no_depth_test = false
	pod.add_child(label)
	return pod


static func _base_mesh() -> ArrayMesh:
	return ResCache.get_or_make("mt_pod_base_v1", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(3.0, 3.2, 0.5, MeshKit.at(Vector3(0, 0.25, 0)), Color(0.32, 0.35, 0.42), 20)
		b.torus(2.9, 0.18, MeshKit.at(Vector3(0, 0.52, 0)), Color(1.0, 0.9, 0.5), 24, 6, true)
		return b.build()) as ArrayMesh


## The picture that spins on top of a pod (about 1 unit across; the pod scales it up).
static func icon_mesh(kind: String, id: String) -> ArrayMesh:
	return ResCache.get_or_make("mt_pod_icon_%s_%s_v1" % [kind, id], func() -> Resource: return _build_icon(kind, id)) as ArrayMesh


static func _build_icon(kind: String, id: String) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var col := pod_color(kind, id)
	var white := Color(0.95, 0.95, 1.0)
	var gold := Color(1.0, 0.82, 0.25)
	if kind == "frame":
		var paint: Dictionary = Data.PAINTS[String(Frames.info(id)["paint"])]
		var mc: Color = paint["main"]
		var tc: Color = paint["trim"]
		var gc: Color = paint["glow"]
		b.rounded_box(Vector3(0.5, 0.42, 0.3), 0.06, MeshKit.at(Vector3(0, 0.05, 0)), mc)
		b.rounded_box(Vector3(0.3, 0.2, 0.26), 0.05, MeshKit.at(Vector3(0, 0.38, 0)), tc)
		b.box(Vector3(0.22, 0.06, 0.02), MeshKit.at(Vector3(0, 0.39, 0.13)), gc, true)
		b.sphere(0.06, MeshKit.at(Vector3(0, 0.08, 0.16)), gc, 8, true)
		for s in [-1.0, 1.0]:
			b.capsule(0.07, 0.36, MeshKit.at(Vector3(s * 0.33, 0.0, 0), Vector3.ONE, Vector3(0, 0, s * 0.25)), mc.darkened(0.15))
			b.sphere(0.1, MeshKit.at(Vector3(s * 0.38, -0.2, 0)), tc, 8)
			b.capsule(0.08, 0.34, MeshKit.at(Vector3(s * 0.13, -0.36, 0)), mc.darkened(0.25))
		return b.build()
	if kind == "mode":
		match id:
			"gentle":
				b.sphere(0.2, MeshKit.at(Vector3(-0.14, 0.12, 0)), col, 12, true)
				b.sphere(0.2, MeshKit.at(Vector3(0.14, 0.12, 0)), col, 12, true)
				b.cone(0.3, 0.42, MeshKit.at(Vector3(0, -0.2, 0), Vector3.ONE, Vector3(PI, 0, 0)), col, 12, true)
			"brave":
				b.star(5, 0.42, 0.18, 0.14, Transform3D.IDENTITY, col, true)
			_:
				b.cylinder(0.32, 0.32, 0.2, MeshKit.at(Vector3(0, -0.1, 0)), gold, 14)
				for k in 5:
					var a := TAU * k / 5.0
					b.cone(0.09, 0.28, MeshKit.at(Vector3(cos(a) * 0.28, 0.12, sin(a) * 0.28)), gold, 6)
					b.sphere(0.05, MeshKit.at(Vector3(cos(a) * 0.28, 0.28, sin(a) * 0.28)), col, 6, true)
		return b.build()
	match id:
		"power":  # a big fist
			b.rounded_box(Vector3(0.5, 0.42, 0.4), 0.1, Transform3D.IDENTITY, col)
			for k in 4:
				b.sphere(0.09, MeshKit.at(Vector3(-0.18 + k * 0.12, 0.18, 0.18)), col.lightened(0.3), 8)
			b.box(Vector3(0.3, 0.3, 0.3), MeshKit.at(Vector3(0, -0.3, -0.05)), white)
		"beam":  # a lightning bolt
			b.polygon(PackedVector2Array([Vector2(0.05, 0.5), Vector2(-0.25, -0.02), Vector2(-0.02, -0.02), Vector2(-0.1, -0.5),
				Vector2(0.25, 0.08), Vector2(0.02, 0.08)]), 0.12, Transform3D.IDENTITY, col, true)
		"legs":  # a running boot with a wing
			b.rounded_box(Vector3(0.2, 0.4, 0.22), 0.05, MeshKit.at(Vector3(0, 0.05, 0)), col)
			b.rounded_box(Vector3(0.22, 0.14, 0.42), 0.05, MeshKit.at(Vector3(0, -0.18, 0.1)), col.darkened(0.2))
			b.wedge(Vector3(0.04, 0.22, 0.3), MeshKit.at(Vector3(-0.14, 0.1, -0.05)), white)
		"rocket":  # a fist with a rocket flame
			b.rounded_box(Vector3(0.36, 0.32, 0.32), 0.08, MeshKit.at(Vector3(0, 0.15, 0)), col)
			b.cylinder(0.12, 0.16, 0.2, MeshKit.at(Vector3(0, -0.1, 0)), white, 10)
			b.cone(0.14, 0.3, MeshKit.at(Vector3(0, -0.34, 0), Vector3.ONE, Vector3(PI, 0, 0)), Color(1.0, 0.75, 0.25), 8, true)
		"repair":  # a plus
			b.box(Vector3(0.6, 0.18, 0.18), Transform3D.IDENTITY, col, true)
			b.box(Vector3(0.18, 0.6, 0.18), Transform3D.IDENTITY, col, true)
		"stomp":  # a foot over rings
			b.rounded_box(Vector3(0.3, 0.16, 0.42), 0.06, MeshKit.at(Vector3(0, 0.12, 0)), white)
			b.torus(0.3, 0.035, MeshKit.at(Vector3(0, -0.05, 0)), col, 16, 4, true)
			b.torus(0.45, 0.03, MeshKit.at(Vector3(0, -0.12, 0)), col, 18, 4, true)
		"magnet":  # a horseshoe magnet
			b.torus(0.26, 0.09, MeshKit.at(Vector3(0, 0.08, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), col, 16, 6)
			b.box(Vector3(0.18, 0.16, 0.18), MeshKit.at(Vector3(-0.26, -0.2, 0)), white, true)
			b.box(Vector3(0.18, 0.16, 0.18), MeshKit.at(Vector3(0.26, -0.2, 0)), white, true)
		"dome":  # a shield bubble
			b.dome(0.4, MeshKit.at(Vector3(0, -0.2, 0)), col, 14, true)
			b.torus(0.4, 0.04, MeshKit.at(Vector3(0, -0.2, 0)), white, 18, 4)
		"jets":  # two jets with flames
			for s in [-1.0, 1.0]:
				b.cylinder(0.11, 0.11, 0.4, MeshKit.at(Vector3(s * 0.15, 0.1, 0)), white, 10)
				b.cone(0.11, 0.18, MeshKit.at(Vector3(s * 0.15, 0.39, 0)), col, 10)
				b.cone(0.1, 0.26, MeshKit.at(Vector3(s * 0.15, -0.24, 0), Vector3.ONE, Vector3(PI, 0, 0)), Color(1.0, 0.6, 0.2), 8, true)
		"buddy":  # a little drone
			b.sphere(0.2, Transform3D.IDENTITY, white, 12)
			b.sphere(0.08, MeshKit.at(Vector3(0, 0.02, 0.17)), col, 8, true)
			b.torus(0.36, 0.035, MeshKit.at(Vector3(0, 0.16, 0)), col, 18, 4, true)
		_:
			b.sphere(0.3, Transform3D.IDENTITY, col, 12, true)
	return b.build()
