extends RefCounted
## GIANT'S TABLE second pass (pure data + small functions; tests/giants_table_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked once a session on the pick orbs after the
##             practice: how many goblins a wave sends and how fast (plan(): RaidGen.plan with a goblin or two fewer
##             and longer gaps on GENTLE, two more and shorter gaps on HARD - every plan still passes RaidGen.check,
##             the slow-kid fairness proof), how often the goblins play a TRICK, how long it is told first and how big.
##   GIFTS     SPARKY'S GIFTS, three offered on the pick orbs in every break from wave 2: BIG FIRE (the fire fills up
##             and burns big), EMBER SHIELD (a glowing dome bounces the first goblins back), KNIGHT HELPERS (three toy
##             knights guard the fire and bonk goblins dizzy), SLEEPY DUST (goblins walk slowly) and BIG HANDS (the
##             Giant reaches further) - the last two open as Sparky's table treasures grow. A gift lasts one wave.
##   TRICKS    the goblins' tricks, told by steady core/warn_rings.gd shapes on the table (each its own colour), never
##             in the first waves, never two at once, never in a wave's first seconds:
##               GOO       a pink circle: a goblin catapult on the rim flings a goo ball there. Knights inside get a
##                         bump; goblins that walk into the goo get stuck in it. The Giant can CATCH the ball!
##               BARREL    an orange band across the table: goblins roll a barrel along it. Knights in the way get a
##                         bump, goblins get bowled over dizzy. The Giant can GRAB the barrel!
##             Tricks never steal embers, so the raid's fairness proof (RaidGen.check) still holds; problems() proves
##             each trick is told long enough for a small knight to walk out, lands on open ground (never the fire,
##             a cottage or the river) and a barrel's band misses the fire and the cottages.
##   SEASONS   the table is dressed for the season (Seeded.season, season.gd): a seasonal tablecloth hangs off the
##             rim, a centrepiece wreath rings Sparky's fire and big seasonal things stand in the room. No rain and
##             nothing falls from the sky (David). The season leans the tricks (autumn barrels of apples ...).
##   TREASURES every TREASURE_EVERY waves cleared (saved, for good) a new treasure joins the rim between the lantern
##             posts (treasures.gd): a candle, a teacup, a cupcake ... The village houses never grow (David).
##   PICK ROW  three orbs float in front of the Giant's seat (an arm's reach away for the VR Giant, over open
##             ground): the VR Giant reaches into one on purpose (a hand moves in and stays a moment), the flat Giant
##             hovers its hand over one, a knight walks under one. Nobody in time = the middle (it glows).

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const RaidGen := preload("res://games/giants_table/raidgen.gd")
const W := preload("res://games/giants_table/world.gd")

