extends RefCounted
## PARTY BOARD parties from a seed (SIMPLE_MODE board): every party is a fresh board -
##   - the LAYOUT (layout()): how many spaces the coast road has, how it wiggles, and which shortcuts exist
##     (the volcano trail, the lagoon pier or both; where they start and end and how long they are);
##   - the BOARD it is dressed as (boards.gd: PARTY ISLAND, SWEET SHOP, PIRATE COVE, HAUNTED HOUSE, SPACE
##     STATION) with that board's SPECIAL spaces (volcano / candy / cannon / ghost / warp pads) and PRESENT
##     spaces (an item);
##   - which spaces are red (slide back) and which blue (bonus hops), where the STAR sits first and the whole
##     route it flies along after each pick-up, which minigame comes after each round, and in which round the
##     board's EVENT happens (once per party).
## Rising: the more parties the family has had (level), the more red spaces (never two in a row).
## Party Board is the strictest SIMPLE_MODE game: story lines are UPPERCASE and at most two words.
## Same (seed, spec) -> same party on every machine: the host sends {seed, level, rounds, daily, board} and
## the TV machines rebuild it. check() is the validator (tests/party_board_gen_test.gd runs it over many seeds):
## the board is fully connected (START reaches every space and every space leads back to START), no tiles
## overlap or sit on the volcano, the specials and presents are where they work, and the party is fair.
## Pure data on a board_data.gd graph (no nodes). Generation is a few hundred tiny steps.

const Seeded := preload("res://core/seeded.gd")
const Boards := preload("res://games/party_board/boards.gd")
const BD := preload("res://games/party_board/board_data.gd")

## mg_runner.gd SIMPLE_GAMES (one motion or one button each; tests/party_board_mg_test.gd proves them fair).
const SIMPLE_GAMES: Array[String] = ["coin_catch", "kart_dash", "balloon_pop", "mole_bop", "paint_splash", "fish_pond",
	"treasure_dive", "star_stack"]
const RED_MIN := 3
const RED_MAX := 9
const STAR_GAP := 5  ## the STAR flies at least this many hops away (both ways round)
const FIRST_STAR := Vector2i(4, 8)  ## the first STAR sits this many hops from START
const ROUTE_LEN := 24
const RING_SIZES := [24, 26, 28, 30]
const MIN_GAP := 1.75  ## board units between space centres (a tile is 1.8 across: they may just touch)
const MAX_HILL := 1.6  ## no space higher up the volcano than this
## Shortcut guides (board units): the volcano trail across the volcano's south foot, the pier over the lagoon.
const TRAIL_GUIDE: Array[Vector2] = [Vector2(4.6, 0.3), Vector2(1.5, 0.85), Vector2(-1.5, 0.85), Vector2(-4.5, 0.3)]
const PIER_GUIDE: Array[Vector2] = [Vector2(-3.5, 4.55), Vector2(-0.3, 4.75), Vector2(2.9, 4.7)]
const SPECIAL_COUNT := {"volcano": 2, "candy": 2, "cannon": 2, "ghost": 2, "warp": 3}
const WARP_GAP := 6  ## warp pads at least this many hops apart (both ways)


## The board's layout from a seed (board_data.gd build_layout): ring size, wiggle and shortcuts.
static func layout(seed_value: int) -> Dictionary:
	var r := Seeded.rng(seed_value, "layout")
	var n: int = RING_SIZES[r.randi() % RING_SIZES.size()]
	var amp := snappedf(r.randf_range(0.15, 0.45), 0.01)
	var wob := [amp, snappedf(r.randf_range(0.0, TAU), 0.01), 9.85 - amp]  # never out to the festival pieces
	var pick := r.randf()
	var want_trail := pick < 0.75
	var want_pier := pick >= 0.25
	var lay := {"ring": n, "wob": wob, "trail": [], "pier": []}
	if want_trail:
		lay["trail"] = _shortcut(r, n, wob, roundi(n * 0.25), roundi(n * 0.75), TRAIL_GUIDE, Vector2i(5, 7), [])
	if want_pier:
		var avoid: Array = (lay["trail"] as Array)[2] if not (lay["trail"] as Array).is_empty() else []
		lay["pier"] = _shortcut(r, n, wob, roundi(n * 0.82), roundi(n * 0.11), PIER_GUIDE, Vector2i(4, 6), avoid)
	if (lay["trail"] as Array).is_empty() and (lay["pier"] as Array).is_empty():
		lay["trail"] = _shortcut(r, n, wob, roundi(n * 0.25), roundi(n * 0.75), TRAIL_GUIDE, Vector2i(5, 7), [])
	return lay


