extends RefCounted
## PAPER PLANES sky generator: a seeded flight = a list of hoop FORMATIONS (scatter, arc, zigzag, ring,
## chain, tiny, plus grumpy clouds and Gust's golden hoop in later chapters). The same seed and
## chapter always give the same flight (every machine can build the clouds itself from the seed).
## check() is the validator (tests/paper_planes_sky_test.gd runs it over many seeds): every hoop is
## inside the sky the TV planes can fly in and the VR player can throw to, hoops never overlap, chains
## can be flown in order, clouds never cover a hoop or block every way into it.

const Seeded := preload("res://core/seeded.gd")

# Hoop kinds (also used by main.gd and meshes.gd).
const PLAIN := 0
const RAINBOW := 1
const CHAIN := 2
const TINY := 3
const GATE := 4
const GOLD := 5
const POINTS := [1, 3, 1, 2, 0, 5]

## Hoop homes stay inside this box (the old game's box: the VR player can reach every part of it).
const BOX_MIN := Vector3(-6.5, 1.7, -10.0)
const BOX_MAX := Vector3(6.5, 4.8, 1.8)
## The TV planes are steered back inside this (main.gd _fly_local).
const FLY_MIN := Vector3(-13.5, 1.0, -20.5)
const FLY_MAX := Vector3(13.5, 9.5, 10.5)
## Drift of a hoop around its home per unit of amp (main.gd _move_hoop uses the same numbers).
const DRIFT := Vector3(1.3, 0.45, 0.9)
const VR_HEAD := Vector3(0.0, 1.6, 5.0)
const VR_REACH := 17.0
const MIN_GAP := 3.2  ## hoop centres at least this far apart (plus drift)
const CLOUD_R := 1.25  ## a grumpy cloud's bump radius
const TURN_R := 3.5  ## a TV plane's turning radius (FLY_SPEED / TURN_RATE)
const FORMATIONS := 14
const GOLD_PATH := {"center": Vector3(0.0, 3.4, -4.5), "rx": 5.0, "rz": 4.2, "ry": 0.9, "speed": 0.32}

## Formation weights per chapter: [scatter, arc, zigzag, ring, chain, tiny].
const WEIGHTS := [
	[3, 3, 2, 1, 0, 0],
	[2, 2, 2, 2, 3, 0],
	[2, 2, 2, 2, 2, 3],
	[2, 2, 2, 2, 2, 2],
	[2, 2, 2, 2, 2, 2],
	[2, 2, 2, 2, 2, 2],
]
const SHAPES := ["scatter", "arc", "zigzag", "ring", "chain", "tiny"]


static func features(chapter: int) -> Dictionary:
	return {"chains": chapter >= 1, "tiny": chapter >= 2, "clouds": chapter >= 3, "gold": chapter >= 4}


## A whole flight. opts: lucky (more rainbows). Returns {seed, chapter, formations: [{shape, hoops:
## [{pos, kind, ci, amp, phase, yaw}], clouds: [Vector3], gold: bool}]}.
static func flight(seed_value: int, chapter: int, opts: Dictionary = {}) -> Dictionary:
	var r := Seeded.rng(seed_value, "sky%d" % chapter)
	var feats := features(chapter)
	var lucky := bool(opts.get("lucky", false))
	var forms: Array = []
	for i in FORMATIONS:
		var shape := "arc" if i == 0 else String(SHAPES[Seeded.weighted(r, WEIGHTS[clampi(chapter, 0, WEIGHTS.size() - 1)])])
		var f := _formation(r, shape, i == 0)
		if f.is_empty():
			f = _formation(r, "scatter", false)
		# Rainbows: one now and then (two with the RAINBOWS breeze).
		var rainbows := (1 if r.randf() < 0.45 else 0) + (1 if lucky else 0)
		var plain: Array = []
		for k in (f.hoops as Array).size():
			if int(f.hoops[k].kind) == PLAIN:
				plain.append(k)
		plain = Seeded.shuffled(r, plain)
		for k in mini(rainbows, plain.size()):
			f.hoops[plain[k]].kind = RAINBOW
		f["gold"] = feats.gold and i > 0 and r.randf() < 0.6
		f["clouds"] = _clouds(r, f.hoops, 1 + r.randi() % 3, f.gold) if feats.clouds and i > 0 else []
		forms.append(f)
	return {"seed": seed_value, "chapter": chapter, "formations": forms}


static func _hoop(pos: Vector3, kind: int, ci: int, amp: float, phase: float, yaw: float) -> Dictionary:
	return {"pos": pos, "kind": kind, "ci": ci, "amp": amp, "phase": phase, "yaw": yaw}


