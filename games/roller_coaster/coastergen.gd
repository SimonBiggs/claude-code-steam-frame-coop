extends RefCounted
## COASTER CREW generator: BUTTONS the bear's coaster PLANS. A plan is the next SECTION of track (a few pieces)
## that continues whatever track is already built: the builder follows the glowing outline piece by piece
## (pad: just press A; VR: the glowing tray piece), and a finished plan earns a golden ticket after the ride.
## Everything is data from a seed (core/seeded.gd), so a section is the same on every machine:
##   section(seed, base, k) -> {"seed", "section": k, "base": [[t, h], ...], "pieces": [[t, 0.0], ...], "wish": t, "full"}
##   ("full": nothing fits any more on this track -> the game starts a brand-new coaster or lets them build freely)
##   check(plan) -> [] when the section is buildable and fun: every piece fits on the table in order, the track
##   never bumps into itself or the station roof, a drop makes it fast, a lap is short enough for little ones.
##   stars(seed, ride, tr, practice) / check_stars(list, tr): the stars and balloons hovering over the ride,
##   spaced so every one can be grabbed (never in a loop, never in the station).
## TODAY'S COASTER: the first section after the practice (straight, left, up) uses daily_seed(), so every
## machine gets the same coaster all day. tests/roller_coaster_gen_test.gd proves all of this over many seeds.

const Track := preload("res://games/roller_coaster/track.gd")
const Seeded := preload("res://core/seeded.gd")

const GAME_ID := "roller_coaster"
const PRACTICE: Array[String] = ["straight", "left", "up"]  # main.gd's practice pieces
const MAX_PIECES := 28  # main.gd
const NEW_COASTER_AT := 10  # a full plan on a track this long starts a brand-new coaster
const TRIES := 28
# The ride physics (main.gd _ride uses the same numbers; the test checks they match).
const G := 9.8
const VMIN := 3.0
const VMAX := 15.0
const LIFT_V := 3.2
const FRICTION := 0.15
const GAP := 1.75  # train.gd: distance between car centres
const MAX_LAP_SECS := 30.0
# Fair-play numbers.
const CLEAR_XZ := 1.3  # two bits of track closer than this sideways...
const CLEAR_Y := 2.0  # ...must be this far apart in height (riders' heads fit under)
const TABLE_HANG := 1.6  # turns may hang this far over the table edge (posts go down to the floor)
const ROOF := [Vector2(-6.6, 4.6), Vector2(-0.4, 8.0), 3.3]  # the station roof (x/z box, top height)
const STAR_GAP := 2.5
const STAR_FROM := Track.STATION_LEN + 2.0
const STAR_END := 4.0  # no stars this close to the end of a lap (the train slows into the station)


## The same seed on every machine all day.
static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


## The practice track the first plan of a session continues.
static func practice_base() -> Array:
	var out: Array = []
	for t in PRACTICE:
		out.append([t, 0.0])
	return out


## Pieces in section k (1, 2, 3...): plans grow a little each time.
static func size_for(k: int) -> int:
	return clampi(3 + k, 4, 7)


## A new section that continues `base` (a piece list). Deterministic: same seed + base + k -> same plan.
static func section(seed_value: int, base: Array, k: int) -> Dictionary:
	var want := size_for(k)
	var attempt := 0
	var stuck := 0
	while attempt < TRIES:
		var n := want if attempt < 14 else maxi(2, want - 1 - (attempt - 14) / 5)  # crowded table: smaller plans
		if base.size() + n > MAX_PIECES:
			n = MAX_PIECES - base.size()
		if n < 2:
			break
		var r := Seeded.rng(seed_value, "try%d" % attempt)
		attempt += 1
		var pcs := _walk(r, base, n, k)
		if pcs.size() != n:
			stuck += 1
			if stuck >= 4 and attempt < 14:
				attempt = 14  # no room for a long plan here: try shorter ones
			continue
		stuck = 0
		var plan := _plan(seed_value, base, k, pcs)
		if check(plan).is_empty():
			return plan
	var empty := _plan(seed_value, base, k, [])
	empty["full"] = true
	return empty


static func _plan(seed_value: int, base: Array, k: int, pcs: Array) -> Dictionary:
	var types: Array = pcs.map(func(p: Array) -> String: return String(p[0]))
	var wish := ""
	for w in ["loop", "splash", "up", "down", "left", "right", "straight"]:
		if types.has(w):
			wish = w
			break
	return {"seed": seed_value, "section": k, "base": base.duplicate(true), "pieces": pcs, "wish": wish, "full": false}


