extends RefCounted
## BLOCK BUILDERS second pass (pure data + small functions; tests/block_builders_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked once a session on the pick orbs before the
##             first sky course: how big the courses are (a step down or up the adventures; TODAY'S SKY keeps its
##             own), how many spare planks the tray gets, how often Puff's sky plays a warned surprise, how long it is
##             told first, how strong the wind is, how big a wobble is and how long it makes runners dizzy.
##   GIFTS     PUFF'S BLOCK GIFTS for the whole team, three offered on the pick orbs before every sky course from a
##             session's second: STICKY BRICKS (wind and wobbles can't move anyone), BIG BRICKS (every plank brings a
##             free plank beside it: wider bridges), BUILDER ROBOT (a little robot puts the glowing block in when the
##             builder waits), BLOCK BOX (one spare of every block) and JUMPY BOOTS (jump higher) - the last two
##             open as Puff's town grows.
##   SURPRISES warned by steady core/warn_rings.gd shapes on bare island ground (each kind its own colour), never on
##             the lessons, never on a session's first course (bots: BB_TRICKS_NOW), never in a course's first
##             seconds, never two at once, only near a runner:
##               WIND    a blue band across an island: a gust blows runners in it towards the front edge.
##               WOBBLE  an orange-red circle: the ground wobbles, runners in it hop (BRAVE / HARD: dizzy a moment).
##             spots(lv, mode) is every fair place for them on a course (the same on every machine); problems()
##             proves each one fair (bare ground only - never over a block, the start, the flag or the friend's
##             planks - told long enough for a small kid in its middle to walk out onto ground that stays safe).
##   SEASONS   Puff's seasonal build sites (Seeded.season): BLOSSOM / SUNNY / LEAFY / SNOWY SKY pick the course themes
##             (spring meadows, summer beaches, autumn leaves, winter snow), the surprise mix, seasonal props on little
##             floating rocks behind the course and drifting petals / pollen / leaves / snow (season.gd).
##   TOWN      every finished sky course adds a little building to PUFF'S TOWN, a floating island below and behind the
##             course (town.gd): houses, towers, windmills, lighthouses, tree houses and a castle every tenth, roofs
##             in the mode's colour (saved: town). The island shows once the first one is built.
##   PICK ROWS with runners who are people: three big orbs over the start island, across it, and a runner STANDS under
##             one for TV_DWELL s (running past never picks). A flat builder alone: three orbs over the middle of the
##             course and the glove hovers under one TV_DWELL s. The VR builder alone (the buddy runner): three small
##             orbs an arm's reach in front of the builder's eyes and the hand moves into one and stays DWELL s.
##             Something already in an orb when they pop up must leave and come back. Nobody in time = the middle.

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")

