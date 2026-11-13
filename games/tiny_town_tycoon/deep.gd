extends RefCounted
## TINY TOWN TYCOON second pass (pure data + small functions; tests/tiny_town_tycoon_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked once a session on the pick orbs once the mayor's
##             practice is done: how often Benny's island has weather, how long it is told first, how big it is and
##             what it does to the vehicles (GENTLE: a wobble and a gentle slow; BRAVE / HARD: stopped a moment).
##   GIFTS     BENNY'S BUILDER GIFTS for the whole town, three offered on the pick orbs every morning (and right after the
##             mode): SPEEDY CRANE (bricks come two at a time and buildings pop up fast), DOUBLE HOUSES (every new house
##             brings a twin next door), HAPPY PARK (a park blueprint by the hall, and people near parks move in twice
##             as fast), ZOOMY WHEELS (every vehicle drives faster) and SUNNY DAY (the weather is gentle all day) - the
##             last two open as Benny's archipelago grows islets. A gift never makes a vehicle slower or the weather
##             stronger: problems() proves every gift in every mode.
##   WEATHER   told in advance by steady core/warn_rings.gd shapes on the island (each kind its own colour), never in a
##             session's first minute, never two at once, never during a pick:
##               GUST  an orange band across the island: a gust blows along it and spins the vehicles in it.
##               FOG   a purple circle: sleepy fog settles in it and vehicles crawl through it for a while.
##             Drive out of it! weather(isl, spec) is the same list for an island and a day; problems() proves it fair
##             (told long enough for a vehicle in its middle to drive out at woods speed round the island's water and
##             rocks, there's always land outside, hit by every weather a vehicle still drives most of the day).
##   SEASONS   Benny's islands by season (Seeded.season): BLOSSOM ISLAND, SUNNY ISLAND (more gusts), LEAFY ISLAND (more
##             gusts), SNOWY ISLAND (more fog); seasonal props on the lawn round the table and drifting petals / leaves /
##             snow (season.gd).
##   ISLETS    every ISLET_EVERY wishes granted (any town, saved: wishes_total) a little islet rises in the sea round the
##             island for good (islets.gd): a palm isle, a lighthouse rock, a windmill isle ... Benny's archipelago.
##   PICK ROW  with drivers (or the flat mayor): three orbs float over road cells by the town hall and a driver STANDS
##             their vehicle under one TV_DWELL s (the flat mayor holds the cursor under one); driving past never picks.
##             With only the VR mayor: three small orbs an arm's reach in front of their eyes, names over them; a hand
##             moves into one and stays DWELL s. Something already in an orb when they pop up must leave and come back.
##             Nobody in time = the middle (it glows).

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const Defs := preload("res://games/tiny_town_tycoon/defs.gd")

