extends RefCounted
## KITCHEN RUSH second pass (SIMPLE_MODE): Gran's café gets theme nights, a team mode, chef gifts, warned kitchen
## events and a café that grows. Pure data (no nodes): parties.gd folds it into each made round and
## tests/kitchen_rush_rounds_test.gd proves it fair over many seeds.
##  - THEME NIGHTS (seeded by the day, the same on every machine): PIZZA NIGHT, PANCAKE DAY (a new dish: PANCAKES =
##    dough + berries from the new berry bush) or PICNIC DAY. The theme's dish joins the menus from round 3 and the
##    party menus lean towards the theme's dishes; the café is dressed for it (decor.gd).
##  - MODE: GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES) picked on the shared pick orbs after the practice
##    toastie. Gentle: more patience, a slower pace, one kitchen event. Hard: less patience, a quicker pace, three
##    events. Every mode is checked doable, and Gentle <= Brave <= Hard in every number.
##  - CHEF GIFTS: before rounds 2, 4, 6 and 8 Gran offers three gifts on the pick orbs (QUICK KNIFE: one chop
##    less, BIG POT: soup keeps the guests patient longer, HELPER MOUSE: brings missing food to the pass, SKATES:
##    runners zoom and never slip). They last the visit. Gifts only make things easier (the fairness model leaves
##    them out).
##  - KITCHEN EVENTS: OVEN SMOKE (a cloud by the stove) and SPILLS (a puddle on the floor) slow the runners inside
##    them for EVENT_SECS. Each one is told WARN_SECS early by warning rings on the floor (core/warn_rings.gd), on
##    every machine. Never on a crate, the pass, the window or the back door; spaced out; the model counts them.
##  - THE CAFE GROWS: every party served counts; at 2, 4, 7, 10, 14, 18, 24 and 32 parties the café gets fairy
##    lights, a fish tank, a piano, lanterns, a cake stand, a fountain outside, a gold star and a chandelier.

const Seeded := preload("res://core/seeded.gd")
const L := preload("res://games/kitchen_rush/layout.gd")

const GAME_ID := "kitchen_rush"
const THEME_ORDER: Array = ["pizza", "pancake", "picnic"]
const THEMES := {
	"pizza": {"word": "PIZZA NIGHT", "pic": "pizzanight", "line": "It's pizza night!", "dish": "PIZZA",
		"boost": {"PIZZA": 3.0, "MELT": 2.0, "TOASTIE": 1.3}, "colors": [Color(0.95, 0.25, 0.2), Color(1.0, 0.95, 0.85), Color(0.3, 0.75, 0.3)]},
	"pancake": {"word": "PANCAKE DAY", "pic": "pancakes", "line": "Pancakes for everyone!", "dish": "PANCAKES",
		"boost": {"PANCAKES": 3.0, "TOASTIE": 1.5, "SALAD": 1.2}, "colors": [Color(1.0, 0.8, 0.35), Color(0.6, 0.3, 0.75), Color(1.0, 0.95, 0.8)]},
	"picnic": {"word": "PICNIC DAY", "pic": "picnic", "line": "A picnic in the sun!", "dish": "SANDWICH",
		"boost": {"SANDWICH": 3.0, "SALAD": 2.0, "WRAP": 2.0}, "colors": [Color(0.95, 0.3, 0.35), Color(1.0, 1.0, 1.0), Color(0.45, 0.8, 0.4)]},
}
const THEME_FROM := 3  ## the theme's dish joins the menus from this round

## Mode numbers (Gentle <= Brave <= Hard): patience and pace multipliers, how many kitchen events a round.
const MODES := {
	"gentle": {"patience": 1.35, "interval": 1.25, "events": 1, "max_wait": -1},
	"brave": {"patience": 1.0, "interval": 1.0, "events": 2, "max_wait": 0},
	"hard": {"patience": 0.85, "interval": 0.85, "events": 3, "max_wait": 0},
}
const MODE_ORDER: Array = ["gentle", "brave", "hard"]

