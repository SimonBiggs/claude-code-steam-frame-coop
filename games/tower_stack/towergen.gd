extends RefCounted
## TOWER STACK generator: every tower JOB is made from a seed, so the same seed gives the same job on
## every machine (the host sends [seed, level, daily] and TV machines rebuild it), and
## tests/tower_stack_gen_test.gd proves over thousands of seeds that every job is buildable and fair.
##   var site := TowerGen.site(seed, level, daily)
##   site = {seed, level, daily, building, name, plan, top, set, wind, wind_dir, sway, sway_period,
##           ground, palette}
## plan: the target silhouette, bottom first: [kind, x, y, z, rot] (block centre on the stage, rot 0/1
##   = turned 0 / 90 degrees). kind: KINDS index (cube, plank, slab, stone: different shapes and weights).
## set: the blocks that drop into the park for this job, in order (the plan's blocks + spares).
## wind: a sideways push (m/s^2, gusting up to this) on the tower blocks; sway: the jelly stage rocks by
##   up to this angle (radians). Both are capped so the plan still stands with room to spare.
## Story: WREN the builder bird (wren.gd) asks for a building (lighthouse, castle, clock tower, windmill,
## bird nest). A built tower gets its roof and joins the TOWN (skyline.gd) behind the park: saved, it
## grows over days. TODAY'S TOWER: job DAILY_N on the first round each day is the same gold job everywhere.
## check(site) is the validator: physics-aware stacking (every block rests on something, every part's
## centre of mass stays over its support even tilted by the worst gust plus the stage's sway, nothing
## slides), the plan fits the stage and the giant's reach, the set has every block (+ spares), and
## est_secs() proves a crew of 0-6 helpers can deliver and stack it well inside a round.
## SECOND PASS:
##   SPECIAL BLOCKS (cube-sized): BOUNCY (springy jelly: slippery, TV players bounce sky-high off it), STICKY (honey:
##     glues to whatever it touches, so nothing tips or slides where it sits), BALLOON (two balloons lift it: light,
##     so wind pushes it about more). They open as Wren's town grows DISTRICTS (districts.gd: the `open` bitmask).
##     The validator weighs every block with its own weight, wind push and friction and treats honey joints as
##     glued, so every tower with special blocks still stands in its worst weather.
##   MODES (the shared GENTLE / BRAVE / HARD pick, core/pick_orbs.gd): gentle = calm and a level lower, hard = a level
##     higher, more weather and more special blocks. BRAVE with no districts open is the first pass's job exactly.
##   WEATHER EVENTS: a big GUST or a QUAKE (the stage shakes) at set times in a job, announced WARN_SECS early with a
##     warning ring round the stage (core/warn_rings.gd). Their strength is inside the plan's tipping limit too.
##   difficulty(site) rises smoothly job by job in every mode (tests/tower_stack_gen_test.gd).

const Seeded := preload("res://core/seeded.gd")
const MODE_IDS: Array[String] = ["gentle", "brave", "hard"]  # == core/pick_orbs.gd MODE_IDS (the test checks)

const GAME_ID := "tower_stack"
const B := 0.6  # == Looks.BLOCK (the test checks)
const BASE_R := 1.2  # == main.gd BASE_R
const BASE_H := 0.2  # == main.gd BASE_H
const ARENA := 9.0
const VR_SPOT := Vector2(0.0, 1.7)  # the giant stands here (x, z)
const REACH_TOP := 3.5  # a child giant (world scale 2.5) reaches about this high comfortably
const REACH_XZ := 2.6  # ...and this far from where they stand
const GRAVITY := 9.8
const FRICTION := 1.0  # block and stage physics materials
const MARGIN := 0.04  # m: centre of mass must stay this far inside its support
const SAFETY := 0.6  # wind + sway may use at most this share of the plan's tipping limit
const ROUND_SECS := 180.0
const JOB_MAX := 95.0  # every job is doable in this many seconds by any crew size (est_secs)
const MAX_LEVEL := 6
const CHOICES := 3  # buildings on the builder pick between jobs
const CHOICE_TRIES := 24
const DAILY_N := 2  # TODAY'S TOWER comes right after the warm-up tower
const DAILY_LEVEL := 3

