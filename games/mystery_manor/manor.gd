extends RefCounted
## MYSTERY MANOR: the house. Layout data (rooms, doorways, stairs portals, search spots, surfaces,
## paintings, crime scenes, spawns) and the builder that turns it into a few merged meshes.
##
## Ground floor (y = 0), x -15..15, z -13..7, ceiling 3.4 m:
##   north row  LIBRARY (west)  | MUSIC ROOM (middle) | CONSERVATORY (east, glass) -> GARDEN MAZE (north, outdoors)
##   middle     STUDY (west)    | GRAND HALL (middle, the case board, stairs) | DINING ROOM (east)
##   south                     |                     | KITCHEN (east)
## Upstairs the ATTIC (y = 6) and downstairs the CELLAR (y = -6), both over/under the hall, reached
## through stair "portals" (a blink in VR, a quick fade on the TV) so nobody climbs real steps.
## Performance (phone-class GPU in the headset): one floor/wall/ceiling "shell" mesh per level with a
## pattern shader (planks, tiles, carpet, wallpaper...), one merged furniture mesh per room (lit +
## glow surfaces), one window mesh (rain streaks + lightning flash), one StaticBody3D per level with a
## box per wall or piece of furniture. Rooms far from the VR player are hidden (VR host only).
## The same box list feeds the navigation grids (AStarGrid2D per level) used by the suspects, the
## hint cat, the reveal re-enactment and the test bots.

const MeshKit := preload("res://core/mesh_kit.gd")
const UiKit := preload("res://core/ui_kit.gd")

const WALL_H := 3.4
const WALL_T := 0.1  ## each room builds its own face of a shared wall: 2 x 0.1 m
const DOOR_W := 1.8
const DOOR_H := 2.5
const LEVEL_Y: Array[float] = [0.0, 6.0, -6.0]  ## ground, attic, cellar
const NAV_CELL := 0.25
const NAV_RADIUS := 0.34
## Render layer for the shell + furniture of a room is 1; hidden-detail layer for the magnifier lens.
const MAG_LAYER := 1 << 17
const TV_ONLY_LAYER := 1 << 10  ## nameplates etc. that the VR camera leaves out

## Floor / wall pattern flags for the shell shader (UV.x).
const PAT_PLAIN := 0
const PAT_PLANKS := 1
const PAT_CHECKER := 2
const PAT_CARPET := 3
const PAT_STONE := 4
const PAT_GRASS := 5
const PAT_STRIPES := 6
const PAT_DAMASK := 7
const PAT_BRICK := 8
const PAT_PANEL := 9
const PAT_PLASTER := 10
const PAT_GLASS := 11
const PAT_TILES := 12

## Rooms. rect = Rect2(x, z, width, depth) on the level's floor. "ext" = exterior wall sides
## (n = -z, s = +z, w = -x, e = +x) that get windows and a stone facade outside.
const ROOMS := [
	{"id": "hall", "name": "GRAND HALL", "level": 0, "rect": Rect2(-5, -5, 10, 12), "floor": PAT_CHECKER,
		"floor_col": Color(0.16, 0.12, 0.14), "wall": PAT_DAMASK, "wall_col": Color(0.55, 0.16, 0.2), "ext": "s",
		"win": {"s": [-3.3, 3.3]}},
	{"id": "library", "name": "LIBRARY", "level": 0, "rect": Rect2(-15, -13, 10, 8), "floor": PAT_PLANKS,
		"floor_col": Color(0.5, 0.32, 0.18), "wall": PAT_PANEL, "wall_col": Color(0.28, 0.42, 0.3), "ext": "nw",
		"win": {"n": [-7.9], "w": [-11.0, -7.0]}},
	{"id": "music", "name": "MUSIC ROOM", "level": 0, "rect": Rect2(-5, -13, 10, 8), "floor": PAT_PLANKS,
		"floor_col": Color(0.7, 0.5, 0.32), "wall": PAT_STRIPES, "wall_col": Color(0.36, 0.48, 0.78), "ext": "n",
		"win": {"n": [-3.6, 1.8]}},
	{"id": "conservatory", "name": "CONSERVATORY", "level": 0, "rect": Rect2(5, -13, 10, 8), "floor": PAT_STONE,
		"floor_col": Color(0.72, 0.45, 0.32), "wall": PAT_GLASS, "wall_col": Color(0.9, 0.92, 0.88), "ext": "ne",
		"win": {}},
	{"id": "study", "name": "STUDY", "level": 0, "rect": Rect2(-15, -5, 10, 12), "floor": PAT_CARPET,
		"floor_col": Color(0.55, 0.14, 0.16), "wall": PAT_PANEL, "wall_col": Color(0.55, 0.38, 0.24), "ext": "ws",
		"win": {"w": [-3.0, 1.0, 5.4], "s": [-13.3, -10.4]}},
	{"id": "dining", "name": "DINING ROOM", "level": 0, "rect": Rect2(5, -5, 10, 6), "floor": PAT_PLANKS,
		"floor_col": Color(0.42, 0.25, 0.15), "wall": PAT_STRIPES, "wall_col": Color(0.86, 0.72, 0.42), "ext": "e",
		"win": {"e": [-1.2]}},
	{"id": "kitchen", "name": "KITCHEN", "level": 0, "rect": Rect2(5, 1, 10, 6), "floor": PAT_CHECKER,
		"floor_col": Color(0.3, 0.5, 0.72), "wall": PAT_TILES, "wall_col": Color(0.92, 0.94, 0.9), "ext": "es",
		"win": {"e": [4.8], "s": [9.0, 12.0]}},
	{"id": "garden", "name": "GARDEN MAZE", "level": 0, "rect": Rect2(0, -27, 20, 14), "floor": PAT_GRASS,
		"floor_col": Color(0.24, 0.42, 0.22), "wall": -1, "wall_col": Color(0, 0, 0), "ext": "", "win": {}},
	{"id": "attic", "name": "ATTIC", "level": 1, "rect": Rect2(-5, -5, 10, 12), "floor": PAT_PLANKS,
		"floor_col": Color(0.55, 0.42, 0.3), "wall": PAT_PANEL, "wall_col": Color(0.6, 0.48, 0.36), "ext": "", "win": {}},
	{"id": "cellar", "name": "CELLAR", "level": 2, "rect": Rect2(-5, -5, 10, 12), "floor": PAT_STONE,
		"floor_col": Color(0.42, 0.42, 0.46), "wall": PAT_BRICK, "wall_col": Color(0.55, 0.32, 0.26), "ext": "", "win": {}},
]
const HALL := 0
const GARDEN := 7
const ATTIC := 8
const CELLAR := 9

