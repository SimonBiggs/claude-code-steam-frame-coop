extends RefCounted
## Map 0 of the rotation: THE HOUSE, a new one every visit (housegen.gd lays it out from a seed; this
## builds it). Same batching rules as world.gd: everything that doesn't glow goes into one vertex-coloured
## mesh, the floors are one mesh (each room's colour + pattern in its vertex colour), and every collider is
## exactly housegen's g.solids (so the validator checked what the physics has). Furniture is drawn in each
## piece's own frame (u along the wall, v into the room). Story.THEMES tint the walls and dress the garden.
## spec: {seed, level, theme, daily} (main.gd; the host sends it to the TV and Decks).

const W := preload("res://games/hide_and_seek/world.gd")
const HouseGen := preload("res://games/hide_and_seek/housegen.gd")
const Story := preload("res://games/hide_and_seek/story.gd")

const TITLE := "THE HOUSE"
## Each room's wallpaper, floor colour and floor pattern (0 planks, 1 checker, 2 terracotta, 3 carpet,
## 4 puzzle mats, 5 little tiles, 6 lawn).
const LOOK := {
	"living": [Color(0.98, 0.86, 0.7), Color(0.72, 0.5, 0.3), 0],
	"kitchen": [Color(0.86, 0.95, 0.82), Color(0.45, 0.68, 0.62), 1],
	"hall": [Color(0.97, 0.92, 0.8), Color(0.8, 0.5, 0.35), 2],
	"bedroom": [Color(0.85, 0.86, 1.0), Color(0.5, 0.6, 0.82), 3],
	"playroom": [Color(1.0, 0.9, 0.86), Color(1.0, 0.85, 0.45), 4],
	"bathroom": [Color(0.82, 0.95, 0.97), Color(0.55, 0.75, 0.8), 5],
	"bunkroom": [Color(0.9, 0.98, 0.85), Color(0.55, 0.78, 0.55), 3],
	"study": [Color(0.95, 0.88, 0.78), Color(0.55, 0.36, 0.22), 0],
	"garden": [Color(0.85, 0.62, 0.5), Color(0.4, 0.7, 0.32), 6],
}
const OUTSIDE := Color(0.86, 0.62, 0.5)  # brick-red outside walls

const FLOOR_SHADER := """
shader_type spatial;
varying vec3 wpos;
varying vec4 col;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; col = COLOR; }
void fragment() {
	vec3 base = col.rgb;
	int pat = int(col.a * 8.0 + 0.5);
	vec3 c = base;
	if (pat == 0) {
		float plank = floor(wpos.z / 0.3);
		float o = fract(sin(plank * 12.9898) * 43758.5453);
		float seam = smoothstep(0.0, 0.04, fract(wpos.z / 0.3)) * smoothstep(0.0, 0.015, fract(wpos.x / 1.8 + o));
		c = mix(base * 0.5, base * (0.9 + 0.2 * o), seam);
	} else if (pat == 1) {
		vec2 g = floor(wpos.xz / 0.5);
		c = mix(vec3(0.95, 0.93, 0.86), base, mod(g.x + g.y, 2.0));
	} else if (pat == 2) {
		vec2 f = fract(wpos.xz / 0.6);
		float grout = smoothstep(0.0, 0.04, f.x) * smoothstep(0.0, 0.04, f.y);
		c = mix(base * 0.62, base, grout);
	} else if (pat == 3) {
		c = base * (0.95 + 0.05 * sin(wpos.x * 30.0) * sin(wpos.z * 30.0));
	} else if (pat == 4) {
		vec2 g = floor(wpos.xz / 0.8);
		float k = mod(g.x * 3.0 + g.y * 5.0, 4.0);
		c = k < 1.0 ? vec3(1.0, 0.6, 0.55) : (k < 2.0 ? vec3(1.0, 0.85, 0.45) : (k < 3.0 ? vec3(0.55, 0.85, 0.6) : vec3(0.55, 0.75, 1.0)));
	} else if (pat == 5) {
		vec2 f = fract(wpos.xz / 0.3);
		float grout = smoothstep(0.0, 0.06, f.x) * smoothstep(0.0, 0.06, f.y);
		c = mix(base, vec3(0.92, 0.97, 1.0), grout);
	} else {
		float stripe = step(0.5, fract(wpos.z / 1.4));
		float n = fract(sin(dot(floor(wpos.xz * 6.0), vec2(12.9898, 78.233))) * 43758.5453);
		c = mix(base * 0.9, base * 1.06, stripe) * (0.93 + 0.1 * n);
	}
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
"""


static func house(spec: Dictionary) -> Dictionary:
	return HouseGen.generate(int(spec.get("seed", 1)), spec)


static func data(spec: Dictionary = {}) -> Dictionary:
	return HouseGen.data(house(spec))


