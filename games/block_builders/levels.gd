extends RefCounted
## Level data. World units: one grid cell = 1 unit (a runner is about 1 unit tall; the VR builder sees
## it at XROrigin3D.world_scale 8, so a cell is a 12.5 cm block). The course runs along +X.
## A block in cell (cx, cy, cz) fills [cx, cx+1] x [cy, cy+1] x [cz, cz+1]: a plank's top is cy+1.
##
## ground: [x0, x1, z0, z1, top]  (solid floating islands)
## lava:   [x0, x1, z0, z1, top]  (touching the surface sends you back)
## gusts:  [x0, x1, z0, z1, y0, y1, push_x, push_z, period, duty]  (wind blows during part of each period)
## water:  [start_y, max_y, delay, rise_per_second]  (rising water sends you back)
## solution / bot_path: used by the headless bot test (and prove each level can be solved).
## bot_path modes: "" walk to it, "rise" stand there until lifted to its height.

const LEVELS := [
	{
		"name": "FIRST BRIDGE",
		"tip": "Builder: grab PLANKS from your tray and bridge the gaps!",
		"time": 120.0,
		"budget": {"plank": 8},
		"ground": [[-11, -5, -2, 3, 0], [-2, 3, -2, 3, 0], [6, 11, -2, 3, 0]],
		"lava": [],
		"gusts": [],
		"water": [],
		"start": Vector3(-9.0, 0.0, 0.5),
		"flag": Vector3(9.0, 0.0, 0.5),
		"solution": [["plank", Vector3i(-5, -1, 0), 0], ["plank", Vector3i(-4, -1, 0), 0], ["plank", Vector3i(-3, -1, 0), 0],
			["plank", Vector3i(3, -1, 0), 0], ["plank", Vector3i(4, -1, 0), 0], ["plank", Vector3i(5, -1, 0), 0]],
		"bot_path": [[Vector3(9.0, 0.0, 0.5), ""]],
	},
	{
		"name": "LAVA STEPS",
		"tip": "Lava! Bridge it, then build STAIRS up to the high ledge.",
		"time": 130.0,
		"budget": {"plank": 5, "stairs": 4},
		"ground": [[-11, -6, -2, 3, 0], [-2, 2, -2, 3, 0], [2, 11, -2, 3, 3]],
		"lava": [[-6, -2, -2, 3, -1]],
		"gusts": [],
		"water": [],
		"start": Vector3(-9.0, 0.0, 0.5),
		"flag": Vector3(8.5, 3.0, 0.5),
		"solution": [["plank", Vector3i(-6, -1, 0), 0], ["plank", Vector3i(-5, -1, 0), 0], ["plank", Vector3i(-4, -1, 0), 0],
			["plank", Vector3i(-3, -1, 0), 0], ["stairs", Vector3i(-1, 0, 0), 0], ["stairs", Vector3i(0, 1, 0), 0],
			["stairs", Vector3i(1, 2, 0), 0]],
		"bot_path": [[Vector3(-1.6, 0.0, 0.5), ""], [Vector3(3.0, 3.0, 0.5), ""], [Vector3(8.5, 3.0, 0.5), ""]],
	},
	{
		"name": "BOUNCE HOUSE",
		"tip": "Too high to climb! A SPRING next to the wall bounces runners up.",
		"time": 130.0,
		"budget": {"plank": 5, "stairs": 1, "spring": 1},
		"ground": [[-11, -5, -2, 3, 0], [-1, 3, -2, 3, 0], [3, 11, -2, 3, 4]],
		"lava": [[-1, 1, -2, 0, 0.2]],
		"gusts": [],
		"water": [],
		"start": Vector3(-9.0, 0.0, 0.5),
		"flag": Vector3(8.5, 4.0, 0.5),
		"solution": [["plank", Vector3i(-5, -1, 0), 0], ["plank", Vector3i(-4, -1, 0), 0], ["plank", Vector3i(-3, -1, 0), 0],
			["plank", Vector3i(-2, -1, 0), 0], ["spring", Vector3i(2, 0, 0), 0]],
		"bot_path": [[Vector3(1.0, 0.0, 0.5), ""], [Vector3(2.5, 0.0, 0.5), ""], [Vector3(5.0, 4.0, 0.5), ""], [Vector3(8.5, 4.0, 0.5), ""]],
	},
	{
		"name": "WINDY RIDGE",
		"tip": "Gusts blow runners off the ridge: build a railing! Then a FAN lifts you up.",
		"time": 150.0,
		"budget": {"plank": 11, "stairs": 1, "fan": 1},
		"ground": [[-11, -7, -2, 3, 0], [-7, 4, 0, 1, 0], [6, 11, -2, 3, 4]],
		"lava": [],
		"gusts": [[-5, 3, -3, 5, -1, 3, 0.0, 4.6, 4.0, 0.5]],
		"water": [],
		"start": Vector3(-9.0, 0.0, 0.5),
		"flag": Vector3(8.5, 4.0, 0.5),
		"solution": [["plank", Vector3i(-5, 0, 1), 0], ["plank", Vector3i(-4, 0, 1), 0], ["plank", Vector3i(-3, 0, 1), 0],
			["plank", Vector3i(-2, 0, 1), 0], ["plank", Vector3i(-1, 0, 1), 0], ["plank", Vector3i(0, 0, 1), 0],
			["plank", Vector3i(1, 0, 1), 0], ["plank", Vector3i(2, 0, 1), 0], ["plank", Vector3i(4, -1, 0), 0],
			["fan", Vector3i(5, -1, 0), 0]],
		"bot_path": [[Vector3(4.5, 0.0, 0.5), ""], [Vector3(5.5, 5.0, 0.5), "rise"], [Vector3(8.5, 4.0, 0.5), ""]],
	},
	{
		"name": "RISING TIDE",
		"tip": "The water is rising! Build high and hurry to the flag.",
		"time": 150.0,
		"budget": {"plank": 9, "stairs": 2, "spring": 1, "fan": 1},
		"ground": [[-11, -7, -2, 3, 3], [-4, -1, -2, 3, 0], [2, 5, -2, 3, 1], [8, 11, -2, 3, 4]],
		"lava": [],
		"gusts": [],
		"water": [-3.0, 2.6, 12.0, 0.04],
		"start": Vector3(-9.0, 3.0, 0.5),
		"flag": Vector3(9.5, 4.0, 0.5),
		"solution": [["plank", Vector3i(-7, 2, 0), 0], ["plank", Vector3i(-6, 2, 0), 0], ["plank", Vector3i(-5, 2, 0), 0],
			["stairs", Vector3i(-1, 0, 0), 0], ["plank", Vector3i(0, 0, 0), 0], ["plank", Vector3i(1, 0, 0), 0],
			["plank", Vector3i(5, 0, 0), 0], ["plank", Vector3i(6, 0, 0), 0], ["fan", Vector3i(7, 0, 0), 0]],
		"bot_path": [[Vector3(-4.6, 3.0, 0.5), ""], [Vector3(-2.0, 0.0, 0.5), ""], [Vector3(1.5, 1.0, 0.5), ""],
			[Vector3(6.5, 1.0, 0.5), ""], [Vector3(7.5, 5.0, 0.5), "rise"], [Vector3(9.5, 4.0, 0.5), ""]],
	},
	{
		"name": "SKY CASTLE",
		"tip": "The grand finale: lava, wind and a castle in the clouds!",
		"time": 170.0,
		"budget": {"plank": 12, "stairs": 2, "spring": 1, "fan": 1},
		"ground": [[-11, -8, -2, 3, 0], [-5, -3, -2, 3, 0], [-3, 3, 0, 1, 0], [6, 11, -2, 3, 5]],
		"lava": [[-8, -5, -2, 3, -1.5], [3, 6, -2, 3, -1.5]],
		"gusts": [[-3, 3, -4, 4, -1, 3, 0.0, -4.6, 3.0, 0.5]],
		"water": [],
		"start": Vector3(-9.5, 0.0, 0.5),
		"flag": Vector3(9.0, 5.0, 0.5),
		"solution": [["plank", Vector3i(-8, -1, 0), 0], ["plank", Vector3i(-7, -1, 0), 0], ["plank", Vector3i(-6, -1, 0), 0],
			["plank", Vector3i(-3, 0, -1), 0], ["plank", Vector3i(-2, 0, -1), 0], ["plank", Vector3i(-1, 0, -1), 0],
			["plank", Vector3i(0, 0, -1), 0], ["plank", Vector3i(1, 0, -1), 0], ["plank", Vector3i(2, 0, -1), 0],
			["stairs", Vector3i(3, 0, 0), 0], ["plank", Vector3i(4, 0, 0), 0], ["fan", Vector3i(5, 0, 0), 0]],
		"bot_path": [[Vector3(-4.0, 0.0, 0.5), ""], [Vector3(2.6, 0.0, 0.5), ""], [Vector3(4.5, 1.0, 0.5), ""],
			[Vector3(5.5, 6.0, 0.5), "rise"], [Vector3(9.0, 5.0, 0.5), ""]],
	},
]


static func count() -> int:
	return LEVELS.size()


static func get_level(i: int) -> Dictionary:
	return LEVELS[clampi(i, 0, LEVELS.size() - 1)]