## every: seconds between weather; warn: seconds told first; gust_w: half a gust band's depth (m); fog_r: a fog's
## radius (m); stall: seconds a gust stops a vehicle; fog_slow: speed in the fog (x); fog_secs: how long fog stays.
const MODES := {
	"gentle": {"every": 160.0, "warn": 5.0, "gust_w": 0.06, "fog_r": 0.1, "stall": 0.0, "fog_slow": 0.85, "fog_secs": 8.0},
	"brave": {"every": 120.0, "warn": 4.4, "gust_w": 0.075, "fog_r": 0.125, "stall": 1.2, "fog_slow": 0.65, "fog_secs": 10.0},
	"hard": {"every": 90.0, "warn": 3.8, "gust_w": 0.09, "fog_r": 0.15, "stall": 2.0, "fog_slow": 0.5, "fog_secs": 12.0},
}
const MIN_WARN := 3.0
const REACT := 0.8  # seconds a driver takes to notice a tell and start driving
const MAX_SPEED := 0.21  # vehicle.gd MAX_SPEED (the deep test checks it)
const SLOWEST := MAX_SPEED * 0.5  # in the woods (town.gd speed_at): the slowest a vehicle drives anywhere
const PATH := 1.15  # a driven way out is this much longer than the cells say (round buildings)
const FIRST_T := 40.0  # no weather in a day's first seconds ...
const FIRST_DAY0 := 75.0  # ... and longer on a session's first day
const SHORT_FIRST := 4.0  # (bots: TT_WEATHER_NOW)
const SHORT_GAP := 12.0
const MIN_GAP := 50.0  # seconds between two weathers' tells
const END_PAD := 5.0  # every weather is over this long before the day ends
const GUST_AFTER := 1.0  # a gust blows this long after its tell
const HIT_PAD := 0.012  # a vehicle's middle this near a zone's edge is still in it
const ESCAPE_PAD := 0.012  # ... and a way out ends this far outside that
const MAX_SLOW_SHARE := 0.1  # hit by every weather, a vehicle loses at most this share of the day
const MAX_LAND_SHARE := 0.35  # a weather never covers more of the island's land than this
const MIN_LAND := 4  # ... and always some (no weather out at sea)
const GUST_COLOR := Color(1.0, 0.55, 0.1)  # gust orange
const FOG_COLOR := Color(0.62, 0.38, 1.0)  # fog purple
const KINDS: Array[String] = ["gust", "fog"]
const KIND_PICS := {"gust": "gust", "fog": "sleepyfog"}
const KIND_NAMES := {"gust": "GUSTY WIND!", "fog": "SLEEPY FOG!"}
## Season -> island: name, weather weights (gust, fog), drift colour, picture, Benny's line.
const SEASONS := {
	"spring": {"name": "BLOSSOM ISLAND", "weights": [1.0, 1.0], "drift": Color(1.0, 0.7, 0.85), "pic": "daisy", "line": "BLOSSOM ISLAND!", "color": Color(1.0, 0.55, 0.75)},
	"summer": {"name": "SUNNY ISLAND", "weights": [1.3, 0.7], "drift": Color(1.0, 0.95, 0.6), "pic": "sun", "line": "SUNNY ISLAND!", "color": Color(1.0, 0.8, 0.2)},
	"autumn": {"name": "LEAFY ISLAND", "weights": [1.6, 0.6], "drift": Color(0.95, 0.5, 0.15), "pic": "pumpkin", "line": "LEAFY ISLAND!", "color": Color(0.95, 0.5, 0.15)},
	"winter": {"name": "SNOWY ISLAND", "weights": [0.7, 1.5], "drift": Color(0.97, 0.98, 1.0), "pic": "snowflake", "line": "SNOWY ISLAND!", "color": Color(0.55, 0.8, 1.0)},
}
## Builder gifts: id, name, picture, a short line, a colour, islets needed.
const GIFTS: Array[Dictionary] = [
	{"id": "crane", "name": "SPEEDY CRANE", "pic": "crane", "line": "SPEEDY CRANE!", "color": Color(1.0, 0.78, 0.15), "unlock": 0},
	{"id": "double", "name": "DOUBLE HOUSES", "pic": "twinhouses", "line": "TWO HOUSES!", "color": Color(1.0, 0.5, 0.45), "unlock": 0},
	{"id": "park", "name": "HAPPY PARK", "pic": "happypark", "line": "A HAPPY PARK!", "color": Color(0.45, 0.95, 0.5), "unlock": 0},
	{"id": "zoomy", "name": "ZOOMY WHEELS", "pic": "speedup", "line": "ZOOM ZOOM!", "color": Color(0.4, 0.8, 1.0), "unlock": 2},
	{"id": "sunny", "name": "SUNNY DAY", "pic": "sun", "line": "A SUNNY DAY!", "color": Color(1.0, 0.92, 0.35), "unlock": 4},
]
const CRANE_BUILD := 0.8  # SPEEDY CRANE: seconds a site takes once its bricks are in (sim.gd: 2.5) ...
const CRANE_CARRY := 2  # ... and bricks a load
const PARK_MOVE := 2.0  # HAPPY PARK: people near a park move in this much faster ...
const PARK_NEAR := 3.5  # ... within this many cells
const ZOOMY := 1.25  # ZOOMY WHEELS: vehicles x this
## Islets: one every ISLET_EVERY wishes granted (name, picture).
const ISLET_EVERY := 3
const ISLETS: Array[Dictionary] = [
	{"id": "palm", "name": "PALM ISLE", "pic": "island"},
	{"id": "lighthouse", "name": "LIGHTHOUSE ROCK", "pic": "lighthouse"},
	{"id": "windmill", "name": "WINDMILL ISLE", "pic": "windmill"},
	{"id": "tent", "name": "CAMP ISLE", "pic": "tent"},
	{"id": "flowers", "name": "FLOWER ISLE", "pic": "daisy"},
	{"id": "castle", "name": "CASTLE ISLE", "pic": "castle"},
	{"id": "treehouse", "name": "TREEHOUSE ISLE", "pic": "treehouse"},
	{"id": "fountain", "name": "FOUNTAIN ISLE", "pic": "fountain"},
]
## Where the islets rise (angle in radians from +X towards +Z, round the table's middle): in the sea between the island
## (a 1.21 m square) and the table's edge (the cloth ends at 0.89 m), never on the mayor's side (+Z, the tray) nor by
## the windmill toy (props.gd WINDMILL_AT, angle 0.65).
const ISLET_RING := 0.75
const ISLET_R := 0.06
const ISLET_ANGLES: Array[float] = [-PI * 0.5, PI, 0.0, -PI * 0.5 - 0.3, -PI * 0.5 + 0.3, PI - 0.3, -0.3, PI + 0.3]
## The island pick row: three orbs over road cells near the town hall's door, ORB_Y above the grass.
const ROW_GAP := 3  # cells between two orbs at least
const ORB_Y := 0.07
const ORB_SCALE := 0.045  # (a ball of radius 0.027 m: bigger than a toy vehicle, smaller than a house)
const TV_R := 0.03  # a vehicle's middle this near an orb's spot (across the ground) is under it ...
const TV_DWELL := 0.8  # ... for this long to pick it (driving past never picks)
## The VR pick row: three small orbs an arm's reach in front of the mayor's eyes, just under eye level.
const VR_X: Array[float] = [-0.3, 0.0, 0.3]
const VR_AHEAD := 0.45
const VR_BELOW := 0.14
const VR_SCALE := 0.11
const HAND_R := 0.05  # a VR grab point this near an orb's ball touches it ...
const DWELL := 0.35  # ... for this long (deliberate: a hand sweeping past never picks)
const ROW_WAIT := {"mode": 20.0, "gift": 16.0}  # nobody took one: the middle
const EMPTY_WAIT := 8.0  # nobody here who could pick at all: sooner
const SETTLE := 3.0  # seconds after the practice (or a sail) before a pick pops up
const MORNING := 7.0  # the town clock's hour a new day (and its gift pick) begins


