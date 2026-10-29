extends Node3D
## The seeded garden bed's look (gardengen.gd): a soft soil patch under every planting spot, the little
## pond (water, a lily pad and reeds), stepping stones, rocks and red toadstools. One vertex-coloured
## mesh, rebuilt only when the garden changes (same on the host and every TV).

const W := preload("res://games/bee_garden/world.gd")

var mesh_i: MeshInstance3D
var water: MeshInstance3D
var shown_seed := -1


func show_garden(g: Dictionary) -> void:
	if int(g.get("seed", -1)) == shown_seed:
		return
	shown_seed = int(g.get("seed", -1))
	for c in get_children():
		c.queue_free()
	var st := W._st()
	var soil := Color(0.3, 0.2, 0.13)
	for s in g.spots:
		W.vcyl(st, Vector3(float(s[0]), 0.005, float(s[1])), 0.42, 0.44, 0.02, soil, 14)
	var r := RandomNumberGenerator.new()
	r.seed = shown_seed
	var ponds: Array = []
	for f in g.features:
		var p := Vector3(float(f[1]), 0.0, float(f[2]))
		var rad := float(f[3])
		match String(f[0]):
			"pond":
				ponds.append([p, rad])
				for k in 12:  # a ring of pebbles
					var a := k * TAU / 12.0
					W.vsphere(st, p + Vector3(cos(a) * (rad + 0.04), 0.03, sin(a) * (rad + 0.04)), Vector3(0.09, 0.05, 0.08),
						Color(0.62, 0.6, 0.56).lightened(r.randf_range(0.0, 0.2)), 6, 3)
				for k in 3:  # reeds
					var a2 := r.randf_range(0.0, TAU)
					var rp := p + Vector3(cos(a2) * rad * 0.85, 0.2, sin(a2) * rad * 0.85)
					W.vcyl(st, rp, 0.012, 0.02, 0.4, Color(0.35, 0.6, 0.25), 5)
					W.vsphere(st, rp + Vector3(0, 0.2, 0), Vector3(0.03, 0.07, 0.03), Color(0.45, 0.3, 0.18), 6, 3)
			"stone":
				W.vcyl(st, p + Vector3(0, 0.025, 0), rad * 0.9, rad, 0.05, Color(0.7, 0.68, 0.62).darkened(r.randf_range(0.0, 0.15)), 9)
			"rock":
				W.vsphere(st, p + Vector3(0, 0.08, 0), Vector3(rad, rad * 0.75, rad * 0.9), Color(0.55, 0.55, 0.58).lightened(r.randf_range(0.0, 0.15)), 8, 5)
				W.vsphere(st, p + Vector3(rad * 0.3, rad * 0.55, -rad * 0.1), Vector3(rad * 0.35, rad * 0.15, rad * 0.3), Color(0.45, 0.7, 0.35), 6, 3)
			"toadstool":
				W.vcyl(st, p + Vector3(0, 0.1, 0), 0.04, 0.05, 0.2, Color(0.96, 0.93, 0.85), 8)
				W.vsphere(st, p + Vector3(0, 0.21, 0), Vector3(0.11, 0.07, 0.11), Color(0.92, 0.2, 0.2), 10, 4)
				for k in 4:
					var a3 := k * TAU / 4.0 + 0.4
					W.vsphere(st, p + Vector3(cos(a3) * 0.06, 0.26, sin(a3) * 0.06), Vector3(0.018, 0.01, 0.018), Color.WHITE, 5, 2)
	mesh_i = MeshInstance3D.new()
	mesh_i.mesh = W.vmesh(st)
	mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_i)
	water = null
	if not ponds.is_empty():
		var wst := W._st()
		for pd in ponds:
			W.vcyl(wst, (pd[0] as Vector3) + Vector3(0, 0.012, 0), float(pd[1]), float(pd[1]), 0.02, Color(0.25, 0.55, 0.85), 20)
			W.vcyl(wst, (pd[0] as Vector3) + Vector3(float(pd[1]) * 0.35, 0.026, float(pd[1]) * 0.2), 0.12, 0.12, 0.01, Color(0.35, 0.72, 0.3), 10)
			W.vsphere(wst, (pd[0] as Vector3) + Vector3(float(pd[1]) * 0.35, 0.05, float(pd[1]) * 0.2), Vector3(0.04, 0.03, 0.04), Color(1.0, 0.75, 0.85), 6, 3)
		water = MeshInstance3D.new()
		water.mesh = W.vmesh(wst)
		var m := water.mesh.surface_get_material(0) as StandardMaterial3D
		m.roughness = 0.15
		m.metallic_specular = 0.9
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(water)
