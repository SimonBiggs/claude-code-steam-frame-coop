extends RefCounted
## KART RACE track generator: a brand-new looping track from a seed (the same seed gives the same track on
## every machine, so the host only sends a few numbers and each TV / Deck builds it itself).
##   const TrackGen := preload("res://games/kart_race/trackgen.gd")
##   var info := TrackGen.generate(seed, {"palette": 1, "size": 0.5, "ramps": 2, "splits": 1})
##   track.build_info(info, TrackGen.key_of(seed, spec))     # a track.gd TRACKS-style Dictionary
##   TrackGen.check(info) -> Array of reasons (empty = fair)  # the validator (tests/kart_trackgen_test.gd)
## How: 8-12 control points round a wobbly ellipse (always a simple loop), one long side turned into the
## start straight (five points in a row, so the grid and the start line are dead straight and flat), gentle
## hills, then features placed in the distance-along-the-track space: ramps on straights, boost arrows,
## rows of ? boxes, and SPLIT LANES (the road widens round a flower-bed island in a bend: the inside lane
## is shorter and has a boost arrow - the secret shortcut). Every attempt is checked; the first fair one
## wins (a few attempts per seed; after 60 it falls back to a hand-made track, which the test forbids).
## The validator proves: closed loop, sensible length, never crosses or runs close to itself (room for walls
## and crowds), every bend drivable at kart speeds (radius), gentle slopes and crests (no surprise launches),
## a straight flat start with room for the whole grid, the practice rings' stretch clear, every ramp jump
## lands on the road at any speed a kart can reach (no wall or island in the air, no landing on a ramp),
## pads / boxes / islands on the road and apart, and no prop spot inside the walls (no hidden walls).

const Seeded := preload("res://core/seeded.gd")
const Track := preload("res://games/kart_race/track.gd")

const CENTER := Vector2(20.0, -35.0)  # middle of the ground and sky dome (track.gd)
const MAX_R := 125.0  # the road stays inside this (the far hills start about 150 m out)
const MIN_RADIUS := 17.0  # tightest bend (a kart turns a 10 m circle at top speed, 14 m boosted)
const START_BACK := 30.0  # straight, flat road behind the start line (the grid: 10 karts need 25 m)
const START_AHEAD := 16.0
const PRACTICE_END := 80.0  # the practice rings (22 / 44 / 66 m) need a plain road
const GAP := 11.0  # metres between the walls of two different parts of the track
const KART_TOP := 30.0  # fastest a kart can go (top speed x catch-up x mushroom x star)
const MAX_SLOPE := 0.11
const MAX_BEND_SLOPE := 0.045  # slope change per sample (crests that would launch a kart)
const ATTEMPTS := 60

static var last_fail := ""  # why the last attempt gave up early (tests print it)

## Track names per palette: first word + second word (track.gd TRACKS order).
const WORDS := [
	[["SUNNY", "DAISY", "BUTTERCUP", "CLOVER", "HONEY", "BLOSSOM"], ["MEADOW", "LANE", "FIELDS", "LOOP", "VALLEY", "FARM"]],
	[["LOLLIPOP", "GUMDROP", "SUGAR", "TOFFEE", "JELLY", "CUPCAKE"], ["HILLS", "LANE", "SWIRL", "LOOP", "TWIST", "PARK"]],
	[["DINO", "CACTUS", "SANDY", "SUNSET", "CANYON", "FOSSIL"], ["DESERT", "DUNES", "TRAIL", "LOOP", "MESA", "RUN"]],
	[["MOONLIGHT", "STARRY", "FIREFLY", "LANTERN", "GLOWING", "SLEEPY"], ["BAY", "COVE", "LOOP", "LAGOON", "PIER", "SHORE"]],
	[["SNOWY", "FROSTY", "IGLOO", "PENGUIN", "ICICLE", "MITTEN"], ["PEAKS", "PASS", "LOOP", "SLOPES", "RIDGE", "VALLEY"]],
]
const RAINBOW_WALLS: Array[Color] = [Color(1.0, 0.3, 0.35), Color(1.0, 0.65, 0.2), Color(1.0, 0.95, 0.3), Color(0.35, 0.95, 0.45),
	Color(0.35, 0.65, 1.0), Color(0.75, 0.45, 1.0)]


