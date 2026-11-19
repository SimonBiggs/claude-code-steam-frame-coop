extends RefCounted
## SKY BOTS: the island generator and its validator (no nodes: the game, the bots and tests/sky_bots_gen_test.gd all
## use it). Every machine builds the same island from a tiny description {"i": island, "s": seed, "m": mode}.
## An island is a row of floating platforms along +X (the robots run that way; the VR giant stands on the cloud floor
## at +Z and looks down on it like a toy diorama). Sections, each a little idea:
##   steps   hop over gaps, up and down          mover   a platform carries you across a wide gap
##   lift    a lift goes up a tall step (the VR giant can lift it with a hand; it goes up by itself too)
##   patrol  a long floor with GRUMBLE bots (punch them, hop on them; they wind up before they charge: a warn line)
##   zap     a floor with ZAP PADS (they flash on warn rings before they buzz; there's always a safe lane)
##   secret  a little side island with a CRACKED WALL: punch it open, the room behind it hides the GOLD GEAR
##   spring  a SPRING PAD throws you up onto a high ledge nothing else reaches (SNOWY PEAKS loves them)
##   fan     a gap far too wide to hop with a WIND FAN in it: its updraft floats you across (JUNGLE JUMBLE)
##   belt    a CONVEYOR BELT floor carries you along, forwards or backwards (CLOCKWORK KEEP)
## two BOT BOXES (a little bot inside: rescue it and it moves to Gizmo Town), then the SPARK on its pedestal at the end
## (the goal), or a boss arena first: CRAB COVE's CRANKY CRAB, CLOCKWORK KEEP's KING KEYWIND (the spark drops when
## the boss is beaten). check() proves every island can be finished from the robots' real jump numbers.

const Seeded := preload("res://core/seeded.gd")

const GAME_ID := "sky_bots"
# The robots' movement (robot.gd moves with exactly these; check() proves every jump with them).
const RUN := 6.0
const ACCEL := 40.0
const AIR_ACCEL := 18.0
const JUMP_V := 9.0
const GRAVITY := 24.0
const HOVER_FALL := 1.6  ## holding A while falling: no faster than this ...
const HOVER_TIME := 0.9  ## ... for this long per jump (a bonus: check() never counts on it)
const ROBOT_R := 0.35
const ROBOT_H := 1.0
const REACH_K := 0.68  ## a jump may use this share of the robot's best jump
const MAX_RISE := 1.15  ## the highest step up a jump may need (a jump reaches ~1.69)
const HEAD_ROOM := 2.4  ## nothing hangs lower than this over a floor
const THICK := 0.8  ## platform slab
const X_MIN := -34.0  ## the islands stay within the giant's walk (giant.gd WALK_X) ...
const X_MAX := 34.0
const Y_MIN := 0.0
const Y_MAX := 6.0
const FALL_BELOW := 4.0  ## a robot this far under the lowest floor pops back at its checkpoint
const MAX_CP_GAP := 26.0  ## a pop-back never costs more than ~4 s of running
const TOUCH := 0.75  ## a robot's middle this near a bolt / the gear / the spark takes it
const LIFT_PERIOD := 6.0
const ZAP_PERIOD := 4.0
const ZAP_TELL := 0.4  ## share of a zap's cycle it flashes on its warn ring first (1.6 s) ...
const ZAP_HOT := 0.2  ## ... then buzzes (0.8 s); off the rest of the time
const ZAP_LANE := 0.8  ## a zap floor always keeps a safe lane this wide
const ROOM := Vector3(3.0, 2.2, 2.6)  ## the secret room inside (x, height, z)
# Island gadgets (the second chapter's islands; TODAY'S ISLAND mixes them in too).
const SPRING_V := 14.0  ## a SPRING PAD throws a robot up this fast (check() proves every spring hop with it)
const SPRING_R := 0.6  ## a robot's feet this near a spring's middle bounce
const SPRING_RISE := 3.4  ## the highest ledge a spring hop may need (a spring reaches ~4.1)
const BELT := 2.2  ## a CONVEYOR BELT carries robots this fast along X (robot.gd adds it while they stand on it)
const FAN_UP := 3.2  ## a WIND FAN's updraft lifts a robot this fast ...
const FAN_TOP := 2.6  ## ... up to this high over the floors either side
# Robot moves that are a bonus (check() never counts on them): X in the air DASHES, B in the air POUNDS.
const DASH_V := 8.5
const POUND_V := 16.0
const POUND_R := 1.6  ## a pound's landing pops grumbles and opens bot boxes this near
const BOX_R := 0.75  ## a BOT BOX (a little bot inside): a robot this near opens it (or a punch / a pound)

const SIZE := {"spring": 13.5, "fan": 12.5, "belt": 11.5}  ## the longest a gadget section gets (the others fit in 9)
const ISLANDS := 6
const ISLAND_NAMES: Array[String] = ["MEADOW HOP", "GEAR WORKS", "CRAB COVE", "SNOWY PEAKS", "JUNGLE JUMBLE", "CLOCKWORK KEEP"]
const ISLAND_PICS: Array[String] = ["meadowisle", "gearisle", "coveisle", "snowisle", "jungleisle", "clockisle"]
const THEMES: Array[String] = ["meadow", "gears", "cove", "snow", "jungle", "clock"]
const BOSSES := {3: "crab", 6: "king"}
const SIGNATURE := {4: "spring", 5: "fan", 6: "belt"}  ## each far island's own gadget (always there, early on)  ## the islands that end on a boss arena: Cranky Crab, King Keywind
const DAILY_NAME := "TODAY'S ISLAND"
## Each island's sections (shuffled, "steps" first; the secret is never first; the goal / boss arena comes last).
const POOLS := {
	1: ["steps", "lift", "patrol", "secret", "zap"],
	2: ["steps", "mover", "lift", "zap", "secret", "patrol"],
	3: ["steps", "mover", "patrol", "secret", "zap", "lift"],
	4: ["steps", "spring", "mover", "secret", "spring", "patrol"],
	5: ["steps", "fan", "lift", "secret", "fan", "zap"],
	6: ["steps", "belt", "spring", "secret", "fan", "belt"],
	0: ["steps", "mover", "lift", "patrol", "zap", "secret", "spring", "fan", "belt"],
}
## GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES): floor width, the widest hop, grumbles per patrol, zap pads per
## zap floor, how fast movers / grumbles go, Cranky Crab's bonks.
const MODES := {
	"gentle": {"w": 3.6, "gap": 1.6, "grumbles": 1, "zaps": 1, "speed": 0.75, "boss_hp": 3, "dash": 5.0},
	"brave": {"w": 3.0, "gap": 2.2, "grumbles": 1, "zaps": 2, "speed": 1.0, "boss_hp": 4, "dash": 6.5},
	"hard": {"w": 2.6, "gap": 2.6, "grumbles": 2, "zaps": 2, "speed": 1.3, "boss_hp": 6, "dash": 8.0},
}