static func build(root: Node3D, spec: Dictionary = {}) -> Dictionary:
	var g := house(spec)
	var th := Story.theme(int(g.theme))
	var ctx: Dictionary = W.new_ctx(root)
	W.environment_for(root, th.sky, Color(1.0, 0.9, 0.78), 0.5 if th.id == "spooky" else 0.65, 0.45)
	var b: Array = g.bounds
	W._collide_box(ctx, Vector3(float(b[1]) - float(b[0]) + 2.0, 0.2, 16.0), Transform3D(Basis(), Vector3((float(b[0]) + float(b[1])) / 2.0, -0.1, 0)))
	for s in g.solids:
		W._collide_box(ctx, s[1], Transform3D(Basis(), s[0]))
	_floors(root, g, th)
	_walls(ctx, g, th)
	var xs: Array = g.xs
	var hx0: float = xs[0]
	var hx1: float = xs[-1]
	W.box(ctx, Vector3(hx1 - hx0 + 0.4, 0.1, HouseGen.HALF_Z * 2.0 + 0.4), Vector3((hx0 + hx1) / 2.0, HouseGen.WALL_H + 0.05, 0), Color(0.98, 0.96, 0.92))
	for wd in g.windows:
		W.window_at(ctx, wd[0], wd[1], Color(1.0, 1.0, 0.97))
	# The front door the seeker faces while counting, with a rug.
	var fd: Vector3 = g.front_door
	W.box(ctx, Vector3(1.0, 2.1, 0.06), Vector3(fd.x, 1.05, HouseGen.HALF_Z - 0.11), Color(0.55, 0.33, 0.2), false)
	W.ball(ctx, 0.05, Vector3(fd.x + 0.35, 1.0, HouseGen.HALF_Z - 0.16), Color(1.0, 0.85, 0.3), 1.0, 0.5)
	W.box(ctx, Vector3(1.6, 0.02, 1.0), Vector3(fd.x, 0.01, HouseGen.HALF_Z - 1.0), Color(0.85, 0.35, 0.3), false)
	W.jail_at(ctx, g.jail, g.bell, Color(0.95, 0.75, 0.3), Color(1.0, 0.45, 0.45))
	for pc in g.pieces:
		_piece(ctx, pc, th)
	_garden(root, ctx, g, th)
	var lamps: Array = []
	for rm in g.rooms_info:
		if rm.type != "garden":
			var c: Vector2 = (rm.rect as Rect2).get_center()
			lamps.append(Vector3(c.x, 2.3, c.y))
			W.cyl(ctx, 0.02, 0.02, 0.3, Vector3(c.x, HouseGen.WALL_H - 0.15, c.y), Color(0.4, 0.35, 0.3), false)
			W.ball(ctx, 0.2, Vector3(c.x, HouseGen.WALL_H - 0.38, c.y), Color(1.0, 0.9, 0.7), 1.0, 2.0)
	var lights: Array = W.omni_lights(root, lamps, Color(1.0, 0.85, 0.65) if th.id != "spooky" else Color(0.9, 0.7, 1.0), 1.1, 6.5)
	var decoys: Array = W.finish(ctx, g.decoys)
	var kennel := Vector3.ZERO
	for pc in g.pieces:
		if pc.k == "kennel":
			kennel = HouseGen.to_world(pc, Vector3(0, 0, 1.3))
	return {"decoys": decoys, "lights": lights, "window_mat": W.window_mat(ctx), "kennel": kennel}


## Pip's toys in front of his kennel (one merged mesh; main.gd rebuilds it when a toy comes home).
static func toys_node(spec: Dictionary, count: int) -> Node3D:
	var root := Node3D.new()
	root.name = "PipToys"
	var g := house(spec)
	var kn := {}
	for pc in g.pieces:
		if pc.k == "kennel":
			kn = pc
	if kn.is_empty() or count <= 0:
		return root
	var ctx := {"tools": {}, "mats": {}, "main": root}
	for i in mini(count, Story.MAX_TOYS_SHOWN):
		var u := -0.45 + (i % 4) * 0.3 + (0.12 if (i / 4) % 2 == 1 else 0.0)
		var v := 1.15 + (i / 4) * 0.16
		var y := 0.0 if i < 8 else 0.08 * ((i - 8) / 4 + 1)
		var at := HouseGen.to_world(kn, Vector3(u, y, v))
		_toy(ctx, i, at)
	W._commit(ctx)
	return root


static func _toy(ctx: Dictionary, i: int, at: Vector3) -> void:
	var t: Array = Story.toy(i)
	var c: Color = t[1]
	match String(t[0]):
		"BALL":
			W.ball(ctx, 0.09, at + Vector3(0, 0.09, 0), c)
		"BONE":
			W.box(ctx, Vector3(0.2, 0.05, 0.05), at + Vector3(0, 0.04, 0), c, false, float(i))
			for s in [-0.1, 0.1]:
				W.ball(ctx, 0.04, at + Vector3(s, 0.04, 0.0).rotated(Vector3.UP, float(i)), c)
		"DUCK":
			W.ball(ctx, 0.08, at + Vector3(0, 0.07, 0), c, 0.8)
			W.ball(ctx, 0.05, at + Vector3(0.06, 0.15, 0), c)
			W.box(ctx, Vector3(0.05, 0.02, 0.03), at + Vector3(0.12, 0.15, 0), Color(1.0, 0.5, 0.1), false)
		"FRISBEE":
			W.cyl(ctx, 0.12, 0.1, 0.03, at + Vector3(0, 0.02, 0), c, false)
		"ROPE":
			W.cyl(ctx, 0.03, 0.03, 0.26, at + Vector3(0, 0.13, 0), c, false)
			W.ball(ctx, 0.05, at + Vector3(0, 0.27, 0), c.lightened(0.3))
		"SLIPPER":
			W.box(ctx, Vector3(0.1, 0.06, 0.22), at + Vector3(0, 0.03, 0), c, false, float(i))
			W.ball(ctx, 0.04, at + Vector3(0, 0.08, 0.02), Color(1, 1, 1))
		"CARROT":
			W.cyl(ctx, 0.0, 0.05, 0.2, at + Vector3(0, 0.1, 0), c, false)
			W.ball(ctx, 0.03, at + Vector3(0, 0.21, 0), Color(0.3, 0.8, 0.3))
		"STAR":
			W.ball(ctx, 0.07, at + Vector3(0, 0.08, 0), c, 1.0, 0.6)
		"TEDDY":
			W.ball(ctx, 0.08, at + Vector3(0, 0.08, 0), c)
			W.ball(ctx, 0.06, at + Vector3(0, 0.2, 0), c)
		_:
			W.cyl(ctx, 0.1, 0.1, 0.04, at + Vector3(0, 0.02, 0), c, false)


