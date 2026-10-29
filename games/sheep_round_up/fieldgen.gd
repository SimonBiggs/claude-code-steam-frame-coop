extends RefCounted
## SHEEP ROUND-UP fields from a seed: which pen gates are open, low hedges with gaps, round bushes, a
## stream with wooden bridges, where the sheep hide (in little clusters, breeds mixed in) and where the
## dogs start. Rising: later fields (level = fields cleared) have more sheep, fewer open gates, more
## bushes and hedges, a stream, and new breeds (lambs, black sheep, fluffy sheep, a golden one).
## Same (seed, spec) -> same field on every machine (the host sends just the seed and the spec).
## check(field) is the validator (tests/sheep_round_up_gen_test.gd runs it over many seeds, and
## generate() only returns fields that pass it): every sheep can be herded to an open gate along a path
## wide enough for a sheep with a dog beside it, there are no pockets a sheep can wander into but never
## leave, every open gate's doorstep is clear, the dogs can reach everywhere, and nothing near the
## field is tall enough to hide a dog from its follow camera (Nathanael's camera, 2026-10: a bush).
## Pure data plus the shared geometry the game uses (move_sheep / move_dog / fence_block / water_at).

const Seeded := preload("res://core/seeded.gd")

const ARENA := 8.0  ## field radius
const PEN := 1.6  ## pen half size (square at the centre)
const GAP := 0.75  ## half width of a gate
const HEDGE_R := 0.22  ## half thickness of a hedge (a capsule between two points)
const HEDGE_H := 0.62
const BUSH_H := 1.15  ## a bush is this many times its radius tall
const BUSH_MAX_R := 0.55
const LOW := 0.75  ## nothing on the field is taller than this: the follow cameras always see over it
## Tall things (trees, the barn, the windmill) only beyond this radius: a follow camera sits up to
## ~4.7 m behind its dog (pivot 0.6, distance 5.5, pitch -0.55) and a tree crown is ~1.5 m wide.
const CAMERA_RING := ARENA + 7.5
const SHEEP_R := 0.3
const DOG_R := 0.3
const HERD_R := 0.6  ## half the width a sheep needs with a dog beside it
const CELL := 0.3  ## validator grid
const STREAM_W := 0.55  ## half width of the stream
const BRIDGE_W := 1.0  ## half width of a bridge
const DOG_SLOW := 0.55  ## dogs paddle across the stream at this speed

## Breeds (index = id in the field's sheep list). speed / scare / wander scale the plain sheep;
## pts = points for the dog that brings it home; from = first field level it can appear on.
const WHITE := 0
const LAMB := 1
const BLACK := 2
const FLUFFY := 3
const GOLDEN := 4
const BREEDS: Array = [
	{"id": "white", "name": "WOOLLY", "wool": Color(0.97, 0.96, 0.92), "face": Color(0.3, 0.28, 0.3), "scale": 0.8,
		"speed": 1.0, "scare": 1.0, "wander": 0.5, "pts": 1, "from": 0, "line": ""},
	{"id": "lamb", "name": "LAMB", "wool": Color(1.0, 0.99, 0.97), "face": Color(0.96, 0.78, 0.74), "scale": 0.58,
		"speed": 1.15, "scare": 1.0, "wander": 0.6, "pts": 1, "from": 1, "line": "A lamb! So tiny!"},
	{"id": "black", "name": "BLACK SHEEP", "wool": Color(0.24, 0.22, 0.26), "face": Color(0.1, 0.1, 0.12), "scale": 0.8,
		"speed": 1.05, "scare": 1.0, "wander": 0.95, "pts": 2, "from": 2, "line": "A black sheep! Cheeky!"},
	{"id": "fluffy", "name": "FLUFFY", "wool": Color(1.0, 0.9, 0.74), "face": Color(0.45, 0.33, 0.28), "scale": 1.05,
		"speed": 0.7, "scare": 0.8, "wander": 0.35, "pts": 2, "from": 4, "line": "So fluffy! So slow!"},
	{"id": "golden", "name": "GOLDEN", "wool": Color(1.0, 0.8, 0.28), "face": Color(0.5, 0.33, 0.18), "scale": 0.8,
		"speed": 1.2, "scare": 1.3, "wander": 0.6, "pts": 5, "from": 5, "line": "GOLDEN fleece! Wow!"},
]
const ADJ: Array[String] = ["SUNNY", "WINDY", "BUMPY", "MUDDY", "DAISY", "CLOVER", "MISTY", "BUTTERCUP", "HONEY", "PEBBLE"]
const NOUN: Array[String] = ["MEADOW", "HILL", "FIELD", "VALLEY", "PASTURE", "DELL", "GREEN", "COMMON"]
## Where Bo's home farm sits (north, beyond the camera ring): main.gd / field_view.gd build it there.
const FARM_CENTER := Vector3(0.0, 0.0, -(ARENA + 10.5))


