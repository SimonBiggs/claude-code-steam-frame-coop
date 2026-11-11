extends RefCounted
## MINI GOLF PARTY second pass (pure data + small functions; tests/mini_golf_party_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked once a session on the PICK GREEN before the
##             first hole: how hard the cup pulls a slow ball in, how many warned surprises a hole has, how long
##             they are told first, how hard a gust blows and how long the mole stays up.
##   GIFTS     GUS'S BALL AND CLUB GIFTS, three offered on the pick green after the practice hole of every course:
##             BOUNCY BALL (walls and bumpers bounce it on), MAGNET CUP (the cup pulls from further), LONG PUTTER
##             (dots show where your putt will roll; a longer club in VR), RAINBOW BALL (every gold star grows two
##             flowers) and GIANT CUP (a bigger hole) - the last two open as Gus's garden corner grows. A gift lasts
##             the rest of the course.
##   SURPRISES warned things on a hole, told by steady core/warn_rings.gd shapes for `warn` seconds before they
##             happen (never two at once):
##               GUST  a pale blue band across the fairway with arrows: for a few seconds a ROLLING ball in the band
##                     is blown the way the arrows point (a resting ball never moves), and the windmill spins fast.
##               MOLE  an orange-brown circle beside the aim line: a mole pops up there for a few seconds and the
##                     ball bounces off him (he never pops up under a resting ball, never on the aim line or the cup).
##             hazards(hole, spec) is made once by the host; problems() proves each one fair: told long enough, away
##             from the cup and the tee, the mole off the aim path, and the hole still sunk by the aiming putter
##             within par + 3 even if the gust blew or the mole stayed up THE WHOLE TIME (with this mode and gift).
##   SEASONS   the lawn is dressed for the season (Seeded.season): spring blossom, summer sunflowers, autumn leaves,
##             winter snow; spring and summer have more moles, autumn and winter more gusts.
##   CORNER    every CORNER_EVERY gold stars Gus's GARDEN CORNER on the left of the lawn gets a new piece for good (a
##             veg patch, a greenhouse, a pond, a beehive ...), far from every hole.
##   PICK GREEN a short green that opens out into three glowing PADS, a modest pick orb floating over each: putt your
##             ball onto a pad (or, in VR, reach a hand into an orb on purpose and hold it there a moment). The first
##             one decides for everyone. Nobody in time = the middle one (it glows brightest).

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const HoleGen := preload("res://games/mini_golf_party/holegen.gd")
const Course := preload("res://games/mini_golf_party/course.gd")
const Ball := preload("res://games/mini_golf_party/ball.gd")

