extends Node3D
## DUNGEON DELVE deep floors: draws a generated floor (games/dungeon_delve/floorgen.gd) on every
## machine and keeps bodies inside it.
##  - ONE merged mesh for floors, walls, pillars, doorframes, decorations and torch flames (plus one
##    for the pits under crumbly tiles), so a whole floor costs a handful of draw calls.
##  - Doors: an iron portcullis per doorway that drops into the floor when the door can be walked
##    through (a gold lock plate on locked doors, glowing runes on puzzle doors, a big crowned door
##    for the boss); secret doors are a cracked bit of wall that crumbles when broken.
##  - Chests, pots, switches (floor plates, wall levers), traps (spikes, boulders, crumbly tiles) and
##    the stairs down, all driven by the host's replicated state (deep.gd).
##  - Walls running east-west are kept low so the TV camera (looking north) sees over them.

const FloorGen := preload("res://games/dungeon_delve/floorgen.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Dungeon := preload("res://games/dungeon_delve/dungeon.gd")

const WALL_NS := 1.0  ## height of walls running along x (north / south sides): low, the camera looks over them
const WALL_EW := 1.7  ## height of walls running along z
const SWITCH_COLORS: Array[Color] = [Color(0.4, 0.8, 1.0), Color(1.0, 0.5, 0.9)]

var f: Dictionary = {}
var rects: Array = []
var obst: Array = []
var pass_bits := 0
var open_bits := 0
var zone := 0
var doors: Array[Dictionary] = []  ## door id -> {"bars": Node3D, "plug": Node3D, "want": float}
var chests: Array[Dictionary] = []  ## chest id -> {"node", "lid", "room", "p": Vector3}
var pots: Array[Dictionary] = []  ## pot id -> {"node", "room", "p": Vector3}
var switches: Array[Dictionary] = []  ## switch id -> {"node", "glow", "kind", "p": Vector3, "on": float}
var traps: Array[Dictionary] = []  ## trap id -> {"kind", ...}
var stairs_ring: MeshInstance3D
var stairs_at := Vector3.INF
var key_spot := Vector3.INF
var light: OmniLight3D
var _t := 0.0
var _chest_bits := 0
var _pot_bits := 0


## Back to nothing (the gentle dungeon is on).
func clear() -> void:
	for c in get_children():
		c.queue_free()
	f = {}
	doors.clear()
	chests.clear()
	pots.clear()
	switches.clear()
	traps.clear()
	rects = []
	obst = []
	stairs_ring = null
	stairs_at = Vector3.INF
	light = null


## Build floor fl (a floorgen dictionary). Frees the old one.
func build(fl: Dictionary) -> void:
	if (fl.get("rooms", []) as Array).is_empty():
		clear()  # (stop() once built an empty floor here and crashed on room 0: TV, 25 Oct)
		return
	for c in get_children():
		c.queue_free()
	f = fl
	zone = int(f["zone"]) % FloorGen.ZONES.size()
	doors.clear()
	chests.clear()
	pots.clear()
	switches.clear()
	traps.clear()
	stairs_ring = null
	stairs_at = Vector3.INF
	_chest_bits = 0
	_pot_bits = 0
	var zd: Dictionary = FloorGen.ZONES[zone]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(f["seed"]), int(f["zone"]), int(f["floor"]), "look"])
	var b := MeshKit.Builder.new()
	var pit := MeshKit.Builder.new()
	var rooms: Array = f["rooms"]
	var crumbly := {}  # Vector3 tile centre -> true (drawn as separate tiles over a pit)
	for t in f["traps"]:
		var td: Dictionary = t
		if String(td["kind"]) == "collapse":
			for tp in td["tiles"]:
				crumbly[FloorGen.to_world(f, int(td["room"]), tp).snappedf(0.01)] = true
	for i in rooms.size():
		_build_room(b, pit, i, zd, rng, crumbly)
	var inst := MeshInstance3D.new()
	inst.mesh = b.build()
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	if not pit.is_empty():
		add_child(MeshKit.instance(pit.build(), false))
	_build_doors(zd)
	_build_props()
	_build_switches()
	_build_traps(zd)
	light = OmniLight3D.new()
	light.omni_range = 13.0
	light.light_energy = 1.7
	light.light_color = Color(1.0, 0.85, 0.65) if zone != 2 else Color(1.0, 0.7, 0.5)
	light.shadow_enabled = false
	light.position = FloorGen.room_center(f, 0) + Vector3(0.0, 4.2, 0.0)
	add_child(light)
	set_pass(FloorGen.start_open_bits(f), FloorGen.start_open_bits(f))


