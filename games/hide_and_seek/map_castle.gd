extends RefCounted
## Map 1: THE CASTLE. Stone walls 3.2 m high, x -9..9, z -7..7, an open-sky COURTYARD in the middle.
## South row (z 3..7): armoury (west), GREAT HALL (middle: the seeker counts here, the jail is in its corner),
## kitchen (east). Middle row (z -3..3): bedchamber, courtyard (grass, a well, a tree, a hay cart), library.
## North row (z -7..-3): throne room (west, wide), tower room (east, treasure and a telescope).
## Same batching rules as world.gd: one vertex-coloured mesh for everything that doesn't glow.

const W := preload("res://games/hide_and_seek/world.gd")

const TITLE := "THE CASTLE"
const H := 3.2      # wall height
const DW := 1.6     # doorway width
const DH := 2.3     # doorway height

const ROOMS := [["armoury", Vector3(-6.5, 0, 4.2)], ["great hall", Vector3(0.0, 0, 5.0)], ["kitchen", Vector3(6.5, 0, 4.0)],
	["bedchamber", Vector3(-6.0, 0, 1.5)], ["courtyard", Vector3(0.0, 0, 0.0)], ["library", Vector3(6.0, 0, 1.0)],
	["throne room", Vector3(-3.0, 0, -4.5)], ["tower room", Vector3(6.0, 0, -5.0)]]
const DOORS := [["armoury-hall", Vector3(-4.0, 0, 4.6)], ["hall-kitchen", Vector3(4.0, 0, 4.6)],
	["armoury-bedchamber", Vector3(-6.5, 0, 3.0)], ["hall-courtyard", Vector3(0.0, 0, 3.0)], ["kitchen-library", Vector3(6.5, 0, 3.0)],
	["bedchamber-courtyard", Vector3(-3.0, 0, 0.0)], ["courtyard-library", Vector3(3.0, 0, 0.0)],
	["bedchamber-throne", Vector3(-6.0, 0, -3.0)], ["courtyard-throne", Vector3(0.0, 0, -3.0)], ["library-tower", Vector3(6.5, 0, -3.0)],
	["throne-tower", Vector3(3.0, 0, -5.0)]]

## Seeker counts facing the big castle gate; the hiders stand behind them.
const SPAWNS: Array[Vector3] = [Vector3(0, 0, 6.0), Vector3(-1.4, 0, 4.0), Vector3(1.4, 0, 4.0), Vector3(0, 0, 3.7),
	Vector3(-2.4, 0, 4.2), Vector3(2.6, 0, 4.4), Vector3(-0.7, 0, 4.4), Vector3(0.7, 0, 4.4)]
const JAIL_POS := Vector3(2.9, 0, 6.1)
const BELL_POS := Vector3(1.85, 0, 5.4)

const STAR_SPOTS: Array[Vector3] = [
	Vector3(-6.5, 0, 4.0), Vector3(-2.0, 0, 5.2), Vector3(6.8, 0, 3.8), Vector3(8.4, 0, 4.6), Vector3(-5.5, 0, -1.5),
	Vector3(-7.5, 0, 1.8), Vector3(0.0, 0, 1.5), Vector3(1.5, 0, 0.8), Vector3(1.0, 0, -0.5), Vector3(5.0, 0, -0.6),
	Vector3(7.0, 0, -2.3), Vector3(-4.0, 0, -5.6), Vector3(-0.5, 0, -5.8), Vector3(5.5, 0, -5.2), Vector3(6.8, 0, -4.2),
	Vector3(-8.0, 0, -4.0),
]

const HIDE_SPOTS: Array[Vector3] = [
	Vector3(-6.2, 0, 6.3), Vector3(-8.0, 0, 5.1), Vector3(8.3, 0, 4.95), Vector3(5.9, 0, 4.9),
	Vector3(-8.2, 0, 1.6), Vector3(-4.0, 0, -2.5), Vector3(-5.0, 0, 2.4), Vector3(-1.8, 0, 0.8),
	Vector3(2.4, 0, -2.5), Vector3(8.1, 0, 2.3), Vector3(8.1, 0, -2.3), Vector3(4.4, 0, -2.5),
	Vector3(-1.2, 0, -6.4), Vector3(-6.8, 0, -5.9), Vector3(4.2, 0, -5.6), Vector3(7.4, 0, -5.6),
]