## events: [min, max] surprises a hole; from: the first hole index with any (0 = the practice putt: never);
## warn: seconds told first; gust: m/s^2 a gust pushes a rolling ball; mole_up: seconds the mole stays up;
## assist_r / assist: how far (m) and how hard the cup pulls a slow ball (brave = the first pass's values).
const MODES := {
	"gentle": {"events": [0, 1], "from": 2, "warn": 3.6, "gust": 0.35, "mole_up": 4.0, "assist_r": 0.42, "assist": 1.3},
	"brave": {"events": [1, 1], "from": 1, "warn": 3.0, "gust": 0.6, "mole_up": 5.0, "assist_r": 0.3, "assist": 0.9},
	"hard": {"events": [1, 2], "from": 1, "warn": 2.6, "gust": 0.85, "mole_up": 6.0, "assist_r": 0.26, "assist": 0.8},
}
const MIN_WARN := 2.4
const FIRST_T := 9.0  # seconds into a hole before the first tell (everyone has a look first)
const GAP := [5.0, 12.0]  # seconds between one surprise ending and the next tell
const GUST_DUR := 5.0
const GUST_DEPTH := 0.7  # the band's depth along the fairway
const GUST_COLOR := Color(0.6, 0.92, 1.0)  # pale wind blue
const MOLE_COLOR := Color(0.95, 0.55, 0.2)  # orange-brown molehill
const MOLE_R := 0.11
const KINDS: Array[String] = ["gust", "mole"]
const PAR_SLACK := 3
const MAX_PROOFS := 5  # whole-hole proofs a hole's surprises may take to make  # with a surprise ON the whole hole, the aiming putter still sinks it within par + this
## Season -> surprise weights (gust, mole), the lawn, the drifting things' colour, a picture, Gus's line.
const SEASONS := {
	"spring": {"weights": [0.8, 1.5], "lawn": Color(0.4, 0.8, 0.38), "drift": Color(1.0, 0.72, 0.85), "pic": "daisy", "line": "Spring golf!"},
	"summer": {"weights": [0.9, 1.2], "lawn": Color(0.42, 0.76, 0.3), "drift": Color(1.0, 0.93, 0.5), "pic": "sunflower", "line": "Summer golf!"},
	"autumn": {"weights": [1.6, 0.8], "lawn": Color(0.55, 0.68, 0.28), "drift": Color(0.95, 0.5, 0.15), "pic": "acorn", "line": "Windy autumn!"},
	"winter": {"weights": [1.4, 0.7], "lawn": Color(0.86, 0.9, 0.95), "drift": Color(1.0, 1.0, 1.0), "pic": "snowflake", "line": "Snowy golf!"},
}
## Gus's gifts: id, name, picture, a short line, a colour, garden-corner pieces needed.
const GIFTS: Array[Dictionary] = [
	{"id": "bouncy", "name": "BOUNCY BALL", "pic": "bouncyball", "line": "Boing boing!", "color": Color(1.0, 0.45, 0.8), "unlock": 0},
	{"id": "magnet", "name": "MAGNET CUP", "pic": "magnetcup", "line": "The cup pulls!", "color": Color(0.95, 0.3, 0.3), "unlock": 0},
	{"id": "long", "name": "LONG PUTTER", "pic": "longputter", "line": "See it roll!", "color": Color(0.45, 0.7, 1.0), "unlock": 0},
	{"id": "rainbow", "name": "RAINBOW BALL", "pic": "rainbowball", "line": "Double flowers!", "color": Color(1.0, 0.85, 0.25), "unlock": 2},
	{"id": "giant", "name": "GIANT CUP", "pic": "giantcup", "line": "A huge hole!", "color": Color(0.7, 0.5, 1.0), "unlock": 4},
]
const BOUNCY_WALL := 0.86  # wall bounce (first pass 0.7)
const BOUNCY_BUMPER := 1.3
const MAGNET_R := 0.6  # the cup's pull reaches this far
const MAGNET := 2.2
const MAGNET_CAPTURE := 2.0
const GIANT := 1.45  # the cup's radius share (never closer than GIANT_ROOM to a wall)
const GIANT_ROOM := 0.06
const LONG_REACH := 1.3  # VR: the long putter reaches this far
const GUIDE_SECS := 1.6  # LONG PUTTER: how far ahead the dots show the roll
const GIFT_HOLE := 1  # the gift pick comes before this hole (after the practice putt)
## Gus's garden corner: one piece every CORNER_EVERY gold stars.
const CORNER_EVERY := 8
const CORNER: Array[String] = ["veg", "greenhouse", "pond", "hive", "scarecrow", "arch", "windmill", "treehouse"]
const CORNER_PICS := {"veg": "carrot", "greenhouse": "greenhouse", "pond": "fish_pond", "hive": "hive", "scarecrow": "scarecrow",
	"arch": "rainbow", "windmill": "windmill", "treehouse": "treehouse"}
const CORNER_X: Array[float] = [-4.5, -6.0]
const CORNER_Z: Array[float] = [-2.4, -0.8, 0.8, 2.4]
## The pick green: a neck from the tee that opens out into three pads.
const NECK_HW := 0.6
const PAD_X: Array[float] = [-0.85, 0.0, 0.85]
const PAD_R := 0.3
const ORB_Y := 0.8  # the orbs float this high over their pads (waist height: never in a VR face)
const ORB_SCALE := 0.36
const HAND_R := 0.1  # a glove this near an orb's edge is in it
const DWELL := 0.25  # seconds a glove must stay in an orb
const ROW_WAIT := {"mode": 22.0, "gift": 18.0}  # nobody took one: the middle
const SOLO_WAIT := 15.0  # one golfer: a bit sooner (still time for two putts)


static func mode_of(id: String) -> String:
	var m := String(PickOrbs.ALIASES.get(id, id))
	return m if MODES.has(m) else "brave"


static func mode_data(id: String) -> Dictionary:
	return MODES[mode_of(id)]


static func season_data(s: String) -> Dictionary:
	return SEASONS.get(s, SEASONS.spring)


