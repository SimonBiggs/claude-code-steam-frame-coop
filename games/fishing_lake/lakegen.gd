extends RefCounted
## FISHING LAKE: the seeded lake of the day (no nodes, pure data, fast).
##   var lake := LakeGen.generate(seed, {"level": 2, "wish": FishScript.KOI, "daily": false})
## A lake is: the weather (sunny / rain / evening, with its own rain window and sky), 2-4 fishing SPOTS
## within casting reach of the jetty (lily pads, reeds, a deep hole, rocks, sandy shallows) and which
## fish swim there, the day's fish mix, and whether OLD WHISKERS (deep hole) and the GOLDEN FISH (sandy
## shallows) visit. Some fish only live at one kind of spot (koi under lily pads, pike and eels in the
## reeds, catfish and moonfish in the deep hole, puffers by the rocks), the common fish swim everywhere.
## `wish` is Ollie's wish for the day (a fish for the book, book.gd): a normal lake is shaped so the wish
## can be caught (its weather and its spot); TODAY'S LAKE (daily) is the same for everyone, so the wish
## only counts when that lake happens to have it.
## check(lake) lists what's wrong (empty = fair): every spot reachable by a cast from the jetty end and
## by the boats, spots apart, the wish catchable, every fish in the mix has its spot and its weather.
## Network: the host sends [seed, level, wish, daily]; every machine rebuilds the same lake.

const Seeded := preload("res://core/seeded.gd")
const Lake := preload("res://games/fishing_lake/lake.gd")
const FishScript := preload("res://games/fishing_lake/fish.gd")

const MINNOW := 0
const PERCH := 1
const TROUT := 2
const CATFISH := 3
const PIKE := 4
const GOLDEN := 5
const BLUEGILL := 8
const EEL := 9
const PUFFER := 10
const MOONFISH := 11
const KOI := 12
const LEGEND := 13

## The fishing spots: id, the fish that live there.
const HABITATS: Array[Dictionary] = [
	{"id": "lily", "fish": [BLUEGILL, PERCH, KOI]},
	{"id": "reeds", "fish": [PIKE, PERCH, EEL]},
	{"id": "deep", "fish": [CATFISH, TROUT, MOONFISH, LEGEND]},
	{"id": "rocks", "fish": [TROUT, PUFFER, MINNOW]},
	{"id": "sandy", "fish": [MINNOW, BLUEGILL, GOLDEN]},
]
## Fish that only live at their own kind of spot (the others swim anywhere).
const HOME := {KOI: "lily", PIKE: "reeds", EEL: "reeds", CATFISH: "deep", MOONFISH: "deep", LEGEND: "deep",
	PUFFER: "rocks", GOLDEN: "sandy"}
## Weather each fish needs (missing: any): eels come out in the rain, moonfish under the stars.
const NEEDS := {EEL: "rain", MOONFISH: "evening"}
## The level (days fished) each fish first appears at: a gentle start, then more to find.
const UNLOCK := {MINNOW: 0, PERCH: 0, BLUEGILL: 0, TROUT: 0, CATFISH: 1, PIKE: 1, EEL: 1,
	PUFFER: 2, MOONFISH: 2, LEGEND: 2, KOI: 3, GOLDEN: 3}
const WEATHERS: Array[String] = ["sunny", "rain", "evening"]
## Sky phases per weather (main.gd THEMES order): theme index, p0 / p1 ranges.
const SKY := {"sunny": [0, 0.0, 0.08, 1.0, 1.08], "rain": [1, 0.02, 0.1, 1.0, 1.08], "evening": [2, 0.55, 0.65, 1.5, 1.56]}  # evening: the stars come out a bit past halfway
const SPOT_R := 1.8
const JETTY_END := Vector3(0.0, 0.0, Lake.JETTY_END_Z)
const CAST_MIN := 6.0
const CAST_MAX := 15.0
const CAST_ANGLE := 1.1


static func habitat(id: String) -> Dictionary:
	for h in HABITATS:
		if h.id == id:
			return h
	return HABITATS[0]


static func weathers_for(level: int) -> Array:
	return ["sunny"] if level <= 0 else (["sunny", "rain"] if level == 1 else WEATHERS.duplicate())


static func unlocked(kind: int, level: int) -> bool:
	return UNLOCK.has(kind) and level >= int(UNLOCK[kind])