## [kind, position, yaw] (0 lamp, 1 pot plant, 2 box, 3 teddy, 4 beach ball).
const DECOYS := [
	[0, Vector3(-3.0, 0, 6.6), 0.0], [2, Vector3(2.0, 0, 3.5), 0.3], [1, Vector3(-3.4, 0, 3.5), 0.0],
	[2, Vector3(-4.7, 0, 3.5), 0.6], [3, Vector3(-5.0, 0, 5.7), 0.4],
	[2, Vector3(4.6, 0, 6.5), 0.1], [0, Vector3(4.6, 0, 3.5), 0.0],
	[3, Vector3(-8.4, 0, 2.5), 1.2], [0, Vector3(-8.5, 0, -2.5), 0.0], [4, Vector3(-4.5, 0, 1.2), 0.0], [3, Vector3(-6.4, 0, -1.6), -0.4],
	[1, Vector3(-2.5, 0, -2.5), 0.4], [1, Vector3(2.5, 0, 2.5), 1.0], [4, Vector3(1.4, 0, 1.9), 0.0], [2, Vector3(-0.8, 0, -1.2), 0.5],
	[0, Vector3(8.5, 0, 0.0), 0.0], [3, Vector3(3.6, 0, 2.5), 0.3], [2, Vector3(5.4, 0, -1.0), 0.2], [1, Vector3(8.5, 0, -0.6), 0.6],
	[0, Vector3(-8.5, 0, -6.5), 0.0], [1, Vector3(-4.6, 0, -6.5), 0.2], [4, Vector3(-3.0, 0, -3.8), 0.0], [3, Vector3(-8.4, 0, -4.6), 0.8],
	[2, Vector3(2.4, 0, -6.4), 0.4], [2, Vector3(3.7, 0, -6.5), 0.0], [2, Vector3(4.4, 0, -6.5), 0.5], [4, Vector3(7.6, 0, -4.8), 0.0],
	[1, Vector3(3.7, 0, -3.6), 0.0], [0, Vector3(-0.6, 0, -6.5), 0.0],
]

const FLOOR_SHADER := """
shader_type spatial;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 c;
	if (abs(wpos.x) < 3.0 && abs(wpos.z) < 3.0) {      // courtyard: grass
		float n = fract(sin(dot(floor(wpos.xz * 5.0), vec2(12.9898, 78.233))) * 43758.5453);
		c = vec3(0.38, 0.66, 0.32) * (0.9 + 0.15 * n);
	} else {                                            // flagstones (brick bond)
		vec2 q = wpos.xz / vec2(0.9, 0.6);
		q.x += floor(q.y) * 0.5;
		vec2 g = floor(q);
		vec2 f = fract(q);
		float n = fract(sin(dot(g, vec2(12.9898, 78.233))) * 43758.5453);
		float grout = smoothstep(0.0, 0.05, f.x) * smoothstep(0.0, 0.05, f.y);
		vec3 stone = vec3(0.62, 0.6, 0.58);
		if (wpos.z > 3.0 && abs(wpos.x) < 4.0) { stone = vec3(0.74, 0.6, 0.48); }       // great hall: sandstone
		else if (wpos.z < -3.0 && wpos.x < 3.0) { stone = vec3(0.6, 0.57, 0.72); }      // throne room: lilac
		else if (wpos.x > 3.0 && wpos.z > -3.0 && wpos.z < 3.0) { stone = vec3(0.66, 0.5, 0.38); }  // library: wood
		c = mix(vec3(0.3, 0.29, 0.28), stone * (0.88 + 0.2 * n), grout);
	}
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
"""


static func data() -> Dictionary:
	return {"title": TITLE, "rooms": ROOMS, "doors": DOORS, "hide_spots": HIDE_SPOTS, "star_spots": STAR_SPOTS,
		"spawns": SPAWNS, "jail": JAIL_POS, "bell": BELL_POS, "bounds": [-9.0, 9.0, -7.0, 7.0]}