static func mode_of(m: String) -> String:
	return m if MODES.has(m) else "brave"


static func island_name(d: Dictionary) -> String:
	var i := int(d.get("i", 1))
	return DAILY_NAME if i == 0 else ISLAND_NAMES[clampi(i - 1, 0, ISLANDS - 1)]


static func theme_of(d: Dictionary) -> String:
	var i := int(d.get("i", 1))
	if i == 0:
		return THEMES[Seeded.derive(int(d.get("s", 1)), "theme") % THEMES.size()]
	return THEMES[clampi(i - 1, 0, ISLANDS - 1)]


## TODAY'S ISLAND's description (the same on every machine all day).
static func daily_desc(m: String, date: String = "") -> Dictionary:
	return {"i": 0, "s": Seeded.daily_seed(GAME_ID, date), "m": mode_of(m)}


# --- Jumps ------------------------------------------------------------------------------------------------------

## How far (horizontally) a running jump carries the robot's middle when it lands dh higher (INF-safe: -1 = can't).
## v: how fast it goes up (a jump, or a spring's throw).
static func reach(dh: float, v: float = JUMP_V) -> float:
	var disc := v * v - 2.0 * GRAVITY * dh
	if disc < 0.0:
		return -1.0
	return RUN * (v + sqrt(disc)) / GRAVITY


static func boss_of(island: int) -> String:
	return String(BOSSES.get(island, ""))


## Can a robot hop a gap of `gap` (edge to edge) landing dh higher? (the margin REACH_K: little thumbs)
static func hop_ok(gap: float, dh: float) -> bool:
	return dh <= MAX_RISE and gap <= reach(dh) * REACH_K


## A platform's top-centre at level time t (movers slide, lifts rise; statics stay).
static func plat_at(p: Dictionary, t: float) -> Vector3:
	var c: Vector3 = p.c
	if not p.has("b"):
		return c
	var k := 0.5 - 0.5 * cos(TAU * (t / float(p.per) + float(p.get("ph", 0.0))))
	return c.lerp(p.b, k)


# --- Generation --------------------------------------------------------------------------------------------------

static func generate(d: Dictionary) -> Dictionary:
	var seed_value := int(d.get("s", 1))
	var island := int(d.get("i", 1))
	var m := mode_of(String(d.get("m", "brave")))
	var best: Dictionary = {}
	for attempt in 12:
		var lv := _try(Seeded.rng(seed_value, "island %d try %d" % [island, attempt]), island, m)
		lv["desc"] = {"i": island, "s": seed_value, "m": m}
		lv["attempt"] = attempt
		if check(lv).is_empty():
			return lv
		if best.is_empty():
			best = lv
	return best


