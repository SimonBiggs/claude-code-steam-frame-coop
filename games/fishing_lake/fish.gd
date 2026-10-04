extends Node3D
## One fish slot in the lake (also used for the boots and treasure chests that get hooked off the bottom).
## The host steers it; on the TV machine it's a ghost gliding to the snapshot positions.
## Fish wander in shoals, flee from boats (so the TV players can herd them), swim up to a lure in the
## water, nibble, then bite. The angler (angler.gd) takes over once it's hooked.
## Each kind is drawn as ONE vertex-coloured mesh (body, fins, eyes, stripes and spots, built once and
## cached) plus a wagging tail, so even the fancy fish cost two draw calls.

const Lake := preload("res://games/fishing_lake/lake.gd")

const MINNOW := 0
const PERCH := 1
const TROUT := 2
const CATFISH := 3
const PIKE := 4
const GOLDEN := 5
const BOOT := 6
const CHEST := 7
const BLUEGILL := 8
const EEL := 9
const PUFFER := 10
const MOONFISH := 11
const KOI := 12
const LEGEND := 13
# len: body length (m), pts: points, pull: how hard it fights (0..1), kg: weight range,
# speed: cruising m/s, notice: how far it spots a lure, spawn: weight in the spawn lottery,
# when: 0 any time, 1 dry weather, 2 only in the rain, 3 only after dark, 4 special (never random),
# thin / tall: body width / height as a fraction of its length, fin: fin + tail colour,
# hint: where to look (shown in the fish journal before you've caught one).
const TYPES := [
	{"name": "Minnow", "col": Color(0.72, 0.82, 0.95), "fin": Color(0.6, 0.7, 0.85), "len": 0.22, "pts": 5, "pull": 0.2, "kg": [0.05, 0.2], "speed": 1.3, "notice": 4.5, "spawn": 26, "shoal": 3, "when": 0, "hint": "everywhere!"},
	{"name": "Stripy Perch", "col": Color(0.55, 0.75, 0.25), "fin": Color(1.0, 0.45, 0.2), "len": 0.32, "pts": 10, "pull": 0.4, "kg": [0.2, 0.8], "speed": 1.1, "notice": 4.0, "spawn": 22, "shoal": 2, "when": 0, "hint": "in little gangs"},
	{"name": "Rainbow Trout", "col": Color(0.62, 0.66, 0.45), "fin": Color(0.85, 0.6, 0.55), "len": 0.42, "pts": 20, "pull": 0.55, "kg": [0.6, 2.0], "speed": 1.2, "notice": 3.5, "spawn": 15, "shoal": 1, "when": 0, "hint": "anywhere"},
	{"name": "Lazy Catfish", "col": Color(0.45, 0.4, 0.35), "fin": Color(0.35, 0.3, 0.27), "len": 0.55, "pts": 30, "pull": 0.65, "kg": [2.0, 6.0], "speed": 0.7, "notice": 3.0, "spawn": 9, "shoal": 1, "when": 0, "hint": "slow and sleepy"},
	{"name": "BIG PIKE", "col": Color(0.4, 0.55, 0.3), "fin": Color(0.6, 0.45, 0.25), "len": 0.8, "pts": 45, "pull": 0.85, "kg": [3.0, 9.0], "speed": 1.4, "notice": 3.0, "spawn": 6, "shoal": 1, "when": 0, "thin": 0.2, "tall": 0.28, "hint": "a fast hunter"},
	{"name": "GOLDEN FISH", "col": Color(1.0, 0.8, 0.15), "fin": Color(1.0, 0.6, 0.1), "len": 0.45, "pts": 100, "pull": 0.9, "kg": [1.0, 3.0], "speed": 1.6, "notice": 4.0, "spawn": 0, "shoal": 1, "when": 4, "hint": "messages in bottles..."},
	{"name": "Old Boot", "col": Color(0.4, 0.27, 0.15), "len": 0.3, "pts": 2, "pull": 0.15, "kg": [0.5, 0.9], "speed": 0.0, "notice": 0.0, "spawn": 0, "shoal": 1, "junk": true, "when": 4},
	{"name": "TREASURE CHEST", "col": Color(0.6, 0.38, 0.18), "len": 0.45, "pts": 60, "pull": 0.35, "kg": [8.0, 15.0], "speed": 0.0, "notice": 0.0, "spawn": 0, "shoal": 1, "junk": true, "when": 4},
	{"name": "Sunny Bluegill", "col": Color(0.25, 0.45, 0.85), "fin": Color(0.3, 0.5, 0.9), "len": 0.26, "pts": 8, "pull": 0.3, "kg": [0.1, 0.4], "speed": 1.2, "notice": 4.5, "spawn": 20, "shoal": 3, "when": 1, "thin": 0.28, "tall": 0.6, "hint": "loves sunshine"},
	{"name": "Wiggly Eel", "col": Color(0.35, 0.42, 0.25), "fin": Color(0.5, 0.55, 0.3), "len": 0.9, "pts": 25, "pull": 0.6, "kg": [0.8, 2.5], "speed": 1.0, "notice": 4.0, "spawn": 16, "shoal": 1, "when": 2, "thin": 0.11, "tall": 0.13, "hint": "only in the rain"},
	{"name": "Bubble Puffer", "col": Color(0.95, 0.8, 0.45), "fin": Color(0.9, 0.55, 0.3), "len": 0.3, "pts": 35, "pull": 0.5, "kg": [0.3, 1.0], "speed": 0.8, "notice": 3.5, "spawn": 5, "shoal": 1, "when": 0, "thin": 0.7, "tall": 0.72, "hint": "rare and round"},
	{"name": "Moonfish", "col": Color(0.6, 0.85, 1.0), "fin": Color(0.75, 0.9, 1.0), "len": 0.4, "pts": 40, "pull": 0.6, "kg": [0.8, 2.2], "speed": 1.1, "notice": 5.0, "spawn": 16, "shoal": 2, "when": 3, "thin": 0.22, "tall": 0.75, "hint": "glows under the stars"},
	{"name": "Spotted Koi", "col": Color(1.0, 0.97, 0.92), "fin": Color(1.0, 0.85, 0.75), "len": 0.5, "pts": 60, "pull": 0.6, "kg": [1.5, 4.0], "speed": 0.9, "notice": 3.5, "spawn": 3, "shoal": 1, "when": 0, "hint": "very rare and fancy"},
	{"name": "OLD WHISKERS", "col": Color(0.25, 0.3, 0.4), "fin": Color(0.2, 0.24, 0.32), "len": 1.6, "pts": 300, "pull": 1.0, "kg": [25.0, 40.0], "speed": 0.8, "notice": 6.0, "spawn": 0, "shoal": 1, "when": 4, "thin": 0.3, "tall": 0.34, "hint": "the lake legend!"},
]

