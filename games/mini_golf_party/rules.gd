extends RefCounted
## MINI GOLF PARTY: the rules as plain functions (no nodes), shared by the host, the TV machine,
## the HUD and the bots: score names, turn order, the scorecard, and the putt power curve.

const Defs := preload("res://games/mini_golf_party/defs.gd")


## What a finished hole is called. Returns {title, sub, style, level, stat}: level 0 = quiet,
## 1 = nice, 2 = birdie-class (fireworks), 3 = hole in one / eagle (the big show).
static func score_info(strokes: int, par: int, picked_up: bool = false) -> Dictionary:
	if picked_up:
		return {"title": "PICKED UP", "sub": "Fresh start on the next hole!", "style": "info", "level": 0, "stat": "pickups"}
	var d := strokes - par
	if strokes == 1:
		return {"title": "HOLE IN ONE!", "sub": "Unbelievable!", "style": "victory", "level": 3, "stat": "holes_in_one"}
	if d <= -3:
		return {"title": "ALBATROSS!", "sub": "%d under par!" % -d, "style": "victory", "level": 3, "stat": "eagles"}
	if d == -2:
		return {"title": "EAGLE!", "sub": "Two under par!", "style": "victory", "level": 3, "stat": "eagles"}
	if d == -1:
		return {"title": "BIRDIE!", "sub": "One under par!", "style": "level", "level": 2, "stat": "birdies"}
	if d == 0:
		return {"title": "PAR!", "sub": "Right on target", "style": "default", "level": 1, "stat": "pars"}
	if d == 1:
		return {"title": "IN THE HOLE!", "sub": "Bogey - so close!", "style": "info", "level": 0, "stat": "bogeys"}
	return {"title": "IN THE HOLE!", "sub": "%d strokes - you did it!" % strokes, "style": "info", "level": 0, "stat": "bogeys"}


## "E" for even, "+2", "-1".
static func vs_par_text(diff: int) -> String:
	if diff == 0:
		return "E"
	return ("+%d" % diff) if diff > 0 else str(diff)


## Who putts next: fewest strokes on this hole first (everyone keeps pace), then the ball farthest
## from the cup (golf's "away" rule), then the honour order (best on the last hole goes first).
## players: slots in the hole; strokes: slot -> int; done: slot -> score (finished); dist: slot ->
## metres to the cup; skip: slots that can't play right now (away). Returns -1 if nobody is left.
static func pick_next(players: Array, strokes: Dictionary, done: Dictionary, dist: Dictionary, honor: Array, skip: Array = []) -> int:
	var best := -1
	var best_key := Vector3(INF, INF, INF)
	for s in players:
		var slot := int(s)
		if done.has(slot) or skip.has(slot):
			continue
		var st := int(strokes.get(slot, 0))
		var hi := honor.find(slot)
		var key := Vector3(float(st), -float(dist.get(slot, 0.0)) if st > 0 else 0.0, float(hi if hi >= 0 else 99 + slot))
		if key.x < best_key.x or (key.x == best_key.x and (key.y < best_key.y - 0.01 or (absf(key.y - best_key.y) <= 0.01 and key.z < best_key.z))):
			best_key = key
			best = slot
	return best


## Honour order for the next hole: lowest score on the last hole first, ties keep the old order.
static func honor_order(prev: Array, scores: Dictionary) -> Array:
	var out := prev.duplicate()
	out.sort_custom(func(a: Variant, b: Variant) -> bool:
		var sa := int(scores.get(int(a), 99))
		var sb := int(scores.get(int(b), 99))
		if sa != sb:
			return sa < sb
		return prev.find(a) < prev.find(b))
	return out


# --- Power curve ---------------------------------------------------------------------------------

## TV power meter 0..1 -> ball speed (m/s). A gentle curve: small taps stay small.
static func speed_for_power(p: float) -> float:
	return lerpf(Defs.MIN_PUTT, Defs.MAX_PUTT, pow(clampf(p, 0.0, 1.0), 1.35))


## Inverse of speed_for_power (bots, the auto-putt).
static func power_for_speed(v: float) -> float:
	var t := clampf((v - Defs.MIN_PUTT) / (Defs.MAX_PUTT - Defs.MIN_PUTT), 0.0, 1.0)
	return pow(t, 1.0 / 1.35)


## How far a ball rolls on flat felt from speed v0 (m) until it slows to v_end.
static func roll_distance(v0: float, v_end: float = 0.0) -> float:
	var v := v0
	var d := 0.0
	var dt := 1.0 / 120.0
	var guard := 0
	while v > maxf(v_end, Defs.STOP_SPEED) and guard < 6000:
		d += v * dt
		v -= (Defs.ROLL_DECEL + Defs.DRAG * v) * dt
		guard += 1
	return d


## Speed needed to roll `d` metres on flat felt and still have v_end left, climbing `rise` metres.
static func speed_for_distance(d: float, v_end: float = 0.0, rise: float = 0.0) -> float:
	var lo := 0.05
	var hi := 12.0
	for i in 32:
		var mid := (lo + hi) * 0.5
		if roll_distance(mid, v_end) < d:
			lo = mid
		else:
			hi = mid
	var v := hi
	if rise > 0.0:
		v = sqrt(v * v + 2.0 * Defs.GRAVITY * rise * 1.08)
	return v


# --- Scorecard ------------------------------------------------------------------------------------

## A fresh scorecard row: -1 = not played (yet).
static func empty_row(holes: int) -> Array:
	var r: Array = []
	for i in holes:
		r.append(-1)
	return r


## Totals for one card row: {strokes, par, diff, played}.
static func row_total(row: Array, pars: Array) -> Dictionary:
	var strokes := 0
	var par := 0
	var played := 0
	for i in mini(row.size(), pars.size()):
		var s := int(row[i])
		if s > 0:
			strokes += s
			par += int(pars[i])
			played += 1
	return {"strokes": strokes, "par": par, "diff": strokes - par, "played": played}


## Standings rows for the HUD / results: [{id, name, color, score (vs par), strokes, played, sub}],
## best first (lowest vs par; then fewest strokes; then most holes played).
static func standings(card: Dictionary, pars: Array, names: Dictionary, colors: Dictionary) -> Array:
	var rows: Array = []
	for k in card:
		var row: Array = card[k]
		var t := row_total(row, pars)
		var slot := int(k)
		rows.append({"id": slot, "name": String(names.get(str(slot), "P%d" % (slot + 1))),
			"color": colors.get(slot, Color.WHITE), "score": int(t.diff), "strokes": int(t.strokes),
			"played": int(t.played), "sub": "%d strokes" % int(t.strokes)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.played) > 0 and int(b.played) == 0:
			return true
		if int(b.played) > 0 and int(a.played) == 0:
			return false
		if int(a.score) != int(b.score):
			return int(a.score) < int(b.score)
		if int(a.strokes) != int(b.strokes):
			return int(a.strokes) < int(b.strokes)
		return int(a.id) < int(b.id))
	var rank := 0
	var prev := Vector2i(-9999, -9999)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var key := Vector2i(int(r.score), int(r.strokes))
		if key != prev:
			rank = i + 1
			prev = key
		r["rank"] = rank
	return rows