static func build(root: Node3D) -> Dictionary:
	var ctx: Dictionary = W.new_ctx(root)
	W.environment_for(root, Color(0.5, 0.68, 0.95), Color(1.0, 0.88, 0.75), 0.6, 0.6)
	W.shader_floor(ctx, Vector2(18.0, 14.0), Vector3.ZERO, FLOOR_SHADER)
	_walls(ctx)
	_armoury(ctx)
	_great_hall(ctx)
	_kitchen(ctx)
	_bedchamber(ctx)
	_courtyard(ctx)
	_library(ctx)
	_throne_room(ctx)
	_tower(ctx)
	var lights: Array = W.omni_lights(root, [Vector3(-6.5, 2.8, 5.0), Vector3(0, 2.8, 5.0), Vector3(6.5, 2.8, 5.0),
		Vector3(-6.0, 2.8, 0.0), Vector3(6.0, 2.8, 0.0), Vector3(-3.0, 2.8, -5.0), Vector3(6.0, 2.8, -5.0)],
		Color(1.0, 0.78, 0.55), 1.2, 6.5)
	var decoys: Array = W.finish(ctx, DECOYS)
	return {"decoys": decoys, "lights": lights, "window_mat": W.window_mat(ctx)}


const STONE := Color(0.78, 0.74, 0.68)
const FIRE := Color(1.0, 0.55, 0.15)


static func _torch(ctx: Dictionary, p: Vector3) -> void:
	W.box(ctx, Vector3(0.08, 0.3, 0.08), p, Color(0.35, 0.25, 0.18), false)
	W.ball(ctx, 0.09, p + Vector3(0, 0.22, 0), FIRE, 1.3, 2.2)


static func _banner(ctx: Dictionary, p: Vector3, along_x: bool, color: Color) -> void:
	var s := Vector3(0.8, 1.4, 0.03) if along_x else Vector3(0.03, 1.4, 0.8)
	W.box(ctx, s, p, color, false)
	W.box(ctx, s * Vector3(0.4, 0.3, 1.0) if along_x else s * Vector3(1.0, 0.3, 0.4), p + Vector3(0, 0.15, 0) + (Vector3(0, 0, 0.02) * signf(-p.z) if along_x else Vector3(0.02, 0, 0) * signf(-p.x)), Color(1.0, 0.85, 0.3), false)


static func _walls(ctx: Dictionary) -> void:
	W.wall_x(ctx, -7.0, -9.0, 9.0, [], STONE, H, DW, DH)
	W.wall_x(ctx, 7.0, -9.0, 9.0, [], STONE, H, DW, DH)
	W.wall_z(ctx, -9.0, -7.0, 7.0, [], STONE, H, DW, DH)
	W.wall_z(ctx, 9.0, -7.0, 7.0, [], STONE, H, DW, DH)
	W.wall_x(ctx, 3.0, -9.0, 9.0, [-6.5, 0.0, 6.5], STONE, H, DW, DH)
	W.wall_x(ctx, -3.0, -9.0, 9.0, [-6.0, 0.0, 6.5], STONE, H, DW, DH)
	W.wall_z(ctx, -4.0, 3.0, 7.0, [4.6], STONE, H, DW, DH)
	W.wall_z(ctx, 4.0, 3.0, 7.0, [4.6], STONE, H, DW, DH)
	W.wall_z(ctx, -3.0, -3.0, 3.0, [0.0], STONE, H, DW, DH)
	W.wall_z(ctx, 3.0, -3.0, 3.0, [0.0], STONE, H, DW, DH)
	W.wall_z(ctx, 3.0, -7.0, -3.0, [-5.0], STONE, H, DW, DH)
	# Wooden ceilings over every room except the courtyard (no collision).
	var roof := Color(0.45, 0.32, 0.22)
	W.box(ctx, Vector3(18.3, 0.1, 4.15), Vector3(0, H + 0.05, 5.0), roof, false)
	W.box(ctx, Vector3(18.3, 0.1, 4.15), Vector3(0, H + 0.05, -5.0), roof, false)
	W.box(ctx, Vector3(6.1, 0.1, 6.0), Vector3(-6.0, H + 0.05, 0.0), roof, false)
	W.box(ctx, Vector3(6.1, 0.1, 6.0), Vector3(6.0, H + 0.05, 0.0), roof, false)
	# Battlements round the courtyard's sky.
	for i in 7:
		var k := -3.0 + i * 1.0
		for p in [Vector3(k, H + 0.3, 3.0), Vector3(k, H + 0.3, -3.0), Vector3(3.0, H + 0.3, k), Vector3(-3.0, H + 0.3, k)]:
			W.box(ctx, Vector3(0.45, 0.5, 0.45), p, STONE.lightened(0.05), false)
	# Arrow-slit windows (they glow at dusk and go dark at night).
	var frame := Color(0.55, 0.5, 0.45)
	for w in [[Vector3(-8.92, 1.8, 5.0), true], [Vector3(8.92, 1.8, 5.0), true], [Vector3(-8.92, 1.8, 0.0), true],
			[Vector3(8.92, 1.8, 0.0), true], [Vector3(-6.0, 1.8, -6.92), false], [Vector3(6.0, 1.8, -6.92), false],
			[Vector3(-7.0, 1.8, 6.92), false], [Vector3(7.0, 1.8, 6.92), false]]:
		W.window_at(ctx, w[0], w[1], frame, Vector2(0.4, 1.2))