static func _try(r: RandomNumberGenerator, island: int, m: String) -> Dictionary:
	var md: Dictionary = MODES[m]
	var w := float(md.w)
	var lv := {"island": island, "mode": m, "theme": "", "plats": [], "chain": [], "bolts": [], "grumbles": [],
		"zaps": [], "cps": [], "route": [], "secret": {}, "gear": Vector3.INF, "goal": Vector3.INF, "boss": {},
		"start": Vector3.ZERO, "low_y": 0.0, "w": w, "springs": [], "fans": [], "belts": [], "boxes": []}
	var pool: Array = (POOLS[island] as Array).duplicate()
	pool.erase("steps")
	pool = Seeded.shuffled(r, pool)
	if pool[0] == "secret":
		pool.remove_at(0)
		pool.insert(1, "secret")
	if island == 0 or island > 3:  # (the long-gadget islands: the secret always fits, early on)
		pool.erase("secret")
		pool.insert(1, "secret")
	if SIGNATURE.has(island):  # (... and the island's own gadget comes first, so it always fits)
		pool.erase(SIGNATURE[island])
		pool.insert(0, SIGNATURE[island])
	var sections: Array = ["steps"] + pool
	var boss := boss_of(island) != ""
	var end_len := 13.0 if boss else 6.0
	# A first floor to stand on.
	var x := X_MIN + 1.0
	var y := 1.0
	var first := _plat(lv, x, 6.0, y, w, "solid")
	lv.start = Vector3(x + 1.6, y, 0.0)
	_cp(lv, first, x + 1.6)
	_route(lv, first, Vector3(x + 3.0, y, 0.0), "walk")
	_bolt_row(lv, x + 2.5, x + 5.5, y, 0.0, 3)
	x += 6.0
	var last := first
	var boxed := false
	for s in sections:
		var budget := X_MAX - end_len - 3.0 - x
		if budget < float(SIZE.get(String(s), 9.0)):
			if String(s) != "secret":
				continue
			if budget < 7.0:
				break
		var count := (lv.plats as Array).size()
		match String(s):
			"steps":
				var res := _steps(lv, r, x, y, last, md, r.randi_range(2, 3))
				x = res[0]; y = res[1]; last = res[2]
				if not boxed:  # a BOT BOX on the first steps' last floor (a little bot to rescue)
					boxed = true
					_box(lv, r, last)
			"spring":
				var res := _spring(lv, r, x, y, last, md)
				x = res[0]; y = res[1]; last = res[2]
			"fan":
				var res := _fan(lv, r, x, y, last, md)
				x = res[0]; y = res[1]; last = res[2]
			"belt":
				var res := _belt(lv, r, x, y, last, md)
				x = res[0]; y = res[1]; last = res[2]
			"mover":
				var res := _mover(lv, r, x, y, last, md)
				x = res[0]; y = res[1]; last = res[2]
			"lift":
				var res := _lift(lv, r, x, y, last, md)
				x = res[0]; y = res[1]; last = res[2]
			"patrol":
				var res := _patrol(lv, r, x, y, last, md)
				x = res[0]; y = res[1]; last = res[2]
			"zap":
				var res := _zap(lv, r, x, y, last, md)
				x = res[0]; y = res[1]; last = res[2]
			"secret":
				var res := _secret(lv, r, x, y, last, md)
				x = res[0]; y = res[1]; last = res[2]
		# A checkpoint flag on the section's first steady floor when the last one is far behind.
		for i in range(count, (lv.plats as Array).size()):
			var p: Dictionary = (lv.plats as Array)[i]
			var c: Vector3 = p.c
			var near_x := c.x - float((p.s as Vector2).x) * 0.5 + 0.9
			if not p.has("b") and c.z == 0.0 and near_x - float(((lv.cps as Array)[-1][1] as Vector3).x) > 12.0:
				_cp(lv, i, near_x)
				break
	# The end: the spark's floor, or Cranky Crab's round arena.
	var ey := clampf(y + float(Seeded.pick(r, [0.0, 0.5])), Y_MIN, Y_MAX - 1.0)
	var gap := _fit_gap(r.randf_range(1.0, minf(1.8, float(md.gap))), ey - y)
	var end := _plat(lv, x + gap, end_len, ey, (end_len if boss else w + 1.0), "arena" if boss else "solid")
	_hop(lv, last, end)
	var ep: Dictionary = (lv.plats as Array)[end]
	var ec: Vector3 = ep.c
	_cp(lv, end, x + gap + 1.0)
	if boss:
		var kind := boss_of(island)
		lv.boss = {"c": ec, "r": end_len * 0.5 - 1.2, "hp": int(md.boss_hp) + (1 if kind == "king" else 0), "kind": kind}
		_route(lv, end, ec, "boss")
	lv.goal = ec + Vector3(end_len * 0.25 if not boss else 0.0, 0.0, 0.0)
	# A second BOT BOX by the goal (on a boss arena: the boss kept a little bot; it opens once the boss is beaten).
	var bz := -((end_len if boss else w + 1.0) * 0.5 - 0.6) if not boss else -2.6
	var bx := (ec.x - end_len * 0.25) if not boss else ec.x + 2.2
	(lv.boxes as Array).append({"pos": Vector3(bx, ey, bz), "p": end})
	_route(lv, end, Vector3(bx, ey, bz + 0.9), "box")
	_route(lv, end, lv.goal, "goal")
	_bolt_row(lv, x + gap + 1.0, x + gap + end_len * 0.4, ey, 0.0, 2)
	var low := INF
	for p in lv.plats:
		low = minf(low, float((p.c as Vector3).y))
		if p.has("b"):
			low = minf(low, float((p.b as Vector3).y))
	lv.low_y = low
	lv.theme = ""
	return lv


## A platform from x0, len long, top at y (z centred at 0 unless given). Returns its index.
static func _plat(lv: Dictionary, x0: float, length: float, y: float, width: float, kind: String, z: float = 0.0) -> int:
	var plats: Array = lv.plats
	plats.append({"c": Vector3(x0 + length * 0.5, y, z), "s": Vector2(length, width), "k": kind})
	return plats.size() - 1


static func _cp(lv: Dictionary, plat: int, x: float) -> void:
	var p: Dictionary = (lv.plats as Array)[plat]
	(lv.cps as Array).append([plat, Vector3(x, float((p.c as Vector3).y), float((p.c as Vector3).z))])


static func _route(lv: Dictionary, plat: int, to: Vector3, act: String) -> void:
	(lv.route as Array).append({"p": plat, "to": to, "act": act})


## The main path goes from platform a to b (check() proves the hop).
static func _hop(lv: Dictionary, a: int, b: int) -> void:
	(lv.chain as Array).append([a, b])


static func _bolt_row(lv: Dictionary, x0: float, x1: float, y: float, z: float, n: int) -> void:
	for k in n:
		var t := 0.5 if n == 1 else float(k) / float(n - 1)
		(lv.bolts as Array).append(Vector3(lerpf(x0, x1, t), y + 0.6, z))


## A hop's gap shrunk until a robot can surely make it (rising dh).
static func _fit_gap(gap: float, dh: float) -> float:
	while gap > 0.6 and not hop_ok(gap, dh):
		gap -= 0.1
	return gap


static func _next_y(r: RandomNumberGenerator, y: float, choices: Array) -> float:
	return clampf(y + float(Seeded.pick(r, choices)), Y_MIN, Y_MAX - 1.5)


static func _steps(lv: Dictionary, r: RandomNumberGenerator, x: float, y: float, last: int, md: Dictionary, n: int) -> Array:
	for k in n:
		var ny := _next_y(r, y, [-1.0, -0.5, 0.0, 0.5, 1.0])
		var gap := _fit_gap(r.randf_range(0.9, float(md.gap)), ny - y)
		var length := r.randf_range(3.0, 5.0)
		var w := float(md.w) * r.randf_range(0.85, 1.0)
		var p := _plat(lv, x + gap, length, ny, w, "solid")
		_hop(lv, last, p)
		_route(lv, p, Vector3(x + gap + length * 0.5, ny, 0.0), "jump")
		# Bolts arc over the gap (the jump's way) and sit on the floor.
		var mid := Vector3(x + gap * 0.5, maxf(y, ny) + 1.4, 0.0)
		(lv.bolts as Array).append(mid)
		_bolt_row(lv, x + gap + 0.8, x + gap + length - 0.8, ny, 0.0, 2)
		x += gap + length
		y = ny
		last = p
	return [x, y, last]


