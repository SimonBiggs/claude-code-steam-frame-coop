extends RefCounted
## PARTY BOARD parties from a seed (SIMPLE_MODE board): every party on Party Island is laid out fresh -
## which spaces are red (slide back) and which blue (bonus hops), where the STAR sits first and the
## whole route it flies along after each pick-up, which minigame comes after each round, and the party's
## THEME (Mango's beach / candy / volcano / lagoon party: the sky and the music). Rising: the more
## parties the family has had (level = festival pieces built), the more red spaces (never two in a row).
## Same (seed, spec) -> same party on every machine: the host sends {seed, level, rounds, daily} and the
## TV machines rebuild it. check() is the validator (tests/party_board_gen_test.gd runs it over many seeds).
## Pure data on a board_data.gd graph (no nodes). Generation is a few hundred tiny steps.

const Seeded := preload("res://core/seeded.gd")

const SIMPLE_GAMES: Array[String] = ["coin_catch", "kart_dash", "balloon_pop"]  ## mg_runner.gd SIMPLE_GAMES
const RED_MIN := 3
const RED_MAX := 9
const STAR_GAP := 5  ## the STAR flies at least this many hops away (both ways round)
const FIRST_STAR := Vector2i(4, 8)  ## the first STAR sits this many hops from START
const ROUTE_LEN := 24
## Party themes: Mango's party for this seed (sky preset, music mood, story picture, Mango's line).
const THEMES: Array[Dictionary] = [
	{"id": "beach", "name": "BEACH PARTY", "sky": "day", "music": "party", "pic": "wave", "line": "Beach party!"},
	{"id": "candy", "name": "CANDY PARTY", "sky": "day", "music": "party", "pic": "heart", "line": "Candy party!"},
	{"id": "volcano", "name": "VOLCANO PARTY", "sky": "sunset", "music": "tension", "pic": "sun", "line": "Volcano party!"},
	{"id": "lagoon", "name": "LAGOON PARTY", "sky": "day", "music": "party", "pic": "wave", "line": "Splash party!"},
	{"id": "lantern", "name": "LANTERN PARTY", "sky": "sunset", "music": "town", "pic": "star", "line": "Lantern party!"},
]


## data: a board_data.gd made simple (make_simple()). spec: {level, rounds, daily}.
## Returns {seed, level, rounds, types: [type per space], reds, route: [star space ids], minigames: [one
## id per round], theme: index into THEMES}.
static func generate(data, seed_value: int, spec: Dictionary) -> Dictionary:
	var level := maxi(0, int(spec.get("level", 0)))
	var rounds := clampi(int(spec.get("rounds", 4)), 1, 12)
	var r := Seeded.rng(seed_value, "board")
	var n: int = data.count()
	var dist := dists(data)
	var types: Array = []
	for i in n:
		var t: String = data.type_of(i)
		types.append("start" if t == "start" else "blue")
	# Red spaces: never on START, a junction or right after START, never two in a row on any path.
	var want := clampi(RED_MIN + level, RED_MIN, RED_MAX)
	var cand: Array = []
	for i in n:
		if types[i] == "start" or data.is_junction(i) or dist[0][i] < 3:
			continue
		cand.append(i)
	cand = Seeded.shuffled(r, cand)
	var reds := 0
	for i in cand:
		if reds >= want:
			break
		var near := false
		for j in data.next_of(i) + data.prev_of(i):
			near = near or types[int(j)] == "red"
		if near:
			continue
		types[i] = "red"
		reds += 1
	# The STAR's route: blue, not a junction; the first one a short walk from START; then always far away,
	# and somewhere else on the island (another zone) when it can be.
	var spots: Array = []
	for i in n:
		if types[i] == "blue" and not data.is_junction(i):
			spots.append(i)
	var sr := Seeded.rng(seed_value, "star")
	var first: Array = spots.filter(func(s: int) -> bool:
		var d: int = dist[0][s]
		return d >= FIRST_STAR.x and d <= FIRST_STAR.y)
	var route: Array = [int(Seeded.pick(sr, first if not first.is_empty() else spots))]
	while route.size() < ROUTE_LEN:
		var cur: int = route[-1]
		var zone := String(data.spaces[cur]["zone"])
		var far: Array = spots.filter(func(s: int) -> bool:
			return s != cur and dist[cur][s] >= STAR_GAP and dist[s][cur] >= STAR_GAP)
		var other: Array = far.filter(func(s: int) -> bool: return String(data.spaces[s]["zone"]) != zone)
		var pool: Array = other if not other.is_empty() else (far if not far.is_empty() else spots)
		route.append(int(Seeded.pick(sr, pool)))
	# Minigames: every simple one once before any comes again, never the same twice in a row.
	var mr := Seeded.rng(seed_value, "minigames")
	var games: Array = []
	var bag: Array = []
	for k in rounds:
		if bag.is_empty():
			bag = Seeded.shuffled(mr, SIMPLE_GAMES)
			if not games.is_empty() and bag[0] == games[-1]:
				bag.append(bag.pop_front())
		games.append(bag.pop_front())
	var theme := Seeded.rng(seed_value, "theme").randi() % THEMES.size()
	return {"seed": seed_value, "level": level, "rounds": rounds, "types": types, "reds": reds, "route": route,
		"minigames": games, "theme": theme}