# --- Floors and walls ------------------------------------------------------------

static func _tint(c: Color, th: Dictionary) -> Color:
	return c.lerp(th.tint, float(th.mix))


static func _floors(root: Node3D, g: Dictionary, th: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rm in g.rooms_info:
		var look: Array = LOOK[rm.type]
		var c: Color = th.ground if rm.type == "garden" else look[1]
		var pat := 6 if rm.type == "garden" else int(look[2])
		var rc: Rect2 = rm.rect
		var y := 0.0 if rm.type == "garden" else 0.002
		st.set_color(Color(c.r, c.g, c.b, pat / 8.0))
		st.set_normal(Vector3.UP)
		var p0 := Vector3(rc.position.x, y, rc.position.y)
		var p1 := Vector3(rc.end.x, y, rc.position.y)
		var p2 := Vector3(rc.end.x, y, rc.end.y)
		var p3 := Vector3(rc.position.x, y, rc.end.y)
		for p in [p0, p1, p2, p0, p2, p3]:
			st.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = FLOOR_SHADER
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Each wall is two half-thick slabs, each in the wallpaper of the room it faces (the colliders are separate).
static func _walls(ctx: Dictionary, g: Dictionary, th: Dictionary) -> void:
	var rooms: Array = g.rooms_info
	var t := HouseGen.WALL_T
	for w in g.walls:
		var cols: Array = []
		for si in w.sides:
			var i := int(si)
			cols.append(OUTSIDE if i < 0 or rooms[i].type == "garden" else _tint((LOOK[rooms[i].type] as Array)[0], th))
		var a := float(w.a) - t / 2.0
		var cuts: Array = (w.doors as Array).duplicate()
		cuts.sort()
		var spans: Array = []
		for dc in cuts:
			if float(dc) - HouseGen.DOOR_W / 2.0 > a:
				spans.append([a, float(dc) - HouseGen.DOOR_W / 2.0, 0.0])
			spans.append([float(dc) - HouseGen.DOOR_W / 2.0, float(dc) + HouseGen.DOOR_W / 2.0, HouseGen.DOOR_H])
			a = float(dc) + HouseGen.DOOR_W / 2.0
		spans.append([a, float(w.b) + t / 2.0, 0.0])
		for sp in spans:
			var mid := (float(sp[0]) + float(sp[1])) / 2.0
			var len := float(sp[1]) - float(sp[0])
			var y0 := float(sp[2])
			var h := HouseGen.WALL_H - y0
			for side in 2:
				var off := (-t / 4.0) if side == 0 else (t / 4.0)
				var col: Color = cols[side]
				if int(w.axis) == 0:
					W.box(ctx, Vector3(len, h, t / 2.0), Vector3(mid, y0 + h / 2.0, float(w.at) + off), col, false)
				else:
					W.box(ctx, Vector3(t / 2.0, h, len), Vector3(float(w.at) + off, y0 + h / 2.0, mid), col, false)
				if y0 == 0.0 and cols[side] != OUTSIDE:  # white skirting
					if int(w.axis) == 0:
						W.box(ctx, Vector3(len, 0.12, 0.02), Vector3(mid, 0.06, float(w.at) + off * 2.0 + signf(off) * 0.01), Color(0.98, 0.98, 0.96), false)
					else:
						W.box(ctx, Vector3(0.02, 0.12, len), Vector3(float(w.at) + off * 2.0 + signf(off) * 0.01, 0.06, mid), Color(0.98, 0.98, 0.96), false)


# --- Furniture (drawn in the piece's frame) ----------------------------------------------

static func _xf(pc: Dictionary, local: Vector3, yaw: float = 0.0) -> Transform3D:
	var n: Vector3 = pc.n
	var basis := Basis(HouseGen.along(n), Vector3.UP, n)
	return Transform3D(basis, pc.o) * Transform3D(Basis(Vector3.UP, yaw), local)


static func _b(ctx: Dictionary, pc: Dictionary, c: Vector3, s: Vector3, col: Color, glow: float = 0.0) -> void:
	var bm := BoxMesh.new()
	bm.size = s
	W._add_mesh(ctx, bm, _xf(pc, c), col, glow)


static func _s(ctx: Dictionary, pc: Dictionary, c: Vector3, r: float, col: Color, squash: float = 1.0, glow: float = 0.0) -> void:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	W._add_mesh(ctx, sm, _xf(pc, c) * Transform3D(Basis().scaled(Vector3(1.0, squash, 1.0)), Vector3.ZERO), col, glow)


static func _c(ctx: Dictionary, pc: Dictionary, c: Vector3, r_top: float, r_bot: float, h: float, col: Color, glow: float = 0.0) -> void:
	W._add_mesh(ctx, W._cyl_mesh(r_top, r_bot, h), _xf(pc, c), col, glow)


## A little colour variety per piece (the same on every machine).
static func _hue(pc: Dictionary, palette: Array) -> Color:
	var o: Vector3 = pc.o
	return palette[absi(int(o.x * 7.0 + o.z * 13.0)) % palette.size()]


static func _piece(ctx: Dictionary, pc: Dictionary, th: Dictionary) -> void:
	var wood := Color(0.6, 0.42, 0.26)
	match String(pc.k):
		"sofa":
			var col := _hue(pc, [Color(0.85, 0.42, 0.45), Color(0.4, 0.6, 0.85), Color(0.55, 0.75, 0.45)])
			_b(ctx, pc, Vector3(0, 0.225, 0.55), Vector3(2.4, 0.45, 0.8), col)
			_b(ctx, pc, Vector3(0, 0.475, 0.125), Vector3(2.4, 0.95, 0.25), col.darkened(0.1))
			for s in [-1.075, 1.075]:
				_b(ctx, pc, Vector3(s, 0.325, 0.475), Vector3(0.25, 0.65, 0.95), col.darkened(0.15))
			for s in [-0.6, 0.6]:
				_b(ctx, pc, Vector3(s, 0.62, 0.33), Vector3(0.5, 0.35, 0.15), Color(1.0, 0.85, 0.5))
			_s(ctx, pc, Vector3(-0.75, 0.58, 0.6), 0.22, Color(1.0, 0.62, 0.3), 0.6)  # the family cat, asleep
			_s(ctx, pc, Vector3(-0.52, 0.6, 0.62), 0.12, Color(1.0, 0.62, 0.3))
			_b(ctx, pc, Vector3(0, 1.65, 0.03), Vector3(0.7, 0.5, 0.04), Color(0.55, 0.38, 0.22))
			_b(ctx, pc, Vector3(0, 1.65, 0.05), Vector3(0.56, 0.4, 0.02), Color(0.95, 0.75, 0.5), 0.3)
		"armchair":
			var col := _hue(pc, [Color(0.45, 0.62, 0.85), Color(0.9, 0.6, 0.3), Color(0.7, 0.5, 0.8)])
			_b(ctx, pc, Vector3(0, 0.225, 0.5), Vector3(0.95, 0.45, 0.9), col)
			_b(ctx, pc, Vector3(0, 0.5, 0.125), Vector3(0.95, 1.0, 0.25), col.darkened(0.1))
		"tv":
			_b(ctx, pc, Vector3(0, 0.25, 0.225), Vector3(1.7, 0.5, 0.45), Color(0.45, 0.32, 0.22))
			_b(ctx, pc, Vector3(0, 0.95, 0.12), Vector3(1.5, 0.9, 0.08), Color(0.12, 0.14, 0.2))
			_b(ctx, pc, Vector3(0, 0.95, 0.17), Vector3(1.35, 0.78, 0.02), Color(0.35, 0.6, 0.9), 0.8)
		"bookcase":
			_b(ctx, pc, Vector3(0, 1.0, 0.175), Vector3(1.4, 2.0, 0.35), Color(0.55, 0.38, 0.24))
			var books: Array[Color] = [Color(0.9, 0.3, 0.3), Color(0.3, 0.6, 0.9), Color(0.95, 0.8, 0.3), Color(0.4, 0.8, 0.45)]
			for shelf in 4:
				for k in 4:
					_b(ctx, pc, Vector3(-0.5 + k * 0.33, 0.25 + shelf * 0.48, 0.3), Vector3(0.26, 0.3, 0.12), books[(shelf + k) % 4])
		"coffee":
			_b(ctx, pc, Vector3(0, 0.37, 0), Vector3(1.2, 0.06, 0.7), wood)
			_b(ctx, pc, Vector3(0, 0.17, 0), Vector3(1.0, 0.34, 0.5), wood.darkened(0.2))
		"counter":
			_b(ctx, pc, Vector3(0, 0.44, 0.35), Vector3(3.0, 0.88, 0.7), Color(0.4, 0.62, 0.55))
			_b(ctx, pc, Vector3(0, 0.9, 0.37), Vector3(3.06, 0.05, 0.76), Color(0.96, 0.94, 0.88))
			_c(ctx, pc, Vector3(0.6, 0.96, 0.35), 0.18, 0.18, 0.12, Color(0.85, 0.3, 0.25))
			_b(ctx, pc, Vector3(-0.8, 0.93, 0.35), Vector3(0.6, 0.02, 0.4), Color(0.7, 0.85, 0.95))
		"fridge":
			_b(ctx, pc, Vector3(0, 1.0, 0.375), Vector3(0.8, 2.0, 0.75), Color(0.95, 0.97, 1.0))
			_b(ctx, pc, Vector3(0.3, 1.2, 0.77), Vector3(0.04, 0.5, 0.04), Color(0.6, 0.6, 0.65))
			_b(ctx, pc, Vector3(0, 1.32, 0.76), Vector3(0.8, 0.02, 0.02), Color(0.8, 0.82, 0.85))
		"stove":
			_b(ctx, pc, Vector3(0, 0.45, 0.35), Vector3(0.8, 0.9, 0.7), Color(0.3, 0.3, 0.34))
			for k in 4:
				_c(ctx, pc, Vector3(-0.18 + (k % 2) * 0.36, 0.91, 0.18 + (k / 2) * 0.34), 0.11, 0.11, 0.02, Color(0.95, 0.3, 0.2), 0.4)
			_b(ctx, pc, Vector3(0, 0.45, 0.71), Vector3(0.6, 0.4, 0.02), Color(0.15, 0.15, 0.18))
		"table":
			_b(ctx, pc, Vector3(0, 1.0, 0), Vector3(2.0, 0.08, 1.2), Color(0.72, 0.5, 0.3))
			_b(ctx, pc, Vector3(0, 1.05, 0), Vector3(2.2, 0.02, 1.5), _hue(pc, [Color(0.95, 0.5, 0.5), Color(0.5, 0.7, 1.0), Color(1.0, 0.85, 0.4)]))
			for lu in [-0.9, 0.9]:
				for lv in [-0.5, 0.5]:
					_b(ctx, pc, Vector3(lu, 0.48, lv), Vector3(0.1, 0.96, 0.1), Color(0.6, 0.4, 0.24))
			for s in [-1.0, 1.0]:
				_b(ctx, pc, Vector3(1.35 * s, 0.25, 0), Vector3(0.5, 0.5, 0.5), Color(0.95, 0.85, 0.5))
				_b(ctx, pc, Vector3(1.57 * s, 0.8, 0), Vector3(0.06, 0.6, 0.5), Color(0.95, 0.85, 0.5))
		"bed":
			_b(ctx, pc, Vector3(0, 0.275, 1.2), Vector3(2.0, 0.55, 2.4), Color(0.95, 0.95, 1.0))
			_b(ctx, pc, Vector3(0, 0.6, 1.6), Vector3(2.04, 0.12, 1.6), _hue(pc, [Color(0.5, 0.75, 1.0), Color(1.0, 0.6, 0.7), Color(0.6, 0.9, 0.6)]))
			_b(ctx, pc, Vector3(0, 0.66, 0.4), Vector3(0.7, 0.15, 0.4), Color(1, 1, 1))
			_b(ctx, pc, Vector3(0, 0.55, 0.06), Vector3(2.0, 1.1, 0.12), Color(0.6, 0.45, 0.75))
			_b(ctx, pc, Vector3(0.8, 1.75, 0.03), Vector3(0.6, 0.45, 0.04), Color(0.55, 0.38, 0.22))
			_b(ctx, pc, Vector3(0.8, 1.75, 0.05), Vector3(0.48, 0.36, 0.02), Color(1.0, 0.8, 0.9), 0.3)
		"wardrobe":
			var wd := _hue(pc, [Color(0.7, 0.55, 0.85), Color(0.85, 0.65, 0.45), Color(0.55, 0.75, 0.7)])
			_b(ctx, pc, Vector3(0, 1.05, 0.04), Vector3(1.56, 2.1, 0.08), wd)
			for s in [-0.74, 0.74]:
				_b(ctx, pc, Vector3(s, 1.05, 0.4), Vector3(0.08, 2.1, 0.8), wd)
			_b(ctx, pc, Vector3(0, 2.13, 0.4), Vector3(1.56, 0.06, 0.8), wd)
			_b(ctx, pc, Vector3(0, 1.85, 0.4), Vector3(1.4, 0.03, 0.03), Color(0.7, 0.7, 0.75))
			for k in 3:
				_b(ctx, pc, Vector3(-0.35 + k * 0.35, 1.5, 0.35), Vector3(0.3, 0.6, 0.06), [Color(1, 0.6, 0.6), Color(0.6, 1, 0.7), Color(1, 0.9, 0.5)][k])
		"dresser":
			_b(ctx, pc, Vector3(0, 0.3, 0.25), Vector3(1.0, 0.6, 0.5), Color(0.95, 0.75, 0.55))
			for k in 2:
				_b(ctx, pc, Vector3(0, 0.18 + k * 0.25, 0.51), Vector3(0.8, 0.02, 0.02), Color(0.7, 0.5, 0.35))
			_s(ctx, pc, Vector3(0.3, 0.68, 0.25), 0.08, Color(0.4, 0.8, 0.5))
		"fort":
			_b(ctx, pc, Vector3(0, 0.6, 0.06), Vector3(2.0, 1.2, 0.12), Color(1.0, 0.75, 0.4))
			for s in [-0.94, 0.94]:
				_b(ctx, pc, Vector3(s, 0.6, 0.55), Vector3(0.12, 1.2, 1.1), Color(0.5, 0.8, 1.0))
			_b(ctx, pc, Vector3(0, 1.25, 0.55), Vector3(2.3, 0.1, 1.2), Color(1.0, 0.45, 0.5))
			_b(ctx, pc, Vector3(0, 1.45, 1.1), Vector3(0.6, 0.4, 0.04), Color(1.0, 0.95, 0.5))
			_c(ctx, pc, Vector3(0.9, 1.6, 0.3), 0.015, 0.015, 0.6, Color(0.5, 0.4, 0.3))
			_b(ctx, pc, Vector3(0.75, 1.8, 0.3), Vector3(0.28, 0.18, 0.02), Color(0.3, 0.8, 0.4))
		"ballpit":
			var pit := Color(0.4, 0.75, 0.95)
			for s in HouseGen.kind_def("ballpit").solids:
				_b(ctx, pc, s[0], s[1], pit)
			var cols: Array[Color] = [Color(1, 0.4, 0.4), Color(1, 0.85, 0.3), Color(0.4, 0.85, 0.5), Color(0.5, 0.6, 1.0)]
			var rr := RandomNumberGenerator.new()
			rr.seed = 7
			for i in 22:
				var p := Vector3(rr.randf_range(0.0, 0.85), 0.1 + rr.randf() * 0.12, rr.randf_range(-0.85, 0.85))
				_s(ctx, pc, p, 0.12, cols[i % 4])
		"beanbag":
			_s(ctx, pc, Vector3(0, 0.3, 0), 0.5, _hue(pc, [Color(0.6, 0.45, 0.9), Color(0.95, 0.55, 0.3), Color(0.3, 0.75, 0.6)]), 0.6)
		"toychest":
			_b(ctx, pc, Vector3(0, 0.25, 0.25), Vector3(1.0, 0.5, 0.5), Color(0.9, 0.35, 0.3))
			_b(ctx, pc, Vector3(0, 0.51, 0.25), Vector3(1.04, 0.04, 0.54), Color(1.0, 0.85, 0.3))
			for k in 3:
				_b(ctx, pc, Vector3(-0.3 + k * 0.3, 0.6, 0.25), Vector3(0.18, 0.18, 0.18), [Color(0.4, 0.85, 0.5), Color(0.5, 0.6, 1.0), Color(1, 0.6, 0.8)][k])
		"bathtub":
			var tub := Color(0.98, 0.98, 1.0)
			_b(ctx, pc, Vector3(0, 0.3, 0.475), Vector3(2.0, 0.6, 0.95), tub)
			_b(ctx, pc, Vector3(0, 0.61, 0.475), Vector3(1.8, 0.02, 0.75), Color(0.6, 0.85, 1.0))
			_s(ctx, pc, Vector3(0.4, 0.68, 0.5), 0.08, Color(1.0, 0.9, 0.2))
			_b(ctx, pc, Vector3(-0.3, 1.6, 0.93), Vector3(1.3, 1.9, 0.03), Color(0.6, 0.9, 0.85))
			_c(ctx, pc, Vector3(0, 2.5, 0.93), 0.015, 0.015, 2.0, Color(0.8, 0.8, 0.85))
		"toilet":
			_c(ctx, pc, Vector3(0, 0.21, 0.45), 0.22, 0.2, 0.42, Color(1, 1, 1))
			_b(ctx, pc, Vector3(0, 0.6, 0.12), Vector3(0.45, 0.55, 0.2), Color(0.95, 0.95, 1.0))
		"sink":
			_b(ctx, pc, Vector3(0, 0.425, 0.225), Vector3(0.6, 0.85, 0.45), Color(0.95, 0.95, 0.97))
			_b(ctx, pc, Vector3(0, 1.6, 0.02), Vector3(0.7, 0.8, 0.03), Color(0.75, 0.9, 1.0), 0.6)
		"bunk":
			var frame := Color(0.55, 0.75, 0.95)
			for pu in [-0.96, 0.96]:
				for pv in [0.04, 0.96]:
					_b(ctx, pc, Vector3(pu, 0.95, pv), Vector3(0.08, 1.9, 0.08), frame)
			_b(ctx, pc, Vector3(0, 0.25, 0.5), Vector3(2.0, 0.5, 1.0), Color(0.95, 0.95, 1.0))
			_b(ctx, pc, Vector3(0, 0.53, 0.55), Vector3(1.9, 0.08, 0.9), Color(1.0, 0.6, 0.4))
			_b(ctx, pc, Vector3(0, 1.4, 0.5), Vector3(2.0, 0.15, 1.0), Color(0.95, 0.95, 1.0))
			_b(ctx, pc, Vector3(0, 1.5, 0.55), Vector3(1.9, 0.08, 0.9), Color(0.4, 0.7, 1.0))
			for k in 4:
				_b(ctx, pc, Vector3(0.8, 0.3 + k * 0.35, 1.02), Vector3(0.3, 0.04, 0.04), frame.darkened(0.2))
		"desk":
			_b(ctx, pc, Vector3(0, 0.75, 0.35), Vector3(1.4, 0.06, 0.7), wood)
			_b(ctx, pc, Vector3(-0.5, 0.36, 0.35), Vector3(0.36, 0.72, 0.66), wood.darkened(0.15))
			_b(ctx, pc, Vector3(0.66, 0.36, 0.35), Vector3(0.06, 0.72, 0.66), wood.darkened(0.15))
			_c(ctx, pc, Vector3(0.4, 0.95, 0.2), 0.02, 0.02, 0.35, Color(0.3, 0.3, 0.35))
			_c(ctx, pc, Vector3(0.4, 1.1, 0.25), 0.04, 0.12, 0.12, Color(1.0, 0.85, 0.4), 0.8)
			_b(ctx, pc, Vector3(-0.2, 0.8, 0.4), Vector3(0.3, 0.05, 0.22), Color(0.3, 0.6, 0.9))
		"bench":
			_b(ctx, pc, Vector3(0, 0.4, 0.2), Vector3(1.2, 0.08, 0.4), wood)
			_b(ctx, pc, Vector3(0, 0.18, 0.2), Vector3(1.1, 0.36, 0.3), wood.darkened(0.2))
			for k in 3:
				_b(ctx, pc, Vector3(-0.35 + k * 0.35, 0.05, 0.55), Vector3(0.12, 0.1, 0.28), [Color(0.9, 0.3, 0.3), Color(0.3, 0.5, 0.9), Color(1.0, 0.8, 0.3)][k])
		"coatstand":
			_c(ctx, pc, Vector3(0, 0.9, 0.25), 0.04, 0.04, 1.8, Color(0.5, 0.35, 0.25))
			_c(ctx, pc, Vector3(0, 0.02, 0.25), 0.25, 0.25, 0.04, Color(0.5, 0.35, 0.25))
			_s(ctx, pc, Vector3(0.05, 1.5, 0.2), 0.25, Color(0.3, 0.5, 0.9), 1.4)
			_s(ctx, pc, Vector3(-0.05, 1.65, 0.35), 0.2, Color(0.95, 0.8, 0.3), 1.2)
		"shed":
			var shed := Color(0.55, 0.75, 0.6)
			for s in HouseGen.kind_def("shed").solids.slice(0, 5):
				_b(ctx, pc, s[0], s[1], shed)
			_b(ctx, pc, Vector3(0, 1.8, 2.15), Vector3(1.2, 0.4, 0.1), shed)
			_b(ctx, pc, Vector3(0, 2.06, 1.1), Vector3(2.6, 0.12, 2.7), Color(0.75, 0.35, 0.3) if th.id != "snowy" else Color(0.95, 0.97, 1.0))
			_b(ctx, pc, Vector3(0.85, 0.8, 2.5), Vector3(0.05, 1.6, 0.6), shed.darkened(0.15))
			_b(ctx, pc, Vector3(-0.55, 0.4, 0.55), Vector3(0.8, 0.8, 0.6), Color(0.7, 0.5, 0.3))
			_c(ctx, pc, Vector3(0.75, 0.45, 0.3), 0.12, 0.12, 0.9, Color(0.4, 0.4, 0.45))
		"hedge":
			var hedge := Color(0.24, 0.52, 0.26) if th.id != "snowy" else Color(0.3, 0.5, 0.35)
			_b(ctx, pc, Vector3(0, 0.5, 1.3), Vector3(2.2, 1.0, 0.6), hedge)
			for k in 3:
				_s(ctx, pc, Vector3((k - 1) * 0.66, 0.95, 1.3), 0.32, hedge.lightened(0.08) if th.id != "snowy" else Color(0.96, 0.98, 1.0), 0.8)
		"tree":
			_c(ctx, pc, Vector3(0, 1.1, 0), 0.18, 0.26, 2.2, Color(0.5, 0.33, 0.2))
			var leaf := Color(0.3, 0.62, 0.3)
			if th.id == "snowy":
				leaf = Color(0.9, 0.95, 1.0)
			elif th.id == "spooky":
				leaf = Color(0.85, 0.5, 0.2)
			_s(ctx, pc, Vector3(0, 2.7, 0), 1.0, leaf, 0.9)
			_s(ctx, pc, Vector3(0.5, 3.2, 0.2), 0.7, leaf.lightened(0.08), 0.9)
			_s(ctx, pc, Vector3(-0.6, 2.4, -0.6), 0.12, Color(1.0, 0.3, 0.3))
		"slide":
			_b(ctx, pc, Vector3(0, 0.6, 1.1), Vector3(0.7, 1.2, 0.7), Color(0.95, 0.6, 0.25))
			var tilt := Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3.ZERO)
			var chute := BoxMesh.new()
			chute.size = Vector3(0.6, 0.06, 2.3)
			W._add_mesh(ctx, chute, _xf(pc, Vector3(0, 0.62, -0.25)) * tilt, Color(0.35, 0.65, 1.0))
			var rail := BoxMesh.new()
			rail.size = Vector3(0.05, 0.15, 2.3)
			for s in [-0.32, 0.32]:
				W._add_mesh(ctx, rail, _xf(pc, Vector3(s, 0.7, -0.25)) * tilt, Color(1.0, 0.85, 0.3))
		"sandpit":
			_b(ctx, pc, Vector3(0, 0.02, 0), Vector3(1.8, 0.04, 1.8), Color(0.95, 0.85, 0.55))
			for k in 4:
				var horiz := k < 2
				var off := -0.9 if k % 2 == 0 else 0.9
				_b(ctx, pc, Vector3(0, 0.09, off) if horiz else Vector3(off, 0.09, 0), Vector3(1.9, 0.18, 0.1) if horiz else Vector3(0.1, 0.18, 1.9), Color(0.7, 0.45, 0.3))
			_c(ctx, pc, Vector3(0.3, 0.1, 0.2), 0.1, 0.08, 0.16, Color(1.0, 0.35, 0.35))
		"washline":
			for s in [-2.0, 2.0]:
				_c(ctx, pc, Vector3(0, 0.95, s), 0.04, 0.04, 1.9, Color(0.6, 0.6, 0.65))
			_b(ctx, pc, Vector3(0, 1.85, 0), Vector3(0.02, 0.02, 4.0), Color(0.9, 0.9, 0.9))
			var cloth: Array[Color] = [Color(1.0, 0.5, 0.5), Color(0.5, 0.75, 1.0), Color(1.0, 0.9, 0.4), Color(0.6, 0.9, 0.6)]
			for k in 4:
				_b(ctx, pc, Vector3(0, 1.58, -1.3 + k * 0.85), Vector3(0.03, 0.5, 0.45), cloth[k])
		"kennel":
			var red := Color(0.85, 0.3, 0.25)
			_b(ctx, pc, Vector3(0, 0.4, 0.5), Vector3(1.1, 0.8, 1.0), red)
			for s in [-1.0, 1.0]:
				W._add_mesh(ctx, _box_mesh(Vector3(0.66, 0.06, 1.1)), _xf(pc, Vector3(0.27 * s, 0.98, 0.5)) * Transform3D(Basis(Vector3.BACK, -0.65 * s), Vector3.ZERO), Color(0.45, 0.3, 0.2))
			_b(ctx, pc, Vector3(0, 0.32, 1.005), Vector3(0.5, 0.55, 0.02), Color(0.15, 0.1, 0.08))
			_b(ctx, pc, Vector3(0, 0.72, 1.01), Vector3(0.5, 0.14, 0.02), Color(1.0, 0.9, 0.5))
			_c(ctx, pc, Vector3(0.75, 0.05, 1.2), 0.15, 0.12, 0.1, Color(0.3, 0.55, 0.95))