## All the book's fish, in page order.
static func species() -> Array:
	return [MINNOW, PERCH, BLUEGILL, TROUT, CATFISH, PIKE, EEL, PUFFER, MOONFISH, KOI, GOLDEN, LEGEND]


static func generate(seed_value: int, opts: Dictionary = {}) -> Dictionary:
	var level := clampi(int(opts.get("level", 3)), 0, 3)
	var daily := bool(opts.get("daily", false))
	var want := int(opts.get("wish", -1))
	var shape_for := -1 if daily or not unlocked(want, level) else want
	var r := Seeded.rng(seed_value, "lake")
	# Weather (the wish's weather when it needs one).
	var ws := weathers_for(level)
	var weather: String = ws[Seeded.weighted(r, [3, 2, 2].slice(0, ws.size()))]
	if NEEDS.has(shape_for):
		weather = NEEDS[shape_for]
	var sky: Array = SKY[weather]
	var rain_from := r.randf_range(0.06, 0.25) if weather == "rain" else 2.0
	var rain_to := r.randf_range(0.6, 0.85) if weather == "rain" else 2.0
	# Spots: the wish's home first, then others.
	var n_spots := 2 if level == 0 else (3 if level == 1 else 3 + r.randi() % 2)
	var ids: Array = []
	if HOME.has(shape_for):
		ids.append(HOME[shape_for])
	if weather == "evening" and not ids.has("deep") and r.randf() < 0.6:
		ids.append("deep")  # moonfish nights
	if weather == "rain" and not ids.has("reeds") and r.randf() < 0.6:
		ids.append("reeds")  # eels in the rain
	for h in Seeded.shuffled(r, HABITATS):
		if ids.size() >= n_spots:
			break
		if not ids.has(h.id):
			ids.append(h.id)
	var spots: Array = []
	var slots := _slots(r)
	for id in ids:
		for s in slots:
			var p: Vector3 = s
			if _spot_ok(p, SPOT_R, spots):
				spots.append({"hab": id, "pos": p, "r": SPOT_R, "fish": (habitat(id).fish as Array).duplicate()})
				break
	var has := {}
	for s in spots:
		has[s.hab] = true
	# The day's fish mix (spawn weights).
	var mix := {}
	for k in species():
		if k == LEGEND or k == GOLDEN or not unlocked(k, level):
			continue
		if HOME.has(k) and not has.has(HOME[k]):
			continue
		if NEEDS.has(k) and NEEDS[k] != weather:
			continue
		var w := int(FishScript.TYPES[k]["spawn"])
		if k == shape_for:
			w = maxi(w * 2, 10)
		mix[k] = w
	var legend := unlocked(LEGEND, level) and has.has("deep") and (shape_for == LEGEND or r.randf() < 0.75)
	var golden := unlocked(GOLDEN, level) and has.has("sandy") and (shape_for == GOLDEN or r.randf() < 0.5)
	var lake := {"seed": seed_value, "level": level, "daily": daily, "weather": weather, "theme": int(sky[0]),
		"p0": snappedf(r.randf_range(float(sky[1]), float(sky[2])), 0.001), "p1": snappedf(r.randf_range(float(sky[3]), float(sky[4])), 0.001),
		"rain_from": snappedf(rain_from, 0.001), "rain_to": snappedf(rain_to, 0.001), "spots": spots, "mix": mix,
		"legend": legend, "legend_at": snappedf(r.randf_range(0.45, 0.7), 0.001),
		"golden": golden, "golden_at": snappedf(r.randf_range(0.2, 0.6), 0.001), "wish": -1}
	lake.wish = want if catchable(lake).has(want) else -1
	return lake


## Candidate spot centres (a jittered fan in front of the jetty), shuffled.
static func _slots(r: RandomNumberGenerator) -> Array:
	var out: Array = []
	for a in [-0.85, -0.42, 0.0, 0.42, 0.85]:
		for d in [7.5, 11.0, 14.0]:
			var aa: float = a + r.randf_range(-0.12, 0.12)
			var dd: float = d + r.randf_range(-0.8, 0.6)
			out.append(JETTY_END + Vector3(sin(aa) * dd, 0.0, -cos(aa) * dd))
	return Seeded.shuffled(r, out)


