extends RefCounted
## Map 2: THE SPACESHIP. A cosy cartoon starship, x -9..9, z -7..7, ceiling 2.8 m, floating in space.
## South row (z 2..7): crew quarters (bunk beds), MESS HALL (middle: the seeker counts facing a big porthole;
## the jail is in its corner), cargo bay (crates). A long CORRIDOR (z -1..2) joins everything.
## North row (z -7..-1): engine room (a glowing reactor), the BRIDGE (a huge window full of stars and a planet),
## hydroponics (planter rows and a tree). Same batching rules as world.gd.

const W := preload("res://games/hide_and_seek/world.gd")

const TITLE := "THE SPACESHIP"
const H := 2.8
const DW := 1.6
const DH := 2.2

const ROOMS := [["crew quarters", Vector3(-6.0, 0, 4.0)], ["mess hall", Vector3(0.0, 0, 4.5)], ["cargo bay", Vector3(6.0, 0, 3.6)],
	["corridor", Vector3(0.0, 0, 0.5)], ["engine room", Vector3(-6.0, 0, -2.5)], ["bridge", Vector3(0.0, 0, -2.5)],
	["hydroponics", Vector3(6.0, 0, -3.7)]]
const DOORS := [["crew-corridor", Vector3(-6.0, 0, 2.0)], ["mess-corridor", Vector3(0.0, 0, 2.0)], ["cargo-corridor", Vector3(6.0, 0, 2.0)],
	["engine-corridor", Vector3(-6.0, 0, -1.0)], ["bridge-corridor", Vector3(0.0, 0, -1.0)], ["hydro-corridor", Vector3(6.0, 0, -1.0)],
	["crew-mess", Vector3(-3.0, 0, 4.6)], ["mess-cargo", Vector3(3.0, 0, 4.6)],
	["engine-bridge", Vector3(-3.0, 0, -4.0)], ["bridge-hydro", Vector3(3.0, 0, -4.0)]]

const SPAWNS: Array[Vector3] = [Vector3(0, 0, 6.0), Vector3(-1.2, 0, 3.4), Vector3(1.2, 0, 3.4), Vector3(0, 0, 3.0),
	Vector3(-2.2, 0, 3.4), Vector3(2.2, 0, 3.4), Vector3(-0.6, 0, 4.0), Vector3(0.6, 0, 4.0)]
const JAIL_POS := Vector3(2.05, 0, 6.15)
const BELL_POS := Vector3(1.15, 0, 5.55)

const STAR_SPOTS: Array[Vector3] = [
	Vector3(-7.5, 0, 0.5), Vector3(-3.0, 0, 0.0), Vector3(3.0, 0, 1.0), Vector3(7.5, 0, 0.0), Vector3(-6.0, 0, 3.6),
	Vector3(-2.0, 0, 2.6), Vector3(5.8, 0, 3.4), Vector3(6.0, 0, 5.6), Vector3(-7.8, 0, -2.6), Vector3(-4.2, 0, -4.6),
	Vector3(-1.8, 0, -2.4), Vector3(1.8, 0, -4.4), Vector3(4.4, 0, -4.0), Vector3(7.8, 0, -3.75),
]

const HIDE_SPOTS: Array[Vector3] = [
	Vector3(-6.0, 0, 6.4), Vector3(-8.4, 0, 4.6), Vector3(-1.3, 0, 5.0), Vector3(8.2, 0, 4.6),
	Vector3(6.0, 0, 6.4), Vector3(3.6, 0, 5.8), Vector3(-6.0, 0, -6.3), Vector3(-8.4, 0, -4.0),
	Vector3(-4.0, 0, -5.4), Vector3(0.0, 0, -6.4), Vector3(-2.4, 0, -1.7), Vector3(6.8, 0, -6.3),
	Vector3(8.6, 0, -3.75), Vector3(-4.4, 0, 3.6),
]