static func _box_mesh(s: Vector3) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = s
	return bm


# --- The garden --------------------------------------------------------------------------

static func _garden(root: Node3D, ctx: Dictionary, g: Dictionary, th: Dictionary) -> void:
	var gside := int(g.gside)
	var far := float(g.gx_far)
	var xs: Array = g.xs
	var near := float(xs[0]) if gside < 0 else float(xs[-1])
	var cx := (far + near) / 2.0
	var hz := HouseGen.HALF_Z
	var picket := Color(0.98, 0.97, 0.93)
	var stripe: bool = th.id == "seaside"
	for k in 28:
		var c := picket if not stripe or k % 2 == 0 else Color(0.35, 0.6, 0.95)
		W.box(ctx, Vector3(0.06, 1.0, 0.18), Vector3(far, 0.5, -hz + 0.25 + k * 0.5), c, false)
	for k in 16:
		var x := minf(far, near) + 0.25 + k * 0.5
		var c := picket if not stripe or k % 2 == 0 else Color(0.35, 0.6, 0.95)
		W.box(ctx, Vector3(0.18, 1.0, 0.06), Vector3(x, 0.5, -hz), c, false)
		W.box(ctx, Vector3(0.18, 1.0, 0.06), Vector3(x, 0.5, hz), c, false)
	W.box(ctx, Vector3(0.05, 0.08, hz * 2.0), Vector3(far, 0.75, 0), picket, false)
	W.box(ctx, Vector3(HouseGen.GARDEN_W, 0.08, 0.05), Vector3(cx, 0.75, -hz), picket, false)
	W.box(ctx, Vector3(HouseGen.GARDEN_W, 0.08, 0.05), Vector3(cx, 0.75, hz), picket, false)
	# Doorstep and stepping stones from the garden door.
	var gd: Vector3 = g.garden_door
	W.box(ctx, Vector3(0.6, 0.03, HouseGen.DOOR_W), Vector3(near + gside * 0.3, 0.015, gd.z), Color(0.75, 0.7, 0.65), false)
	for k in 5:
		W.ball(ctx, 0.28, Vector3(near + gside * (1.0 + k * 0.9), 0.0, gd.z - 0.2 * k), Color(0.78, 0.76, 0.72), 0.12)
	# Flowers along the house wall (pumpkins in a spooky garden, shells by the sea, snowballs in the snow).
	for k in 18:
		var z := -hz + 0.5 + k * 0.75
		if absf(z - gd.z) < 1.1:
			continue
		var at := Vector3(near + gside * 0.25, 0.0, z)
		match String(th.id):
			"spooky":
				if k % 3 == 0:
					W.ball(ctx, 0.17, at + Vector3(0, 0.15, 0), Color(1.0, 0.55, 0.1), 0.8)
					W.ball(ctx, 0.05, at + Vector3(gside * 0.15, 0.2, 0), Color(1.0, 0.9, 0.3), 1.0, 2.0)
			"seaside":
				W.ball(ctx, 0.07, at + Vector3(0, 0.03, 0), [Color(1.0, 0.85, 0.75), Color(1.0, 0.6, 0.55), Color(0.95, 0.95, 0.9)][k % 3], 0.5)
			"snowy":
				W.ball(ctx, 0.14, at + Vector3(0, 0.1, 0), Color(0.97, 0.98, 1.0))
			_:
				W.ball(ctx, 0.11, at + Vector3(0, 0.32, 0), [Color(1.0, 0.45, 0.55), Color(1.0, 0.85, 0.3), Color(0.75, 0.55, 1.0)][k % 3])
				W.cyl(ctx, 0.015, 0.015, 0.3, at + Vector3(0, 0.15, 0), Color(0.3, 0.6, 0.3), false)
	# A snowman / a beach umbrella / pumpkin lanterns on the fence posts (themes).
	if th.id == "spooky":
		for k in 6:
			W.ball(ctx, 0.16, Vector3(far, 1.12, -hz + 1.0 + k * 2.4), Color(1.0, 0.55, 0.1), 0.85)
			W.ball(ctx, 0.04, Vector3(far - gside * 0.14, 1.16, -hz + 1.0 + k * 2.4), Color(1.0, 0.9, 0.3), 1.0, 2.0)
	elif th.id == "seaside":
		for k in 4:
			W.cyl(ctx, 0.18, 0.18, 0.06, Vector3(far - gside * 0.06, 0.75, -hz + 2.0 + k * 3.3), Color(1.0, 0.35, 0.3) if k % 2 == 0 else Color(1, 1, 1), false)
	elif th.id == "snowy":
		for k in 10:
			W.ball(ctx, 0.07, Vector3(far, 1.05, -hz + 0.7 + k * 1.4), Color(0.97, 0.98, 1.0))
	_fairy_lights(root, far, near, th)


