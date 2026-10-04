extends Node3D
## DUNGEON DELVE world builder: turns a dungeon_gen.gd Layout into 3D, cheaply.
## - Geometry is merged per 13x13-tile chunk (one mesh for floor + decorations, one for walls), so a
##   whole floor is a few dozen draw calls and far chunks are culled (visibility range in VR).
## - Lighting is BAKED into vertex colours: every torch, crystal and lava pool lights the tiles it can
##   see (line of sight on the tile grid), so rooms glow warmly with almost no real lights.
## - Walls come in two heights: tall (3.2 m) for the VR paladin (render layer 2) and short (1.05 m)
##   for the TV's top-down cameras (render layer 3), each built only where a camera needs it.
## - Dynamic pieces are separate nodes: locked gates, cracked walls, chests (with opening lids),
##   breakable pots (one MultiMesh), spike traps (MultiMesh), boulders, the stairs and the shrine.

const Gen := preload("res://games/dungeon_delve/dungeon_gen.gd")
const Data := preload("res://games/dungeon_delve/data.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Creatures := preload("res://core/creatures.gd")

const TILE := 1.5
const CHUNK := 13
const WALL_VR := 3.2
const WALL_TV := 1.05
const LAYER_WORLD := 1
const LAYER_VR := 2  ## render layer 2: only the headset (and the VR mirror) sees it
const LAYER_TV := 4  ## render layer 3: only TV cameras see it
const VR_RANGE := 46.0

var layout: Gen.Layout
var theme: Dictionary
var vr_walls := false
var tv_walls := true
var tile_light := PackedColorArray()
var corner_light := PackedColorArray()
var gates := {}  # door id -> Node3D
var cracks := {}  # door id -> Node3D
var chests := {}  # chest id -> Node3D (child "Lid")
var pots_mm: MultiMeshInstance3D
var pot_alive := PackedByteArray()
var spike_mm: MultiMeshInstance3D
var plate_mm: MultiMeshInstance3D
var spike_index := {}  # trap id -> Array[int] instance indices
var boulders := {}  # trap id -> Node3D
var stairs: Node3D
var stairs_glow: MeshInstance3D
var shrine: Node3D
var shrine_orb: MeshInstance3D
var _rng := RandomNumberGenerator.new()


## Build everything for `lay`. vr / tv: which wall sets to make.
func build(lay: Gen.Layout, vr: bool, tv: bool) -> void:
	layout = lay
	theme = Data.THEMES[lay.theme]
	vr_walls = vr
	tv_walls = tv
	_rng.seed = lay.seed_value * 31 + lay.stage
	_bake_light()
	for cy in range(0, lay.h, CHUNK):
		for cx in range(0, lay.w, CHUNK):
			_build_chunk(Rect2i(cx, cy, CHUNK, CHUNK))
	_build_doors()
	_build_chests()
	_build_pots()
	_build_traps()
	_build_stairs()
	if lay.shrine_room >= 0:
		_build_shrine()


# =================================================================================================
# Baked light
# =================================================================================================

func _bake_light() -> void:
	var lay := layout
	var amb: Color = theme["amb"]
	var lights: Array = []
	var torch: Color = theme["torch"]
	for t in lay.torches:
		var ta: Array = t
		var p: Vector3 = ta[0]
		var n: Vector3 = ta[1]
		lights.append([p + n * 0.4, torch, 0.95, 6.5])
	for l in lay.lights:
		lights.append(l)
	# bucket lights in 8x8-tile cells
	var buckets := {}
	for i in lights.size():
		var la: Array = lights[i]
		var p: Vector3 = la[0]
		var k := Vector2i(int(p.x / (TILE * 8.0)), int(p.z / (TILE * 8.0)))
		if not buckets.has(k):
			buckets[k] = []
		(buckets[k] as Array).append(i)
	tile_light.resize(lay.w * lay.h)
	tile_light.fill(amb)
	for y in lay.h:
		for x in lay.w:
			if not lay.floor_at(x, y):
				continue
			var c := lay.center(Vector2i(x, y))
			var col := amb
			var bk := Vector2i(int(c.x / (TILE * 8.0)), int(c.z / (TILE * 8.0)))
			for by in range(bk.y - 1, bk.y + 2):
				for bx in range(bk.x - 1, bk.x + 2):
					var key := Vector2i(bx, by)
					if not buckets.has(key):
						continue
					for li in buckets[key]:
						var la: Array = lights[int(li)]
						var lp: Vector3 = la[0]
						var r: float = float(la[3])
						var d := Vector2(lp.x - c.x, lp.z - c.z).length()
						if d >= r:
							continue
						var f := pow(1.0 - d / r, 2.0) * float(la[2])
						if f < 0.03 or not _tile_los(lp, c):
							continue
						var lc: Color = la[1]
						col += lc * f
			tile_light[lay.idx(x, y)] = Color(minf(col.r, 1.7), minf(col.g, 1.7), minf(col.b, 1.7))
	# corner light = average of the floor tiles touching the corner
	corner_light.resize((lay.w + 1) * (lay.h + 1))
	for y in lay.h + 1:
		for x in lay.w + 1:
			var sum := Color(0, 0, 0)
			var n := 0
			for d in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
				var dv: Vector2i = d
				var tx := x + dv.x
				var ty := y + dv.y
				if lay.floor_at(tx, ty):
					sum += tile_light[lay.idx(tx, ty)]
					n += 1
			corner_light[y * (lay.w + 1) + x] = sum / float(n) if n > 0 else amb


func _tile_los(a: Vector3, b: Vector3) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var steps := maxi(1, int(d.length() / (TILE * 0.5)))
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var tile := layout.tile_of(Vector3(a.x + d.x * t, 0.0, a.z + d.y * t))
		if not layout.floor_at(tile.x, tile.y):
			return false
	return true


func _corner(x: int, y: int) -> Color:
	return corner_light[y * (layout.w + 1) + x]


## Baked light at any world point on the floor (props, chests, dynamic pieces).
func light_at(p: Vector3) -> Color:
	var t := layout.tile_of(p)
	if layout.in_bounds(t.x, t.y) and layout.floor_at(t.x, t.y):
		return tile_light[layout.idx(t.x, t.y)]
	return theme["amb"]


# =================================================================================================
# Chunks
# =================================================================================================

class Geo:
	## Raw triangle arrays for custom (per-vertex lit) geometry.
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()

	## Quad p0..p3 (in order round the edge) facing `nrm`, with a colour per corner.
	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nrm: Vector3, c0: Color, c1: Color, c2: Color, c3: Color) -> void:
		var base := v.size()
		v.append_array(PackedVector3Array([p0, p1, p2, p3]))
		n.append_array(PackedVector3Array([nrm, nrm, nrm, nrm]))
		c.append_array(PackedColorArray([c0, c1, c2, c3]))
		# Godot front faces: normal = (c - a) x (b - a)
		if (p2 - p0).cross(p1 - p0).dot(nrm) >= 0.0:
			i.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
		else:
			i.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))

	func mesh() -> ArrayMesh:
		var m := ArrayMesh.new()
		if v.is_empty():
			return m
		var a: Array = []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_COLOR] = c
		a[Mesh.ARRAY_INDEX] = i
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		return m


