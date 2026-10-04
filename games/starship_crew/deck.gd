extends Node3D
## Starship Crew: the ship's deck - a cut-away cartoon interior the TV crew runs around in.
## Layout data (rooms, doors, walls, stations), 2D collision for walkers (circle vs boxes on the XZ
## plane), simple door-to-door paths for the robot crew and bots, and the deck visuals: floors, walls,
## consoles with live screens, the reactor, the torpedo rack and tube, floating "job" markers and the
## red-alert light strips (one shared material, so an alert recolours every strip at once).
## 2D positions are Vector2(x, z). The bridge (front, -Z) holds the captain's cockpit (cockpit.gd).

const MeshKit := preload("res://core/mesh_kit.gd")
const UiKit := preload("res://core/ui_kit.gd")
const Models := preload("res://games/starship_crew/models.gd")

## Rooms: display name, Rect2(x, z, width, depth), floor colour.
const ROOMS := {
	"bridge": {"name": "BRIDGE", "rect": Rect2(-3.2, -11.0, 6.4, 5.0), "floor": Color(0.3, 0.34, 0.46)},
	"weapons": {"name": "WEAPONS", "rect": Rect2(-8.0, -6.0, 5.0, 5.0), "floor": Color(0.55, 0.32, 0.34)},
	"science": {"name": "SCIENCE LAB", "rect": Rect2(3.0, -6.0, 5.0, 5.0), "floor": Color(0.27, 0.48, 0.44)},
	"hall": {"name": "MAIN HALL", "rect": Rect2(-3.0, -6.0, 6.0, 10.0), "floor": Color(0.38, 0.4, 0.5)},
	"armoury": {"name": "ARMOURY", "rect": Rect2(-8.0, -1.0, 5.0, 5.0), "floor": Color(0.5, 0.4, 0.27)},
	"cargo": {"name": "CARGO BAY", "rect": Rect2(3.0, -1.0, 5.0, 5.0), "floor": Color(0.33, 0.37, 0.56)},
	"engine": {"name": "ENGINE ROOM", "rect": Rect2(-8.0, 4.0, 16.0, 5.0), "floor": Color(0.45, 0.35, 0.53)},
}
## Doors between rooms (door centre on the wall line).
const DOORS: Array = [
	["bridge", "hall", Vector2(0.0, -6.0)],
	["weapons", "hall", Vector2(-3.0, -3.5)],
	["science", "hall", Vector2(3.0, -3.5)],
	["armoury", "hall", Vector2(-3.0, 1.5)],
	["cargo", "hall", Vector2(3.0, 1.5)],
	["weapons", "armoury", Vector2(-5.5, -1.0)],
	["science", "cargo", Vector2(5.5, -1.0)],
	["hall", "engine", Vector2(0.0, 4.0)],
	["armoury", "engine", Vector2(-5.5, 4.0)],
	["cargo", "engine", Vector2(5.5, 4.0)],
]
const DOOR_WIDTH := 1.8
## Wall lines: [from, to] on the XZ plane (doors are cut out of them).
const WALL_LINES: Array = [
	[Vector2(-8.0, -6.0), Vector2(-8.0, 9.0)], [Vector2(8.0, -6.0), Vector2(8.0, 9.0)],
	[Vector2(-8.0, 9.0), Vector2(8.0, 9.0)],
	[Vector2(-8.0, -6.0), Vector2(-3.2, -6.0)], [Vector2(3.2, -6.0), Vector2(8.0, -6.0)],
	[Vector2(-3.2, -11.0), Vector2(-3.2, -6.0)], [Vector2(3.2, -11.0), Vector2(3.2, -6.0)],
	[Vector2(-3.0, -6.0), Vector2(-3.0, 4.0)], [Vector2(3.0, -6.0), Vector2(3.0, 4.0)],
	[Vector2(-8.0, -1.0), Vector2(-3.0, -1.0)], [Vector2(3.0, -1.0), Vector2(8.0, -1.0)],
	[Vector2(-8.0, 4.0), Vector2(-3.0, 4.0)], [Vector2(3.0, 4.0), Vector2(8.0, 4.0)],
	[Vector2(-3.0, 4.0), Vector2(3.0, 4.0)],
]
const WALL_H := 1.05
const WALL_T := 0.3