## more: goblins added (+) or taken away (-) per wave; gap: the gaps between goblins times this; every: seconds
## between tricks; warn: seconds told first; goo_r: a goo circle's radius; barrel_w: half a barrel band's width;
## bump: a trick's bump on a knight (of KnightScript.MAX_HP 100); first: the first wave with tricks.
const MODES := {
	"gentle": {"more": -1, "gap": 1.2, "every": 34.0, "warn": 3.6, "goo_r": 2.0, "barrel_w": 0.9, "bump": 0.0, "first": 3},
	"brave": {"more": 0, "gap": 1.0, "every": 26.0, "warn": 3.1, "goo_r": 2.4, "barrel_w": 1.1, "bump": 5.0, "first": 2},
	"hard": {"more": 2, "gap": 0.88, "every": 19.0, "warn": 2.6, "goo_r": 2.8, "barrel_w": 1.3, "bump": 10.0, "first": 2},
}
const MIN_WARN := 2.2
const MAX_BUMP := 15.0  # a trick alone never puts a knight down
const KNIGHT_SPEED := 4.6  # == knight.gd SPEED (the test checks)
const KNIGHT_R := 0.35  # == knight.gd radius
const KID_SHARE := 0.6  # a small kid moves a knight at this share of full speed
const REACT := 0.6  # seconds to notice a tell and start walking
const FIRST_T := 8.0  # no trick in a wave's first seconds
const SHORT_FIRST := 3.0  # (bots: GT_TRICKS_NOW)
const MIN_GAP := 10.0  # seconds between two tricks' tells
const AFTER := 3.3  # seconds a trick lasts after its tell (the goo stays / the barrel rolls)
const WINDOW_PAD := 12.0  # tricks fit in the goblins' sending time + this
const GOO_FLY := 1.5  # the goo ball's flight (it lands as the tell ends)
const GOO_TOP := 9.0  # how high it arcs
const GOO_DIZZY := 2.5
const BARREL_SPEED := 9.0
const BARREL_R := 0.75  # the barrel's radius (it rolls on the table, a knight is ~1 tall)
const BARREL_D := Vector2(7.0, 10.5)  # the band passes this far from the fire (outside the village)
const BARREL_DIZZY := 2.0
const GOO_COLOR := Color(1.0, 0.3, 0.85)  # goo pink
const BARREL_COLOR := Color(1.0, 0.42, 0.0)  # barrel orange
const KINDS: Array[String] = ["goo", "barrel"]
const KIND_PICS := {"goo": "gooball", "barrel": "barrel"}
const KIND_NAMES := {"goo": "GOO BALL!", "barrel": "BARREL!"}
## Season -> trick weights (goo, barrel), a picture and Sparky's line.
const SEASONS := {
	"spring": {"weights": [1.0, 1.0], "pic": "daisy", "line": "Spring flowers!"},
	"summer": {"weights": [1.4, 0.8], "pic": "sunflower", "line": "Sunny summer!"},
	"autumn": {"weights": [0.7, 1.5], "pic": "pumpkin", "line": "Cosy autumn!"},
	"winter": {"weights": [1.0, 1.0], "pic": "snowflake", "line": "Snowy winter!"},
}
## Sparky's gifts: id, name, picture, a short line, a colour, treasures needed.
const GIFTS: Array[Dictionary] = [
	{"id": "bigfire", "name": "BIG FIRE", "pic": "bigfire", "line": "A big warm fire!", "color": Color(1.0, 0.5, 0.15), "unlock": 0},
	{"id": "shield", "name": "EMBER SHIELD", "pic": "shieldbubble", "line": "A shield for my embers!", "color": Color(0.35, 0.85, 1.0), "unlock": 0},
	{"id": "helpers", "name": "KNIGHT HELPERS", "pic": "knight", "line": "Little helpers!", "color": Color(0.85, 0.88, 0.95), "unlock": 0},
	{"id": "sleepy", "name": "SLEEPY DUST", "pic": "snoozy", "line": "Sleepy goblins!", "color": Color(0.75, 0.55, 1.0), "unlock": 2},
	{"id": "bighands", "name": "BIG HANDS", "pic": "biggloves", "line": "Giant giant hands!", "color": Color(0.4, 1.0, 0.5), "unlock": 4},
]
const BIGFIRE_FLAMES := 1.5  # BIG FIRE: the flames this much bigger (and the fire fills up)
const SHIELD_HITS := 3  # EMBER SHIELD: goblins bounced before it pops
const SHIELD_R := 2.3
const HELPERS := 3  # KNIGHT HELPERS round the fire
const HELPER_RING := 2.4
const HELPER_ANGLES: Array[float] = [0.52, 1.75, 3.67]  # (clear of the well, the market stall and the bakery spots)
const HELPER_R := 1.7  # a goblin this near a helper gets bonked
const HELPER_CD := 2.2
const HELPER_DIZZY := 2.2
const SLEEPY := 0.72  # SLEEPY DUST: goblins walk at this share
const BIG_REACH := 1.5  # BIG HANDS: the Giant's grab reach times this
const BIG_HAND := 1.35  # ... and the hands look this big
## Sparky's table treasures: one every TREASURE_EVERY waves cleared, between the lantern posts on the rim.
const TREASURE_EVERY := 3
const TREASURES: Array[String] = ["candle", "teacup", "cupcake", "drum", "flowerpot", "bell", "lollipop", "boat", "jar", "cocoamug"]
## The pick row: three orbs in front of the Giant's seat (+z), over open ground on the Giant's side of the table.
## World units (20 = 1 m for the VR Giant): the orbs float ~22 cm over the table, ~42 cm in front of the eyes.
const ROW_X: Array[float] = [-5.6, -1.0, 2.6]  # (between the trees in front of the Giant: open ground under each)
const ROW_Z := 11.0
const ROW_Y := 4.5  # above the ground under the orb
const ORB_SCALE := 2.3  # 0.6 * 2.3 = 1.4 units (7 cm) radius: a modest glass ball in VR, easy on a TV / Deck
const HAND_R := 0.25  # a VR grab point this near an orb's edge is in it
const DWELL := 0.35  # seconds a hand must stay in an orb (a sweep past never picks)
const FLAT_R := 1.6  # the flat Giant's hovering hand this near an orb's middle (across) is in it
const TV_R := 1.4  # a knight this near an orb's middle (across) takes it
const TV_DWELL := 0.8  # (standing under it: a knight walking past under one never picks it)
const ROW_WAIT := {"mode": 20.0, "gift": 16.0}  # nobody took one: the middle
const EMPTY_WAIT := 8.0


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
	for k in ["more", "goo_r", "barrel_w", "bump"]:  # more is harder
		if not (float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k])):
			out.append("%s not gentle <= brave <= hard" % k)
	for k in ["gap", "every", "warn", "first"]:  # more is gentler
		if not (float(g[k]) >= float(b[k]) and float(b[k]) >= float(h[k])):
			out.append("%s not most on gentle" % k)
	if float(h.warn) < MIN_WARN:
		out.append("hard warns under %.1f s" % MIN_WARN)
	if float(h.every) < MIN_GAP + AFTER:
		out.append("hard: tricks closer than %.0f s" % (MIN_GAP + AFTER))
	if float(h.bump) > MAX_BUMP:
		out.append("hard: a trick's bump is too big")
	return out