# --- Difficulty ---------------------------------------------------------------------------------

## The field a level brings. players = everyone playing (dogs + the farmer); time = the round's base seconds.
static func spec(level: int, players: int = 2, time: float = 120.0) -> Dictionary:
	var lv := maxi(0, level)
	var weights: Array = []
	for b in BREEDS.size():
		var w := 0.0
		if lv >= int(BREEDS[b].from) and b != GOLDEN:
			w = [6.0, 2.0, 1.5, 1.5][b] if b < 4 else 0.0
		weights.append(w)
	var n := mini(5 + lv * 2 + (1 if players >= 4 else 0), 18)
	var gates := 4 if lv < 2 else (3 if lv < 4 else (2 if lv < 7 else 1 + (lv % 2)))
	return {
		"level": lv,
		"n": n,
		"gates": gates,
		"bushes": 0 if lv < 1 else mini(2 + lv, 8),
		"hedges": 0 if lv < 2 else mini(1 + lv / 2, 5),
		"stream": lv == 3 or (lv >= 5 and lv % 3 != 1),
		"bridges": 2 if lv < 7 else 1,
		"breeds": weights,
		"golden": lv >= int(BREEDS[GOLDEN].from) and lv % 2 == 1,
		"time": float(time) + (maxf(0.0, n - 5.0) * 4.0 if time >= 60.0 else 0.0),
	}


## TODAY'S FIELD: the same middling field for everyone all day (level 3..6 from the date).
static func daily_spec(players: int = 2, time: float = 120.0, date: String = "") -> Dictionary:
	var r := Seeded.rng(daily_seed(date), "level")
	var sp := spec(3 + r.randi() % 4, players, time)
	sp["daily"] = true
	return sp


static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed("sheep_round_up", date)


# --- Generation ---------------------------------------------------------------------------------

## A field that passes check(). Tries a few layouts from the same seed; the plain field (no hedges,
## bushes or stream, every gate open) is the last resort and always passes.
static func generate(seed_value: int, sp: Dictionary) -> Dictionary:
	for attempt in 10:
		var f := _try(seed_value, sp, attempt)
		if check(f).is_empty():
			return f
	var plain := sp.duplicate()
	plain.merge({"gates": 4, "bushes": 0, "hedges": 0, "stream": false}, true)
	var f2 := _try(seed_value, plain, 99)
	f2["level"] = int(sp.get("level", 0))
	return f2