## step: the adventure size moved by this many steps (CourseGen.generate's adv); spare: planks added to the tray;
## every: seconds between surprises; warn: seconds told first; wind: m/s a gust pushes; wobble_r: a wobble's radius;
## dizzy: seconds a wobble stops a runner (0: just a hop).
const MODES := {
	"gentle": {"step": -2, "spare": 2, "every": 40.0, "warn": 3.6, "wind": 1.2, "wobble_r": 1.0, "dizzy": 0.0},
	"brave": {"step": 0, "spare": 1, "every": 30.0, "warn": 3.0, "wind": 2.2, "wobble_r": 1.25, "dizzy": 0.6},
	"hard": {"step": 2, "spare": 0, "every": 24.0, "warn": 2.6, "wind": 3.0, "wobble_r": 1.5, "dizzy": 1.0},
}
const MAX_ADV := 989  # (story.gd ADVENTURES - 1)
const MIN_WARN := 2.0
const REACT := 0.8  # seconds a runner takes to notice a tell and start walking
const RUN_SPEED := 4.3 * 0.7  # m/s a small kid really runs (runner.gd SPEED, a wobbly stick)
const FIRST_T := 15.0  # no surprise in a course's first seconds
const SHORT_FIRST := 4.0  # (bots: BB_TRICKS_NOW)
const RETRY := 2.0  # nobody near a fair spot: look again this much later
const NEAR := 6.0  # a surprise only goes where a runner is this near
const AFTER := {"wind": 2.0, "wobble": 0.6}  # seconds a surprise lasts after its tell
const HOP := 6.0  # a wobble's hop (m/s up)
const HIT_PAD := 0.25  # a runner's middle this near a zone's edge is still in it
const ESCAPE_PAD := 0.3  # ... and an escape lands this far outside that
const EDGE := 0.35  # safe ground keeps this far from an island's edge
const BLOCK_PAD := 0.3  # a zone keeps this far from any block of the course's solution
const WIND_W := 0.8  # half a wind band's width (along the course)
const WIND_COLOR := Color(0.2, 0.35, 0.95)  # wind blue
const WOBBLE_COLOR := Color(0.95, 0.3, 0.1)  # wobble orange-red
const KINDS: Array[String] = ["wind", "wobble"]
const KIND_PICS := {"wind": "gust", "wobble": "quake"}
const KIND_NAMES := {"wind": "WIND!", "wobble": "WOBBLE!"}
## Season -> build site: name, surprise weights (wind, wobble), course themes (themes.gd), drift colour, picture, Puff's line.
const SEASONS := {
	"spring": {"name": "BLOSSOM SKY", "weights": [1.0, 1.0], "themes": ["meadow", "candy", "rainbow", "castle"],
		"drift": Color(1.0, 0.72, 0.86), "pic": "daisy", "line": "Blossom time!"},
	"summer": {"name": "SUNNY SKY", "weights": [0.7, 1.4], "themes": ["beach", "canyon", "meadow", "volcano"],
		"drift": Color(1.0, 0.95, 0.6), "pic": "sun", "line": "Sunny building!"},
	"autumn": {"name": "LEAFY SKY", "weights": [1.6, 0.7], "themes": ["autumn", "castle", "canyon", "night"],
		"drift": Color(0.95, 0.5, 0.15), "pic": "pumpkin", "line": "Leafy and windy!"},
	"winter": {"name": "SNOWY SKY", "weights": [1.0, 1.2], "themes": ["snow", "night", "candy", "castle"],
		"drift": Color(0.97, 0.98, 1.0), "pic": "snowflake", "line": "Snowy building!"},
}
## Block gifts: id, name, picture, a short line, a colour, town buildings needed.
const GIFTS: Array[Dictionary] = [
	{"id": "sticky", "name": "STICKY BRICKS", "pic": "stickybrick", "line": "Sticky feet!", "color": Color(0.55, 1.0, 0.35), "unlock": 0},
	{"id": "big", "name": "BIG BRICKS", "pic": "bigbrick", "line": "Wide bridges!", "color": Color(1.0, 0.6, 0.25), "unlock": 0},
	{"id": "robot", "name": "BUILDER ROBOT", "pic": "robot", "line": "Beep! I can build!", "color": Color(0.7, 0.8, 1.0), "unlock": 0},
	{"id": "box", "name": "BLOCK BOX", "pic": "blockbox", "line": "Spare blocks!", "color": Color(1.0, 0.85, 0.3), "unlock": 2},
	{"id": "boots", "name": "JUMPY BOOTS", "pic": "jumpboots", "line": "Boing boing!", "color": Color(1.0, 0.45, 0.7), "unlock": 4},
]
const BOOTS := 1.15  # JUMPY BOOTS: jump speed x this
const ROBOT_IDLE := 7.0  # BUILDER ROBOT: seconds the builder waits before the robot puts the glowing block in
## Puff's town: one building per finished sky course (kind ids are story pictures).
const TOWN_KINDS: Array[String] = ["house", "tower", "windmill", "lighthouse", "treehouse", "castle"]
const TOWN_SHOWN := 24  # the newest this many stand on the island
const TOWN_COLS := 8
const TOWN_GAP := 2.4
const TOWN_AT := Vector3(0.0, -3.0, -15.5)  # the town island's middle (top), below and behind the course
## The pick rows. Start row: across the start island (z), ROW_AHEAD past the start, ROW_Y over its top.
const ROW_AHEAD := 1.6
const ROW_Z: Array[float] = [-1.2, 0.5, 2.2]  # (a runner camera looks +X: -Z is on the left, GENTLE first)
const ROW_Y := 2.4
const ORB_SCALE := 0.7
const TV_R := 0.7  # a runner's middle (or the flat glove) this near an orb's spot (across the ground) is under it ...
const TV_DWELL := 0.8  # ... for this long to pick it
## Flat builder row: along X over the middle of the course (the flat camera looks down from +Z).
const FLAT_X: Array[float] = [-3.0, 0.0, 3.0]
const FLAT_Z := 0.5
const FLAT_Y := 3.2
const FLAT_SCALE := 0.9
## VR row (metres, times builder.gd S = 8 world units): an arm's reach in front of the builder's eyes, just under eye
## level; GENTLE on the builder's left.
const S := 8.0
const VR_X: Array[float] = [-0.3, 0.0, 0.3]
const VR_AHEAD := 0.42
const VR_BELOW := 0.14
const VR_SCALE := 0.14  # (times S in the world)
const HAND_R := 0.05  # metres: a hand this near an orb's ball touches it ...
const DWELL := 0.35  # ... for this long (deliberate: a hand sweeping past never picks)
const ROW_WAIT := {"mode": 20.0, "gift": 16.0}  # nobody took one: the middle
const EMPTY_WAIT := 8.0  # nobody here who could pick at all: sooner


