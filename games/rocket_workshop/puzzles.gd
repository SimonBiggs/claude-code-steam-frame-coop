extends RefCounted
## Puzzle modules for one rocket. Each module is a plain Dictionary so the host can send it to the
## TV in snapshots. The VR pilot's panel has the controls; the TV crew's blueprint boards say what
## the right answer is. From rocket 3 the boards list a few rockets by name, so the crew must ask
## the pilot what this rocket is called (it's only written on the pilot's desk screen).
## Two modules turn the talking round: ALIEN HELLO (the pilot describes the alien on the desk, the crew
## look it up) and the PAINT job (only the pilot's screen says which colour the rocket wants).

const COLOR_NAMES: Array[String] = ["RED", "BLUE", "YELLOW", "GREEN"]
const COLORS: Array[Color] = [Color(0.95, 0.25, 0.22), Color(0.25, 0.5, 1.0), Color(1.0, 0.82, 0.15), Color(0.3, 0.82, 0.3)]
const SHAPE_NAMES: Array[String] = ["BALL", "CUBE", "CONE", "RING", "PILL", "TENT"]
const SHAPE_COLORS: Array[Color] = [Color(1.0, 0.4, 0.35), Color(0.35, 0.6, 1.0), Color(1.0, 0.8, 0.2),
	Color(0.4, 0.85, 0.4), Color(0.8, 0.45, 0.95), Color(1.0, 0.6, 0.25)]
const ROCKET_NAMES: Array[String] = ["ZOOMY", "BLIPPY", "NOVA", "WOBBLE", "SPARKY", "LUNA", "ROCKO", "PIP", "COMET", "BIBBLE",
	"FIZZ", "DOODLE", "TWINKLE", "ZIPPY"]
const VR_TYPES: Array[String] = ["fuel", "wires", "symbols", "gauge", "switches", "alien", "crank"]
const NEW_TYPES: Array[String] = ["alien", "crank"]  # introduced from rocket 2, one at a time
const JOB_TYPES: Array[String] = ["canister", "pipe", "bolts", "paint"]
const TITLES := {
	"fuel": "FUEL MIX", "wires": "WIRE PLUGS", "symbols": "SHAPE BUTTONS", "gauge": "PRESSURE DIAL",
	"switches": "SWITCHES", "alien": "ALIEN HELLO", "crank": "THRUSTER CRANK",
	"canister": "FUEL CANISTER", "pipe": "LEAKY PIPE", "bolts": "LOOSE BOLTS", "paint": "PAINT JOB", "cat": "SPACE CAT",
}
const MISTAKE_SECONDS := 10.0
const SWITCH_COUNT := 5
# Alien features: skin colour, eyes (1-3) and what's on top of its head.
const ALIEN_COLOR_NAMES: Array[String] = ["GREEN", "PURPLE", "ORANGE"]
const ALIEN_COLORS: Array[Color] = [Color(0.45, 0.9, 0.35), Color(0.7, 0.4, 1.0), Color(1.0, 0.6, 0.2)]
const ALIEN_TOPS: Array[String] = ["ANTENNA", "HORNS", "BIG EARS"]
const HELLO_WORDS: Array[String] = ["BEEP", "BOOP", "ZORP"]
const HELLO_COLORS: Array[Color] = [Color(0.3, 0.85, 1.0), Color(1.0, 0.45, 0.75), Color(1.0, 0.85, 0.25)]
# Where the TV crew's jobs can turn up.
const CAN_SPOTS: Array[Vector3] = [Vector3(-9.0, 0, 6.5), Vector3(9.0, 0, 6.5), Vector3(-9.0, 0, -4.5), Vector3(9.0, 0, -4.5), Vector3(-5.0, 0, -13.0)]
const PIPE_SPOTS: Array[Vector3] = [Vector3(-10.75, 1.1, 1.75), Vector3(10.75, 1.1, 1.75), Vector3(-5.0, 1.1, 7.75), Vector3(5.0, 1.1, 7.75)]
const BOLT_SPOTS: Array[Vector3] = [Vector3(-7.5, 0, 2.0), Vector3(-4.0, 0, 5.5), Vector3(4.5, 0, 5.0), Vector3(7.8, 0, 1.2),
	Vector3(-6.0, 0, -3.2), Vector3(6.0, 0, -3.5), Vector3(-3.0, 0, -9.0), Vector3(3.5, 0, -14.5), Vector3(-2.8, 0, 3.0),
	Vector3(2.6, 0, -4.0), Vector3(-9.5, 0, -1.0), Vector3(9.5, 0, 3.5)]
