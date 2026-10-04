extends RefCounted
## Builds the cosy cartoon house, all procedural. One storey, x -9..9, z -7..7, ceiling at 2.6 m.
## South row (z 1..7): living room (west), hall (middle, where the seeker counts), kitchen (east).
## North row (z -7..1): bedroom (west), playroom (middle), bathroom (east).
## Through the living room's garden door (west wall): the BACK GARDEN, x -17..-9, open to the sky, with a
## shed, hedges, trees, a slide, a sandpit, a washing line and fairy lights along the fence.
## Every doorway is kept clear of furniture (the test bot checks the whole house can be walked).
## Static furniture is merged into one mesh per colour (few draw calls on the Frame's phone-class GPU)
## and one StaticBody3D holds every collision box (layer 1, "world").

const HALF_X := 9.0
const HALF_Z := 7.0
const WALL_H := 2.6
const WALL_T := 0.16
const DOOR_W := 1.5
const DOOR_H := 2.15

const GARDEN_W := 8.0
const GARDEN_DOOR_Z := 1.9
const PIT_SHIFT := 0.8

## Room centres and doorway centres (the test bot checks every one can be walked to without jumping).
const ROOMS := [["living room", Vector3(-6.0, 0, 4.0)], ["hall", Vector3(0.0, 0, 4.0)], ["kitchen", Vector3(6.0, 0, 4.5)],
	["bedroom", Vector3(-5.5, 0, -2.5)], ["playroom", Vector3(1.5, 0, -3.0)], ["bathroom", Vector3(6.5, 0, -2.5)],
	["garden", Vector3(-12.5, 0, 0.0)], ["garden shed", Vector3(-15.6, 0, 1.4)]]
const DOORS := [["living-bedroom", Vector3(-6.0, 0, 1.0)], ["hall-playroom", Vector3(0.5, 0, 1.0)], ["kitchen-bathroom", Vector3(6.5, 0, 1.0)],
	["living-hall", Vector3(-3.0, 0, 4.0)], ["hall-kitchen", Vector3(3.0, 0, 4.0)], ["bedroom-playroom", Vector3(-2.0, 0, -3.0)],
	["playroom-bathroom", Vector3(4.0, 0, -3.0)], ["living-garden", Vector3(-9.0, 0, 1.9)], ["shed door", Vector3(-14.4, 0, 1.4)]]

## Household objects a hider can turn into. Matching decoys stand all over the house.
const PROP_NAMES: Array[String] = ["lamp", "pot plant", "box", "teddy", "beach ball"]

## The jail: a cage in the hall's north-east corner. Found hiders wait inside; a free hider ringing the
## bell by its door lets everyone out.
const JAIL_POS := Vector3(2.05, 0, 6.15)
const JAIL_HALF := 0.65
const BELL_POS := Vector3(1.15, 0, 5.55)

## Where golden stars can appear in a STAR HUNT round (all on open floor).
const STAR_SPOTS: Array[Vector3] = [
	Vector3(-7.0, 0, 2.4), Vector3(-4.0, 0, 6.2), Vector3(-1.5, 0, 4.6), Vector3(4.5, 0, 1.8), Vector3(7.5, 0, 2.2),
	Vector3(4.6, 0, 5.4), Vector3(-6.5, 0, -1.0), Vector3(-3.0, 0, -5.0), Vector3(-6.2, 0, -4.6), Vector3(2.9, 0, -2.4),
	Vector3(-1.2, 0, -4.8), Vector3(3.0, 0, -6.2), Vector3(5.6, 0, -1.6), Vector3(7.6, 0, -3.8), Vector3(0.5, 0, 0.2),
	Vector3(-0.6, 0, 6.0), Vector3(-12.0, 0, 1.0), Vector3(-15.0, 0, -4.0), Vector3(-11.0, 0, 4.5),
]

## Decoy props: [kind, position, yaw].
const DECOYS := [
	[0, Vector3(-8.4, 0, 6.5), 0.0], [1, Vector3(-3.6, 0, 6.5), 0.3], [1, Vector3(-3.6, 0, 2.2), 1.0],
	[2, Vector3(-3.7, 0, 1.7), 0.4], [1, Vector3(2.5, 0, 1.6), 0.0], [0, Vector3(-2.5, 0, 1.6), 0.0],
	[2, Vector3(-2.4, 0, 2.9), 0.2], [1, Vector3(3.5, 0, 1.6), 2.0], [2, Vector3(8.4, 0, 1.7), 0.7],
	[0, Vector3(-8.5, 0, 0.4), 0.0], [1, Vector3(-2.6, 0, -6.4), 0.5], [2, Vector3(-2.6, 0, -0.2), 1.2],
	[2, Vector3(2.9, 0, -1.2), 0.3], [2, Vector3(-1.4, 0, -6.3), 0.9], [1, Vector3(3.4, 0, 0.3), 0.0],
	[1, Vector3(8.5, 0, 0.4), 0.2], [2, Vector3(4.6, 0, 0.4), 0.0], [0, Vector3(3.5, 0, -6.4), 0.0],
	[0, Vector3(8.4, 0, -1.4), 0.0], [2, Vector3(-5.1, 0, -1.2), 0.5],
	[3, Vector3(-6.8, 0, -2.2), 0.4], [3, Vector3(2.6, 0, -6.4), -0.3], [3, Vector3(-4.7, 0, 3.0), 0.2], [3, Vector3(-8.4, 0, -1.2), 1.4],
	[4, Vector3(-0.9, 0, -0.4), 0.0], [4, Vector3(3.2, 0, -1.4), 0.0], [4, Vector3(5.3, 0, -3.9), 0.0], [4, Vector3(-1.0, 0, 6.5), 0.0],
	[3, Vector3(8.5, 0, -2.0), 2.0],
	[1, Vector3(-10.0, 0, 6.3), 0.2], [1, Vector3(-16.3, 0, -2.6), 0.9], [1, Vector3(-11.8, 0, -6.3), 0.4], [4, Vector3(-12.6, 0, 3.4), 0.0],
	[2, Vector3(-16.2, 0, 6.2), 0.3], [4, Vector3(-10.4, 0, -3.6), 0.0], [1, Vector3(-14.0, 0, 4.6), 0.0],
]

## Good hiding places (used by the test bot and to place late-joining hiders).
const HIDE_SPOTS: Array[Vector3] = [
	Vector3(-6.0, 0, 6.3), Vector3(5.8, 0, 3.2), Vector3(-4.2, 0, -6.4), Vector3(7.4, 0, -6.4),
	Vector3(1.0, 0, -6.2), Vector3(-8.3, 0, -3.0), Vector3(4.2, 0, 5.6), Vector3(0.2, 0, -2.2),
	Vector3(-8.2, 0, 4.4), Vector3(8.2, 0, -3.5), Vector3(-5.0, 0, -4.4), Vector3(2.5, 0, -3.8),
	Vector3(-15.8, 0, 1.0), Vector3(-13.0, 0, -5.4), Vector3(-16.2, 0, 4.8), Vector3(-10.6, 0, 5.4),
]