func _build_chunk(r: Rect2i) -> void:
	var lay := layout
	var origin := Vector3((r.position.x + r.size.x * 0.5) * TILE, 0.0, (r.position.y + r.size.y * 0.5) * TILE)
	var floor_geo := Geo.new()
	var wall_vr := Geo.new()
	var wall_tv := Geo.new()
	var deco := MeshKit.Builder.new()
	var deco_vr := MeshKit.Builder.new()
	var deco_tv := MeshKit.Builder.new()
	var fcol: Color = theme["floor"]
	var fcol2: Color = theme["floor2"]
	var any := false
	for y in range(r.position.y, mini(r.end.y, lay.h)):
		for x in range(r.position.x, mini(r.end.x, lay.w)):
			if lay.floor_at(x, y):
				any = true
				_floor_tile(floor_geo, deco, x, y, origin, fcol, fcol2)
				_walls_of(wall_vr, wall_tv, x, y, origin)
			elif tv_walls and _is_boundary(x, y):
				_cap(wall_tv, x, y, origin)
	if not any:
		return
	# Decorations, torches, door frames that live in this chunk.
	for d in lay.deco:
		var da: Array = d
		var p: Vector3 = da[1]
		if r.has_point(lay.tile_of(p)):
			_deco_piece(deco, String(da[0]), p - origin, float(da[2]), float(da[3]), light_at(p))
	for t in lay.torches:
		var ta: Array = t
		var p: Vector3 = ta[0]
		var nrm: Vector3 = ta[1]
		if r.has_point(lay.tile_of(p + nrm * 0.3)):
			if vr_walls:
				_torch_vr(deco_vr, p - origin, nrm)
			if tv_walls:
				_torch_tv(deco_tv, p - origin, nrm)
	for dd in lay.doors:
		var door: Dictionary = dd
		var p: Vector3 = door["pos"]
		var o: Vector3 = door["out"]
		if r.has_point(lay.tile_of(p - o * 0.3)):
			_door_frame(deco_vr if vr_walls else null, deco_tv if tv_walls else null, p - origin, o, light_at(p - o * 0.75))
	if lay.kind == "boss":
		var arena := lay.exit_room
		var c := lay.room_center(arena)
		if r.has_point(lay.tile_of(c)):
			_arena_runes(deco, c - origin)
	# Assemble: floor + decorations (everyone), walls per camera kind.
	deco.add_mesh(floor_geo.mesh())
	var main := MeshKit.instance(deco.build(), false)
	main.name = "Chunk%d_%d" % [r.position.x, r.position.y]
	main.position = origin
	main.layers = LAYER_WORLD
	_cull(main)
	add_child(main)
	if vr_walls:
		deco_vr.add_mesh(wall_vr.mesh())
		var wv := MeshKit.instance(deco_vr.build(), false)
		wv.name = main.name + "VR"
		wv.position = origin
		wv.layers = LAYER_VR
		_cull(wv)
		add_child(wv)
	if tv_walls:
		deco_tv.add_mesh(wall_tv.mesh())
		var wt := MeshKit.instance(deco_tv.build(), false)
		wt.name = main.name + "TV"
		wt.position = origin
		wt.layers = LAYER_TV
		add_child(wt)


func _cull(mi: GeometryInstance3D) -> void:
	if vr_walls and not tv_walls:
		mi.visibility_range_end = VR_RANGE
		mi.visibility_range_end_margin = 4.0


func _hash01(x: int, y: int, k: int = 0) -> float:
	var hsh := (x * 73856093) ^ (y * 19349663) ^ (k * 83492791) ^ (layout.seed_value * 2654435)
	hsh = (hsh ^ (hsh >> 13)) * 1274126177
	return float(hsh & 0xFFFF) / 65535.0


func _floor_tile(g: Geo, deco: MeshKit.Builder, x: int, y: int, origin: Vector3, c1: Color, c2: Color) -> void:
	var base := c1 if (x + y) % 2 == 0 else c1.lerp(c2, 0.6)
	var tint := 0.9 + 0.16 * _hash01(x, y)
	if layout.tiles[layout.idx(x, y)] == Gen.HALL:
		base = base.darkened(0.08)
	var col := base * tint
	var x0 := x * TILE - origin.x
	var z0 := y * TILE - origin.z
	var gap := 0.03
	var p0 := Vector3(x0 + gap, 0.0, z0 + gap)
	var p1 := Vector3(x0 + TILE - gap, 0.0, z0 + gap)
	var p2 := Vector3(x0 + TILE - gap, 0.0, z0 + TILE - gap)
	var p3 := Vector3(x0 + gap, 0.0, z0 + TILE - gap)
	g.quad(p0, p1, p2, p3, Vector3.UP, _lit(col, _corner(x, y)), _lit(col, _corner(x + 1, y)),
		_lit(col, _corner(x + 1, y + 1)), _lit(col, _corner(x, y + 1)))
	# grout under the tile gaps
	var grout := col.darkened(0.55)
	g.quad(Vector3(x0, -0.02, z0), Vector3(x0 + TILE, -0.02, z0), Vector3(x0 + TILE, -0.02, z0 + TILE),
		Vector3(x0, -0.02, z0 + TILE), Vector3.UP, _lit(grout, _corner(x, y)), _lit(grout, _corner(x + 1, y)),
		_lit(grout, _corner(x + 1, y + 1)), _lit(grout, _corner(x, y + 1)))
	# theme details
	var h := _hash01(x, y, 3)
	var light := tile_light[layout.idx(x, y)]
	var c := Vector3(x0 + TILE * 0.5, 0.0, z0 + TILE * 0.5)
	var acc: Color = theme["accent"]
	match String(theme["deco"]):
		"moss":
			if h < 0.22:
				deco.ellipsoid(Vector3(0.45 + h, 0.03, 0.35 + h * 0.8), MeshKit.at(c + Vector3((h - 0.1) * 2.0, 0.015, 0.2 - h)), _lit(acc, light))
		"crystal":
			if h < 0.06:
				deco.prism(5, 0.06, 0.18, MeshKit.at(c + Vector3(0.3, 0.09, -0.2), Vector3.ONE, Vector3(0.2, h * 30.0, 0.1)), acc, true)
		"lava":
			if h < 0.12:
				deco.box(Vector3(0.9, 0.012, 0.07), MeshKit.at(c + Vector3(0.0, 0.006, (h - 0.06) * 6.0), Vector3.ONE, Vector3(0, h * 40.0, 0)), Color(1.0, 0.45, 0.1), true)
		"ice":
			if h < 0.25:
				deco.ellipsoid(Vector3(0.5, 0.025, 0.4), MeshKit.at(c + Vector3((h - 0.12) * 3.0, 0.012, 0.1)), _lit(Color(0.95, 0.97, 1.0), light))
		"gold":
			if h < 0.1:
				for k in 3:
					deco.cylinder(0.07, 0.07, 0.015, MeshKit.at(c + Vector3(0.15 * k - 0.15, 0.008 + 0.012 * k, 0.1 * k)), Color(1.0, 0.8, 0.3), 8, true)