static func _mover(lv: Dictionary, r: RandomNumberGenerator, x: float, y: float, last: int, md: Dictionary) -> Array:
	var span := r.randf_range(6.0, 8.0)  # too wide to hop
	var ml := 2.8 if float(md.w) > 3.2 else 2.4
	var near := 0.7
	var ax := x + near + ml * 0.5
	var bx := x + span - near - ml * 0.5
	var p := _plat(lv, x + near, ml, y, ml, "mover")
	var pl: Dictionary = (lv.plats as Array)[p]
	pl["b"] = Vector3(bx, y, 0.0)
	pl["c"] = Vector3(ax, y, 0.0)
	pl["per"] = 2.0 * (bx - ax) / (2.2 * float(md.speed)) + 1.0
	pl["ph"] = r.randf()
	_hop(lv, last, p)
	_route(lv, p, Vector3(ax, y, 0.0), "board")
	var length := r.randf_range(4.0, 5.5)
	var ny := y
	var q := _plat(lv, x + span, length, ny, float(md.w), "solid")
	_hop(lv, p, q)
	_route(lv, q, Vector3(x + span + length * 0.5, ny, 0.0), "alight")
	for k in 3:  # bolts ride along over the mover's way
		(lv.bolts as Array).append(Vector3(lerpf(ax, bx, (k + 1) / 4.0), y + 1.3, 0.0))
	_bolt_row(lv, x + span + 0.8, x + span + length - 0.8, ny, 0.0, 2)
	return [x + span + length, ny, q]


static func _lift(lv: Dictionary, r: RandomNumberGenerator, x: float, y: float, last: int, md: Dictionary) -> Array:
	var rise := r.randf_range(2.4, 3.2)
	var lowy := float((((lv.plats as Array)[last] as Dictionary).c as Vector3).y)
	var top := minf(lowy + rise, Y_MAX - 0.5)
	var gap := 0.6
	var ls := 2.6
	var p := _plat(lv, x + gap, ls, lowy, ls, "lift")
	var pl: Dictionary = (lv.plats as Array)[p]
	pl["b"] = Vector3(x + gap + ls * 0.5, top, 0.0)
	pl["per"] = LIFT_PERIOD / float(md.speed) * 1.0
	pl["ph"] = r.randf()
	_hop(lv, last, p)
	_route(lv, p, pl.c, "ride_up")
	var length := r.randf_range(4.0, 5.5)
	var q := _plat(lv, x + gap + ls + 0.6, length, top, float(md.w), "solid")
	_hop(lv, p, q)
	_route(lv, q, Vector3(x + gap + ls + 0.6 + length * 0.5, top, 0.0), "step_off")
	_bolt_row(lv, x + gap + ls * 0.5, x + gap + ls * 0.5, top, 0.0, 1)  # (over the lift at the top)
	_bolt_row(lv, x + gap + ls + 1.4, x + gap + ls + length - 0.4, top, 0.0, 3)
	return [x + gap + ls + 0.6 + length, top, q]


static func _patrol(lv: Dictionary, r: RandomNumberGenerator, x: float, y: float, last: int, md: Dictionary) -> Array:
	var ny := _next_y(r, y, [-0.5, 0.0, 0.5])
	var gap := _fit_gap(r.randf_range(0.9, float(md.gap)), ny - y)
	var length := r.randf_range(9.0, 11.0)
	var p := _plat(lv, x + gap, length, ny, float(md.w), "solid")
	_hop(lv, last, p)
	var n := int(md.grumbles)
	for k in n:
		var a := x + gap + 1.5 + (length - 3.0) * float(k) / float(n)
		var b := x + gap + 1.5 + (length - 3.0) * float(k + 1) / float(n)
		(lv.grumbles as Array).append({"p": p, "x0": a, "x1": b, "y": ny, "speed": 1.2 * float(md.speed), "dash": float(md.dash)})
	_route(lv, p, Vector3(x + gap + length * 0.5, ny, 0.0), "fight")
	_route(lv, p, Vector3(x + gap + length - 0.8, ny, 0.0), "walk")
	_bolt_row(lv, x + gap + 1.0, x + gap + length - 1.0, ny, 0.0, 5)
	return [x + gap + length, ny, p]


static func _zap(lv: Dictionary, r: RandomNumberGenerator, x: float, y: float, last: int, md: Dictionary) -> Array:
	var ny := _next_y(r, y, [-0.5, 0.0, 0.5])
	var gap := _fit_gap(r.randf_range(0.9, float(md.gap)), ny - y)
	var length := r.randf_range(9.0, 12.0)
	var w := float(md.w)
	var p := _plat(lv, x + gap, length, ny, w, "solid")
	_hop(lv, last, p)
	var n := int(md.zaps)
	var side := 1.0 if r.randf() < 0.5 else -1.0
	for k in n:
		var zr := minf(1.15, (w - ZAP_LANE) / 1.6 - 0.02)
		var zx := x + gap + 2.4 + (length - 4.8) * (float(k) + 0.5) / float(n)
		var zz := side * (w * 0.5 - zr * 0.6)
		(lv.zaps as Array).append({"pos": Vector3(zx, ny, zz), "r": zr, "ph": r.randf(), "p": p})
		side = -side
	_route(lv, p, Vector3(x + gap + length - 0.8, ny, 0.0), "zaps")
	_bolt_row(lv, x + gap + 1.0, x + gap + length - 1.0, ny, 0.0, 4)
	return [x + gap + length, ny, p]


static func _secret(lv: Dictionary, r: RandomNumberGenerator, x: float, y: float, last: int, md: Dictionary) -> Array:
	var ny := _next_y(r, y, [-0.5, 0.0, 0.5])
	var gap := _fit_gap(r.randf_range(0.9, minf(1.8, float(md.gap))), ny - y)
	var length := 6.5
	var w := float(md.w)
	var p := _plat(lv, x + gap, length, ny, w, "solid")
	_hop(lv, last, p)
	# The side island behind (-Z), a short hop across.
	var zgap := r.randf_range(1.0, 1.4)
	var sw := ROOM.z + 2.2  # deep enough for the room and a ledge in front of its wall
	var sz := -(w * 0.5 + zgap + sw * 0.5)
	var sx := x + gap + length * 0.5
	var sl := ROOM.x + 1.6
	var s := _plat(lv, sx - sl * 0.5, sl, ny, sw, "side", sz)
	var room_c := Vector3(sx, ny, sz - sw * 0.5 + 0.2 + ROOM.z * 0.5)  # at the island's far side
	var wall_z := room_c.z + ROOM.z * 0.5  # the cracked wall faces the path (+Z)
	lv.secret = {"side": s, "room": room_c, "wall": Vector3(sx, ny, wall_z), "from": p}
	lv.gear = room_c + Vector3(0.0, 0.7, -0.2)
	_route(lv, p, Vector3(sx, ny, -w * 0.5 + 0.6), "walk")
	_route(lv, s, Vector3(sx, ny, wall_z + 1.0), "jump_side")
	_route(lv, s, Vector3(sx, ny, wall_z + 0.9), "punch")
	_route(lv, s, lv.gear - Vector3(0.0, 0.7, 0.0), "gear")
	_route(lv, s, Vector3(sx, ny, wall_z + 1.0), "walk")
	_route(lv, p, Vector3(sx, ny, -w * 0.5 + 0.7), "jump_back")
	_route(lv, p, Vector3(x + gap + length - 0.8, ny, 0.0), "walk")
	(lv.bolts as Array).append(Vector3(sx, ny + 1.3, -w * 0.5 - zgap * 0.5))  # (a bolt shows the way across)
	_bolt_row(lv, x + gap + 0.8, x + gap + length - 0.8, ny, 0.0, 3)
	return [x + gap + length, ny, p]