const DECOYS := [
	# crew quarters
	[3, Vector3(-8.4, 0, 5.3), 0.6], [2, Vector3(-4.4, 0, 2.6), 0.3], [4, Vector3(-8.0, 0, 2.6), 0.0], [0, Vector3(-3.5, 0, 2.5), 0.0],
	# mess hall
	[1, Vector3(2.6, 0, 2.5), 0.0], [0, Vector3(-2.6, 0, 2.5), 0.0], [2, Vector3(-2.5, 0, 5.9), 0.2],
	# cargo bay
	[2, Vector3(5.0, 0, 5.1), 0.4], [2, Vector3(7.0, 0, 3.2), 0.1], [3, Vector3(3.6, 0, 6.5), -0.3],
	# corridor
	[1, Vector3(-8.4, 0, 1.4), 0.0], [1, Vector3(3.8, 0, -0.6), 0.5], [2, Vector3(-3.2, 0, -0.6), 0.3], [3, Vector3(-8.4, 0, -0.4), 1.0],
	[4, Vector3(8.4, 0, 1.4), 0.0], [0, Vector3(2.0, 0, 1.6), 0.0], [0, Vector3(-2.0, 0, 1.6), 0.0], [2, Vector3(8.4, 0, -0.4), 0.2],
	# engine room
	[2, Vector3(-3.8, 0, -6.4), 0.1], [2, Vector3(-4.5, 0, -6.4), 0.4], [0, Vector3(-8.4, 0, -6.4), 0.0], [3, Vector3(-3.6, 0, -1.6), -0.5],
	[4, Vector3(-7.6, 0, -2.0), 0.0],
	# bridge
	[1, Vector3(-2.5, 0, -1.6), 0.0], [1, Vector3(2.5, 0, -1.6), 0.7], [3, Vector3(-1.5, 0, -4.6), 0.0], [0, Vector3(2.4, 0, -5.4), 0.0],
	# hydroponics
	[1, Vector3(4.6, 0, -1.5), 0.0], [1, Vector3(3.6, 0, -2.8), 0.4], [1, Vector3(5.0, 0, -6.4), 1.2], [1, Vector3(7.6, 0, -1.5), 0.2],
	[4, Vector3(8.4, 0, -1.5), 0.0],
]

const FLOOR_SHADER := """
shader_type spatial;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 f = fract(wpos.xz);
	float seam = smoothstep(0.0, 0.03, f.x) * smoothstep(0.0, 0.03, f.y);
	float rivet = step(0.06, length(f - vec2(0.1)));
	vec3 c = vec3(0.55, 0.58, 0.64);
	vec3 glow = vec3(0.0);
	if (wpos.z > -1.0 && wpos.z < 2.0) {                           // corridor: a glowing guide line
		c = vec3(0.32, 0.35, 0.42);
		if (abs(wpos.z - 0.5) < 0.06) { c = vec3(0.3, 0.9, 1.0); glow = c * 0.6; }
	} else if (wpos.z >= 2.0 && abs(wpos.x) < 3.0) { c = vec3(0.78, 0.64, 0.5); }   // mess hall
	else if (wpos.z >= 2.0 && wpos.x > 3.0) {                                       // cargo bay
		c = vec3(0.5, 0.52, 0.5);
		if (wpos.z > 6.5) { c = mod(floor((wpos.x + wpos.z) * 2.0), 2.0) < 1.0 ? vec3(0.95, 0.8, 0.2) : vec3(0.15, 0.15, 0.15); }
	}
	else if (wpos.z >= 2.0) { c = vec3(0.45, 0.55, 0.78); }                         // crew quarters
	else if (wpos.x < -3.0) { c = vec3(0.6, 0.5, 0.42); }                           // engine room
	else if (wpos.x < 3.0) { c = vec3(0.28, 0.32, 0.5); }                           // bridge
	else { c = vec3(0.45, 0.62, 0.45); }                                            // hydroponics
	ALBEDO = c * mix(0.6, 1.0, seam) * mix(0.7, 1.0, rivet);
	EMISSION = glow;
	ROUGHNESS = 0.5;
	METALLIC = 0.3;
}
"""

const HULL := Color(0.86, 0.89, 0.94)
const CYAN := Color(0.3, 0.9, 1.0)
const LAMP := Color(0.85, 0.95, 1.0)