func _build_room(b: MeshKit.Builder, pit: MeshKit.Builder, i: int, zd: Dictionary, rng: RandomNumberGenerator, crumbly: Dictionary) -> void:
	var r: Dictionary = (f["rooms"] as Array)[i]
	var c := FloorGen.room_center(f, i)
	var role: String = r["role"]
	var fc: Array = zd["floor"]
	var wall: Color = zd["wall"]
	var glow: Color = zd["glow"]
	var h := FloorGen.HALF
	var tile := FloorGen.TILE
	# Checker floor.
	for ix in 7:
		for iz in 7:
			var tp := c + Vector3((ix - 3) * tile, 0.0, (iz - 3) * tile)
			var col: Color = fc[(ix + iz) % 2]
			if role == "boss":
				col = col.lerp(Color(0.5, 0.25, 0.4), 0.3)
			elif role in ["secret", "treasure"]:
				col = col.lerp(Color(0.75, 0.6, 0.3), 0.35)
			elif role == "shop":
				col = col.lerp(Color(0.6, 0.45, 0.3), 0.5)
			if crumbly.has(tp.snappedf(0.01)):
				pit.box(Vector3(tile, 0.1, tile), MeshKit.at(tp + Vector3(0.0, -1.2, 0.0)), Color(0.05, 0.04, 0.06) if zone != 2 else Color(1.0, 0.4, 0.1), zone == 2)
				continue
			b.box(Vector3(tile - 0.03, 0.1, tile - 0.03), MeshKit.at(tp + Vector3(0.0, -0.05, 0.0)), col)
	# Walls with door gaps (each room draws its own half of a shared wall).
	var ds: Dictionary = r["doors"]
	for d in 4:
		var v: Vector2i = FloorGen.DIRS[d]
		var hgt := WALL_NS if d % 2 == 0 else WALL_EW
		var len := 2.0 * h + 1.0
		var mid := c + Vector3(v.x, 0.0, v.y) * (h + 0.25)
		var along := Vector3(1.0, 0.0, 0.0) if d % 2 == 0 else Vector3(0.0, 0.0, 1.0)
		var size_for := func(l: float) -> Vector3: return Vector3(l, hgt, 0.5) if d % 2 == 0 else Vector3(0.5, hgt, l)
		if ds.has(d):
			var seg := (len - 2.0 * FloorGen.DOOR) * 0.5
			for s in [-1.0, 1.0]:
				var sc: Vector3 = mid + along * s * (FloorGen.DOOR + seg * 0.5)
				b.box(size_for.call(seg), MeshKit.at(sc + Vector3(0.0, hgt * 0.5, 0.0)), wall)
				b.cylinder(0.24, 0.28, hgt + 0.35, MeshKit.at(mid + along * s * (FloorGen.DOOR + 0.12) + Vector3(0.0, (hgt + 0.35) * 0.5, 0.0)), wall.lightened(0.15), 8)
			if d % 2 == 1:
				b.box(size_for.call(2.0 * FloorGen.DOOR), MeshKit.at(mid + Vector3(0.0, hgt - 0.2, 0.0)), wall.lightened(0.12))
			# The doorway floor (between the rooms).
			b.box(Vector3(2.0 * FloorGen.DOOR, 0.1, 0.55) if d % 2 == 0 else Vector3(0.55, 0.1, 2.0 * FloorGen.DOOR), MeshKit.at(mid + Vector3(0.0, -0.05, 0.0)), (fc[0] as Color).darkened(0.1))
		else:
			b.box(size_for.call(len), MeshKit.at(mid + Vector3(0.0, hgt * 0.5, 0.0)), wall)
			# A row of rounded stones on top.
			for k in 4:
				b.rounded_box(Vector3(2.4, 0.2, 0.6) if d % 2 == 0 else Vector3(0.6, 0.2, 2.4), 0.06, MeshKit.at(mid + along * (-3.9 + k * 2.6) + Vector3(0.0, hgt + 0.08, 0.0)), wall.lightened(0.1))
	# Corner pillars.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.cylinder(0.4, 0.45, WALL_EW + 0.2, MeshKit.at(c + Vector3(sx * (h + 0.25), (WALL_EW + 0.2) * 0.5, sz * (h + 0.25))), wall.darkened(0.12), 8)
	# Pillars inside (the obstacles).
	for rect in FloorGen.LAYOUTS[int(r["layout"])]:
		var a: Array = rect
		var pc := c + Vector3(float(a[0]), 0.0, float(a[1]))
		var sz2 := Vector3(float(a[2]) * 2.0, 1.6, float(a[3]) * 2.0)
		b.rounded_box(sz2, 0.12, MeshKit.at(pc + Vector3(0.0, 0.8, 0.0)), wall.lightened(0.05))
		b.box(sz2 + Vector3(0.2, -1.45, 0.2), MeshKit.at(pc + Vector3(0.0, 1.62, 0.0)), wall.lightened(0.2))
	# Torches on the side walls (glowing flames are part of the mesh: no per-torch nodes).
	for sx in [-1.0, 1.0]:
		var tz: float = rng.randf_range(-2.5, 2.5)
		if ds.has(1 if sx > 0.0 else 3) and absf(tz) < 2.0:
			tz = 3.2 * signf(tz + 0.01)
		var tp2 := c + Vector3(sx * (h - 0.05), 1.55, tz)
		b.box(Vector3(0.12, 0.08, 0.08), MeshKit.at(tp2 + Vector3(sx * 0.05, -0.25, 0.0)), Color(0.25, 0.25, 0.3))
		b.cylinder(0.05, 0.035, 0.35, MeshKit.at(tp2 + Vector3(0.0, -0.12, 0.0), Vector3.ONE, Vector3(0, 0, -sx * 0.35)), Color(0.45, 0.3, 0.18), 6)
		b.sphere(0.09, MeshKit.at(tp2 + Vector3(0.0, 0.05, 0.0), Vector3(1, 1.3, 1)), glow.lerp(Color(1.0, 0.6, 0.2), 0.6), 8, true)
	# Decorations per zone.
	for k in rng.randi_range(3, 6):
		var side := rng.randi_range(0, 3)
		var t := rng.randf_range(-4.3, 4.3)
		var v2: Vector2i = FloorGen.DIRS[side]
		var dp := c + Vector3(v2.x, 0.0, v2.y) * (h - 0.35) + (Vector3(t, 0.0, 0.0) if side % 2 == 0 else Vector3(0.0, 0.0, t))
		if ds.has(side) and absf(t) < FloorGen.DOOR + 0.6:
			continue
		match zone:
			0:
				b.sphere(rng.randf_range(0.2, 0.35), MeshKit.at(dp, Vector3(1.0, 0.55, 1.0)), Color(0.35, 0.65, 0.35), 8)
				if rng.randf() < 0.5:
					b.prism(5, 0.09, rng.randf_range(0.35, 0.6), MeshKit.at(dp + Vector3(0.15, 0.2, 0.1), Vector3.ONE, Vector3(0.2, 0, 0.3)), Color(0.4, 1.0, 0.8), true)
			1:
				b.cylinder(0.04, 0.04, 0.4, MeshKit.at(dp + Vector3(0.0, 0.04, 0.0), Vector3.ONE, Vector3(0, rng.randf() * TAU, PI * 0.5)), Color(0.92, 0.9, 0.82), 6)
				b.sphere(0.07, MeshKit.at(dp + Vector3(0.18, 0.06, 0.0)), Color(0.92, 0.9, 0.82), 6)
				if rng.randf() < 0.5:
					b.cylinder(0.05, 0.05, 0.2, MeshKit.at(dp + Vector3(-0.2, 0.1, 0.1)), Color(0.95, 0.92, 0.8), 6)
					b.sphere(0.05, MeshKit.at(dp + Vector3(-0.2, 0.25, 0.1), Vector3(1, 1.4, 1)), Color(1.0, 0.8, 0.4), 6, true)
			_:
				b.box(Vector3(rng.randf_range(0.6, 1.4), 0.02, 0.08), MeshKit.at(dp + Vector3(0.0, 0.01, 0.0) - Vector3(v2.x, 0.0, v2.y) * 0.8, Vector3.ONE, Vector3(0, rng.randf() * PI, 0)), Color(1.0, 0.45, 0.1), true)
				if rng.randf() < 0.4:
					b.box(Vector3(0.5, 0.3, 0.3), MeshKit.at(dp + Vector3(0.0, 0.15, 0.0)), Color(0.25, 0.25, 0.3))
	# Stairs down: a dark square with steps, ringed with light.
	if r.has("stairs"):
		var sp := FloorGen.to_world(f, i, r["stairs"])
		stairs_at = sp
		for k in 4:
			var w := 1.8 - k * 0.3
			b.box(Vector3(w, 0.05, w), MeshKit.at(sp + Vector3(0.0, 0.01 - k * 0.0, 0.0) + Vector3(0.0, 0.002 * k, 0.0)), Color(0.12, 0.1, 0.14).lerp(Color.BLACK, k * 0.25))
		b.box(Vector3(0.6, 0.06, 0.6), MeshKit.at(sp + Vector3(0.0, 0.03, 0.0)), Color(0.0, 0.0, 0.0))
	if r.has("key_at"):
		key_spot = FloorGen.to_world(f, i, r["key_at"])