static func mode_of(id: String) -> String:
	var m := String(PickOrbs.ALIASES.get(id, id))
	return m if MODES.has(m) else "brave"


static func mode_data(id: String) -> Dictionary:
	return MODES[mode_of(id)]


static func season_data(s: String) -> Dictionary:
	return SEASONS.get(s, SEASONS.spring)


static func wait_for(stage: String, nobody: bool) -> float:
	return EMPTY_WAIT if nobody else float(ROW_WAIT.get(stage, 16.0))


## Problems with the mode table (GENTLE <= BRAVE <= HARD in every way that makes it harder).
static func ordered() -> Array:
	var out: Array = []
	var g: Dictionary = MODES.gentle
	var b: Dictionary = MODES.brave
	var h: Dictionary = MODES.hard
	for k in ["gust_w", "fog_r", "stall", "fog_secs"]:  # more is harder
		if not (float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k])):
			out.append("%s not gentle <= brave <= hard" % k)
	for k in ["every", "warn", "fog_slow"]:  # more is gentler
		if not (float(g[k]) >= float(b[k]) and float(b[k]) >= float(h[k])):
			out.append("%s not most on gentle" % k)
	if float(h.warn) < MIN_WARN:
		out.append("hard warns under %.1f s" % MIN_WARN)
	if float(h.every) < MIN_GAP:
		out.append("hard: weather closer than %.0f s" % MIN_GAP)
	if float(g.stall) != 0.0:
		out.append("gentle gusts stop vehicles")
	if float(h.fog_slow) <= 0.0:
		out.append("hard fog stops vehicles")
	return out