## Stations: name, room, console position, where the crew member stands, icon, accent colour.
## "upgrade": only there once that upgrade is bought. "shop": only at a trading post.
const STATIONS := {
	"nav": {"name": "NAVIGATION", "room": "bridge", "pos": Vector2(2.6, -8.2), "stand": Vector2(1.75, -8.2), "icon": "flag", "color": Color(0.4, 0.8, 1.0)},
	"tube": {"name": "TORPEDO TUBE", "room": "hall", "pos": Vector2(-2.3, -5.35), "stand": Vector2(-1.9, -4.45), "icon": "arrow_up", "color": Color(1.0, 0.4, 0.35)},
	"weapons": {"name": "TURRET 1", "room": "weapons", "pos": Vector2(-7.3, -3.5), "stand": Vector2(-6.45, -3.5), "icon": "sword", "color": Color(1.0, 0.45, 0.4)},
	"science": {"name": "SCIENCE", "room": "science", "pos": Vector2(7.3, -3.5), "stand": Vector2(6.45, -3.5), "icon": "eye", "color": Color(0.45, 1.0, 0.65)},
	"armoury": {"name": "TORPEDO RACK", "room": "armoury", "pos": Vector2(-7.35, 1.8), "stand": Vector2(-6.4, 1.8), "icon": "bag", "color": Color(1.0, 0.75, 0.3)},
	"turret2": {"name": "TURRET 2", "room": "cargo", "pos": Vector2(7.3, 1.6), "stand": Vector2(6.45, 1.6), "icon": "sword", "color": Color(1.0, 0.45, 0.4), "upgrade": "turret2"},
	"engineering": {"name": "ENGINEERING", "room": "engine", "pos": Vector2(3.2, 8.35), "stand": Vector2(3.2, 7.45), "icon": "bolt", "color": Color(1.0, 0.85, 0.3)},
	"shop": {"name": "TRADER", "room": "hall", "pos": Vector2(0.0, 1.9), "stand": Vector2(0.0, 0.85), "icon": "coin", "color": Color(1.0, 0.82, 0.3), "shop": true},
}
## Which way each console faces (its screen side), as yaw radians (0 = facing +Z).
const STATION_YAW := {"nav": -PI * 0.5, "tube": 0.0, "weapons": PI * 0.5, "science": -PI * 0.5, "armoury": PI * 0.5,
	"turret2": -PI * 0.5, "engineering": PI, "shop": 0.0}
const USE_RADIUS := 1.35
const REACTOR := Vector2(0.0, 6.6)
const CAPTAIN_SEAT := Vector3(0.0, 0.0, -8.6)
## Furniture the walkers bump into (Rect2(x, z, w, d)).
const OBSTACLES: Array = [
	Rect2(-1.0, -9.95, 2.0, 1.9),  # captain's chair and dashboard
	Rect2(-0.95, 5.65, 1.9, 1.9),  # reactor
	Rect2(-3.2, -11.0, 6.4, 0.7),  # window sill
]
## Robot docks in the cargo bay.
const DOCKS: Array[Vector2] = [Vector2(4.1, 3.2), Vector2(5.3, 3.2), Vector2(6.5, 3.2), Vector2(4.1, 2.2)]
## Rooms where problems (fires, holes) can break out.
const PROBLEM_ROOMS: Array[String] = ["weapons", "science", "hall", "armoury", "cargo", "engine"]
## Turret gun mounts on the hull (world positions), by station.
const TURRET_MOUNTS := {"weapons": Vector3(-8.75, 0.55, -3.5), "turret2": Vector3(8.75, 0.55, 1.6)}