## Block kinds: shape (in blocks), weight. cube, plank (long + flat), slab (half height), stone (heavy), and the
## special cube-sized ones: bouncy, sticky (honey), balloon.
const KINDS: Array[String] = ["cube", "plank", "slab", "stone", "bouncy", "sticky", "balloon"]
const K_CUBE := 0
const K_PLANK := 1
const K_SLAB := 2
const K_STONE := 3
const K_BOUNCY := 4
const K_STICKY := 5
const K_BALLOON := 6
const SPECIALS: Array[int] = [K_BOUNCY, K_STICKY, K_BALLOON]
const OPEN_ALL := 7  # every special block open (bit k = SPECIALS[k])
const SIZE: Array[Vector3] = [Vector3(1, 1, 1), Vector3(2, 0.5, 1), Vector3(1, 0.5, 1), Vector3(1, 1, 1),
	Vector3(1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 1)]
const MASS: Array[float] = [1.0, 1.0, 0.6, 2.5, 0.8, 1.0, 1.0]
## Share of its weight that still presses down (the balloons lift the rest: main.gd pushes it up with the rest).
const HEAVY: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.4]
## Physics material per kind (main.gd uses these; Godot combines two touching blocks' friction as the smaller).
const FRIC: Array[float] = [1.0, 1.0, 1.0, 1.0, 0.6, 1.0, 1.0]
const BOUNCE: Array[float] = [0.05, 0.05, 0.05, 0.05, 0.6, 0.0, 0.05]
## Seconds one helper takes to push a block of this kind to the pad and come back (stone is heavy).
const TRIP: Array[float] = [7.0, 7.5, 6.5, 10.0, 7.0, 7.5, 6.0]
const SPAWN_SECS := 2.2  # main.gd drops a block this often (when there's room)
const PAD_HELP := 10.0  # main.gd: no block on the pad this long -> Wren drops the needed one right on it
const STACK_SECS := 5.5  # the crane's cycle (the giant is quicker)
const CHEER_SECS := 6.0  # the celebration between jobs

## Buildings: name, layer recipe (base, middle choices, top) and the topper the finished tower wears.
const BUILDINGS: Array[String] = ["lighthouse", "castle", "clock", "windmill", "nest"]
const NAMES: Array[String] = ["LIGHTHOUSE", "CASTLE", "CLOCK TOWER", "WINDMILL", "BIRD NEST"]
const RECIPES := {
	"lighthouse": {"base": ["stone"], "mid": ["cube", "cube", "slab"], "top": ["slab", "cube"]},
	"castle": {"base": ["pair"], "mid": ["plank", "pair", "cube"], "top": ["pair", "cube"]},
	"clock": {"base": ["stone", "cube"], "mid": ["cube", "slab", "stone"], "top": ["cube"]},
	"windmill": {"base": ["cube", "stone"], "mid": ["cube", "slab"], "top": ["plank"]},
	"nest": {"base": ["cube", "pair"], "mid": ["slab", "cube", "plank"], "top": ["plank", "slab"]},
}
## Layers per level (1-6); level 1-2 are calm, wind from 3, the wobbly jelly stage from 4.
const LAYERS: Array[int] = [3, 4, 4, 5, 5, 6]
const WIND_MAX: Array[float] = [0.0, 0.0, 0.5, 0.8, 1.0, 1.2]
const SWAY_MAX: Array[float] = [0.0, 0.0, 0.0, 0.03, 0.04, 0.05]
## Special blocks per level (from the open ones), weather events per level (from level 3; quakes from 4).
const SPECIALS_AT: Array[int] = [0, 1, 1, 2, 2, 3]
const EVENTS_AT: Array[int] = [0, 0, 1, 1, 2, 2]
const GUST_MAX: Array[float] = [0.0, 0.0, 0.7, 0.8, 0.9, 1.0]  # extra wind (m/s^2) at a GUST's peak
const QUAKE_MAX: Array[float] = [0.0, 0.0, 0.0, 0.02, 0.025, 0.03]  # extra stage tilt (radians) in a QUAKE
const WARN_SECS := 3.0  # the warning ring shows this long before an event
const EVENT_SECS := 2.5  # an event lasts this long
const FIRST_EVENT := 16.0  # no event before this many seconds into a job
const EVENT_GAP := 18.0  # at least this between events
## Per mode: level shift, weather share, extra special blocks, extra events, extra spares, top level.
const MODE_TUNE := {
	"gentle": {"shift": -1, "weather": 0.0, "specials": 0, "events": -9, "spares": 1, "max": 4},
	"brave": {"shift": 0, "weather": 1.0, "specials": 0, "events": 0, "spares": 0, "max": MAX_LEVEL},
	"hard": {"shift": 1, "weather": 1.2, "specials": 1, "events": 1, "spares": 0, "max": MAX_LEVEL},
}
## Which special blocks each mode likes (weights for bouncy, sticky, balloon): gentle loves honey.
const SPECIAL_LIKES := {"gentle": [2, 4, 1], "brave": [2, 2, 2], "hard": [2, 1, 3]}
## Ground themes: grass, path (park ring), flower colours are the core palette.
const GROUNDS: Array[String] = ["meadow", "beach", "snow", "autumn"]
const GROUND_COLORS := {
	"meadow": [Color(0.45, 0.75, 0.38), Color(0.55, 0.82, 0.45)],
	"beach": [Color(0.93, 0.85, 0.6), Color(0.97, 0.9, 0.7)],
	"snow": [Color(0.88, 0.92, 0.98), Color(0.95, 0.97, 1.0)],
	"autumn": [Color(0.72, 0.62, 0.32), Color(0.8, 0.68, 0.38)],
}
## The town: rows of finished towers on an arc behind the park (beyond the walk edge, before the trees).
const TOWN_R: Array[float] = [10.4, 11.9]
const TOWN_ARC := 2.5  # radians of arc behind the stage (centred on -z)
const TOWN_STEP := 1.55
const TOWN_SCALE := 0.7
const TOWN_KEEP := 40