static func _armoury(ctx: Dictionary) -> void:
	var steel := Color(0.75, 0.78, 0.85)
	for p in [Vector3(-8.4, 0, 6.4), Vector3(-7.3, 0, 6.5)]:
		var at: Vector3 = p
		W.cyl(ctx, 0.22, 0.28, 1.1, at + Vector3(0, 0.55, 0), steel)  # legs + body
		W.box(ctx, Vector3(0.6, 0.45, 0.35), at + Vector3(0, 1.25, 0), steel.lightened(0.1), false)
		W.ball(ctx, 0.17, at + Vector3(0, 1.62, 0), steel.lightened(0.15))
		W.box(ctx, Vector3(0.25, 0.04, 0.05), at + Vector3(0, 1.64, -0.16), Color(0.15, 0.15, 0.2), false)
		W.box(ctx, Vector3(0.04, 0.3, 0.04), at + Vector3(0, 1.88, 0), Color(0.9, 0.2, 0.25), false)
	var wood := Color(0.6, 0.42, 0.26)
	for p in [Vector3(-8.5, 0, 3.6), Vector3(-8.5, 0, 4.35), Vector3(-7.8, 0, 3.6)]:
		var at: Vector3 = p
		W.cyl(ctx, 0.32, 0.35, 0.9, at + Vector3(0, 0.45, 0), wood)
		W.cyl(ctx, 0.36, 0.36, 0.06, at + Vector3(0, 0.25, 0), Color(0.35, 0.33, 0.32), false)
		W.cyl(ctx, 0.36, 0.36, 0.06, at + Vector3(0, 0.65, 0), Color(0.35, 0.33, 0.32), false)
	W.box(ctx, Vector3(0.1, 1.4, 1.2), Vector3(-8.88, 0.9, 5.3), wood.darkened(0.2))
	for i in 4:
		W.box(ctx, Vector3(0.05, 1.3, 0.05), Vector3(-8.75, 0.95, 4.85 + i * 0.3), steel, false)
		W.box(ctx, Vector3(0.05, 0.2, 0.18), Vector3(-8.75, 1.65, 4.85 + i * 0.3), steel.lightened(0.2), false)
	W.box(ctx, Vector3(1.2, 0.6, 0.7), Vector3(-5.0, 0.3, 6.5), Color(0.55, 0.32, 0.2))
	W.box(ctx, Vector3(1.24, 0.08, 0.74), Vector3(-5.0, 0.62, 6.5), Color(0.95, 0.8, 0.3), false)
	# Hay bales to crouch behind.
	var hay := Color(0.92, 0.8, 0.42)
	W.box(ctx, Vector3(1.2, 0.6, 0.8), Vector3(-6.2, 0.3, 5.2), hay)
	W.box(ctx, Vector3(0.9, 0.5, 0.7), Vector3(-6.1, 0.85, 5.2), hay.darkened(0.06), true, 0.2)
	_banner(ctx, Vector3(-6.5, 2.1, 6.9), true, Color(0.3, 0.45, 0.85))
	_torch(ctx, Vector3(-4.12, 1.9, 6.0))