var paint_id := "classic"
var walls: Array[Rect2] = []  # collision boxes (walls + furniture + consoles)
var screens := {}  # station id -> MeshInstance3D (the console screen)
var screen_mats := {}  # station id -> StandardMaterial3D
var markers := {}  # station id -> Node3D (floating "job here" marker)
var stand_rings := {}  # station id -> MeshInstance3D (glowing ring on the floor)
var rack_torps: MultiMeshInstance3D
var tube_torps: Array[MeshInstance3D] = []
var reactor_core: MeshInstance3D
var strip_mat: StandardMaterial3D
var light: OmniLight3D
var hull_mi: MeshInstance3D
var deck_mi: MeshInstance3D
var turret2_parts: Array[Node3D] = []
var _t := 0.0
var _alert := 0
var _room_labels: Array[Label3D] = []


func _ready() -> void:
	_build_collision()
	_build_visuals()


# --- Layout queries --------------------------------------------------------------------------

## The room id at a 2D point ("" outside).
static func room_at(p: Vector2) -> String:
	for id in ROOMS:
		var r: Rect2 = ROOMS[id]["rect"]
		if r.grow(0.05).has_point(p):
			if id == "hall" and p.y < -6.0:
				continue
			return str(id)
	return ""


static func room_name(id: String) -> String:
	return String(ROOMS[id]["name"]) if ROOMS.has(id) else "SPACE"


static func station_pos(id: String) -> Vector2:
	return STATIONS[id]["pos"]


static func station_stand(id: String) -> Vector2:
	return STATIONS[id]["stand"]