static func data() -> Dictionary:
	return {"title": TITLE, "rooms": ROOMS, "doors": DOORS, "hide_spots": HIDE_SPOTS, "star_spots": STAR_SPOTS,
		"spawns": SPAWNS, "jail": JAIL_POS, "bell": BELL_POS, "bounds": [-9.0, 9.0, -7.0, 7.0]}


static func build(root: Node3D) -> Dictionary:
	var ctx: Dictionary = W.new_ctx(root)
	W.environment_for(root, Color(0.03, 0.03, 0.09), Color(0.85, 0.9, 1.0), 0.6, 0.3)
	W.shader_floor(ctx, Vector2(18.0, 14.0), Vector3.ZERO, FLOOR_SHADER)
	_hull(ctx)
	_crew(ctx)
	_mess(ctx)
	_cargo(ctx)
	_corridor(ctx)
	_engine(ctx)
	_bridge(ctx)
	_hydro(ctx)
	var lights: Array = W.omni_lights(root, [Vector3(-6.0, 2.5, 4.5), Vector3(0, 2.5, 4.5), Vector3(6.0, 2.5, 4.5),
		Vector3(0, 2.5, 0.5), Vector3(-6.0, 2.5, -4.0), Vector3(0, 2.5, -4.0), Vector3(6.0, 2.5, -4.0)],
		Color(0.9, 0.95, 1.0), 1.1, 6.5)
	var decoys: Array = W.finish(ctx, DECOYS)
	return {"decoys": decoys, "lights": lights, "window_mat": W.window_mat(ctx)}


static func _hull(ctx: Dictionary) -> void:
	W.wall_x(ctx, -7.0, -9.0, 9.0, [], HULL, H, DW, DH)
	W.wall_x(ctx, 7.0, -9.0, 9.0, [], HULL, H, DW, DH)
	W.wall_z(ctx, -9.0, -7.0, 7.0, [], HULL, H, DW, DH)
	W.wall_z(ctx, 9.0, -7.0, 7.0, [], HULL, H, DW, DH)
	W.wall_x(ctx, 2.0, -9.0, 9.0, [-6.0, 0.0, 6.0], HULL, H, DW, DH)
	W.wall_x(ctx, -1.0, -9.0, 9.0, [-6.0, 0.0, 6.0], HULL, H, DW, DH)
	W.wall_z(ctx, -3.0, 2.0, 7.0, [4.6], HULL, H, DW, DH)
	W.wall_z(ctx, 3.0, 2.0, 7.0, [4.6], HULL, H, DW, DH)
	W.wall_z(ctx, -3.0, -7.0, -1.0, [-4.0], HULL, H, DW, DH)
	W.wall_z(ctx, 3.0, -7.0, -1.0, [-4.0], HULL, H, DW, DH)
	W.box(ctx, Vector3(18.3, 0.1, 14.3), Vector3(0, H + 0.05, 0), Color(0.32, 0.35, 0.42), false)
	# Glowing strips over every doorway (sliding-door frames).
	for d in DOORS:
		var p: Vector3 = d[1]
		var along_x := absf(p.z - 2.0) < 0.01 or absf(p.z + 1.0) < 0.01
		W.box(ctx, Vector3(DW, 0.08, 0.2) if along_x else Vector3(0.2, 0.08, DW), Vector3(p.x, DH + 0.06, p.z), CYAN, false, 0.0, 1.5)
	# Ceiling light panels.
	for p in [Vector3(-6.0, H - 0.02, 4.5), Vector3(0, H - 0.02, 4.5), Vector3(6.0, H - 0.02, 4.5), Vector3(-4.5, H - 0.02, 0.5),
			Vector3(4.5, H - 0.02, 0.5), Vector3(-6.0, H - 0.02, -4.0), Vector3(0, H - 0.02, -3.5), Vector3(6.0, H - 0.02, -4.0)]:
		W.box(ctx, Vector3(1.4, 0.04, 0.6), p, LAMP, false, 0.0, 1.5)
	# Coloured stripe round the walls at hand height.
	for w in [[Vector3(0, 1.0, 6.9), Vector3(17.8, 0.12, 0.04)], [Vector3(0, 1.0, -6.9), Vector3(17.8, 0.12, 0.04)],
			[Vector3(-8.9, 1.0, 0), Vector3(0.04, 0.12, 13.8)], [Vector3(8.9, 1.0, 0), Vector3(0.04, 0.12, 13.8)]]:
		W.box(ctx, w[1], w[0], Color(0.35, 0.55, 0.95), false)
	# Portholes (they glow, and go dark at night).
	var frame := Color(0.6, 0.65, 0.72)
	for w in [[Vector3(-7.6, 1.6, 6.92), false], [Vector3(-4.4, 1.6, 6.92), false], [Vector3(0, 1.6, 6.92), false],
			[Vector3(5.6, 1.6, 6.92), false], [Vector3(-8.92, 1.6, 4.5), true], [Vector3(8.92, 1.6, 4.5), true],
			[Vector3(-8.92, 1.6, -4.0), true], [Vector3(8.92, 1.6, -4.0), true]]:
		W.window_at(ctx, w[0], w[1], frame, Vector2(0.9, 0.9) if absf((w[0] as Vector3).x) > 0.1 else Vector2(1.8, 1.0))


