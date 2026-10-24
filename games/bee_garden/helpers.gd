extends Node3D
## Simple mode, solo VR: when no TV bees are playing (a host with nobody connected yet), two little
## helper bees buzz between the flowers and the hive, so the garden still pollinates, fruits and fills
## the honey jars. They fly home as soon as a TV bee arrives. Host only (the TV never sees them: by
## then they've gone).

const W := preload("res://games/bee_garden/world.gd")
const COUNT := 2
const SPEED := 1.6

var main
var bees: Array = []  # {node, pos, goal_i, carry, from_i, wait}
var t := 0.0
var delivered := 0  # the bot reads it


func _ready() -> void:
	name = "Helpers"
	for i in COUNT:
		var n := Node3D.new()
		add_child(n)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		W.vsphere(st, Vector3.ZERO, Vector3(0.1, 0.09, 0.13), Color(1.0, 0.8, 0.15), 8, 4)
		W.vsphere(st, Vector3(0, 0, 0.02), Vector3(0.102, 0.092, 0.025), Color(0.12, 0.1, 0.08), 8, 4)
		W.vsphere(st, Vector3(0, 0.01, -0.12), Vector3(0.065, 0.065, 0.065), Color(0.12, 0.1, 0.08), 8, 4)
		var body := MeshInstance3D.new()
		body.mesh = W.vmesh(st)
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(body)
		var wings: Array[MeshInstance3D] = []
		for s in [-1.0, 1.0]:
			var wm := W.mesh_node(n, W.sphere(0.09, 6), W.cmat(Color(0.92, 0.97, 1.0)), Vector3(s * 0.1, 0.09, 0.0), Vector3(1.2, 0.12, 0.7))
			wm.set_meta("side", s)
			wings.append(wm)
		var start := W.HIVE_ENTRY + Vector3(0.4 + i * 0.3, 0.3, 0.0)
		n.position = start
		n.visible = false
		bees.append({"node": n, "wings": wings, "pos": start, "goal_i": -1, "carry": 0, "from_i": -1, "wait": i * 1.5})


func _wanted() -> bool:
	return main.net != null and main.net.mode == "host" and not main.net.connected


## Host: fly, collect pollen, pollinate, make honey (called by main every frame in simple mode).
func host_update(delta: float) -> void:
	t += delta
	var on := _wanted()
	for hb in bees:
		var n: Node3D = hb["node"]
		var pos: Vector3 = hb["pos"]
		if not on:
			# Fly home and vanish.
			if n.visible:
				pos = pos.move_toward(W.HIVE_ENTRY, SPEED * 1.5 * delta)
				if pos.distance_to(W.HIVE_ENTRY) < 0.1:
					n.visible = false
			hb["pos"] = pos
			n.position = pos
			continue
		n.visible = true
		hb["wait"] = float(hb["wait"]) - delta
		if float(hb["wait"]) > 0.0:
			_animate(hb, delta)
			continue
		var goal := W.HIVE_ENTRY
		var gi: int = hb["goal_i"]
		if int(hb["carry"]) < 2:
			if gi < 0 or not main.spots[gi].bloom or gi == int(hb["from_i"]):
				gi = _pick_flower(int(hb["from_i"]))
				hb["goal_i"] = gi
			if gi >= 0:
				goal = main.head_pos(gi) + Vector3(0.0, 0.15, 0.0)
		var to := goal - pos
		var step := SPEED * delta
		if to.length() > step:
			pos += to.normalized() * step
			pos.y = maxf(pos.y, W.floor_y(pos.x, pos.z) + 0.1)
		else:
			pos = goal
			if int(hb["carry"]) >= 2 or gi < 0:
				if int(hb["carry"]) > 0:
					main.helper_deliver(int(hb["carry"]))
					delivered += 1
				hb["carry"] = 0
				hb["from_i"] = -1
				hb["wait"] = 1.5
			else:
				main.helper_visit(gi, int(hb["carry"]) > 0 and gi != int(hb["from_i"]))
				hb["carry"] = int(hb["carry"]) + 1
				hb["from_i"] = gi
				hb["goal_i"] = -1
				hb["wait"] = 1.2
		hb["pos"] = pos
		var flat := Vector2(to.x, to.z)
		if flat.length() > 0.05:
			n.rotation.y = atan2(-to.x, -to.z)
		_animate(hb, delta)


func _animate(hb: Dictionary, _delta: float) -> void:
	var n: Node3D = hb["node"]
	n.position = (hb["pos"] as Vector3) + Vector3.UP * sin(t * 5.0 + float(hb["wait"])) * 0.03
	for w in hb["wings"]:
		var wm: MeshInstance3D = w
		wm.rotation.z = float(wm.get_meta("side")) * (0.25 + sin(t * 60.0) * 0.55)


func _pick_flower(not_i: int) -> int:
	var opts: Array[int] = []
	for i in main.spots.size():
		if main.spots[i].bloom and i != not_i:
			opts.append(i)
			if float(main.spots[i].fruit) < 0.0:
				opts.append(i)  # unpollinated flowers first
	if opts.is_empty():
		return -1
	return opts[randi() % opts.size()]
