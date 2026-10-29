extends RefCounted
## TINY TOWN TYCOON wishes and story (host / local): the townsfolk ask for things with PICTURE BUBBLES.
## A HOUSE WISH floats over a house ("a park near me!"): a building of that kind with its middle within
## NEAR cells of the house grants it. A LAND WISH floats over a resource (islandgen.gd): a farm on or
## beside the golden field, a water tower by the spring, a windmill on the breezy hilltop, a sawmill by
## the deep woods. A wish is only ever made when wishes.gd can see a free spot for it that a road can
## reach (town.near_spot / res_spot), so no wish is ever impossible (tests/tiny_town_tycoon_gen_test.gd
## plays many towns through self_play() to prove it). Granted wishes add up (saved with the town) and
## lift the MIST off the island's districts one by one (OPEN_AT), each with its LANDMARK blueprint.
## BENNY the beaver, the island's builder, tells the story with picture cards (LINES).
## TODAY'S ISLAND: today_seed() gives the same island on every machine all day.

const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const IslandGen := preload("res://games/tiny_town_tycoon/islandgen.gd")
const Seeded := preload("res://core/seeded.gd")
const Town := preload("res://games/tiny_town_tycoon/town.gd")

const GAME_ID := "tiny_town_tycoon"
const NEAR := 3.6  ## a house wish: the building's middle within this many cells of the house
const MAX_OPEN := 2  ## wishes at once (3 in a town of 12+ houses)
const FIRST_WAIT := 20.0  ## seconds before the first wish
const GAP := 22.0  ## seconds between wishes
## Granted wishes needed to open district k (k = 1..3).
const OPEN_AT: Array[int] = [0, 3, 7, 12]
## What houses wish for (picked among the unlocked tray kinds).
const HOUSE_WANTS: Array[String] = ["house", "park", "shop", "bakery", "school", "fire_station", "farm", "windmill", "water"]

const WHO := "BENNY"
const WHO_PIC := "beaver"
const WHO_COLOR := Color(0.75, 0.5, 0.3)
const LINES := {
	"hello": ["Hi Mayor! I'm Benny!", "pic"],
	"back": ["Welcome back, Mayor!", "pic"],
	"today": ["TODAY'S ISLAND!", "island"],
	"home": ["Home sweet home!", "house"],
	"wish": ["A wish came true!", "heart"],
	"mist": ["The mist is lifting!", "cloud"],
	"landmark": ["A new landmark!", "star"],
	"all_open": ["The whole island is ours!", "crown"],
}
const PICTURES_USED: Array[String] = ["beaver", "island", "house", "heart", "cloud", "star", "crown", "boat"]

var town: Town
var list: Array = []  ## [{id, kind, x, z, home (house id, 0 = a land wish), res}]
var done := 0  ## wishes granted in this town (saved)
var next_id := 1
var rng: RandomNumberGenerator
## Times in a row no wish could be made (the open land is full): main.gd lifts the next mist at 2,
## so the island never stops growing.
var dry := 0
var _t := FIRST_WAIT


func setup(t: Town, p_done: int, seed_value: int) -> void:
	town = t
	done = p_done
	list.clear()
	rng = Seeded.rng(seed_value + done * 977, "wishes")
	_t = FIRST_WAIT


## TODAY'S ISLAND's seed (the same everywhere all day).
static func today_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


## The district count `done` wishes have opened (bit mask, the middle always open).
static func open_for(n: int) -> int:
	var m := 1
	for k in range(1, OPEN_AT.size()):
		if n >= OPEN_AT[k]:
			m |= 1 << k
	return m


## The bit of the next district still under the mist (0 when all are open).
static func next_open(mask: int) -> int:
	for k in range(1, OPEN_AT.size()):
		if (mask >> k) & 1 == 0:
			return 1 << k
	return 0


## Seconds pass: maybe a new wish (returns it, or {}). `kinds`: what the mayor's tray has.
func tick(dt: float, kinds: Array) -> Dictionary:
	_t -= dt
	_drop_stale()
	var houses := town.of_kind("house")
	var cap := MAX_OPEN + (1 if houses.size() >= 12 else 0)
	if _t > 0.0 or list.size() >= cap:
		return {}
	_t = GAP
	var w := make(kinds)
	if not w.is_empty():
		list.append(w)
		dry = 0
	elif list.is_empty() and town_full():
		dry += 1
	return w


## No room left for houses where the roads can reach (the open land is full): time to lift a mist.
func town_full() -> bool:
	var spots := 0
	for z in Defs.GRID:
		for x in Defs.GRID:
			if town.can_place("house", x, z) == "" and town.reach(Vector2i(x, z), 1):
				spots += 1
				if spots >= 4:
					return false
	return true