static func v3(p: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


static func v2(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


## A random free floor spot in a room for a problem (away from consoles and other spots).
static func random_spot(room: String, rng: RandomNumberGenerator, avoid: Array) -> Vector2:
	var r: Rect2 = ROOMS[room]["rect"]
	var best := r.get_center()
	for attempt in 24:
		var p := Vector2(rng.randf_range(r.position.x + 0.9, r.end.x - 0.9), rng.randf_range(r.position.y + 0.9, r.end.y - 0.9))
		var ok := p.distance_to(REACTOR) > 1.7
		for sid in STATIONS:
			if p.distance_to(STATIONS[sid]["pos"]) < 1.4 or p.distance_to(STATIONS[sid]["stand"]) < 1.0:
				ok = false
		for a in avoid:
			var q: Vector2 = a
			if p.distance_to(q) < 1.3:
				ok = false
		for d in DOORS:
			var dp: Vector2 = d[2]
			if p.distance_to(dp) < 1.2:
				ok = false
		if ok:
			return p
		best = p
	return best


## Push a walker (circle of `radius` at p) out of walls and furniture.
func resolve(p: Vector2, radius: float = 0.3) -> Vector2:
	for pass_i in 2:
		for w in walls:
			var closest := Vector2(clampf(p.x, w.position.x, w.end.x), clampf(p.y, w.position.y, w.end.y))
			var d := p - closest
			var dist := d.length()
			if dist < radius:
				if dist > 0.0001:
					p = closest + d / dist * radius
				else:
					# inside the box: leave by the nearest side
					var outs: Array[Vector2] = [Vector2(w.position.x - radius, p.y), Vector2(w.end.x + radius, p.y),
						Vector2(p.x, w.position.y - radius), Vector2(p.x, w.end.y + radius)]
					var best := outs[0]
					for o in outs:
						if o.distance_to(p) < best.distance_to(p):
							best = o
					p = best
	return p


## A walking route from `from` to `to`: door centres then the goal (rooms are boxes, so straight
## lines between them stay inside). Every point is inside the ship.
func path(from: Vector2, to: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var a := room_at(from)
	var b := room_at(to)
	if a == "" or b == "" or a == b:
		out.append(to)
		return out
	# Breadth-first search over rooms.
	var prev := {a: ""}
	var queue: Array[String] = [a]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == b:
			break
		for d in DOORS:
			var da: String = d[0]
			var db: String = d[1]
			var nxt := ""
			if da == cur:
				nxt = db
			elif db == cur:
				nxt = da
			if nxt != "" and not prev.has(nxt):
				prev[nxt] = cur
				queue.append(nxt)
	if not prev.has(b):
		out.append(to)
		return out
	var rooms: Array[String] = []
	var c := b
	while c != "":
		rooms.push_front(c)
		c = String(prev[c])
	for i in rooms.size() - 1:
		var door := _door_between(rooms[i], rooms[i + 1])
		# step through the middle of the doorway (a little either side of the wall line)
		var into := ROOMS[rooms[i + 1]]["rect"] as Rect2
		var dir := (into.get_center() - door).normalized()
		var axis := Vector2(signf(dir.x), 0.0) if _door_vertical(door) else Vector2(0.0, signf(dir.y))
		out.append(door - axis * 0.45)
		out.append(door + axis * 0.45)
	out.append(to)
	return out


func _door_between(a: String, b: String) -> Vector2:
	for d in DOORS:
		if (String(d[0]) == a and String(d[1]) == b) or (String(d[0]) == b and String(d[1]) == a):
			return d[2]
	return Vector2.ZERO


## True if the door sits on a wall running along Z (so you walk through it along X).
func _door_vertical(door: Vector2) -> bool:
	return absf(absf(door.x) - 3.0) < 0.3 or absf(absf(door.x) - 8.0) < 0.3


func _build_collision() -> void:
	walls.clear()
	for line in WALL_LINES:
		var a: Vector2 = line[0]
		var b: Vector2 = line[1]
		for seg in _cut_doors(a, b):
			var s: Array = seg
			var p: Vector2 = s[0]
			var q: Vector2 = s[1]
			walls.append(Rect2(Vector2(minf(p.x, q.x), minf(p.y, q.y)) - Vector2(WALL_T, WALL_T) * 0.5,
				Vector2(absf(q.x - p.x), absf(q.y - p.y)) + Vector2(WALL_T, WALL_T)))
	for o in OBSTACLES:
		walls.append(o)
	for sid in STATIONS:
		var sp: Vector2 = STATIONS[sid]["pos"]
		if sid == "shop":
			continue
		walls.append(Rect2(sp - Vector2(0.42, 0.42), Vector2(0.84, 0.84)))


## Split a wall line into the pieces left after cutting out its doors.
func _cut_doors(a: Vector2, b: Vector2) -> Array:
	var horizontal := absf(a.y - b.y) < 0.01
	var cuts: Array[Vector2] = []  # (from, to) along the wall's axis
	for d in DOORS:
		var dp: Vector2 = d[2]
		var w := DOOR_WIDTH * (1.6 if String(d[0]) == "bridge" or (String(d[0]) == "hall" and String(d[1]) == "engine") else 1.0)
		if String(d[0]) == "bridge":
			w = 6.4
		if horizontal and absf(dp.y - a.y) < 0.05 and dp.x > minf(a.x, b.x) - 0.01 and dp.x < maxf(a.x, b.x) + 0.01:
			cuts.append(Vector2(dp.x - w * 0.5, dp.x + w * 0.5))
		elif not horizontal and absf(dp.x - a.x) < 0.05 and dp.y > minf(a.y, b.y) - 0.01 and dp.y < maxf(a.y, b.y) + 0.01:
			cuts.append(Vector2(dp.y - w * 0.5, dp.y + w * 0.5))
	var lo := minf(a.x, b.x) if horizontal else minf(a.y, b.y)
	var hi := maxf(a.x, b.x) if horizontal else maxf(a.y, b.y)
	cuts.sort_custom(func(u: Vector2, v: Vector2) -> bool: return u.x < v.x)
	var out: Array = []
	var cur := lo
	for c in cuts:
		if c.x > cur + 0.05:
			out.append(_seg(horizontal, a, cur, minf(c.x, hi)))
		cur = maxf(cur, c.y)
	if hi > cur + 0.05:
		out.append(_seg(horizontal, a, cur, hi))
	return out


func _seg(horizontal: bool, a: Vector2, from: float, to: float) -> Array:
	if horizontal:
		return [Vector2(from, a.y), Vector2(to, a.y)]
	return [Vector2(a.x, from), Vector2(a.x, to)]


# --- Visuals ----------------------------------------------------------------------------------

func _build_visuals() -> void:
	hull_mi = MeshKit.instance(Models.ship_hull(paint_id), false)
	hull_mi.name = "Hull"
	add_child(hull_mi)
	deck_mi = MeshKit.instance(_deck_mesh(), false)
	deck_mi.name = "DeckMesh"
	add_child(deck_mi)
	strip_mat = StandardMaterial3D.new()
	strip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	strip_mat.albedo_color = Color(0.45, 0.85, 1.0)
	var strips := MeshKit.instance(_strip_mesh(), false)
	strips.name = "AlertStrips"
	strips.material_override = strip_mat
	add_child(strips)
	for id in ROOMS:
		if id == "bridge":
			continue
		var r: Rect2 = ROOMS[id]["rect"]
		var l := UiKit.label3d(String(ROOMS[id]["name"]), 0.32, Color(1, 1, 1, 0.28), true)
		l.no_depth_test = false
		l.outline_size = 0
		l.render_priority = 0
		l.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		var at := r.get_center()
		if id == "hall":
			at = Vector2(0.0, -0.2)
		elif id == "engine":
			at = Vector2(-4.5, 6.6)
		l.position = Vector3(at.x, 0.03, at.y + (0.0 if id != "armoury" and id != "cargo" else -0.9))
		add_child(l)
		_room_labels.append(l)
	# Consoles with their own screens.
	for sid in STATIONS:
		_build_station(String(sid))
	# The reactor: frame + glowing core (pulses with power).
	var frame := MeshKit.instance(Models.reactor_frame(), false)
	frame.position = v3(REACTOR)
	add_child(frame)
	reactor_core = MeshKit.instance(Models.reactor_core(), false)
	reactor_core.position = v3(REACTOR)
	add_child(reactor_core)
	# Torpedoes on the rack (as many as the ship has in stock, up to six).
	var xfs: Array = []
	var rp: Vector2 = STATIONS["armoury"]["pos"]
	for k in 6:
		xfs.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(rp.x - 0.05, 0.68 + (k / 3) * 0.5, rp.y - 0.45 + (k % 3) * 0.45)))
	rack_torps = MeshKit.scatter(Models.torpedo(), xfs, PackedColorArray(), PackedColorArray(), false)
	add_child(rack_torps)
	# Loaded torpedoes peeking out of the tube loader.
	var tp: Vector2 = STATIONS["tube"]["pos"]
	for k in 3:
		var t := MeshKit.instance(Models.torpedo(), false)
		t.position = Vector3(tp.x - 0.18 + k * 0.18, 0.75, tp.y)
		t.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		t.scale = Vector3.ONE * 0.6
		t.visible = false
		add_child(t)
		tube_torps.append(t)
	# A cosy warm light over the hall (one of the game's two OmniLights).
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.92, 0.8)
	light.light_energy = 1.1
	light.omni_range = 16.0
	light.omni_attenuation = 0.8
	light.shadow_enabled = false
	light.position = Vector3(0.0, 4.5, 0.5)
	add_child(light)