## Colour times light (the bake), kept in range.
func _lit(c: Color, l: Color) -> Color:
	return Color(minf(c.r * l.r, 1.0), minf(c.g * l.g, 1.0), minf(c.b * l.b, 1.0))


func _is_boundary(x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if layout.floor_at(x + dx, y + dy):
				return true
	return false


## Wall faces of floor tile (x, y) that face solid tiles.
func _walls_of(gv: Geo, gt: Geo, x: int, y: int, origin: Vector3) -> void:
	var lay := layout
	var wall: Color = theme["wall"]
	for k in 4:
		var d: Vector2i = Gen.DIRS[k]
		if lay.floor_at(x + d.x, y + d.y):
			continue
		# the face lies on the shared edge, looking back into (x, y)
		var nrm := Vector3(-d.x, 0, -d.y)
		var a := Vector2i.ZERO  # corner indices along the edge
		var b := Vector2i.ZERO
		match k:
			0:
				a = Vector2i(x + 1, y)
				b = Vector2i(x + 1, y + 1)
			1:
				a = Vector2i(x + 1, y + 1)
				b = Vector2i(x, y + 1)
			2:
				a = Vector2i(x, y + 1)
				b = Vector2i(x, y)
			3:
				a = Vector2i(x, y)
				b = Vector2i(x + 1, y)
		var pa := Vector3(a.x * TILE, 0.0, a.y * TILE) - origin
		var pb := Vector3(b.x * TILE, 0.0, b.y * TILE) - origin
		var la := _corner(a.x, a.y)
		var lb := _corner(b.x, b.y)
		if vr_walls:
			_brick_face(gv, pa, pb, nrm, WALL_VR, wall, la, lb, x * 7 + y * 13 + k)
		if tv_walls:
			_brick_face(gt, pa, pb, nrm, WALL_TV, wall, la, lb, x * 7 + y * 13 + k)


## A wall face from pa to pb (floor level) up to height h: dark mortar behind rows of bricks, each
## brick tinted a little and lit by the baked light (darker near the floor, brightest at torch height).
func _brick_face(g: Geo, pa: Vector3, pb: Vector3, nrm: Vector3, h: float, wall: Color, la: Color, lb: Color, seed_k: int) -> void:
	var up := Vector3.UP
	var mortar := wall.darkened(0.6)
	g.quad(pa, pb, pb + up * h, pa + up * h, nrm, _lit(mortar, la), _lit(mortar, lb), _lit(mortar, lb), _lit(mortar, la))
	var rows := maxi(2, int(round(h / 0.52)))
	var rh := h / float(rows)
	var along := pb - pa
	var off := nrm * 0.012
	for row in rows:
		var y0 := row * rh + 0.025
		var y1 := (row + 1) * rh - 0.025
		var cuts: Array[float] = [0.0, 0.5, 1.0]
		if row % 2 == 1:
			cuts = [0.0, 0.25, 0.75, 1.0]
		var vf0 := _vert_light(y0, h)
		var vf1 := _vert_light(y1, h)
		for ci in cuts.size() - 1:
			var t0 := cuts[ci] + (0.02 if ci > 0 else 0.0)
			var t1 := cuts[ci + 1] - (0.02 if ci < cuts.size() - 2 else 0.0)
			var tint := 0.86 + 0.22 * _hash01(seed_k, row, ci)
			var bc := wall * tint
			if row == 0:
				bc = bc.darkened(0.18)
			var l0 := la.lerp(lb, t0)
			var l1 := la.lerp(lb, t1)
			var q0 := pa + along * t0 + up * y0 + off
			var q1 := pa + along * t1 + up * y0 + off
			var q2 := pa + along * t1 + up * y1 + off
			var q3 := pa + along * t0 + up * y1 + off
			g.quad(q0, q1, q2, q3, nrm, _lit(bc, l0 * vf0), _lit(bc, l1 * vf0), _lit(bc, l1 * vf1), _lit(bc, l0 * vf1))


func _vert_light(y: float, h: float) -> float:
	if h <= WALL_TV + 0.01:
		return 0.85 + 0.25 * (y / h)
	return 0.78 + 0.32 * clampf(1.0 - absf(y - 1.9) / 1.9, 0.0, 1.0)


## TV only: the flat top of a wall tile (so walls read as solid blocks from above).
func _cap(g: Geo, x: int, y: int, origin: Vector3) -> void:
	var top: Color = theme["top"]
	var best := Color(0, 0, 0)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if layout.floor_at(x + dx, y + dy):
				var l := tile_light[layout.idx(x + dx, y + dy)]
				if l.get_luminance() > best.get_luminance():
					best = l
	var c := _lit(top * (0.92 + 0.12 * _hash01(x, y, 9)), best)
	var x0 := x * TILE - origin.x
	var z0 := y * TILE - origin.z
	var hgt := WALL_TV
	g.quad(Vector3(x0, hgt, z0), Vector3(x0 + TILE, hgt, z0), Vector3(x0 + TILE, hgt, z0 + TILE), Vector3(x0, hgt, z0 + TILE),
		Vector3.UP, c, c, c, c)


func _torch_vr(b: MeshKit.Builder, p: Vector3, nrm: Vector3) -> void:
	var flame: Color = theme["torch"]
	var iron := Color(0.22, 0.2, 0.2)
	var at := p + nrm * 0.12 + Vector3.UP * 1.75
	b.box(Vector3(0.1, 0.1, 0.1), MeshKit.at(p + nrm * 0.04 + Vector3.UP * 1.62), iron)
	b.cylinder(0.035, 0.03, 0.34, MeshKit.aim(p + nrm * 0.09 + Vector3.UP * 1.7, (nrm + Vector3.UP * 1.4).normalized()), Color(0.45, 0.3, 0.2), 6)
	b.cylinder(0.09, 0.06, 0.1, MeshKit.at(at + Vector3.UP * 0.06), iron, 8)
	b.sphere(0.085, MeshKit.at(at + Vector3.UP * 0.16), flame, 8, true)
	b.cone(0.07, 0.22, MeshKit.at(at + Vector3.UP * 0.3), flame.lerp(Color(1, 1, 0.8), 0.4), 8, true)


func _torch_tv(b: MeshKit.Builder, p: Vector3, nrm: Vector3) -> void:
	var flame: Color = theme["torch"]
	var at := p - nrm * 0.35 + Vector3.UP * WALL_TV
	b.cylinder(0.16, 0.11, 0.14, MeshKit.at(at + Vector3.UP * 0.07), Color(0.25, 0.22, 0.22), 8)
	b.sphere(0.14, MeshKit.at(at + Vector3.UP * 0.2), flame, 8, true)
	b.cone(0.11, 0.3, MeshKit.at(at + Vector3.UP * 0.36), flame.lerp(Color(1, 1, 0.8), 0.4), 8, true)


func _door_frame(bv: MeshKit.Builder, bt: MeshKit.Builder, p: Vector3, out: Vector3, l: Color) -> void:
	var side := Vector3(-out.z, 0.0, out.x)
	var stone: Color = (theme["top"] as Color).darkened(0.1)
	var c := _lit(stone, l)
	for s in [-1.0, 1.0]:
		var sf: float = s
		var post := p + side * sf * (TILE + 0.12) - out * 0.02
		if bv != null:
			bv.box(Vector3(0.36, 2.9, 0.36), MeshKit.at(post + Vector3.UP * 1.45, Vector3.ONE, Vector3(0, atan2(out.x, out.z), 0)), c)
		if bt != null:
			bt.box(Vector3(0.36, 1.25, 0.36), MeshKit.at(post + Vector3.UP * 0.625, Vector3.ONE, Vector3(0, atan2(out.x, out.z), 0)), c)
	if bv != null:
		bv.box(Vector3(TILE * 2.0 + 0.6, 0.4, 0.42), MeshKit.at(p + Vector3.UP * 2.9 - out * 0.02, Vector3.ONE, Vector3(0, atan2(side.x, side.z) + PI * 0.5, 0)), c)
		bv.box(Vector3(0.3, 0.3, 0.1), MeshKit.at(p + Vector3.UP * 2.9 - out * 0.24, Vector3.ONE, Vector3(0, atan2(out.x, out.z), PI * 0.25)), theme["accent"], true)


func _arena_runes(b: MeshKit.Builder, c: Vector3) -> void:
	var glow: Color = theme["glow"]
	b.torus(6.2, 0.07, MeshKit.at(c + Vector3.UP * 0.02, Vector3(1, 0.15, 1)), glow, 32, 6, true)
	b.torus(4.0, 0.05, MeshKit.at(c + Vector3.UP * 0.02, Vector3(1, 0.15, 1)), glow.darkened(0.2), 28, 6, true)
	for k in 8:
		var a := k * TAU / 8.0
		b.box(Vector3(0.35, 0.02, 0.35), MeshKit.at(c + Vector3(cos(a), 0.0, sin(a)) * 5.1 + Vector3.UP * 0.02, Vector3.ONE, Vector3(0, a + PI * 0.25, 0)), glow, true)


# =================================================================================================
# Decorations (custom cached meshes; MeshKit ready props where they fit)
# =================================================================================================

func _deco_piece(b: MeshKit.Builder, kind: String, p: Vector3, yaw: float, s: float, light: Color) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), p)
	var tint := Color(minf(light.r, 1.2), minf(light.g, 1.2), minf(light.b, 1.2))
	match kind:
		"mushroom", "rock", "crate", "barrel", "candle", "gem":
			b.add_mesh(MeshKit.prop(kind, int(s * 10.0) % 3), xf, tint)
		_:
			b.add_mesh(deco_mesh(kind), xf, tint)