## A BOT BOX on floor p's back edge (out of the way: never blocks the path), a little bot inside. The route walks up
## to it (punch it, pound it, or just bump into it) and comes back to the middle.
static func _box(lv: Dictionary, r: RandomNumberGenerator, p: int) -> void:
	var pl: Dictionary = (lv.plats as Array)[p]
	var c: Vector3 = pl.c
	var s: Vector2 = pl.s
	var bx := c.x + r.randf_range(-0.25, 0.25) * maxf(0.0, s.x - 2.0)
	var bz := c.z - s.y * 0.5 + 0.55
	(lv.boxes as Array).append({"pos": Vector3(bx, c.y, bz), "p": p})
	_route(lv, p, Vector3(bx, c.y, bz + 0.9), "box")
	_route(lv, p, Vector3(c.x + s.x * 0.5 - 0.8, c.y, 0.0), "walk")


## SPRING: a floor with a SPRING PAD near its end, and a high ledge past it that only a spring's throw reaches.
static func _spring(lv: Dictionary, r: RandomNumberGenerator, x: float, y: float, last: int, md: Dictionary) -> Array:
	var ny := _next_y(r, y, [-1.0, -0.5, 0.0])
	var gap := _fit_gap(r.randf_range(0.9, float(md.gap)), ny - y)
	var length := r.randf_range(4.0, 5.0)
	var w := float(md.w)
	var p := _plat(lv, x + gap, length, ny, w, "solid")
	_hop(lv, last, p)
	var sx := x + gap + length - 1.1
	(lv.springs as Array).append({"pos": Vector3(sx, ny, 0.0), "p": p})
	var top := minf(ny + r.randf_range(2.4, SPRING_RISE), Y_MAX - 0.5)
	var g2 := r.randf_range(0.5, 1.1)
	var ql := r.randf_range(4.0, 5.0)
	var q := _plat(lv, x + gap + length + g2, ql, top, w, "solid")
	(lv.chain as Array).append([p, q, "spring"])
	_route(lv, p, Vector3(x + gap + 1.0, ny, 0.0), "walk")
	_route(lv, p, Vector3(sx, ny, 0.0), "spring")
	_route(lv, q, Vector3(x + gap + length + g2 + ql * 0.5, top, 0.0), "jump")
	(lv.bolts as Array).append(Vector3(sx, ny + 2.2, 0.0))  # (bolts up the spring's way)
	_bolt_row(lv, x + gap + length + g2 + 0.8, x + gap + length + g2 + ql - 0.8, top, 0.0, 3)
	_bolt_row(lv, x + gap + 0.8, sx - 1.0, ny, 0.0, 2)
	return [x + gap + length + g2 + ql, top, q]


## FAN: a gap far too wide to hop, a WIND FAN down in it: walk off the edge and its updraft floats you across.
static func _fan(lv: Dictionary, r: RandomNumberGenerator, x: float, y: float, last: int, md: Dictionary) -> Array:
	var span := r.randf_range(5.5, 7.0)
	var ny := _next_y(r, y, [-0.5, 0.0, 0.5])
	var length := r.randf_range(4.0, 5.5)
	var w := float(md.w)
	var q := _plat(lv, x + span, length, ny, w, "solid")
	var top := maxf(y, ny) + FAN_TOP
	(lv.fans as Array).append({"x0": x + 0.15, "x1": x + span - 0.15, "y": minf(y, ny) - 2.2, "top": top, "w": w})
	(lv.chain as Array).append([last, q, "fan"])
	_route(lv, q, Vector3(x + span + length * 0.5, ny, 0.0), "fan")
	for k in 3:  # bolts float at the top of the updraft
		(lv.bolts as Array).append(Vector3(lerpf(x + 1.4, x + span - 1.4, k / 2.0), top + 0.1, 0.0))
	_bolt_row(lv, x + span + 0.8, x + span + length - 0.8, ny, 0.0, 2)
	return [x + span + length, ny, q]


## BELT: a long CONVEYOR BELT floor carrying robots along (some forwards, some backwards: run against it).
static func _belt(lv: Dictionary, r: RandomNumberGenerator, x: float, y: float, last: int, md: Dictionary) -> Array:
	var ny := _next_y(r, y, [-0.5, 0.0, 0.5])
	var gap := _fit_gap(r.randf_range(0.9, float(md.gap)), ny - y)
	var length := r.randf_range(7.0, 9.0)
	var p := _plat(lv, x + gap, length, ny, float(md.w), "belt")
	_hop(lv, last, p)
	var dir := 1.0 if r.randf() < 0.5 else -1.0
	(lv.belts as Array).append({"p": p, "dir": dir})
	_route(lv, p, Vector3(x + gap + length - 0.8, ny, 0.0), "walk")
	_bolt_row(lv, x + gap + 1.0, x + gap + length - 1.0, ny, 0.0, 4)
	return [x + gap + length, ny, p]


## Which spring pad robot feet at p bounce on (-1 none).
static func spring_at(lv: Dictionary, p: Vector3) -> int:
	var sp: Array = lv.get("springs", [])
	for i in sp.size():
		var s: Vector3 = (sp[i] as Dictionary).pos
		if Vector2(p.x - s.x, p.z - s.z).length() < SPRING_R and absf(p.y - s.y) < 0.35:
			return i
	return -1