static func _great_hall(ctx: Dictionary) -> void:
	# The big castle gate (closed): the seeker faces it while counting.
	var oak := Color(0.5, 0.32, 0.18)
	W.box(ctx, Vector3(2.4, 2.6, 0.1), Vector3(0, 1.3, 6.88), oak, false)
	W.box(ctx, Vector3(0.04, 2.6, 0.12), Vector3(0, 1.3, 6.86), oak.darkened(0.3), false)
	for y in [0.6, 2.0]:
		W.box(ctx, Vector3(2.4, 0.1, 0.13), Vector3(0, y, 6.85), Color(0.3, 0.3, 0.32), false)
	W.ball(ctx, 0.07, Vector3(-0.25, 1.3, 6.8), Color(1.0, 0.85, 0.3), 1.0, 0.6)
	W.ball(ctx, 0.07, Vector3(0.25, 1.3, 6.8), Color(1.0, 0.85, 0.3), 1.0, 0.6)
	# Red carpet from the courtyard arch to the gate.
	W.box(ctx, Vector3(1.4, 0.02, 3.8), Vector3(0, 0.01, 5.0), Color(0.8, 0.2, 0.25), false)
	# Fireplace in the west wall.
	W.box(ctx, Vector3(0.5, 1.4, 1.8), Vector3(-3.7, 0.7, 6.0), STONE.darkened(0.2))
	W.box(ctx, Vector3(0.1, 0.6, 1.0), Vector3(-3.44, 0.4, 6.0), Color(0.12, 0.08, 0.06), false)
	W.ball(ctx, 0.22, Vector3(-3.4, 0.25, 6.0), FIRE, 1.4, 2.2)
	_banner(ctx, Vector3(-2.0, 2.0, 6.9), true, Color(0.85, 0.25, 0.3))
	_banner(ctx, Vector3(2.0, 2.0, 6.9), true, Color(0.85, 0.25, 0.3))
	_torch(ctx, Vector3(-1.4, 1.9, 6.88))
	_torch(ctx, Vector3(1.4, 1.9, 6.88))
	W.jail_at(ctx, JAIL_POS, BELL_POS, Color(0.55, 0.55, 0.6), Color(0.3, 0.3, 0.35))
	# Benches by the east wall.
	W.box(ctx, Vector3(1.4, 0.45, 0.4), Vector3(-2.0, 0.225, 3.45), oak)


static func _kitchen(ctx: Dictionary) -> void:
	# Bubbling cauldron over a fire.
	W.cyl(ctx, 0.55, 0.45, 0.7, Vector3(7.9, 0.5, 6.0), Color(0.18, 0.18, 0.2))
	W.cyl(ctx, 0.48, 0.48, 0.04, Vector3(7.9, 0.86, 6.0), Color(0.45, 0.85, 0.35), false, 0.8)
	W.ball(ctx, 0.25, Vector3(7.9, 0.1, 6.0), FIRE, 0.6, 2.2)
	# Big table (tall enough to hide under).
	var wood := Color(0.62, 0.42, 0.25)
	W.box(ctx, Vector3(2.0, 0.08, 1.0), Vector3(5.9, 1.0, 4.9), wood)
	for lx in [5.0, 6.8]:
		for lz in [4.5, 5.3]:
			W.box(ctx, Vector3(0.1, 0.96, 0.1), Vector3(lx, 0.48, lz), wood.darkened(0.15))
	W.box(ctx, Vector3(0.3, 0.2, 0.3), Vector3(5.5, 1.14, 4.9), Color(0.95, 0.75, 0.35), false)  # a loaf
	W.ball(ctx, 0.12, Vector3(6.3, 1.12, 4.8), Color(0.9, 0.25, 0.2))  # apples
	W.ball(ctx, 0.12, Vector3(6.5, 1.12, 5.0), Color(0.5, 0.85, 0.3))
	# Shelves of jars by the north wall and flour sacks.
	W.box(ctx, Vector3(1.6, 1.8, 0.4), Vector3(6.0, 0.9, 6.7), wood.darkened(0.2))
	for i in 4:
		W.cyl(ctx, 0.1, 0.1, 0.25, Vector3(5.4 + i * 0.4, 1.35, 6.48), [Color(0.9, 0.5, 0.3), Color(0.5, 0.8, 0.5), Color(0.9, 0.85, 0.4), Color(0.6, 0.6, 0.95)][i], false)
	for p in [Vector3(8.4, 0.3, 3.6), Vector3(8.4, 0.3, 4.2)]:
		var at: Vector3 = p
		W.ball(ctx, 0.35, at, Color(0.9, 0.85, 0.75), 0.9)
	W.box(ctx, Vector3(0.5, 0.6, 1.2), Vector3(8.4, 0.3, 3.9), Color(0.9, 0.85, 0.75), true)
	_torch(ctx, Vector3(8.88, 1.9, 5.0))