## Doorways: [room_a, room_b, centre (floor), wall axis]. "z" = the wall runs along x at constant z.
const DOORS := [
	[0, 2, Vector3(0, 0, -5), "z"], [0, 4, Vector3(-5, 0, 5), "x"], [0, 5, Vector3(5, 0, -2.5), "x"],
	[0, 6, Vector3(5, 0, 4), "x"], [1, 2, Vector3(-5, 0, -9), "x"], [2, 3, Vector3(5, 0, -9), "x"],
	[1, 4, Vector3(-10, 0, -5), "z"], [5, 6, Vector3(10, 0, 1), "z"], [3, 7, Vector3(10, 0, -13), "z"],
]

## Stairs: walk into `zone` (radius r, on `room`'s floor) and you blink to `to` in `to_room`, facing `yaw`.
const PORTALS := [
	{"room": 0, "zone": Vector3(-3.45, 0, -2.55), "r": 0.75, "to_room": 8, "to": Vector3(-3.45, 6, -1.6), "yaw": PI, "label": "UP TO THE ATTIC"},
	{"room": 8, "zone": Vector3(-3.45, 6, -4.0), "r": 0.75, "to_room": 0, "to": Vector3(-3.45, 0, -0.9), "yaw": PI, "label": "DOWN TO THE HALL"},
	{"room": 0, "zone": Vector3(3.45, 0, -4.0), "r": 0.75, "to_room": 9, "to": Vector3(3.45, -6, -2.2), "yaw": PI, "label": "DOWN TO THE CELLAR"},
	{"room": 9, "zone": Vector3(3.45, -6, -4.0), "r": 0.75, "to_room": 0, "to": Vector3(3.45, 0, -2.2), "yaw": PI, "label": "UP TO THE HALL"},
]

## Search spots (drawers, cupboards...): room, name, furniture position (the thing itself, at about
## hand height) and where a player stands to search it (floor, reachable: the bot checks).
const SPOTS := [
	{"room": 0, "name": "GRANDFATHER CLOCK", "pos": Vector3(-4.5, 1.2, 6.45), "stand": Vector3(-3.7, 0, 6.2)},
	{"room": 0, "name": "COAT STAND", "pos": Vector3(4.4, 1.2, 6.4), "stand": Vector3(3.6, 0, 5.7)},
	{"room": 0, "name": "SUIT OF ARMOUR", "pos": Vector3(-1.6, 1.1, 6.5), "stand": Vector3(-1.6, 0, 5.6)},
	{"room": 1, "name": "TALL BOOKSHELF", "pos": Vector3(-10.6, 1.2, -12.75), "stand": Vector3(-10.6, 0, -11.9)},
	{"room": 1, "name": "BIG GLOBE", "pos": Vector3(-6.2, 0.9, -12.3), "stand": Vector3(-6.7, 0, -11.3)},
	{"room": 1, "name": "READING DESK", "pos": Vector3(-12.6, 0.7, -9.0), "stand": Vector3(-11.4, 0, -9.0)},
	{"room": 1, "name": "COMFY ARMCHAIR", "pos": Vector3(-13.9, 0.6, -6.2), "stand": Vector3(-12.8, 0, -6.3)},
	{"room": 2, "name": "GRAND PIANO", "pos": Vector3(-2.4, 0.9, -11.2), "stand": Vector3(-2.4, 0, -9.85)},
	{"room": 2, "name": "CELLO CASE", "pos": Vector3(4.4, 0.8, -11.0), "stand": Vector3(3.5, 0, -10.9)},
	{"room": 2, "name": "SHEET MUSIC CABINET", "pos": Vector3(4.6, 1.0, -6.0), "stand": Vector3(3.7, 0, -6.0)},
	{"room": 2, "name": "VELVET SOFA", "pos": Vector3(-3.6, 0.5, -5.55), "stand": Vector3(-3.6, 0, -6.55)},
	{"room": 3, "name": "POTTING BENCH", "pos": Vector3(6.9, 0.9, -12.6), "stand": Vector3(6.9, 0, -11.7)},
	{"room": 3, "name": "GIANT PLANT POT", "pos": Vector3(13.9, 0.7, -12.0), "stand": Vector3(12.9, 0, -11.3)},
	{"room": 3, "name": "WICKER BASKET", "pos": Vector3(6.0, 0.4, -5.6), "stand": Vector3(6.9, 0, -6.4)},
	{"room": 4, "name": "BIG DESK", "pos": Vector3(-12.0, 0.7, 0.5), "stand": Vector3(-10.9, 0, 0.5)},
	{"room": 4, "name": "FILING CABINET", "pos": Vector3(-14.5, 0.9, -4.3), "stand": Vector3(-13.6, 0, -3.6)},
	{"room": 4, "name": "TROPHY CABINET", "pos": Vector3(-8.0, 1.0, 6.6), "stand": Vector3(-8.0, 0, 5.6)},
	{"room": 5, "name": "SIDEBOARD", "pos": Vector3(10.0, 0.8, -4.7), "stand": Vector3(10.0, 0, -3.85)},
	{"room": 5, "name": "CHINA CABINET", "pos": Vector3(14.6, 1.1, -3.6), "stand": Vector3(13.6, 0, -3.6)},
	{"room": 5, "name": "UNDER THE TABLECLOTH", "pos": Vector3(7.9, 0.5, -2.2), "stand": Vector3(7.0, 0, -2.2)},
	{"room": 6, "name": "BIG OVEN", "pos": Vector3(7.0, 0.6, 6.6), "stand": Vector3(7.0, 0, 5.6)},
	{"room": 6, "name": "ICEBOX", "pos": Vector3(14.55, 1.0, 6.3), "stand": Vector3(13.6, 0, 6.0)},
	{"room": 6, "name": "PANTRY CUPBOARD", "pos": Vector3(14.6, 1.1, 3.0), "stand": Vector3(13.6, 0, 3.0)},
	{"room": 6, "name": "FLOUR SACKS", "pos": Vector3(5.7, 0.5, 1.7), "stand": Vector3(6.7, 0, 2.4)},
	{"room": 7, "name": "GARDEN SHED", "pos": Vector3(1.9, 1.0, -25.3), "stand": Vector3(1.8, 0, -23.7)},
	{"room": 7, "name": "GAZEBO BENCH", "pos": Vector3(17.9, 0.6, -25.2), "stand": Vector3(17.9, 0, -23.8)},
	{"room": 7, "name": "WHEELBARROW", "pos": Vector3(17.2, 0.5, -14.5), "stand": Vector3(15.9, 0, -14.6)},
	{"room": 7, "name": "FOUNTAIN", "pos": Vector3(10.0, 0.7, -21.5), "stand": Vector3(10.0, 0, -19.75)},
	{"room": 8, "name": "OLD TRUNK", "pos": Vector3(4.0, 6.5, 6.2), "stand": Vector3(4.0, 6, 5.2)},
	{"room": 8, "name": "WARDROBE", "pos": Vector3(-4.55, 7.0, 4.0), "stand": Vector3(-3.6, 6, 4.0)},
	{"room": 8, "name": "HAT BOXES", "pos": Vector3(4.3, 6.6, -3.8), "stand": Vector3(3.3, 6, -3.3)},
	{"room": 8, "name": "DRESS-UP BOX", "pos": Vector3(1.8, 6.5, -4.4), "stand": Vector3(1.8, 6, -3.4)},
	{"room": 9, "name": "JAM SHELVES", "pos": Vector3(-4.6, -5.0, 0.0), "stand": Vector3(-3.6, -6, 0.0)},
	{"room": 9, "name": "PICKLE BARRELS", "pos": Vector3(3.8, -5.4, 5.6), "stand": Vector3(3.8, -6, 4.3)},
	{"room": 9, "name": "OLD CRATES", "pos": Vector3(-3.8, -5.4, 5.8), "stand": Vector3(-3.8, -6, 4.7)},
	{"room": 9, "name": "RUMBLY BOILER", "pos": Vector3(4.2, -5.2, 1.5), "stand": Vector3(3.1, -6, 1.5)},
]