static func wait_for(stage: String, solo: bool) -> float:
	return SOLO_WAIT if solo else float(ROW_WAIT.get(stage, 18.0))


## Problems with the mode table (GENTLE <= BRAVE <= HARD in every way that makes it harder).
static func ordered() -> Array:
	var out: Array = []
	var g: Dictionary = MODES.gentle
	var b: Dictionary = MODES.brave
	var h: Dictionary = MODES.hard
	for k in ["gust", "mole_up"]:  # more is harder
		if not (float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k])):
			out.append("%s not gentle <= brave <= hard" % k)
	for k in ["warn", "assist_r", "assist", "from"]:  # more is gentler
		if not (float(g[k]) >= float(b[k]) and float(b[k]) >= float(h[k])):
			out.append("%s not most on gentle" % k)
	for i in 2:
		if not (int(g.events[i]) <= int(b.events[i]) and int(b.events[i]) <= int(h.events[i])):
			out.append("events not gentle <= brave <= hard")
	if float(h.warn) < MIN_WARN:
		out.append("hard warns under %.1f s" % MIN_WARN)
	if int(g.from) < 1 or int(b.from) < 1 or int(h.from) < 1:
		out.append("a surprise on the practice putt")
	return out


# --- Ball physics knobs: the mode and the gift (course.gd apply()) -----------------------------------------------

## The course's ball physics for this mode and gift on hole d.
static func knobs(mode: String, gift_id: String, d: Dictionary) -> Dictionary:
	var md := mode_data(mode)
	var k := {"assist_r": float(md.assist_r), "assist": float(md.assist), "wall_bounce": Course.WALL_BOUNCE,
		"bumper_bounce": Course.BUMPER_BOUNCE, "capture": Course.CAPTURE_SPEED, "cup_r": Course.CUP_R}
	match gift_id:
		"bouncy":
			k.wall_bounce = BOUNCY_WALL
			k.bumper_bounce = BOUNCY_BUMPER
		"magnet":
			k.assist_r = maxf(float(k.assist_r), MAGNET_R)
			k.assist = maxf(float(k.assist), MAGNET)
			k.capture = MAGNET_CAPTURE
		"giant":
			k.cup_r = giant_r(d)
	return k


## The GIANT CUP's radius on hole d: GIANT times bigger, never nearer than GIANT_ROOM to a wall or a bumper.
static func giant_r(d: Dictionary) -> float:
	if d.is_empty() or not d.has("outline"):
		return Course.CUP_R * GIANT
	var cup: Vector2 = d.cup
	var room := HoleGen.wall_dist(d.outline, cup) - GIANT_ROOM
	for bm in d.get("bumpers", []):
		room = minf(room, (bm[0] as Vector2).distance_to(cup) - float(bm[1]) - GIANT_ROOM)
	return clampf(room, Course.CUP_R, Course.CUP_R * GIANT)


# --- Surprises ------------------------------------------------------------------------------------------------

## Proof hole d stays sinkable with this mode's and gift's ball physics: the aiming putter sinks it within par +
## PAR_SLACK (holegen.gd hole() also_proven: the host picks a try that passes; the TV machines rebuild that try).
static func sinkable(d: Dictionary, mode: String, gift_id: String) -> bool:
	var r := HoleGen.sim(d, HoleGen.MAX_PUTTS, knobs(mode, gift_id, d))
	return bool(r.sunk) and int(r.putts) <= int(d.par) + PAR_SLACK