## A stable name for a generated track (what track.gd compares to know if it must rebuild).
static func key_of(seed_value: int, spec: Dictionary) -> String:
	return "gen:%d:%s" % [seed_value, var_to_str(spec).md5_text().substr(0, 8)]


## A generated track (track.gd TRACKS-style Dictionary plus "seed", "palette", "splits", "attempt").
static func generate(seed_value: int, spec: Dictionary) -> Dictionary:
	for attempt in ATTEMPTS:
		var r := Seeded.rng(seed_value, "track%d" % attempt)
		var info := _attempt(r, seed_value, spec)
		if info.is_empty():
			continue
		if check(info).is_empty():
			info["attempt"] = attempt
			return info
	var fb: Dictionary = (Track.TRACKS[posmod(int(spec.get("palette", 0)), Track.TRACKS.size())] as Dictionary).duplicate(true)
	fb["palette"] = int(spec.get("palette", 0))
	fb["seed"] = seed_value
	fb["fallback"] = true
	return fb


static func _attempt(r: RandomNumberGenerator, seed_value: int, spec: Dictionary) -> Dictionary:
	var pal := posmod(int(spec.get("palette", 0)), Track.TRACKS.size())
	var base_info: Dictionary = Track.TRACKS[pal]
	var size := clampf(float(spec.get("size", 0.5)), 0.0, 1.0)
	var twist := clampf(float(spec.get("twist", 0.5)), 0.0, 1.0)
	var hills := float(spec.get("hills", 3.0))
	# 1. A wobbly ellipse of control points (angles always go round: a simple loop) with its bottom cut flat:
	# the points below the cut line sit on it, so that side is a long straight (the start goes there).
	var m := r.randi_range(7, 11)  # points round the curved part
	var base := lerpf(70.0, 90.0, size) * r.randf_range(0.94, 1.06)
	var rx := minf(112.0, base * r.randf_range(1.05, 1.3))
	var rz := minf(92.0, base * r.randf_range(0.72, 0.95))
	var cut := minf(r.randf_range(0.42, 0.7), sqrt(1.0 - pow(52.0 / rx, 2.0)))
	var a1 := PI + asin(cut)  # the flat side runs from angle a1 to a2 (through straight down)
	var a2 := TAU - asin(cut)
	var ph := r.randf() * TAU
	var raw: Array[Vector2] = [Vector2(cos(a1) * rx, -cut * rz), Vector2(cos(a2) * rx, -cut * rz)]
	var arc := TAU - (a2 - a1)
	for k in m:
		var f := (k + 1.0 + r.randf_range(-0.25, 0.25)) / (m + 1.0)
		var a := a2 + arc * f
		var calm := clampf(minf(f, 1.0 - f) * (m + 1.0) * 0.6, 0.0, 1.0)  # no wobble next to the straight
		var rr := 1.0 + calm * (twist * r.randf_range(-0.3, 0.2) + 0.08 * sin(2.0 * a + ph))
		raw.append(Vector2(cos(a) * rx * rr, sin(a) * rz * rr))
	var f1 := raw[0]
	var f2 := raw[1]
	if f2.x - f1.x < 100.0:
		last_fail = "flat side too short"
		return {}
	# 2. Travel order from the flat side's entry P to its exit Q (either way round), the start in between:
	# P, S1 (the grid), S0 (the start line), S3, Q all in a row.
	var others: Array[Vector2] = raw.slice(2)
	var P := f1
	var Q := f2
	if r.randf() < 0.5:
		P = f2
		Q = f1
		others.reverse()
	var u := (Q - P).normalized()
	var margin := ((Q - P).length() - 60.0) * 0.5
	var s1 := P + u * margin
	var s0 := s1 + u * 36.0
	var s3 := s0 + u * 24.0
	# Guards keep the straight straight; P and Q round off into the bends.
	var g1 := s1 - u * minf(12.0, margin * 0.6)
	var g2 := s3 + u * minf(12.0, margin * 0.6)
	var order: Array[Vector2] = [s0, s3, g2, Q]
	order.append_array(others)
	order.append(P)
	order.append(g1)
	order.append(s1)
	var cnt := order.size()
	# Round off the corners (the straight's five points stay put).
	for it in 3:
		var nxt := order.duplicate()
		for k in range(3, cnt - 2):
			nxt[k] = order[k].lerp((order[k - 1] + order[k + 1]) * 0.5, 0.35)
		order = nxt
	var rot := r.randf() * TAU
	for k in cnt:
		order[k] = CENTER + order[k].rotated(rot)
	# 3. Heights: gentle hills from waves round the loop, flat round the start.
	var hph := r.randf() * TAU
	var hfreq := float(r.randi_range(1, 3))
	var cps: Array = []
	for k in cnt:
		var h := 0.0
		if k > 3 and k < cnt - 3:
			var f := float(k) / cnt
			h = hills * (0.5 + 0.5 * sin(f * TAU * hfreq + hph)) * clampf(minf(k - 3, cnt - 3 - k) / 2.0, 0.0, 1.0)
		cps.append([snappedf(order[k].x, 0.01), snappedf(order[k].y, 0.01), snappedf(h, 0.01)])
	# Limit slopes between control points.
	for pass_i in 3:
		for k in cnt:
			var a: Array = cps[k]
			var b: Array = cps[(k + 1) % cnt]
			var d := Vector2(float(a[0]) - float(b[0]), float(a[1]) - float(b[1])).length()
			var lim := d * MAX_SLOPE * 0.6
			if absf(float(b[2]) - float(a[2])) > lim and (k + 1) % cnt > 3 and (k + 1) % cnt < cnt - 3:
				b[2] = snappedf(float(a[2]) + clampf(float(b[2]) - float(a[2]), -lim, lim), 0.01)
	var words: Array = WORDS[pal]
	var info: Dictionary = base_info.duplicate(true)
	info["name"] = String(spec.get("name", "")) if spec.has("name") else "%s %s" % [Seeded.pick(r, words[0]), Seeded.pick(r, words[1])]
	info["pts"] = cps
	info["ramps"] = []
	info["pads"] = []
	info["items"] = []
	info["splits"] = []
	info["palette"] = pal
	info["seed"] = seed_value
	if spec.has("night"):
		info["night"] = bool(spec["night"])
	if bool(spec.get("rainbow", false)):
		info["rainbow"] = true
		info["wall_a"] = RAINBOW_WALLS[r.randi() % RAINBOW_WALLS.size()]
		info["wall_b"] = Color(1, 1, 1)
		info["road"] = Color(0.28, 0.22, 0.42)
	_hue(info, r)
	# 4. Features, placed by distance along the sampled track.
	var t: Track = Track.new()
	t.prepare(info)
	var L := t.length
	var rad := radii(t)
	var used: Array = []  # [s from, s to] taken by a feature (plus its run-up / landing)
	var lo := PRACTICE_END + 10.0
	var hi := L - START_BACK - 14.0
	# Split lanes in bends.
	for i in int(spec.get("splits", 0)):
		var ln := r.randf_range(44.0, 56.0)
		for tries in 30:
			var sa := r.randf_range(lo, hi - ln)
			if _overlaps(used, sa - 12.0, sa + ln + 12.0, L):
				continue
			var rmin := _min_radius(t, rad, sa, sa + ln)
			var turn := _bulge(t, sa, sa + ln)
			if rmin < 34.0 or absf(turn) < 4.0:
				continue  # wants a real bend that is not too tight for the wide road
			var wide := r.randf_range(3.6, 4.6)
			var isl := r.randf_range(1.6, 2.2)
			var side := signf(turn)  # the inside of the bend
			(info["splits"] as Array).append([sa / L, snappedf(ln, 0.1), snappedf(wide, 0.01), snappedf(isl, 0.01), side])
			# The shortcut's boost arrow, in the inside lane in the middle of the split.
			var lane := (isl + Track.WIDTH * 0.5 + wide) * 0.5
			(info["pads"] as Array).append([(sa + ln * 0.5 - 2.5) / L, snappedf(side * lane, 0.01)])
			used.append([sa - 12.0, sa + ln + 12.0])
			break
	# Ramps on straight-ish road with room to land.
	for i in int(spec.get("ramps", 1)):
		var ln := r.randf_range(7.0, 8.0)
		for tries in 30:
			var sa := r.randf_range(lo, hi - ln - 30.0)
			if _overlaps(used, sa - 15.0, sa + ln + 32.0, L):
				continue
			if _min_radius(t, rad, sa - 6.0, sa + ln + 30.0) < 55.0:
				continue
			var hw := 3.0 if r.randf() < 0.6 else 2.5
			var lat := 0.0 if hw >= 3.0 else (r.randf_range(-2.4, 2.4))
			(info["ramps"] as Array).append([sa / L, snappedf(ln, 0.1), snappedf(r.randf_range(0.95, 1.25), 0.01), snappedf(lat, 0.01), hw])
			used.append([sa - 15.0, sa + ln + 32.0])
			break
	# Boost arrows.
	for i in int(spec.get("pads", 2)):
		for tries in 30:
			var sa := r.randf_range(24.0, hi)
			if _overlaps(used, sa - 6.0, sa + 11.0, L):
				continue
			if _min_radius(t, rad, sa, sa + 5.0) < 28.0:
				continue
			var lat := [0.0, -2.6, 2.6][r.randi() % 3] as float
			(info["pads"] as Array).append([sa / L, lat])
			used.append([sa - 6.0, sa + 11.0])
			break
	# Rows of ? boxes, spread round the lap.
	var rows := int(spec.get("rows", 3))
	for i in rows:
		for tries in 30:
			var f := (float(i) + r.randf_range(0.2, 0.8)) / rows
			var sa := lerpf(24.0, hi + 6.0, f)
			if _overlaps(used, sa - 8.0, sa + 8.0, L):
				continue
			(info["items"] as Array).append(sa / L)
			used.append([sa - 8.0, sa + 8.0])
			break
	t.free()
	if (info["items"] as Array).size() < mini(rows, 2) or (info["ramps"] as Array).size() < mini(int(spec.get("ramps", 1)), 1):
		last_fail = "no room for boxes / ramps"
		return {}
	if (info["splits"] as Array).size() < int(spec.get("splits", 0)):
		last_fail = "no bend for the split lanes"
		return {}
	for k in ["ramps", "pads", "items", "splits"]:
		(info[k] as Array).sort()
	return info