## Table tops etc. where a clue object can lie in plain sight: room, name, top position, stand.
const SURFACES := [
	{"room": 0, "name": "HALL TABLE", "pos": Vector3(3.3, 0.86, 6.55), "stand": Vector3(3.0, 0, 5.7)},
	{"room": 1, "name": "READING DESK", "pos": Vector3(-12.75, 0.82, -8.6), "stand": Vector3(-11.4, 0, -8.4)},
	{"room": 1, "name": "LITTLE TABLE", "pos": Vector3(-7.5, 0.66, -5.6), "stand": Vector3(-7.5, 0, -6.5)},
	{"room": 2, "name": "GRAMOPHONE TABLE", "pos": Vector3(2.45, 0.76, -5.5), "stand": Vector3(2.4, 0, -6.4)},
	{"room": 3, "name": "WICKER TABLE", "pos": Vector3(12.3, 0.62, -9.0), "stand": Vector3(12.3, 0, -8.0)},
	{"room": 4, "name": "BIG DESK", "pos": Vector3(-12.0, 0.82, 1.15), "stand": Vector3(-10.9, 0, 1.3)},
	{"room": 4, "name": "SIDE TABLE", "pos": Vector3(-6.4, 0.62, 2.3), "stand": Vector3(-7.3, 0, 2.3)},
	{"room": 5, "name": "DINING TABLE", "pos": Vector3(12.0, 0.82, -2.2), "stand": Vector3(13.4, 0, -2.0)},
	{"room": 6, "name": "KITCHEN TABLE", "pos": Vector3(10.3, 0.82, 4.2), "stand": Vector3(10.3, 0, 5.4)},
	{"room": 7, "name": "FOUNTAIN BENCH", "pos": Vector3(13.0, 0.5, -22.0), "stand": Vector3(13.0, 0, -21.1)},
	{"room": 8, "name": "DUSTY TABLE", "pos": Vector3(-3.8, 6.78, 1.0), "stand": Vector3(-2.75, 6, 1.0)},
	{"room": 9, "name": "WORKBENCH", "pos": Vector3(-1.0, -5.12, -4.55), "stand": Vector3(-1.0, -6, -3.5)},
]

## Paintings: room, wall position (centre of the picture) and the direction it faces. Any of them may
## hide invisible-ink digits of the safe code (seen with the UV torch).
const PAINTINGS := [
	{"room": 0, "pos": Vector3(4.4, 2.35, 0.75), "normal": Vector3(-1, 0, 0), "name": "PORTRAIT OF GREAT-GRANDPA CRUMPET", "pic": 0},
	{"room": 1, "pos": Vector3(-14.86, 2.0, -9.3), "normal": Vector3(1, 0, 0), "name": "SHIP IN A STORM", "pic": 1},
	{"room": 2, "pos": Vector3(0.0, 2.1, -12.86), "normal": Vector3(0, 0, 1), "name": "DANCING CATS", "pic": 2},
	{"room": 4, "pos": Vector3(-13.0, 2.0, -4.86), "normal": Vector3(0, 0, 1), "name": "MOUNTAIN SUNSET", "pic": 3},
	{"room": 5, "pos": Vector3(6.9, 2.1, -4.86), "normal": Vector3(0, 0, 1), "name": "BOWL OF FRUIT", "pic": 4},
	{"room": 6, "pos": Vector3(13.0, 2.1, 1.14), "normal": Vector3(0, 0, 1), "name": "PRIZE CARROT", "pic": 5},
	{"room": 8, "pos": Vector3(-0.5, 7.5, -4.86), "normal": Vector3(0, 0, 1), "name": "DUSTY OLD LADY", "pic": 0},
	{"room": 9, "pos": Vector3(0.0, -4.4, 6.86), "normal": Vector3(0, 0, -1), "name": "SPOOKY CASTLE", "pic": 1},
]

## Crime scenes: where the stolen thing stood (a pedestal), per room.
const SCENES := {
	5: Vector3(13.8, 0, 0.2), 4: Vector3(-8.6, 0, -1.6), 3: Vector3(9.5, 0, -6.2),
	1: Vector3(-8.3, 0, -11.5), 6: Vector3(12.9, 0, 1.65), 2: Vector3(0.6, 0, -9.6),
}

## Where people stand around in each room (suspects' schedules, spawns, the cat).
const LOITER := [
	[Vector3(-0.5, 0, -1.0), Vector3(1.6, 0, 2.6), Vector3(-1.6, 0, 4.8), Vector3(2.2, 0, -2.6)],
	[Vector3(-9.5, 0, -8.8), Vector3(-7.4, 0, -7.0), Vector3(-11.0, 0, -6.6)],
	[Vector3(-1.0, 0, -8.2), Vector3(2.6, 0, -11.0), Vector3(-3.4, 0, -7.6)],
	[Vector3(10.2, 0, -9.6), Vector3(7.8, 0, -8.0), Vector3(11.0, 0, -11.4)],
	[Vector3(-9.2, 0, 2.6), Vector3(-11.0, 0, -2.6), Vector3(-7.0, 0, 4.6)],
	[Vector3(7.0, 0, -0.2), Vector3(11.4, 0, -0.1), Vector3(13.2, 0, -4.0)],
	[Vector3(8.0, 0, 3.0), Vector3(12.4, 0, 3.4), Vector3(8.6, 0, 5.4)],
	[Vector3(10.0, 0, -15.0), Vector3(6.6, 0, -21.6), Vector3(14.6, 0, -18.4), Vector3(2.0, 0, -18.0)],
	[Vector3(0.0, 6, 1.6), Vector3(-1.4, 6, 4.4), Vector3(2.2, 6, -1.6)],
	[Vector3(0.0, -6, 1.0), Vector3(-1.6, -6, 3.4), Vector3(1.4, -6, -1.8)],
]