static func _bedchamber(ctx: Dictionary) -> void:
	# Four-poster bed with a canopy.
	var post := Color(0.5, 0.32, 0.2)
	W.box(ctx, Vector3(2.0, 0.55, 2.2), Vector3(-7.9, 0.275, -0.6), Color(0.95, 0.92, 0.85))
	W.box(ctx, Vector3(2.04, 0.12, 1.5), Vector3(-7.9, 0.6, -0.2), Color(0.55, 0.3, 0.7), false)
	W.box(ctx, Vector3(0.7, 0.15, 0.4), Vector3(-7.9, 0.66, -1.4), Color(1, 1, 1), false)
	for x in [-8.85, -6.95]:
		for z in [-1.65, 0.45]:
			W.box(ctx, Vector3(0.1, 2.3, 0.1), Vector3(x, 1.15, z), post)
	W.box(ctx, Vector3(2.1, 0.12, 2.3), Vector3(-7.9, 2.35, -0.6), Color(0.55, 0.3, 0.7), false)
	W.box(ctx, Vector3(0.03, 1.4, 2.1), Vector3(-6.92, 1.6, -0.6), Color(0.65, 0.4, 0.8), false)
	# Open wardrobe (step inside to hide).
	var wood := Color(0.6, 0.45, 0.3)
	W.box(ctx, Vector3(1.4, 2.1, 0.08), Vector3(-4.0, 1.05, -2.88), wood)
	W.box(ctx, Vector3(0.08, 2.1, 0.8), Vector3(-4.74, 1.05, -2.45), wood)
	W.box(ctx, Vector3(0.08, 2.1, 0.8), Vector3(-3.26, 1.05, -2.45), wood)
	W.box(ctx, Vector3(1.56, 0.08, 0.8), Vector3(-4.0, 2.1, -2.45), wood)
	for i in 3:
		W.box(ctx, Vector3(0.3, 0.6, 0.04), Vector3(-4.35 + i * 0.35, 1.45, -2.7), [Color(0.9, 0.3, 0.35), Color(0.35, 0.5, 0.9), Color(0.95, 0.85, 0.4)][i], false)
	# Toy chest and a rug.
	W.box(ctx, Vector3(0.9, 0.55, 0.5), Vector3(-4.2, 0.275, 2.5), Color(0.75, 0.5, 0.3))
	W.box(ctx, Vector3(2.4, 0.02, 1.8), Vector3(-5.6, 0.01, 0.2), Color(0.95, 0.75, 0.55), false)
	_banner(ctx, Vector3(-8.9, 1.9, 2.0), false, Color(0.55, 0.3, 0.7))
	_torch(ctx, Vector3(-3.12, 1.9, -1.6))