static func job_seed(session_seed: int, round_no: int, n: int) -> int:
	return Seeded.derive(session_seed, "job%d.%d" % [round_no, n])


static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


## The challenge for job n of a round (1 = the warm-up), nudged up by towers built over all days, shifted by mode.
static func level(n: int, built_total: int, mode: String = "brave") -> int:
	var t: Dictionary = tune(mode)
	return clampi(n + mini(built_total / 8, 2) + int(t.shift), 1, int(t.max))


static func tune(mode: String) -> Dictionary:
	return MODE_TUNE.get(mode, MODE_TUNE["brave"])


static func is_special(kind: int) -> bool:
	return SPECIALS.has(kind)


## Seed of choice k for job n (the builder pick between jobs offers a few; choice 0 is the plain job_seed).
static func choice_seed(session_seed: int, round_no: int, n: int, k: int) -> int:
	return job_seed(session_seed, round_no, n) if k == 0 else Seeded.derive(session_seed, "job%d.%d.%d" % [round_no, n, k])


## The builder pick's offer for job n: up to CHOICES jobs of level lv, each a different building.
static func choices(session_seed: int, round_no: int, n: int, lv: int, mode: String, open: int) -> Array:
	var out: Array = []
	var seen := {}
	for k in CHOICE_TRIES:
		var s := site(choice_seed(session_seed, round_no, n, k), lv, false, mode, open)
		if seen.has(s.building):
			continue
		seen[s.building] = true
		out.append(s)
		if out.size() == CHOICES:
			break
	return out


static func size_of(kind: int, rot: int = 0) -> Vector3:
	var s := SIZE[kind] * B
	return Vector3(s.z, s.y, s.x) if rot == 1 else s