const HALL_BOARD_POS := Vector3(-4.86, 1.75, 1.0)  ## centre of the case board (faces +x)
const EVIDENCE_TABLE := Vector3(-3.75, 0.86, 1.0)    ## top centre of the detective's table
const LORD_POS := Vector3(-3.1, 0, 3.7)
const VR_SPAWN := Vector3(-1.3, 0, 1.0)
const VR_SPAWN_YAW := PI * 0.5  ## facing -x: the case board
const TV_SPAWNS: Array[Vector3] = [Vector3(0.4, 0, 2.6), Vector3(0.8, 0, 3.6), Vector3(-0.2, 0, 4.4),
	Vector3(1.6, 0, 3.0), Vector3(1.4, 0, 4.6), Vector3(0.2, 0, 5.4), Vector3(2.2, 0, 4.0)]
## Where everyone gathers for the big reveal (a semicircle in front of the case board).
const GATHER: Array[Vector3] = [Vector3(-2.6, 0, -1.2), Vector3(-1.6, 0, -0.4), Vector3(-1.2, 0, 0.8),
	Vector3(-1.2, 0, 2.0), Vector3(-1.6, 0, 3.2), Vector3(-2.6, 0, 3.9)]
const GATHER_CULPRIT := Vector3(-2.2, 0, 1.0)


# --- Lookups ----------------------------------------------------------------------------------

static func room_name(r: int) -> String:
	if r < 0 or r >= ROOMS.size():
		return "?"
	return String((ROOMS[r] as Dictionary)["name"])


static func room_level(r: int) -> int:
	return int((ROOMS[r] as Dictionary)["level"])


static func room_rect(r: int) -> Rect2:
	return (ROOMS[r] as Dictionary)["rect"]


## Which level a world height belongs to.
static func level_of_y(y: float) -> int:
	if y > 3.0:
		return 1
	if y < -3.0:
		return 2
	return 0


## The room a world point is in (-1 = outside every room).
static func room_at(p: Vector3) -> int:
	var lv := level_of_y(p.y)
	for i in ROOMS.size():
		var r: Dictionary = ROOMS[i]
		if int(r["level"]) != lv:
			continue
		var rc: Rect2 = r["rect"]
		if rc.grow(0.05).has_point(Vector2(p.x, p.z)):
			return i
	return -1


## Rooms you can walk to directly from room r (doors and stairs).
static func neighbours(r: int) -> Array[int]:
	var out: Array[int] = []
	for d in DOORS:
		var dd: Array = d
		if int(dd[0]) == r:
			out.append(int(dd[1]))
		elif int(dd[1]) == r:
			out.append(int(dd[0]))
	for p in PORTALS:
		var pp: Dictionary = p
		if int(pp["room"]) == r and not out.has(int(pp["to_room"])):
			out.append(int(pp["to_room"]))
	return out


static func spot_count() -> int:
	return SPOTS.size()


static func spots_in_room(r: int) -> Array[int]:
	var out: Array[int] = []
	for i in SPOTS.size():
		if int((SPOTS[i] as Dictionary)["room"]) == r:
			out.append(i)
	return out


static func surfaces_in_room(r: int) -> Array[int]:
	var out: Array[int] = []
	for i in SURFACES.size():
		if int((SURFACES[i] as Dictionary)["room"]) == r:
			out.append(i)
	return out


static func paintings_in_room(r: int) -> Array[int]:
	var out: Array[int] = []
	for i in PAINTINGS.size():
		if int((PAINTINGS[i] as Dictionary)["room"]) == r:
			out.append(i)
	return out


# --- Building ------------------------------------------------------------------------------------

## Build the whole manor under `parent`. Returns the ManorNode (a Node3D named "Manor").
static func build(parent: Node3D, vr: bool) -> ManorNode:
	var m := ManorNode.new()
	m.name = "Manor"
	m.vr = vr
	parent.add_child(m)
	m.build_all()
	return m