## The surprises of hole d, in time order: [{kind, t (the tell starts), warn, dur, p, dir, len, depth, acc, r}].
## spec: {mode, season, gift, from (bots: an earlier hole), first_t (bots: sooner)}.
static func hazards(d: Dictionary, spec: Dictionary) -> Array:
	var out: Array = []
	if d.is_empty() or bool(d.get("pick", false)):
		return out
	var md := mode_data(String(spec.get("mode", "brave")))
	if int(d.get("index", 0)) < int(spec.get("from", md.from)):
		return out
	var r := Seeded.rng(int(d.get("seed", 0)), "surprises")
	var n := r.randi_range(int(md.events[0]), int(md.events[1]))
	var weights: Array = season_data(String(spec.get("season", "spring"))).weights
	var t := float(spec.get("first_t", FIRST_T)) + r.randf_range(0.0, 3.0)
	var proofs := MAX_PROOFS  # (each proof is a whole simulated hole: a Deck hosting stays quick)
	for _e in n:
		var first: String = KINDS[Seeded.weighted(r, weights)]
		var ev := {}
		for kind in [first, "gust" if first == "mole" else "mole"]:
			for _try in 8:
				var cand := _place(d, String(kind), r, md, t)
				if cand.is_empty() or proofs <= 0 or not event_problems(d, cand, spec, false).is_empty():
					continue
				proofs -= 1
				if event_problems(d, cand, spec).is_empty():
					ev = cand
					break
			if not ev.is_empty():
				break
		if ev.is_empty():
			continue
		out.append(ev)
		t = float(ev.t) + float(ev.warn) + float(ev.dur) + r.randf_range(float(GAP[0]), float(GAP[1]))
	return out


## The aim path: the tee, then every aim point to the cup.
static func chain(d: Dictionary) -> Array:
	var out: Array = [d.tee]
	out.append_array(d.path)
	return out


static func _place(d: Dictionary, kind: String, r: RandomNumberGenerator, md: Dictionary, t: float) -> Dictionary:
	var ch := chain(d)
	var total := 0.0
	for k in ch.size() - 1:
		total += (ch[k] as Vector2).distance_to(ch[k + 1])
	var at := r.randf_range(0.2, 0.8) * total
	var k0 := 0
	while k0 < ch.size() - 2 and at > (ch[k0] as Vector2).distance_to(ch[k0 + 1]):
		at -= (ch[k0] as Vector2).distance_to(ch[k0 + 1])
		k0 += 1
	var a: Vector2 = ch[k0]
	var b: Vector2 = ch[k0 + 1]
	var along := (b - a).normalized()
	var p := a + along * minf(at, a.distance_to(b))
	var lat := Vector2(-along.y, along.x) * (1.0 if r.randf() < 0.5 else -1.0)
	var hw := float(d.get("hw", 0.55))
	var ev := {"kind": kind, "t": snappedf(t, 0.1), "warn": float(md.warn)}
	if kind == "gust":
		ev.merge({"dur": GUST_DUR, "p": p, "dir": lat, "len": hw * 2.0 + 0.6, "depth": GUST_DEPTH, "acc": float(md.gust), "r": 0.0})
	else:
		var off := r.randf_range(MOLE_R + Course.BALL_R + 0.13, hw - MOLE_R - Course.BALL_R * 2.0 - 0.07)
		ev.merge({"dur": float(md.mole_up), "p": p + lat * off, "dir": lat, "len": 0.0, "depth": 0.0, "acc": 0.0, "r": MOLE_R})
	return ev


## Is point q in a gust's band?
static func in_gust(ev: Dictionary, q: Vector2, pad: float = 0.0) -> bool:
	var dir: Vector2 = ev.dir
	var along := Vector2(-dir.y, dir.x)
	var rel := q - (ev.p as Vector2)
	return absf(rel.dot(dir)) <= float(ev.len) * 0.5 + pad and absf(rel.dot(along)) <= float(ev.depth) * 0.5 + pad


## What a surprise does to the course while it is ON (course.gd gust / moles): the sim and the game both use it.
static func on_knobs(ev: Dictionary) -> Dictionary:
	if String(ev.get("kind", "")) == "gust":
		return {"gust": {"p": ev.p, "dir": ev.dir, "len": ev.len, "depth": ev.depth, "acc": ev.acc}}
	return {"moles": [[ev.p, float(ev.r)]]}