## One job. mode: gentle / brave / hard; open: bitmask of the special blocks Wren's town has opened (districts.gd).
static func site(seed_value: int, lv: int, daily: bool = false, mode: String = "brave", open: int = 0) -> Dictionary:
	lv = clampi(lv, 1, MAX_LEVEL)
	if not MODE_TUNE.has(mode):
		mode = "brave"
	var t: Dictionary = tune(mode)
	var r := Seeded.rng(seed_value, "plan")
	var bi := r.randi() % BUILDINGS.size()
	var building := BUILDINGS[bi]
	var plan := _plan(r, building, LAYERS[lv - 1])
	while _top(plan) > REACH_TOP and plan.size() > 2:  # never above the giant's reach
		plan = _plan(r, building, _layer_count(plan) - 1)
	var specials := _add_specials(plan, Seeded.rng(seed_value, "special"), SPECIALS_AT[lv - 1] + int(t.specials), open, mode)
	var w := Seeded.rng(seed_value, "weather")
	var wind := 0.0
	var wk := float(t.weather)
	if WIND_MAX[lv - 1] > 0.0 and w.randf() < 0.8:
		wind = snappedf(w.randf_range(0.5, 1.0) * WIND_MAX[lv - 1] * wk, 0.01)
	var wind_dir := snappedf(w.randf() * TAU, 0.01)
	var sway := 0.0
	if SWAY_MAX[lv - 1] > 0.0 and w.randf() < 0.6:
		sway = snappedf(minf(w.randf_range(0.6, 1.0) * SWAY_MAX[lv - 1] * wk, 0.06), 0.001)
	var events := _events(Seeded.rng(seed_value, "events"), lv, mode)
	# Physics-aware cap: the worst gust + the stage's tilt (+ the strongest event) use at most SAFETY of the
	# plan's tipping limit (special blocks included: a balloon block tips at a smaller lean).
	var limit := safe_tan(plan) * SAFETY
	var ev := event_peaks(events)
	var need := (wind + ev.x) / GRAVITY + tan(sway + ev.y)
	if need > limit and need > 0.0:
		var k := limit / need
		wind = floorf(wind * k * 100.0) / 100.0
		sway = floorf(sway * k * 1000.0) / 1000.0
		for e in events:
			e[2] = floorf(float(e[2]) * k * 1000.0) / 1000.0
		events = events.filter(func(e: Array) -> bool: return float(e[2]) > 0.0)
	var set: Array = []
	for b in plan:
		set.append(int(b[0]))
	var spares := 1 + (1 if wind > 0.0 else 0) + (1 if sway > 0.0 else 0) + int(t.spares)
	for i in spares:
		set.append(K_PLANK if i == 0 and set.has(K_PLANK) else K_CUBE)
	var c := Seeded.rng(seed_value, "look")
	var palette: Array = Seeded.shuffled(c, [0, 1, 2, 3, 4, 5]).slice(0, 3)
	return {"seed": seed_value, "level": lv, "daily": daily, "mode": mode, "open": open, "building": building,
		"name": NAMES[bi], "plan": plan, "top": snappedf(_top(plan), 0.001), "set": set, "wind": wind,
		"wind_dir": wind_dir, "sway": sway, "sway_period": snappedf(c.randf_range(4.0, 6.5), 0.1),
		"ground": GROUNDS[c.randi() % GROUNDS.size()], "palette": palette, "events": events, "specials": specials}


## Turn up to `count` single cubes of the plan into open special blocks (each one only if the tower still stands
## with it, no weather). Returns how many.
static func _add_specials(plan: Array, r: RandomNumberGenerator, count: int, open: int, mode: String) -> int:
	var kinds: Array = []
	var likes: Array = []
	var pref: Array = SPECIAL_LIKES.get(mode, SPECIAL_LIKES["brave"])
	for k in SPECIALS.size():
		if (open >> k) & 1 == 1:
			kinds.append(SPECIALS[k])
			likes.append(pref[k])
	if kinds.is_empty() or count <= 0:
		return 0
	var spots: Array = []
	for i in plan.size():
		if int(plan[i][0]) == K_CUBE:
			spots.append(i)
	var done := 0
	for i in Seeded.shuffled(r, spots):
		if done >= count:
			break
		var kind: int = kinds[Seeded.weighted(r, likes)]
		plan[i][0] = kind
		if stability(plan, 0.0).is_empty():
			done += 1
		else:
			plan[i][0] = K_CUBE
	return done


## A job's weather events: [[seconds into the job, "gust" | "quake", strength], ...] (gust: m/s^2 of extra wind,
## quake: radians of extra stage tilt), in time order.
static func _events(r: RandomNumberGenerator, lv: int, mode: String) -> Array:
	var t: Dictionary = tune(mode)
	var n := EVENTS_AT[lv - 1] + int(t.events)
	if lv < 3 or n <= 0 or float(t.weather) <= 0.0:
		return []
	var out: Array = []
	var at := FIRST_EVENT + r.randf_range(0.0, 8.0)
	for i in n:
		if at + EVENT_SECS > JOB_MAX - 5.0:
			break
		var quake := lv >= 4 and r.randf() < 0.5
		var top := (QUAKE_MAX[lv - 1] if quake else GUST_MAX[lv - 1]) * minf(float(t.weather), 1.0)
		out.append([snappedf(at, 0.1), "quake" if quake else "gust", snappedf(r.randf_range(0.6, 1.0) * top, 0.001)])
		at += EVENT_GAP + r.randf_range(0.0, 8.0)
	return out


## The strongest gust (x, m/s^2) and quake (y, radians) of a job's events.
static func event_peaks(events: Array) -> Vector2:
	var p := Vector2.ZERO
	for e in events:
		if String(e[1]) == "gust":
			p.x = maxf(p.x, float(e[2]))
		else:
			p.y = maxf(p.y, float(e[2]))
	return p


## The worst lean a job's tower must survive: wind gust + stage sway + its strongest events.
static func worst_lean(s: Dictionary) -> float:
	var ev := event_peaks(s.get("events", []))
	return (float(s.wind) + ev.x) / GRAVITY + tan(float(s.sway) + ev.y)