# --- Wave plans by mode ---------------------------------------------------------------------------------------

## RaidGen.plan in a mode. GENTLE: `more` plain goblins fewer (never the first, at least 3 left) and longer gaps;
## HARD: plain goblins added on this wave's ladders (before the King) and shorter gaps, spread out again until the
## slow kid copes (RaidGen's own STRETCH), added goblins taken back if that isn't enough. Every result passes
## RaidGen.check (the same proof as BRAVE). The ladders never change (every machine builds them from the seed).
static func plan(raid_seed: int, n: int, extra: int = 0, solo: bool = true, mode: String = "brave") -> Dictionary:
	var p := RaidGen.plan(raid_seed, n, extra, solo)
	var m := mode_of(mode)
	p["mode"] = m
	if m == "brave":
		return p
	var md := mode_data(m)
	var spawns: Array = (p.spawns as Array).duplicate(true)
	var r := Seeded.rng(RaidGen.wave_seed(raid_seed, n), "mode %s %d%s" % [m, int(p.extra), "s" if solo else ""])
	if m == "gentle":
		# A plain goblin fewer (its gap goes to the next one: the wave takes as long, with fewer goblins), then longer
		# gaps - as long as the slow kid's proof still holds (a gap stretched past the wave's time limit squeezes
		# others), else the gentler of the two that does.
		for _k in -int(md.more):
			for i in range(spawns.size() - 1, 0, -1):
				if String(spawns[i][0]) == "goblin" and spawns.size() > 3:
					if i + 1 < spawns.size():
						spawns[i + 1][2] = snappedf(float(spawns[i + 1][2]) + float(spawns[i][2]), 0.01)
					spawns.remove_at(i)
					break
		for k in [float(md.gap), lerpf(1.0, float(md.gap), 0.5), 1.0]:
			var q := p.duplicate(true)
			q.spawns = spawns.duplicate(true)
			_scale_gaps(q.spawns, k)
			if RaidGen.check(q).is_empty():
				return q
		return p
	# HARD
	var lad: Array = p.ladders
	var king := not spawns.is_empty() and String(spawns[spawns.size() - 1][0]) == "king"
	for _k in int(md.more):
		var at := r.randi_range(1, spawns.size() - (1 if king else 0))
		var a := snappedf(fposmod(float(lad[r.randi() % lad.size()]) + r.randf_range(-RaidGen.JITTER, RaidGen.JITTER), TAU), 0.001)
		spawns.insert(at, ["goblin", a, snappedf(maxf(RaidGen.MIN_GAP, float(spawns[mini(at, spawns.size() - 1)][2])), 0.01), 0.0])
	_scale_gaps(spawns, float(md.gap))
	var added := int(md.more)
	while true:
		var q := p.duplicate(true)
		q.spawns = spawns.duplicate(true)
		for _t in RaidGen.STRETCH_TRIES:
			if RaidGen.check(q).is_empty():
				break
			for i in range(1, (q.spawns as Array).size()):
				q.spawns[i][2] = snappedf(float(q.spawns[i][2]) * RaidGen.STRETCH, 0.01)
		if RaidGen.check(q).is_empty():
			return q
		if added <= 0:
			break
		for i in range(spawns.size() - 1, 0, -1):  # one added goblin fewer and try again
			if String(spawns[i][0]) == "goblin":
				spawns.remove_at(i)
				break
		added -= 1
	return RaidGen.plan(raid_seed, n, extra, solo).merged({"mode": m}, true)  # (never reached in the tests)