## Glowing fairy lights along the fence tops (one MultiMesh; they light the garden at night).
static func _fairy_lights(root: Node3D, far: float, near: float, th: Dictionary) -> void:
	var xfs: Array[Transform3D] = []
	var hz := HouseGen.HALF_Z
	for i in 28:
		xfs.append(Transform3D(Basis(), Vector3(far, 1.0 + 0.06 * sin(i * 1.3), -hz + 0.25 + i * 0.5)))
	for i in 16:
		var x := minf(far, near) + 0.25 + i * 0.5
		xfs.append(Transform3D(Basis(), Vector3(x, 1.0 + 0.06 * sin(i * 1.7), -hz)))
		xfs.append(Transform3D(Basis(), Vector3(x, 1.0 + 0.06 * sin(i * 1.1), hz)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	sm.radial_segments = 6
	sm.rings = 3
	mm.mesh = sm
	mm.instance_count = xfs.size()
	var cols: Array[Color] = [Color(1.0, 0.5, 0.5), Color(1.0, 0.9, 0.4), Color(0.5, 0.8, 1.0), Color(0.6, 1.0, 0.6)]
	if th.id == "spooky":
		cols = [Color(1.0, 0.55, 0.1), Color(0.75, 0.45, 1.0), Color(0.5, 1.0, 0.4)]
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i % cols.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