## Repaint the hull (paint job chosen at the title).
func set_paint(id: String) -> void:
	if id == paint_id and hull_mi != null:
		return
	paint_id = id
	if hull_mi != null:
		hull_mi.mesh = Models.ship_hull(paint_id)


func _deck_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var wall_col := Color(0.86, 0.88, 0.93)
	for id in ROOMS:
		var r: Rect2 = ROOMS[id]["rect"]
		var c: Color = ROOMS[id]["floor"]
		b.box(Vector3(r.size.x, 0.2, r.size.y), MeshKit.at(Vector3(r.get_center().x, -0.1, r.get_center().y)), c.darkened(0.15))
		b.panel(r.size - Vector2(0.5, 0.5), 0.3, MeshKit.at(Vector3(r.get_center().x, 0.005, r.get_center().y), Vector3.ONE, Vector3(-PI * 0.5, 0, 0)), c)
		# floor tiles: a light grid of thin lines
		var nx := int(r.size.x / 1.0)
		for k in range(1, nx):
			b.box(Vector3(0.03, 0.01, r.size.y - 0.7), MeshKit.at(Vector3(r.position.x + k * r.size.x / nx, 0.012, r.get_center().y)), c.lightened(0.08))
	for seg in _wall_segments():
		var s: Array = seg
		var p: Vector2 = s[0]
		var q: Vector2 = s[1]
		var mid := (p + q) * 0.5
		var size := Vector3(absf(q.x - p.x) + WALL_T, WALL_H, absf(q.y - p.y) + WALL_T)
		b.rounded_box(size, 0.1, MeshKit.at(Vector3(mid.x, WALL_H * 0.5, mid.y)), wall_col, 1)
	# Door frames: posts with a glowing top light either side of every doorway.
	for d in DOORS:
		if String(d[0]) == "bridge":
			continue
		var dp: Vector2 = d[2]
		var along := Vector2(0, 1) if _door_vertical(dp) else Vector2(1, 0)
		var w := DOOR_WIDTH * (1.6 if String(d[0]) == "hall" and String(d[1]) == "engine" else 1.0)
		for side in [-1.0, 1.0]:
			var sd: float = side
			var pp := dp + along * sd * (w * 0.5 + 0.05)
			b.rounded_box(Vector3(0.36, WALL_H + 0.25, 0.36), 0.08, MeshKit.at(Vector3(pp.x, (WALL_H + 0.25) * 0.5, pp.y)), Color(0.7, 0.72, 0.8), 1)
			b.sphere(0.09, MeshKit.at(Vector3(pp.x, WALL_H + 0.3, pp.y)), Color(0.5, 0.9, 1.0), 8, true)
	# Furniture: crates in the cargo bay, lockers in the armoury, a bunk, plants and a cake box!
	b.add_mesh(MeshKit.prop("crate"), MeshKit.at(Vector3(7.2, 0, 3.4), Vector3.ONE * 0.9, Vector3(0, 0.3, 0)))
	b.add_mesh(MeshKit.prop("crate", 1), MeshKit.at(Vector3(7.25, 0, -0.35), Vector3.ONE * 0.75, Vector3(0, -0.2, 0)))
	b.add_mesh(MeshKit.prop("barrel"), MeshKit.at(Vector3(-7.4, 0, 3.45), Vector3.ONE * 0.8))
	b.add_mesh(MeshKit.prop("barrel", 1), MeshKit.at(Vector3(-6.7, 0, 3.5), Vector3.ONE * 0.75))
	b.add_mesh(MeshKit.prop("bookshelf"), MeshKit.at(Vector3(7.55, 0, -5.4), Vector3.ONE * 0.6, Vector3(0, -PI * 0.5, 0)))
	b.add_mesh(MeshKit.prop("pot"), MeshKit.at(Vector3(-2.55, 0, 3.55), Vector3.ONE * 0.9))
	b.add_mesh(MeshKit.prop("pot", 1), MeshKit.at(Vector3(2.55, 0, 3.55), Vector3.ONE * 0.9))
	b.add_mesh(MeshKit.prop("pot", 2), MeshKit.at(Vector3(-2.55, 0, -0.6), Vector3.ONE * 0.8))
	# THE CAKE (in a glass case in the engine room, where it's warm).
	var cake := Vector3(-5.0, 0.0, 7.6)
	b.cylinder(0.8, 0.85, 0.5, MeshKit.at(cake + Vector3(0, 0.25, 0)), Color(0.6, 0.62, 0.7), 16)
	b.cylinder(0.65, 0.65, 0.4, MeshKit.at(cake + Vector3(0, 0.7, 0)), Color(1.0, 0.65, 0.8), 16)
	b.cylinder(0.45, 0.45, 0.35, MeshKit.at(cake + Vector3(0, 1.07, 0)), Color(1.0, 0.95, 0.88), 16)
	b.torus(0.65, 0.06, MeshKit.at(cake + Vector3(0, 0.9, 0)), Color(1, 1, 1), 16, 5)
	for k in 5:
		var a := k * TAU / 5.0
		b.cylinder(0.03, 0.03, 0.18, MeshKit.at(cake + Vector3(cos(a) * 0.28, 1.33, sin(a) * 0.28)), Color(0.5, 0.8, 1.0), 5)
		b.sphere(0.04, MeshKit.at(cake + Vector3(cos(a) * 0.28, 1.46, sin(a) * 0.28)), Color(1.0, 0.8, 0.3), 5, true)
	# Robot docks: charging pads.
	for d in DOCKS:
		b.disc(0.42, MeshKit.at(Vector3(d.x, 0.02, d.y)), Color(0.35, 0.65, 1.0), 14, true)
	# Wall screens and portholes on the outer walls.
	for k in 5:
		var z := -4.8 + k * 3.2
		b.disc(0.32, MeshKit.at(Vector3(-7.83, 0.62, z), Vector3.ONE, Vector3(0, 0, -PI * 0.5)), Color(0.15, 0.2, 0.4), 12)
		b.disc(0.32, MeshKit.at(Vector3(7.83, 0.62, z), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.15, 0.2, 0.4), 12)
	return b.build()