func _ring(radius: float, col: Color) -> MeshInstance3D:
	var b := MeshKit.Builder.new()
	b.torus(radius, 0.06, Transform3D.IDENTITY, col, 24, 4, true)
	var mi := MeshKit.instance(b.build(), false)
	add_child(mi)
	return mi


func _build_doors(zd: Dictionary) -> void:
	var dl: Array = f["doors"]
	for di in dl.size():
		var d: Dictionary = dl[di]
		var t := int(d["type"])
		var m := FloorGen.door_world(f, di)
		var ns := int(d["dir"]) % 2 == 0  # the wall runs along x
		var node := Node3D.new()
		node.position = m
		if not ns:
			node.rotation.y = PI * 0.5
		add_child(node)
		var entry := {"bars": null, "plug": null, "y": 0.0, "type": t}
		if t == FloorGen.SECRET:
			var pb := MeshKit.Builder.new()
			var wall: Color = zd["wall"]
			var hgt := WALL_NS if ns else WALL_EW
			pb.box(Vector3(2.0 * FloorGen.DOOR + 0.1, hgt, 0.95), MeshKit.at(Vector3(0.0, hgt * 0.5, 0.0)), wall.darkened(0.04))
			for k in 5:  # cracks: thin dark lines, the clue
				pb.box(Vector3(0.05, 0.4 + k * 0.08, 0.98), MeshKit.at(Vector3(-0.8 + k * 0.4, 0.35 + (k % 2) * 0.25, 0.0), Vector3.ONE, Vector3(0, 0, 0.5 - k * 0.25)), Color(0.12, 0.1, 0.12))
			var plug := MeshKit.instance(pb.build(), false)
			node.add_child(plug)
			entry["plug"] = plug
		else:
			var bb := MeshKit.Builder.new()
			var iron := Color(0.3, 0.3, 0.36)
			var hgt2 := 2.3
			for k in 7:
				bb.cylinder(0.045, 0.045, hgt2, MeshKit.at(Vector3(-FloorGen.DOOR + 0.15 + k * (2.0 * FloorGen.DOOR - 0.3) / 6.0, hgt2 * 0.5, 0.0)), iron, 6)
			for y in [0.45, 1.3, 2.1]:
				bb.box(Vector3(2.0 * FloorGen.DOOR, 0.07, 0.07), MeshKit.at(Vector3(0.0, float(y), 0.0)), iron)
			match t:
				FloorGen.LOCKED:
					bb.rounded_box(Vector3(0.4, 0.46, 0.16), 0.05, MeshKit.at(Vector3(0.0, 0.9, 0.0)), Color(1.0, 0.8, 0.3), true)
					bb.box(Vector3(0.07, 0.16, 0.18), MeshKit.at(Vector3(0.0, 0.85, 0.0)), Color(0.15, 0.1, 0.05))
				FloorGen.BOSS:
					bb.rounded_box(Vector3(2.0 * FloorGen.DOOR, 2.0, 0.18), 0.08, MeshKit.at(Vector3(0.0, 1.05, 0.0)), Color(0.45, 0.2, 0.4))
					bb.rounded_box(Vector3(0.5, 0.56, 0.24), 0.05, MeshKit.at(Vector3(0.0, 1.0, 0.0)), Color(1.0, 0.8, 0.3), true)
					for k in 3:
						bb.cone(0.1, 0.25, MeshKit.at(Vector3(-0.22 + k * 0.22, 1.42, 0.0)), Color(1.0, 0.8, 0.3), 6, true)
				FloorGen.PUZZLE:
					var sc: Color = SWITCH_COLORS[0]
					for k in 3:
						bb.sphere(0.1, MeshKit.at(Vector3(-0.6 + k * 0.6, 1.3, 0.0)), sc, 8, true)
			var bars := MeshKit.instance(bb.build(), false)
			node.add_child(bars)
			entry["bars"] = bars
		doors.append(entry)