const FLOOR_SHADER := """
shader_type spatial;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 c;
	if (wpos.z > 1.0 && wpos.x < -3.0) {          // living room: honey planks
		float plank = floor(wpos.z / 0.3);
		float o = fract(sin(plank * 12.9898) * 43758.5453);
		float seam = smoothstep(0.0, 0.04, fract(wpos.z / 0.3)) * smoothstep(0.0, 0.015, fract(wpos.x / 1.8 + o));
		c = mix(vec3(0.35, 0.22, 0.13), vec3(0.72, 0.5, 0.3) * (0.9 + 0.2 * o), seam);
	} else if (wpos.z > 1.0 && wpos.x > 3.0) {    // kitchen: checker tiles
		vec2 g = floor(wpos.xz / 0.5);
		c = mix(vec3(0.95, 0.93, 0.86), vec3(0.45, 0.68, 0.62), mod(g.x + g.y, 2.0));
	} else if (wpos.z > 1.0) {                     // hall: terracotta tiles
		vec2 f = fract(wpos.xz / 0.6);
		float grout = smoothstep(0.0, 0.04, f.x) * smoothstep(0.0, 0.04, f.y);
		c = mix(vec3(0.5, 0.4, 0.33), vec3(0.8, 0.5, 0.35), grout);
	} else if (wpos.x < -2.0) {                    // bedroom: soft blue carpet
		c = vec3(0.5, 0.6, 0.82) * (0.95 + 0.05 * sin(wpos.x * 30.0) * sin(wpos.z * 30.0));
	} else if (wpos.x < 4.0) {                     // playroom: puzzle mats
		vec2 g = floor(wpos.xz / 0.8);
		float k = mod(g.x * 3.0 + g.y * 5.0, 4.0);
		c = k < 1.0 ? vec3(1.0, 0.6, 0.55) : (k < 2.0 ? vec3(1.0, 0.85, 0.45) : (k < 3.0 ? vec3(0.55, 0.85, 0.6) : vec3(0.55, 0.75, 1.0)));
	} else {                                       // bathroom: little white tiles
		vec2 f = fract(wpos.xz / 0.3);
		float grout = smoothstep(0.0, 0.06, f.x) * smoothstep(0.0, 0.06, f.y);
		c = mix(vec3(0.55, 0.75, 0.8), vec3(0.92, 0.97, 1.0), grout);
	}
	ALBEDO = c;
	ROUGHNESS = 0.8;
}
"""

const WALL_SHADER := """
shader_type spatial;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 c;
	if (wpos.z > 1.0 && wpos.x < -3.0) { c = vec3(0.98, 0.86, 0.7); }
	else if (wpos.z > 1.0 && wpos.x > 3.0) { c = vec3(0.86, 0.95, 0.82); }
	else if (wpos.z > 1.0) { c = vec3(0.97, 0.92, 0.8); }
	else if (wpos.x < -2.0) { c = vec3(0.85, 0.86, 1.0); }
	else if (wpos.x < 4.0) { c = vec3(1.0, 0.9, 0.86); }
	else { c = vec3(0.82, 0.95, 0.97); }
	float stripe = step(0.5, fract((wpos.x + wpos.z) * 2.0));
	c *= 0.96 + 0.04 * stripe;
	float skirting = 1.0 - step(0.12, wpos.y);
	c = mix(c, vec3(0.98, 0.98, 0.96), skirting);
	ALBEDO = c;
	ROUGHNESS = 0.9;
}
"""


static func build(main: Node3D) -> Dictionary:
	var ctx := {"tools": {}, "mats": {}, "main": main}
	var body := StaticBody3D.new()
	body.name = "House"
	body.collision_layer = 1
	body.collision_mask = 0
	main.add_child(body)
	ctx["body"] = body
	_environment(main)
	_shell(ctx)
	_living_room(ctx)
	_hall(ctx)
	_kitchen(ctx)
	_bedroom(ctx)
	_playroom(ctx)
	_bathroom(ctx)
	_garden(ctx)
	var decoys: Array = []
	for d in DECOYS:
		var kind: int = d[0]
		var pos: Vector3 = d[1]
		var yaw: float = d[2]
		_bake_prop(ctx, kind, Transform3D(Basis(Vector3.UP, yaw), pos))
		decoys.append({"kind": kind, "pos": pos})
	var lights := _lights(main)
	_commit(ctx)
	var wkey := Color(0.6, 0.72, 1.0).to_html() + ("g%.1f" % 1.4)
	return {"decoys": decoys, "lights": lights, "window_mat": ctx["mats"].get(wkey)}


# --- Batching ------------------------------------------------------------------

static func mat(color: Color, glow: float = 0.0, rough: float = 0.75) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


static func _tool(ctx: Dictionary, key: String, material: Material) -> SurfaceTool:
	var tools: Dictionary = ctx["tools"]
	if not tools.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[key] = st
		var mats: Dictionary = ctx["mats"]
		mats[key] = material
	return tools[key]


## Non-glowing parts all go into ONE vertex-coloured mesh (one draw call for the whole house's furniture);
## glowing parts are grouped per colour (they need their own emissive material).
static func _add_mesh(ctx: Dictionary, mesh: Mesh, xf: Transform3D, color: Color, glow: float = 0.0) -> void:
	if glow <= 0.0:
		var vc := _tool(ctx, "vc", _vertex_material())
		var arr: Array = mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var raw = arr[Mesh.ARRAY_INDEX]
		var nb := xf.basis.inverse().transposed()
		vc.set_color(color)
		if raw is PackedInt32Array and not (raw as PackedInt32Array).is_empty():
			for i in (raw as PackedInt32Array):
				vc.set_normal((nb * n[i]).normalized())
				vc.add_vertex(xf * v[i])
		else:
			for i in v.size():
				vc.set_normal((nb * n[i]).normalized())
				vc.add_vertex(xf * v[i])
		return
	var key := color.to_html() + ("g%.1f" % glow)
	var st := _tool(ctx, key, mat(color, glow))
	st.append_from(mesh, 0, xf)


static func _vertex_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.75
	return m