## Cached decoration meshes for the themes (bones, graves, crystals, anvils, lava, ice, snow, coins).
static func deco_mesh(kind: String) -> ArrayMesh:
	return ResCache.get_or_make("dd_deco_%s_v2" % kind, func() -> Resource: return _make_deco(kind)) as ArrayMesh


static func _make_deco(kind: String) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	match kind:
		"bones":
			var bone := Color(0.93, 0.9, 0.82)
			b.sphere(0.13, MeshKit.at(Vector3(0, 0.12, 0), Vector3(1, 0.9, 1.05)), bone, 10)
			b.box(Vector3(0.05, 0.03, 0.04), MeshKit.at(Vector3(-0.045, 0.12, 0.12)), Color(0.2, 0.18, 0.2))
			b.box(Vector3(0.05, 0.03, 0.04), MeshKit.at(Vector3(0.045, 0.12, 0.12)), Color(0.2, 0.18, 0.2))
			b.capsule_between(Vector3(0.2, 0.04, -0.1), Vector3(0.5, 0.04, 0.12), 0.04, bone, 6)
			b.capsule_between(Vector3(-0.15, 0.04, 0.25), Vector3(-0.42, 0.04, 0.0), 0.04, bone, 6)
		"grave":
			var stone := Color(0.6, 0.62, 0.6)
			b.rounded_box(Vector3(0.6, 0.8, 0.16), 0.08, MeshKit.at(Vector3(0, 0.4, 0)), stone)
			b.box(Vector3(0.28, 0.05, 0.02), MeshKit.at(Vector3(0, 0.55, 0.085)), stone.darkened(0.35))
			b.box(Vector3(0.05, 0.22, 0.02), MeshKit.at(Vector3(0, 0.52, 0.085)), stone.darkened(0.35))
			b.ellipsoid(Vector3(0.3, 0.06, 0.24), MeshKit.at(Vector3(0.1, 0.03, 0.2)), Color(0.35, 0.6, 0.25))
		"crystal":
			var c1 := Color(0.5, 0.75, 1.0)
			var c2 := Color(0.85, 0.5, 1.0)
			b.sphere(0.25, MeshKit.at(Vector3(0, 0.05, 0), Vector3(1.2, 0.4, 1.0)), Color(0.4, 0.33, 0.3), 8)
			b.prism(6, 0.13, 0.9, MeshKit.at(Vector3(0, 0.45, 0), Vector3.ONE, Vector3(0.1, 0, 0.12)), c1, true)
			b.prism(6, 0.09, 0.6, MeshKit.at(Vector3(0.18, 0.3, 0.05), Vector3.ONE, Vector3(-0.2, 0, -0.45)), c2, true)
			b.prism(6, 0.08, 0.5, MeshKit.at(Vector3(-0.16, 0.25, -0.05), Vector3.ONE, Vector3(0.3, 0, 0.5)), c1.lerp(c2, 0.5), true)
			b.cone(0.13, 0.2, MeshKit.at(Vector3(0, 0.99, 0), Vector3.ONE, Vector3(0.1, 0, 0.12)), c1, 6, true)
		"anvil":
			var iron := Color(0.3, 0.3, 0.33)
			b.box(Vector3(0.35, 0.35, 0.3), MeshKit.at(Vector3(0, 0.175, 0)), Color(0.4, 0.3, 0.22))
			b.box(Vector3(0.22, 0.16, 0.2), MeshKit.at(Vector3(0, 0.43, 0)), iron)
			b.box(Vector3(0.7, 0.14, 0.26), MeshKit.at(Vector3(0, 0.57, 0)), iron)
			b.cone(0.12, 0.25, MeshKit.at(Vector3(0.45, 0.57, 0), Vector3.ONE, Vector3(0, 0, -PI * 0.5)), iron)
			b.box(Vector3(0.3, 0.04, 0.1), MeshKit.at(Vector3(-0.1, 0.66, 0)), Color(1.0, 0.5, 0.15), true)
		"lava":
			b.ellipsoid(Vector3(0.75, 0.03, 0.55), MeshKit.at(Vector3(0, 0.015, 0)), Color(0.25, 0.18, 0.16))
			b.ellipsoid(Vector3(0.6, 0.03, 0.42), MeshKit.at(Vector3(0, 0.03, 0)), Color(1.0, 0.45, 0.1), 12, true)
			b.sphere(0.07, MeshKit.at(Vector3(0.2, 0.05, 0.1)), Color(1.0, 0.85, 0.3), 6, true)
		"ice":
			var ice := Color(0.65, 0.92, 1.0)
			b.prism(6, 0.14, 1.0, MeshKit.at(Vector3(0, 0.5, 0), Vector3.ONE, Vector3(0.1, 0, 0.05)), ice, true)
			b.prism(6, 0.1, 0.6, MeshKit.at(Vector3(0.2, 0.3, 0.05), Vector3.ONE, Vector3(-0.15, 0, -0.4)), ice.lightened(0.2), true)
			b.cone(0.14, 0.25, MeshKit.at(Vector3(0, 1.12, 0)), ice, 6, true)
			b.dome(0.3, MeshKit.at(Vector3(0, 0, 0), Vector3(1.2, 0.4, 1.0)), Color(0.95, 0.97, 1.0), 10)
		"snow":
			b.dome(0.5, MeshKit.at(Vector3(0, 0, 0), Vector3(1.3, 0.45, 1.0)), Color(0.96, 0.98, 1.0), 12)
			b.dome(0.3, MeshKit.at(Vector3(0.4, 0, 0.2), Vector3(1.0, 0.5, 1.0)), Color(0.93, 0.96, 1.0), 10)
		"coins":
			var gold := Color(1.0, 0.8, 0.3)
			b.dome(0.45, MeshKit.at(Vector3(0, 0, 0), Vector3(1.2, 0.55, 1.0)), gold.darkened(0.15), 12)
			for k in 6:
				var a := k * 1.1
				b.cylinder(0.07, 0.07, 0.02, MeshKit.at(Vector3(cos(a) * 0.3, 0.12 + 0.03 * k, sin(a) * 0.25), Vector3.ONE, Vector3(0.4, a, 0.2)), gold, 8, true)
			b.prism(5, 0.07, 0.15, MeshKit.at(Vector3(0.05, 0.27, 0.0)), Color(0.9, 0.3, 0.4), true)
		_:
			b.sphere(0.2, MeshKit.at(Vector3(0, 0.2, 0)), Color(0.5, 0.5, 0.5), 8)
	return b.build()