## How hard a job is (one number: blocks, height, weather, special blocks, events). Rises job by job in every mode.
static func difficulty(s: Dictionary) -> float:
	return (s.plan as Array).size() + 2.0 * float(s.top) + 12.0 * worst_lean(s) + 0.5 * int(s.get("specials", 0)) \
		+ 0.5 * (s.get("events", []) as Array).size()


## The compact description the host sends ("job" state); TV machines call from_job() to rebuild it.
## [seed, level, daily, mode index, open] (old saves' 3-long entries rebuild as brave with nothing open).
static func job_of(s: Dictionary) -> Array:
	return [int(s.seed), int(s.level), 1 if s.daily else 0, maxi(0, MODE_IDS.find(String(s.get("mode", "brave")))),
		int(s.get("open", 0))]


static func from_job(j: Array) -> Dictionary:
	if j.size() < 3:
		return {}
	if j.size() < 5:
		return site(int(j[0]), int(j[1]), int(j[2]) == 1)
	return site(int(j[0]), int(j[1]), int(j[2]) == 1, MODE_IDS[clampi(int(j[3]), 0, MODE_IDS.size() - 1)], int(j[4]))


static func _layer_count(plan: Array) -> int:
	var ys := {}
	for b in plan:
		ys[snappedf(float(b[2]) - size_of(int(b[0]), int(b[4])).y * 0.5, 0.001)] = true
	return ys.size()


## Stack layers bottom-up following the building's recipe. A layer is one block or a "pair" (two cubes
## side by side). Pairs stand on the stage or on a plank along the same line; a plank bridges a pair
## (same line) or balances on one block (a T).
static func _plan(r: RandomNumberGenerator, building: String, layers: int) -> Array:
	var rec: Dictionary = RECIPES[building]
	var seq: Array = [Seeded.pick(r, rec.base)]
	for i in maxi(0, layers - 2):
		seq.append(Seeded.pick(r, rec.mid))
	seq.append(Seeded.pick(r, rec.top))
	# Grammar fixes: a pair only on the stage or on a plank.
	for i in range(1, seq.size()):
		if seq[i] == "pair" and seq[i - 1] != "plank":
			seq[i] = "cube"
	var plan: Array = []
	var below: Array = []  # the previous layer's blocks
	var floor_y := BASE_H
	var axis := r.randi() % 2  # the line pairs and bridges follow (0 = x, 1 = z)
	for layer in seq:
		var cx := 0.0
		var cz := 0.0
		if not below.is_empty():
			for b in below:
				cx += float(b[1]) / below.size()
				cz += float(b[3]) / below.size()
		var made: Array = []
		match String(layer):
			"pair":
				var along := Vector2(1, 0) if axis == 0 else Vector2(0, 1)
				for sgn in [-1.0, 1.0]:
					var off := along * B * 0.5 * float(sgn)
					made.append([K_CUBE, cx + off.x, floor_y + B * 0.5, cz + off.y, 0])
			"plank":
				var rot := axis if below.size() == 2 else r.randi() % 2
				axis = rot
				made.append([K_PLANK, cx, floor_y + B * 0.25, cz, rot])
			_:
				var kind := KINDS.find(String(layer))
				var jx := 0.0
				var jz := 0.0
				if below.size() == 1 and int(below[0][0]) != K_PLANK:
					jx = snappedf(r.randf_range(-0.06, 0.06), 0.01)
					jz = snappedf(r.randf_range(-0.06, 0.06), 0.01)
				elif below.size() == 1:  # on a plank: may sit off-centre along it
					var slide := snappedf(r.randf_range(-0.12, 0.12), 0.01)
					jx = slide if int(below[0][4]) == 0 else 0.0
					jz = slide if int(below[0][4]) == 1 else 0.0
				made.append([kind, cx + jx, floor_y + size_of(kind).y * 0.5, cz + jz, 0])
		for m in made:
			m[1] = snappedf(float(m[1]), 0.001)
			m[2] = snappedf(float(m[2]), 0.001)
			m[3] = snappedf(float(m[3]), 0.001)
		plan.append_array(made)
		below = made
		var top := 0.0
		for m in made:
			top = maxf(top, float(m[2]) + size_of(int(m[0]), int(m[4])).y * 0.5)
		floor_y = top
	return plan


static func _top(plan: Array) -> float:
	var t := BASE_H
	for b in plan:
		t = maxf(t, float(b[2]) + size_of(int(b[0]), int(b[4])).y * 0.5)
	return t