## The glowing strips along the bottom of every wall (red-alert colour comes from one material).
func _strip_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	for seg in _wall_segments():
		var s: Array = seg
		var p: Vector2 = s[0]
		var q: Vector2 = s[1]
		var mid := (p + q) * 0.5
		var size := Vector3(absf(q.x - p.x) + WALL_T + 0.02, 0.07, absf(q.y - p.y) + WALL_T + 0.02)
		b.box(size, MeshKit.at(Vector3(mid.x, WALL_H - 0.06, mid.y)), Color.WHITE)
	return b.build()


func _wall_segments() -> Array:
	var out: Array = []
	for line in WALL_LINES:
		var a: Vector2 = line[0]
		var b: Vector2 = line[1]
		out.append_array(_cut_doors(a, b))
	return out


func _build_station(sid: String) -> void:
	var st: Dictionary = STATIONS[sid]
	var p: Vector2 = st["pos"]
	var yaw: float = STATION_YAW.get(sid, 0.0)
	var root := Node3D.new()
	root.name = "Station_" + sid
	root.position = v3(p)
	root.rotation.y = yaw
	add_child(root)
	var col: Color = st["color"]
	match sid:
		"armoury":
			root.add_child(MeshKit.instance(Models.torpedo_rack(), false))
		"tube":
			root.add_child(MeshKit.instance(Models.tube_loader(), false))
		"shop":
			pass  # the trader is a character (crew.gd)
		_:
			root.add_child(MeshKit.instance(Models.console(), false))
			var scr := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.78, 0.36)
			scr.mesh = q
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = col.darkened(0.35)
			scr.material_override = m
			scr.position = Vector3(0.0, 1.16, -0.068)  # on the console's sloped face
			scr.rotation.x = -0.71
			root.add_child(scr)
			screens[sid] = scr
			screen_mats[sid] = m
			_station_decor(sid, root, col)
	if st.has("upgrade"):
		turret2_parts.append(root)
	# Stand ring on the floor (where to stand to use it) and the floating marker.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.52
	tm.rings = 24
	tm.ring_segments = 4
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(col.r, col.g, col.b, 0.55)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = rm
	ring.scale = Vector3(1.0, 0.15, 1.0)
	ring.position = v3(st["stand"], 0.03)
	add_child(ring)
	stand_rings[sid] = ring
	var mk := Node3D.new()
	mk.name = "Marker_" + sid
	var icon := UiKit.label3d("!", 0.5, Color(1.0, 0.85, 0.25), true)
	icon.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y  # TV-only marker (the VR captain never sees it from the front)
	icon.outline_size = 24
	mk.add_child(icon)
	mk.position = v3(p, 2.35)
	mk.visible = false
	add_child(mk)
	markers[sid] = mk
	if sid == "shop":
		ring.visible = false