## Shift the palette a little so every track of a place looks its own.
static func _hue(info: Dictionary, r: RandomNumberGenerator) -> void:
	var dh := r.randf_range(-0.04, 0.04)
	for k in ["grass", "sky", "sky_top", "earth"]:
		if info.has(k):
			var c: Color = info[k]
			info[k] = Color.from_hsv(fposmod(c.h + dh, 1.0), c.s, c.v)
	if not bool(info.get("rainbow", false)) and r.randf() < 0.5:
		var a: Color = info["wall_a"]
		info["wall_a"] = info["wall_b"]
		info["wall_b"] = a


static func _overlaps(used: Array, a: float, b: float, L: float) -> bool:
	for u in used:
		var ua: Array = u
		if a < float(ua[1]) and b > float(ua[0]):
			return true
	return a < 0.0 or b > L


## Turning radius at every sample (metres; big = straight).
static func radii(t: Track) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(t.n)
	var w := 3
	for i in t.n:
		var a := t.tans[posmod(i - w, t.n)]
		var b := t.tans[(i + w) % t.n]
		var ang := absf(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z)))
		var arc := fposmod(t.cum[(i + w) % t.n] - t.cum[posmod(i - w, t.n)], t.length)
		out[i] = 9999.0 if ang < 0.0001 else arc / ang
	return out