## A new wish the mayor can grant (or {} when there's nothing sensible to wish for).
func make(kinds: Array) -> Dictionary:
	var options: Array = []
	# land wishes: a resource whose building is unlocked, not already used, not already wished for
	for i in town.res.size():
		var rk := int(town.res[i])
		if rk == 0:
			continue
		var kind := String(IslandGen.RES_KIND.get(rk, ""))
		var c := Vector2i(i % Defs.GRID, i / Defs.GRID)
		if not kinds.has(kind) or not town.is_open(c.x, c.y) or _res_used(c, kind) or _wished_at(c):
			continue
		if town.res_spot(kind, c).x >= 0:
			options.append({"kind": kind, "x": c.x, "z": c.y, "home": 0, "res": rk, "w": 3.0})
	# house wishes: a few built houses without a wish (in a seeded order), each for one thing it lacks
	var asked := 0
	for h in Seeded.shuffled(rng, town.of_kind("house")):
		if asked >= 4:
			break
		if _wished_by(int(h["id"])):
			continue
		var hc := Vector2i(int(h["x"]), int(h["z"]))
		for kind2 in Seeded.shuffled(rng, HOUSE_WANTS):
			if not kinds.has(kind2) or _has_near(String(kind2), hc):
				continue
			if town.near_spot(String(kind2), hc, NEAR).x >= 0:
				options.append({"kind": String(kind2), "x": hc.x, "z": hc.y, "home": int(h["id"]), "res": 0, "w": 1.0 if kind2 == "house" else 2.0})
				asked += 1
				break
	if options.is_empty():
		return {}
	var ws: Array = []
	for o in options:
		ws.append(float(o["w"]))
	var pick: Dictionary = options[Seeded.weighted(rng, ws)]
	pick.erase("w")
	pick["id"] = next_id
	next_id += 1
	return pick


## A building went down at b: the wishes it grants (removed from the list).
func granted_by(b: Dictionary) -> Array:
	var out: Array = []
	var kind := String(b["kind"])
	var s := Defs.size_of(kind)
	for w in list.duplicate():
		if String(w["kind"]) != kind:
			continue
		var ok := false
		if int(w["home"]) == 0:
			ok = town.touches(int(b["x"]), int(b["z"]), s, Vector2i(int(w["x"]), int(w["z"])))
		else:
			var mid := Vector2(int(b["x"]) + s * 0.5, int(b["z"]) + s * 0.5)
			ok = mid.distance_to(Vector2(int(w["x"]) + 0.5, int(w["z"]) + 0.5)) <= NEAR + 0.01
		if ok:
			list.erase(w)
			out.append(w)
			done += 1
	return out


## The spot the game would suggest for a wish ((-1, -1) when none: the wish is dropped).
func spot_for(w: Dictionary) -> Vector2i:
	var c := Vector2i(int(w["x"]), int(w["z"]))
	if int(w["home"]) == 0:
		return town.res_spot(String(w["kind"]), c)
	return town.near_spot(String(w["kind"]), c, NEAR)


## Compact form for the net store: [id, kind index, x, z, home].
func packed() -> Array:
	var out: Array = []
	for w in list:
		out.append([int(w["id"]), Defs.kind_index(String(w["kind"])), int(w["x"]), int(w["z"]), int(w["home"])])
	return out


func _drop_stale() -> void:
	for w in list.duplicate():
		var gone := int(w["home"]) > 0 and not town.buildings.has(int(w["home"]))
		if gone or spot_for(w).x < 0:
			list.erase(w)


func _res_used(c: Vector2i, kind: String) -> bool:
	for b in town.of_kind(kind, true):
		if town.touches(int(b["x"]), int(b["z"]), Defs.size_of(kind), c):
			return true
	return false


func _wished_at(c: Vector2i) -> bool:
	for w in list:
		if int(w["home"]) == 0 and int(w["x"]) == c.x and int(w["z"]) == c.y:
			return true
	return false


func _wished_by(id: int) -> bool:
	for w in list:
		if int(w["home"]) == id:
			return true
	return false


func _has_near(kind: String, hc: Vector2i) -> bool:
	for b in town.of_kind(kind, true):
		var s := Defs.size_of(kind)
		if Vector2(int(b["x"]) + s * 0.5, int(b["z"]) + s * 0.5).distance_to(Vector2(hc.x + 0.5, hc.y + 0.5)) <= NEAR + 0.01:
			return true
	return false


# --- The proof (tests) --------------------------------------------------------------------------------