func _build_props() -> void:
	var pot_mesh := Dungeon.make_pot()
	var base := Dungeon.make_chest_base()
	var lid_mesh := Dungeon.make_lid()
	for ch in FloorGen.chest_list(f):
		var a: Array = ch
		var n := Node3D.new()
		n.add_child(MeshKit.instance(base, false))
		var lid := Node3D.new()
		lid.position = Vector3(0.0, 0.42, -0.26)
		var lm := MeshKit.instance(lid_mesh, false)
		lm.position = Vector3(0.0, 0.0, 0.26)
		lid.add_child(lm)
		n.add_child(lid)
		var p := FloorGen.to_world(f, int(a[0]), a[1])
		n.position = p
		n.rotation.y = PI if (a[1] as Vector2).y < 0.0 else 0.0
		add_child(n)
		chests.append({"node": n, "lid": lid, "room": int(a[0]), "p": p})
	for pt in FloorGen.pot_list(f):
		var a2: Array = pt
		var pn := MeshKit.instance(pot_mesh, false)
		var pp := FloorGen.to_world(f, int(a2[0]), a2[1])
		pn.position = pp
		pn.rotation.y = randf() * TAU
		add_child(pn)
		pots.append({"node": pn, "room": int(a2[0]), "p": pp})
	if stairs_at != Vector3.INF:
		stairs_ring = _ring(1.2, Color(0.5, 1.0, 0.7))
		stairs_ring.position = stairs_at + Vector3(0.0, 0.04, 0.0)