## A little extra per console so each station reads at a glance.
func _station_decor(sid: String, root: Node3D, col: Color) -> void:
	var b := MeshKit.Builder.new()
	match sid:
		"nav":
			b.sphere(0.22, MeshKit.at(Vector3(0, 1.62, -0.12)), Color(0.4, 0.75, 1.0), 12, true)
			b.torus(0.3, 0.025, MeshKit.at(Vector3(0, 1.62, -0.12), Vector3.ONE, Vector3(0.4, 0, 0.3)), Color(1.0, 0.85, 0.4), 16, 4, true)
		"weapons", "turret2":
			b.cylinder(0.04, 0.05, 0.4, MeshKit.at(Vector3(0, 1.5, -0.15)), Color(0.4, 0.4, 0.45), 6)
			b.dome(0.26, MeshKit.at(Vector3(0, 1.72, -0.15), Vector3(1, 0.35, 1), Vector3(0.9, 0, 0)), Color(0.85, 0.85, 0.9), 12)
		"science":
			b.cylinder(0.12, 0.14, 0.28, MeshKit.at(Vector3(-0.32, 1.06, 0.05)), GLASS, 10)
			b.sphere(0.12, MeshKit.at(Vector3(0.32, 1.06, 0.05)), Color(0.5, 1.0, 0.5), 10, true)
		"engineering":
			for k in 3:
				b.box(Vector3(0.06, 0.3, 0.06), MeshKit.at(Vector3(-0.3 + k * 0.3, 1.5, -0.2)), Color(1.0, 0.85, 0.3), true)
	if not b.is_empty():
		root.add_child(MeshKit.instance(b.build(), false))