static func mode_of(id: String) -> String:
	var m := String(PickOrbs.ALIASES.get(id, id))
	return m if MODES.has(m) else "brave"


static func mode_data(id: String) -> Dictionary:
	return MODES[mode_of(id)]


static func season_data(s: String) -> Dictionary:
	return SEASONS.get(s, SEASONS.spring)


static func wait_for(stage: String, nobody: bool) -> float:
	return EMPTY_WAIT if nobody else float(ROW_WAIT.get(stage, 16.0))


## The adventure size a course is built at in a mode (TODAY'S SKY keeps its own).
static func mode_adv(adv: int, mode: String) -> int:
	return clampi(adv + int(mode_data(mode).step), 0, MAX_ADV)


## A course's theme for the season (the same on every machine for a seed).
static func season_theme(seed_value: int, season: String) -> String:
	var th: Array = season_data(season).themes
	return String(th[Seeded.rng(seed_value, "season theme").randi() % th.size()])


## Problems with the mode table (GENTLE <= BRAVE <= HARD in every way that makes it harder).
static func ordered() -> Array:
	var out: Array = []
	var g: Dictionary = MODES.gentle
	var b: Dictionary = MODES.brave
	var h: Dictionary = MODES.hard
	for k in ["step", "wind", "wobble_r", "dizzy"]:  # more is harder
		if not (float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k])):
			out.append("%s not gentle <= brave <= hard" % k)
	for k in ["spare", "every", "warn"]:  # more is gentler
		if not (float(g[k]) >= float(b[k]) and float(b[k]) >= float(h[k])):
			out.append("%s not most on gentle" % k)
	if float(h.warn) < MIN_WARN:
		out.append("hard warns under %.1f s" % MIN_WARN)
	if float(g.dizzy) != 0.0:
		out.append("gentle wobbles make runners dizzy")
	if float(h.wind) >= RUN_SPEED:
		out.append("hard wind is stronger than a small kid walks")
	if int(g.spare) < 1:
		out.append("gentle has no spare plank")
	return out


# --- Courses' surprise spots ----------------------------------------------------------------------------------

