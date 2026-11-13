extends RefCounted
## FISHING LAKE tackle and modes (pure data, fast, no nodes). Second deep pass:
##  * GENTLE / BRAVE / HARD (the shared core/pick_orbs.gd MODES): the team picks once per visit by casting the
##    bobber at a glowing orb (boats row into one). MODE_NUM: day length, how soon fish bite, OLD WHISKERS'
##    stamina, how long his pulls are TOLD before they come, how hard they pull and how long he rests.
##  * LURES: every day Ollie offers three lures (offer(lake)): WORM (everything nibbles sooner), SPINNER (trout,
##    pike, puffers), LILY BUG (bluegill, koi, perch), GLOW (eels, moonfish, catfish), GOLD FLY (the golden fish
##    comes sooner, shiny fish turn up more). A lure's fish swim BOOST times as often. The lure that helps Ollie's
##    wish sits in the middle (the one a little one gets by waiting).
##  * OLD WHISKERS' PULLS: boss_pulls(seed, mode) is a seeded list of [rest, pull, side]: he rests (reel then!),
##    a ring on the water TELLS where he is about to swim, then he pulls that way. Gentle rests longer and pulls
##    softer; pulls grow a little each time, never in a jump.
##  * SHINY FISH: any catch (not the legend or the golden fish) can be a shiny one (a gold star on its book page).
## check_offer / check_modes / check_pulls list what's wrong (empty = fair); tests/fishing_lake_gen_test.gd runs
## them over many seeds.

const Seeded := preload("res://core/seeded.gd")
const LakeGen := preload("res://games/fishing_lake/lakegen.gd")

const BOOST := 3
const SHINY_CHANCE := 0.06
const LURES: Array[Dictionary] = [
	{"id": "worm", "name": "WORM", "pic": "lure_worm", "color": Color(0.95, 0.5, 0.55), "fish": [], "level": 0, "bite": 0.8, "shiny": 1.0},
	{"id": "spinner", "name": "SPINNER", "pic": "lure_spinner", "color": Color(0.75, 0.88, 1.0),
		"fish": [LakeGen.TROUT, LakeGen.PIKE, LakeGen.PUFFER], "level": 0, "bite": 1.0, "shiny": 1.0},
	{"id": "lilybug", "name": "LILY BUG", "pic": "lure_lily", "color": Color(0.45, 0.9, 0.4),
		"fish": [LakeGen.BLUEGILL, LakeGen.KOI, LakeGen.PERCH], "level": 0, "bite": 1.0, "shiny": 1.0},
	{"id": "glow", "name": "GLOW", "pic": "lure_glow", "color": Color(0.5, 1.0, 0.95),
		"fish": [LakeGen.EEL, LakeGen.MOONFISH, LakeGen.CATFISH], "level": 1, "bite": 1.0, "shiny": 1.0},
	{"id": "goldfly", "name": "GOLD FLY", "pic": "lure_gold", "color": Color(1.0, 0.82, 0.25),
		"fish": [LakeGen.GOLDEN, LakeGen.MINNOW], "level": 2, "bite": 1.0, "shiny": 3.0},
]
## Per mode. day: day length x; bite: time to a nibble x; stamina: Old Whiskers' stamina x; tell: seconds his pull
## is told before it comes; pull: how hard he pulls x; rest: how long he rests x. Third pass (seasons.gd):
## visit_tell: seconds a flock's ring shows before it lands; visits: how many of the lake's flocks come.
const MODE_NUM := {
	"gentle": {"day": 1.15, "bite": 0.8, "stamina": 0.6, "tell": 1.8, "pull": 0.75, "rest": 1.3, "visit_tell": 4.0, "visits": 1},
	"brave": {"day": 1.0, "bite": 1.0, "stamina": 1.0, "tell": 1.3, "pull": 1.0, "rest": 1.0, "visit_tell": 3.2, "visits": 2},
	"hard": {"day": 0.9, "bite": 1.15, "stamina": 1.35, "tell": 1.0, "pull": 1.2, "rest": 0.85, "visit_tell": 2.5, "visits": 3},
}
const PULLS := 16
const TIRE_PER_S := 0.06  # angler.gd: stamina worn off per second of reeling while he rests (simple mode)


static func lure(id: String) -> Dictionary:
	for d in LURES:
		if String(d.id) == id:
			return d
	return LURES[0]


static func num(mode: String) -> Dictionary:
	return MODE_NUM.get(mode, MODE_NUM.brave)


## Does this lure bring this fish more often?
static func helps(id: String, kind: int) -> bool:
	return (lure(id).fish as Array).has(kind)


## A lure is worth offering today when one of its fish can be caught here (the worm always is).
static func useful(id: String, lake: Dictionary) -> bool:
	if (lure(id).fish as Array).is_empty():
		return true
	var can := LakeGen.catchable(lake)
	for k in lure(id).fish:
		if can.has(k):
			return true
	return false


static func unlocked(id: String, level: int) -> bool:
	return level >= int(lure(id).level)


## Today's three lures (seeded by the lake): the lure that helps the wish in the middle.
static func offer(lake: Dictionary) -> Array:
	var level := int(lake.get("level", 0))
	var wish := int(lake.get("wish", -1))
	var r := Seeded.rng(int(lake.get("seed", 0)), "lures")
	var can: Array = []
	for d in LURES:
		if unlocked(String(d.id), level) and useful(String(d.id), lake):
			can.append(String(d.id))
	var mid := "worm"
	for id in can:
		if wish >= 0 and helps(String(id), wish):
			mid = String(id)
			break
	can.erase(mid)
	can = Seeded.shuffled(r, can)
	var out: Array = can.slice(0, 2)
	out.insert(out.size() / 2, mid)
	return out