static func _bunk(ctx: Dictionary, c: Vector3, blanket: Color) -> void:
	var metal := Color(0.7, 0.74, 0.8)
	W.box(ctx, Vector3(2.0, 0.45, 0.9), c + Vector3(0, 0.225, 0), metal)
	W.box(ctx, Vector3(1.9, 0.12, 0.85), c + Vector3(0, 0.5, 0), blanket, false)
	W.box(ctx, Vector3(2.0, 0.15, 0.9), c + Vector3(0, 1.45, 0), metal, false)
	W.box(ctx, Vector3(1.9, 0.12, 0.85), c + Vector3(0, 1.58, 0), blanket.lightened(0.2), false)
	for x in [-0.96, 0.96]:
		for z in [-0.41, 0.41]:
			W.box(ctx, Vector3(0.08, 1.7, 0.08), c + Vector3(x, 0.85, z), metal.darkened(0.2))
	W.box(ctx, Vector3(0.5, 0.12, 0.35), c + Vector3(-0.65, 0.62, 0), Color(1, 1, 1), false)


static func _crew(ctx: Dictionary) -> void:
	_bunk(ctx, Vector3(-7.6, 0, 6.25), Color(0.9, 0.4, 0.45))
	_bunk(ctx, Vector3(-4.4, 0, 6.25), Color(0.4, 0.7, 0.95))
	W.box(ctx, Vector3(0.5, 2.0, 1.6), Vector3(-8.7, 1.0, 3.4), Color(0.55, 0.65, 0.85))
	for i in 3:
		W.box(ctx, Vector3(0.02, 1.8, 0.02), Vector3(-8.44, 1.0, 2.87 + i * 0.53), Color(0.3, 0.35, 0.45), false)
	W.box(ctx, Vector3(2.4, 0.02, 1.6), Vector3(-6.0, 0.01, 4.4), Color(0.95, 0.8, 0.45), false)


static func _mess(ctx: Dictionary) -> void:
	# Food dispenser with a glowing screen.
	W.box(ctx, Vector3(0.8, 2.0, 0.5), Vector3(-2.5, 1.0, 6.6), Color(0.75, 0.78, 0.85))
	W.box(ctx, Vector3(0.5, 0.35, 0.02), Vector3(-2.5, 1.4, 6.34), CYAN, false, 0.0, 1.5)
	# Round table on one leg.
	W.cyl(ctx, 0.75, 0.75, 0.06, Vector3(-1.9, 1.0, 5.4), Color(0.95, 0.6, 0.3), false)
	W.cyl(ctx, 0.12, 0.25, 0.97, Vector3(-1.9, 0.485, 5.4), Color(0.6, 0.62, 0.7))
	W.ball(ctx, 0.12, Vector3(-1.7, 1.12, 5.3), Color(0.95, 0.3, 0.3))
	W.cyl(ctx, 0.08, 0.06, 0.15, Vector3(-2.1, 1.1, 5.5), Color(1.0, 0.9, 0.4), false)
	W.jail_at(ctx, JAIL_POS, BELL_POS, Color(0.6, 0.85, 1.0), Color(0.35, 0.45, 0.95))