func _build_switches() -> void:
	for sw in f["switches"]:
		var s: Dictionary = sw
		var p := FloorGen.to_world(f, int(s["room"]), s["p"])
		var col: Color = SWITCH_COLORS[switches.size() % 2]
		var n := Node3D.new()
		n.position = p
		add_child(n)
		var e := {"node": n, "kind": String(s["kind"]), "p": p, "on": 0.0, "col": col}
		if String(s["kind"]) == "plate":
			var b := MeshKit.Builder.new()
			b.cylinder(0.62, 0.66, 0.08, MeshKit.at(Vector3(0, 0.04, 0)), Color(0.35, 0.35, 0.4), 16)
			var base := MeshKit.instance(b.build(), false)
			n.add_child(base)
			var tb := MeshKit.Builder.new()
			tb.cylinder(0.5, 0.52, 0.1, MeshKit.at(Vector3(0, 0.0, 0)), col, 16, true)
			var top := MeshKit.instance(tb.build(), false)
			top.position.y = 0.12
			n.add_child(top)
			e["top"] = top
			e["ring"] = _ring(0.8, col)
			(e["ring"] as Node3D).position = p + Vector3(0.0, 0.03, 0.0)
		else:
			var w := int(s["wall"])
			n.rotation.y = [0.0, -PI * 0.5, PI, PI * 0.5][maxi(w, 0)]
			var b2 := MeshKit.Builder.new()
			b2.rounded_box(Vector3(0.5, 0.6, 0.12), 0.04, MeshKit.at(Vector3(0, 1.0, 0.0)), Color(0.35, 0.35, 0.4))
			n.add_child(MeshKit.instance(b2.build(), false))
			var arm := Node3D.new()
			arm.position = Vector3(0.0, 1.0, 0.1)
			var ab := MeshKit.Builder.new()
			ab.cylinder(0.04, 0.04, 0.5, MeshKit.at(Vector3(0, 0.25, 0)), Color(0.5, 0.35, 0.2), 6)
			ab.sphere(0.1, MeshKit.at(Vector3(0, 0.52, 0)), col, 10, true)
			arm.add_child(MeshKit.instance(ab.build(), false))
			arm.rotation.x = 0.7
			n.add_child(arm)
			e["arm"] = arm
		switches.append(e)