## The yaw that faces a hoop at `pos` towards the VR player (plus a little turn).
static func yaw_to_vr(pos: Vector3, turn: float = 0.0) -> float:
	var d := VR_HEAD - pos
	return atan2(d.x, d.z) + turn


static func _in_box(p: Vector3) -> bool:
	return p.x >= BOX_MIN.x and p.x <= BOX_MAX.x and p.y >= BOX_MIN.y and p.y <= BOX_MAX.y and p.z >= BOX_MIN.z and p.z <= BOX_MAX.z


static func _spaced(p: Vector3, hoops: Array, gap: float = MIN_GAP + 0.3) -> bool:
	for h in hoops:
		if (h.pos as Vector3).distance_to(p) < gap:
			return false
	return true


static func _rand_in_box(r: RandomNumberGenerator) -> Vector3:
	return Vector3(r.randf_range(BOX_MIN.x, BOX_MAX.x), r.randf_range(BOX_MIN.y, BOX_MAX.y), r.randf_range(BOX_MIN.z, BOX_MAX.z))


## One formation, or {} when the shape didn't fit after a few tries.
static func _formation(r: RandomNumberGenerator, shape: String, first: bool) -> Dictionary:
	for attempt in 24:
		var hoops: Array = []
		var ok := true
		match shape:
			"scatter", "tiny":
				var n := 5
				var tiny := 3 if shape == "tiny" else 0
				for k in n:
					var placed := false
					for t in 30:
						var p := _rand_in_box(r)
						if _spaced(p, hoops):
							var kind := TINY if k < tiny else PLAIN
							hoops.append(_hoop(p, kind, r.randi() % 6, r.randf_range(0.9, 1.25) if kind == TINY else r.randf_range(0.6, 1.0),
								r.randf() * TAU, yaw_to_vr(p, r.randf_range(-0.4, 0.4))))
							placed = true
							break
					if not placed:
						ok = false
						break
			"arc":
				var n := 4
				var c := Vector3(r.randf_range(-0.8, 0.8), r.randf_range(2.0, 3.6), r.randf_range(-6.5, -3.5))
				var w := r.randf_range(10.6, 12.0)
				var bend := r.randf_range(-2.6, 2.6)
				var tilt := r.randf_range(-0.12, 0.12)
				if first:
					c = Vector3(0.0, 2.2, -1.8)
					w = 10.6
					bend = 1.5
					tilt = 0.0
				for k in n:
					var u := -1.0 + 2.0 * float(k) / float(n - 1)
					var p := c + Vector3(u * w * 0.5, u * w * 0.5 * tilt, bend * (u * u - 0.5))
					hoops.append(_hoop(p, PLAIN, k, 0.25 if first else r.randf_range(0.3, 0.6), r.randf() * TAU, yaw_to_vr(p)))
			"zigzag":
				var n := 5
				var x0 := r.randf_range(2.6, 3.4) * (1.0 if r.randf() < 0.5 else -1.0)
				var z0 := r.randf_range(0.0, 1.6)
				var dz := r.randf_range(2.2, 2.5)
				for k in n:
					var p := Vector3(x0 * (1.0 if k % 2 == 0 else -1.0), 2.0 + 1.6 * (0.5 + 0.5 * sin(k * 1.3 + r.randf())), z0 - dz * k)
					hoops.append(_hoop(p, PLAIN, k, r.randf_range(0.3, 0.5), r.randf() * TAU, yaw_to_vr(p, r.randf_range(-0.2, 0.2))))
			"ring":
				var n := 6
				var rad := r.randf_range(4.3, 4.6)
				var c := Vector3(r.randf_range(-1.2, 1.2), r.randf_range(2.4, 3.6), r.randf_range(-5.0, -3.8))
				var a0 := r.randf() * TAU
				for k in n:
					var a := a0 + TAU * float(k) / float(n)
					var p := c + Vector3(cos(a) * rad, sin(a * 2.0) * 0.4, sin(a) * rad)
					var tangent := atan2(-sin(a), cos(a))  # the yaw whose normal runs along the ring
					var to_vr := yaw_to_vr(p)
					if absf(wrapf(tangent - to_vr, -PI, PI)) > PI * 0.5:
						tangent += PI  # hoops fly both ways: take the side nearer the VR player
					var yaw := lerp_angle(tangent, to_vr, 0.55)
					hoops.append(_hoop(p, PLAIN, k, r.randf_range(0.2, 0.4), r.randf() * TAU, yaw))
			"chain":
				var n := 3 + r.randi() % 2
				var p := Vector3(r.randf_range(-5.5, 5.5), r.randf_range(1.8, 4.2), r.randf_range(-1.0, 1.6))
				var heading := r.randf_range(-0.5, 0.5)  # yaw of travel (0 = away from the VR player, -Z)
				for k in n:
					# A chain hoop faces along the way it's flown (its normal along the path).
					hoops.append(_hoop(p, CHAIN, k + 1, 0.2, r.randf() * TAU, heading + PI))
					heading += r.randf_range(-0.55, 0.55)
					var step := r.randf_range(4.4, 5.2)
					p = p + Vector3(-sin(heading) * step, r.randf_range(-0.6, 0.6), -cos(heading) * step)
					p.y = clampf(p.y, 1.8, 4.4)
				# Plus two plain hoops off to the side.
				for k in 2:
					for t in 30:
						var q := _rand_in_box(r)
						if _spaced(q, hoops):
							hoops.append(_hoop(q, PLAIN, r.randi() % 6, r.randf_range(0.5, 0.9), r.randf() * TAU, yaw_to_vr(q, r.randf_range(-0.4, 0.4))))
							break
		if ok and _fits(hoops):
			return {"shape": shape, "hoops": hoops}
	return {}