static func _try(seed_value: int, sp: Dictionary, attempt: int) -> Dictionary:
	var r := Seeded.rng(seed_value, "field%d" % attempt)
	var nr := Seeded.rng(seed_value, "name")
	var f := {"seed": seed_value, "attempt": attempt, "level": int(sp.get("level", 0)), "n": int(sp.get("n", 5)),
		"time": float(sp.get("time", 120.0)), "daily": bool(sp.get("daily", false)),
		"name": "%s %s" % [Seeded.pick(nr, ADJ), Seeded.pick(nr, NOUN)],
		"gates": 15, "stream": {}, "hedges": [], "bushes": [], "sheep": [], "dogs": [], "trees": [], "flowers": []}
	# Gates: k of the four sides open.
	var sides := Seeded.shuffled(r, [0, 1, 2, 3])
	var mask := 0
	for i in clampi(int(sp.get("gates", 4)), 1, 4):
		mask |= 1 << int(sides[i])
	f.gates = mask
	# The stream: a straight band across the field, clear of the pen, with wooden bridges.
	if bool(sp.get("stream", false)):
		var a := r.randf() * TAU
		var d := snappedf(r.randf_range(PEN + 2.4, ARENA - 2.8), 0.01)
		var half := sqrt(ARENA * ARENA - d * d)
		var br: Array = []
		if int(sp.get("bridges", 2)) >= 2:
			br.append(snappedf(r.randf_range(-half + 1.8, -0.6), 0.01))
			br.append(snappedf(r.randf_range(0.6, half - 1.8), 0.01))
		else:
			br.append(snappedf(r.randf_range(-half + 1.8, half - 1.8), 0.01))
		f.stream = {"n": [snappedf(cos(a), 0.0001), snappedf(sin(a), 0.0001)], "d": d, "w": STREAM_W, "bridges": br}
	# Hedges: low green walls, mostly running round the pen (sheep go round them).
	for k in int(sp.get("hedges", 0)):
		for _t in 30:
			var ca := r.randf() * TAU
			var cr := r.randf_range(PEN + 2.6, ARENA - 1.9)
			var c := Vector2(cos(ca), sin(ca)) * cr
			var dir := Vector2(-sin(ca), cos(ca))
			if r.randf() < 0.3:
				dir = Vector2(cos(ca), sin(ca))
			dir = dir.rotated(r.randf_range(-0.4, 0.4))
			var ln := r.randf_range(1.6, 3.0)
			var pa := c - dir * ln * 0.5
			var pb := c + dir * ln * 0.5
			if pa.length() > ARENA - 1.7 or pb.length() > ARENA - 1.7:
				continue
			if _seg_dist(Vector2.ZERO, pa, pb) < PEN * 1.42 + 1.1:
				continue
			if _seg_near_stream(f, pa, pb, STREAM_W + HEDGE_R + 1.3):
				continue
			var ok := true
			for h in f.hedges:
				if _seg_seg(pa, pb, Vector2(h[0], h[1]), Vector2(h[2], h[3])) < 1.7:
					ok = false
					break
			if ok:
				f.hedges.append([snappedf(pa.x, 0.01), snappedf(pa.y, 0.01), snappedf(pb.x, 0.01), snappedf(pb.y, 0.01)])
				break
	# Bushes: small and round (never taller than LOW).
	for k in int(sp.get("bushes", 0)):
		for _t in 30:
			var ba := r.randf() * TAU
			var p := Vector2(cos(ba), sin(ba)) * r.randf_range(PEN + 2.0, ARENA - 1.7)
			var br := snappedf(r.randf_range(0.35, BUSH_MAX_R), 0.01)
			if _blocked(f, p, br + 0.9) or _water2(f, p, br + 0.6) or _near_gate(p, 1.6 + br):
				continue
			f.bushes.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), br])
			break
	# Sheep: hiding in little clusters around the field; the first two near open gates (easy first catches).
	var n := int(f.n)
	var open: Array = []
	for s in 4:
		if gate_open(mask, s):
			open.append(s)
	var clusters: Array = []
	for c in 1 + n / 4:
		var ca := r.randf() * TAU
		clusters.append(Vector2(cos(ca), sin(ca)) * r.randf_range(PEN + 3.0, ARENA - 2.0))
	var weights: Array = sp.get("breeds", [1.0])
	var golden := -1
	if bool(sp.get("golden", false)) and n > 3:
		golden = 2 + r.randi() % (n - 2)
	for i in n:
		for _t in 60:
			var p: Vector2
			if i < 2 and _t < 20:
				var side: int = open[i % open.size()]
				var g := _rot(side, Vector2(r.randf_range(-0.4, 0.4), PEN + 1.4 + r.randf_range(0.0, 0.5)))
				p = g
			elif _t < 40:
				p = clusters[i % clusters.size()] + Vector2(r.randf_range(-1.6, 1.6), r.randf_range(-1.6, 1.6))
			else:
				var sa := r.randf() * TAU
				p = Vector2(cos(sa), sin(sa)) * r.randf_range(PEN + 2.0, ARENA - 1.0)
			if p.length() > ARENA - 1.0 or _cheb(p) < PEN + 1.0 or _blocked(f, p, SHEEP_R + 0.5) or _water2(f, p, 0.6):
				continue
			var ok := true
			for o in f.sheep:
				if p.distance_to(Vector2(o[0], o[1])) < 0.75:
					ok = false
					break
			if not ok:
				continue
			var breed := WHITE
			if i == golden:
				breed = GOLDEN
			elif i >= 2:
				breed = Seeded.weighted(r, weights)
			f.sheep.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), breed])
			break
	# Dog starts: six spots round the pen (south first), each on clear ground.
	for k in 6:
		for t in 24:
			var da := k * TAU / 6.0 + (t % 6) * 0.35
			var p := Vector2(sin(da), cos(da)) * (PEN + 2.6 + (t / 6) * 0.9)
			if p.length() < ARENA - 1.0 and not _blocked(f, p, DOG_R + 0.4) and not _water2(f, p, 0.4):
				f.dogs.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
				break
	# Scenery: trees far beyond the camera ring (never in the farm's corner), flowers on the field.
	var tr := Seeded.rng(seed_value, "trees")
	for k in 26:
		var ta := tr.randf() * TAU
		var p := Vector2(cos(ta), sin(ta)) * tr.randf_range(CAMERA_RING + 0.3, ARENA + 15.0)
		if p.y < -(ARENA + 4.0) and absf(p.x) < 11.0:
			continue  # Bo's farm
		f.trees.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(tr.randf_range(0.9, 1.4), 0.01)])
	for k in 44:
		var fa := tr.randf() * TAU
		var p := Vector2(cos(fa), sin(fa)) * tr.randf_range(PEN + 1.0, ARENA - 0.3)
		if not _water2(f, p, 0.15) and not _blocked(f, p, 0.15):
			f.flowers.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), tr.randi() % 4])
	return f