## The course's main islands (the path's; not the friend's side island): [[x0, x1, z0, z1, top], ...].
static func main_islands(lv: Dictionary) -> Array:
	var out: Array = []
	for g in lv.get("ground", []):
		if int(g[2]) == -2 and int(g[3]) == 3:
			out.append(g)
	return out


## Is p (x, z) bare safe ground on island g: inside it (EDGE in), off every solution block (BLOCK_PAD)?
static func bare(lv: Dictionary, g: Array, p: Vector2) -> bool:
	if p.x < float(g[0]) + EDGE or p.x > float(g[1]) - EDGE or p.y < float(g[2]) + EDGE or p.y > float(g[3]) - EDGE:
		return false
	for s in lv.get("solution", []):
		var c: Vector3i = s[1]
		if p.x > c.x - BLOCK_PAD and p.x < c.x + 1 + BLOCK_PAD and p.y > c.z - BLOCK_PAD and p.y < c.z + 1 + BLOCK_PAD:
			return false
	return true


## How far p is inside zone e: > 0 inside (metres past the edge), < 0 outside.
static func depth(e: Dictionary, p: Vector2) -> float:
	if String(e.kind) == "wobble":
		return float(e.w) - p.distance_to(Vector2(float(e.x), float(e.z)))
	return float(e.w) - absf(p.x - float(e.x))  # (a wind band runs across the island: only x matters)


static func inside(e: Dictionary, p: Vector3, pad: float = HIT_PAD) -> bool:
	if String(e.kind) == "wind" and (p.z < float(e.z0) - pad or p.z > float(e.z1) + pad):
		return false
	if absf(p.y - float(e.y)) > 1.2:
		return false  # (on a block above it, or below on another island)
	return depth(e, Vector2(p.x, p.z)) > -pad


## The zone's corners must all be bare ground (no blocks, start, flag or friend under it).
static func _zone_bare(lv: Dictionary, g: Array, e: Dictionary) -> bool:
	var pts: Array = []
	var w := float(e.w) + 0.1
	if String(e.kind) == "wobble":
		for k in 12:
			pts.append(Vector2(float(e.x), float(e.z)) + Vector2.RIGHT.rotated(k * TAU / 12.0) * w)
		pts.append(Vector2(float(e.x), float(e.z)))
	else:
		for z in [float(g[2]) + EDGE, 0.5, float(g[3]) - EDGE]:
			for dx in [-w, 0.0, w]:
				pts.append(Vector2(float(e.x) + dx, float(z)))
	for p in pts:
		var q: Vector2 = p
		if String(e.kind) == "wind":  # the band spans the island: only blocks matter, not its edges
			q = Vector2(q.x, clampf(q.y, float(g[2]) + EDGE, float(g[3]) - EDGE))
			if q.x < float(g[0]) + 0.05 or q.x > float(g[1]) - 0.05:
				return false
			for s in lv.get("solution", []):
				var c: Vector3i = s[1]
				if q.x > c.x - BLOCK_PAD and q.x < c.x + 1 + BLOCK_PAD and float(c.z) < float(g[3]) and float(c.z) + 1.0 > float(g[2]):
					return false
		elif not bare(lv, g, q):
			return false
	for key in ["start", "flag"]:
		var fp: Vector3 = lv.get(key, Vector3.INF)
		if absf(fp.y - float(g[4])) < 0.5 and depth(e, Vector2(fp.x, fp.z)) > -1.2:
			return false
	return true


## The nearest bare spot outside e from p (ESCAPE_PAD out), Vector2.INF if none.
static func escape(lv: Dictionary, g: Array, e: Dictionary, p: Vector2) -> Vector2:
	var need := float(e.w) + HIT_PAD + ESCAPE_PAD + 0.05
	var cands: Array = []
	if String(e.kind) == "wobble":
		var c := Vector2(float(e.x), float(e.z))
		var away := (p - c).normalized() if p.distance_to(c) > 0.05 else Vector2.DOWN
		for k in 16:
			cands.append(c + away.rotated(k * TAU / 16.0) * need)
	else:
		cands = [Vector2(float(e.x) - need, p.y), Vector2(float(e.x) + need, p.y)]
	var best := Vector2.INF
	for q in cands:
		var qq: Vector2 = q
		if not bare(lv, g, qq):
			continue
		if best == Vector2.INF or p.distance_to(qq) < p.distance_to(best):
			best = qq
	return best