static func _idx(t: Track, s: float) -> int:
	return int(t.point_at(s, 0.0)[2])


static func _min_radius(t: Track, rad: PackedFloat32Array, a: float, b: float) -> float:
	var m := 9999.0
	var s := a
	while s <= b:
		m = minf(m, rad[_idx(t, s)])
		s += 2.0
	return m


## How far the road between a and b bows away from the straight line joining them (metres), signed:
## + when the inside of the bend is on the +lat side.
static func _bulge(t: Track, a: float, b: float) -> float:
	var pa: Vector3 = t.point_at(a, 0.0)[0]
	var pb: Vector3 = t.point_at(b, 0.0)[0]
	var mid: Array = t.point_at((a + b) * 0.5, 0.0)
	var pm: Vector3 = mid[0]
	var yaw: float = mid[1]
	var tg := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var rt := Vector3(-tg.z, 0.0, tg.x)
	var to := (pa + pb) * 0.5 - pm
	to.y = 0.0
	return to.dot(rt)


# --- The validator ------------------------------------------------------------------------------

## Why this track is unfair (empty = fine). Pure: builds a track.gd in memory, no scene needed.
static func check(info: Dictionary) -> Array:
	var why: Array = []
	var t: Track = Track.new()
	t.prepare(info)
	_check_track(t, why)
	t.free()
	return why