## The updraft at point p: how fast a fan lifts a robot there (0 = none).
static func fan_up(lv: Dictionary, p: Vector3) -> float:
	for f in lv.get("fans", []):
		if p.x > float(f.x0) and p.x < float(f.x1) and absf(p.z) < float(f.w) * 0.5 and p.y > float(f.y) and p.y < float(f.top):
			return FAN_UP * clampf((float(f.top) - p.y) / 0.6, 0.0, 1.0)
	return 0.0


## The belt push (x speed) under robot feet at p (0 = not on a belt).
static func belt_push(lv: Dictionary, p: Vector3) -> float:
	for bt in lv.get("belts", []):
		var pl: Dictionary = (lv.plats as Array)[int(bt.p)]
		if _on_top(pl, p):
			return BELT * float(bt.dir)
	return 0.0


static func _on_top(pl: Dictionary, p: Vector3) -> bool:
	var c: Vector3 = pl.c
	var s: Vector2 = pl.s
	return absf(p.x - c.x) <= s.x * 0.5 + ROBOT_R and absf(p.z - c.z) <= s.y * 0.5 + ROBOT_R and p.y > c.y - 0.1 and p.y < c.y + 0.3


# --- Questions about an island (game, bots, check) ---------------------------------------------------------------

## The platform under point p at level time t (its top within `up` above / `down` below p.y), -1 none.
static func support(lv: Dictionary, p: Vector3, t: float, up: float = 0.35, down: float = 0.6, margin: float = 0.0) -> int:
	var plats: Array = lv.plats
	var best := -1
	var by := -INF
	for i in plats.size():
		var pl: Dictionary = plats[i]
		var c := plat_at(pl, t)
		var s: Vector2 = pl.s
		if absf(p.x - c.x) > s.x * 0.5 + margin or absf(p.z - c.z) > s.y * 0.5 + margin:
			continue
		if pl.k == "arena" and Vector2(p.x - c.x, p.z - c.z).length() > s.x * 0.5 + margin:
			continue
		if c.y <= p.y + up and c.y >= p.y - down and c.y > by:
			by = c.y
			best = i
	return best


## Zap pad z's state at level time t: 0 off, 1 telling (flashing on its warn ring), 2 buzzing.
static func zap_state(z: Dictionary, t: float) -> int:
	var c := fposmod(t / ZAP_PERIOD + float(z.ph), 1.0)
	if c < ZAP_TELL:
		return 1
	if c < ZAP_TELL + ZAP_HOT:
		return 2
	return 0


## Which checkpoint a robot at p has reached (the furthest flag it walked past on that flag's platform).
static func checkpoint_for(lv: Dictionary, p: Vector3, current: int) -> int:
	var cps: Array = lv.cps
	var best := current
	for k in range(current + 1, cps.size()):
		var cp: Vector3 = cps[k][1]
		if p.x >= cp.x - 0.4 and absf(p.y - cp.y) < 1.2 and absf(p.z - cp.z) < 3.0:
			best = k
	return best


# --- The validator -----------------------------------------------------------------------------------------------