## A random walk of n pieces from the end of `base`: every piece must fit on the table, hills stay in a band,
## at most one loop and one splash, never three turns the same way in a row, and no piece ends on top of an
## earlier bit of track (a cheap pre-check; check() does the real one).
static func _walk(r: RandomNumberGenerator, base: Array, n: int, k: int) -> Array:
	var end := Track.end_of(base)
	var pos: Vector3 = end[0]
	var yaw: float = end[1]
	var ends: Array = [Track.station_start(), Track.station_end()]
	var p := Track.station_end()
	var py := 0.0
	for b in base:
		var e := Track.piece_end(String(b[0]), float(b[1]), p, py)
		p = e[0]
		py = e[1]
		ends.append(p)
	var out: Array = []
	var loops := 0
	var splashes := 0
	var last_turns: Array = []
	for i in n:
		var names: Array = []
		var weights: Array = []
		var y := pos.y
		var cand := {"straight": 1.5, "left": 2.4, "right": 1.6}
		if y < 4.6:
			cand["up"] = 3.0 if i == 0 and y < 2.5 else 2.0
		if y > 2.2:
			cand["down"] = 3.5
		if loops == 0 and k >= 1 and y < 4.0:
			cand["loop"] = 1.6 if k >= 2 else 1.0
		if splashes == 0 and y > 2.5:
			cand["splash"] = 1.4
		for t in cand:
			if last_turns.size() >= 2 and last_turns[-1] == t and last_turns[-2] == t:
				continue  # a third turn the same way curls into itself
			if not Track.fits(t, 0.0, pos, yaw):
				continue
			var e := Track.piece_end(t, 0.0, pos, yaw)
			if _crowded(e[0], ends):
				continue
			names.append(t)
			weights.append(cand[t])
		if names.is_empty():
			return out
		var t: String = names[Seeded.weighted(r, weights)]
		var e := Track.piece_end(t, 0.0, pos, yaw)
		out.append([t, 0.0])
		pos = e[0]
		yaw = e[1]
		ends.append(pos)
		if t == "loop":
			loops += 1
		elif t == "splash":
			splashes += 1
		if t == "left" or t == "right":
			last_turns.append(t)
		else:
			last_turns.clear()
	return out


static func _crowded(p: Vector3, ends: Array) -> bool:
	for i in range(0, ends.size() - 2):
		var o: Vector3 = ends[i]
		if Vector2(p.x - o.x, p.z - o.z).length() < 2.2 and absf(p.y - o.y) < CLEAR_Y:
			return true
	return false


## Why a plan is not buildable or not fun (empty = fine).
static func check(plan: Dictionary) -> Array:
	var out: Array = []
	var base: Array = plan.base
	var pcs: Array = plan.pieces
	if pcs.is_empty():
		if not bool(plan.get("full", false)):
			out.append("an empty plan that isn't marked full")
		return out
	if base.size() + pcs.size() > MAX_PIECES:
		out.append("too many pieces (%d)" % (base.size() + pcs.size()))
	var end := Track.end_of(base)
	var pos: Vector3 = end[0]
	var yaw: float = end[1]
	var types: Array = []
	for i in pcs.size():
		var t := String(pcs[i][0])
		types.append(t)
		if not Track.TYPES.has(t):
			out.append("unknown piece %s" % t)
			return out
		if not Track.fits(t, 0.0, pos, yaw):
			out.append("piece %d (%s) falls off the table" % [i, t])
		var e := Track.piece_end(t, 0.0, pos, yaw)
		pos = e[0]
		yaw = e[1]
	if types.count("loop") > 1 or types.count("splash") > 1:
		out.append("more than one loop or splash")
	if not types.has(String(plan.wish)):
		out.append("the wish (%s) isn't in the plan" % plan.wish)
	if not out.is_empty():
		return out  # (cheap checks first: generation retries fast)
	var all := base.duplicate(true)
	all.append_array(pcs)
	var tr := Track.build(all)
	var from_s := Track.STATION_LEN if base.is_empty() else float((tr.piece_s as Array)[base.size() - 1])
	out.append_array(track_problems(tr, from_s))
	if not out.is_empty():
		return out
	var st := ride_stats(tr)
	if float(st.secs) > MAX_LAP_SECS:
		out.append("a lap takes too long (%.1f s)" % float(st.secs))
	if float(st.vmax) < 6.0:
		out.append("no fast drop (top speed %.1f)" % float(st.vmax))
	return out


## Problems with the part of a built track from distance from_s on (the new section and the way home): off
## the table, too high or low, through the station roof, or bumping into another bit of track.
static func track_problems(tr: Dictionary, from_s: float) -> Array:
	var out: Array = []
	var pts: PackedVector3Array = tr.pts
	var dist: PackedFloat32Array = tr.dist
	var length: float = tr.length
	var loops: Array = tr.loops
	var grid := {}
	for i in range(0, pts.size(), 2):
		var c := Vector2i(floori(pts[i].x / CLEAR_XZ), floori(pts[i].z / CLEAR_XZ))
		if not grid.has(c):
			grid[c] = []
		(grid[c] as Array).append(i)
	var roof_a: Vector2 = ROOF[0]
	var roof_b: Vector2 = ROOF[1]
	for i in range(0, pts.size(), 2):
		var s := dist[i]
		if s < from_s - 0.01:
			continue
		var p := pts[i]
		if Vector2(p.x, p.z).length() > Track.TABLE_R + TABLE_HANG:
			out.append("off the table at %.1f m" % s)
			return out
		if p.y < Track.MIN_Y - 0.05 or p.y > Track.MAX_Y + Track.LOOP_R * 2.0 + 0.3:
			out.append("too high or low at %.1f m (%.1f)" % [s, p.y])
			return out
		if s > Track.STATION_LEN + 0.5 and s < length - 2.5 and p.x > roof_a.x and p.x < roof_b.x and p.z > roof_a.y and p.z < roof_b.y and p.y < float(ROOF[2]):
			out.append("through the station roof at %.1f m" % s)
			return out
		var c := Vector2i(floori(p.x / CLEAR_XZ), floori(p.z / CLEAR_XZ))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for j in grid.get(c + Vector2i(dx, dz), []):
					var ds := absf(dist[j] - s)
					ds = minf(ds, length - ds)
					if ds < 5.0 or _same_loop(loops, s, dist[j]):
						continue
					var q := pts[j]
					if Vector2(p.x - q.x, p.z - q.z).length() < CLEAR_XZ and absf(p.y - q.y) < CLEAR_Y:
						out.append("the track bumps into itself at %.1f m and %.1f m" % [s, dist[j]])
						return out
	return out