## The built manor: meshes, collision, materials, navigation and runtime effects (lightning,
## room culling for the headset).
class ManorNode extends Node3D:
	const MeshKit := preload("res://core/mesh_kit.gd")
	const Me := preload("res://games/mystery_manor/manor.gd")
	const Furniture := preload("res://games/mystery_manor/furniture.gd")

	var vr := false
	var shell_mat: ShaderMaterial
	var window_mat: ShaderMaterial
	var room_nodes: Array[Node3D] = []      ## per room: furniture mesh(es)
	var level_nodes: Array[Node3D] = []     ## per level: shell mesh
	var bodies: Array[StaticBody3D] = []    ## per level
	var solids: Array = [[], [], []]        ## per level: Array of Rect2 footprints (for the nav grid)
	var nav: Array[AStarGrid2D] = []
	var nav_origin: Array[Vector2] = []
	var flash := 0.0
	var culling := false
	var _builders: Array = []               ## per room Builder (during the build)
	var _shell: Array = []                  ## per level Builder
	var _win: MeshKit.Builder
	var _visible_room := -2

	func build_all() -> void:
		shell_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SHELL_SHADER
		shell_mat.shader = sh
		window_mat = ShaderMaterial.new()
		var wsh := Shader.new()
		wsh.code = WINDOW_SHADER
		window_mat.shader = wsh
		for lv in 3:
			var ln := Node3D.new()
			ln.name = "Level%d" % lv
			add_child(ln)
			level_nodes.append(ln)
			var body := StaticBody3D.new()
			body.name = "Body%d" % lv
			body.collision_layer = 1
			body.collision_mask = 0
			add_child(body)
			bodies.append(body)
			var sb := MeshKit.Builder.new()
			_shell.append(sb)
		_win = MeshKit.Builder.new()
		for r in Me.ROOMS.size():
			var rn := Node3D.new()
			rn.name = "Room_%s" % String((Me.ROOMS[r] as Dictionary)["id"])
			add_child(rn)
			room_nodes.append(rn)
			_builders.append(MeshKit.Builder.new())
		for r in Me.ROOMS.size():
			_room_shell(r)
		Furniture.furnish(self)
		for r in Me.ROOMS.size():
			var b: MeshKit.Builder = _builders[r]
			if not b.is_empty():
				var mi := MeshKit.instance(b.build(), false)
				mi.name = "Furniture"
				room_nodes[r].add_child(mi)
		for lv in 3:
			var sb: MeshKit.Builder = _shell[lv]
			var smi := MeshKit.instance(sb.build(shell_mat), false)
			smi.name = "Shell"
			level_nodes[lv].add_child(smi)
		if not _win.is_empty():
			var wmi := MeshKit.instance(_win.build(window_mat, window_mat), false)
			wmi.name = "Windows"
			add_child(wmi)
		_builders.clear()
		_shell.clear()
		_build_nav()

	# --- Builder access for furniture.gd -------------------------------------------------------

	func fb(r: int) -> MeshKit.Builder:
		return _builders[r]

	func win() -> MeshKit.Builder:
		return _win

	func shell(level: int) -> MeshKit.Builder:
		return _shell[level]

	## A solid box (collision + nav footprint). centre = box centre in world space.
	func solid(level: int, centre: Vector3, size: Vector3) -> void:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = centre
		bodies[level].add_child(cs)
		(solids[level] as Array).append(Rect2(centre.x - size.x * 0.5, centre.z - size.z * 0.5, size.x, size.z))

	# --- Shell: floors, walls with doorways, ceilings, windows ---------------------------------------

	func _room_shell(r: int) -> void:
		var room: Dictionary = Me.ROOMS[r]
		var lv := int(room["level"])
		var y := Me.LEVEL_Y[lv]
		var rc: Rect2 = room["rect"]
		var sb: MeshKit.Builder = _shell[lv]
		# floor (with a solid slab under it so nothing falls through)
		sb.flag = float(int(room["floor"]))
		sb.box(Vector3(rc.size.x, 0.1, rc.size.y), MeshKit.at(Vector3(rc.position.x + rc.size.x * 0.5, y - 0.05, rc.position.y + rc.size.y * 0.5)), room["floor_col"])
		solid(lv, Vector3(rc.position.x + rc.size.x * 0.5, y - 0.25, rc.position.y + rc.size.y * 0.5), Vector3(rc.size.x, 0.5, rc.size.y))
		var wall_pat := int(room["wall"])
		if wall_pat < 0:
			return  # the garden: hedges instead (furniture.gd)
		var col: Color = room["wall_col"]
		var ext := String(room["ext"])
		var x0 := rc.position.x
		var z0 := rc.position.y
		var x1 := rc.end.x
		var z1 := rc.end.y
		var h := Me.WALL_H
		if r == Me.ATTIC:
			h = 2.2  # low knee walls under the sloping roof
		# north (z = z0), south (z = z1): walls along x; west / east: along z
		var wins: Dictionary = room["win"]
		_wall(r, lv, Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(0, 0, 1), col, wall_pat, h, ext.contains("n"), wins.get("n", []))
		_wall(r, lv, Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(0, 0, -1), col, wall_pat, h, ext.contains("s"), wins.get("s", []))
		_wall(r, lv, Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3(1, 0, 0), col, wall_pat, h, ext.contains("w"), wins.get("w", []))
		_wall(r, lv, Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(-1, 0, 0), col, wall_pat, h, ext.contains("e"), wins.get("e", []))
		# ceiling
		sb.flag = float(Me.PAT_PLASTER)
		var cx := (x0 + x1) * 0.5
		var cz := (z0 + z1) * 0.5
		if r == Me.ATTIC:
			# a pitched roof: two slopes from the knee walls (2.2 m) up to the ridge (4.4 m) along z
			var half := rc.size.x * 0.5
			var rise := 2.2
			var slope := sqrt(half * half + rise * rise)
			var ang := atan2(rise, half)
			for s in [-1.0, 1.0]:
				var sx: float = s
				var xf := Transform3D(Basis(Vector3(0, 0, 1), -sx * ang), Vector3(cx + sx * half * 0.5, y + h + rise * 0.5, cz))
				sb.flag = float(Me.PAT_PANEL)
				sb.box(Vector3(slope, 0.08, rc.size.y), xf, Color(0.5, 0.36, 0.24))
				# rafters
				sb.flag = float(Me.PAT_PLAIN)
				var k := 0.0
				while k < rc.size.y - 0.1:
					var rz := z0 + 0.5 + k
					sb.box(Vector3(slope, 0.14, 0.12), Transform3D(Basis(Vector3(0, 0, 1), -sx * ang), Vector3(cx + sx * half * 0.5, y + h + rise * 0.5 - 0.1, rz)), Color(0.36, 0.24, 0.15))
					k += 1.6
			# gable ends
			for gz in [z0 + 0.05, z1 - 0.05]:
				var g: float = gz
				var tri := PackedVector2Array([Vector2(-half, 0), Vector2(half, 0), Vector2(0, rise)])
				sb.flag = float(Me.PAT_PANEL)
				sb.polygon(tri, 0.1, Transform3D(Basis(), Vector3(cx, y + h, g)), Color(0.55, 0.42, 0.3))
		else:
			sb.box(Vector3(rc.size.x, 0.1, rc.size.y), MeshKit.at(Vector3(cx, y + h + 0.05, cz)), Color(0.93, 0.9, 0.84) if r != Me.CELLAR else Color(0.4, 0.36, 0.34))
			# crown moulding
			sb.flag = float(Me.PAT_PLAIN)
			var mc := Color(0.95, 0.92, 0.84) if r != Me.CELLAR else Color(0.35, 0.3, 0.28)
			sb.box(Vector3(rc.size.x, 0.14, 0.14), MeshKit.at(Vector3(cx, y + h - 0.07, z0 + 0.17)), mc)
			sb.box(Vector3(rc.size.x, 0.14, 0.14), MeshKit.at(Vector3(cx, y + h - 0.07, z1 - 0.17)), mc)
			sb.box(Vector3(0.14, 0.14, rc.size.y), MeshKit.at(Vector3(x0 + 0.17, y + h - 0.07, cz)), mc)
			sb.box(Vector3(0.14, 0.14, rc.size.y), MeshKit.at(Vector3(x1 - 0.17, y + h - 0.07, cz)), mc)
		# keep everyone inside: a solid ceiling slab
		solid(lv, Vector3(cx, y + Me.WALL_H + 0.2, cz), Vector3(rc.size.x, 0.4, rc.size.y))

	## One side of a room: wall panels between the doorways (+ lintels), door frames, skirting, and
	## windows + an outside facade when the side is exterior.
	func _wall(r: int, lv: int, a: Vector3, b: Vector3, inward: Vector3, col: Color, pat: int, h: float, exterior: bool, win_at: Array) -> void:
		var sb: MeshKit.Builder = _shell[lv]
		var along := (b - a).normalized()
		var length := (b - a).length()
		var openings: Array[float] = []  # centres along the side
		for d in Me.DOORS:
			var dd: Array = d
			if int(dd[0]) != r and int(dd[1]) != r:
				continue
			var c: Vector3 = dd[2]
			c.y = a.y
			var rel := c - a
			var t := rel.dot(along)
			var off := rel - along * t
			if off.length() < 0.05 and t > 0.0 and t < length:
				openings.append(t)
		openings.sort()
		var segs: Array = []  # [t0, t1]
		var cur := 0.0
		for t in openings:
			segs.append([cur, t - Me.DOOR_W * 0.5])
			cur = t + Me.DOOR_W * 0.5
		segs.append([cur, length])
		var depth_c := inward * (Me.WALL_T * 0.5)
		var basis := Basis(along, Vector3.UP, along.cross(Vector3.UP))
		for s in segs:
			var ss: Array = s
			var t0: float = ss[0]
			var t1: float = ss[1]
			if t1 - t0 < 0.01:
				continue
			var mid := a + along * ((t0 + t1) * 0.5) + depth_c
			var size := Vector3(t1 - t0, h, Me.WALL_T)
			sb.flag = float(pat)
			sb.box(size, Transform3D(basis, mid + Vector3(0, h * 0.5, 0)), col)
			solid(lv, mid + Vector3(0, h * 0.5, 0), _axis_size(along, t1 - t0, h, Me.WALL_T))
			for wv in win_at:
				var wt: float = float(wv) - (a.x if absf(along.x) > 0.5 else a.z)
				if wt > t0 + 0.7 and wt < t1 - 0.7:
					_window(lv, a, along, inward, wt)
			if exterior:
				sb.flag = float(Me.PAT_BRICK)
				sb.box(Vector3(t1 - t0 + 0.2, h + 0.4, 0.12), Transform3D(basis, a + along * ((t0 + t1) * 0.5) - inward * 0.06 + Vector3(0, (h + 0.4) * 0.5, 0)), Color(0.5, 0.46, 0.5))
		for t in openings:
			# lintel above the doorway
			var mid2 := a + along * t + depth_c
			sb.flag = float(pat)
			sb.box(Vector3(Me.DOOR_W, h - Me.DOOR_H, Me.WALL_T), Transform3D(basis, mid2 + Vector3(0, Me.DOOR_H + (h - Me.DOOR_H) * 0.5, 0)), col)
			# a chunky painted door frame on this side
			sb.flag = float(Me.PAT_PLAIN)
			var fc := Color(0.93, 0.88, 0.76)
			var fo := inward * (Me.WALL_T + 0.03)
			for sx in [-1.0, 1.0]:
				var side: float = sx
				sb.box(Vector3(0.16, Me.DOOR_H + 0.1, 0.08), Transform3D(basis, a + along * (t + side * (Me.DOOR_W * 0.5 + 0.06)) + fo + Vector3(0, (Me.DOOR_H + 0.1) * 0.5, 0)), fc)
			sb.box(Vector3(Me.DOOR_W + 0.3, 0.18, 0.08), Transform3D(basis, a + along * t + fo + Vector3(0, Me.DOOR_H + 0.08, 0)), fc)
			# the floor under the doorway (threshold) so there's no gap between the rooms
			sb.flag = float(Me.PAT_PLAIN)
			sb.box(Vector3(Me.DOOR_W, 0.02, Me.WALL_T * 2.0 + 0.02), Transform3D(basis, a + along * t + Vector3(0, 0.0, 0)), Color(0.45, 0.3, 0.2))

	func _axis_size(along: Vector3, l: float, h: float, t: float) -> Vector3:
		if absf(along.x) > 0.5:
			return Vector3(l, h, t)
		return Vector3(t, h, l)

	## A window at distance t along the wall (pane in the window mesh, frame and curtains in the shell).
	func _window(lv: int, a: Vector3, along: Vector3, inward: Vector3, t: float) -> void:
		var sb: MeshKit.Builder = _shell[lv]
		var basis := Basis(along, Vector3.UP, along.cross(Vector3.UP))
		var c := a + along * t + inward * (Me.WALL_T + 0.01) + Vector3(0, 1.85, 0)
		_win.box(Vector3(1.0, 1.5, 0.02), Transform3D(basis, c), Color(1, 1, 1))
		sb.flag = float(Me.PAT_PLAIN)
		var fc := Color(0.95, 0.93, 0.86)
		sb.box(Vector3(1.2, 0.1, 0.1), Transform3D(basis, c + Vector3(0, 0.8, 0) + inward * 0.03), fc)
		sb.box(Vector3(1.3, 0.08, 0.22), Transform3D(basis, c + Vector3(0, -0.8, 0) + inward * 0.08), fc)
		sb.box(Vector3(0.1, 1.6, 0.1), Transform3D(basis, c + along * 0.55 + inward * 0.03), fc)
		sb.box(Vector3(0.1, 1.6, 0.1), Transform3D(basis, c - along * 0.55 + inward * 0.03), fc)
		sb.box(Vector3(0.06, 1.5, 0.06), Transform3D(basis, c + inward * 0.03), fc)
		sb.box(Vector3(1.0, 0.06, 0.06), Transform3D(basis, c + inward * 0.03), fc)
		var cc := Color(0.5, 0.12, 0.18)
		sb.box(Vector3(0.28, 1.9, 0.06), Transform3D(basis, c + along * 0.78 + inward * 0.1 + Vector3(0, 0.05, 0)), cc)
		sb.box(Vector3(0.28, 1.9, 0.06), Transform3D(basis, c - along * 0.78 + inward * 0.1 + Vector3(0, 0.05, 0)), cc)
		# the same window seen from outside: a warm lit pane in the facade
		_win.box(Vector3(1.0, 1.5, 0.02), Transform3D(basis, a + along * t - inward * 0.13 + Vector3(0, 1.85, 0)), Color(1.0, 0.85, 0.55))

	# --- Navigation ---------------------------------------------------------------------------

	func _build_nav() -> void:
		nav.clear()
		nav_origin.clear()
		for lv in 3:
			var bounds := Rect2()
			var first := true
			for i in Me.ROOMS.size():
				var room: Dictionary = Me.ROOMS[i]
				if int(room["level"]) != lv:
					continue
				var rc: Rect2 = room["rect"]
				bounds = rc if first else bounds.merge(rc)
				first = false
			bounds = bounds.grow(0.5)
			var g := AStarGrid2D.new()
			var w := int(ceil(bounds.size.x / Me.NAV_CELL))
			var d := int(ceil(bounds.size.y / Me.NAV_CELL))
			g.region = Rect2i(0, 0, w, d)
			g.cell_size = Vector2(1, 1)
			g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
			g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
			g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
			g.update()
			var origin := bounds.position
			# walkable = inside a room of this level, outside every (inflated) solid footprint
			for iz in d:
				for ix in w:
					var p := Vector2(origin.x + (ix + 0.5) * Me.NAV_CELL, origin.y + (iz + 0.5) * Me.NAV_CELL)
					var inside := false
					for i in Me.ROOMS.size():
						var room: Dictionary = Me.ROOMS[i]
						if int(room["level"]) == lv and (room["rect"] as Rect2).has_point(p):
							inside = true
							break
					if not inside:
						# doorway thresholds sit on the room boundary: count them as inside
						for dr in Me.DOORS:
							var dd: Array = dr
							var dc: Vector3 = dd[2]
							if lv == 0 and absf(p.x - dc.x) < Me.DOOR_W * 0.5 and absf(p.y - dc.z) < 0.3:
								inside = true
					g.set_point_solid(Vector2i(ix, iz), not inside)
			for sr in solids[lv]:
				var rr: Rect2 = sr
				if rr.size.x > 9.0 and rr.size.y > 5.0:
					continue  # floor / ceiling slabs
				var big := rr.grow(Me.NAV_RADIUS)
				var ax := int(floor((big.position.x - origin.x) / Me.NAV_CELL))
				var az := int(floor((big.position.y - origin.y) / Me.NAV_CELL))
				var bx := int(ceil((big.end.x - origin.x) / Me.NAV_CELL))
				var bz := int(ceil((big.end.y - origin.y) / Me.NAV_CELL))
				for iz in range(maxi(az, 0), mini(bz, d)):
					for ix in range(maxi(ax, 0), mini(bx, w)):
						var cp := Vector2(origin.x + (ix + 0.5) * Me.NAV_CELL, origin.y + (iz + 0.5) * Me.NAV_CELL)
						if big.has_point(cp):
							g.set_point_solid(Vector2i(ix, iz), true)
			nav.append(g)
			nav_origin.append(origin)

	func _cell(lv: int, p: Vector3) -> Vector2i:
		var o: Vector2 = nav_origin[lv]
		var g: AStarGrid2D = nav[lv]
		var c := Vector2i(int((p.x - o.x) / Me.NAV_CELL), int((p.z - o.y) / Me.NAV_CELL))
		c.x = clampi(c.x, 0, g.region.size.x - 1)
		c.y = clampi(c.y, 0, g.region.size.y - 1)
		return c

	func _cell_pos(lv: int, c: Vector2i) -> Vector3:
		var o: Vector2 = nav_origin[lv]
		return Vector3(o.x + (c.x + 0.5) * Me.NAV_CELL, Me.LEVEL_Y[lv], o.y + (c.y + 0.5) * Me.NAV_CELL)

	## Is this floor point walkable (on the nav grid)?
	func walkable(p: Vector3) -> bool:
		var lv := Me.level_of_y(p.y)
		return not (nav[lv] as AStarGrid2D).is_point_solid(_cell(lv, p))

	## Nearest walkable cell centre to p (same level), or p itself.
	func snap_walkable(p: Vector3) -> Vector3:
		var lv := Me.level_of_y(p.y)
		var g: AStarGrid2D = nav[lv]
		var c := _cell(lv, p)
		if not g.is_point_solid(c):
			return Vector3(p.x, Me.LEVEL_Y[lv], p.z)
		for rad in range(1, 12):
			for dz in range(-rad, rad + 1):
				for dx in range(-rad, rad + 1):
					if absi(dx) != rad and absi(dz) != rad:
						continue
					var n := c + Vector2i(dx, dz)
					if g.is_in_boundsv(n) and not g.is_point_solid(n):
						return _cell_pos(lv, n)
		return p

	## A walking path (floor points). Between levels it goes through the stairs: consecutive points
	## whose heights differ by more than 2 m mean "blink through the portal here".
	func path(from: Vector3, to: Vector3) -> PackedVector3Array:
		var la := Me.level_of_y(from.y)
		var lb := Me.level_of_y(to.y)
		if la == lb:
			return _path_level(la, from, to)
		# go through the hall: level a -> (portal) -> hall -> (portal) -> level b
		var out := PackedVector3Array()
		var cur := from
		var lv := la
		var guard := 0
		while lv != lb and guard < 4:
			guard += 1
			var target_room := Me.HALL if lv != 0 else (Me.ATTIC if lb == 1 else Me.CELLAR)
			var portal: Dictionary = {}
			for p in Me.PORTALS:
				var pp: Dictionary = p
				if Me.level_of_y((pp["zone"] as Vector3).y) == lv and int(pp["to_room"]) == target_room:
					portal = pp
			if portal.is_empty():
				break
			var seg := _path_level(lv, cur, portal["zone"])
			out.append_array(seg)
			cur = portal["to"]
			out.append(cur)
			lv = Me.level_of_y(cur.y)
		out.append_array(_path_level(lv, cur, to))
		return out

	func _path_level(lv: int, from: Vector3, to: Vector3) -> PackedVector3Array:
		var g: AStarGrid2D = nav[lv]
		var a := _cell(lv, snap_walkable(from))
		var b := _cell(lv, snap_walkable(to))
		var ids := g.get_id_path(a, b, true)
		var out := PackedVector3Array()
		if ids.is_empty():
			out.append(Vector3(to.x, Me.LEVEL_Y[lv], to.z))
			return out
		# keep the corners only
		var prev_dir := Vector2i.ZERO
		for i in ids.size():
			if i == 0:
				continue
			var dir: Vector2i = ids[i] - ids[i - 1]
			if dir != prev_dir and i > 1:
				out.append(_cell_pos(lv, ids[i - 1]))
			prev_dir = dir
		out.append(Vector3(to.x, Me.LEVEL_Y[lv], to.z) if not g.is_point_solid(_cell(lv, to)) else _cell_pos(lv, ids[ids.size() - 1]))
		return out

	# --- Runtime: lightning flash, room culling --------------------------------------------------

	func set_flash(v: float) -> void:
		flash = v
		window_mat.set_shader_parameter("flash", v)

	## Headset host only: show the room the player is in, its neighbours and their neighbours'
	## doorways (one hop), hide the rest. Levels other than the player's are hidden too.
	func cull_for(p: Vector3) -> void:
		if not culling:
			return
		var r := Me.room_at(p)
		if r == _visible_room or r < 0:
			return
		_visible_room = r
		var show: Array[int] = [r]
		for n in Me.neighbours(r):
			if Me.room_level(n) == Me.room_level(r):
				show.append(n)
		for i in room_nodes.size():
			room_nodes[i].visible = show.has(i)
		var lv := Me.room_level(r)
		for l in 3:
			level_nodes[l].visible = l == lv

	func show_everything() -> void:
		_visible_room = -2
		for n in room_nodes:
			n.visible = true
		for n in level_nodes:
			n.visible = true

	## The room visible-set the headset currently draws (for hiding suspects in culled rooms).
	func room_shown(r: int) -> bool:
		if r < 0 or r >= room_nodes.size():
			return true
		return room_nodes[r].visible