## Every hoop in the box and spaced apart.
static func _fits(hoops: Array) -> bool:
	for i in hoops.size():
		if not _in_box(hoops[i].pos):
			return false
		for j in i:
			if (hoops[i].pos as Vector3).distance_to(hoops[j].pos) < MIN_GAP + _drift_len(hoops[i]) * 0.5 + _drift_len(hoops[j]) * 0.5:
				return false
	return true


static func _drift_len(h: Dictionary) -> float:
	return DRIFT.length() * float(h.amp) * 0.5


static func _clouds(r: RandomNumberGenerator, hoops: Array, n: int, gold: bool) -> Array:
	var out: Array = []
	for k in n:
		for t in 40:
			var c := Vector3(r.randf_range(-7.0, 7.0), r.randf_range(2.0, 5.5), r.randf_range(-11.0, 0.5))
			if _cloud_ok(c, hoops, out) and (not gold or _gold_clear(c)):
				out.append(c)
				break
	return out


static func _cloud_ok(c: Vector3, hoops: Array, clouds: Array) -> bool:
	for o in clouds:
		if (o as Vector3).distance_to(c) < CLOUD_R * 3.0:
			return false
	for h in hoops:
		if _cloud_reasons(c, h).size() > 0:
			return false
	return true


## Why cloud `c` is unfair for hoop `h` (empty = fine).
static func _cloud_reasons(c: Vector3, h: Dictionary) -> Array:
	var out: Array = []
	var p: Vector3 = h.pos
	var room := CLOUD_R + _drift_len(h) + 1.4
	if c.distance_to(p) < room:
		out.append("cloud too close to a hoop")
	# The VR player's throw line must stay clear.
	if _seg_dist(VR_HEAD, p, c) < CLOUD_R + 0.5:
		out.append("cloud blocks the VR throw to a hoop")
	# At least one side of the hoop must have a clear run-up for the TV planes.
	var n := Vector3(sin(float(h.yaw)), 0.0, cos(float(h.yaw)))
	var front := _seg_dist(p + n * 4.0, p, c) >= CLOUD_R + 0.4
	var back := _seg_dist(p - n * 4.0, p, c) >= CLOUD_R + 0.4
	if not front and not back:
		out.append("cloud blocks both ways into a hoop")
	return out