var main
var slot := 0
var kind := -1  # -1: empty slot
var ghost := false
var state := "swim"  # swim, approach, nibble, bite, hooked, flee, landed
var state_t := 0.0
var nibble_time := 1.5
var vel := Vector3.ZERO
var wander := Vector3.ZERO
var shoal := -1
var depth := -0.4
var weight := 1.0
var called_t := 0.0
var called_by := -1
var herded_by := -1
var herded_t := 0.0
var flee_from := Vector3.ZERO
var wiggle := 0.0
var pirate := false  # host: the treasure-map chest
var helpers: Array[int] = []  # host: boats that splashed to help land it
var puff := 0.0

var net_pos := Vector3.ZERO
var net_yaw := 0.0
var net_flags := 0

var built_kind := -2
var body: Node3D
var body_mesh: MeshInstance3D
var tail: MeshInstance3D
var icon: Label3D


func info() -> Dictionary:
	return TYPES[maxi(kind, 0)]


func is_junk() -> bool:
	return kind >= 0 and bool(info().get("junk", false))


func free_to_bite() -> bool:
	return kind >= 0 and not is_junk() and (state == "swim" or state == "flee")


static func is_species(k: int) -> bool:
	return k >= 0 and k < TYPES.size() and not bool((TYPES[k] as Dictionary).get("junk", false))