const SHELL_SHADER := """
shader_type spatial;
// Floors, walls and ceilings of the manor. UV.x = pattern id (see manor.gd PAT_*), COLOR = base
// colour. Patterns use model-space position, so a scaled copy keeps its look.
varying vec3 mpos;
varying float pat;
void vertex() {
	mpos = VERTEX;
	pat = UV.x;
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec3 base = COLOR.rgb;
	int k = int(pat + 0.5);
	vec3 c = base;
	float rough = 0.85;
	float h = mod(mpos.y + 6.0 + 0.0001, 6.0);
	vec2 wp = vec2(mpos.x + mpos.z, mpos.y);
	if (k == 1) {
		float row = floor(mpos.z / 0.22);
		float o = hash(vec2(row, 3.1));
		float seam = smoothstep(0.0, 0.05, fract(mpos.z / 0.22)) * smoothstep(0.0, 0.012, fract(mpos.x / 1.7 + o));
		float grain = 0.92 + 0.08 * sin(mpos.x * 22.0 + o * 9.0 + sin(mpos.z * 40.0));
		c = mix(base * 0.45, base * (0.82 + 0.3 * o) * grain, seam);
		rough = 0.55;
	} else if (k == 2) {
		vec2 g = floor(mpos.xz / 0.6);
		float m = mod(g.x + g.y, 2.0);
		c = mix(base, vec3(0.92, 0.9, 0.85), m);
		vec2 f = fract(mpos.xz / 0.6);
		float grout = smoothstep(0.0, 0.03, f.x) * smoothstep(0.0, 0.03, f.y);
		c *= mix(0.55, 1.0, grout);
		rough = 0.3;
	} else if (k == 3) {
		vec2 q = mpos.xz;
		float pile = 0.9 + 0.1 * noise(q * 18.0);
		float border = step(0.5, fract((q.x + q.y) * 1.2)) * 0.05;
		c = base * pile + border;
		rough = 1.0;
	} else if (k == 4) {
		vec2 g = floor(mpos.xz / vec2(0.7, 0.5) + vec2(floor(mpos.z / 0.5) * 0.5, 0.0));
		float o = hash(g);
		vec2 f = fract(mpos.xz / vec2(0.7, 0.5) + vec2(floor(mpos.z / 0.5) * 0.5, 0.0));
		float grout = smoothstep(0.0, 0.05, f.x) * smoothstep(0.0, 0.07, f.y);
		c = mix(base * 0.5, base * (0.8 + 0.35 * o), grout);
		rough = 0.9;
	} else if (k == 5) {
		float n = noise(mpos.xz * 3.0) * 0.5 + noise(mpos.xz * 11.0) * 0.5;
		c = base * (0.75 + 0.5 * n);
		rough = 1.0;
	} else if (k == 6 || k == 7 || k == 9 || k == 12) {
		if (k == 6) {
			float s = step(0.5, fract(wp.x * 2.2));
			c = mix(base, base * 1.18 + 0.04, s * 0.6);
		} else if (k == 7) {
			vec2 d = fract(vec2(wp.x * 2.5, wp.y * 2.5 + floor(wp.x * 2.5) * 0.5)) - 0.5;
			float dot_ = 1.0 - smoothstep(0.12, 0.16, length(d * vec2(1.0, 0.7)));
			c = mix(base, base * 1.5 + vec3(0.08, 0.06, 0.02), dot_ * 0.7);
		} else if (k == 9) {
			float p = fract(wp.x / 0.9);
			float frame = smoothstep(0.0, 0.04, p) * smoothstep(1.0, 0.96, p);
			c = mix(base * 0.6, base * (0.95 + 0.05 * sin(wp.y * 30.0)), frame);
		} else {
			vec2 f = fract(wp / 0.2);
			float grout = smoothstep(0.0, 0.05, f.x) * smoothstep(0.0, 0.05, f.y);
			c = mix(base * 0.7, base, grout);
			rough = 0.25;
		}
		if (k != 12 && h < 1.05 && h > 0.0) {
			// wood wainscot, rail and skirting
			float p2 = fract(wp.x / 0.6);
			float panel = smoothstep(0.0, 0.05, p2) * smoothstep(1.0, 0.95, p2);
			c = mix(vec3(0.3, 0.18, 0.1), vec3(0.48, 0.3, 0.17), panel);
			if (h > 0.97) { c = vec3(0.62, 0.42, 0.24); }
			if (h < 0.13) { c = vec3(0.22, 0.13, 0.08); }
			rough = 0.6;
		}
	} else if (k == 8) {
		vec2 b = wp / vec2(0.32, 0.14);
		b.x += floor(b.y) * 0.5;
		vec2 f = fract(b);
		float o = hash(floor(b));
		float mortar = smoothstep(0.0, 0.06, f.x) * smoothstep(0.0, 0.12, f.y);
		c = mix(vec3(0.62, 0.6, 0.56), base * (0.75 + 0.4 * o), mortar);
		rough = 0.95;
	} else if (k == 10) {
		c = base * (0.95 + 0.05 * noise(mpos.xz * 2.0));
	} else if (k == 11) {
		// conservatory glass walls: white frames over night-blue glass
		vec2 f = fract(vec2(wp.x / 1.0, wp.y / 0.9));
		float frame = 1.0 - smoothstep(0.0, 0.05, f.x) * smoothstep(1.0, 0.95, f.x) * smoothstep(0.0, 0.06, f.y) * smoothstep(1.0, 0.94, f.y);
		vec3 glass = vec3(0.09, 0.13, 0.24) + 0.05 * noise(wp * 3.0 + TIME * 0.2);
		c = mix(glass, base, frame);
		rough = mix(0.1, 0.6, frame);
		EMISSION = glass * (1.0 - frame) * 0.4;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
}
"""