# --- What weather does (every machine) ------------------------------------------------------------------------

## What the weather does to a vehicle in this mode with this gift: {stall, slow, fog_secs} (SUNNY DAY: gentle's).
static func effect(mode: String, gift_id: String) -> Dictionary:
	var md := mode_data(mode)
	var soft: Dictionary = MODES.gentle if gift_id == "sunny" else md
	return {"stall": minf(float(md.stall), float(soft.stall)), "slow": maxf(float(md.fog_slow), float(soft.fog_slow))}


## A vehicle's speed factor from its gift (ZOOMY WHEELS).
static func gift_speed(gift_id: String) -> float:
	return ZOOMY if gift_id == "zoomy" else 1.0


# --- Weather ---------------------------------------------------------------------------------------------------

## The weather of a day on an island: [{t, kind, x, z, w, warn, after}] by time. t: when the tell starts (seconds
## after the day's weather began); it goes off at t + warn and lasts `after`. gust: a band across the whole island at
## z of half-depth w. fog: a circle at (x, z) of radius w. isl: {ter} (the island's terrain, Town.ter). spec: {seed,
## mode, season, day (0: the session's first), len (seconds left in the day), first, gap (bots: sooner)}.
static func weather(isl: Dictionary, spec: Dictionary) -> Array:
	var out: Array = []
	var mode := mode_of(String(spec.get("mode", "brave")))
	var md := mode_data(mode)
	var weights: Array = season_data(String(spec.get("season", "spring"))).weights
	var rlen := float(spec.get("len", 400.0))
	var first := float(spec.get("first", FIRST_DAY0 if int(spec.get("day", 1)) == 0 else FIRST_T))
	var gap := float(spec.get("gap", MIN_GAP))
	var every := maxf(float(md.every) if gap >= MIN_GAP else gap * 1.3, gap)
	var r := Seeded.rng(int(spec.get("seed", 1)), "weather %s %d" % [mode, int(rlen)])
	var ter := open_land(isl)
	var land := _land_cells(ter)
	if land.size() < MIN_LAND * 3:
		return out
	var t := first + r.randf_range(0.0, every * 0.25)
	var cost := _slow_cost(md)
	while t + float(md.warn) + float(md.fog_secs) <= rlen - END_PAD:
		var kind: String = KINDS[Seeded.weighted(r, weights)]
		if cost * (out.size() + 1) > MAX_SLOW_SHARE * maxf(rlen, 1.0):
			break  # (hit by every weather, a vehicle still drives most of the day)
		var e := {}
		for attempt in 24:
			e = _make(r, kind, t, md, land)
			if _where_problem(ter, e, out, gap).is_empty():
				break
			e = {}
		if not e.is_empty():
			out.append(e)
		t += maxf(gap, every * r.randf_range(0.85, 1.2))
	return out


## Seconds a vehicle loses to the worst weather of this mode (a gust's stop, or crawling through the fog).
static func _slow_cost(md: Dictionary) -> float:
	return maxf(float(md.stall), float(md.fog_secs) * (1.0 - float(md.fog_slow)))


## The island's terrain with the districts still under the mist turned to water: weather only comes where the town
## can drive (isl: {ter, dist, open} - Town or IslandGen; no dist: all of it).
static func open_land(isl: Dictionary) -> PackedByteArray:
	var ter: PackedByteArray = (isl.get("ter", PackedByteArray()) as PackedByteArray).duplicate()
	var dist: PackedByteArray = isl.get("dist", PackedByteArray())
	if dist.size() != ter.size():
		return ter
	var open := int(isl.get("open", 1)) | 1
	for i in ter.size():
		if (open >> int(dist[i])) & 1 == 0:
			ter[i] = Defs.T_WATER
	return ter


static func _land_cells(ter: PackedByteArray) -> Array:
	var out: Array = []
	for i in ter.size():
		if _is_land(int(ter[i])):
			out.append(i)
	return out