## The worst places to be when a tell starts (its middle; for wind all across the island).
static func worst_spots(g: Array, e: Dictionary) -> Array:
	if String(e.kind) == "wobble":
		var c := Vector2(float(e.x), float(e.z))
		return [c, c + Vector2(0.4, 0.0), c - Vector2(0.4, 0.0), c + Vector2(0.0, 0.4), c - Vector2(0.0, 0.4)]
	var out: Array = []
	var z := float(g[2]) + EDGE
	while z <= float(g[3]) - EDGE + 0.001:
		out.append(Vector2(float(e.x), z))
		z += 0.5
	return out


static func _make(kind: String, g: Array, x: float, z: float, md: Dictionary) -> Dictionary:
	var e := {"kind": kind, "x": snappedf(x, 0.01), "z": snappedf(z, 0.01), "y": float(g[4]), "warn": float(md.warn),
		"z0": float(g[2]), "z1": float(g[3])}
	e["w"] = float(md.wobble_r) if kind == "wobble" else WIND_W
	return e


## Every fair surprise spot on a course in a mode: [{kind, x, z, y, w, warn, z0, z1}] (start island excluded: the
## picks and the start are there). The same on every machine.
static func spots(lv: Dictionary, mode: String) -> Array:
	var md := mode_data(mode)
	var out: Array = []
	var isl := main_islands(lv)
	for gi in range(1, isl.size()):
		var g: Array = isl[gi]
		for kind in KINDS:
			var best := {}
			var mid := (float(g[0]) + float(g[1])) * 0.5
			var x := float(g[0]) + 0.5
			while x <= float(g[1]) - 0.5:
				var z := 0.5
				var e := _make(kind, g, x, z, md)
				if _where_problem(lv, g, e) == "":
					if best.is_empty() or absf(x - mid) < absf(float(best.x) - mid):
						best = e
				x += 0.5
			if not best.is_empty():
				out.append(best)
	return out


static func _island_of(lv: Dictionary, e: Dictionary) -> Array:
	for g in main_islands(lv):
		if float(e.x) > float(g[0]) and float(e.x) < float(g[1]) and absf(float(e.y) - float(g[4])) < 0.01:
			return g
	return []


static func _where_problem(lv: Dictionary, g: Array, e: Dictionary) -> String:
	if not _zone_bare(lv, g, e):
		return "not on bare ground"
	for p in worst_spots(g, e):
		var q := escape(lv, g, e, p)
		if q == Vector2.INF:
			return "no way out from %s" % str(p)
		if REACT + p.distance_to(q) / RUN_SPEED > float(e.warn):
			return "no way out in time from %s" % str(p)
	return ""


## Reasons a surprise spot is unfair (empty = fine).
static func problems(lv: Dictionary, e: Dictionary, mode: String) -> Array:
	var why: Array = []
	var md := mode_data(mode)
	var tag := "%s at %.1f" % [e.get("kind", "?"), float(e.get("x", 0.0))]
	if not KINDS.has(String(e.get("kind", ""))):
		return ["unknown surprise %s" % str(e)]
	if float(e.warn) < MIN_WARN or float(e.warn) < float(md.warn) - 0.001:
		why.append("%s: told only %.1f s" % [tag, float(e.warn)])
	var g := _island_of(lv, e)
	if g.is_empty():
		return why + ["%s: not on a main island" % tag]
	if g == main_islands(lv)[0]:
		why.append("%s: on the start island" % tag)
	var w := _where_problem(lv, g, e)
	if w != "":
		why.append("%s: %s" % [tag, w])
	return why