static func _spot_ok(p: Vector3, rad: float, spots: Array) -> bool:
	return reach_problem(p, rad) == "" and not _overlaps(p, rad, spots)


static func _overlaps(p: Vector3, rad: float, spots: Array) -> bool:
	for s in spots:
		var q: Vector3 = s.pos
		if Vector2(p.x - q.x, p.z - q.z).length() < rad + float(s.r) + 1.2:
			return true
	return false


## Why a spot can't be fished ("" = fine): the angler must reach its middle with a cast, the boats must
## fit round it (water all round, clear of the jetty and the two boards).
static func reach_problem(p: Vector3, rad: float) -> String:
	var off := Vector2(p.x - JETTY_END.x, p.z - JETTY_END.z)
	var d := off.length()
	if d < CAST_MIN or d > CAST_MAX:
		return "cast distance %.1f" % d
	if absf(atan2(off.x, -off.y)) > CAST_ANGLE:
		return "behind the angler"
	var lc := Vector2(p.x - Lake.LAKE_C.x, p.z - Lake.LAKE_C.z).length()
	if lc + rad > Lake.LAKE_R - 2.0:
		return "too close to the shore"
	for b in [Lake.BOARD_L, Lake.BOARD_R]:
		var bb: Vector3 = b
		if Vector2(p.x - bb.x, p.z - bb.z).length() < rad + 2.5:
			return "on a board"
	if p.z + rad > Lake.JETTY_END_Z - 1.0:
		return "under the jetty"
	return ""


## The fish that can be caught on this lake (the mix, plus the legend and the golden fish when they visit).
static func catchable(lake: Dictionary) -> Array:
	var out: Array = []
	for k in species():
		if (lake.mix as Dictionary).has(k) and int(lake.mix[k]) > 0:
			out.append(k)
	if bool(lake.legend):
		out.append(LEGEND)
	if bool(lake.golden):
		out.append(GOLDEN)
	return out


## The spots a fish kind lives at (empty: anywhere).
static func spots_for(lake: Dictionary, kind: int) -> Array:
	var out: Array = []
	for s in lake.spots:
		if (s.fish as Array).has(kind):
			out.append(s)
	return out


static func spot_of(lake: Dictionary, hab: String) -> Variant:
	for s in lake.spots:
		if s.hab == hab:
			return s
	return null


static func check(lake: Dictionary) -> Array:
	var why: Array = []
	var spots: Array = lake.spots
	var level := int(lake.level)
	var want := 2 if level == 0 else 3
	if spots.size() < want:
		why.append("only %d spots" % spots.size())
	var seen := {}
	for i in spots.size():
		var s: Dictionary = spots[i]
		var p: Vector3 = s.pos
		var rp := reach_problem(p, float(s.r))
		if rp != "":
			why.append("spot %s: %s" % [s.hab, rp])
		if _overlaps(p, float(s.r), spots.slice(0, i)):
			why.append("spot %s overlaps another" % s.hab)
		if seen.has(s.hab):
			why.append("two %s spots" % s.hab)
		seen[s.hab] = true
	if not weathers_for(level).has(lake.weather):
		why.append("weather %s too early (level %d)" % [lake.weather, level])
	var mix: Dictionary = lake.mix
	if mix.size() < 3:
		why.append("only %d kinds of fish" % mix.size())
	for k in mix:
		if not unlocked(int(k), level):
			why.append("%s too early" % FishScript.TYPES[int(k)].name)
		if HOME.has(k) and spot_of(lake, HOME[k]) == null:
			why.append("%s has no %s spot" % [FishScript.TYPES[int(k)].name, HOME[k]])
		if NEEDS.has(k) and NEEDS[k] != lake.weather:
			why.append("%s needs %s" % [FishScript.TYPES[int(k)].name, NEEDS[k]])
	if bool(lake.legend) and spot_of(lake, "deep") == null:
		why.append("the legend has no deep hole")
	if bool(lake.golden) and spot_of(lake, "sandy") == null:
		why.append("the golden fish has no shallows")
	if int(lake.wish) >= 0 and not catchable(lake).has(int(lake.wish)):
		why.append("the wish %d can't be caught" % int(lake.wish))
	if lake.weather == "rain" and not (float(lake.rain_from) < float(lake.rain_to) - 0.3):
		why.append("too little rain")
	return why