## Hops from every space to every other (following the arrows; 999 = can't get there): one walk per space.
static func dists(data) -> Array:
	var n: int = data.count()
	var out: Array = []
	for a in n:
		var row := PackedInt32Array()
		row.resize(n)
		row.fill(999)
		row[a] = 0
		var q: Array[int] = [a]
		var qi := 0
		while qi < q.size():
			var c: int = q[qi]
			qi += 1
			for nx in data.next_of(c):
				var b := int(nx)
				if row[b] == 999:
					row[b] = row[c] + 1
					q.append(b)
		out.append(row)
	return out


## The validator: reasons this party is unfair or broken (empty when fine).
static func check(data, p: Dictionary) -> Array:
	var why: Array = []
	var types: Array = p.get("types", [])
	var n: int = data.count()
	if types.size() != n:
		return ["%d types for %d spaces" % [types.size(), n]]
	var reds := 0
	for i in n:
		var t := String(types[i])
		if not t in ["blue", "red", "start"]:
			why.append("space %d is %s" % [i, t])
		if (t == "start") != (data.type_of(i) == "start"):
			why.append("START moved (space %d)" % i)
		if t == "red":
			reds += 1
			if data.is_junction(i):
				why.append("a red junction %d" % i)
			if data.distance(0, i) < 3:
				why.append("a red space %d right after START" % i)
			for j in data.next_of(i):
				if String(types[int(j)]) == "red":
					why.append("two reds in a row (%d, %d)" % [i, int(j)])
	var want := clampi(RED_MIN + int(p.get("level", 0)), RED_MIN, RED_MAX)
	if reds < mini(want, RED_MIN) or reds > want:
		why.append("%d reds (want %d)" % [reds, want])
	if reds * 3 > n:
		why.append("too many reds (%d of %d)" % [reds, n])
	var route: Array = p.get("route", [])
	if route.size() != ROUTE_LEN:
		why.append("star route of %d" % route.size())
	for k in route.size():
		var s := int(route[k])
		if s < 0 or s >= n or String(types[s]) != "blue" or data.is_junction(s):
			why.append("the STAR on space %d (%s)" % [s, String(types[s]) if s >= 0 and s < n else "?"])
			continue
		if k == 0:
			var d: int = data.distance(0, s)
			if d < FIRST_STAR.x or d > FIRST_STAR.y:
				why.append("the first STAR is %d hops from START" % d)
		else:
			var prev := int(route[k - 1])
			if data.distance(prev, s) < STAR_GAP or data.distance(s, prev) < STAR_GAP:
				why.append("the STAR only flew %d hops (%d -> %d)" % [data.distance(prev, s), prev, s])
	var games: Array = p.get("minigames", [])
	if games.size() != int(p.get("rounds", 0)):
		why.append("%d minigames for %d rounds" % [games.size(), int(p.get("rounds", 0))])
	for k in games.size():
		if not SIMPLE_GAMES.has(String(games[k])):
			why.append("minigame %s isn't simple" % String(games[k]))
		if k > 0 and games[k] == games[k - 1]:
			why.append("%s twice in a row" % String(games[k]))
	if games.size() >= SIMPLE_GAMES.size():
		for g in SIMPLE_GAMES:
			if not games.has(g):
				why.append("%s never comes" % g)
	var th := int(p.get("theme", -1))
	if th < 0 or th >= THEMES.size():
		why.append("bad theme %d" % th)
	return why