## The k-th surprise's kind on a course (the season's mix; the same on every machine).
static func kind_at(seed_value: int, k: int, season: String) -> String:
	return KINDS[Seeded.weighted(Seeded.rng(seed_value, "surprise %d" % k), season_data(season).weights)]


## The fair spot of a kind nearest p ({} none within NEAR).
static func pick_spot(list: Array, kind: String, p: Vector3) -> Dictionary:
	var best := {}
	var bd := NEAR
	for e in list:
		if String(e.kind) != kind:
			continue
		var d := Vector2(float(e.x) - p.x, float(e.z) - p.z).length()
		if d < bd and absf(p.y - float(e.y)) < 2.5:
			bd = d
			best = e
	return best


static func after(e: Dictionary) -> float:
	return float(AFTER.get(String(e.get("kind", "wind")), 1.0))


static func span(e: Dictionary) -> float:
	return float(e.warn) + after(e)


static func pack(e: Dictionary) -> Array:
	return [] if e.is_empty() else [String(e.kind), float(e.x), float(e.z), float(e.y), float(e.w), float(e.warn),
		float(e.z0), float(e.z1)]


static func unpack(a: Array) -> Dictionary:
	return {} if a.size() < 8 else {"kind": String(a[0]), "x": float(a[1]), "z": float(a[2]), "y": float(a[3]),
		"w": float(a[4]), "warn": float(a[5]), "z0": float(a[6]), "z1": float(a[7])}


## Where a runner standing in zone e should walk (Vector3.INF: it's fine where it is). Bots and the buddy.
static func escape_to(lv: Dictionary, e: Dictionary, p: Vector3) -> Vector3:
	if e.is_empty() or not inside(e, p, HIT_PAD + ESCAPE_PAD):
		return Vector3.INF
	var g := _island_of(lv, e)
	if g.is_empty():
		return Vector3.INF
	var q := escape(lv, g, e, Vector2(p.x, p.z))
	return Vector3.INF if q == Vector2.INF else Vector3(q.x, p.y, q.y)


# --- Gifts ----------------------------------------------------------------------------------------------------

static func unlocked(town_n: int) -> Array:
	var out: Array = []
	for g in GIFTS:
		if town_n >= int(g.unlock):
			out.append(String(g.id))
	return out