static func _is_land(t: int) -> bool:
	return t == Defs.T_GRASS or t == Defs.T_SAND


static func _make(r: RandomNumberGenerator, kind: String, t: float, md: Dictionary, land: Array) -> Dictionary:
	var ci: int = land[r.randi() % land.size()]
	var c := Defs.cell_center(ci % Defs.GRID, ci / Defs.GRID)
	var e := {"t": snappedf(t, 0.01), "kind": kind, "warn": float(md.warn)}
	if kind == "gust":
		e.merge({"x": 0.0, "z": snappedf(c.z, 0.001), "w": float(md.gust_w), "after": GUST_AFTER}, true)
	else:
		e.merge({"x": snappedf(c.x, 0.001), "z": snappedf(c.z, 0.001), "w": float(md.fog_r), "after": float(md.fog_secs)}, true)
	return e


static func span(e: Dictionary) -> float:
	return float(e.warn) + float(e.get("after", GUST_AFTER))


## How far a point p (x, z, metres) is inside weather e's zone: > 0 inside (metres past the edge), < 0 outside.
static func depth(e: Dictionary, p: Vector2) -> float:
	if String(e.kind) == "fog":
		return float(e.w) - p.distance_to(Vector2(float(e.x), float(e.z)))
	if absf(p.x) > Defs.HALF + Defs.CELL:
		return -1.0
	return float(e.w) - absf(p.y - float(e.z))


## Is a vehicle at p in e (HIT_PAD: its body)?
static func inside(e: Dictionary, p: Vector2, pad: float = HIT_PAD) -> bool:
	return not e.is_empty() and depth(e, p) > -pad


## The nearest point just outside e from p (straight out: across a gust band, or away from the fog's middle).
static func way_out(e: Dictionary, p: Vector2) -> Vector2:
	var need := float(e.w) + HIT_PAD + ESCAPE_PAD + 0.006
	if String(e.kind) == "fog":
		var c := Vector2(float(e.x), float(e.z))
		var away := (p - c).normalized() if p.distance_to(c) > 0.002 else Vector2.RIGHT
		return c + away * need
	var up := p.y >= float(e.z)
	return Vector2(p.x, float(e.z) + (need if up else -need))


## Seconds the slowest vehicle needs from every land cell inside e to land outside it (REACT + driving the shortest
## way over land round the water and rocks, PATH longer for buildings): {worst (INF: a cell with no way out), cells
## (land cells inside), safe (land cells outside)}.
static func escape_times(ter: PackedByteArray, e: Dictionary) -> Dictionary:
	var n := Defs.GRID
	var dist := PackedInt32Array()
	dist.resize(n * n)
	dist.fill(-1)
	var queue: Array[int] = []
	var inside_cells: Array[int] = []
	var safe := 0
	for i in n * n:
		if not _is_land(int(ter[i])):
			continue
		var c := Defs.cell_center(i % n, i / n)
		var d := depth(e, Vector2(c.x, c.z))
		if d > -HIT_PAD:
			inside_cells.append(i)
		elif d < -(HIT_PAD + ESCAPE_PAD):
			dist[i] = 0
			queue.append(i)
			safe += 1
	var head := 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var x := i % n
		var z := i / n
		for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + dd.x
			var nz: int = z + dd.y
			if nx < 0 or nz < 0 or nx >= n or nz >= n:
				continue
			var j := nz * n + nx
			if dist[j] >= 0 or not _is_land(int(ter[j])):
				continue
			dist[j] = dist[i] + 1
			queue.append(j)
	var worst := 0.0
	for i in inside_cells:
		if dist[i] < 0:
			return {"worst": INF, "cells": inside_cells.size(), "safe": safe}
		worst = maxf(worst, REACT + (float(dist[i]) + 0.5) * Defs.CELL * PATH / SLOWEST)
	return {"worst": worst, "cells": inside_cells.size(), "safe": safe}