## Reasons one surprise on hole d is unfair (empty = fine). Includes the proof: the aiming putter (holegen.gd sim)
## still sinks the hole within par + PAR_SLACK with the surprise ON the whole time, with this mode and gift.
static func event_problems(d: Dictionary, ev: Dictionary, spec: Dictionary, proof: bool = true) -> Array:
	var why: Array = []
	var md := mode_data(String(spec.get("mode", "brave")))
	if float(ev.get("warn", 0.0)) < maxf(MIN_WARN, float(md.warn)) - 0.001:
		why.append("told only %.1f s early" % float(ev.get("warn", 0.0)))
	var poly := PackedVector2Array(d.outline)
	var cup: Vector2 = d.cup
	var tee: Vector2 = d.tee
	var p: Vector2 = ev.p
	match String(ev.get("kind", "")):
		"gust":
			if in_gust(ev, cup, 0.35):
				why.append("a gust blows over the cup")
			if in_gust(ev, tee, 0.35):
				why.append("a gust blows over the tee")
			if float(ev.acc) > 1.0:
				why.append("a gust blows too hard")
		"mole":
			if not Geometry2D.is_point_in_polygon(p, poly):
				why.append("the mole is off the green")
			elif HoleGen.wall_dist(d.outline, p) < MOLE_R + Course.BALL_R * 2.0 + 0.05:
				why.append("the mole leaves a pocket by a wall")
			if p.distance_to(cup) < 0.6 or p.distance_to(tee) < 0.6:
				why.append("the mole is by the cup or the tee")
			var ch := chain(d)
			for k in ch.size() - 1:
				var q := Geometry2D.get_closest_point_to_segment(p, ch[k], ch[k + 1])
				if q.distance_to(p) < MOLE_R + Course.BALL_R + 0.1:
					why.append("the mole is on the aim line")
					break
			for bm in d.get("bumpers", []):
				if (bm[0] as Vector2).distance_to(p) < float(bm[1]) + MOLE_R + Course.BALL_R * 2.0 + 0.05:
					why.append("the mole is by a bumper")
			match String(d.get("gimmick", "")):
				"windmill":
					if absf(p.y - float(d.mill_z)) < 0.7:
						why.append("the mole is in the windmill")
				"loop":
					if absf(p.y - float(d.loop_z)) < 0.7:
						why.append("the mole is in the loop")
		_:
			why.append("unknown surprise %s" % str(ev.get("kind")))
			return why
	if not why.is_empty() or not proof:
		return why
	var k := knobs(String(spec.get("mode", "brave")), String(spec.get("gift", "")), d)
	k.merge(on_knobs(ev))
	var res := HoleGen.sim(d, HoleGen.MAX_PUTTS, k)
	if not bool(res.sunk) or int(res.putts) > int(d.par) + PAR_SLACK:
		why.append("with the %s on the whole time the putter needs %s putts (par %d)" % [ev.kind,
			str(res.putts) if bool(res.sunk) else "more than %d" % HoleGen.MAX_PUTTS, int(d.par)])
	return why


## Reasons a hole's surprise list is unfair (empty = fine).
static func problems(d: Dictionary, list: Array, spec: Dictionary) -> Array:
	var why: Array = []
	var md := mode_data(String(spec.get("mode", "brave")))
	if not list.is_empty() and (bool(d.get("pick", false)) or int(d.get("index", 0)) < 1):
		why.append("a surprise on the practice putt or the pick green")
	if list.size() > int(md.events[1]):
		why.append("%d surprises (most %d)" % [list.size(), int(md.events[1])])
	var end := -INF
	for ev in list:
		if float(ev.t) < float(spec.get("first_t", FIRST_T)) - 0.001:
			why.append("a surprise told %.1f s into the hole" % float(ev.t))
		if float(ev.t) < end + float(GAP[0]) - 0.001:
			why.append("two surprises too close together")
		end = float(ev.t) + float(ev.warn) + float(ev.dur)
		for w in event_problems(d, ev, spec):
			why.append(w)
	return why


## Host -> every machine: the surprise showing now. [kind, phase ("warn" / "on"), seconds left, p, dir, len, depth, r]
static func pack(ev: Dictionary, phase: String, left: float) -> Array:
	if ev.is_empty() or phase == "":
		return []
	return [String(ev.kind), phase, snappedf(left, 0.05), ev.p, ev.dir, float(ev.len), float(ev.depth), float(ev.r)]


static func unpack(a: Array) -> Dictionary:
	if a.size() < 8:
		return {}
	return {"kind": String(a[0]), "phase": String(a[1]), "left": float(a[2]), "p": a[3], "dir": a[4], "len": float(a[5]),
		"depth": float(a[6]), "r": float(a[7])}


# --- Gifts ----------------------------------------------------------------------------------------------------

static func unlocked(pieces: int) -> Array:
	var out: Array = []
	for g in GIFTS:
		if pieces >= int(g.unlock):
			out.append(String(g.id))
	return out