static func _seg_dist(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (a + ab * t).distance_to(p)


static func _gold_clear(c: Vector3) -> bool:
	for k in 32:
		if gold_pos(TAU / float(GOLD_PATH.speed) * float(k) / 32.0).distance_to(c) < CLOUD_R + 1.2:
			return false
	return true


## Where Gust's golden hoop is at time t (it loops an ellipse inside the sky).
static func gold_pos(t: float) -> Vector3:
	var a := t * float(GOLD_PATH.speed)
	var c: Vector3 = GOLD_PATH.center
	return c + Vector3(sin(a) * float(GOLD_PATH.rx), sin(a * 2.0) * float(GOLD_PATH.ry), cos(a) * float(GOLD_PATH.rz))


## The three pick-a-breeze gates (same spots every time).
static func gate_positions() -> Array:
	return [Vector3(-4.6, 3.0, -3.0), Vector3(0.0, 3.6, -5.0), Vector3(4.6, 3.0, -3.0)]


# --- Validator ------------------------------------------------------------------------------

## Reasons a flight is not fair / completable (empty = good).
static func check(fl: Dictionary) -> Array:
	var out: Array = []
	var forms: Array = fl.get("formations", [])
	if forms.size() != FORMATIONS:
		out.append("has %d formations" % forms.size())
	var chap := int(fl.get("chapter", 0))
	var feats := features(chap)
	for fi in forms.size():
		var f: Dictionary = forms[fi]
		var hoops: Array = f.hoops
		if hoops.size() < 4:
			out.append("formation %d has only %d hoops" % [fi, hoops.size()])
		for i in hoops.size():
			var h: Dictionary = hoops[i]
			var p: Vector3 = h.pos
			var reach := DRIFT * float(h.amp)
			for corner in [p - reach, p + reach]:
				if corner.x < FLY_MIN.x or corner.x > FLY_MAX.x or corner.y < FLY_MIN.y or corner.y > FLY_MAX.y or corner.z < FLY_MIN.z or corner.z > FLY_MAX.z:
					out.append("formation %d hoop %d drifts out of the TV planes' sky" % [fi, i])
			if not _in_box(p):
				out.append("formation %d hoop %d is outside the hoop box %s" % [fi, i, str(p)])
			if p.distance_to(VR_HEAD) > VR_REACH:
				out.append("formation %d hoop %d is out of the VR player's reach" % [fi, i])
			if p.z > VR_HEAD.z - 3.0:
				out.append("formation %d hoop %d is too close to the VR player" % [fi, i])
			# A VR plane must be able to go through: the hoop must not be edge-on to the thrower.
			var n := Vector3(sin(float(h.yaw)), 0.0, cos(float(h.yaw)))
			var to_vr := (VR_HEAD - p).normalized()
			if absf(n.dot(to_vr)) < 0.3 and int(h.kind) != CHAIN:
				out.append("formation %d hoop %d is edge-on to the VR player" % [fi, i])
			if int(h.kind) == TINY and not feats.tiny:
				out.append("tiny hoop before chapter 3")
			if int(h.kind) == CHAIN and not feats.chains:
				out.append("chain hoop before chapter 2")
			for j in i:
				var gap := p.distance_to(hoops[j].pos)
				if gap < MIN_GAP:
					out.append("formation %d hoops %d and %d overlap (%.1f m)" % [fi, i, j, gap])
		# Chains: numbered 1..n in order, each next hoop ahead of the last one's facing and not too far.
		var chain: Array = []
		for h in hoops:
			if int(h.kind) == CHAIN:
				chain.append(h)
		if not chain.is_empty():
			if chain.size() < 3:
				out.append("formation %d chain has %d hoops" % [fi, chain.size()])
			for k in chain.size():
				if int(chain[k].ci) != k + 1:
					out.append("formation %d chain numbers out of order" % fi)
				if k > 0:
					var a: Dictionary = chain[k - 1]
					var d: Vector3 = (chain[k].pos as Vector3) - (a.pos as Vector3)
					var fwd := Vector3(sin(float(a.yaw)), 0.0, cos(float(a.yaw)))  # a chain hoop's normal points along the path
					var flat := Vector3(d.x, 0.0, d.z)
					if flat.length() > 8.0 or flat.length() < TURN_R:
						out.append("formation %d chain step %d is %.1f m" % [fi, k, flat.length()])
					if fwd.angle_to(flat.normalized()) > 0.75:
						out.append("formation %d chain turns too sharply at %d" % [fi, k])
		for c in f.get("clouds", []):
			if not feats.clouds:
				out.append("cloud before chapter 4")
			for h in hoops:
				for why in _cloud_reasons(c, h):
					out.append("formation %d: %s" % [fi, why])
		if bool(f.get("gold", false)):
			if not feats.gold:
				out.append("gold hoop before chapter 5")
			for k in 32:
				var gp := gold_pos(TAU / float(GOLD_PATH.speed) * float(k) / 32.0)
				if gp.x < FLY_MIN.x or gp.x > FLY_MAX.x or gp.y < FLY_MIN.y or gp.y > FLY_MAX.y or gp.z < FLY_MIN.z or gp.z > VR_HEAD.z - 3.0 or gp.distance_to(VR_HEAD) > VR_REACH:
					out.append("formation %d gold hoop path leaves the sky" % fi)
					break
			for c in f.get("clouds", []):
				if not _gold_clear(c):
					out.append("formation %d gold path runs through a cloud" % fi)
	return out