static func _courtyard(ctx: Dictionary) -> void:
	# The well (off-centre so the cross paths stay clear).
	W.cyl(ctx, 0.6, 0.65, 0.75, Vector3(1.5, 0.375, -1.5), STONE.darkened(0.1))
	W.cyl(ctx, 0.45, 0.45, 0.02, Vector3(1.5, 0.74, -1.5), Color(0.2, 0.4, 0.75), false)
	for dx in [-0.5, 0.5]:
		W.box(ctx, Vector3(0.08, 1.2, 0.08), Vector3(1.5 + dx, 1.3, -1.5), Color(0.45, 0.3, 0.2), false)
	W.box(ctx, Vector3(1.3, 0.12, 1.0), Vector3(1.5, 1.95, -1.5), Color(0.75, 0.35, 0.3), false)
	W.cyl(ctx, 0.12, 0.1, 0.18, Vector3(1.5, 1.1, -1.5), Color(0.55, 0.38, 0.22), false)
	# A tree.
	W.cyl(ctx, 0.18, 0.26, 2.2, Vector3(-1.8, 1.1, -1.8), Color(0.5, 0.33, 0.2))
	W.ball(ctx, 1.0, Vector3(-1.8, 2.8, -1.8), Color(0.3, 0.62, 0.3), 0.9)
	W.ball(ctx, 0.12, Vector3(-2.3, 2.5, -1.2), Color(1.0, 0.3, 0.3))
	# Hay cart.
	var cart := Color(0.65, 0.45, 0.28)
	W.box(ctx, Vector3(1.4, 0.5, 0.9), Vector3(-1.8, 0.6, 1.8), cart)
	W.box(ctx, Vector3(1.3, 0.35, 0.8), Vector3(-1.8, 1.0, 1.8), Color(0.92, 0.8, 0.42), false)
	for dx in [-0.5, 0.5]:
		for dz in [-0.48, 0.48]:
			var wm := CylinderMesh.new()
			wm.top_radius = 0.3
			wm.bottom_radius = 0.3
			wm.height = 0.06
			wm.radial_segments = 12
			wm.rings = 1
			W._add_mesh(ctx, wm, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(-1.8 + dx, 0.3, 1.8 + dz)), Color(0.4, 0.28, 0.18))
	W.box(ctx, Vector3(1.4, 0.6, 0.9), Vector3(-1.8, 0.3, 1.8), cart, true)  # (collision under the cart)
	# Flower bushes.
	for p in [Vector3(2.5, 0.35, 1.4), Vector3(-2.4, 0.35, -0.9)]:
		var at: Vector3 = p
		W.ball(ctx, 0.45, at, Color(0.28, 0.58, 0.3), 0.8)
		W.ball(ctx, 0.08, at + Vector3(0.2, 0.3, 0.1), Color(1.0, 0.5, 0.6))
		W.ball(ctx, 0.08, at + Vector3(-0.15, 0.32, -0.15), Color(1.0, 0.9, 0.4))


static func _library(ctx: Dictionary) -> void:
	var shelf := Color(0.48, 0.32, 0.2)
	var book_cols: Array[Color] = [Color(0.9, 0.3, 0.3), Color(0.3, 0.6, 0.9), Color(0.95, 0.8, 0.3), Color(0.4, 0.8, 0.45)]
	for s in [[Vector3(8.1, 0, 1.3), 1.6], [Vector3(8.1, 0, -1.3), 1.6], [Vector3(4.6, 0, 1.8), 1.4], [Vector3(4.6, 0, -1.8), 1.4]]:
		var at: Vector3 = s[0]
		var sl: float = s[1]
		W.box(ctx, Vector3(sl, 2.0, 0.4), at + Vector3(0, 1.0, 0), shelf)
		for row in 4:
			for b in 5:
				W.box(ctx, Vector3(0.22, 0.3, 0.42), at + Vector3(-sl / 2.0 + 0.2 + b * (sl - 0.4) / 4.0, 0.3 + row * 0.45, 0), book_cols[(row + b) % 4], false)
	# Reading desk with a candle and a globe.
	W.box(ctx, Vector3(1.2, 0.8, 0.7), Vector3(6.3, 0.4, 0.0), Color(0.55, 0.36, 0.22))
	W.cyl(ctx, 0.03, 0.03, 0.15, Vector3(6.0, 0.88, 0.1), Color(1, 1, 0.95), false)
	W.ball(ctx, 0.04, Vector3(6.0, 0.99, 0.1), FIRE, 1.3, 2.2)
	W.ball(ctx, 0.18, Vector3(6.6, 1.0, -0.1), Color(0.35, 0.6, 0.95))
	_torch(ctx, Vector3(8.88, 1.9, 0.0))