## One shortcut [from ring id, to ring id, points]: spaces spread evenly along a smooth line from the ring
## through the guide points. A few tries with different lengths and wiggles; [] when none fits.
static func _shortcut(r: RandomNumberGenerator, n: int, wob: Array, from0: int, to0: int, guide: Array[Vector2],
		count: Vector2i, avoid: Array) -> Array:
	for attempt in 8:
		var from := posmod(from0 + r.randi_range(-1, 1), n)
		var to := posmod(to0 + r.randi_range(-1, 1), n)
		var k := r.randi_range(count.x, count.y)
		var line: Array[Vector2] = [BD.ring_point(from, n, wob)]
		for g in guide:
			line.append(g + Vector2(r.randf_range(-0.35, 0.35), r.randf_range(-0.3, 0.3)))
		line.append(BD.ring_point(to, n, wob))
		var pts := _spread(line, k)
		if _fits(pts, n, wob, avoid):
			return [from, to, pts]
	return []


## k points spread evenly (by length) along a smooth line through `line`, leaving out both ends.
static func _spread(line: Array[Vector2], k: int) -> Array:
	var dense: Array[Vector2] = []
	for i in line.size() - 1:
		var p0: Vector2 = line[maxi(i - 1, 0)]
		var p1: Vector2 = line[i]
		var p2: Vector2 = line[i + 1]
		var p3: Vector2 = line[mini(i + 2, line.size() - 1)]
		for s in 12:
			var t := float(s) / 12.0
			dense.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	dense.append(line[-1])
	var lens := PackedFloat32Array([0.0])
	for i in range(1, dense.size()):
		lens.append(lens[i - 1] + dense[i].distance_to(dense[i - 1]))
	var total := lens[-1]
	var out: Array = []
	var j := 0
	for s in k:
		var want := total * float(s + 1) / float(k + 1)
		while j < dense.size() - 2 and lens[j + 1] < want:
			j += 1
		var f := (want - lens[j]) / maxf(0.0001, lens[j + 1] - lens[j])
		var q := dense[j].lerp(dense[j + 1], f)
		out.append(Vector2(snappedf(q.x, 0.01), snappedf(q.y, 0.01)))
	return out


static func _fits(pts: Array, n: int, wob: Array, avoid: Array) -> bool:
	var others: Array = avoid.duplicate()
	for i in n:
		others.append(BD.ring_point(i, n, wob))
	for i in pts.size():
		var p: Vector2 = pts[i]
		if BD.height(p.x, p.y) > MAX_HILL:
			return false
		if i > 0 and p.distance_to(pts[i - 1]) < MIN_GAP:
			return false
		for q in others:
			if p.distance_to(q) < MIN_GAP:
				return false
	return true


## The board a seed visits when the spec doesn't say (tests): any board.
static func board_for(seed_value: int) -> String:
	return Boards.ids()[Seeded.rng(seed_value, "board_pick").randi() % Boards.BOARDS.size()]