# =================================================================================================
# Dynamic pieces
# =================================================================================================

func _build_doors() -> void:
	for dd in layout.doors:
		var d: Dictionary = dd
		var kind := String(d["kind"])
		if kind == "locked":
			var g := _make_gate()
			g.position = d["gate"]
			var o: Vector3 = d["out"]
			g.rotation.y = atan2(o.x, o.z)
			add_child(g)
			gates[int(d["id"])] = g
		elif kind == "cracked":
			var c := _make_crack()
			var o2: Vector3 = d["out"]
			c.position = (d["pos"] as Vector3) + o2 * 0.35
			c.rotation.y = atan2(o2.x, o2.z)
			add_child(c)
			cracks[int(d["id"])] = c


## Iron portcullis with a golden lock plate (faces +Z / -Z; the gap is along X).
func _make_gate() -> Node3D:
	var root := Node3D.new()
	root.name = "Gate"
	var mesh: ArrayMesh = ResCache.get_or_make("dd_gate_v2", func() -> Resource:
		var b := MeshKit.Builder.new()
		var iron := Color(0.32, 0.32, 0.38)
		for k in 9:
			var x := -1.35 + k * 0.3375
			b.cylinder(0.045, 0.045, 2.8, MeshKit.at(Vector3(x, 1.4, 0)), iron, 6)
			b.cone(0.07, 0.16, MeshKit.at(Vector3(x, 0.0, 0), Vector3.ONE, Vector3(PI, 0, 0)), iron, 6)
		for yy in [0.6, 1.5, 2.4]:
			b.box(Vector3(2.9, 0.1, 0.1), MeshKit.at(Vector3(0, float(yy), 0)), iron.darkened(0.2))
		b.rounded_box(Vector3(0.5, 0.6, 0.12), 0.05, MeshKit.at(Vector3(0, 1.2, 0.0)), Color(1.0, 0.78, 0.25))
		b.sphere(0.07, MeshKit.at(Vector3(0, 1.28, 0.07)), Color(0.15, 0.1, 0.05), 8)
		b.box(Vector3(0.05, 0.14, 0.04), MeshKit.at(Vector3(0, 1.16, 0.07)), Color(0.15, 0.1, 0.05))
		b.box(Vector3(0.62, 0.72, 0.03), MeshKit.at(Vector3(0, 1.2, -0.05)), Color(1.0, 0.85, 0.35), true)
		return b.build()) as ArrayMesh
	var mi := MeshKit.instance(mesh, false)
	mi.name = "Bars"
	root.add_child(mi)
	return root