static func _where_problem(ter: PackedByteArray, e: Dictionary, earlier: Array, gap: float = MIN_GAP) -> String:
	if not earlier.is_empty() and float(e.t) - float((earlier[earlier.size() - 1] as Dictionary).t) < gap - 0.001:
		return "two weathers too close together"
	var et := escape_times(ter, e)
	var land := _land_cells(ter).size()
	if int(et.cells) < MIN_LAND:
		return "hardly any land in it (%d cells)" % int(et.cells)
	if float(et.cells) > MAX_LAND_SHARE * land:
		return "covers too much of the island (%d of %d cells)" % [int(et.cells), land]
	if float(et.worst) > float(e.warn):
		return "no way out in time (%.1f s, told %.1f s)" % [float(et.worst), float(e.warn)]
	return ""


## Reasons a day's weather is unfair (empty = fine). spec as weather(); spec.gift: the day's gift (it may only help).
static func problems(isl: Dictionary, list: Array, spec: Dictionary) -> Array:
	var why: Array = []
	var mode := mode_of(String(spec.get("mode", "brave")))
	var md := mode_data(mode)
	var gift_id := String(spec.get("gift", ""))
	var first := float(spec.get("first", FIRST_DAY0 if int(spec.get("day", 1)) == 0 else FIRST_T))
	var gap := float(spec.get("gap", MIN_GAP))
	var rlen := float(spec.get("len", 400.0))
	var ter := open_land(isl)
	var fx := effect(mode, gift_id)
	if float(fx.stall) > float(md.stall) or float(fx.slow) < float(md.fog_slow) or gift_speed(gift_id) < 1.0:
		why.append("the gift %s makes the weather worse" % gift_id)
	var prev: Array = []
	for e in list:
		var tag := "%s at %.1f s" % [e.get("kind", "?"), float(e.get("t", 0.0))]
		if not KINDS.has(String(e.get("kind", ""))):
			why.append("unknown weather %s" % str(e))
			continue
		if float(e.t) < first - 0.001:
			why.append("%s: too early in the day" % tag)
		if float(e.t) + span(e) > rlen - END_PAD + 0.001:
			why.append("%s: runs past the day's end" % tag)
		if float(e.warn) < MIN_WARN or float(e.warn) < float(md.warn) - 0.001:
			why.append("%s: told only %.1f s" % [tag, float(e.warn)])
		var where := _where_problem(ter, e, prev, gap)
		if where != "":
			why.append("%s: %s" % [tag, where])
		if String(e.kind) == "fog" and (absf(float(e.x)) > Defs.HALF or absf(float(e.z)) > Defs.HALF):
			why.append("%s: off the island" % tag)
		prev.append(e)
	var lost := 0.0
	for e in list:
		lost += float(fx.stall) if String(e.kind) == "gust" else float(e.after) * (1.0 - float(fx.slow))
	if lost > MAX_SLOW_SHARE * maxf(rlen, 1.0) + 0.001:
		why.append("hit by every weather a vehicle loses %.0f s of %.0f" % [lost, rlen])
	return why


static func pack(e: Dictionary) -> Array:
	return [] if e.is_empty() else [String(e.kind), float(e.x), float(e.z), float(e.w), float(e.warn), float(e.t), float(e.after)]


static func unpack(a: Array) -> Dictionary:
	return {} if a.size() < 7 else {"kind": String(a[0]), "x": float(a[1]), "z": float(a[2]), "w": float(a[3]),
		"warn": float(a[4]), "t": float(a[5]), "after": float(a[6])}


# --- Gifts -----------------------------------------------------------------------------------------------------

static func unlocked(islets_n: int) -> Array:
	var out: Array = []
	for g in GIFTS:
		if islets_n >= int(g.unlock):
			out.append(String(g.id))
	return out