## Gaps (after the first) times k, never under RaidGen.MIN_GAP, and the wave's sending time within
## RaidGen.MAX_SPAWN_SECS (a long GENTLE wave keeps its gaps just short of the limit).
static func _scale_gaps(spawns: Array, k: float) -> void:
	var total := 0.0
	for i in spawns.size():
		if i > 0:
			spawns[i][2] = snappedf(maxf(RaidGen.MIN_GAP, float(spawns[i][2]) * k), 0.01)
		total += float(spawns[i][2])
	if total > RaidGen.MAX_SPAWN_SECS - 1.0:
		var shrink := (RaidGen.MAX_SPAWN_SECS - 1.0) / total
		for i in range(1, spawns.size()):
			spawns[i][2] = snappedf(maxf(RaidGen.MIN_GAP, float(spawns[i][2]) * shrink - 0.01), 0.01)


## Seconds a plan takes to send all its goblins.
static func send_secs(p: Dictionary) -> float:
	var total := 0.0
	for s in p.spawns:
		total += float(s[2])
	return total


## Problems with GENTLE <= BRAVE <= HARD for one wave and party (fewer goblins and no quicker on GENTLE).
static func order_problems(raid_seed: int, n: int, extra: int, solo: bool) -> Array:
	var why: Array = []
	var g := plan(raid_seed, n, extra, solo, "gentle")
	var b := plan(raid_seed, n, extra, solo, "brave")
	var h := plan(raid_seed, n, extra, solo, "hard")
	var cg := (g.spawns as Array).size()
	var cb := (b.spawns as Array).size()
	var ch := (h.spawns as Array).size()
	if not (cg <= cb and cb <= ch):
		why.append("wave %d: goblins gentle %d / brave %d / hard %d" % [n, cg, cb, ch])
	var pg := float(cg) / maxf(1.0, send_secs(g))
	var pb := float(cb) / maxf(1.0, send_secs(b))
	if pg > pb * 1.01 + 0.001:  # (1 %: gaps are snapped to 0.01 s)
		why.append("wave %d: gentle sends goblins quicker than brave (%.2f > %.2f a second)" % [n, pg, pb])
	for p in [g, h]:
		for w in RaidGen.check(p):
			why.append("%s: %s" % [p.mode, w])
	return why


# --- Tricks ---------------------------------------------------------------------------------------------------