## Footprint rect (x0, z0, x1, z1) and bottom / top heights of a plan block.
static func _box(b: Array) -> Array:
	var s := size_of(int(b[0]), int(b[4])) * 0.5
	return [float(b[1]) - s.x, float(b[3]) - s.z, float(b[1]) + s.x, float(b[3]) + s.z,
		float(b[2]) - s.y, float(b[2]) + s.y]


static func _overlap(a: Array, b: Array) -> Array:
	var x0 := maxf(a[0], b[0])
	var z0 := maxf(a[1], b[1])
	var x1 := minf(a[2], b[2])
	var z1 := minf(a[3], b[3])
	return [x0, z0, x1, z1] if x1 - x0 > 0.01 and z1 - z0 > 0.01 else []


## What each plan block rests on: index -> Array of [supporter index (-1 = stage), contact rect].
static func supports(plan: Array) -> Array:
	var out: Array = []
	var boxes: Array = []
	for b in plan:
		boxes.append(_box(b))
	for i in plan.size():
		var bi: Array = boxes[i]
		var sup: Array = []
		if absf(float(bi[4]) - BASE_H) < 0.005:
			sup.append([-1, [bi[0], bi[1], bi[2], bi[3]]])
		else:
			for j in plan.size():
				if j != i and absf(float(boxes[j][5]) - float(bi[4])) < 0.005:
					var o := _overlap(bi, boxes[j])
					if not o.is_empty():
						sup.append([j, o])
		out.append(sup)
	return out


## Does the plan stand when everything leans by tan_tilt (wind gust + stage sway) in any direction?
## Two kinds of check: every block with the blocks that rest only on it (it could tip off its own
## support, or slide), and every cut through the tower (everything above a level could tip as one).
## Each block weighs MASS * HEAVY (a balloon block presses down less) but the wind pushes its whole MASS, so a
## light block leans further; a contact grips with the smaller FRIC of its two sides (bouncy jelly is slippery);
## a STICKY honey block is glued to everything it touches (it can't tip or slide off, nor can what sits on it).
static func stability(plan: Array, tan_tilt: float, margin: float = MARGIN) -> Array:
	var why: Array = []
	var sup := supports(plan)
	var boxes: Array = []
	for b in plan:
		boxes.append(_box(b))
	for i in plan.size():
		if (sup[i] as Array).is_empty():
			why.append("block %d floats" % i)
	if not why.is_empty():
		return why
	# Per block: its load = itself + whatever rests (only, transitively) on it.
	for i in plan.size():
		if _glued_down(plan, sup, i):
			continue
		var load := {i: true}
		for k in range(i + 1, plan.size()):
			var all_in := true
			for s in sup[k]:
				if not load.has(int(s[0])):
					all_in = false
			if all_in:
				load[k] = true
		var patches: Array = []
		var grip := FRIC[int(plan[i][0])]
		for s in sup[i]:
			patches.append(s[1])
			grip = minf(grip, 1.0 if int(s[0]) < 0 else FRIC[int(plan[int(s[0])][0])])
		var bad := _tips(plan, load.keys(), patches, float(boxes[i][4]), tan_tilt, margin)
		if bad != "":
			why.append("block %d (%s) %s" % [i, KINDS[int(plan[i][0])], bad])
		var push := _push_ratio(plan, load.keys()) * tan_tilt
		if push >= grip:
			why.append("block %d (%s) slides (push %.2f >= grip %.2f)" % [i, KINDS[int(plan[i][0])], push, grip])
	# Per cut: everything at or above each bottom level vs its contacts with what's below (a cut held by honey
	# anywhere along it can't tip there).
	var levels := {}
	for bx in boxes:
		levels[snappedf(float(bx[4]), 0.001)] = true
	for y in levels:
		var above: Array = []
		var patches2: Array = []
		var glued := false
		for i in plan.size():
			if float(boxes[i][4]) >= float(y) - 0.005:
				above.append(i)
		for i in above:
			if absf(float(boxes[i][4]) - float(y)) > 0.005:
				continue
			for s in sup[i]:
				if not above.has(int(s[0])):
					patches2.append(s[1])
					if int(plan[i][0]) == K_STICKY or (int(s[0]) >= 0 and int(plan[int(s[0])][0]) == K_STICKY):
						glued = true
		if glued:
			continue
		var bad2 := _tips(plan, above, patches2, float(y), tan_tilt, margin)
		if bad2 != "":
			why.append("the part above %.2f m %s" % [float(y), bad2])
	if tan_tilt >= FRICTION:
		why.append("blocks would slide (tilt %.2f >= friction %.2f)" % [tan_tilt, FRICTION])
	return why