## Fill this slot with a new fish (host).
func spawn(k: int, pos: Vector3, shoal_id: int) -> void:
	kind = k
	shoal = shoal_id
	var d := info()
	var kg: Array = d["kg"]
	weight = snappedf(randf_range(float(kg[0]), float(kg[1])), 0.01)
	depth = -0.25 - float(d["len"]) * 0.45
	if k == LEGEND:
		depth = -0.5  # shallow, so everyone can see the giant shadow
	state = "swim"
	state_t = 0.0
	called_t = 0.0
	called_by = -1
	herded_by = -1
	herded_t = 0.0
	pirate = false
	helpers.clear()
	puff = 0.0
	position = pos
	position.y = depth
	vel = Vector3.ZERO
	wander = pos
	_rebuild()
	visible = true


func clear() -> void:
	kind = -1
	state = "swim"
	visible = false
	called_t = 0.0
	pirate = false


func set_state(s: String) -> void:
	state = s
	state_t = 0.0


# --- Looks -------------------------------------------------------------------------

func _rebuild() -> void:
	if built_kind == kind:
		return
	built_kind = kind
	if body != null:
		body.queue_free()
	body = Node3D.new()
	add_child(body)
	body_mesh = null
	tail = null
	if kind < 0:
		return
	var d := info()
	var col: Color = d["col"]
	var l: float = d["len"]
	var mat: StandardMaterial3D = main.make_material(col, 0.0)
	if kind == BOOT:
		var leg := MeshInstance3D.new()
		leg.mesh = main.box_mesh(Vector3(0.12, 0.22, 0.12))
		leg.material_override = mat
		leg.position = Vector3(0, 0.08, -0.05)
		body.add_child(leg)
		var foot := MeshInstance3D.new()
		foot.mesh = main.box_mesh(Vector3(0.12, 0.08, 0.26))
		foot.material_override = mat
		foot.position = Vector3(0, -0.04, 0.03)
		body.add_child(foot)
		return
	if kind == CHEST:
		var box := MeshInstance3D.new()
		box.mesh = main.box_mesh(Vector3(0.45, 0.28, 0.3))
		box.material_override = mat
		body.add_child(box)
		var band := MeshInstance3D.new()
		band.mesh = main.box_mesh(Vector3(0.47, 0.06, 0.32))
		band.material_override = main.make_material(Color(1.0, 0.8, 0.2), 0.6)
		band.position = Vector3(0, 0.06, 0)
		body.add_child(band)
		return
	body_mesh = MeshInstance3D.new()
	body_mesh.mesh = main.fish_mesh(kind)
	body_mesh.material_override = main.fish_material(kind)
	body.add_child(body_mesh)
	tail = MeshInstance3D.new()
	var pm := PrismMesh.new()
	var thin: float = d.get("thin", 0.32)
	pm.size = Vector3(l * (0.3 if kind == EEL else 0.45), l * (0.2 if kind == EEL else 0.35), 0.02)
	tail.mesh = pm
	var fin_col: Color = d.get("fin", col)
	var glow := 0.0
	if kind == GOLDEN or kind == MOONFISH:
		glow = 0.8
	tail.material_override = main.make_material(fin_col, glow)
	tail.rotation = Vector3(deg_to_rad(90.0), 0.0, deg_to_rad(90.0))
	tail.position = Vector3(0, 0, -l * 0.52)
	body.add_child(tail)
	if kind == LEGEND:
		# Glowing eyes so the legend's shadow looks back at you from under the water.
		for s in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			eye.mesh = main.sphere_mesh(0.06)
			eye.material_override = main.make_material(Color(1.0, 0.9, 0.3), 2.5)
			eye.position = Vector3(s * l * thin * 0.42, l * 0.07, l * 0.36)
			body.add_child(eye)