## data: a board_data.gd (made simple: make_simple()); it is REBUILT with this party's layout. spec: {level,
## rounds, daily, board}. Returns {seed, level, rounds, board, layout, types: [type per space], reds, gifts,
## specials: [ids], warps: [warp pad ids in order], route: [star space ids], minigames: [one per round],
## event_round (0 = none)}.
static func generate(data, seed_value: int, spec: Dictionary) -> Dictionary:
	var level := maxi(0, int(spec.get("level", 0)))
	var rounds := clampi(int(spec.get("rounds", 4)), 1, 12)
	var bid := String(spec.get("board", ""))
	if not Boards.ids().has(bid):
		bid = board_for(seed_value)
	var bd: Dictionary = Boards.board(bid)
	var special := String(bd.special)
	var lay := layout(seed_value)
	data.build_layout(lay)
	data.make_simple()
	var r := Seeded.rng(seed_value, "board")
	var n: int = data.count()
	var dist := dists(data)
	var types: Array = []
	for i in n:
		types.append("start" if i == 0 else "blue")
	var free := func(i: int) -> bool:
		if types[i] != "blue" or data.is_junction(i) or dist[0][i] < 3:
			return false
		for j in data.next_of(i) + data.prev_of(i):
			if types[int(j)] != "blue" and types[int(j)] != "start":
				return false
		return true
	# The board's special spaces (warp pads far apart), then the presents, then the reds.
	var specials: Array = []
	var cand: Array = Seeded.shuffled(r, range(n))
	var want_sp: int = SPECIAL_COUNT.get(special, 2)
	for i in cand:
		if specials.size() >= want_sp:
			break
		if not free.call(i):
			continue
		var far := true
		for s in specials:
			if special == "warp" and (dist[s][i] < WARP_GAP or dist[i][s] < WARP_GAP):
				far = false
			elif dist[s][i] < 4 and dist[i][s] < 4:
				far = false
		if far:
			types[i] = special
			specials.append(i)
	var warps: Array = []
	if special == "warp":
		warps = specials.duplicate()
		warps.sort()
	var gifts: Array = []
	var want_gifts := 3 if n >= 38 else 2
	cand = Seeded.shuffled(r, range(n))
	for i in cand:
		if gifts.size() >= want_gifts:
			break
		if free.call(i):
			types[i] = "gift"
			gifts.append(i)
	var want := clampi(RED_MIN + level, RED_MIN, RED_MAX)
	cand = Seeded.shuffled(r, range(n))
	var reds := 0
	for i in cand:
		if reds >= want:
			break
		if free.call(i):
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
		var far2: Array = spots.filter(func(s: int) -> bool:
			return s != cur and dist[cur][s] >= STAR_GAP and dist[s][cur] >= STAR_GAP)
		var other: Array = far2.filter(func(s: int) -> bool: return String(data.spaces[s]["zone"]) != zone)
		var pool: Array = other if not other.is_empty() else (far2 if not far2.is_empty() else spots)
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
	var ev := 0
	if rounds >= 2:
		ev = Seeded.rng(seed_value, "event").randi_range(2, rounds)
	return {"seed": seed_value, "level": level, "rounds": rounds, "board": bid, "layout": lay, "types": types,
		"reds": reds, "gifts": gifts, "specials": specials, "warps": warps, "route": route, "minigames": games,
		"event_round": ev}


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


## Where a CANNON space blasts you: CANNON_HOPS spaces on along the coast road (the first arrow each time).
static func cannon_target(data, from: int) -> int:
	var at := from
	for k in Boards.CANNON_HOPS:
		at = int(data.next_of(at)[0])
	return at


## Where a WARP pad sends you: the next pad in the party's list (round and round).
static func warp_target(warps: Array, from: int) -> int:
	var i := warps.find(from)
	if i < 0 or warps.size() < 2:
		return from
	return int(warps[(i + 1) % warps.size()])


## Spaces a few hops ahead of `from` (gap.x..gap.y) where the STAR / a chest may land: blue, not a junction.
static func ahead_spots(data, from: int, gap: Vector2i) -> Array:
	var out: Array = []
	var seen := {from: 0}
	var q: Array = [from]
	while not q.is_empty():
		var c: int = q.pop_front()
		var d: int = seen[c]
		if d >= gap.x and data.type_of(c) == "blue" and not data.is_junction(c):
			out.append(c)
		if d >= gap.y:
			continue
		for nx in data.next_of(c):
			if not seen.has(int(nx)):
				seen[int(nx)] = d + 1
				q.append(int(nx))
	return out