static func _crate(ctx: Dictionary, c: Vector3, s: float, color: Color, yaw: float = 0.0) -> void:
	W.box(ctx, Vector3(s, s, s), c + Vector3(0, s / 2.0, 0), color, true, yaw)
	W.box(ctx, Vector3(s + 0.02, 0.08, s + 0.02), c + Vector3(0, s * 0.8, 0), color.darkened(0.25), false, yaw)
	W.box(ctx, Vector3(s + 0.02, 0.08, s + 0.02), c + Vector3(0, s * 0.2, 0), color.darkened(0.25), false, yaw)


static func _cargo(ctx: Dictionary) -> void:
	_crate(ctx, Vector3(5.0, 0, 6.3), 1.0, Color(0.95, 0.6, 0.25))
	_crate(ctx, Vector3(5.0, 1.0, 6.3), 0.8, Color(0.4, 0.75, 0.95))
	_crate(ctx, Vector3(8.2, 0, 6.2), 1.2, Color(0.55, 0.8, 0.45))
	_crate(ctx, Vector3(8.3, 0, 3.0), 1.0, Color(0.95, 0.6, 0.25))
	_crate(ctx, Vector3(6.6, 0, 4.4), 0.9, Color(0.85, 0.45, 0.7))
	_crate(ctx, Vector3(8.2, 1.2, 6.2), 0.7, Color(0.95, 0.85, 0.35))


static func _corridor(ctx: Dictionary) -> void:
	# Pipes along the corridor walls (up high, no collision) and an airlock at the east end.
	for z in [-0.82, 1.82]:
		var pm := CylinderMesh.new()
		pm.top_radius = 0.06
		pm.bottom_radius = 0.06
		pm.height = 17.6
		pm.radial_segments = 8
		pm.rings = 1
		W._add_mesh(ctx, pm, Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(0, 2.45, z)), Color(0.6, 0.62, 0.68))
	W.box(ctx, Vector3(0.06, 2.1, 1.6), Vector3(8.88, 1.05, 0.5), Color(0.55, 0.58, 0.65), false)
	W.box(ctx, Vector3(0.08, 2.1, 0.05), Vector3(8.86, 1.05, 0.5), Color(0.3, 0.32, 0.38), false)
	W.box(ctx, Vector3(0.06, 0.12, 1.6), Vector3(8.86, 2.2, 0.5), CYAN, false, 0.0, 1.5)
	W.box(ctx, Vector3(0.06, 2.1, 1.6), Vector3(-8.88, 1.05, 0.5), Color(0.55, 0.58, 0.65), false)
	W.box(ctx, Vector3(0.06, 0.12, 1.6), Vector3(-8.86, 2.2, 0.5), CYAN, false, 0.0, 1.5)


static func _engine(ctx: Dictionary) -> void:
	var core := Color(0.45, 1.0, 0.6)
	W.cyl(ctx, 1.0, 1.0, 0.4, Vector3(-6.0, 0.2, -4.6), Color(0.45, 0.48, 0.55))
	W.cyl(ctx, 0.45, 0.45, 2.0, Vector3(-6.0, 1.4, -4.6), core, true, 1.6)
	for y in [0.9, 1.5, 2.1]:
		W.cyl(ctx, 0.62, 0.62, 0.08, Vector3(-6.0, y, -4.6), Color(0.6, 0.62, 0.7), false)
	W.cyl(ctx, 0.7, 0.7, 0.2, Vector3(-6.0, H - 0.1, -4.6), Color(0.45, 0.48, 0.55), false)
	for z in [-2.5, -5.5]:
		W.cyl(ctx, 0.12, 0.12, H, Vector3(-8.75, H / 2.0, z), Color(0.85, 0.55, 0.3))
	W.box(ctx, Vector3(0.6, 1.0, 1.2), Vector3(-8.55, 0.5, -2.2), Color(0.6, 0.62, 0.7))
	W.box(ctx, Vector3(0.02, 0.4, 0.9), Vector3(-8.24, 0.85, -2.2), core, false, 0.0, 1.6)