static func _collide_box(ctx: Dictionary, size: Vector3, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = xf
	var body: StaticBody3D = ctx["body"]
	body.add_child(cs)


## A box: `pos` is its centre.
static func box(ctx: Dictionary, size: Vector3, pos: Vector3, color: Color, collide: bool = true, yaw: float = 0.0, glow: float = 0.0) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	_add_mesh(ctx, bm, xf, color, glow)
	if collide:
		_collide_box(ctx, size, xf)


static func cyl(ctx: Dictionary, r_top: float, r_bot: float, h: float, pos: Vector3, color: Color, collide: bool = true, glow: float = 0.0) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 12
	cm.rings = 1
	_add_mesh(ctx, cm, Transform3D(Basis(), pos), color, glow)
	if collide:
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = maxf(r_top, r_bot)
		shape.height = h
		cs.shape = shape
		cs.position = pos
		var body: StaticBody3D = ctx["body"]
		body.add_child(cs)


static func ball(ctx: Dictionary, r: float, pos: Vector3, color: Color, squash: float = 1.0, glow: float = 0.0) -> void:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	_add_mesh(ctx, sm, Transform3D(Basis().scaled(Vector3(1.0, squash, 1.0)), pos), color, glow)


static func _commit(ctx: Dictionary) -> void:
	var main: Node3D = ctx["main"]
	var tools: Dictionary = ctx["tools"]
	var mats: Dictionary = ctx["mats"]
	for key in tools.keys():
		var st: SurfaceTool = tools[key]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mats[key]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main.add_child(mi)


# --- Props (decoys and disguises look exactly the same) -----------------------

## A household object as separate meshes (for a disguised hider). Its origin is on the floor.
static func make_prop(kind: int, cache: Node) -> Node3D:
	var root := Node3D.new()
	for part in _prop_parts(kind, cache):
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		var c: Color = part[2]
		var g: float = part[3]
		mi.material_override = _prop_mat(c, g, cache)
		mi.transform = part[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


## Shared materials / meshes are cached as metadata on `cache` (the Main node), so they go away with the scene.
static func _prop_mat(c: Color, g: float, cache: Node) -> StandardMaterial3D:
	var key := "hs_prop_mat_%s_%d" % [c.to_html(), int(g * 10.0)]
	if not cache.has_meta(key):
		cache.set_meta(key, mat(c, g))
	return cache.get_meta(key)


static func _bake_prop(ctx: Dictionary, kind: int, xf: Transform3D) -> void:
	for part in _prop_parts(kind, ctx["main"]):
		var m: Mesh = part[0]
		var local: Transform3D = part[1]
		_add_mesh(ctx, m, xf * local, part[2], part[3])
	if kind == 2:
		_collide_box(ctx, Vector3(0.66, 0.66, 0.66), xf * Transform3D(Basis(), Vector3(0, 0.33, 0)))
	else:
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = [0.22, 0.3, 0.3, 0.3, 0.33][kind]
		shape.height = [1.2, 1.2, 1.2, 0.9, 0.66][kind]
		cs.shape = shape
		cs.position = xf.origin + Vector3(0, shape.height / 2.0, 0)
		var body: StaticBody3D = ctx["body"]
		body.add_child(cs)


## [mesh, transform, colour, glow] for each part. Cached meshes (shared by every copy).
static func _prop_parts(kind: int, cache: Node) -> Array:
	var key := "hs_prop_parts_%d" % kind
	if cache.has_meta(key):
		return cache.get_meta(key)
	var parts: Array = []
	match kind:
		0:  # floor lamp with a cream shade
			parts.append([_cyl_mesh(0.18, 0.2, 0.05), Transform3D(Basis(), Vector3(0, 0.025, 0)), Color(0.35, 0.24, 0.16), 0.0])
			parts.append([_cyl_mesh(0.025, 0.025, 1.2), Transform3D(Basis(), Vector3(0, 0.6, 0)), Color(0.75, 0.6, 0.3), 0.0])
			parts.append([_cyl_mesh(0.17, 0.3, 0.36), Transform3D(Basis(), Vector3(0, 1.32, 0)), Color(1.0, 0.92, 0.7), 0.6])
		1:  # pot plant
			parts.append([_cyl_mesh(0.25, 0.18, 0.4), Transform3D(Basis(), Vector3(0, 0.2, 0)), Color(0.85, 0.45, 0.28), 0.0])
			parts.append([_sphere_mesh(0.38), Transform3D(Basis(), Vector3(0, 0.72, 0)), Color(0.3, 0.68, 0.32), 0.0])
			parts.append([_sphere_mesh(0.24), Transform3D(Basis(), Vector3(0.14, 1.0, 0.05)), Color(0.42, 0.8, 0.38), 0.0])
		3:  # a big friendly teddy bear, sitting
			var fur := Color(0.72, 0.48, 0.3)
			var muzzle := Color(0.95, 0.8, 0.62)
			parts.append([_sphere_mesh(0.3), Transform3D(Basis.from_scale(Vector3(1.0, 1.05, 0.9)), Vector3(0, 0.3, 0)), fur, 0.0])
			parts.append([_sphere_mesh(0.22), Transform3D(Basis(), Vector3(0, 0.72, -0.02)), fur, 0.0])
			parts.append([_sphere_mesh(0.09), Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 0.8)), Vector3(0, 0.68, -0.2)), muzzle, 0.0])
			parts.append([_sphere_mesh(0.08), Transform3D(Basis(), Vector3(-0.16, 0.9, 0.0)), fur, 0.0])
			parts.append([_sphere_mesh(0.08), Transform3D(Basis(), Vector3(0.16, 0.9, 0.0)), fur, 0.0])
			parts.append([_sphere_mesh(0.11), Transform3D(Basis.from_scale(Vector3(0.8, 1.0, 1.3)), Vector3(-0.17, 0.09, -0.2)), muzzle, 0.0])
			parts.append([_sphere_mesh(0.11), Transform3D(Basis.from_scale(Vector3(0.8, 1.0, 1.3)), Vector3(0.17, 0.09, -0.2)), muzzle, 0.0])
			parts.append([_sphere_mesh(0.035), Transform3D(Basis(), Vector3(0, 0.74, -0.27)), Color(0.15, 0.1, 0.08), 0.0])
		4:  # a big stripy beach ball
			parts.append([_sphere_mesh(0.33), Transform3D(Basis(), Vector3(0, 0.33, 0)), Color(1.0, 0.95, 0.9), 0.0])
			var band := _sphere_mesh(0.335)
			parts.append([band, Transform3D(Basis.from_scale(Vector3(0.35, 1.0, 1.0)), Vector3(0, 0.33, 0)), Color(1.0, 0.35, 0.3), 0.0])
			parts.append([band, Transform3D(Basis(Vector3.UP, PI / 2.0) * Basis.from_scale(Vector3(0.35, 1.0, 1.0)), Vector3(0, 0.33, 0)), Color(0.3, 0.6, 1.0), 0.0])
			parts.append([_sphere_mesh(0.07), Transform3D(Basis(), Vector3(0, 0.66, 0)), Color(1.0, 0.85, 0.2), 0.0])
		_:  # cardboard box with tape
			var bm := BoxMesh.new()
			bm.size = Vector3(0.66, 0.66, 0.66)
			parts.append([bm, Transform3D(Basis(), Vector3(0, 0.33, 0)), Color(0.78, 0.6, 0.38), 0.0])
			var tm := BoxMesh.new()
			tm.size = Vector3(0.68, 0.02, 0.14)
			parts.append([tm, Transform3D(Basis(), Vector3(0, 0.665, 0)), Color(0.92, 0.82, 0.6), 0.0])
	cache.set_meta(key, parts)
	return parts


static func _cyl_mesh(r_top: float, r_bot: float, h: float) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 12
	cm.rings = 1
	return cm


static func _sphere_mesh(r: float) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	return sm