# Paint pots stand in a line along the yard's left fence, so the way back to the rocket never brushes past another pot.
const PAINT_SPOTS: Array[Vector3] = [Vector3(-9.6, 0, -8.0), Vector3(-9.6, 0, -9.6), Vector3(-9.6, 0, -11.2), Vector3(-9.6, 0, -12.8)]
const CAT_BASKET := Vector3(-3.4, 0, -4.9)
# The space map: one planet per rocket, then round again.
const PLANETS: Array[String] = ["THE MOON", "MARS", "RINGO", "JELLY WORLD", "ICEBALL", "SPOTTY", "BUBBLE PLANET",
	"CANDY STAR", "GIGANTO", "STARHOME"]
const PLANET_COLORS: Array[Color] = [Color(0.85, 0.85, 0.8), Color(0.95, 0.4, 0.25), Color(0.95, 0.8, 0.45),
	Color(1.0, 0.5, 0.8), Color(0.65, 0.9, 1.0), Color(0.5, 0.85, 0.4), Color(0.45, 0.6, 1.0), Color(1.0, 0.55, 0.9),
	Color(1.0, 0.65, 0.25), Color(1.0, 0.95, 0.55)]
const PLANET_RINGS: Array[bool] = [false, false, true, false, false, false, true, false, true, true]


static func planet(n: int) -> int:
	return (maxi(n, 1) - 1) % PLANETS.size()


static func make_rocket(n: int, crew: int = 1) -> Dictionary:
	var names: Array = ROCKET_NAMES.duplicate()
	names.shuffle()
	var vr_count := clampi(1 + floori((n + 1) / 2.0), 2, 4)  # 2, 2, 3, 3, 4, 4...
	if n >= 9:
		vr_count = 5
	var types: Array = VR_TYPES.duplicate()
	types.shuffle()
	# Rocket 2 shows off the alien, rocket 3 the crank; later rockets pick from everything.
	if n == 2 or n == 3:
		var fresh: String = NEW_TYPES[n - 2]
		types.erase(fresh)
		types.push_front(fresh)
	elif n == 1:
		for t in NEW_TYPES:
			types.erase(t)
			types.append(t)
	var keyed := 1 if n < 3 else (2 if n < 5 else 3)
	var mods: Array = []
	for i in vr_count:
		mods.append(_make(types[i], n, names, keyed))
	var job_count := 0 if n < 2 else (1 if n < 5 else 2)
	if n >= 2 and crew >= 3:
		job_count += 1  # a big crew gets more to do
	if n >= 4 and crew >= 5:
		job_count += 1
	var jobs: Array = JOB_TYPES.duplicate()
	jobs.shuffle()
	if n == 3:  # the first paint job comes early so everyone meets it
		jobs.erase("paint")
		jobs.push_front("paint")
	job_count = mini(job_count, jobs.size())
	for i in job_count:
		mods.append(_make(jobs[i], n, names, keyed))
	var time := 50.0 + 40.0 * vr_count + 30.0 * job_count - minf(n, 6.0) * 3.0
	time += 60.0 if n <= 2 else 0.0  # extra learning time for the first rockets
	return {"name": names[0], "modules": mods, "time": time}


## Simple mode: one new desk control per rocket, never more than two puzzles (plus the launch lever).
## Rocket 1 is the practice: press ONE coloured button. Then plugs, the dial, switches, shapes.
## No crew jobs, no rocket names, no countdown.
const SIMPLE_ORDER: Array[String] = ["fuel", "wires", "gauge", "switches", "symbols"]


static func make_simple_rocket(n: int) -> Dictionary:
	var names: Array = ROCKET_NAMES.duplicate()
	names.shuffle()
	var types: Array = []
	if n <= SIMPLE_ORDER.size():
		types.append(SIMPLE_ORDER[n - 1])  # the new one first (the ghost hand shows how it works)
		if n > 1:
			types.append(SIMPLE_ORDER[randi() % (n - 1)])
	else:
		var all: Array = SIMPLE_ORDER.duplicate()
		all.shuffle()
		types = all.slice(0, 2)
	var mods: Array = []
	for t in types:
		mods.append(make_simple(t, n))
	return {"name": names[0], "modules": mods, "time": 999.0}


static func make_simple(type: String, n: int) -> Dictionary:
	match type:
		"fuel":  # press 1 (later 2 different) coloured buttons
			var cols: Array = [0, 1, 2, 3]
			cols.shuffle()
			var answer: Array = cols.slice(0, 1 if n <= 2 else 2)
			answer.sort()
			return {"type": type, "done": false, "rows": [["", answer]], "answer": answer, "pressed": []}
		"wires":  # two plugs into two sockets (order[socket] = colour, -1 = leave empty)
			var cols: Array = [0, 1, 2, 3]
			cols.shuffle()
			var socks: Array = [0, 1, 2, 3]
			socks.shuffle()
			var order: Array = [-1, -1, -1, -1]
			for k in 2:
				order[socks[k]] = cols[k]
			return {"type": type, "done": false, "order": order, "placed": [-1, -1, -1, -1]}
		"symbols":  # two shapes, left one first
			var m := _make("symbols", 1, ROCKET_NAMES.duplicate(), 1)
			m.order = (m.order as Array).slice(0, 2)
			return m
		"switches":  # one or two switches up
			var state: Array = []
			var answer: Array = []
			for k in SWITCH_COUNT:
				state.append(false)
				answer.append(false)
			var ks: Array = range(SWITCH_COUNT)
			ks.shuffle()
			for k in (1 if n <= 4 else 2):
				answer[ks[k]] = true
			return {"type": type, "done": false, "rows": [["", answer]], "answer": answer, "state": state}
	return _make(type, n, ROCKET_NAMES.duplicate(), 1)