func _make_crack() -> Node3D:
	var root := Node3D.new()
	root.name = "Crack"
	var wall: Color = theme["wall"]
	for pass_i in 2:
		var tall := pass_i == 0
		if tall and not vr_walls:
			continue
		if not tall and not tv_walls:
			continue
		var h := WALL_VR if tall else WALL_TV
		var b := MeshKit.Builder.new()
		b.box(Vector3(TILE * 2.0, h, 0.7), MeshKit.at(Vector3(0, h * 0.5, 0)), _lit(wall.darkened(0.05), theme["amb"]))
		var dark := Color(0.08, 0.07, 0.08)
		var pts: Array[Vector3] = [Vector3(-0.2, 0.1, 0.36), Vector3(0.1, 0.5, 0.36), Vector3(-0.15, 0.9, 0.36), Vector3(0.25, 1.4, 0.36), Vector3(0.0, 1.9, 0.36)]
		for k in pts.size() - 1:
			if pts[k + 1].y > h:
				break
			b.tube(pts[k], pts[k + 1], 0.035, 0.03, dark, 4)
		b.tube(Vector3(0.1, 0.5, 0.36), Vector3(0.6, 0.75, 0.36), 0.03, 0.02, dark, 4)
		b.tube(Vector3(-0.15, 0.9, 0.36), Vector3(-0.7, 1.05, 0.36), 0.03, 0.02, dark, 4)
		for k in 4:
			b.sphere(0.12 + 0.03 * k, MeshKit.at(Vector3(-0.6 + k * 0.4, 0.08, 0.55 + 0.05 * (k % 2))), wall.darkened(0.25), 6)
		var mi := MeshKit.instance(b.build(), false)
		mi.layers = LAYER_VR if tall else LAYER_TV
		root.add_child(mi)
	return root


func _build_chests() -> void:
	for ch in layout.chests:
		var c: Dictionary = ch
		var node := make_chest(String(c["kind"]))
		node.position = c["pos"]
		node.rotation.y = float(c["yaw"])
		add_child(node)
		chests[int(c["id"])] = node


## A chest with a hinged lid ("Lid" child). kind: normal | gold | key | mimic.
static func make_chest(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Chest"
	var gold := kind == "gold" or kind == "key"
	var key := "dd_chest_%s_v2" % ("gold" if gold else "wood")
	var body: ArrayMesh = ResCache.get_or_make(key + "_body", func() -> Resource:
		var b := MeshKit.Builder.new()
		var wood := Color(0.62, 0.4, 0.24) if not gold else Color(0.55, 0.22, 0.25)
		var trim := Color(0.45, 0.45, 0.52) if not gold else Color(1.0, 0.8, 0.3)
		b.rounded_box(Vector3(0.9, 0.5, 0.6), 0.05, MeshKit.at(Vector3(0, 0.25, 0)), wood)
		b.box(Vector3(0.94, 0.07, 0.64), MeshKit.at(Vector3(0, 0.08, 0)), trim)
		b.box(Vector3(0.94, 0.07, 0.64), MeshKit.at(Vector3(0, 0.46, 0)), trim)
		for x in [-0.3, 0.3]:
			b.box(Vector3(0.08, 0.5, 0.64), MeshKit.at(Vector3(float(x), 0.25, 0)), trim)
		return b.build()) as ArrayMesh
	var lid_m: ArrayMesh = ResCache.get_or_make(key + "_lid", func() -> Resource:
		var b := MeshKit.Builder.new()
		var wood := Color(0.62, 0.4, 0.24) if not gold else Color(0.55, 0.22, 0.25)
		var trim := Color(0.45, 0.45, 0.52) if not gold else Color(1.0, 0.8, 0.3)
		b.cylinder(0.3, 0.3, 0.9, MeshKit.at(Vector3(0, 0.0, 0.3), Vector3(1, 1, 0.75), Vector3(0, 0, PI * 0.5)), wood, 12)
		for x in [-0.3, 0.3]:
			b.cylinder(0.31, 0.31, 0.08, MeshKit.at(Vector3(float(x), 0.0, 0.3), Vector3(1, 1, 0.76), Vector3(0, 0, PI * 0.5)), trim, 12)
		b.box(Vector3(0.16, 0.2, 0.06), MeshKit.at(Vector3(0, -0.02, 0.62)), Color(1.0, 0.82, 0.3), gold)
		return b.build()) as ArrayMesh
	var bm := MeshKit.instance(body, false)
	root.add_child(bm)
	var lid := Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(0, 0.5, -0.3)
	root.add_child(lid)
	var lm := MeshKit.instance(lid_m, false)
	lid.add_child(lm)
	if kind == "mimic":
		# a tiny pink tongue peeks out: observant kids can spot the mimic!
		var t := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.06
		sm.radial_segments = 8
		sm.rings = 4
		t.mesh = sm
		t.material_override = MeshKit.material(Color(1.0, 0.45, 0.55))
		t.position = Vector3(0.15, 0.48, 0.31)
		root.add_child(t)
	if gold:
		var beam := _beam(Color(1.0, 0.85, 0.35), 1.2)
		beam.name = "Beam"
		root.add_child(beam)
	return root


## A soft vertical light beam (loot / gold chests): additive, cheap.
static func _beam(col: Color, height: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.22
	cm.height = height
	cm.radial_segments = 8
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(col.r, col.g, col.b, 0.35)
	mi.material_override = m
	mi.position.y = height * 0.5 + 0.3
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func open_chest(id: int, instant: bool = false) -> void:
	var node: Node3D = chests.get(id, null)
	if node == null:
		return
	var lid := node.get_node_or_null("Lid") as Node3D
	if lid == null:
		return
	if instant:
		lid.rotation.x = -1.9
	else:
		var tw := lid.create_tween()
		tw.tween_property(lid, "rotation:x", -2.1, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(lid, "rotation:x", -1.9, 0.15)
	var beam := node.get_node_or_null("Beam")
	if beam != null:
		beam.queue_free()


## A mimic chest woke up: hide the chest (an enemy takes its place).
func remove_chest(id: int) -> void:
	var node: Node3D = chests.get(id, null)
	if node != null:
		node.queue_free()
	chests.erase(id)


func _build_pots() -> void:
	var xfs: Array = []
	var cols := PackedColorArray()
	var acc: Color = theme["accent"]
	for i in layout.pots.size():
		var p: Vector3 = layout.pots[i]
		var s := 0.85 + 0.3 * _hash01(i, 7)
		xfs.append(Transform3D(Basis(Vector3.UP, _hash01(i, 3) * TAU).scaled(Vector3.ONE * s), p))
		var l := light_at(p)
		var base := Color(1, 1, 1).lerp(acc, 0.25 * _hash01(i, 5))
		cols.append(Color(minf(base.r * l.r * 1.1, 1.3), minf(base.g * l.g * 1.1, 1.3), minf(base.b * l.b * 1.1, 1.3)))
	pot_alive.resize(layout.pots.size())
	pot_alive.fill(1)
	if xfs.is_empty():
		return
	pots_mm = MeshKit.scatter(MeshKit.prop("pot"), xfs, cols, PackedColorArray(), false)
	pots_mm.name = "Pots"
	add_child(pots_mm)


func break_pot(i: int) -> void:
	if i < 0 or i >= pot_alive.size() or pot_alive[i] == 0:
		return
	pot_alive[i] = 0
	if pots_mm != null:
		pots_mm.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), layout.pots[i] + Vector3.DOWN))