# --- Shell: floor, walls, ceiling, windows -------------------------------------

static func _environment(main: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.45, 0.55, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.9, 0.78)
	e.ambient_light_energy = 0.65
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_bloom = 0.05
	env.environment = e
	main.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.light_energy = 0.45
	sun.shadow_enabled = false
	sun.rotation_degrees = Vector3(-60, 30, 0)
	main.add_child(sun)


static func _shell(ctx: Dictionary) -> void:
	var main: Node3D = ctx["main"]
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF_X * 2.0, HALF_Z * 2.0)
	floor_mi.mesh = pm
	var fm := ShaderMaterial.new()
	fm.shader = Shader.new()
	fm.shader.code = FLOOR_SHADER
	floor_mi.material_override = fm
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(floor_mi)
	_collide_box(ctx, Vector3(HALF_X * 2.0 + 2.0, 0.2, HALF_Z * 2.0 + 2.0), Transform3D(Basis(), Vector3(0, -0.1, 0)))
	box(ctx, Vector3(HALF_X * 2.0 + 0.4, 0.1, HALF_Z * 2.0 + 0.4), Vector3(0, WALL_H + 0.05, 0), Color(0.98, 0.96, 0.92))
	# Walls (one shader-coloured mesh: each room gets its own wallpaper).
	var wctx := {"tools": {}, "mats": {}, "main": main, "body": ctx["body"]}
	_wall_x(wctx, -HALF_Z, -HALF_X, HALF_X, [])
	_wall_x(wctx, HALF_Z, -HALF_X, HALF_X, [])
	_wall_z(wctx, -HALF_X, -HALF_Z, HALF_Z, [GARDEN_DOOR_Z])
	_wall_z(wctx, HALF_X, -HALF_Z, HALF_Z, [])
	_wall_x(wctx, 1.0, -HALF_X, HALF_X, [-6.0, 0.5, 6.5])
	_wall_z(wctx, -3.0, 1.0, HALF_Z, [4.0])
	_wall_z(wctx, 3.0, 1.0, HALF_Z, [4.0])
	_wall_z(wctx, -2.0, -HALF_Z, 1.0, [-3.0])
	_wall_z(wctx, 4.0, -HALF_Z, 1.0, [-3.0])
	var wm := ShaderMaterial.new()
	wm.shader = Shader.new()
	wm.shader.code = WALL_SHADER
	for key in wctx["tools"].keys():
		var st: SurfaceTool = wctx["tools"][key]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = wm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main.add_child(mi)
	# Evening windows (glowing, can't be walked through: they're on the outer walls).
	var sky := Color(0.6, 0.72, 1.0)
	var frame := Color(1.0, 1.0, 0.97)
	for w in [[Vector3(-8.9, 1.55, 3.6), true], [Vector3(-8.9, 1.55, -2.5), true], [Vector3(8.9, 1.65, 3.4), true],
			[Vector3(8.9, 1.6, -3.6), true], [Vector3(-0.6, 1.8, -6.9), false], [Vector3(-6.0, 1.55, 6.9), false],
			[Vector3(6.6, 1.6, 6.9), false], [Vector3(-5.5, 1.6, -6.9), false]]:
		var p: Vector3 = w[0]
		var side: bool = w[1]
		var glass := Vector3(0.05, 1.0, 1.3) if side else Vector3(1.3, 1.0, 0.05)
		var rim := Vector3(0.03, 1.14, 1.44) if side else Vector3(1.44, 1.14, 0.03)
		box(ctx, rim, p, frame, false)
		box(ctx, glass, p, sky, false, 0.0, 1.4)
		box(ctx, Vector3(0.07, 1.0, 0.06) if side else Vector3(0.06, 1.0, 0.07), p, frame, false)


static func _wall_piece(ctx: Dictionary, size: Vector3, pos: Vector3) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var st := _tool(ctx, "wall", null)
	var xf := Transform3D(Basis(), pos)
	st.append_from(bm, 0, xf)
	_collide_box(ctx, size, xf)


## A wall along x at `z` from x0 to x1, with door openings centred at `doors`.
static func _wall_x(ctx: Dictionary, z: float, x0: float, x1: float, doors: Array) -> void:
	var a := x0 - WALL_T / 2.0
	var cuts: Array = doors.duplicate()
	cuts.sort()
	for d in cuts:
		var dx: float = d
		var b := dx - DOOR_W / 2.0
		if b > a:
			_wall_piece(ctx, Vector3(b - a, WALL_H, WALL_T), Vector3((a + b) / 2.0, WALL_H / 2.0, z))
		_wall_piece(ctx, Vector3(DOOR_W, WALL_H - DOOR_H, WALL_T), Vector3(dx, (WALL_H + DOOR_H) / 2.0, z))
		a = dx + DOOR_W / 2.0
	var e := x1 + WALL_T / 2.0
	_wall_piece(ctx, Vector3(e - a, WALL_H, WALL_T), Vector3((a + e) / 2.0, WALL_H / 2.0, z))


static func _wall_z(ctx: Dictionary, x: float, z0: float, z1: float, doors: Array) -> void:
	var a := z0
	var cuts: Array = doors.duplicate()
	cuts.sort()
	for d in cuts:
		var dz: float = d
		var b := dz - DOOR_W / 2.0
		if b > a:
			_wall_piece(ctx, Vector3(WALL_T, WALL_H, b - a), Vector3(x, WALL_H / 2.0, (a + b) / 2.0))
		_wall_piece(ctx, Vector3(WALL_T, WALL_H - DOOR_H, DOOR_W), Vector3(x, (WALL_H + DOOR_H) / 2.0, dz))
		a = dz + DOOR_W / 2.0
	_wall_piece(ctx, Vector3(WALL_T, WALL_H, z1 - a), Vector3(x, WALL_H / 2.0, (a + z1) / 2.0))


static func _lights(main: Node3D) -> Array:
	var out: Array = []
	for p in [Vector3(-6, 2.3, 4), Vector3(0, 2.3, 4), Vector3(6, 2.3, 4), Vector3(-5.5, 2.3, -3), Vector3(1, 2.3, -3), Vector3(6.5, 2.3, -3)]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.85, 0.65)
		l.light_energy = 1.1
		l.omni_range = 6.5
		l.omni_attenuation = 1.2
		l.shadow_enabled = false
		main.add_child(l)
		l.position = p
		out.append(l)
	return out


# --- Rooms ---------------------------------------------------------------------

static func _ceiling_lamp(ctx: Dictionary, x: float, z: float) -> void:
	cyl(ctx, 0.02, 0.02, 0.3, Vector3(x, WALL_H - 0.15, z), Color(0.4, 0.35, 0.3), false)
	ball(ctx, 0.2, Vector3(x, WALL_H - 0.38, z), Color(1.0, 0.9, 0.7), 1.0, 2.0)