func _build_traps(_zd: Dictionary) -> void:
	for t in f["traps"]:
		var td: Dictionary = t
		var e := {"kind": String(td["kind"]), "room": int(td["room"]), "s": 0.0, "v": 0.0}
		match String(td["kind"]):
			"spikes":
				var b := MeshKit.Builder.new()
				var wb := MeshKit.Builder.new()
				var base := MeshKit.Builder.new()
				var world: Array = []
				for tp in td["tiles"]:
					var p := FloorGen.to_world(f, int(td["room"]), tp)
					world.append(p)
					for k in 4:
						var o := Vector3(-0.35 + (k % 2) * 0.7, 0.0, -0.35 + (k / 2) * 0.7)
						b.cone(0.13, 0.6, MeshKit.at(p + o + Vector3(0.0, 0.3, 0.0)), Color(0.85, 0.87, 0.92), 6)
						base.cylinder(0.12, 0.14, 0.03, MeshKit.at(p + o + Vector3(0.0, 0.015, 0.0)), Color(0.12, 0.12, 0.15), 6)
					wb.box(Vector3(FloorGen.TILE - 0.1, 0.02, FloorGen.TILE - 0.1), MeshKit.at(p + Vector3(0.0, 0.015, 0.0)), Color(1.0, 0.3, 0.2), true)
				add_child(MeshKit.instance(base.build(), false))
				var spikes := MeshKit.instance(b.build(), false)
				spikes.position.y = -0.62
				add_child(spikes)
				var warn := MeshKit.instance(wb.build(), false)
				warn.visible = false
				add_child(warn)
				e["node"] = spikes
				e["warn"] = warn
				e["tiles"] = world
			"boulder":
				var bb := MeshKit.Builder.new()
				bb.sphere(0.75, Transform3D.IDENTITY, Color(0.5, 0.45, 0.42), 12)
				for k in 5:
					bb.sphere(0.2, MeshKit.at(Vector3(cos(k * 1.3) * 0.62, sin(k * 2.1) * 0.5, sin(k * 1.3) * 0.62)), Color(0.42, 0.38, 0.36), 6)
				var boulder := MeshKit.instance(bb.build(), false)
				boulder.visible = false
				add_child(boulder)
				e["node"] = boulder
				var lb := MeshKit.Builder.new()
				lb.box(Vector3(2.0 * FloorGen.HALF, 0.02, 1.5) if int(td["axis"]) == 0 else Vector3(1.5, 0.02, 2.0 * FloorGen.HALF), Transform3D.IDENTITY, Color(1.0, 0.35, 0.2), true)
				var lane := MeshKit.instance(lb.build(), false)
				lane.position = boulder_lane_point(td, 0.0) + Vector3(0.0, 0.02, 0.0)
				lane.visible = false
				add_child(lane)
				e["lane"] = lane
				e["axis"] = int(td["axis"])
			"collapse":
				var tiles: Array = []
				var zd: Dictionary = FloorGen.ZONES[zone]
				var fc: Array = zd["floor"]
				var tb := MeshKit.Builder.new()
				tb.box(Vector3(FloorGen.TILE - 0.06, 0.1, FloorGen.TILE - 0.06), MeshKit.at(Vector3(0.0, -0.05, 0.0)), (fc[1] as Color).darkened(0.08))
				for k in 4:
					tb.box(Vector3(0.6, 0.012, 0.035), MeshKit.at(Vector3(-0.2 + k * 0.15, 0.003, -0.3 + k * 0.2), Vector3.ONE, Vector3(0, k * 0.9, 0)), Color(0.1, 0.08, 0.1))
				var tm := tb.build()
				for tp in td["tiles"]:
					var p := FloorGen.to_world(f, int(td["room"]), tp)
					var tn := MeshKit.instance(tm, false)
					tn.position = p
					add_child(tn)
					tiles.append({"node": tn, "p": p})
				e["tiles"] = tiles
		traps.append(e)