## One vertex-coloured mesh for a fish kind: body with belly shading and markings, fins, eyes, and
## extras (whiskers, spikes). +Z is the nose.
static func build_mesh(k: int) -> ArrayMesh:
	var d: Dictionary = TYPES[k]
	var l: float = d["len"]
	var thin: float = d.get("thin", 0.32)
	var tall: float = d.get("tall", 0.4)
	var r := Vector3(l * thin * 0.5, l * tall * 0.5, l * 0.5)
	var fin_col: Color = d.get("fin", d["col"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 12 if l > 0.5 else 10
	_ellipsoid(st, Vector3.ZERO, r, k, seg, 7, Color(0, 0, 0, 0))
	if k == PIKE:  # long duck-bill snout
		_ellipsoid(st, Vector3(0, -r.y * 0.1, r.z * 0.85), Vector3(r.x * 0.55, r.y * 0.35, r.z * 0.4), k, 8, 4, Color(0, 0, 0, 0))
	# Dorsal fin (spiky for perch and bluegill), belly fin and two side fins.
	var top := r.y * 0.85
	if k == EEL:
		_fin(st, Vector3(0, top, r.z * 0.4), Vector3(0, top, -r.z * 0.9), Vector3(0, top + r.y * 0.9, -r.z * 0.3), fin_col)
	elif k == PERCH or k == BLUEGILL:
		for i in 3:
			var z0 := r.z * (0.35 - i * 0.28)
			_fin(st, Vector3(0, top, z0), Vector3(0, top, z0 - r.z * 0.3), Vector3(0, top + r.y * 0.8, z0 - r.z * 0.05), fin_col)
	elif k != PUFFER:
		var back := -0.45 if k == PIKE else 0.15
		_fin(st, Vector3(0, top, r.z * (back + 0.25)), Vector3(0, top * 0.9, r.z * (back - 0.45)), Vector3(0, top + r.y * 0.75, r.z * (back - 0.3)), fin_col)
	_fin(st, Vector3(0, -top, r.z * -0.1), Vector3(0, -top * 0.9, r.z * -0.5), Vector3(0, -top - r.y * 0.45, r.z * -0.45), fin_col)
	for s in [-1.0, 1.0]:
		var sx: float = s
		var base := Vector3(sx * r.x * 0.8, -r.y * 0.2, r.z * 0.3)
		_fin(st, base, base + Vector3(0, 0, -r.z * 0.25), base + Vector3(sx * r.x * 0.9, -r.y * 0.3, -r.z * 0.3), fin_col)
	# Eyes: white with a dark pupil (big ones on the moonfish, so it looks surprised).
	var er := l * (0.085 if k == MOONFISH else (0.04 if k == LEGEND else 0.06))
	if k == EEL:
		er = l * 0.025
	for s in [-1.0, 1.0]:
		var sx: float = s
		var ec := Vector3(sx * r.x * 0.72, r.y * 0.28, r.z * 0.62)
		if k == PIKE:
			ec.z = r.z * 0.55
		_ellipsoid(st, ec, Vector3(er * 0.6, er, er), -1, 8, 4, Color(1, 1, 1))
		_ellipsoid(st, ec + Vector3(sx * er * 0.45, 0.0, er * 0.25), Vector3(er * 0.35, er * 0.6, er * 0.6), -1, 6, 3, Color(0.05, 0.05, 0.08))
	# Whiskers on the catfish and the legend.
	if k == CATFISH or k == LEGEND:
		var wc := Color(0.15, 0.13, 0.12)
		for s in [-1.0, 1.0]:
			var sx: float = s
			for j in 2:
				var root := Vector3(sx * r.x * 0.3, -r.y * (0.1 + 0.25 * j), r.z * 0.92)
				var tip := root + Vector3(sx * l * (0.35 - 0.1 * j), -l * 0.08 * j, -l * 0.12)
				_fin(st, root, root + Vector3(0, l * 0.015, 0), tip, wc)
	# Little spikes on the puffer.
	if k == PUFFER:
		for i in 14:
			var a := float(i) * 2.399
			var y := 1.0 - 2.0 * (float(i) + 0.5) / 14.0
			var rr := sqrt(maxf(0.0, 1.0 - y * y))
			var n := Vector3(cos(a) * rr, y, sin(a) * rr)
			var p := n * r * 0.95
			var side := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized() * l * 0.025
			_fin(st, p - side, p + side, p + n * l * 0.12, fin_col.darkened(0.2))
	st.index()
	return st.commit()


static func _skin(k: int, u: Vector3) -> Color:
	var d: Dictionary = TYPES[k]
	var col: Color = d["col"]
	var belly := col.lightened(0.5)
	var back := col.darkened(0.3)
	var c := back.lerp(belly, clampf(0.5 - u.y * 0.7, 0.0, 1.0))
	var h := absf(sin(u.x * 41.0 + u.y * 17.0 + u.z * 29.0) * 43758.5453)
	h = h - floorf(h)
	match k:
		MINNOW:
			if absf(u.y) < 0.12 and u.z < 0.6:
				c = col.darkened(0.45)
		PERCH:
			if u.y > -0.35 and sin(u.z * 15.0) > 0.35:
				c = Color(0.18, 0.25, 0.1)
		TROUT:
			if absf(u.y + 0.05) < 0.28:
				c = Color(1.0, 0.45, 0.55)
			elif u.y > 0.2 and h > 0.82:
				c = Color(0.15, 0.15, 0.12)
		CATFISH, LEGEND:
			if u.y > 0.0 and h > 0.88:
				c = col.darkened(0.5)
		PIKE:
			if u.y > -0.3 and h > 0.72:
				c = Color(0.85, 0.9, 0.55)
		GOLDEN:
			c = col.lerp(Color(1.0, 0.98, 0.7), clampf(-u.y, 0.0, 1.0))
		BLUEGILL:
			if u.y < -0.15:
				c = Color(1.0, 0.6, 0.15)
			if u.z > 0.35 and u.z < 0.55 and absf(u.y - 0.1) < 0.18:
				c = Color(0.05, 0.08, 0.2)  # the "ear" spot
		EEL:
			if u.y < -0.3:
				c = Color(0.85, 0.8, 0.45)
		PUFFER:
			if u.y > -0.2 and h > 0.75:
				c = Color(0.4, 0.3, 0.15)
		MOONFISH:
			c = Color(0.65, 0.9, 1.0).lerp(Color(1.0, 1.0, 1.0), clampf(-u.y, 0.0, 1.0))
			if sin(u.z * 9.0) > 0.7 and u.y > 0.0:
				c = Color(0.4, 0.7, 1.0)
		KOI:
			var patch := sin(u.x * 5.0 + 1.3) * sin(u.z * 6.5) + sin(u.y * 4.0 + u.z * 3.0) * 0.6
			if patch > 0.35:
				c = Color(1.0, 0.4, 0.1)
			elif patch < -0.75:
				c = Color(0.1, 0.1, 0.1)
	return c


## Ellipsoid with poles at the nose and tail; colour from _skin (k >= 0) or a flat colour.
static func _ellipsoid(st: SurfaceTool, c: Vector3, r: Vector3, k: int, seg: int, rings: int, flat: Color) -> void:
	for i in rings:
		var v0 := PI * float(i) / rings
		var v1 := PI * float(i + 1) / rings
		for j in seg:
			var u0 := TAU * float(j) / seg
			var u1 := TAU * float(j + 1) / seg
			var us: Array[Vector3] = [_unit(v0, u0), _unit(v1, u0), _unit(v1, u1), _unit(v0, u1)]
			var ps: Array[Vector3] = []
			var ns: Array[Vector3] = []
			var cs: Array[Color] = []
			for un in us:
				ps.append(c + un * r)
				ns.append(Vector3(un.x / maxf(r.x, 0.001), un.y / maxf(r.y, 0.001), un.z / maxf(r.z, 0.001)).normalized())
				cs.append(flat if flat.a > 0.0 else _skin(k, un))
			_tri(st, ps[0], ps[1], ps[2], ns[0], ns[1], ns[2], cs[0], cs[1], cs[2])
			_tri(st, ps[0], ps[2], ps[3], ns[0], ns[2], ns[3], cs[0], cs[2], cs[3])


static func _unit(v: float, u: float) -> Vector3:
	return Vector3(sin(v) * cos(u), sin(v) * sin(u), cos(v))


## A triangle wound so its front faces along the given normals (Godot: clockwise from the front).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var face := (b - a).cross(c - a)
	if face.length_squared() < 1e-14:
		return
	if face.dot(na + nb + nc) > 0.0:
		var tb := b
		b = c
		c = tb
		var tn := nb
		nb = nc
		nc = tn
		var tc := cb
		cb = cc
		cc = tc
	for v in [[a, na, ca], [b, nb, cb], [c, nc, cc]]:
		var vv: Array = v
		st.set_color(vv[2])
		st.set_normal(vv[1])
		st.add_vertex(vv[0])


## A thin fin: the same triangle from both sides.
static func _fin(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	_tri(st, a, b, c, n, n, n, col, col, col)
	_tri(st, a, c, b, -n, -n, -n, col, col, col)


func _update_icon() -> void:
	var legend := kind == LEGEND
	var show := (called_t > 0.0 or legend) and kind >= 0 and state != "landed"
	if show and icon == null:
		icon = Label3D.new()
		icon.font_size = 96
		icon.pixel_size = 0.012
		icon.outline_size = 24
		icon.modulate = Color(1.0, 0.9, 0.2)
		icon.no_depth_test = false
		icon.render_priority = 4
		add_child(icon)
	if icon != null:
		icon.visible = show
		if show:
			if legend:
				icon.text = "OLD WHISKERS" if called_t <= 0.0 else "!! OLD WHISKERS !!"
				icon.modulate = Color(0.75, 0.9, 1.0) if called_t <= 0.0 else Color(1.0, 0.9, 0.2)
			else:
				icon.text = "!! %s !!" % str(info()["name"]).to_upper() if kind >= TROUT else "!! FISH !!"
				icon.modulate = Color(1.0, 0.9, 0.2)
			icon.global_position = global_position + Vector3(0, (2.4 if legend else 1.6) + 0.15 * sin(wiggle * 2.0), 0)
			main.face_label(icon)


func _process(delta: float) -> void:
	if kind < 0:
		visible = false
		return
	if ghost:
		_ghost_follow(delta)
	wiggle += delta * (4.0 + vel.length() * 6.0)
	var fighting := state == "hooked" or state == "landed"
	if tail != null:
		var amp := 0.5 if fighting else 0.25
		tail.rotation.y = sin(wiggle * 2.2) * amp
		body.rotation.y = sin(wiggle * 2.2 + 1.5) * amp * (0.45 if kind == EEL else 0.25)
	if state == "landed" and body != null:
		body.rotation.z = sin(wiggle * 3.0) * 0.6
	elif body != null:
		body.rotation.z = 0.0
	# The puffer blows itself up like a balloon when it's caught.
	if kind == PUFFER and body != null:
		puff = move_toward(puff, 1.0 if fighting else 0.0, delta * 2.5)
		body.scale = Vector3.ONE * (1.0 + 0.6 * puff)
	if called_t > 0.0:
		called_t -= delta
	_update_icon()


func _ghost_follow(delta: float) -> void:
	if position.distance_to(net_pos) > 4.0:
		position = net_pos
	else:
		position = position.lerp(net_pos, 1.0 - exp(-10.0 * delta))
	rotation.y = lerp_angle(rotation.y, net_yaw, 1.0 - exp(-10.0 * delta))
	called_t = 1.0 if net_flags & 1 else 0.0
	if net_flags & 2:
		state = "hooked"
	elif net_flags & 4:
		state = "landed"
	else:
		state = "swim"


# --- Host AI -------------------------------------------------------------------------

func sim(delta: float) -> void:
	if kind < 0 or ghost:
		return
	state_t += delta
	if herded_t > 0.0:
		herded_t -= delta
		if herded_t <= 0.0:
			herded_by = -1
	if state == "hooked" or state == "landed":
		return  # the angler moves us
	var d := info()
	var speed: float = d["speed"]
	var want := Vector3.ZERO
	var lure: Vector3 = main.lure_position()
	var lure_wet: bool = main.lure_in_water()
	match state:
		"swim":
			if Vector2(position.x - wander.x, position.z - wander.z).length() < 1.0 or state_t > 9.0:
				_pick_wander()
			want = _flat(wander - position).normalized() * speed * 0.6
		"flee":
			want = _flat(position - flee_from).normalized() * speed * 2.2
			if state_t > 2.2:
				set_state("swim")
				_pick_wander()
		"approach":
			if not lure_wet:
				set_state("swim")
			else:
				var to := _flat(lure - position)
				want = to.normalized() * clampf(to.length() * 0.35, maxf(speed, 0.9), 3.0) * (1.4 if called_t > 0.0 else 1.0)
				if to.length() < 0.45 + (0.6 if kind == LEGEND else 0.0):
					set_state("nibble")
					nibble_time = randf_range(1.0, 2.6) * main.nibble_factor()
					main.on_fish_nibble(self)
		"nibble":
			if not lure_wet:
				set_state("swim")
			else:
				var ang := state_t * 2.5
				var around := lure + Vector3(cos(ang), 0, sin(ang)) * (0.3 if kind != LEGEND else 0.8)
				want = _flat(around - position) * 3.0
				if state_t > nibble_time:
					set_state("bite")
					main.on_fish_bite(self)
		"bite":
			want = _flat(lure - position) * 4.0
	# Boats scare fish: they swim away from any boat that comes close (that's how you herd them).
	# The legend is too big to be scared.
	if (state == "swim" or state == "approach" or state == "flee") and kind != LEGEND:
		for b in main.active_boats():
			var away := _flat(position - b.global_position)
			var dist := away.length()
			if dist < 3.2 and dist > 0.01:
				want += away / dist * (3.2 - dist) * (0.4 if state == "approach" else 1.3)
				herded_by = b.index
				herded_t = 8.0
	vel = vel.move_toward(want, 2.5 * delta)
	position += vel * delta
	_keep_in_lake()
	position.y = lerpf(position.y, depth * (0.5 if state == "nibble" or state == "bite" else 1.0), 1.0 - exp(-2.0 * delta))
	if vel.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(vel.x, vel.z), 1.0 - exp(-6.0 * delta))


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _pick_wander() -> void:
	state_t = 0.0
	# Shoals share a target so they swim together.
	if shoal >= 0:
		for f in main.fish:
			if f != self and f.kind >= 0 and f.shoal == shoal and f.state == "swim" and f.wander != Vector3.ZERO and randf() < 0.8:
				wander = f.wander + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
				return
	# The legend cruises where the angler can reach him with a cast.
	if kind == LEGEND:
		wander = main._castable_point(8.0, 16.0)
		return
	# A fish frenzy pulls nearby fish into the bubbles.
	if main.frenzy_t > 0.0 and _flat(position - main.frenzy_pos).length() < 12.0 and randf() < 0.7:
		wander = main.frenzy_pos + Vector3(randf_range(-2.5, 2.5), 0.0, randf_range(-2.5, 2.5))
		return
	var a := randf() * TAU
	var r := sqrt(randf()) * (Lake.LAKE_R - 3.0)
	wander = Lake.LAKE_C + Vector3(sin(a) * r, 0.0, cos(a) * r)
	if wander.z > Lake.JETTY_END_Z - 1.0:
		wander.z = Lake.JETTY_END_Z - 1.0 - randf() * 4.0


func _keep_in_lake() -> void:
	var off := _flat(position - Lake.LAKE_C)
	var lim := Lake.LAKE_R - 1.5
	if off.length() > lim:
		position = Lake.LAKE_C + off.normalized() * lim + Vector3(0, position.y, 0)
		vel *= 0.3
	# Not under the jetty.
	if position.z > Lake.JETTY_END_Z - 0.6 and absf(position.x) < 1.6:
		position.z = Lake.JETTY_END_Z - 0.6


## Scare this fish away from a point (boat splash, missed bite).
func scare(from: Vector3, by: int) -> void:
	if state == "hooked" or state == "landed" or kind < 0:
		return
	if state == "nibble" or state == "bite" or state == "approach":
		main.on_fish_scared(self)
	flee_from = from
	set_state("flee")
	if by > 0:
		herded_by = by
		herded_t = 8.0