## Problems with an island ([] = it can be finished): the main path's hops from the robots' real jump numbers (movers at
## their nearest, lifts at the bottom to get on and at the top to get off, the secret island across), floors inside
## the giant's walk and above the clouds, nothing overlapping or hanging over a floor, bolts within a jump, the gear
## in its room, zap floors with a safe lane, grumbles on their floors, checkpoints close enough, the goal at the end.
static func check(lv: Dictionary) -> Array:
	var out: Array = []
	var plats: Array = lv.get("plats", [])
	if plats.size() < 4:
		return ["only %d platforms" % plats.size()]
	for i in plats.size():
		var p: Dictionary = plats[i]
		for c in [p.c, p.get("b", p.c)]:
			var v: Vector3 = c
			var s: Vector2 = p.s
			if v.x - s.x * 0.5 < X_MIN - 0.01 or v.x + s.x * 0.5 > X_MAX + 0.01:
				out.append("platform %d at x %.1f leaves the giant's walk" % [i, v.x])
			if v.y < Y_MIN - 0.01 or v.y > Y_MAX + 0.01:
				out.append("platform %d at y %.1f" % [i, v.y])
	# The main path (plain hops, spring hops, fan floats).
	for hop in lv.get("chain", []):
		var how := String(hop[2]) if (hop as Array).size() > 2 else ""
		var why := ""
		if how == "spring":
			why = _spring_problem(lv, int(hop[0]), int(hop[1]))
		elif how == "fan":
			why = _fan_problem(lv, plats[int(hop[0])], plats[int(hop[1])])
		else:
			why = _hop_problem(plats[int(hop[0])], plats[int(hop[1])])
		if why != "":
			out.append("%s hop %d -> %d: %s" % [how, int(hop[0]), int(hop[1]), why])
	# Gadgets: belts walkable against, fans always on, springs on still floors.
	if BELT > RUN * 0.5:
		out.append("belts faster than a robot can walk against")
	for bt in lv.get("belts", []):
		if String((plats[int(bt.p)] as Dictionary).k) != "belt":
			out.append("a belt that isn't a belt floor")
	for sp in lv.get("springs", []):
		var pl: Dictionary = plats[int(sp.p)]
		if pl.has("b") or not _on(pl, sp.pos, 0.0) or absf(float((sp.pos as Vector3).x) - float((pl.c as Vector3).x)) > float((pl.s as Vector2).x) * 0.5 - 0.5:
			out.append("spring at x %.1f not well on a still floor" % float((sp.pos as Vector3).x))
	# Bot boxes: on a floor of the main path (at its back edge; they never block: no collision), never on a zap pad.
	var on_path := {}
	for hop in lv.get("chain", []):
		on_path[int(hop[0])] = true
		on_path[int(hop[1])] = true
	for bx in lv.get("boxes", []):
		var pl: Dictionary = plats[int(bx.p)]
		var bp: Vector3 = bx.pos
		if not on_path.has(int(bx.p)) or pl.has("b") or not _on(pl, bp, 0.0) or not _on(pl, bp + Vector3(0, 0, 0.9), 0.0):
			out.append("bot box at x %.1f not on a still floor of the path" % bp.x)
		for z in lv.get("zaps", []):
			if Vector2(bp.x - (z.pos as Vector3).x, bp.z - (z.pos as Vector3).z).length() < float(z.r) + 1.2:
				out.append("bot box at x %.1f by a zap pad" % bp.x)
	if (lv.get("boxes", []) as Array).size() < 2:
		out.append("only %d bot boxes" % (lv.get("boxes", []) as Array).size())
	var chain: Array = lv.get("chain", [])
	if chain.is_empty() or int(chain[0][0]) != 0:
		out.append("the path doesn't start on the first floor")
	for k in range(1, chain.size()):
		if int(chain[k][0]) != int(chain[k - 1][1]):
			out.append("the path breaks at hop %d" % k)
	var end_i := int(chain[-1][1]) if not chain.is_empty() else -1
	# Overlaps and head room (swept movers / lifts included).
	for i in plats.size():
		for j in range(i + 1, plats.size()):
			var a := _sweep(plats[i])
			var b := _sweep(plats[j])
			if a.grow(0.15).intersects(b):
				out.append("platforms %d and %d overlap" % [i, j])
				continue
			var ov := Rect2(a.position.x, a.position.z, a.size.x, a.size.z).intersects(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))
			if ov:
				var gap_y := absf((a.position.y + a.size.y) - (b.position.y + b.size.y))
				if gap_y < HEAD_ROOM + THICK:
					out.append("platforms %d and %d too close above each other (%.1f)" % [i, j, gap_y])
	# The secret.
	var sec: Dictionary = lv.get("secret", {})
	if sec.is_empty():
		out.append("no secret")
	else:
		var why := _hop_problem(plats[int(sec.from)], plats[int(sec.side)], true)
		if why != "":
			out.append("secret hop: %s" % why)
		var side: Dictionary = plats[int(sec.side)]
		var room: Vector3 = sec.room
		if not _on(side, room, 0.0) or not _on(side, Vector3(room.x, room.y, float((sec.wall as Vector3).z) + 0.9), 0.0):
			out.append("the secret room / its doorstep isn't on the side island")
		var g: Vector3 = lv.get("gear", Vector3.INF)
		if g == Vector3.INF or absf(g.x - room.x) > ROOM.x * 0.5 - 0.3 or absf(g.z - room.z) > ROOM.z * 0.5 - 0.3 or g.y - room.y > 1.2:
			out.append("the gear isn't inside the secret room")
	# Bolts within a jump of a floor (or over a hop on the path).
	var bolts: Array = lv.get("bolts", [])
	if bolts.size() < 10:
		out.append("only %d bolts" % bolts.size())
	for k in bolts.size():
		if not _bolt_ok(lv, bolts[k]):
			out.append("bolt %d at %s out of reach" % [k, str(bolts[k])])
	# Zaps: on their floor, a lane, away from the floor's ends.
	for z in lv.get("zaps", []):
		var pl: Dictionary = plats[int(z.p)]
		var c: Vector3 = pl.c
		var s: Vector2 = pl.s
		var zp: Vector3 = z.pos
		var zr := float(z.r)
		var lane := maxf(s.y * 0.5 - (zp.z + zr), (zp.z - zr) + s.y * 0.5)
		if lane < ZAP_LANE - 0.01:
			out.append("zap at x %.1f leaves a lane of %.2f" % [zp.x, lane])
		if absf(zp.x - c.x) > s.x * 0.5 - 1.9:
			out.append("zap at x %.1f too near its floor's end" % zp.x)
		if ZAP_TELL * ZAP_PERIOD < 1.0:
			out.append("zap tell shorter than 1 s")
	for gr in lv.get("grumbles", []):
		var pl: Dictionary = plats[int(gr.p)]
		var c: Vector3 = pl.c
		var s: Vector2 = pl.s
		if float(gr.x0) < c.x - s.x * 0.5 + 0.9 or float(gr.x1) > c.x + s.x * 0.5 - 0.9 or float(gr.x1) <= float(gr.x0):
			out.append("grumble patrol off its floor")
	# Checkpoints.
	var cps: Array = lv.get("cps", [])
	if cps.is_empty():
		out.append("no checkpoints")
	var last_x := X_MIN
	for cp in cps:
		var v: Vector3 = cp[1]
		if not _on(plats[int(cp[0])], v, 0.0):
			out.append("checkpoint at x %.1f not on its floor" % v.x)
		if v.x - last_x > MAX_CP_GAP:
			out.append("checkpoints %.1f apart" % (v.x - last_x))
		last_x = v.x
	var goal: Vector3 = lv.get("goal", Vector3.INF)
	if goal == Vector3.INF or end_i < 0 or not _on(plats[end_i], goal, 0.0):
		out.append("the goal isn't on the last floor")
	elif goal.x - last_x > MAX_CP_GAP:
		out.append("the goal is %.1f past the last checkpoint" % (goal.x - last_x))
	var sig := String(SIGNATURE.get(int(lv.get("island", 1)), ""))
	if sig != "" and (lv.get(sig + "s", []) as Array).is_empty():
		out.append("no %s on its own island" % sig)
	var bk := boss_of(int(lv.get("island", 1)))
	if bk != "":
		var bd: Dictionary = lv.get("boss", {})
		if bd.is_empty() or int(bd.get("hp", 0)) <= 0 or end_i < 0 or String((plats[end_i] as Dictionary).k) != "arena" or String(bd.get("kind", "")) != bk:
			out.append("%s has no %s arena" % [island_name(lv.get("desc", {"i": lv.island})), bk])
	elif not (lv.get("boss", {}) as Dictionary).is_empty():
		out.append("a boss on an island without one")
	var start: Vector3 = lv.get("start", Vector3.INF)
	if not _on(plats[0], start, 0.0):
		out.append("the start isn't on the first floor")
	var route: Array = lv.get("route", [])
	if route.is_empty() or String((route[-1] as Dictionary).act) != "goal":
		out.append("the route doesn't end at the goal")
	return out