# --- Validator ----------------------------------------------------------------------------------

## Every reason this field isn't fair (empty = fine).
static func check(f: Dictionary) -> Array:
	var why: Array = []
	var mask := int(f.get("gates", 0))
	if mask <= 0 or mask > 15:
		why.append("no open gate")
		return why
	if (f.sheep as Array).size() != int(f.n):
		why.append("only %d of %d sheep placed" % [(f.sheep as Array).size(), int(f.n)])
	if (f.dogs as Array).size() < 6:
		why.append("only %d dog starts" % (f.dogs as Array).size())
	# Nothing tall where a follow camera could be.
	if HEDGE_H > LOW:
		why.append("hedges too tall")
	for b in f.bushes:
		if float(b[2]) * BUSH_H > LOW:
			why.append("bush too tall at %.1f,%.1f" % [b[0], b[1]])
	for t in f.trees:
		if Vector2(t[0], t[1]).length() < CAMERA_RING:
			why.append("tree inside the camera ring at %.1f,%.1f" % [t[0], t[1]])
	if not (f.stream as Dictionary).is_empty():
		var st: Dictionary = f.stream
		if float(st.d) < PEN * 1.42 + STREAM_W + 0.8:
			why.append("stream too close to the pen")
		if (st.bridges as Array).is_empty():
			why.append("stream without a bridge")
	# Spawns on clear ground.
	var spots: Array = []
	for s in f.sheep:
		var p := Vector2(s[0], s[1])
		if p.length() > ARENA - 0.5 or _cheb(p) < PEN + 0.5:
			why.append("sheep outside the field or in the pen at %.1f,%.1f" % [p.x, p.y])
		if _blocked(f, p, SHEEP_R) or _water2(f, p, 0.0):
			why.append("sheep stuck in a hedge, bush or the stream at %.1f,%.1f" % [p.x, p.y])
		for o in spots:
			if p.distance_to(o) < 0.6:
				why.append("two sheep on one spot at %.1f,%.1f" % [p.x, p.y])
		spots.append(p)
	for d in f.dogs:
		if _blocked(f, Vector2(d[0], d[1]), DOG_R) or Vector2(d[0], d[1]).length() > ARENA - 0.5:
			why.append("dog start blocked at %.1f,%.1f" % [d[0], d[1]])
	if not why.is_empty():
		return why
	# The grid: where a sheep can be, where a herd (sheep + dog) fits, where a dog can run.
	var n := int(ceil(ARENA * 2.0 / CELL))
	var sheep_ok := PackedByteArray()
	var herd_ok := PackedByteArray()
	var dog_ok := PackedByteArray()
	sheep_ok.resize(n * n)
	herd_ok.resize(n * n)
	dog_ok.resize(n * n)
	for iz in n:
		for ix in n:
			var p := Vector2(-ARENA + (ix + 0.5) * CELL, -ARENA + (iz + 0.5) * CELL)
			var rad := p.length()
			if rad > ARENA - 0.35:
				continue
			var clear := _clearance(f, p)
			var i := iz * n + ix
			var pen := _cheb(p) < PEN + 0.35
			if clear > DOG_R:
				dog_ok[i] = 1
			if pen:
				continue
			if clear > SHEEP_R and not water_at(f, p.x, p.y, SHEEP_R):
				sheep_ok[i] = 1
			if clear > HERD_R and rad < ARENA - HERD_R and not water_at(f, p.x, p.y, HERD_R * 0.6):
				herd_ok[i] = 1
	var starts: Array = []
	for s in 4:
		if gate_open(mask, s):
			var g := _rot(s, Vector2(0.0, PEN + 0.55))
			var gi := _cell(g, n)
			if sheep_ok[gi] == 0 or herd_ok[gi] == 0:
				why.append("gate %d's doorstep is blocked" % s)
			starts.append(gi)
	if not why.is_empty():
		return why
	var reach_s := _flood(sheep_ok, n, starts)
	var reach_h := _flood(herd_ok, n, starts)
	var pockets := 0
	for i in n * n:
		if sheep_ok[i] == 1 and reach_s[i] == 0:
			pockets += 1
	if pockets > 0:
		why.append("%d spots a sheep could wander into and never be herded out of" % pockets)
	for s in f.sheep:
		if not _reached_near(reach_h, n, Vector2(s[0], s[1]), 2):
			why.append("sheep at %.1f,%.1f has no herding path to an open gate" % [s[0], s[1]])
	var d0 := _cell(Vector2(f.dogs[0][0], f.dogs[0][1]), n)
	var reach_d := _flood(dog_ok, n, [d0])
	var lost := 0
	for i in n * n:
		if dog_ok[i] == 1 and reach_d[i] == 0:
			lost += 1
	if lost > 0:
		why.append("%d spots the dogs can't reach" % lost)
	return why