static func gift(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return {}


## Three different unlocked gifts: the newest unlock always among them, not the last one again when there are
## others (the same on every machine for a seed).
static func gift_choices(islets_n: int, last: String, seed_value: int) -> Array:
	return PickOrbs.gift_choices(unlocked(islets_n), last, seed_value)  # (the shared gift pick)


## DOUBLE HOUSES: where a new house at (x, z)'s twin goes (a free cell next to it on a road), (-1, -1) if none.
static func twin_spot(town, x: int, z: int) -> Vector2i:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		var c: Vector2i = Vector2i(x, z) + d
		if town.can_place("house", c.x, c.y) == "" and town.on_road({"kind": "house", "x": c.x, "z": c.y}):
			return c
	return Vector2i(-1, -1)


## HAPPY PARK: a park blueprint's cell near the town hall's door (on a road), (-1, -1) if none.
static func park_spot(town) -> Vector2i:
	var door := Vector2i(Defs.GRID / 2, Defs.GRID / 2)
	var halls: Array = town.of_kind("hall", true)
	if not halls.is_empty():
		door = town.door_cell(halls[0])
	var best := Vector2i(-1, -1)
	var bd := INF
	for z in Defs.GRID:
		for x in Defs.GRID:
			var d := Vector2(x - door.x, z - door.y).length()
			if d < bd and town.can_place("park", x, z) == "" and town.on_road({"kind": "park", "x": x, "z": z}):
				bd = d
				best = Vector2i(x, z)
	return best


# --- Islets ----------------------------------------------------------------------------------------------------

static func islets(wishes_total: int) -> int:
	return mini(ISLETS.size(), maxi(0, wishes_total) / ISLET_EVERY)


## Islet i's middle on the sea (y: the sea's surface).
static func islet_spot(i: int) -> Vector3:
	var a: float = ISLET_ANGLES[i % ISLET_ANGLES.size()]
	return Vector3(cos(a) * ISLET_RING, Defs.SEA_Y, sin(a) * ISLET_RING)


# --- The pick rows ---------------------------------------------------------------------------------------------

## The island row's cells: drivable road cells nearest the town hall's door, ROW_GAP apart (then any drivable land),
## sorted along X. town: town.gd (has_road, drivable, door_cell, of_kind).
static func row_cells(town, n: int = 3) -> Array:
	var door := Vector2i(Defs.GRID / 2, Defs.GRID / 2)
	var halls: Array = town.of_kind("hall", true)
	if not halls.is_empty():
		door = town.door_cell(halls[0])
	var roads: Array = []
	var land: Array = []
	for z in Defs.GRID:
		for x in Defs.GRID:
			if not town._drivable(x, z):
				continue
			var d := Vector2(x - door.x, z - door.y).length()
			if town.has_road(x, z):
				roads.append([d, Vector2i(x, z)])
			else:
				land.append([d, Vector2i(x, z)])
	roads.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	land.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out: Array = []
	for list in [roads, land]:
		for it in list:
			if out.size() >= n:
				break
			var c: Vector2i = it[1]
			var ok := true
			for o in out:
				if absi((o as Vector2i).x - c.x) + absi((o as Vector2i).y - c.y) < ROW_GAP:
					ok = false
			if ok:
				out.append(c)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out


## The island orbs' middles in the world.
static func row_spots(town, n: int = 3) -> Array:
	var out: Array = []
	for c in row_cells(town, n):
		out.append(Defs.cell_center((c as Vector2i).x, (c as Vector2i).y) + Vector3(0.0, ORB_Y, 0.0))
	return out


## The VR orbs' places: an arm's reach in front of the mayor's eyes (where they look, level), just under eye level,
## left to right as they see it.
static func vr_spots(head: Transform3D, n: int = 3) -> Array:
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var out: Array = []
	for i in n:
		var x: float = VR_X[i] if n == 3 else lerpf(VR_X[0], VR_X[2], float(i) / maxf(1.0, n - 1))
		out.append(head.origin + fwd * VR_AHEAD + right * x + Vector3.DOWN * VR_BELOW)
	return out


## Which island orb a point p (a vehicle, the flat cursor) is under (-1 none).
static func under(spots: Array, p: Vector3) -> int:
	var best := -1
	var bd := TV_R
	for i in spots.size():
		var s: Vector3 = spots[i]
		var d := Vector2(s.x - p.x, s.z - p.z).length()
		if d < bd:
			bd = d
			best = i
	return best