static func _bridge(ctx: Dictionary) -> void:
	# The big window: a starry sky and a ringed planet.
	W.box(ctx, Vector3(5.2, 1.7, 0.03), Vector3(0, 1.5, -6.9), Color(0.65, 0.7, 0.78), false)
	W.box(ctx, Vector3(5.0, 1.5, 0.03), Vector3(0, 1.5, -6.88), Color(0.06, 0.08, 0.25), false, 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 22:
		var s := rng.randf_range(0.025, 0.05)
		W.box(ctx, Vector3(s, s, 0.02), Vector3(rng.randf_range(-2.4, 2.4), rng.randf_range(0.8, 2.2), -6.86), LAMP, false, 0.0, 1.5)
	var pl := CylinderMesh.new()
	pl.top_radius = 0.42
	pl.bottom_radius = 0.42
	pl.height = 0.02
	pl.radial_segments = 16
	pl.rings = 1
	W._add_mesh(ctx, pl, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(1.4, 1.7, -6.85)), Color(1.0, 0.6, 0.3), 0.9)
	W.box(ctx, Vector3(1.3, 0.04, 0.02), Vector3(1.4, 1.7, -6.84), Color(0.95, 0.85, 0.6), false, 0.0, 0.0)
	# Main console with glowing buttons, two side consoles and the captain's chair.
	var panel := Color(0.55, 0.6, 0.7)
	W.box(ctx, Vector3(2.6, 1.0, 0.6), Vector3(0, 0.5, -5.6), panel)
	W.box(ctx, Vector3(2.3, 0.03, 0.4), Vector3(0, 1.02, -5.6), CYAN, false, 0.0, 1.5)
	for x in [-2.55, 2.55]:
		W.box(ctx, Vector3(0.7, 1.0, 0.9), Vector3(x, 0.5, -6.3), panel)
		W.box(ctx, Vector3(0.6, 0.03, 0.6), Vector3(x, 1.02, -6.3), Color(0.45, 1.0, 0.6), false, 0.0, 1.6)
	W.box(ctx, Vector3(0.7, 0.5, 0.7), Vector3(0, 0.25, -3.4), Color(0.9, 0.3, 0.35))
	W.box(ctx, Vector3(0.7, 0.9, 0.12), Vector3(0, 0.95, -3.05), Color(0.9, 0.3, 0.35))
	W.box(ctx, Vector3(0.12, 0.25, 0.6), Vector3(-0.4, 0.62, -3.4), panel, false)
	W.box(ctx, Vector3(0.12, 0.25, 0.6), Vector3(0.4, 0.62, -3.4), panel, false)


static func _hydro(ctx: Dictionary) -> void:
	var soil := Color(0.45, 0.32, 0.22)
	var leaf := Color(0.32, 0.72, 0.36)
	for z in [-2.6, -4.9]:
		W.box(ctx, Vector3(3.0, 0.6, 0.7), Vector3(6.8, 0.3, z), Color(0.75, 0.78, 0.85))
		W.box(ctx, Vector3(2.9, 0.04, 0.6), Vector3(6.8, 0.61, z), soil, false)
		for i in 6:
			W.ball(ctx, 0.2, Vector3(5.55 + i * 0.5, 0.78, z), leaf.lightened(0.1 * (i % 2)), 1.1)
			if i % 2 == 0:
				W.ball(ctx, 0.06, Vector3(5.6 + i * 0.5, 0.85, z + 0.15), Color(1.0, 0.3, 0.25))
	# A tree in a big pot.
	W.cyl(ctx, 0.4, 0.32, 0.6, Vector3(4.0, 0.3, -6.2), Color(0.85, 0.5, 0.3))
	W.cyl(ctx, 0.08, 0.12, 1.2, Vector3(4.0, 1.1, -6.2), Color(0.5, 0.33, 0.2), false)
	W.ball(ctx, 0.6, Vector3(4.0, 1.9, -6.2), leaf, 0.9)
	W.ball(ctx, 0.08, Vector3(4.3, 1.8, -5.8), Color(1.0, 0.75, 0.2))
	# Water tank.
	W.cyl(ctx, 0.45, 0.45, 1.6, Vector3(8.4, 0.8, -6.3), Color(0.5, 0.75, 0.95))
	W.cyl(ctx, 0.47, 0.47, 0.08, Vector3(8.4, 1.2, -6.3), Color(0.6, 0.62, 0.7), false)