static func _same_loop(loops: Array, a: float, b: float) -> bool:
	for l in loops:
		if a >= float(l[0]) - 1.5 and a <= float(l[1]) + 1.5 and b >= float(l[0]) - 1.5 and b <= float(l[1]) + 1.5:
			return true
	return false


## One lap with main.gd's ride physics: {"secs", "vmin", "vmax"}.
static func ride_stats(tr: Dictionary, dt: float = 1.0 / 20.0) -> Dictionary:
	var length: float = tr.length
	var s0 := Track.STATION_LEN - 0.4
	var d := 0.0
	var v := 5.0
	var energy := 0.5 * v * v + G * Track.STATION_Y
	var secs := 0.0
	var vmin := 99.0
	var vmax := 0.0
	while d < length and secs < 120.0:
		var xf := Track.sample(tr, s0 + d - GAP)
		var y := xf.origin.y
		v = sqrt(maxf(0.0, 2.0 * (energy - G * y)))
		if -xf.basis.z.y > 0.08 and v < LIFT_V:
			v = LIFT_V
		v = clampf(v, VMIN, VMAX)
		energy = 0.5 * v * v + G * y - FRICTION * dt
		vmin = minf(vmin, v)
		vmax = maxf(vmax, v)
		d += v * dt
		secs += dt
	return {"secs": secs, "vmin": vmin, "vmax": vmax}


## Stars and balloons for ride number `ride` (1, 2, ...) on the built track: [[s, kind], ...]. The practice
## ride has three easy ones; later rides have more (3 -> 7), spread out and never in a loop.
static func stars(seed_value: int, ride: int, tr: Dictionary, practice: bool) -> Array:
	var length: float = tr.length
	var out: Array = []
	if practice:
		for f in [0.35, 0.55, 0.78]:
			out.append([length * f, "star"])
		return out
	var want := mini(3 + ride / 2, 7)
	var r := Seeded.rng(seed_value, "stars%d" % ride)
	var lo := STAR_FROM
	var hi := length - STAR_END
	if hi <= lo:
		return out
	want = mini(want, int((hi - lo) / STAR_GAP))
	if want <= 0:
		return out
	var span := (hi - lo) / want
	var wiggle := maxf(0.0, (span - STAR_GAP) * 0.45)
	for i in want:
		var s := lo + span * (i + 0.5) + r.randf_range(-wiggle, wiggle)
		if not out.is_empty():
			s = maxf(s, float(out[-1][0]) + STAR_GAP)  # pushed along, never closer than the gap
		for l in tr.loops:
			if s >= float(l[0]) - 0.2 and s <= float(l[1]) + 0.2:
				s = float(l[1]) + 0.4  # just after the loop
		if s > hi:
			break
		out.append([s, "balloon" if out.size() % 2 == 1 else "star"])
	var x := lo
	while out.size() < want and x <= hi:  # loops pushed some out: fill any free gap from the start
		var free := not Track.in_ranges(tr.loops, x)
		for o in out:
			free = free and absf(float(o[0]) - x) >= STAR_GAP
		if free:
			out.append([x, "balloon" if out.size() % 2 == 1 else "star"])
		x += 0.5
	out.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	return out


## Why a star list is unfair on this track (empty = fine).
static func check_stars(list: Array, tr: Dictionary, practice: bool) -> Array:
	var out: Array = []
	var length: float = tr.length
	if list.size() < 3 and length > STAR_FROM + STAR_END + STAR_GAP * 3.0:
		out.append("only %d stars on a %.0f m track" % [list.size(), length])
	for i in list.size():
		var s := float(list[i][0])
		if s < Track.STATION_LEN or s > length - 1.0:
			out.append("a star in the station (%.1f)" % s)
		if not practice and Track.in_ranges(tr.loops, s):
			out.append("a star inside a loop (%.1f)" % s)
		if i > 0 and s - float(list[i - 1][0]) < (1.0 if practice else STAR_GAP - 0.01):
			out.append("stars too close (%.1f, %.1f)" % [float(list[i - 1][0]), s])
	return out