static func gift(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return {}


## Three different unlocked gifts: the newest unlock always among them, not the last one again when there are others
## (the same on every machine for a seed).
static func gift_choices(pieces: int, last: String, seed_value: int) -> Array:
	var un := unlocked(pieces)
	var newest: String = un[un.size() - 1]
	var pool: Array = []
	for id in un:
		if id != newest and (id != last or un.size() <= 3):
			pool.append(id)
	pool = Seeded.shuffled(Seeded.rng(seed_value, "gifts"), pool)
	var out: Array = [newest] if newest != last or un.size() <= 3 else []
	for id in pool:
		if out.size() >= 3:
			break
		out.append(id)
	if out.size() < 3:
		for id in un:
			if out.size() < 3 and not out.has(id):
				out.append(id)
	return Seeded.shuffled(Seeded.rng(seed_value, "gift order"), out)


## Gold stars a sink grows in Gus's garden (RAINBOW BALL: two).
static func stars_for(gift_id: String) -> int:
	return 2 if gift_id == "rainbow" else 1


# --- Gus's garden corner --------------------------------------------------------------------------------------

static func corner(stars: int) -> int:
	return mini(CORNER.size(), maxi(0, stars) / CORNER_EVERY)


## Where corner piece i stands (world, on the lawn): a column down the left of the lawn, nearest the cup end first.
static func corner_spot(i: int) -> Vector2:
	return Vector2(CORNER_X[i / CORNER_Z.size()], CORNER_Z[i % CORNER_Z.size()])


# --- The pick green -------------------------------------------------------------------------------------------

## The pick green as a hole (course.gd builds it; holegen.gd check() passes it): a neck from the tee opening into a
## wide end with three pads. "pick": true (no cup: course.gd skips the cup, the flag and sinking), "pads": [Vector2].
static func pick_green() -> Dictionary:
	var top := 2.0  # the tee end
	var mid := 0.2  # where the neck opens out
	var bot := -1.7
	var wide := 1.4
	var outline: Array = [Vector2(-NECK_HW, top), Vector2(-NECK_HW, mid), Vector2(-wide, mid), Vector2(-wide, bot),
		Vector2(wide, bot), Vector2(wide, mid), Vector2(NECK_HW, mid), Vector2(NECK_HW, top)]
	var pads: Array = []
	for x in PAD_X:
		pads.append(Vector2(x, -0.9))
	var d := {"outline": outline, "rects": [[-NECK_HW, mid, NECK_HW, top], [-wide, bot, wide, mid]], "tee": Vector2(0.0, top - 0.45),
		"cup": Vector2(0.0, bot + 0.3), "path": [pads[1], Vector2(0.0, bot + 0.3)], "bumpers": [], "gimmick": "", "shape": "pick", "hw": NECK_HW, "par": 2,
		"seed": 0, "index": -1, "level": 1, "try": 0, "course_seed": 0, "pick": true, "pads": pads}
	HoleGen._center(d)
	var o: Vector2 = (d.tee as Vector2) - Vector2(0.0, top - 0.45)
	for k in pads.size():
		pads[k] = (pads[k] as Vector2) + o
	return d


## The pad a ball at p is on (-1: none).
static func pad_at(d: Dictionary, p: Vector2) -> int:
	var pads: Array = d.get("pads", [])
	for i in pads.size():
		if (pads[i] as Vector2).distance_to(p) <= PAD_R:
			return i
	return -1


## Where orb i floats (world).
static func orb_spot(d: Dictionary, i: int) -> Vector3:
	var p: Vector2 = d.pads[i]
	return Vector3(p.x, ORB_Y, p.y)


## Proof a putt aimed at pad i (the bots' and the sim's speed rule) rolls onto it: putts needed (99: never).
static func putts_to_pad(d: Dictionary, i: int, k: Dictionary = {}) -> int:
	var c := Course.new()
	c.setup(d)
	c.apply(k)
	var b := Ball.new()
	b.course = c
	b.place(d.tee)
	var target: Vector2 = d.pads[i]
	var got := 99
	for n in 4:
		b.putt((target - b.pos).normalized() * HoleGen.putt_speed(c, b.pos, target))
		var steps := 0
		while b.state != "rest" and steps < 60 * 12:
			b.step(1.0 / 60.0)
			b.events.clear()
			steps += 1
			if pad_at(d, b.pos) == i:
				got = n + 1
				break
		if got < 99:
			break
	b.free()
	c.free()
	return got