func _build_traps() -> void:
	var spike_xf: Array = []
	var plate_xf: Array = []
	for tr in layout.traps:
		var t: Dictionary = tr
		if String(t["kind"]) == "spikes":
			var idxs: Array[int] = []
			for tile in t["tiles"]:
				var tv: Vector2i = tile
				var c := layout.center(tv)
				idxs.append(spike_xf.size())
				spike_xf.append(Transform3D(Basis(), c + Vector3.DOWN * 0.6))
				plate_xf.append(Transform3D(Basis(), c + Vector3.UP * 0.012))
			spike_index[int(t["id"])] = idxs
		else:
			var bnode := _make_boulder()
			bnode.position = t["a"]
			add_child(bnode)
			boulders[int(t["id"])] = bnode
	if not spike_xf.is_empty():
		var spikes: ArrayMesh = ResCache.get_or_make("dd_spikes_v1", func() -> Resource:
			var b := MeshKit.Builder.new()
			for z in 3:
				for x in 3:
					b.cone(0.11, 0.55, MeshKit.at(Vector3(-0.45 + x * 0.45, 0.27, -0.45 + z * 0.45)), Color(0.78, 0.8, 0.86), 6)
			return b.build()) as ArrayMesh
		var plate: ArrayMesh = ResCache.get_or_make("dd_spike_plate_v1", func() -> Resource:
			var b := MeshKit.Builder.new()
			b.box(Vector3(TILE - 0.1, 0.02, TILE - 0.1), MeshKit.at(Vector3.ZERO), Color(0.3, 0.3, 0.34))
			for z in 3:
				for x in 3:
					b.cylinder(0.12, 0.12, 0.025, MeshKit.at(Vector3(-0.45 + x * 0.45, 0.005, -0.45 + z * 0.45)), Color(0.08, 0.08, 0.1), 8)
			return b.build(MeshKit.vertex_material(true))) as ArrayMesh
		spike_mm = MeshKit.scatter(spikes, spike_xf, PackedColorArray(), PackedColorArray(), false)
		spike_mm.name = "Spikes"
		add_child(spike_mm)
		var pc := PackedColorArray()
		for i in plate_xf.size():
			pc.append(Color(1, 1, 1))
		plate_mm = MeshKit.scatter(plate, plate_xf, pc, PackedColorArray(), false)
		plate_mm.name = "SpikePlates"
		add_child(plate_mm)


## Spike trap visual: 0 = hidden, 1 = fully up; warn 0..1 glows the plate red.
func set_spikes(trap_id: int, up: float, warn: float) -> void:
	if spike_mm == null or not spike_index.has(trap_id):
		return
	for i in spike_index[trap_id]:
		var ii: int = i
		var xf := spike_mm.multimesh.get_instance_transform(ii)
		var base := plate_mm.multimesh.get_instance_transform(ii).origin
		xf.origin = base + Vector3.DOWN * (0.62 * (1.0 - up))
		spike_mm.multimesh.set_instance_transform(ii, xf)
		plate_mm.multimesh.set_instance_color(ii, Color(1, 1, 1).lerp(Color(2.2, 0.5, 0.4), warn))


func _make_boulder() -> Node3D:
	var root := Node3D.new()
	root.name = "Boulder"
	var mesh: ArrayMesh = ResCache.get_or_make("dd_boulder_v1", func() -> Resource:
		var b := MeshKit.Builder.new()
		var rock := Color(0.55, 0.5, 0.46)
		b.sphere(0.75, MeshKit.at(Vector3.ZERO), rock, 12)
		for k in 7:
			var a := k * 0.9
			b.sphere(0.32, MeshKit.at(Vector3(cos(a) * 0.55, sin(a * 1.7) * 0.4, sin(a) * 0.55)), rock.darkened(0.12 * (k % 3)), 8)
		b.box(Vector3(0.9, 0.06, 0.06), MeshKit.at(Vector3(0, 0.0, 0.74)), Color(0.25, 0.22, 0.2))
		return b.build()) as ArrayMesh
	var mi := MeshKit.instance(mesh, false)
	mi.name = "Rock"
	mi.position.y = 0.75
	root.add_child(mi)
	var shadow := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.8
	dm.bottom_radius = 0.8
	dm.height = 0.01
	dm.radial_segments = 12
	dm.rings = 1
	shadow.mesh = dm
	shadow.material_override = MeshKit.material(Color(0, 0, 0, 0.45))
	shadow.position.y = 0.02
	root.add_child(shadow)
	return root


func _build_stairs() -> void:
	stairs = Node3D.new()
	stairs.name = "Stairs"
	stairs.position = layout.stairs
	add_child(stairs)
	var mesh: ArrayMesh = ResCache.get_or_make("dd_stairs_v2", func() -> Resource:
		var b := MeshKit.Builder.new()
		var stone := Color(0.55, 0.55, 0.6)
		b.cylinder(1.45, 1.45, 0.02, MeshKit.at(Vector3(0, 0.012, 0)), Color(0.02, 0.02, 0.04), 24)
		b.torus(1.45, 0.14, MeshKit.at(Vector3(0, 0.06, 0), Vector3(1, 0.5, 1)), stone, 24)
		for k in 6:
			var a := k * 0.75
			var r := 1.05 - k * 0.12
			b.box(Vector3(0.75, 0.05, 0.45), MeshKit.at(Vector3(cos(a) * r * 0.75, 0.03 - k * 0.003, sin(a) * r * 0.75), Vector3.ONE, Vector3(0, -a, 0)),
				stone.darkened(0.12 * k))
		b.torus(1.32, 0.04, MeshKit.at(Vector3(0, 0.09, 0), Vector3(1, 0.4, 1)), Color(0.5, 0.8, 1.0), 24, 6, true)
		return b.build()) as ArrayMesh
	stairs.add_child(MeshKit.instance(mesh, false))
	stairs_glow = _beam(Color(0.5, 0.8, 1.0), 3.0)
	stairs_glow.scale = Vector3(6.0, 1.0, 6.0)
	stairs_glow.position.y = 1.5
	stairs.add_child(stairs_glow)
	if layout.kind == "boss":
		stairs.visible = false  # appears when the boss is defeated