## Is block i glued to everything under it (it's honey, or it sits only on honey)?
static func _glued_down(plan: Array, sup: Array, i: int) -> bool:
	if int(plan[i][0]) == K_STICKY:
		return true
	for s in sup[i]:
		if int(s[0]) < 0 or int(plan[int(s[0])][0]) != K_STICKY:
			return false
	return not (sup[i] as Array).is_empty()


## Sideways push per weight of these blocks for a lean of 1 (the wind pushes all their mass, only HEAVY presses).
static func _push_ratio(plan: Array, ids: Array) -> float:
	var m := 0.0
	var w := 0.0
	for i in ids:
		var k := int(plan[int(i)][0])
		m += MASS[k]
		w += MASS[k] * HEAVY[k]
	return m / maxf(w, 0.001)


## "" if the blocks' centre of weight stays inside the patches' outline (shifted by the lean), else why.
## The lean shift is the wind's turning push (every block's whole mass at its height) over their weight.
static func _tips(plan: Array, ids: Array, patches: Array, floor_y: float, t: float, m: float) -> String:
	if patches.is_empty():
		return "has nothing under it"
	var weight := 0.0
	var com := Vector3.ZERO
	var turn := 0.0
	for i in ids:
		var b: Array = plan[int(i)]
		var k := int(b[0])
		var w := MASS[k] * HEAVY[k]
		weight += w
		com += Vector3(float(b[1]), float(b[2]), float(b[3])) * w
		turn += MASS[k] * (float(b[2]) - floor_y)
	com /= weight
	var x0 := INF
	var z0 := INF
	var x1 := -INF
	var z1 := -INF
	for p in patches:
		x0 = minf(x0, p[0])
		z0 = minf(z0, p[1])
		x1 = maxf(x1, p[2])
		z1 = maxf(z1, p[3])
	var lean := turn * t / weight
	if com.x - lean < x0 + m or com.x + lean > x1 - m or com.z - lean < z0 + m or com.z + lean > z1 - m:
		return "tips over (centre %.2f,%.2f, lean %.2f, support x %.2f..%.2f z %.2f..%.2f)" % [com.x, com.z, lean, x0, x1, z0, z1]
	return ""


## The largest lean (tan of the angle) the plan survives with MARGIN to spare.
static func safe_tan(plan: Array) -> float:
	if not stability(plan, 0.0).is_empty():
		return 0.0
	var lo := 0.0
	var hi := FRICTION
	for i in 12:
		var mid := (lo + hi) * 0.5
		if stability(plan, mid).is_empty():
			lo = mid
		else:
			hi = mid
	return lo


## Estimated seconds for a crew of `crew` helpers (0 = blocks drop straight on the pad) and the giant
## or the crane to build this job, including blocks lost to wobbles on windy / swaying sites.
static func est_secs(s: Dictionary, crew: int) -> float:
	var per := 0.0
	var count := (s.plan as Array).size()
	var lost := ceili(count * 0.3) if float(s.wind) > 0.0 or float(s.sway) > 0.0 or not (s.get("events", []) as Array).is_empty() else 0
	var kinds: Array = (s.set as Array).slice(0, count + lost) if (s.set as Array).size() >= count + lost else (s.set as Array)
	for k in kinds:
		var deliver := SPAWN_SECS if crew == 0 else maxf(SPAWN_SECS, minf(TRIP[int(k)] / crew, PAD_HELP))
		per += maxf(deliver, STACK_SECS)
	for i in maxi(0, count + lost - kinds.size()):
		per += maxf(SPAWN_SECS if crew == 0 else maxf(SPAWN_SECS, minf(TRIP[K_CUBE] / crew, PAD_HELP)), STACK_SECS)
	return per + CHEER_SECS