static func _check_track(t: Track, why: Array) -> void:
	var L := t.length
	var n := t.n
	if L < 380.0 or L > 820.0:
		why.append("length %.0f m" % L)
	# Closed: the last sample runs back into the first.
	var gap := Vector2(t.pts[n - 1].x - t.pts[0].x, t.pts[n - 1].z - t.pts[0].z).length()
	if gap > Track.STEP * 1.6:
		why.append("not closed (%.1f m gap)" % gap)
	# Stays on the ground plane, away from the far hills.
	for i in n:
		var q := t.pts[i]
		if Vector2(q.x, q.z).distance_to(CENTER) + t.wall_at(t.cum[i]) > MAX_R + 8.0:
			why.append("runs off the edge at s=%.0f" % t.cum[i])
			break
	# Never crosses or runs close to itself.
	var near_fail := false
	for i in range(0, n, 2):
		if near_fail:
			break
		var qi := t.pts[i]
		var wi := t.wall_at(t.cum[i])
		for j in range(i + 2, n, 2):
			var arc := absf(t.cum[j] - t.cum[i])
			arc = minf(arc, L - arc)
			if arc < 70.0:
				continue
			var qj := t.pts[j]
			var d := Vector2(qi.x - qj.x, qi.z - qj.z).length()
			if d < wi + t.wall_at(t.cum[j]) + GAP:
				why.append("too close to itself at s=%.0f and s=%.0f (%.1f m)" % [t.cum[i], t.cum[j], d])
				near_fail = true
				break
	# Bends: drivable at kart speeds, and the road never folds over on the inside.
	var rad := radii(t)
	for i in n:
		var need := maxf(MIN_RADIUS, t.wall_at(t.cum[i]) + 6.0)
		if rad[i] < need:
			why.append("bend too tight at s=%.0f (radius %.1f m)" % [t.cum[i], rad[i]])
			break
	# Hills: gentle slopes and crests.
	var prev_slope := 0.0
	for i in n + 1:
		var a := t.pts[i % n]
		var b := t.pts[(i + 1) % n]
		var d := maxf(0.01, Vector2(b.x - a.x, b.z - a.z).length())
		var slope := (b.y - a.y) / d
		if absf(slope) > MAX_SLOPE:
			why.append("too steep at s=%.0f (%.2f)" % [t.cum[i % n], slope])
			break
		if i > 0 and absf(slope - prev_slope) > MAX_BEND_SLOPE:
			why.append("sharp crest at s=%.0f" % t.cum[i % n])
			break
		prev_slope = slope
	# The start: straight and flat behind and just after the line (the grid of 10 karts fits).
	var s := -START_BACK
	var h0 := t.pts[0].y
	while s <= START_AHEAD:
		var i := _idx(t, s)
		if rad[i] < 120.0 or absf(t.pts[i].y - h0) > 0.05:
			why.append("start not straight / flat at %.0f m" % s)
			break
		s += 2.0
	# The practice rings' stretch and the start have no features.
	for r in t.ramps:
		var ra: Array = r
		if not _clear(float(ra[0]), float(ra[0]) + float(ra[1]), L):
			why.append("ramp in the start / practice stretch")
	for p in t.pads:
		var pa: Array = p
		if float(pa[0]) + float(pa[1]) > L - START_BACK - 4.0:
			why.append("boost arrow on the grid")
		var pisl := t.island_at(float(pa[0]) + 2.5)
		if absf(float(pa[2])) + float(pa[3]) > t.wall_at(float(pa[0])) - 0.3 or (pisl > 0.0 and pisl > absf(float(pa[2])) - float(pa[3])):
			why.append("boost arrow off the road or on the island")
		for r in t.ramps:
			var ra: Array = r
			if _near(float(pa[0]), float(ra[0]) - 3.0, float(ra[0]) + float(ra[1]) + 3.0, L):
				why.append("boost arrow on a ramp")
	for sp in t.splits:
		var sa: Array = sp
		if not _clear(float(sa[0]), float(sa[0]) + float(sa[1]), L):
			why.append("split lanes in the start / practice stretch")
		for r in t.ramps:
			var ra: Array = r
			if fposmod(float(ra[0]) - float(sa[0]) + 20.0, L) < float(sa[1]) + 40.0:
				why.append("ramp too near the split lanes")
		var lane := Track.WIDTH * 0.5 + float(sa[2]) - float(sa[3])
		if lane < Track.WIDTH * 0.6:
			why.append("split lane too narrow (%.1f m)" % lane)
	for b in t.boxes.size():
		var r: Array = t.locate(t.boxes[b], -1)
		var bs: float = r[1]
		var bl: float = r[2]
		if absf(bl) > t.wall_at(bs) - 1.0 or (t.island_at(bs) > 0.0 and absf(bl) < t.island_at(bs) + 1.0):
			why.append("? box off the road or on the island")
			break
		if t.ramp_height(bs, bl) > 0.0 or bs < 16.0 or bs > L - START_BACK - 4.0:
			why.append("? box on a ramp or by the start")
			break
	# Ramps: every jump lands on the road at any speed (no wall or island in the air, no landing on a ramp).
	for r in t.ramps:
		var ra: Array = r
		var lip := float(ra[0]) + float(ra[1])
		for v in [6.0, 10.0, 14.0, 18.0, 22.0, 26.0, KART_TOP]:
			for lf in [-1.0, 0.0, 1.0]:
				var lat0 := float(ra[3]) + float(ra[4]) * float(lf) * 0.9
				var res := _flight(t, lip, lat0, float(v), float(ra[2]))
				if res != "":
					why.append("jump at s=%.0f, %.0f m/s, lat %.1f: %s" % [lip, v, lat0, res])
					break
			if not why.is_empty() and str(why[-1]).begins_with("jump"):
				break
	# No prop spot inside the walls (a hidden wall): the same spot finder the scenery uses.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for p in t._side_spots(rng, 60, 0.5, 9.0):
		var lr: Array = t.locate(p, -1)
		if absf(float(lr[2])) < t.wall_at(float(lr[1])) + 0.3:
			why.append("a prop spot on the road")
			break