## Where a boulder is at `along` (-1..1 across the room) on its lane.
func boulder_lane_point(td: Dictionary, along: float) -> Vector3:
	var c := FloorGen.room_center(f, int(td["room"]))
	var lane: float = td["lane"]
	if int(td["axis"]) == 0:
		return c + Vector3(along * FloorGen.HALF, 0.0, lane)
	return c + Vector3(lane, 0.0, along * FloorGen.HALF)


# --- State ---------------------------------------------------------------------------------------

## Which doors can be walked through now (pass) and which are opened for good (open: secret walls).
func set_pass(walk_bits: int, opened: int) -> void:
	pass_bits = walk_bits
	open_bits = opened
	if f.is_empty():
		return
	rects = FloorGen.walk_rects(f, walk_bits)
	obst = FloorGen.obstacle_rects(f)
	for di in doors.size():
		var e: Dictionary = doors[di]
		if e["plug"] != null:
			(e["plug"] as Node3D).visible = opened & (1 << di) == 0


func set_chests(bits: int) -> void:
	for id in chests.size():
		var on := bits & (1 << id) != 0
		var lid: Node3D = chests[id]["lid"]
		if on and _chest_bits & (1 << id) == 0:
			var tw := lid.create_tween()
			tw.tween_property(lid, "rotation:x", -1.9, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		elif not on:
			lid.rotation.x = 0.0
	_chest_bits = bits


func set_pots(bits: int) -> void:
	_pot_bits = bits
	for id in pots.size():
		(pots[id]["node"] as Node3D).visible = bits & (1 << id) == 0


func chest_open(id: int) -> bool:
	return _chest_bits & (1 << id) != 0


func pot_broken(id: int) -> bool:
	return _pot_bits & (1 << id) != 0


## Switch states from the host: 0 off, 0..1 = staying on for a bit longer, 1 = held.
func apply_switches(a: PackedFloat32Array) -> void:
	for i in mini(a.size(), switches.size()):
		switches[i]["on"] = a[i]


## Trap states from the host: two floats per trap (see deep.gd).
func apply_traps(a: PackedFloat32Array) -> void:
	for i in mini(a.size() / 2, traps.size()):
		traps[i]["s"] = a[i * 2]
		traps[i]["v"] = a[i * 2 + 1]


func clamp(from: Vector3, to: Vector3, r: float) -> Vector3:
	if f.is_empty():
		return to
	return FloorGen.clamp_move(rects, obst, from, to, r)


# --- Every frame ---------------------------------------------------------------------------------

func animate(delta: float, focus_room: int) -> void:
	if f.is_empty():
		return
	_t += delta
	if focus_room >= 0:
		var target := FloorGen.room_center(f, focus_room) + Vector3(0.0, 4.2, 0.0)
		light.position = light.position.lerp(target, 1.0 - exp(-2.5 * delta))
	for di in doors.size():
		var e: Dictionary = doors[di]
		if e["bars"] == null:
			continue
		var want := -2.45 if pass_bits & (1 << di) != 0 else 0.0
		var bars: Node3D = e["bars"]
		bars.position.y = move_toward(bars.position.y, want, delta * 3.0)
		bars.visible = bars.position.y > -2.4
	for s in switches:
		var on: float = s["on"]
		if s.has("top"):
			(s["top"] as Node3D).position.y = 0.12 - (0.07 if on >= 0.999 else (0.05 if on > 0.0 else 0.0))
			var ring: Node3D = s["ring"]
			ring.scale = Vector3.ONE * (1.0 + (0.15 * sin(_t * 6.0) if on <= 0.0 else 0.0)) * (0.6 + 0.4 * (1.0 if on <= 0.0 else on))
		else:
			var arm: Node3D = s["arm"]
			arm.rotation.x = lerpf(arm.rotation.x, -0.7 if on > 0.0 else 0.7, 1.0 - exp(-10.0 * delta))
	for t in traps:
		match String(t["kind"]):
			"spikes":
				var st: float = t["s"]
				var node: Node3D = t["node"]
				var want_y := -0.62 if st < 0.5 else (-0.45 if st < 1.5 else 0.0)
				node.position.y = move_toward(node.position.y, want_y, delta * (8.0 if st >= 1.5 else 2.0))
				(t["warn"] as Node3D).visible = st >= 0.5 and st < 1.5 and fmod(_t, 0.3) < 0.18
			"boulder":
				var st2: float = t["s"]
				var bn: Node3D = t["node"]
				(t["lane"] as Node3D).visible = st2 >= 0.5 and st2 < 1.5 and fmod(_t, 0.3) < 0.2
				bn.visible = st2 >= 1.5
				if bn.visible:
					var td: Dictionary = (f["traps"] as Array)[traps.find(t)]
					var np := boulder_lane_point(td, float(t["v"])) + Vector3(0.0, 0.75, 0.0)
					var moved := np - bn.position
					bn.position = np
					if moved.length() < 2.0:
						var axis := Vector3(0, 0, 1) if int(t["axis"]) == 0 else Vector3(1, 0, 0)
						bn.rotate(axis, -moved.length() / 0.75 * signf(moved.x if int(t["axis"]) == 0 else -moved.z))
			"collapse":
				var shaking := int(t["s"])
				var fallen := int(t["v"])
				var tiles: Array = t["tiles"]
				for k in tiles.size():
					var te: Dictionary = tiles[k]
					var tn: Node3D = te["node"]
					var p: Vector3 = te["p"]
					if fallen & (1 << k) != 0:
						tn.position.y = move_toward(tn.position.y, -3.0, delta * 6.0)
						tn.visible = tn.position.y > -2.9
					else:
						tn.visible = true
						tn.position = Vector3(p.x, move_toward(tn.position.y, 0.0, delta * 4.0), p.z)
						if shaking & (1 << k) != 0:
							tn.position.x = p.x + sin(_t * 60.0) * 0.03
	if stairs_ring != null:
		stairs_ring.scale = Vector3.ONE * (1.0 + 0.1 * sin(_t * 4.0))