const WINDOW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
// Window panes: night sky, rain running down, the lightning flash (uniform `flash`, 0..1).
// COLOR tints it (warm for panes seen from outside).
uniform float flash = 0.0;
varying vec3 mpos;
void vertex() { mpos = VERTEX; }
float hash(float p) { return fract(sin(p * 127.1) * 43758.5453); }
void fragment() {
	vec2 p = vec2(mpos.x + mpos.z, mpos.y);
	float col = floor(p.x * 9.0);
	float speed = 1.5 + hash(col) * 2.0;
	float drop = smoothstep(0.85, 1.0, fract(p.y * 1.3 + TIME * speed * 0.35 + hash(col + 3.0)));
	float streak = drop * smoothstep(0.35, 0.5, fract(p.x * 9.0)) * smoothstep(0.65, 0.5, fract(p.x * 9.0));
	vec3 night = mix(vec3(0.04, 0.05, 0.12), vec3(0.12, 0.13, 0.28), clamp(fract(mpos.y / 6.0 + 0.5) , 0.0, 1.0));
	vec3 c = night + streak * vec3(0.18, 0.22, 0.32) + flash * vec3(0.85, 0.9, 1.0);
	bool outside = COLOR.b < 0.8;
	if (outside) {
		c = vec3(1.0, 0.75, 0.4) * (0.75 + 0.15 * sin(TIME * 1.3 + mpos.x)) + flash * 0.3;
	}
	ALBEDO = c;
}
"""