static func _picture(ctx: Dictionary, pos: Vector3, along_x: bool, color: Color) -> void:
	var s := Vector3(0.7, 0.5, 0.04) if along_x else Vector3(0.04, 0.5, 0.7)
	box(ctx, s, pos, Color(0.55, 0.38, 0.22), false)
	box(ctx, s * Vector3(0.8, 0.8, 1.0) if along_x else s * Vector3(1.0, 0.8, 0.8), pos + (Vector3(0, 0, 0.012) * signf(-pos.z) if along_x else Vector3(0.012, 0, 0) * signf(-pos.x)), color, false, 0.0, 0.3)


static func _living_room(ctx: Dictionary) -> void:
	var sofa := Color(0.85, 0.42, 0.45)
	box(ctx, Vector3(3.0, 0.02, 2.4), Vector3(-6.0, 0.01, 3.6), Color(0.95, 0.75, 0.45), false)
	box(ctx, Vector3(2.4, 0.45, 0.9), Vector3(-6.0, 0.225, 5.0), sofa)
	box(ctx, Vector3(2.4, 0.95, 0.25), Vector3(-6.0, 0.475, 5.55), sofa.darkened(0.1))
	box(ctx, Vector3(0.25, 0.65, 0.95), Vector3(-7.3, 0.325, 5.05), sofa.darkened(0.15))
	box(ctx, Vector3(0.25, 0.65, 0.95), Vector3(-4.7, 0.325, 5.05), sofa.darkened(0.15))
	for x in [-6.6, -5.4]:
		box(ctx, Vector3(0.5, 0.35, 0.15), Vector3(x, 0.62, 5.33), Color(1.0, 0.85, 0.5), false, 0.2)
	# The family cat, asleep on the sofa.
	ball(ctx, 0.22, Vector3(-6.9, 0.58, 4.85), Color(1.0, 0.62, 0.3), 0.6)
	ball(ctx, 0.12, Vector3(-6.66, 0.6, 4.78), Color(1.0, 0.62, 0.3))
	box(ctx, Vector3(1.2, 0.4, 0.7), Vector3(-6.0, 0.2, 3.4), Color(0.6, 0.4, 0.25))
	# TV corner (kept clear of the bedroom doorway at x -6.75..-5.25: a kid got stuck in the bedroom once).
	box(ctx, Vector3(1.7, 0.5, 0.45), Vector3(-4.25, 0.25, 1.4), Color(0.45, 0.32, 0.22))
	box(ctx, Vector3(1.5, 0.9, 0.08), Vector3(-4.25, 0.95, 1.38), Color(0.12, 0.14, 0.2), false, 0.0, 0.0)
	box(ctx, Vector3(1.35, 0.78, 0.02), Vector3(-4.25, 0.95, 1.43), Color(0.35, 0.6, 0.9), false, 0.0, 0.8)
	box(ctx, Vector3(0.95, 0.45, 0.95), Vector3(-8.2, 0.225, 3.45), Color(0.45, 0.62, 0.85))
	box(ctx, Vector3(0.25, 1.0, 0.95), Vector3(-8.65, 0.5, 3.45), Color(0.4, 0.55, 0.78))
	box(ctx, Vector3(0.35, 2.0, 1.4), Vector3(-8.72, 1.0, 5.6), Color(0.55, 0.38, 0.24))
	var book_cols: Array[Color] = [Color(0.9, 0.3, 0.3), Color(0.3, 0.6, 0.9), Color(0.95, 0.8, 0.3), Color(0.4, 0.8, 0.45)]
	for shelf in 4:
		for b in 4:
			box(ctx, Vector3(0.05, 0.3, 0.25), Vector3(-8.5, 0.25 + shelf * 0.48, 5.05 + b * 0.32), book_cols[(shelf + b) % 4], false)
	_picture(ctx, Vector3(-6.0, 1.7, 6.9), true, Color(0.95, 0.75, 0.5))
	_ceiling_lamp(ctx, -6.0, 4.0)


static func _hall(ctx: Dictionary) -> void:
	box(ctx, Vector3(1.0, 2.1, 0.06), Vector3(0.0, 1.05, 6.89), Color(0.55, 0.33, 0.2), false)
	ball(ctx, 0.05, Vector3(0.35, 1.0, 6.84), Color(1.0, 0.85, 0.3), 1.0, 0.5)
	box(ctx, Vector3(1.6, 0.02, 1.0), Vector3(0.0, 0.01, 6.1), Color(0.85, 0.35, 0.3), false)
	box(ctx, Vector3(1.2, 0.45, 0.4), Vector3(-2.2, 0.225, 6.6), Color(0.62, 0.45, 0.3))
	cyl(ctx, 0.04, 0.04, 1.8, Vector3(-2.55, 0.9, 5.2), Color(0.5, 0.35, 0.25))
	cyl(ctx, 0.25, 0.25, 0.04, Vector3(-2.55, 0.02, 5.2), Color(0.5, 0.35, 0.25), false)
	ball(ctx, 0.25, Vector3(-2.55, 1.5, 5.15), Color(0.3, 0.5, 0.9), 1.4)
	ball(ctx, 0.2, Vector3(-2.6, 1.65, 5.3), Color(0.95, 0.8, 0.3), 1.2)
	_jail(ctx)
	_picture(ctx, Vector3(-3.0 + 0.1, 1.6, 2.4), false, Color(0.6, 0.8, 1.0))
	_ceiling_lamp(ctx, 0.0, 4.0)


## The jail cage: bars all round (no way in except being found), a stripy roof and a big bell by the door.
static func _jail(ctx: Dictionary) -> void:
	var c := JAIL_POS
	var h := JAIL_HALF
	var bar := Color(0.95, 0.75, 0.3)
	for i in 8:
		var t := (i + 0.5) / 8.0
		for side in 4:
			var p := Vector3.ZERO
			match side:
				0:
					p = c + Vector3(-h + t * 2.0 * h, 0.75, -h)
				1:
					p = c + Vector3(-h + t * 2.0 * h, 0.75, h)
				2:
					p = c + Vector3(-h, 0.75, -h + t * 2.0 * h)
				_:
					p = c + Vector3(h, 0.75, -h + t * 2.0 * h)
			cyl(ctx, 0.025, 0.025, 1.5, p, bar, false)
	box(ctx, Vector3(h * 2.0 + 0.1, 0.08, h * 2.0 + 0.1), c + Vector3(0, 1.52, 0), Color(1.0, 0.45, 0.45), false)
	box(ctx, Vector3(h * 2.0 + 0.1, 0.05, h * 2.0 + 0.1), c + Vector3(0, 0.025, 0), Color(0.6, 0.45, 0.3), false)
	# Solid (invisible) sides so nobody wanders in or out.
	for side in 4:
		var horiz := side < 2
		var off := (-h if side % 2 == 0 else h)
		var size := Vector3(h * 2.0, 1.5, 0.06) if horiz else Vector3(0.06, 1.5, h * 2.0)
		var at := c + (Vector3(0, 0.75, off) if horiz else Vector3(off, 0.75, 0))
		_collide_box(ctx, size, Transform3D(Basis(), at))
	# The bell post.
	cyl(ctx, 0.04, 0.05, 1.1, BELL_POS + Vector3(0, 0.55, 0), Color(0.45, 0.32, 0.22))
	cyl(ctx, 0.06, 0.16, 0.2, BELL_POS + Vector3(0, 1.15, 0), Color(1.0, 0.85, 0.2), false, 0.6)
	ball(ctx, 0.04, BELL_POS + Vector3(0, 1.03, 0), Color(0.5, 0.35, 0.2))