# --- Live updates -------------------------------------------------------------------------------

## Per frame: animate markers, the reactor and the alert strips. alert 0 calm, 1 yellow, 2 red.
func tick(delta: float, alert: int, power_total: float) -> void:
	_t += delta
	_alert = alert
	var c := Color(0.45, 0.85, 1.0)
	if alert == 2:
		c = Color(1.0, 0.2, 0.2).lerp(Color(0.4, 0.05, 0.05), 0.5 + 0.5 * sin(_t * 6.0))
	elif alert == 1:
		c = Color(1.0, 0.75, 0.2).lerp(Color(0.6, 0.4, 0.1), 0.5 + 0.5 * sin(_t * 3.0))
	strip_mat.albedo_color = c
	light.light_color = Color(1.0, 0.92, 0.8).lerp(Color(1.0, 0.35, 0.3), 0.45 if alert == 2 else 0.0)
	for sid in markers:
		var mk: Node3D = markers[sid]
		if mk.visible:
			mk.position.y = 2.35 + 0.15 * sin(_t * 4.0 + float(String(sid).length()))
	if reactor_core != null:
		var s := 0.92 + 0.06 * sin(_t * (3.0 + power_total)) + 0.01 * power_total
		reactor_core.scale = Vector3(s, 1.0, s)


## Show which stations need someone right now ("!" markers).
func set_markers(wanted: Dictionary) -> void:
	for sid in markers:
		(markers[sid] as Node3D).visible = bool(wanted.get(sid, false))


## Screen colour per station: "idle", "busy" (with the user's colour), "alert", "off" (sparking).
func set_screen(sid: String, state: String, col: Color = Color.WHITE) -> void:
	if not screen_mats.has(sid):
		return
	var m: StandardMaterial3D = screen_mats[sid]
	var base: Color = STATIONS[sid]["color"]
	match state:
		"busy":
			m.albedo_color = col.lerp(base, 0.3)
		"alert":
			m.albedo_color = Color(1.0, 0.85, 0.3) if fmod(_t, 0.6) < 0.3 else base
		"off":
			m.albedo_color = Color(0.25, 0.05, 0.05) if fmod(_t, 0.2) < 0.1 else Color(0.6, 0.1, 0.1)
		_:
			m.albedo_color = base.darkened(0.35)


## Torpedo stock on the rack and loaded torpedoes in the tube.
func set_torpedoes(stock: int, loaded: int) -> void:
	if rack_torps != null:
		rack_torps.multimesh.visible_instance_count = clampi(stock, 0, 6)
	for k in tube_torps.size():
		tube_torps[k].visible = k < loaded


## Turret 2's console only exists once it's bought.
func set_turret2(on: bool) -> void:
	for n in turret2_parts:
		n.visible = on
	if stand_rings.has("turret2"):
		(stand_rings["turret2"] as Node3D).visible = on


func set_shop(on: bool) -> void:
	if stand_rings.has("shop"):
		(stand_rings["shop"] as Node3D).visible = on