static func check_offer(lake: Dictionary, ids: Array) -> Array:
	var why: Array = []
	var level := int(lake.get("level", 0))
	if ids.size() != 3:
		why.append("%d lures offered" % ids.size())
	var seen := {}
	for id in ids:
		if seen.has(id):
			why.append("lure %s twice" % id)
		seen[id] = true
		if not unlocked(String(id), level):
			why.append("lure %s too early (level %d)" % [id, level])
		if not useful(String(id), lake):
			why.append("lure %s helps nothing here" % id)
	var wish := int(lake.get("wish", -1))
	if wish >= 0 and ids.size() == 3:
		var any := false
		for d in LURES:
			if unlocked(String(d.id), level) and helps(String(d.id), wish):
				any = true
		if any and not helps(String(ids[1]), wish):
			why.append("the wish's lure isn't in the middle")
	return why


## Old Whiskers' pulls for one fight: [rest secs, pull secs, side -1/1] each, rising gently.
static func boss_pulls(seed_value: int, mode: String) -> Array:
	var n := num(mode)
	var r := Seeded.rng(seed_value, "whiskers")
	var out: Array = []
	for i in PULLS:
		var grow := minf(1.0, float(i) / 8.0)
		var rest := (2.6 - 0.5 * grow + r.randf_range(-0.15, 0.15)) * float(n.rest)
		var pull := (0.9 + 0.6 * grow + r.randf_range(-0.1, 0.1)) * float(n.pull)
		var side := -1.0 if r.randf() < 0.5 else 1.0
		out.append([snappedf(maxf(rest, float(n.tell) + 0.7), 0.01), snappedf(pull, 0.01), side])
	return out


## Seconds of reeling it takes to tire him out (rests only: his pulls don't tire him).
static func tire_secs(mode: String) -> float:
	return float(num(mode).stamina) / TIRE_PER_S


## The whole fight's length (rest and pull seconds until he's worn out).
static func fight_secs(seed_value: int, mode: String) -> float:
	var need := tire_secs(mode)
	var total := 0.0
	for p in boss_pulls(seed_value, mode):
		var rest := float(p[0]) - 0.4  # a moment to see the tell and start reeling again
		total += float(p[0])
		need -= rest
		if need <= 0.0:
			return total
		total += float(p[1])
	return total + need


static func check_pulls(pulls: Array, mode: String) -> Array:
	var why: Array = []
	var n := num(mode)
	for i in pulls.size():
		var p: Array = pulls[i]
		if float(p[0]) < float(n.tell) + 0.6:
			why.append("pull %d: rest %.2f s is shorter than its tell" % [i, float(p[0])])
		if float(p[1]) > 2.2:
			why.append("pull %d lasts %.2f s" % [i, float(p[1])])
		if absf(float(p[2])) != 1.0:
			why.append("pull %d has no side" % i)
		if i > 0:
			var q: Array = pulls[i - 1]
			if absf(float(p[1]) - float(q[1])) > 0.35:
				why.append("pull %d jumps %.2f -> %.2f s" % [i, float(q[1]), float(p[1])])
			if absf(float(p[0]) - float(q[0])) > 0.5:
				why.append("rest %d jumps %.2f -> %.2f s" % [i, float(q[0]), float(p[0])])
	return why


## The modes rise in order (gentle <= brave <= hard), tells stay readable, and no fight drags on.
static func check_modes(seed_value: int) -> Array:
	var why: Array = []
	var order := ["gentle", "brave", "hard"]
	for i in order.size():
		var m: String = order[i]
		var n := num(m)
		if float(n.tell) < 0.9:
			why.append("%s: tell %.1f s too short to read" % [m, float(n.tell)])
		if float(n.visit_tell) < 2.2:
			why.append("%s: a flock's ring shows only %.1f s (reel out in time?)" % [m, float(n.visit_tell)])
		why.append_array(check_pulls(boss_pulls(seed_value, m), m).map(func(w: String) -> String: return "%s: %s" % [m, w]))
		var f := fight_secs(seed_value, m)
		var cap := 30.0 if m == "gentle" else (50.0 if m == "brave" else 75.0)
		if f > cap:
			why.append("%s: Old Whiskers takes %.0f s (want <= %.0f)" % [m, f, cap])
		if i == 0:
			continue
		var a := num(order[i - 1])
		for k in ["bite", "stamina", "pull", "visits"]:
			if float(n[k]) < float(a[k]):
				why.append("%s %s easier than %s" % [m, k, order[i - 1]])
		for k in ["day", "tell", "rest", "visit_tell"]:
			if float(n[k]) > float(a[k]):
				why.append("%s %s kinder than %s" % [m, k, order[i - 1]])
		var pa := boss_pulls(seed_value, order[i - 1])
		var pb := boss_pulls(seed_value, m)
		for j in pb.size():
			if float(pb[j][1]) < float(pa[j][1]) - 0.001:
				why.append("%s pull %d softer than %s" % [m, j, order[i - 1]])
		if fight_secs(seed_value, m) < fight_secs(seed_value, order[i - 1]):
			why.append("%s fight shorter than %s" % [m, order[i - 1]])
	return why


## Shiny fish: any fish but the legend and the golden fish.
static func shiny_ok(kind: int) -> bool:
	return LakeGen.species().has(kind) and kind != LakeGen.LEGEND and kind != LakeGen.GOLDEN


static func shiny_chance(lure_id: String) -> float:
	return SHINY_CHANCE * float(lure(lure_id).get("shiny", 1.0))