## The validator: reasons this party is unfair or broken (empty when fine). `data` must hold the party's
## layout (generate() builds it).
static func check(data, p: Dictionary) -> Array:
	var why: Array = []
	why.append_array(check_board(data))
	var types: Array = p.get("types", [])
	var n: int = data.count()
	if types.size() != n:
		return why + ["%d types for %d spaces" % [types.size(), n]]
	var bid := String(p.get("board", ""))
	if not Boards.ids().has(bid):
		return why + ["no board %s" % bid]
	var special := String(Boards.board(bid).special)
	var reds := 0
	var gifts := 0
	var sp: Array = []
	var others := ["blue", "red", "start", "gift", special]
	for i in n:
		var t := String(types[i])
		if not t in others:
			why.append("space %d is %s on %s" % [i, t, bid])
		if (t == "start") != (i == 0):
			why.append("START moved (space %d)" % i)
		if t == "start" or t == "blue":
			continue
		if data.is_junction(i):
			why.append("a %s junction %d" % [t, i])
		if data.distance(0, i) < 3:
			why.append("a %s space %d right after START" % [t, i])
		for j in data.next_of(i):
			if String(types[int(j)]) != "blue" and String(types[int(j)]) != "start":
				why.append("%s then %s in a row (%d, %d)" % [t, String(types[int(j)]), i, int(j)])
		match t:
			"red":
				reds += 1
			"gift":
				gifts += 1
			_:
				sp.append(i)
	var want := clampi(RED_MIN + int(p.get("level", 0)), RED_MIN, RED_MAX)
	if reds < mini(want, RED_MIN) or reds > want:
		why.append("%d reds (want %d)" % [reds, want])
	if reds * 3 > n:
		why.append("too many reds (%d of %d)" % [reds, n])
	if gifts < 2:
		why.append("only %d presents" % gifts)
	var want_sp: int = SPECIAL_COUNT.get(special, 2)
	if sp.size() < 2 or sp.size() > want_sp:
		why.append("%d %s spaces" % [sp.size(), special])
	if special == "warp":
		var warps: Array = p.get("warps", [])
		if warps.size() < 2 or warps.size() != sp.size():
			why.append("warps %s for pads %s" % [str(warps), str(sp)])
		for w in warps:
			if String(types[int(w)]) != "warp":
				why.append("warp %d isn't a pad" % int(w))
			var to := warp_target(warps, int(w))
			if to == int(w) or data.distance(int(w), to) < WARP_GAP or data.distance(to, int(w)) < WARP_GAP:
				why.append("warp %d -> %d is too close" % [int(w), to])
	if special == "cannon":
		for c in sp:
			var to2 := cannon_target(data, int(c))
			if to2 == int(c) or data.distance(int(c), to2) > Boards.CANNON_HOPS:
				why.append("cannon %d lands on %d" % [int(c), to2])
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
	# Every special space that moves the STAR / a chest has somewhere to put it.
	if special == "volcano":
		for v in sp:
			if ahead_spots(data, int(v), Boards.VOLCANO_STAR).is_empty():
				why.append("volcano %d has nowhere for the STAR" % int(v))
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
	var ev := int(p.get("event_round", -1))
	var rounds := int(p.get("rounds", 0))
	if (rounds >= 2 and (ev < 2 or ev > rounds)) or (rounds < 2 and ev != 0):
		why.append("event in round %d of %d" % [ev, rounds])
	return why


## The board's shape: fully connected (START reaches every space, every space leads back to START), every
## space has a way on, junctions offer two different ways, no tiles overlap, none sit up the volcano or out
## at sea.
static func check_board(data) -> Array:
	var why: Array = []
	var n: int = data.count()
	if n < 20:
		why.append("only %d spaces" % n)
	var fwd := _reach(data, 0, false)
	var back := _reach(data, 0, true)
	for i in n:
		if not fwd.has(i):
			why.append("space %d can't be reached from START" % i)
		if not back.has(i):
			why.append("space %d never leads back to START" % i)
		var nx: Array = data.next_of(i)
		if nx.is_empty():
			why.append("space %d is a dead end" % i)
		if nx.size() > 2 or (nx.size() == 2 and int(nx[0]) == int(nx[1])):
			why.append("space %d has odd ways on %s" % [i, str(nx)])
		if nx.has(i):
			why.append("space %d leads to itself" % i)
		var p: Vector3 = data.pos(i)
		if Vector2(p.x, p.z).length() > BD.ISLAND_R - 1.2:
			why.append("space %d is out at sea" % i)
		if BD.height(p.x, p.z) > MAX_HILL + 0.05:
			why.append("space %d is up the volcano" % i)
		for j in range(i + 1, n):
			var q: Vector3 = data.pos(j)
			if Vector2(p.x - q.x, p.z - q.z).length() < MIN_GAP - 0.01:
				why.append("spaces %d and %d overlap" % [i, j])
	return why


## Every space reachable from `from` following the arrows (or against them: back = true).
static func _reach(data, from: int, back: bool) -> Dictionary:
	var prev := {}
	if back:
		for s in data.spaces:
			for nx in s["next"]:
				if not prev.has(int(nx)):
					prev[int(nx)] = []
				(prev[int(nx)] as Array).append(int(s["id"]))
	var seen := {from: true}
	var q: Array = [from]
	while not q.is_empty():
		var c: int = q.pop_front()
		var nxt: Array = prev.get(c, []) if back else data.next_of(c)
		for x in nxt:
			if not seen.has(int(x)):
				seen[int(x)] = true
				q.append(int(x))
	return seen