static func gift(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return {}


## Three different unlocked gifts: the newest unlock always among them, not the last one again when there are
## others (the same on every machine for a seed).
static func gift_choices(town_n: int, last: String, seed_value: int) -> Array:
	var un := unlocked(town_n)
	var newest: String = un[un.size() - 1]
	var pool: Array = []
	for id in un:
		if id != newest and (id != last or un.size() <= 3):
			pool.append(id)
	pool = Seeded.shuffled(Seeded.rng(seed_value, "gifts"), pool)
	var out: Array = [newest] if newest != last or un.size() <= 3 else []
	for id in pool:
		if out.size() >= 3:
			break
		out.append(id)
	if out.size() < 3:
		for id in un:
			if out.size() < 3 and not out.has(id):
				out.append(id)
	return Seeded.shuffled(Seeded.rng(seed_value, "gift order"), out)


## A course's tray: its budget plus the mode's spare planks and the BLOCK BOX (one more of every block it uses).
static func tray(budget: Dictionary, mode: String, gift_id: String) -> Dictionary:
	var out := budget.duplicate()
	if out.has("plank") or int(mode_data(mode).spare) > 0:
		out["plank"] = int(out.get("plank", 0)) + int(mode_data(mode).spare)
	if gift_id == "box":
		for k in out:
			if int(out[k]) > 0:
				out[k] = int(out[k]) + 1
	return out


## BIG BRICKS: the free plank that comes with a plank put at c (Vector3i(0, -99, 0): none). Never in a solution cell,
## never over the start or the flag, never inside an island, never off the build area.
const NO_CELL := Vector3i(0, -99, 0)


static func big_extra(lv: Dictionary, kind: String, c: Vector3i) -> Vector3i:
	if kind != "plank":
		return NO_CELL
	var e := Vector3i(c.x, c.y, c.z + 1)
	if e.z > 2 or e.z < -4:
		return NO_CELL
	for s in lv.get("solution", []):
		if (s[1] as Vector3i) == e:
			return NO_CELL
	var lo := float(e.y) + 0.7
	for g in lv.get("ground", []):
		if e.x + 1 > float(g[0]) + 0.01 and e.x < float(g[1]) - 0.01 and e.z + 1 > float(g[2]) + 0.01 and e.z < float(g[3]) - 0.01 \
				and lo < float(g[4]) - 0.01:
			return NO_CELL
	for key in ["start", "flag", "friend"]:
		var fp: Variant = lv.get(key, null)
		if fp is Vector3 and floori((fp as Vector3).x) == e.x and floori((fp as Vector3).z) == e.z:
			return NO_CELL
	return e


static func jump_scale(gift_id: String) -> float:
	return BOOTS if gift_id == "boots" else 1.0


static func sticky(gift_id: String) -> bool:
	return gift_id == "sticky"


# --- Town -----------------------------------------------------------------------------------------------------

## The n-th building's kind (0-based): mostly houses, a castle every tenth.
static func town_kind(n: int) -> String:
	if n % 10 == 9:
		return "castle"
	var cycle: Array[String] = ["house", "house", "tower", "house", "windmill", "house", "lighthouse", "treehouse", "house"]
	return cycle[(n - n / 10) % cycle.size()]


## Where the i-th shown building stands (x, z) on the town island (rows from the front).
static func town_spot(i: int) -> Vector2:
	var col := i % TOWN_COLS
	var row := i / TOWN_COLS
	return Vector2(TOWN_AT.x + (float(col) - (TOWN_COLS - 1) * 0.5) * TOWN_GAP, TOWN_AT.z + 2.4 - float(row) * TOWN_GAP)


# --- The pick rows --------------------------------------------------------------------------------------------

## The start row over a course's start island (lv: a levels.gd level).
static func row_spots(lv: Dictionary, n: int = 3) -> Array:
	var st: Vector3 = lv.get("start", Vector3.ZERO)
	var out: Array = []
	for i in n:
		var z: float = ROW_Z[i] if n == 3 else lerpf(ROW_Z[0], ROW_Z[2], float(i) / maxf(1.0, n - 1))
		out.append(Vector3(st.x + ROW_AHEAD, st.y + ROW_Y, z))
	return out


## The flat builder's row over the middle of the course.
static func flat_spots(n: int = 3) -> Array:
	var out: Array = []
	for i in n:
		var x: float = FLAT_X[i] if n == 3 else lerpf(FLAT_X[0], FLAT_X[2], float(i) / maxf(1.0, n - 1))
		out.append(Vector3(x, FLAT_Y, FLAT_Z))
	return out


## The VR row: an arm's reach in front of the builder's eyes (head: its transform; world units = metres x S).
static func vr_spots(head: Transform3D, n: int = 3) -> Array:
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	var out: Array = []
	for i in n:
		var x: float = VR_X[i] if n == 3 else lerpf(VR_X[0], VR_X[2], float(i) / maxf(1.0, n - 1))
		out.append(head.origin + (fwd * VR_AHEAD + right * x + Vector3.DOWN * VR_BELOW) * S)
	return out


## Which orb a point stands under (-1 none).
static func under(at: Array, p: Vector3) -> int:
	var best := -1
	var bd := TV_R
	for i in at.size():
		var s: Vector3 = at[i]
		var d := Vector2(s.x - p.x, s.z - p.z).length()
		if d < bd:
			bd = d
			best = i
	return best