## The goblins' tricks in wave n: [{t, kind, x, z, dx, dz, warn, r, cx, cz}] by time. t: wave seconds when the tell
## starts; it goes off at t + warn. goo: a circle at (x, z) of radius r, flung from the catapult at (cx, cz) on the
## rim. barrel: a band through (x, z) along (dx, dz), r = half its width. spec: {mode, season, send (the wave's
## sending seconds), first (bots: earlier)}.
static func tricks(raid_seed: int, n: int, spec: Dictionary) -> Array:
	var out: Array = []
	var m := mode_of(String(spec.get("mode", "brave")))
	var md := mode_data(m)
	if n < int(md.first) and not spec.has("first"):
		return out
	var weights: Array = season_data(String(spec.get("season", "spring"))).weights
	var r := Seeded.rng(RaidGen.wave_seed(raid_seed, n), "tricks %s" % m)
	var every := float(md.every)
	var t := float(spec.get("first", FIRST_T + r.randf_range(0.0, every * 0.3)))
	var last := float(spec.get("send", 60.0)) + WINDOW_PAD
	while t + float(md.warn) + AFTER <= last:
		var kind: String = KINDS[Seeded.weighted(r, weights)]
		for attempt in 24:
			var e := _make(r, kind, t, md)
			if _where_problem(e, out).is_empty():
				out.append(e)
				break
		t += every * r.randf_range(0.9, 1.25)
	return out


static func _make(r: RandomNumberGenerator, kind: String, t: float, md: Dictionary) -> Dictionary:
	var e := {"t": snappedf(t, 0.01), "kind": kind, "warn": float(md.warn), "cx": 0.0, "cz": 0.0}
	if kind == "goo":
		var rad := float(md.goo_r)
		var a := r.randf() * TAU
		var d := r.randf_range(W.FIRE_R + rad + 1.6, W.R - rad - 0.8)
		var ca := a + r.randf_range(-0.6, 0.6)
		e.merge({"x": snappedf(cos(a) * d, 0.01), "z": snappedf(sin(a) * d, 0.01), "dx": 0.0, "dz": 1.0, "r": rad,
			"cx": snappedf(cos(ca) * (W.EDGE - 0.3), 0.01), "cz": snappedf(sin(ca) * (W.EDGE - 0.3), 0.01)}, true)
	else:
		var a := r.randf() * TAU
		var dir := Vector2(cos(a), sin(a))
		var off := Vector2(-dir.y, dir.x) * r.randf_range(BARREL_D.x, BARREL_D.y)
		e.merge({"x": snappedf(off.x, 0.01), "z": snappedf(off.y, 0.01), "dx": snappedf(dir.x, 0.0001), "dz": snappedf(dir.y, 0.0001),
			"r": float(md.barrel_w)}, true)
	return e


## How far point p is from a barrel band's middle line (across it).
static func line_dist(e: Dictionary, p: Vector2) -> float:
	var dir := Vector2(float(e.dx), float(e.dz)).normalized()
	var q := p - Vector2(float(e.x), float(e.z))
	return absf(q.x * -dir.y + q.y * dir.x)


## Is point p (on the table) inside trick e's zone (pad: extra margin)?
static func inside(e: Dictionary, p: Vector2, pad: float = 0.0) -> bool:
	if String(e.kind) == "goo":
		return p.distance_to(Vector2(float(e.x), float(e.z))) < float(e.r) + pad
	return line_dist(e, p) < float(e.r) + pad


## Seconds after its tell starts that a trick is over.
static func span(e: Dictionary) -> float:
	return float(e.warn) + AFTER


## Half the barrel's roll (the band's half-length across the table, rim to rim).
static func barrel_half(e: Dictionary) -> float:
	var mid := Vector2(float(e.x), float(e.z))
	return sqrt(maxf(0.0, W.EDGE * W.EDGE - mid.length_squared()))


static func barrel_secs(e: Dictionary) -> float:
	return barrel_half(e) * 2.0 / BARREL_SPEED