## The validator: reasons this job is NOT buildable / fair (empty = fine).
static func check(s: Dictionary) -> Array:
	var why: Array = []
	var plan: Array = s.plan
	if plan.size() < 3:
		why.append("too few blocks (%d)" % plan.size())
	var lean := worst_lean(s)
	for w in stability(plan, lean):
		why.append("unstable in the weather: %s" % w)
	if float(s.top) > REACH_TOP + 0.001:
		why.append("top %.2f m is out of the giant's reach" % float(s.top))
	if float(s.top) < BASE_H + B * 1.4:
		why.append("too short to be a tower (%.2f m)" % float(s.top))
	var boxes: Array = []
	for b in plan:
		var bx := _box(b)
		for c in [[bx[0], bx[1]], [bx[2], bx[1]], [bx[0], bx[3]], [bx[2], bx[3]]]:
			if Vector2(c[0], c[1]).length() > BASE_R - 0.02:
				why.append("block %s hangs off the stage" % str(b))
		if Vector2(float(b[1]) - VR_SPOT.x, float(b[3]) - VR_SPOT.y).length() > REACH_XZ:
			why.append("block %s is out of the giant's reach" % str(b))
		for o in boxes:
			if not _overlap(bx, o).is_empty() and minf(bx[5], o[5]) - maxf(bx[4], o[4]) > 0.005:
				why.append("blocks overlap at %s" % str(b))
		boxes.append(bx)
	# The set has every block of the plan, plus spares, in plan order (bottom first).
	var set: Array = s.set
	if set.size() < plan.size() + 1:
		why.append("no spare blocks")
	for i in plan.size():
		if i >= set.size() or int(set[i]) != int(plan[i][0]):
			why.append("block %d of the set doesn't match the plan" % i)
			break
	for k in set:
		if int(k) < 0 or int(k) >= KINDS.size():
			why.append("unknown block kind %d" % int(k))
	for crew in range(0, 7):
		var secs := est_secs(s, crew)
		if secs > JOB_MAX:
			why.append("crew %d needs %.0f s (max %.0f)" % [crew, secs, JOB_MAX])
	if float(s.wind) < 0.0 or float(s.sway) < 0.0 or float(s.sway) > 0.08:
		why.append("bad weather numbers")
	if int(s.level) < 3 and (float(s.wind) > 0.0 or float(s.sway) > 0.0):
		why.append("warm-up levels are calm")
	var mode := String(s.get("mode", "brave"))
	if not MODE_TUNE.has(mode):
		why.append("unknown mode %s" % mode)
	var open := int(s.get("open", 0))
	var specials := 0
	for b in plan:
		var k := int(b[0])
		if is_special(k):
			specials += 1
			if (open >> SPECIALS.find(k)) & 1 == 0:
				why.append("special block %s isn't open yet" % KINDS[k])
	if specials != int(s.get("specials", 0)):
		why.append("special block count is off")
	if mode == "gentle" and (float(s.wind) > 0.0 or float(s.sway) > 0.0 or not (s.events as Array).is_empty()):
		why.append("gentle jobs are calm")
	if int(s.level) > int(tune(mode).max):
		why.append("level %d is too high for %s" % [int(s.level), mode])
	var last := -INF
	for e in s.get("events", []):
		var at := float(e[0])
		if at < FIRST_EVENT - 0.01 or at - last < EVENT_GAP - 0.01:
			why.append("weather event at %.1f s comes too soon" % at)
		if at < WARN_SECS + 5.0:
			why.append("weather event at %.1f s has no time to warn" % at)
		if at + EVENT_SECS > JOB_MAX:
			why.append("weather event at %.1f s is past the job" % at)
		if not String(e[1]) in ["gust", "quake"] or float(e[2]) <= 0.0:
			why.append("bad weather event %s" % str(e))
		if String(e[1]) == "quake" and int(s.level) < 4:
			why.append("quakes come from level 4")
		last = at
	if (s.palette as Array).size() != 3:
		why.append("palette needs three colours")
	if not GROUNDS.has(String(s.ground)):
		why.append("unknown ground")
	return why


# --- The town --------------------------------------------------------------------------------

static func town_size() -> int:
	var n := 0
	for r in TOWN_R:
		n += int(floor(r * TOWN_ARC / TOWN_STEP)) + 1
	return n


## Where finished tower i stands (the first ones right behind the stage, then outwards); INF past the end.
static func town_slot(i: int) -> Vector3:
	var spots: Array = []
	for row in TOWN_R.size():
		var r: float = TOWN_R[row]
		var count := int(floor(r * TOWN_ARC / TOWN_STEP)) + 1
		var step := TOWN_ARC / float(count - 1)
		for k in count:
			var a := -PI * 0.5 - TOWN_ARC * 0.5 + step * k
			spots.append([row, absf(a + PI * 0.5) + (0.0 if row == 0 else 0.07), Vector3(cos(a) * r, 0.0, sin(a) * r)])
	spots.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0] or (p[0] == q[0] and p[1] < q[1]))
	return (spots[i][2] as Vector3) if i >= 0 and i < spots.size() else Vector3.INF