static func _flood(ok: PackedByteArray, n: int, starts: Array) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(n * n)
	var q := PackedInt32Array()
	for s in starts:
		if ok[int(s)] == 1 and seen[int(s)] == 0:
			seen[int(s)] = 1
			q.append(int(s))
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var x := i % n
		var nb: Array[int] = []
		if x > 0:
			nb.append(i - 1)
		if x < n - 1:
			nb.append(i + 1)
		if i >= n:
			nb.append(i - n)
		if i < n * (n - 1):
			nb.append(i + n)
		for j in nb:
			if ok[j] == 1 and seen[j] == 0:
				seen[j] = 1
				q.append(j)
	return seen


static func _cell(p: Vector2, n: int) -> int:
	var ix := clampi(int(floor((p.x + ARENA) / CELL)), 0, n - 1)
	var iz := clampi(int(floor((p.y + ARENA) / CELL)), 0, n - 1)
	return iz * n + ix


static func _reached_near(seen: PackedByteArray, n: int, p: Vector2, rad: int) -> bool:
	var c := _cell(p, n)
	var cx := c % n
	var cz := c / n
	for dz in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			var x := cx + dx
			var z := cz + dz
			if x >= 0 and z >= 0 and x < n and z < n and seen[z * n + x] == 1:
				return true
	return false


# --- Geometry (shared with main.gd) -----------------------------------------------------------

static func in_pen(p: Vector3, margin: float = 0.0) -> bool:
	return absf(p.x) < PEN - margin and absf(p.z) < PEN - margin


## Sides: 0 = south (+Z), 1 = east (+X), 2 = north (-Z), 3 = west (-X).
static func gate_open(gates: int, side: int) -> bool:
	return (gates >> side) & 1 == 1


## A point on side `side` (local x along the fence, y outwards) in field x,z.
static func _rot(side: int, v: Vector2) -> Vector2:
	match side:
		0:
			return Vector2(v.x, v.y)
		1:
			return Vector2(v.y, -v.x)
		2:
			return Vector2(-v.x, -v.y)
	return Vector2(-v.y, v.x)


## The world position of a gate's middle (y = 0), `out` metres out from the fence.
static func gate_point(side: int, out: float = 0.0) -> Vector3:
	var g := _rot(side, Vector2(0.0, PEN + out))
	return Vector3(g.x, 0.0, g.y)


## A walking sheep outside the pen may only get in through an OPEN gate.
static func fence_block(from: Vector3, to: Vector3, gates: int = 15) -> Vector3:
	if not in_pen(to) or in_pen(from):
		return to
	var r := to
	if absf(from.x) >= PEN and absf(from.z) < PEN:
		if absf(to.z) > GAP or not gate_open(gates, 1 if from.x > 0.0 else 3):
			r.x = signf(from.x) * PEN
	elif absf(from.z) >= PEN and absf(from.x) < PEN:
		if absf(to.x) > GAP or not gate_open(gates, 0 if from.z > 0.0 else 2):
			r.z = signf(from.z) * PEN
	else:
		r = from
	return r