## The barrel `s` seconds after it set off (on the table: the caller adds the ground height).
static func barrel_at(e: Dictionary, s: float) -> Vector3:
	var dir := Vector2(float(e.dx), float(e.dz)).normalized()
	var p := Vector2(float(e.x), float(e.z)) + dir * (-barrel_half(e) + 0.4 + clampf(s, 0.0, barrel_secs(e)) * BARREL_SPEED)
	return Vector3(p.x, 0.0, p.y)


## The goo ball `s` seconds into its flight (0..GOO_FLY), from the catapult to the circle's middle.
static func goo_at(e: Dictionary, s: float) -> Vector3:
	var k := clampf(s / GOO_FLY, 0.0, 1.0)
	var from := Vector3(float(e.cx), 1.2, float(e.cz))
	var to := Vector3(float(e.x), 0.3, float(e.z))
	return from.lerp(to, k) + Vector3.UP * (4.0 * k * (1.0 - k) * GOO_TOP)


static func _where_problem(e: Dictionary, earlier: Array) -> String:
	var at := Vector2(float(e.x), float(e.z))
	var rad := float(e.r)
	if not earlier.is_empty() and float(e.t) - float((earlier[earlier.size() - 1] as Dictionary).t) < MIN_GAP + AFTER:
		return "two tricks too close together"
	if String(e.kind) == "goo":
		if at.length() + rad > W.R - 0.5:
			return "goo off the meadow"
		if at.length() - rad < W.FIRE_R + 1.2:
			return "goo on the campfire"
		if W.river_dist(at.x, at.y) < W.RIVER_HALF + W.BANK + 0.2:
			return "goo in the river"
		if W.push_out(Vector3(at.x, 0.0, at.y), 0.5).distance_to(Vector3(at.x, 0.0, at.y)) > 0.001:
			return "goo on a house or tree"
		for c in W.COTTAGES:
			if at.distance_to(Vector2(float(c[0]), float(c[1]))) < W.COTTAGE_R + 1.0:
				return "goo on a cottage"
		if Vector2(float(e.cx), float(e.cz)).length() < W.R:
			return "the catapult isn't on the rim"
	else:
		var d := at.length()
		if d < BARREL_D.x - 0.01 or d > BARREL_D.y + 0.01:
			return "a barrel band %.1f from the fire" % d
		if line_dist(e, Vector2.ZERO) < W.FIRE_R + rad + 1.0:
			return "a barrel through the campfire"
		for c in W.COTTAGES:
			if line_dist(e, Vector2(float(c[0]), float(c[1]))) < W.COTTAGE_R + rad + 0.3:
				return "a barrel through a cottage"
	return ""


## Reasons wave n's tricks are unfair (empty = fine).
static func problems(list: Array, n: int, spec: Dictionary) -> Array:
	var why: Array = []
	var md := mode_data(String(spec.get("mode", "brave")))
	var first := float(spec.get("first", FIRST_T))
	if n < int(md.first) and not spec.has("first") and not list.is_empty():
		why.append("tricks before wave %d" % int(md.first))
	var kid := KNIGHT_SPEED * KID_SHARE
	var prev: Array = []
	for e in list:
		var tag := "%s at %.1f s" % [e.get("kind", "?"), float(e.get("t", 0.0))]
		if not KINDS.has(String(e.get("kind", ""))):
			why.append("unknown trick %s" % str(e))
			continue
		if float(e.t) < first - 0.001:
			why.append("%s: too early in the wave" % tag)
		if float(e.t) + span(e) > float(spec.get("send", 60.0)) + WINDOW_PAD + 0.001:
			why.append("%s: after the goblins have all come" % tag)
		if float(e.warn) < MIN_WARN or float(e.warn) < float(md.warn) - 0.001:
			why.append("%s: told only %.1f s" % [tag, float(e.warn)])
		var where := _where_problem(e, prev)
		if where != "":
			why.append("%s: %s" % [tag, where])
		var walk := (float(e.r) + KNIGHT_R) / kid + REACT  # a small knight in the middle walks out in time
		if walk > float(e.warn):
			why.append("%s: a small knight can't get out in time (%.1f s for %.1f s)" % [tag, walk, float(e.warn)])
		if String(e.kind) == "barrel" and barrel_secs(e) > AFTER:
			why.append("%s: the barrel takes %.1f s to roll by" % [tag, barrel_secs(e)])
		if float(md.bump) > MAX_BUMP:
			why.append("%s: the bump could put a knight down" % tag)
		prev.append(e)
	return why