func show_stairs(on: bool) -> void:
	if stairs != null:
		stairs.visible = on


func _build_shrine() -> void:
	shrine = Node3D.new()
	shrine.name = "Shrine"
	shrine.position = layout.room_center(layout.shrine_room)
	add_child(shrine)
	var mesh: ArrayMesh = ResCache.get_or_make("dd_shrine_v1", func() -> Resource:
		var b := MeshKit.Builder.new()
		var stone := Color(0.78, 0.78, 0.82)
		b.cylinder(1.3, 1.4, 0.12, MeshKit.at(Vector3(0, 0.06, 0)), stone.darkened(0.2), 20)
		b.torus(1.25, 0.05, MeshKit.at(Vector3(0, 0.13, 0), Vector3(1, 0.4, 1)), Color(1.0, 0.85, 0.4), 24, 6, true)
		b.prism(6, 0.38, 0.9, MeshKit.at(Vector3(0, 0.55, 0)), stone)
		b.cylinder(0.45, 0.38, 0.12, MeshKit.at(Vector3(0, 1.05, 0)), stone.lightened(0.1), 12)
		for k in 4:
			var a := k * TAU / 4.0 + PI * 0.25
			b.box(Vector3(0.12, 0.12, 0.02), MeshKit.at(Vector3(cos(a) * 0.36, 0.6, sin(a) * 0.36), Vector3.ONE, Vector3(0, -a + PI * 0.5, 0)), Color(1.0, 0.85, 0.4), true)
		return b.build()) as ArrayMesh
	shrine.add_child(MeshKit.instance(mesh, false))
	shrine_orb = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.28
	sm.height = 0.56
	sm.radial_segments = 14
	sm.rings = 7
	shrine_orb.mesh = sm
	shrine_orb.material_override = MeshKit.material(Color(1.0, 0.9, 0.55), 3.0)
	shrine_orb.position = Vector3(0, 1.45, 0)
	shrine.add_child(shrine_orb)
	var beam := _beam(Color(1.0, 0.9, 0.5), 2.4)
	beam.name = "Beam"
	shrine.add_child(beam)


## The shrine was used: its orb dims.
func use_shrine() -> void:
	if shrine_orb != null:
		shrine_orb.material_override = MeshKit.material(Color(0.5, 0.5, 0.55), 0.0)
	if shrine != null and shrine.get_node_or_null("Beam") != null:
		shrine.get_node("Beam").queue_free()


func open_gate(door_id: int, instant: bool = false) -> void:
	var g: Node3D = gates.get(door_id, null)
	if g == null:
		return
	gates.erase(door_id)
	if instant:
		g.queue_free()
		return
	var tw := g.create_tween()
	tw.tween_property(g, "position:y", 3.1, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(g.queue_free)


func break_crack(door_id: int, instant: bool = false) -> void:
	var c: Node3D = cracks.get(door_id, null)
	if c == null:
		return
	cracks.erase(door_id)
	if instant:
		c.queue_free()
		return
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector3(1.05, 0.05, 1.05), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(c.queue_free)


## Update traps every frame from the shared floor clock (same on both machines).
func update_traps(t: float) -> void:
	for tr in layout.traps:
		var d: Dictionary = tr
		var id := int(d["id"])
		if String(d["kind"]) == "spikes":
			var st := spike_state(d, t)
			set_spikes(id, st.x, st.y)
		else:
			var b: Node3D = boulders.get(id, null)
			if b == null:
				continue
			var info := boulder_state(d, t)
			var pos: Vector3 = info[0]
			var moving: bool = info[1]
			var prev := b.position
			b.position = pos
			var rock := b.get_node_or_null("Rock") as Node3D
			if rock != null and moving:
				var mv := pos - prev
				var axis := Vector3(mv.z, 0.0, -mv.x).normalized() if mv.length() > 0.0001 else Vector3.RIGHT
				rock.rotate(axis, mv.length() / 0.75)


## Spike timing: returns Vector2(up 0..1, warn 0..1).
static func spike_state(d: Dictionary, t: float) -> Vector2:
	var period := float(d["period"])
	var ph := fposmod(t + float(d["offset"]), period)
	# 0 .. 1.6 down, 1.6 .. 2.2 warn, 2.2 .. 2.35 rising, 2.35 .. 3.0 up, 3.0 .. 3.2 falling
	if ph < 1.6:
		return Vector2(0.0, 0.0)
	if ph < 2.2:
		return Vector2(0.0, (ph - 1.6) / 0.6)
	if ph < 2.35:
		return Vector2((ph - 2.2) / 0.15, 1.0)
	if ph < 3.0:
		return Vector2(1.0, 1.0)
	return Vector2(1.0 - (ph - 3.0) / 0.2, 0.0)


## Boulder: [position, rolling?]. Rolls a -> b (2.4 s), waits, rolls back (2.4 s), waits.
static func boulder_state(d: Dictionary, t: float) -> Array:
	var period := float(d["period"])
	var ph := fposmod(t + float(d["offset"]), period)
	var a: Vector3 = d["a"]
	var b: Vector3 = d["b"]
	var half := period * 0.5
	var roll := 2.4
	if ph < roll:
		var k := ph / roll
		return [a.lerp(b, k * k * (3.0 - 2.0 * k)), true]
	if ph < half:
		return [b, false]
	if ph < half + roll:
		var k2 := (ph - half) / roll
		return [b.lerp(a, k2 * k2 * (3.0 - 2.0 * k2)), true]
	return [a, false]


## True while the boulder is about to roll (rumble warning), for sounds and hints.
static func boulder_warning(d: Dictionary, t: float) -> bool:
	var period := float(d["period"])
	var ph := fposmod(t + float(d["offset"]), period)
	var half := period * 0.5
	return (ph > half - 0.8 and ph < half) or ph > period - 0.8