## Is (x, z) in the stream (and not on a bridge)? margin: how far onto a bridge counts as "on" it.
static func water_at(f: Dictionary, x: float, z: float, margin: float = 0.0) -> bool:
	var st: Dictionary = f.get("stream", {})
	if st.is_empty():
		return false
	var nv: Array = st.n
	var s := x * float(nv[0]) + z * float(nv[1]) - float(st.d)
	if absf(s) >= float(st.w):
		return false
	var t := -x * float(nv[1]) + z * float(nv[0])
	for b in st.bridges:
		if absf(t - float(b)) < BRIDGE_W - margin:
			return false
	return true


static func _water2(f: Dictionary, p: Vector2, pad: float) -> bool:
	var st: Dictionary = f.get("stream", {})
	if st.is_empty():
		return false
	var nv: Array = st.n
	return absf(p.x * float(nv[0]) + p.y * float(nv[1]) - float(st.d)) < float(st.w) + pad


## Where a sheep walking from `from` towards `to` ends up: never into the stream (it walks along the
## bank, or over a bridge), never through a hedge or a bush. A sheep that lands in the water (thrown)
## scrambles out to the nearer bank.
static func move_sheep(f: Dictionary, from: Vector3, to: Vector3) -> Vector3:
	var p := to
	if water_at(f, p.x, p.z):
		var st: Dictionary = f.stream
		var nv: Array = st.n
		var nn := Vector3(float(nv[0]), 0.0, float(nv[1]))
		var s_to := p.dot(nn) - float(st.d)
		if not water_at(f, from.x, from.z):
			var s_from := from.dot(nn) - float(st.d)
			p -= nn * (s_to - s_from)
			if water_at(f, p.x, p.z):
				p = from
		else:
			p += nn * ((float(st.w) + 0.05) * signf(s_to if s_to != 0.0 else 1.0) - s_to)
	return push_solid(f, p, SHEEP_R)


## Dogs run round hedges and bushes (they paddle through the stream: see DOG_SLOW).
static func move_dog(f: Dictionary, p: Vector3) -> Vector3:
	return push_solid(f, p, DOG_R)


static func push_solid(f: Dictionary, p: Vector3, rad: float) -> Vector3:
	var q := Vector2(p.x, p.z)
	for h in f.get("hedges", []):
		var c := _closest(q, Vector2(h[0], h[1]), Vector2(h[2], h[3]))
		var dv := q - c
		var need := HEDGE_R + rad
		if dv.length() < need:
			q = c + (dv.normalized() if dv.length() > 0.001 else Vector2(0.0, 1.0)) * need
	for b in f.get("bushes", []):
		var c := Vector2(b[0], b[1])
		var dv := q - c
		var need := float(b[2]) + rad
		if dv.length() < need:
			q = c + (dv.normalized() if dv.length() > 0.001 else Vector2(1.0, 0.0)) * need
	return Vector3(q.x, p.y, q.y)


## Distance from p to the nearest hedge / bush surface (INF when there are none).
static func _clearance(f: Dictionary, p: Vector2) -> float:
	var best := INF
	for h in f.hedges:
		best = minf(best, _seg_dist(p, Vector2(h[0], h[1]), Vector2(h[2], h[3])) - HEDGE_R)
	for b in f.bushes:
		best = minf(best, p.distance_to(Vector2(b[0], b[1])) - float(b[2]))
	return best


static func _blocked(f: Dictionary, p: Vector2, rad: float) -> bool:
	return _clearance(f, p) < rad


static func _near_gate(p: Vector2, rad: float) -> bool:
	for s in 4:
		if p.distance_to(_rot(s, Vector2(0.0, PEN + 0.6))) < rad:
			return true
	return false


static func _cheb(p: Vector2) -> float:
	return maxf(absf(p.x), absf(p.y))


static func _closest(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return a + ab * t


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(_closest(p, a, b))


static func _seg_seg(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return 0.0
	return minf(minf(_seg_dist(a, c, d), _seg_dist(b, c, d)), minf(_seg_dist(c, a, b), _seg_dist(d, a, b)))


static func _seg_near_stream(f: Dictionary, a: Vector2, b: Vector2, pad: float) -> bool:
	var st: Dictionary = f.get("stream", {})
	if st.is_empty():
		return false
	var nv: Array = st.n
	var sa := a.x * float(nv[0]) + a.y * float(nv[1]) - float(st.d)
	var sb := b.x * float(nv[0]) + b.y * float(nv[1]) - float(st.d)
	return signf(sa) != signf(sb) or minf(absf(sa), absf(sb)) < pad