const GIFTS := {
	"knife": {"name": "QUICK KNIFE", "pic": "quickknife", "color": Color(0.75, 0.85, 1.0)},
	"pot": {"name": "BIG POT", "pic": "bigpot", "color": Color(1.0, 0.7, 0.3)},
	"mouse": {"name": "HELPER MOUSE", "pic": "helpermouse", "color": Color(0.85, 0.8, 0.95)},
	"skates": {"name": "SKATES", "pic": "skates", "color": Color(0.45, 1.0, 0.8)},
}
const GIFT_ORDER: Array = ["knife", "pot", "mouse", "skates"]
const GIFT_BEFORE: Array = [2, 4, 6, 8]  ## gift picks come before these rounds
const POT_PATIENCE := 1.25
const SKATES_SPEED := 1.2
const MOUSE_EVERY := 14.0

const EVENT_KINDS: Array = ["smoke", "spill"]
const EVENT_COLORS := {"smoke": Color(0.75, 0.75, 0.8), "spill": Color(0.35, 0.7, 1.0)}
const EVENTS_FROM := 2
const WARN_SECS := 3.0
const EVENT_SECS := 9.0
const EVENT_FIRST := 16.0  ## no event before this many seconds into a round
const EVENT_GAP := 24.0  ## seconds between event starts
const SLOW := 0.5  ## runner speed inside smoke / a spill
const EVENT_DELAY := 4.0  ## the fairness model: seconds an event can cost the dish being made
const SMOKE_AT := Vector3(-3.6, 0.0, -4.0)  ## in front of the stove (L.STOVE)
const SMOKE_R := 1.4
const SPILL_R := Vector2(0.9, 1.25)
const CLEAR := 0.45  ## events keep this far (past their edge) from every place a runner must stand

## The café grows: [parties served, decoration].
const CAFE_STEPS: Array = [[2, "fairylights"], [4, "fishtank"], [7, "piano"], [10, "lantern"], [14, "cake"],
	[18, "fountain"], [24, "cafestar"], [32, "chandelier"]]
const CAFE_WORDS := {"fairylights": "Fairy lights!", "fishtank": "A fish tank!", "piano": "A piano!", "lantern": "Lanterns!",
	"cake": "A cake stand!", "fountain": "A fountain!", "cafestar": "A gold star!", "chandelier": "A chandelier!"}


## Today's theme night (every machine, all day).
static func theme_for(date: String = "") -> String:
	var rng := Seeded.rng(Seeded.daily_seed(GAME_ID, date), "theme")
	return THEME_ORDER[rng.randi() % THEME_ORDER.size()]


static func mode_of(id: String) -> String:
	return id if MODES.has(id) else "brave"


static func boost(theme: String, dish: String) -> float:
	return float((THEMES.get(theme, {}) as Dictionary).get("boost", {}).get(dish, 1.0))


static func theme_dish(theme: String) -> String:
	return String((THEMES.get(theme, {}) as Dictionary).get("dish", ""))


## Gift picks: up to three gifts (seeded order) not taken yet, before round r ([] when there's no gift pick).
static func gift_offer(r: int, run_seed: int, taken: Array) -> Array:
	if not GIFT_BEFORE.has(r):
		return []
	var pool: Array = GIFT_ORDER.filter(func(g: String) -> bool: return not taken.has(g))
	return Seeded.shuffled(Seeded.rng(run_seed, "gifts%d" % r), pool).slice(0, 3)


## How many café decorations `parties` served parties have unlocked.
static func cafe_level(parties: int) -> int:
	var n := 0
	for s in CAFE_STEPS:
		if parties >= int(s[0]):
			n += 1
	return n


static func cafe_step(level: int) -> String:
	return String(CAFE_STEPS[level - 1][1]) if level >= 1 and level <= CAFE_STEPS.size() else ""


## Every place a runner must be able to stand (crates, garden beds, the pass, the window, the back door).
static func action_points() -> Array:
	var out: Array = []
	for s in L.SOURCES:
		var st := L.source_stand(String(s[0]))
		out.append(Vector2(st.x, st.z))
	for x in [-0.6, -0.2, 0.2, 0.6, -1.02, 1.02]:
		out.append(Vector2(x, -0.8))
	for z in L.CUSTOMER_Z:
		out.append(Vector2(L.SERVE_X, z))
	out.append(Vector2(0.0, -6.0))
	return out


