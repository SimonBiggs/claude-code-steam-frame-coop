extends RefCounted
## Where everything is in the kitchen (metres). -Z is towards the garden, +X towards the serving window.
## The chef stands behind the counter facing -Z; the runners work on the far side of it.

const COUNTER_TOP := 0.95
const COUNTER_HALF := Vector2(1.25, 0.3)  # x, z half extents
const CHEF_POS := Vector3(0.0, 0.0, 0.62)
const CHEF_HEAD_HEIGHT := 1.6
# Far edge of the counter: runners drop raw ingredients here.
const PASS_SLOTS := [Vector3(-0.6, 0.95, -0.13), Vector3(-0.2, 0.95, -0.13), Vector3(0.2, 0.95, -0.13), Vector3(0.6, 0.95, -0.13)]
# Chef's side of the counter.
const BOARD := Vector3(0.0, 0.95, 0.14)
const PLATE_HOME := [Vector3(-0.45, 0.95, 0.15), Vector3(0.45, 0.95, 0.15)]
const TRASH := Vector3(-0.95, 0.95, 0.13)
# Finished plates wait here (counter corners on the runners' side).
const OUT_SLOTS := [Vector3(-1.02, 0.95, -0.15), Vector3(1.02, 0.95, -0.15)]
# Chef area (runners can't go in): x -1.4..1.4, z 0.3..1.9
const CHEF_AREA := Rect2(-1.4, 0.3, 2.8, 1.6)

const ROOM_HALF := Vector2(7.0, 6.0)
const DOOR_HALF := 1.1  # back door in the north wall (z = -6), out to the garden
const GARDEN_END := -11.5
const STOVE := Vector3(-3.6, 0.0, -5.35)
const EXT_POS := Vector3(3.6, 0.0, -5.55)
const WINDOW_X := 6.5
const CUSTOMER_Z := [-2.4, -0.8, 0.8, 2.4]
const CUSTOMER_X := 7.45
const SERVE_X := 5.95  # where a runner stands to hand a plate over

# [kind, position of the crate / plant]
const SOURCES := [
	["patty", Vector3(-6.25, 0.0, -2.8)],
	["cheese", Vector3(-6.25, 0.0, -1.4)],
	["dough", Vector3(-6.25, 0.0, 0.0)],
	["bun", Vector3(-6.25, 0.0, 2.2)],
	["lettuce", Vector3(-3.0, 0.0, -8.8)],
	["tomato", Vector3(0.0, 0.0, -9.4)],
	["cucumber", Vector3(3.0, 0.0, -8.8)],
]

const RUNNER_SPAWN := [Vector3(-2.0, 0.0, -2.2), Vector3(2.0, 0.0, -2.2)]
const RACCOON_DOOR := Vector3(0.0, 0.0, -6.8)
const RACCOON_EXIT := Vector3(0.0, 0.0, -11.0)


## Chef cursor spots (button chef): 0-3 pass, 4 trash, 5 left plate, 6 board, 7 right plate.
static func spot_pos(i: int) -> Vector3:
	if i < 4:
		return PASS_SLOTS[i]
	match i:
		4:
			return TRASH
		5:
			return PLATE_HOME[0]
		6:
			return BOARD
	return PLATE_HOME[1]


static func spot_count() -> int:
	return 8


static func source_pos(kind: String) -> Vector3:
	for s in SOURCES:
		if s[0] == kind:
			return s[1]
	return Vector3.ZERO


## Where a runner stands to use a source (a little in front of it, inside the walkable area).
static func source_stand(kind: String) -> Vector3:
	var p := source_pos(kind)
	if p.x < -5.0:
		return Vector3(-5.4, 0.0, p.z)
	return Vector3(p.x, 0.0, p.z + 1.0)