## Why a robot can't hop from platform a to platform b ("" = it can). Movers at their nearest, lifts: on at the
## bottom, off at the top. across: the secret hop (along Z).
static func _hop_problem(a: Dictionary, b: Dictionary, across: bool = false) -> String:
	var best := "never close enough"
	for ta in _poses(a, b, true):
		for tb in _poses(b, a, false):
			var pa: Vector3 = ta
			var pb: Vector3 = tb
			var sa: Vector2 = a.s
			var sb: Vector2 = b.s
			var gap: float
			if across:
				gap = absf(pa.z - pb.z) - sa.y * 0.5 - sb.y * 0.5
				if absf(pa.x - pb.x) > (sa.x + sb.x) * 0.5 - 1.0:
					continue
			else:
				gap = absf(pa.x - pb.x) - sa.x * 0.5 - sb.x * 0.5
				if absf(pa.z - pb.z) > (sa.y + sb.y) * 0.5 - 1.0:
					continue
			var dh := pb.y - pa.y
			if gap < -0.01:
				return ""  # touching / overlapping in x (a lift beside its floors) is a step only if level
			if hop_ok(gap, dh):
				return ""
			best = "gap %.2f, rise %.2f (reach %.2f)" % [gap, dh, reach(dh) * REACH_K]
	return best


## Why a spring on floor a can't throw a robot onto ledge b ("" = it can): the ledge within the throw's reach from the
## pad (REACH_K margin), never hanging over the pad, and no higher than SPRING_RISE.
static func _spring_problem(lv: Dictionary, ai: int, bi: int) -> String:
	var plats: Array = lv.plats
	var a: Dictionary = plats[ai]
	var b: Dictionary = plats[bi]
	var pad := Vector3.INF
	for sp in lv.get("springs", []):
		if int(sp.p) == ai:
			pad = sp.pos
	if pad == Vector3.INF:
		return "no spring on its floor"
	if b.has("b") or a.has("b"):
		return "a spring hop needs still floors"
	var dh := float((b.c as Vector3).y) - pad.y
	var near := float((b.c as Vector3).x) - float((b.s as Vector2).x) * 0.5
	var d := near - pad.x
	if dh > SPRING_RISE + 0.01:
		return "ledge %.2f up (most %.2f)" % [dh, SPRING_RISE]
	if d < SPRING_R + 0.3:
		return "the ledge hangs over the spring"
	if d > reach(dh, SPRING_V) * REACH_K:
		return "ledge %.2f away, a spring throws %.2f" % [d, reach(dh, SPRING_V) * REACH_K]
	if absf(float((b.c as Vector3).z) - pad.z) > float((b.s as Vector2).y) * 0.5 - 0.5:
		return "the ledge isn't in line with the spring"
	return ""


## Why a fan can't float a robot from floor a to floor b ("" = it can): its updraft fills the whole gap, rises over
## both floors, and stays out of the way of every floor.
static func _fan_problem(lv: Dictionary, a: Dictionary, b: Dictionary) -> String:
	var a_end := float((a.c as Vector3).x) + float((a.s as Vector2).x) * 0.5
	var b_near := float((b.c as Vector3).x) - float((b.s as Vector2).x) * 0.5
	for f in lv.get("fans", []):
		if float(f.x0) > a_end + 0.3 or float(f.x1) < b_near - 0.3 or float(f.x0) < a_end - 0.5:
			continue
		var hi := maxf(float((a.c as Vector3).y), float((b.c as Vector3).y))
		if float(f.top) < hi + FAN_TOP - 0.01:
			return "the updraft only reaches %.1f" % float(f.top)
		if float(f.w) < minf(float((a.s as Vector2).y), float((b.s as Vector2).y)) - 0.01:
			return "the updraft is narrower than the floors"
		if FAN_UP < 2.0:
			return "the updraft is too weak"
		return ""
	return "no fan fills the gap (%.1f to %.1f)" % [a_end, b_near]


## Where a moving platform is worth checking from: statics where they are; movers at both ends; a lift at its
## bottom when you get on (`leaving` false) and its top when you get off (`leaving` true) - or both when unsure.
static func _poses(p: Dictionary, _other: Dictionary, leaving: bool) -> Array:
	if not p.has("b"):
		return [p.c]
	if String(p.k) == "lift":
		return [p.b] if leaving else [p.c]
	return [p.c, p.b]


static func _sweep(p: Dictionary) -> AABB:
	var s: Vector2 = p.s
	var a: Vector3 = p.c
	var b: Vector3 = p.get("b", p.c)
	var lo := Vector3(minf(a.x, b.x) - s.x * 0.5, minf(a.y, b.y) - THICK, minf(a.z, b.z) - s.y * 0.5)
	var hi := Vector3(maxf(a.x, b.x) + s.x * 0.5, maxf(a.y, b.y), maxf(a.z, b.z) + s.y * 0.5)
	return AABB(lo, hi - lo)


static func _on(p: Dictionary, v: Vector3, margin: float) -> bool:
	var c: Vector3 = p.c
	var s: Vector2 = p.s
	return absf(v.x - c.x) <= s.x * 0.5 + margin and absf(v.z - c.z) <= s.y * 0.5 + margin and absf(v.y - c.y) < 0.05


## A bolt is fine over any floor (any time) within a jump's height, or over a hop between floors at most 1.9 up.
static func _bolt_ok(lv: Dictionary, b: Vector3) -> bool:
	for f in lv.get("fans", []):  # (floating at the top of a fan's updraft)
		if b.x > float(f.x0) and b.x < float(f.x1) and absf(b.z) < float(f.w) * 0.5 and b.y < float(f.top) + 0.5 and b.y > float(f.top) - 1.5:
			return true
	var top := JUMP_V * JUMP_V / (2.0 * GRAVITY) + ROBOT_H * 0.5 + TOUCH - 0.3
	for p in lv.plats:
		var a := _sweep(p)
		var y_hi := a.position.y + a.size.y  # (the highest top of a lift's way)
		var y_lo := y_hi - (a.size.y - THICK)
		if b.x < a.position.x - 1.4 or b.x > a.end.x + 1.4 or b.z < a.position.z - 1.0 or b.z > a.end.z + 1.0:
			continue
		if b.y - y_hi <= top and b.y - y_lo >= 0.2:
			return true
	return false