static func pack(e: Dictionary) -> Array:
	return [] if e.is_empty() else [String(e.kind), float(e.x), float(e.z), float(e.dx), float(e.dz), float(e.warn), float(e.r),
		float(e.cx), float(e.cz), float(e.t)]


static func unpack(a: Array) -> Dictionary:
	return {} if a.size() < 10 else {"kind": String(a[0]), "x": float(a[1]), "z": float(a[2]), "dx": float(a[3]), "dz": float(a[4]),
		"warn": float(a[5]), "r": float(a[6]), "cx": float(a[7]), "cz": float(a[8]), "t": float(a[9])}


# --- Gifts ----------------------------------------------------------------------------------------------------

static func unlocked(treasures: int) -> Array:
	var out: Array = []
	for g in GIFTS:
		if treasures >= int(g.unlock):
			out.append(String(g.id))
	return out


static func gift(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return {}


## Three different unlocked gifts: the newest unlock always among them, not the last one again when there are others
## (the same for a seed).
static func gift_choices(treasures: int, last: String, seed_value: int) -> Array:
	return PickOrbs.gift_choices(unlocked(treasures), last, seed_value)  # (the shared gift pick)


static func goblin_speed(gift_id: String) -> float:
	return SLEEPY if gift_id == "sleepy" else 1.0


static func reach(gift_id: String) -> float:
	return BIG_REACH if gift_id == "bighands" else 1.0


static func flames(gift_id: String) -> float:
	return BIGFIRE_FLAMES if gift_id == "bigfire" else 1.0


## Where knight helper i stands (round the fire, facing out).
static func helper_spot(i: int) -> Vector3:
	var a: float = HELPER_ANGLES[i % HELPER_ANGLES.size()]
	return Vector3(cos(a), 0.0, sin(a)) * HELPER_RING


# --- Sparky's table treasures ---------------------------------------------------------------------------------

static func treasures(cleared: int) -> int:
	return mini(TREASURES.size(), maxi(0, cleared) / TREASURE_EVERY)


## Treasure i's place on the rim: between two lantern posts, nearest the Giant first (one side, then the other).
static func treasure_slot(i: int) -> Vector3:
	if i < 0 or i >= TREASURES.size():
		return Vector3.INF
	var gaps: Array = []
	for k in RaidGen.LANTERNS_MAX - 1:
		gaps.append(RaidGen.LANTERN_FIRST + (k + 0.5) * RaidGen.LANTERN_STEP)
	gaps.sort_custom(func(x: float, y: float) -> bool:
		return absf(angle_difference(x, RaidGen.GIANT_A)) < absf(angle_difference(y, RaidGen.GIANT_A)))
	var a: float = gaps[i]
	return Vector3(cos(a), 0.0, sin(a)) * (W.R + W.RIM * 0.5)


# --- The pick row ---------------------------------------------------------------------------------------------

## The orbs' places (world): over the ground in front of the Giant's seat.
static func row_spots(n: int = 3) -> Array:
	var out: Array = []
	for i in n:
		var x: float = ROW_X[i] if n == 3 else lerpf(ROW_X[0], ROW_X[2], float(i) / maxf(1.0, n - 1))
		out.append(Vector3(x, maxf(0.0, W.height(x, ROW_Z)) + ROW_Y, ROW_Z))
	return out


## An orb's radius in the world.
static func orb_r() -> float:
	return PickOrbs.BALL_R * ORB_SCALE