## Is a floor circle clear of every action point and inside the runners' room (not the chef area)?
static func spot_ok(c: Vector2, r: float) -> bool:
	if absf(c.x) > L.ROOM_HALF.x - 0.6 - r or c.y < -L.ROOM_HALF.y + 0.5 + r or c.y > L.ROOM_HALF.y - 0.5 - r:
		return false
	var ca := L.CHEF_AREA.grow(0.4 + r)
	if ca.has_point(c) or (absf(c.x) < L.COUNTER_HALF.x + r + 0.3 and absf(c.y) < L.COUNTER_HALF.y + r + 0.3):
		return false
	for p in action_points():
		if (p as Vector2).distance_to(c) < r + CLEAR:
			return false
	return true


## The round's events for `mode`: [[t, kind, x, z, r], ...]. Hard's list is made first; Brave takes its first two
## and Gentle its first one, so a harder mode only ever adds events. `length`: the round's expected seconds.
static func make_events(r: int, run_seed: int, mode: String, length: float) -> Array:
	if r < EVENTS_FROM:
		return []
	var rng := Seeded.rng(run_seed, "events%d" % r)
	var all: Array = []
	var t := EVENT_FIRST + rng.randf_range(0.0, 8.0)
	var smoke_done := false
	while all.size() < int(MODES.hard.events) and t + EVENT_SECS <= maxf(length, EVENT_FIRST + EVENT_SECS + 1.0):
		var kind: String = "smoke" if (not smoke_done and rng.randf() < 0.45) else "spill"
		if kind == "smoke":
			smoke_done = true
			all.append([snappedf(t, 0.1), "smoke", SMOKE_AT.x, SMOKE_AT.z, SMOKE_R])
		else:
			for i in 40:
				var rad := snappedf(rng.randf_range(SPILL_R.x, SPILL_R.y), 0.01)
				# On the runners' busy floor: between the pass, the crates and the back door, or on the way to the window.
				var c := Vector2(rng.randf_range(-5.0, 5.4), rng.randf_range(-5.2, -1.0)) if rng.randf() < 0.7 else Vector2(rng.randf_range(2.6, 5.0), rng.randf_range(-3.0, 3.0))
				c = Vector2(snappedf(c.x, 0.01), snappedf(c.y, 0.01))
				if spot_ok(c, rad):
					all.append([snappedf(t, 0.1), "spill", c.x, c.y, rad])
					break
		t += EVENT_GAP + rng.randf_range(0.0, 10.0)
	return all.slice(0, int(MODES[mode_of(mode)].events))


## Why a round's mode numbers / events are wrong (empty = fine). m: a made round (parties.gd make).
static func check_events(m: Dictionary) -> Array:
	var out: Array = []
	var ev: Array = m.get("events", [])
	var mode := String(m.get("mode", "brave"))
	if not MODES.has(mode):
		out.append("unknown mode %s" % mode)
		return out
	if ev.size() > int(MODES[mode].events):
		out.append("%d events in %s" % [ev.size(), mode])
	if int(m.get("round", 0)) < EVENTS_FROM and not ev.is_empty():
		out.append("events before round %d" % EVENTS_FROM)
	var last := -INF
	for e in ev:
		var t := float(e[0])
		if not EVENT_KINDS.has(String(e[1])):
			out.append("unknown event %s" % e[1])
		if t < EVENT_FIRST - 0.01:
			out.append("event at %.1f s (too early to see it coming)" % t)
		if t - last < EVENT_GAP - 0.01:
			out.append("events %.1f s apart" % (t - last))
		last = t
		if not spot_ok(Vector2(float(e[2]), float(e[3])), float(e[4])):
			out.append("%s at (%.1f, %.1f) covers a place runners need" % [e[1], float(e[2]), float(e[3])])
	return out


## The numbers that make a round harder (for Gentle <= Brave <= Hard): bigger = harder.
static func pressure(m: Dictionary) -> Array:
	return [1000.0 / float(m.patience), 100.0 / float(m.interval), float(m.max_wait), float((m.get("events", []) as Array).size())]