static func _kitchen(ctx: Dictionary) -> void:
	var counter := Color(0.4, 0.62, 0.55)
	var top := Color(0.96, 0.94, 0.88)
	box(ctx, Vector3(0.7, 0.88, 3.7), Vector3(8.6, 0.44, 4.35), counter)
	box(ctx, Vector3(0.76, 0.05, 3.76), Vector3(8.58, 0.9, 4.35), top, false)
	box(ctx, Vector3(3.0, 0.88, 0.7), Vector3(6.0, 0.44, 6.6), counter)
	box(ctx, Vector3(3.06, 0.05, 0.76), Vector3(6.0, 0.9, 6.58), top, false)
	cyl(ctx, 0.18, 0.18, 0.12, Vector3(6.0, 0.98, 6.5), Color(0.85, 0.3, 0.25), false)
	box(ctx, Vector3(0.8, 2.0, 0.75), Vector3(3.55, 1.0, 6.5), Color(0.95, 0.97, 1.0))
	box(ctx, Vector3(0.04, 0.5, 0.04), Vector3(3.9, 1.2, 6.1), Color(0.6, 0.6, 0.65), false)
	# Big farmhouse table: tall enough for a hider to crawl under.
	box(ctx, Vector3(2.0, 0.08, 1.2), Vector3(5.8, 1.0, 3.2), Color(0.72, 0.5, 0.3))
	box(ctx, Vector3(2.2, 0.02, 1.5), Vector3(5.8, 1.05, 3.2), Color(0.95, 0.5, 0.5), false)
	for lx in [4.9, 6.7]:
		for lz in [2.7, 3.7]:
			box(ctx, Vector3(0.1, 0.96, 0.1), Vector3(lx, 0.48, lz), Color(0.6, 0.4, 0.24))
	for cx in [4.2, 7.4]:
		box(ctx, Vector3(0.5, 0.5, 0.5), Vector3(cx, 0.25, 3.2), Color(0.95, 0.85, 0.5))
		box(ctx, Vector3(0.06, 0.6, 0.5), Vector3(cx + (-0.25 if cx < 5.0 else 0.25), 0.8, 3.2), Color(0.95, 0.85, 0.5), false)
	_ceiling_lamp(ctx, 6.0, 4.0)


static func _bedroom(ctx: Dictionary) -> void:
	box(ctx, Vector3(2.0, 0.55, 2.4), Vector3(-7.6, 0.275, -5.6), Color(0.95, 0.95, 1.0))
	box(ctx, Vector3(2.04, 0.12, 1.6), Vector3(-7.6, 0.6, -5.15), Color(0.5, 0.75, 1.0), false)
	box(ctx, Vector3(0.7, 0.15, 0.4), Vector3(-7.6, 0.66, -6.4), Color(1.0, 1.0, 1.0), false)
	box(ctx, Vector3(2.0, 1.1, 0.12), Vector3(-7.6, 0.55, -6.82), Color(0.6, 0.45, 0.75))
	# Open wardrobe against the north wall: step inside to hide.
	var wood := Color(0.7, 0.55, 0.85)
	box(ctx, Vector3(1.4, 2.1, 0.08), Vector3(-4.2, 1.05, -6.86), wood)
	box(ctx, Vector3(0.08, 2.1, 0.8), Vector3(-4.94, 1.05, -6.45), wood)
	box(ctx, Vector3(0.08, 2.1, 0.8), Vector3(-3.46, 1.05, -6.45), wood)
	box(ctx, Vector3(1.56, 0.08, 0.8), Vector3(-4.2, 2.1, -6.45), wood)
	box(ctx, Vector3(0.6, 2.0, 0.05), Vector3(-5.3, 1.0, -5.85), wood.darkened(0.1), true, 0.9)
	for i in 3:
		box(ctx, Vector3(0.3, 0.5, 0.04), Vector3(-4.55 + i * 0.35, 1.5, -6.55), [Color(1, 0.6, 0.6), Color(0.6, 1, 0.7), Color(1, 0.9, 0.5)][i], false)
	box(ctx, Vector3(0.5, 0.55, 0.5), Vector3(-6.2, 0.275, -6.55), Color(0.85, 0.7, 0.5))
	box(ctx, Vector3(1.0, 0.55, 0.5), Vector3(-7.6, 0.275, -3.9), Color(0.95, 0.6, 0.3))
	box(ctx, Vector3(2.6, 0.02, 1.6), Vector3(-6.0, 0.01, -2.4), Color(1.0, 0.85, 0.9), false)
	_picture(ctx, Vector3(-8.9 + 0.0, 1.7, -5.6), false, Color(1.0, 0.8, 0.9))
	_ceiling_lamp(ctx, -5.5, -3.0)