## Manual rows: [rocket name ("" = any rocket), answer]. answers[0] belongs to this rocket (names[0]).
static func _rows(names: Array, keyed: int, answers: Array) -> Array:
	var rows: Array = []
	for i in keyed:
		rows.append([names[i] if keyed > 1 else "", answers[i]])
	rows.shuffle()
	return rows


static func make(type: String, n: int) -> Dictionary:
	return _make(type, n, ROCKET_NAMES.duplicate(), 1)


static func _make(type: String, n: int, names: Array, keyed: int) -> Dictionary:
	match type:
		"fuel":
			var length := clampi(n + 1, 2, 4)
			var answers: Array = []
			while answers.size() < keyed:
				var r: Array = []
				for k in length:
					r.append(randi() % COLORS.size())
				r.sort()
				if not answers.has(r):
					answers.append(r)
			return {"type": type, "done": false, "rows": _rows(names, keyed, answers), "answer": answers[0], "pressed": []}
		"wires":
			var order: Array = [0, 1, 2, 3]
			order.shuffle()
			order.resize(3 if n < 3 else 4)
			return {"type": type, "done": false, "order": order, "placed": [-1, -1, -1, -1]}
		"symbols":
			var all: Array = [0, 1, 2, 3, 4, 5]
			all.shuffle()
			var layout: Array = all.slice(0, 4)
			var order: Array = layout.duplicate()
			order.shuffle()
			order.resize(3 if n < 4 else 4)
			return {"type": type, "done": false, "layout": layout, "order": order, "step": 0}
		"gauge":
			var nums: Array = [2, 3, 4, 5, 6, 7, 8, 9]
			nums.shuffle()
			return {"type": type, "done": false, "rows": _rows(names, keyed, nums.slice(0, keyed)), "answer": nums[0], "value": 1}
		"switches":
			var answers: Array = []
			while answers.size() < keyed:
				var pat: Array = []
				var on := 0
				for k in SWITCH_COUNT:
					var b := randf() < 0.5
					pat.append(b)
					on += int(b)
				if on >= 1 and on <= 4 and not answers.has(pat):
					answers.append(pat)
			var state: Array = []
			for k in SWITCH_COUNT:
				state.append(false)
			return {"type": type, "done": false, "rows": _rows(names, keyed, answers), "answer": answers[0], "state": state}
		"alien":
			# Six different aliens on the crew's chart, each with its hello word. The pilot's desk shows one.
			var combos: Array = []
			for c in ALIEN_COLORS.size():
				for e in 3:
					for tp in ALIEN_TOPS.size():
						combos.append([c, e + 1, tp])
			combos.shuffle()
			var cast: Array = []
			var count := 4 if n < 4 else 6
			for i in count:
				var a: Array = combos[i]
				cast.append([int(a[0]), int(a[1]), int(a[2]), i % HELLO_WORDS.size()])
			cast.shuffle()
			var pick := randi() % cast.size()
			var answer: int = (cast[pick] as Array)[3]
			return {"type": type, "done": false, "cast": cast, "pick": pick, "answer": answer}
		"crank":
			var nums: Array = [2, 3, 4, 5] if n < 5 else [2, 3, 4, 5, 6]
			nums.shuffle()
			return {"type": type, "done": false, "rows": _rows(names, keyed, nums.slice(0, keyed)), "answer": nums[0], "turns": 0}
		"canister":
			var spot := randi() % CAN_SPOTS.size()
			return {"type": type, "done": false, "spot": spot, "pos": CAN_SPOTS[spot], "carrier": -1}
		"pipe":
			return {"type": type, "done": false, "spot": randi() % PIPE_SPOTS.size(), "progress": 0.0}
		"bolts":
			var spots: Array = range(BOLT_SPOTS.size())
			spots.shuffle()
			return {"type": type, "done": false, "spots": spots.slice(0, 3), "got": [false, false, false]}
		"paint":
			return {"type": type, "done": false, "answer": randi() % COLORS.size(), "carrier": -1, "carry": -1}
		"cat":
			var start: Vector3 = BOLT_SPOTS[randi() % BOLT_SPOTS.size()]
			return {"type": type, "done": false, "pos": start, "carrier": -1, "tired": 0.0}
	return {"type": type, "done": true}


static func is_job(type: String) -> bool:
	return type in ["canister", "pipe", "bolts", "paint", "cat"]