static func _throne_room(ctx: Dictionary) -> void:
	# Throne on a dais against the north wall.
	var gold := Color(1.0, 0.82, 0.3)
	W.box(ctx, Vector3(2.6, 0.2, 1.4), Vector3(-3.0, 0.1, -6.25), Color(0.55, 0.3, 0.55))
	W.box(ctx, Vector3(0.9, 0.5, 0.7), Vector3(-3.0, 0.45, -6.3), Color(0.85, 0.2, 0.3))
	W.box(ctx, Vector3(0.9, 1.7, 0.15), Vector3(-3.0, 1.05, -6.7), gold)
	W.box(ctx, Vector3(0.15, 0.4, 0.7), Vector3(-3.5, 0.85, -6.3), gold, false)
	W.box(ctx, Vector3(0.15, 0.4, 0.7), Vector3(-2.5, 0.85, -6.3), gold, false)
	W.ball(ctx, 0.12, Vector3(-3.0, 2.0, -6.7), gold, 1.0, 0.6)
	W.box(ctx, Vector3(1.2, 0.02, 3.0), Vector3(-3.0, 0.01, -4.1), Color(0.8, 0.2, 0.25), false)
	# Round table with a single leg (crawl underneath).
	W.cyl(ctx, 1.0, 1.0, 0.08, Vector3(-6.8, 0.98, -5.2), Color(0.6, 0.42, 0.25), false)
	W.cyl(ctx, 0.18, 0.3, 0.94, Vector3(-6.8, 0.47, -5.2), Color(0.5, 0.34, 0.2))
	# Pillars.
	for p in [Vector3(-1.4, 0, -4.6), Vector3(1.6, 0, -4.6), Vector3(-4.6, 0, -4.6)]:
		var at: Vector3 = p
		W.cyl(ctx, 0.28, 0.3, H, at + Vector3(0, H / 2.0, 0), STONE.lightened(0.1))
	_banner(ctx, Vector3(-5.0, 2.0, -6.9), true, Color(0.3, 0.45, 0.85))
	_banner(ctx, Vector3(-1.0, 2.0, -6.9), true, Color(0.3, 0.45, 0.85))
	_torch(ctx, Vector3(-8.88, 1.9, -5.0))
	_torch(ctx, Vector3(2.88, 1.9, -6.3))


static func _tower(ctx: Dictionary) -> void:
	# Treasure pile (glows gold) and a telescope by the window.
	var gold := Color(1.0, 0.85, 0.2)
	W.ball(ctx, 0.5, Vector3(8.3, 0.0, -6.3), gold, 0.7, 0.6)
	W.cyl(ctx, 0.5, 0.5, 0.5, Vector3(8.3, 0.25, -6.3), gold, true, 0.6)
	W.box(ctx, Vector3(0.6, 0.4, 0.4), Vector3(7.5, 0.2, -6.6), Color(0.55, 0.32, 0.2))
	W.cyl(ctx, 0.04, 0.04, 1.2, Vector3(6.0, 0.6, -6.4), Color(0.35, 0.3, 0.25))
	var tm := CylinderMesh.new()
	tm.top_radius = 0.07
	tm.bottom_radius = 0.1
	tm.height = 0.9
	tm.radial_segments = 12
	tm.rings = 1
	W._add_mesh(ctx, tm, Transform3D(Basis(Vector3.RIGHT, -1.0), Vector3(6.0, 1.3, -6.5)), Color(0.8, 0.6, 0.3))
	# Stacked crates to duck behind.
	var crate := Color(0.7, 0.52, 0.32)
	W.box(ctx, Vector3(0.9, 0.9, 0.9), Vector3(5.2, 0.45, -5.9), crate)
	W.box(ctx, Vector3(0.7, 0.7, 0.7), Vector3(5.2, 1.25, -5.9), crate.lightened(0.08), true, 0.4)
	# A spiral staircase column going up.
	W.cyl(ctx, 0.45, 0.45, H, Vector3(8.3, H / 2.0, -3.9), STONE.darkened(0.1))
	for i in 6:
		var a := i * 1.05
		W.box(ctx, Vector3(0.7, 0.08, 0.3), Vector3(8.3 + cos(a) * 0.55, 0.35 + i * 0.45, -3.9 + sin(a) * 0.55), Color(0.55, 0.5, 0.45), false, -a)
	_banner(ctx, Vector3(3.1, 2.0, -6.0), false, Color(0.85, 0.25, 0.3))
	_torch(ctx, Vector3(8.88, 1.9, -5.4))