## Clear of the start (grid + line) and the practice rings.
static func _clear(a: float, b: float, L: float, pad: float = 0.0) -> bool:
	return a >= PRACTICE_END + pad and b <= L - START_BACK - pad


static func _near(s: float, a: float, b: float, L: float) -> bool:
	return fposmod(s - a, L) <= b - a


## Fly a kart off a ramp lip in a straight line (what kart.gd does, steering aside). "" = a fair landing.
static func _flight(t: Track, lip: float, lat0: float, v: float, rh: float) -> String:
	var pa: Array = t.point_at(lip, lat0)
	var pos: Vector3 = pa[0]
	var yaw: float = pa[1]
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var vy := 5.0 + v * 0.12
	var hint := int(pa[2])
	var dt := 1.0 / 60.0
	var air := 0.0
	while air < 2.0:
		air += dt
		pos += fwd * v * dt
		vy -= 24.0 * dt
		pos.y += vy * dt
		var r: Array = t.locate(pos, hint)
		hint = int(r[0])
		var s: float = r[1]
		var lat: float = r[2]
		if absf(lat) > t.wall_at(s) - 0.65:
			return "flies into the wall"
		var isl := t.island_at(s)
		if isl > 0.0 and absf(lat) < isl + 0.65:
			return "flies into the island"
		var g := t.ground(s, lat, float(r[3]))
		if pos.y <= g and air > 0.1:
			if t.ramp_height(s, lat) > 0.0:
				return "lands on a ramp"
			if air > 1.3:
				return "too long in the air (%.1f s)" % air
			return ""
	return "never lands"