static func _playroom(ctx: Dictionary) -> void:
	# Play fort: three walls and a stripy roof.
	box(ctx, Vector3(2.0, 1.2, 0.12), Vector3(1.0, 0.6, -6.8), Color(1.0, 0.75, 0.4))
	box(ctx, Vector3(0.12, 1.2, 1.4), Vector3(0.0, 0.6, -6.2), Color(0.5, 0.8, 1.0))
	box(ctx, Vector3(0.12, 1.2, 1.4), Vector3(2.0, 0.6, -6.2), Color(0.5, 0.8, 1.0))
	box(ctx, Vector3(2.3, 0.1, 1.6), Vector3(1.0, 1.25, -6.2), Color(1.0, 0.45, 0.5))
	box(ctx, Vector3(0.6, 0.4, 0.04), Vector3(1.0, 1.45, -5.5), Color(1.0, 0.95, 0.5), false)
	# Ball pit (low walls you can see over).
	# (Kept a metre clear of the bedroom doorway at x = -2.)
	var pit := Color(0.4, 0.75, 0.95)
	var px := PIT_SHIFT
	box(ctx, Vector3(2.2, 0.5, 0.12), Vector3(-0.6 + px, 0.25, -3.3), pit)
	box(ctx, Vector3(2.2, 0.5, 0.12), Vector3(-0.6 + px, 0.25, -1.1), pit)
	box(ctx, Vector3(0.12, 0.5, 2.2), Vector3(-1.7 + px, 0.25, -2.2), pit)
	box(ctx, Vector3(0.12, 0.5, 0.8), Vector3(0.5 + px, 0.25, -2.9), pit)
	var cols: Array[Color] = [Color(1, 0.4, 0.4), Color(1, 0.85, 0.3), Color(0.4, 0.85, 0.5), Color(0.5, 0.6, 1.0)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 26:
		var p := Vector3(rng.randf_range(-1.55, 0.35) + PIT_SHIFT, 0.1 + rng.randf() * 0.15, rng.randf_range(-3.15, -1.25))
		ball(ctx, 0.12, p, cols[i % 4])
	# Bean bags and toy blocks.
	ball(ctx, 0.5, Vector3(3.3, 0.3, -5.6), Color(0.6, 0.45, 0.9), 0.6)
	ball(ctx, 0.5, Vector3(3.2, 0.3, -4.4), Color(0.95, 0.55, 0.3), 0.6)
	_collide_box(ctx, Vector3(0.8, 0.5, 0.8), Transform3D(Basis(), Vector3(3.3, 0.25, -5.6)))
	_collide_box(ctx, Vector3(0.8, 0.5, 0.8), Transform3D(Basis(), Vector3(3.2, 0.25, -4.4)))
	for i in 5:
		box(ctx, Vector3(0.3, 0.3, 0.3), Vector3(1.4 + (i % 3) * 0.34, 0.15 + (i / 3) * 0.3, -0.4), cols[i % 4], i < 3)
	_picture(ctx, Vector3(-1.9, 1.6, -4.8), false, Color(0.7, 1.0, 0.75))
	_ceiling_lamp(ctx, 1.0, -3.0)


static func _bathroom(ctx: Dictionary) -> void:
	var tub := Color(0.98, 0.98, 1.0)
	box(ctx, Vector3(2.0, 0.6, 0.1), Vector3(7.4, 0.3, -6.85), tub)
	box(ctx, Vector3(0.1, 0.6, 1.0), Vector3(6.45, 0.3, -6.4), tub)
	box(ctx, Vector3(0.1, 0.6, 1.0), Vector3(8.35, 0.3, -6.4), tub)
	box(ctx, Vector3(1.2, 0.6, 0.1), Vector3(7.0, 0.3, -5.95), tub)
	box(ctx, Vector3(0.75, 0.12, 0.1), Vector3(7.98, 0.06, -5.95), tub, false)
	box(ctx, Vector3(1.8, 0.04, 0.8), Vector3(7.4, 0.35, -6.4), Color(0.6, 0.85, 1.0), false)
	ball(ctx, 0.08, Vector3(7.8, 0.42, -6.3), Color(1.0, 0.9, 0.2))
	# Shower curtain (hides most of the tub; the gap is at the tap end).
	box(ctx, Vector3(1.2, 1.9, 0.03), Vector3(7.0, 1.55, -5.9), Color(0.6, 0.9, 0.85))
	cyl(ctx, 0.015, 0.015, 2.0, Vector3(7.4, 2.5, -5.9), Color(0.8, 0.8, 0.85), false)
	box(ctx, Vector3(0.6, 0.85, 0.45), Vector3(5.0, 0.425, -6.72), Color(0.95, 0.95, 0.97))
	box(ctx, Vector3(0.7, 0.8, 0.03), Vector3(5.0, 1.6, -6.9), Color(0.75, 0.9, 1.0), false, 0.0, 0.6)
	cyl(ctx, 0.22, 0.2, 0.42, Vector3(4.75, 0.21, -4.6), Color(1.0, 1.0, 1.0))
	box(ctx, Vector3(0.2, 0.55, 0.45), Vector3(4.2, 0.6, -4.6), Color(0.95, 0.95, 1.0))
	box(ctx, Vector3(1.6, 0.02, 0.9), Vector3(6.4, 0.01, -3.5), Color(0.95, 0.7, 0.8), false)
	_ceiling_lamp(ctx, 6.5, -3.0)



# --- The back garden ------------------------------------------------------------

static func _garden(ctx: Dictionary) -> void:
	var main: Node3D = ctx["main"]
	var x0 := -HALF_X - GARDEN_W
	var cx := -HALF_X - GARDEN_W / 2.0
	# Lawn with mowing stripes.
	var lawn := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(GARDEN_W, HALF_Z * 2.0)
	lawn.mesh = pm
	var gm := ShaderMaterial.new()
	gm.shader = Shader.new()
	gm.shader.code = """
shader_type spatial;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float stripe = step(0.5, fract(wpos.z / 1.4));
	float n = fract(sin(dot(floor(wpos.xz * 6.0), vec2(12.9898, 78.233))) * 43758.5453);
	ALBEDO = mix(vec3(0.36, 0.66, 0.3), vec3(0.42, 0.74, 0.34), stripe) * (0.93 + 0.1 * n);
	ROUGHNESS = 0.95;
}
"""
	lawn.material_override = gm
	lawn.position = Vector3(cx, 0.0, 0.0)
	lawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(lawn)
	_collide_box(ctx, Vector3(GARDEN_W + 1.0, 0.2, HALF_Z * 2.0 + 2.0), Transform3D(Basis(), Vector3(cx - 0.5, -0.1, 0)))
	# Doorstep and a stepping-stone path from the garden door.
	box(ctx, Vector3(0.6, 0.03, DOOR_W), Vector3(-HALF_X - 0.3, 0.015, GARDEN_DOOR_Z), Color(0.75, 0.7, 0.65), false)
	for i in 5:
		ball(ctx, 0.28, Vector3(-10.0 - i * 0.9, 0.0, GARDEN_DOOR_Z - 0.2 * i), Color(0.78, 0.76, 0.72), 0.12)
	# Picket fence (with invisible walls) round the three open sides.
	var picket := Color(0.98, 0.97, 0.93)
	_collide_box(ctx, Vector3(0.2, 2.0, HALF_Z * 2.0), Transform3D(Basis(), Vector3(x0, 1.0, 0)))
	_collide_box(ctx, Vector3(GARDEN_W, 2.0, 0.2), Transform3D(Basis(), Vector3(cx, 1.0, -HALF_Z)))
	_collide_box(ctx, Vector3(GARDEN_W, 2.0, 0.2), Transform3D(Basis(), Vector3(cx, 1.0, HALF_Z)))
	for z in range(0, 28):
		box(ctx, Vector3(0.06, 1.0, 0.18), Vector3(x0, 0.5, -HALF_Z + 0.25 + z * 0.5), picket, false)
	for i in range(0, 16):
		box(ctx, Vector3(0.18, 1.0, 0.06), Vector3(x0 + 0.25 + i * 0.5, 0.5, -HALF_Z), picket, false)
		box(ctx, Vector3(0.18, 1.0, 0.06), Vector3(x0 + 0.25 + i * 0.5, 0.5, HALF_Z), picket, false)
	box(ctx, Vector3(0.05, 0.08, HALF_Z * 2.0), Vector3(x0, 0.75, 0), picket, false)
	box(ctx, Vector3(GARDEN_W, 0.08, 0.05), Vector3(cx, 0.75, -HALF_Z), picket, false)
	box(ctx, Vector3(GARDEN_W, 0.08, 0.05), Vector3(cx, 0.75, HALF_Z), picket, false)
	# Garden shed: step inside to hide (door opening faces the house).
	var shed := Color(0.55, 0.75, 0.6)
	var roof := Color(0.75, 0.35, 0.3)
	var sc := Vector3(-15.6, 0, 1.4)
	box(ctx, Vector3(2.2, 2.0, 0.1), sc + Vector3(0, 1.0, -1.1), shed)
	box(ctx, Vector3(2.2, 2.0, 0.1), sc + Vector3(0, 1.0, 1.1), shed)
	box(ctx, Vector3(0.1, 2.0, 2.3), sc + Vector3(-1.1, 1.0, 0), shed)
	box(ctx, Vector3(0.1, 2.0, 0.55), sc + Vector3(1.1, 1.0, -0.875), shed)
	box(ctx, Vector3(0.1, 2.0, 0.55), sc + Vector3(1.1, 1.0, 0.875), shed)
	box(ctx, Vector3(0.1, 0.4, 1.2), sc + Vector3(1.1, 1.8, 0), shed, false)
	box(ctx, Vector3(2.6, 0.12, 2.7), sc + Vector3(0, 2.06, 0), roof, false)
	box(ctx, Vector3(0.6, 1.6, 0.05), sc + Vector3(1.45, 0.8, -0.85), shed.darkened(0.15), false, 0.6)
	box(ctx, Vector3(0.8, 0.8, 0.5), sc + Vector3(-0.6, 0.4, -0.75), Color(0.7, 0.5, 0.3))
	cyl(ctx, 0.12, 0.12, 0.9, sc + Vector3(-0.75, 0.45, 0.75), Color(0.4, 0.4, 0.45), false)
	# Hedges to crouch behind.
	var hedge := Color(0.24, 0.52, 0.26)
	for hd in [[Vector3(-13.0, 0.5, -4.6), Vector3(2.4, 1.0, 0.6)], [Vector3(-10.6, 0.5, 4.6), Vector3(1.8, 1.0, 0.6)],
			[Vector3(-16.4, 0.5, 4.0), Vector3(0.6, 1.0, 1.8)]]:
		var at: Vector3 = hd[0]
		var size: Vector3 = hd[1]
		box(ctx, size, at, hedge)
		for k in 3:
			ball(ctx, 0.32, at + Vector3((k - 1) * size.x * 0.3, 0.45, (k - 1) * size.z * 0.3), hedge.lightened(0.08), 0.8)
	# Trees: chunky trunks and fluffy tops.
	for tr in [Vector3(-15.8, 0, -5.4), Vector3(-11.0, 0, -1.8), Vector3(-15.2, 0, 5.9)]:
		var at: Vector3 = tr
		cyl(ctx, 0.18, 0.26, 2.2, at + Vector3(0, 1.1, 0), Color(0.5, 0.33, 0.2))
		ball(ctx, 1.0, at + Vector3(0, 2.7, 0), Color(0.3, 0.62, 0.3), 0.9)
		ball(ctx, 0.7, at + Vector3(0.5, 3.2, 0.2), Color(0.36, 0.7, 0.34), 0.9)
		ball(ctx, 0.12, at + Vector3(-0.6, 2.4, -0.6), Color(1.0, 0.3, 0.3))
	# Slide: steps, a platform and a shiny chute.
	var sl := Vector3(-12.8, 0, 5.6)
	box(ctx, Vector3(0.7, 1.2, 0.7), sl + Vector3(0, 0.6, 0), Color(0.95, 0.6, 0.25))
	var chute := BoxMesh.new()
	chute.size = Vector3(0.6, 0.06, 2.2)
	_add_mesh(ctx, chute, Transform3D(Basis(Vector3.RIGHT, -0.5), sl + Vector3(0, 0.62, -1.2)), Color(0.35, 0.65, 1.0))
	for side in [-0.32, 0.32]:
		var rail := BoxMesh.new()
		rail.size = Vector3(0.05, 0.15, 2.2)
		_add_mesh(ctx, rail, Transform3D(Basis(Vector3.RIGHT, -0.5), sl + Vector3(side, 0.7, -1.2)), Color(1.0, 0.85, 0.3))
	# Sandpit with a bucket.
	var sp := Vector3(-12.0, 0, -4.3)
	box(ctx, Vector3(1.8, 0.05, 1.8), sp + Vector3(0, 0.02, 0), Color(0.95, 0.85, 0.55), false)
	for k in 4:
		var horiz := k < 2
		var off := -0.9 if k % 2 == 0 else 0.9
		box(ctx, Vector3(1.9, 0.18, 0.1) if horiz else Vector3(0.1, 0.18, 1.9), sp + (Vector3(0, 0.09, off) if horiz else Vector3(off, 0.09, 0)), Color(0.7, 0.45, 0.3), false)
	cyl(ctx, 0.1, 0.08, 0.16, sp + Vector3(0.3, 0.1, 0.2), Color(1.0, 0.35, 0.35), false)
	# Washing line with clothes flapping (well, standing very still).
	for zz in [-1.0, 3.0]:
		cyl(ctx, 0.04, 0.04, 1.9, Vector3(-14.0, 0.95, zz), Color(0.6, 0.6, 0.65))
	box(ctx, Vector3(0.02, 0.02, 4.0), Vector3(-14.0, 1.85, 1.0), Color(0.9, 0.9, 0.9), false)
	var cloth: Array[Color] = [Color(1.0, 0.5, 0.5), Color(0.5, 0.75, 1.0), Color(1.0, 0.9, 0.4), Color(0.6, 0.9, 0.6)]
	for i in 4:
		box(ctx, Vector3(0.03, 0.5, 0.45), Vector3(-14.0, 1.58, -0.3 + i * 0.85), cloth[i], false)
	# Flower beds along the house wall.
	var petals: Array[Color] = [Color(1.0, 0.45, 0.55), Color(1.0, 0.85, 0.3), Color(0.75, 0.55, 1.0)]
	for i in 12:
		var z := -6.2 + i * 0.7 + (0.0 if i < 6 else 1.6)
		if absf(z - GARDEN_DOOR_Z) < 1.0:
			continue
		ball(ctx, 0.11, Vector3(-9.35, 0.32, z), petals[i % 3])
		cyl(ctx, 0.015, 0.015, 0.3, Vector3(-9.35, 0.15, z), Color(0.3, 0.6, 0.3), false)
	_fairy_lights(main)


## Glowing fairy lights strung along the fence tops (one MultiMesh; they're what lights the garden at night).
static func _fairy_lights(main: Node3D) -> void:
	var xfs: Array[Transform3D] = []
	var x0 := -HALF_X - GARDEN_W
	for i in 28:
		xfs.append(Transform3D(Basis(), Vector3(x0, 1.0 + 0.06 * sin(i * 1.3), -HALF_Z + 0.25 + i * 0.5)))
	for i in 16:
		xfs.append(Transform3D(Basis(), Vector3(x0 + 0.25 + i * 0.5, 1.0 + 0.06 * sin(i * 1.7), -HALF_Z)))
		xfs.append(Transform3D(Basis(), Vector3(x0 + 0.25 + i * 0.5, 1.0 + 0.06 * sin(i * 1.1), HALF_Z)))
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
	main.add_child(mmi)