## A greedy little mayor plays a town on `isl` through `rounds` wishes the way the game does: houses along
## the roads, each wish granted at its suggested spot with a road laid to it, districts opened at OPEN_AT.
## Returns {granted, land, kinds, open, problems}.
static func self_play(isl: Dictionary, rounds: int, seed_value: int) -> Dictionary:
	var t := Town.new()
	t.apply_island(isl)
	t.starter_town()
	var w: RefCounted = new()
	w.setup(t, 0, seed_value)
	var problems: Array = []
	var land := 0
	var kinds := {}
	var unl := 2
	for round_i in rounds:
		# the town grows a little between wishes: a house by a road (or a short road on from the street)
		_grow(t, 2)
		unl = Defs.simple_unlocked(t.buildings.size() - 1)
		var tray: Array = Defs.simple_tray(unl, false)
		var made: Dictionary = w.make(tray)
		if made.is_empty():
			if w.town_full():
				w.dry += 1
			if w.dry >= 2:
				w.dry = 0
				t.open_mask |= next_open(t.open_mask)
				t.version += 1
			continue
		w.dry = 0
		w.list.append(made)
		var spot: Vector2i = w.spot_for(made)
		if spot.x < 0:
			problems.append("wish %d (%s) has no spot the moment it's made" % [round_i, String(made["kind"])])
			w.list.erase(made)
			continue
		var kind := String(made["kind"])
		if not _road_to(t, spot, Defs.size_of(kind)):
			problems.append("wish %d (%s at %d,%d): no road can reach %s" % [round_i, kind, int(made["x"]), int(made["z"]), str(spot)])
			w.list.erase(made)
			continue
		if t.can_place(kind, spot.x, spot.y) != "":
			problems.append("wish %d: the road blocked the spot" % round_i)
			w.list.erase(made)
			continue
		var id: int = t.add_building(kind, spot.x, spot.y, t.auto_rot(kind, spot.x, spot.y), 1)
		var got: Array = w.granted_by(t.buildings[id])
		if got.is_empty():
			problems.append("wish %d (%s): building at the suggested spot didn't grant it" % [round_i, kind])
			w.list.erase(made)
			continue
		land += 1 if int(made["home"]) == 0 else 0
		kinds[kind] = true
		t.open_mask |= open_for(w.done)
		t.version += 1
	return {"granted": w.done, "land": land, "kinds": kinds.keys(), "open": t.open_mask & 15, "problems": problems}


## Lay a road from the town's roads to a cell beside the footprint (BFS over open land); true if done.
static func _road_to(t: Town, c: Vector2i, s: int) -> bool:
	if t.on_road({"kind": "house" if s == 1 else "farm", "x": c.x, "z": c.y}):
		return true
	var goals := {}
	for g in t.ring_at(c.x, c.y, s):
		goals[g] = true
	var prev := {}
	var q: Array[Vector2i] = []
	for z in Defs.GRID:
		for x in Defs.GRID:
			if t.has_road(x, z):
				prev[Vector2i(x, z)] = Vector2i(x, z)
				q.append(Vector2i(x, z))
	var head := 0
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		if goals.has(cur) and not t.has_road(cur.x, cur.y):
			var p := cur
			while not t.has_road(p.x, p.y):
				t.set_layer(p.x, p.y, Defs.L_ROAD)
				p = prev[p]
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if prev.has(n) or t.can_place("road", n.x, n.y) != "":
				continue
			# never pave the wished spot itself
			if n.x >= c.x and n.x < c.x + s and n.y >= c.y and n.y < c.y + s:
				continue
			prev[n] = cur
			q.append(n)
	return false


## A few houses beside the roads (a road on from the street when there's no room).
static func _grow(t: Town, n: int) -> void:
	for k in n:
		var best := Vector2i(-1, -1)
		var bd := INF
		for z in Defs.GRID:
			for x in Defs.GRID:
				if t.can_place("house", x, z) != "" or not t.on_road({"kind": "house", "x": x, "z": z}):
					continue
				var d := Vector2(x, z).distance_to(Vector2(11, 11))
				if d < bd:
					bd = d
					best = Vector2i(x, z)
		if best.x >= 0:
			t.add_building("house", best.x, best.y, t.auto_rot("house", best.x, best.y), 1)
		else:
			# extend a road outwards by one cell
			for z2 in Defs.GRID:
				for x2 in Defs.GRID:
					if t.has_road(x2, z2):
						for d2 in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
							var c2: Vector2i = Vector2i(x2, z2) + d2
							if t.can_place("road", c2.x, c2.y) == "" and not t.has_road(c2.x, c2.y):
								t.set_layer(c2.x, c2.y, Defs.L_ROAD)
								return


## Story rules (tests).
static func self_check() -> Array:
	var why: Array = []
	for k in LINES:
		var l: Array = LINES[k]
		if String(l[0]).length() > 28:
			why.append("line %s is too long for a card" % k)
	for k in range(1, OPEN_AT.size()):
		if OPEN_AT[k] <= OPEN_AT[k - 1]:
			why.append("districts open in order")
	if open_for(0) != 1 or open_for(OPEN_AT[OPEN_AT.size() - 1]) != (1 << OPEN_AT.size()) - 1:
		why.append("open_for: middle only at first, everything at the end")
	return why
