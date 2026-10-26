extends RefCounted
## KITCHEN RUSH party rounds (SIMPLE_MODE): Gran's café. After the practice toastie every round is a
## PARTY made from a seed: who comes (pirates, robots, aliens, knights, kids or Gran's friends), the
## round's menu (the dishes they like, out of the ones the kitchen knows), the exact list of orders,
## sometimes a STAR GUEST (a golden crown: a golden gift), the pace and the patience.
##  - Round 1 is always Gran's friends (toasties). Round 2 is TODAY'S PARTY: the same on every machine
##    all day (daily seed), and its thank-you gift is golden.
##  - From round 3 the team CHOOSES the next party: two invitations float over the pass; the chef grabs
##    one or a runner taps one (nobody picks: the first one comes).
##  - Rounds 2-4 still bring one new lesson dish each (SALAD, BURGER, PIZZA), first in the list.
##  - Each party leaves a THANK-YOU GIFT for the café shelf (saved: the café fills up over the days).
##    Gifts bring new guests (robots at 2 gifts, aliens at 4, knights at 6), and a party type that has
##    visited twice teaches the kitchen ITS dish (robots: MELT, aliens: WRAP, knights: SANDWICH), on the
##    menu from round 5.
##  - It gets a little busier each round (more orders, a quicker pace, less patience) but every round is
##    checked doable: a simple kitchen model (one runner, or the solo kitchen helpers) must be able to
##    serve every order in time. If a made round isn't, the pace is eased until it is.
## Same (round, seed, progress, party, fresh dish) -> same round. tests/kitchen_rush_rounds_test.gd
## checks many seeds and progress states.

const Seeded := preload("res://core/seeded.gd")
const L := preload("res://games/kitchen_rush/layout.gd")

const GAME_ID := "kitchen_rush"
## Every dish (same as main.gd RECIPES, which reads this). The first four are the lesson dishes.
const DISHES := {
	"SALAD": ["lettuce", "tomato", "cucumber"],
	"TOASTIE": ["bun", "cheese"],
	"BURGER": ["bun", "patty", "lettuce", "tomato"],
	"PIZZA": ["dough", "tomato", "cheese"],
	"WRAP": ["dough", "lettuce", "cucumber"],
	"SANDWICH": ["bun", "lettuce", "cucumber"],
	"MELT": ["patty", "cheese", "tomato"],
}
const LESSONS: Array = ["TOASTIE", "SALAD", "BURGER", "PIZZA"]  ## one new one per round (rounds 1-4)
const CHOPS := {"lettuce": 3, "tomato": 3, "cucumber": 3, "cheese": 2}
## Party types: name word, the dishes they like (weights), their thank-you gift, the dish they teach
## after two visits, gifts needed before they come, and Gran's line.
const PARTIES := {
	"granny": {"word": "GRAN'S FRIENDS", "likes": {"TOASTIE": 3, "SALAD": 2, "SANDWICH": 2, "PIZZA": 1}, "gift": "teapot", "teach": "", "need": 0, "line": "My friends are coming!"},
	"kid": {"word": "KIDS' PARTY", "likes": {"PIZZA": 3, "TOASTIE": 3, "BURGER": 2, "WRAP": 1}, "gift": "balloon", "teach": "", "need": 0, "line": "A birthday party!"},
	"pirate": {"word": "PIRATES", "likes": {"BURGER": 3, "MELT": 3, "PIZZA": 1, "TOASTIE": 1}, "gift": "treasure", "teach": "", "need": 0, "line": "Pirates ahoy!"},
	"robot": {"word": "ROBOTS", "likes": {"PIZZA": 3, "MELT": 3, "BURGER": 1, "SALAD": 1}, "gift": "robot", "teach": "MELT", "need": 2, "line": "Beep! Robots are hungry!"},
	"alien": {"word": "ALIENS", "likes": {"SALAD": 3, "WRAP": 3, "PIZZA": 1, "TOASTIE": 1}, "gift": "ufo", "teach": "WRAP", "need": 4, "line": "Aliens have landed!"},
	"knight": {"word": "KNIGHTS", "likes": {"BURGER": 3, "SANDWICH": 3, "SALAD": 1, "TOASTIE": 1}, "gift": "shield", "teach": "SANDWICH", "need": 6, "line": "Knights want a feast!"},
}
const PARTY_ORDER: Array = ["granny", "kid", "pirate", "robot", "alien", "knight"]  ## index = invite number
const TEACH_VISITS := 2
const DAILY_ROUND := 2
const CHOICE_FROM := 3  ## rounds from here on are chosen with invitations
const MENU_FROM := 5  ## taught dishes join the menus from this round
const MAX_ORDERS := 10
const SPARE := 3  ## extra orders after `count` (more runners serve a few more)
const PATIENCE_MIN := 60.0
const PATIENCE_MAX := 110.0
const INTERVAL_MIN := 6.0
const INTERVAL_MAX := 22.0
## The kitchen model (fairness): runner speed (m/s) with a path factor, seconds per chop / per stack,
## the solo helpers' pace, and the walk to the window.
const RUN_SPEED := 5.2 / 1.35
const CHOP_S := 0.5
const STACK_S := 1.3
const HELPER_FIRST := 6.0
const HELPER_NEXT := 3.0
const SERVE_S := 3.0
## Customer patience multipliers (customer.gd TYPES[...][0]); a star guest waits a bit longer.
const PATIENCE_MULT := {"kid": 0.85, "granny": 1.45, "robot": 1.0, "pirate": 0.9, "alien": 1.1, "knight": 1.0}
const STAR_PATIENCE := 1.2


## Party types open with `progress` ({"gifts": n}).
static func parties_open(progress: Dictionary) -> Array:
	var gifts := int(progress.get("gifts", 0))
	var out: Array = []
	for p in PARTY_ORDER:
		if gifts >= int(PARTIES[p]["need"]):
			out.append(p)
	return out


## Dishes the kitchen knows in round r (1-based): the lessons so far, plus (from MENU_FROM) the dishes
## taught by parties that visited twice ({"visits": {type: n}}).
static func known_dishes(r: int, progress: Dictionary) -> Array:
	var out: Array = LESSONS.slice(0, clampi(r, 1, LESSONS.size()))
	if r >= MENU_FROM:
		out.append_array(taught(progress))
	return out


## Dishes taught so far (in PARTY_ORDER).
static func taught(progress: Dictionary) -> Array:
	var visits: Dictionary = progress.get("visits", {})
	var out: Array = []
	for p in PARTY_ORDER:
		var d := String(PARTIES[p]["teach"])
		if d != "" and int(visits.get(p, 0)) >= TEACH_VISITS:
			out.append(d)
	return out


## The lesson dish that is new in round r ("" from round 5).
static func lesson_dish(r: int) -> String:
	return LESSONS[r - 1] if r >= 2 and r <= LESSONS.size() else ""


## The two invitations before round r (r >= CHOICE_FROM): two different open party types, not the
## last party if that can be helped. Returns [] when the round isn't chosen.
static func offers(r: int, run_seed: int, progress: Dictionary, last_party: String = "") -> Array:
	if r < CHOICE_FROM:
		return []
	var rng := Seeded.rng(run_seed, "offers%d" % r)
	var open := parties_open(progress)
	var pool: Array = open.filter(func(p: String) -> bool: return p != last_party)
	if pool.size() < 2:
		pool = open.duplicate()
	# The newest guests are a bit likelier (new is exciting), the rest even.
	var weights: Array = []
	for i in pool.size():
		weights.append(2.0 if i == pool.size() - 1 and pool.size() > 3 else 1.0)
	var a: String = pool[Seeded.weighted(rng, weights)]
	pool.erase(a)
	weights.resize(pool.size())
	weights.fill(1.0)
	var b: String = pool[Seeded.weighted(rng, weights)]
	return [a, b]


## The party that comes in round r when nobody chooses: Gran's friends (1), today's party (2), or the
## first invitation.
static func default_party(r: int, run_seed: int, progress: Dictionary, last_party: String = "") -> String:
	if r <= 1:
		return "granny"
	if r == DAILY_ROUND:
		return daily_party()
	return String(offers(r, run_seed, progress, last_party)[0])


## Today's party type (every machine, all day).
static func daily_party(date: String = "") -> String:
	var rng := Seeded.rng(Seeded.daily_seed(GAME_ID, date), "party")
	return PARTY_ORDER[rng.randi() % PARTY_ORDER.size()]


## Round r (1-based) of a session. `party` "" = the default. `fresh` = a taught dish to put first
## (the first time a session meets it). Returns a plain Dictionary:
## {round, party, daily, menu, orders, count, star, patience, interval, max_wait, raccoon, gift, word, line, fresh}
static func make(r: int, run_seed: int, progress: Dictionary, party: String = "", fresh: String = "") -> Dictionary:
	var daily := r == DAILY_ROUND
	if party == "" or daily or r <= 1:
		party = default_party(r, run_seed, progress)
	var rng := Seeded.rng(Seeded.daily_seed(GAME_ID) if daily else run_seed, "round%d/%s" % [0 if daily else r, party])
	var info: Dictionary = PARTIES[party]
	var known := known_dishes(r, progress)
	var new_dish := lesson_dish(r)
	if new_dish == "" and fresh != "" and known.has(fresh):
		new_dish = fresh
	# The menu: early rounds use every dish learned so far; later two or three the party likes.
	var menu: Array = []
	if r < MENU_FROM:
		menu = known.duplicate()
	else:
		var size := mini(known.size(), 2 + (1 if r >= 7 else 0) + (1 if r >= 11 else 0))
		if new_dish != "":
			menu.append(new_dish)
		var pool: Array = known.filter(func(d: String) -> bool: return not menu.has(d))
		while menu.size() < size and not pool.is_empty():
			var w: Array = []
			for d in pool:
				w.append(float(info["likes"].get(d, 0.5)))
			var pick: String = pool[Seeded.weighted(rng, w)]
			menu.append(pick)
			pool.erase(pick)
	# How many orders, and which (the new dish first).
	var count := 3
	if r >= MENU_FROM:
		count = mini(6 + (r - MENU_FROM) / 3, MAX_ORDERS - SPARE)
	elif r > 1:
		count = mini(2 + r, 6)
	var orders: Array = []
	if new_dish != "":
		orders.append(new_dish)
	var mw: Array = []
	for d in menu:
		mw.append(float(info["likes"].get(d, 0.5)) + (1.0 if d == new_dish else 0.0))
	while orders.size() < count + SPARE:
		var w2: Array = mw.duplicate()
		var n := orders.size()
		if menu.size() > 1 and n >= 2 and orders[n - 1] == orders[n - 2]:
			w2[menu.find(orders[n - 1])] = 0.0  # never three of the same in a row
		orders.append(menu[Seeded.weighted(rng, w2)])
	# A star guest now and then (never the first order, which is the new dish or a warm-up).
	var star := -1
	if daily:
		star = 1 + rng.randi() % (count - 1)
	elif r >= 3 and rng.randf() < 0.5:
		star = 1 + rng.randi() % (count - 1)
	var patience := clampf(110.0 - 6.0 * r, PATIENCE_MIN, PATIENCE_MAX)
	var interval := clampf(14.0 - r, INTERVAL_MIN, INTERVAL_MAX) * rng.randf_range(0.95, 1.1)
	var max_wait := clampi(1 + r / 2, 1, 4)
	var raccoon := r >= 3 and (r < MENU_FROM or rng.randf() < 0.6)
	var m := {"round": r, "party": party, "daily": daily, "menu": menu, "orders": orders, "count": count, "star": star,
		"patience": patience, "interval": interval, "max_wait": max_wait, "raccoon": raccoon,
		"gift": String(info["gift"]), "word": "TODAY'S PARTY" if daily else String(info["word"]),
		"line": String(info["line"]), "fresh": new_dish}
	# Fair pace: ease it until the simple kitchen model serves every order in time.
	var tries := 0
	while not simulate(m).is_empty() and tries < 40:
		tries += 1
		if int(m.max_wait) > 1 and tries % 2 == 1:
			m.max_wait = int(m.max_wait) - 1
		else:
			m.interval = minf(float(m.interval) * 1.12, INTERVAL_MAX)
			m.patience = minf(float(m.patience) * 1.05, PATIENCE_MAX)
	return m


## Seconds for one dish in the kitchen model, as [busy, latency]: `busy` = how long the slowest helper
## (the runner fetching, the solo kitchen helpers, or the chef chopping and stacking) is tied up,
## `latency` = from starting it to the customer getting it.
static func dish_time(d: String) -> Array:
	var items: Array = DISHES[d]
	var fetch := 0.0
	var chef := 1.0
	for k in items:
		var stand := L.source_stand(k)
		var dist := Vector2(stand.x, stand.z).distance_to(Vector2(0.0, -0.8))
		fetch += 2.0 * dist / RUN_SPEED + 1.0
		chef += STACK_S + float(CHOPS.get(k, 0)) * CHOP_S
	var helper := HELPER_FIRST + HELPER_NEXT * float(items.size() - 1)
	var busy := maxf(maxf(fetch, helper), chef)
	return [busy, maxf(fetch, helper) + chef + SERVE_S]


## The kitchen model: customers arrive every `interval` * 0.85 (the quick end of the random spawn
## gap), never more than `max_wait` at once; one dish at a time is fetched / made, in order. Returns
## the orders (indices) that would run out of patience (empty = fair).
static func simulate(m: Dictionary) -> Array:
	var late: Array = []
	var orders: Array = m.orders
	var count := int(m.count) + SPARE
	var arrive: Array = []
	var served: Array = []
	var free_at := 0.0
	var next_arrival := 1.5
	for j in mini(count, orders.size()):
		var a := next_arrival
		var mw := int(m.max_wait)
		if j >= mw:
			a = maxf(a, float(served[j - mw]))
		arrive.append(a)
		var t: Array = dish_time(String(orders[j]))
		var start := maxf(free_at, a)
		free_at = start + float(t[0])
		var done := start + float(t[1])
		served.append(done)
		var pm := float(PATIENCE_MULT.get(String(m.party), 1.0)) * (STAR_PATIENCE if j == int(m.star) else 1.0)
		if done - a > float(m.patience) * pm:
			late.append(j)
		next_arrival = a + float(m.interval) * 0.85
	return late


## Why a round is not fair (empty = fine). Pure data checks.
static func check(m: Dictionary, progress: Dictionary) -> Array:
	var out: Array = []
	var r := int(m.get("round", 0))
	var party := String(m.get("party", ""))
	if not PARTIES.has(party):
		out.append("unknown party %s" % party)
		return out
	if not bool(m.daily) and r >= CHOICE_FROM and not parties_open(progress).has(party):
		out.append("party %s isn't open with %d gifts" % [party, int(progress.get("gifts", 0))])
	if r <= 1 and party != "granny":
		out.append("round 1 should be Gran's friends")
	var known := known_dishes(r, progress)
	var menu: Array = m.get("menu", [])
	if menu.is_empty():
		out.append("empty menu")
	for d in menu:
		if not DISHES.has(d):
			out.append("unknown dish %s" % d)
		elif not known.has(d):
			out.append("dish %s isn't known in round %d" % [d, r])
		for k in DISHES.get(d, []):
			if L.source_pos(k) == Vector3.ZERO:
				out.append("no crate or garden bed for %s" % k)
	# No dish may be a part of another on the same menu (the plate would DING too early).
	for a in menu:
		for b in menu:
			if a != b and _subset(DISHES.get(a, []), DISHES.get(b, [])):
				out.append("%s is inside %s" % [a, b])
	var orders: Array = m.get("orders", [])
	var count := int(m.get("count", 0))
	if count < 2 or count > MAX_ORDERS - SPARE:
		out.append("count %d out of range" % count)
	if orders.size() != count + SPARE:
		out.append("%d orders for count %d" % [orders.size(), count])
	for d in orders:
		if not menu.has(d):
			out.append("order %s isn't on the menu" % d)
	var lesson := lesson_dish(r)
	if lesson != "" and (orders.is_empty() or orders[0] != lesson):
		out.append("the new dish %s isn't first" % lesson)
	if lesson != "" and not menu.has(lesson):
		out.append("the new dish %s isn't on the menu" % lesson)
	var star := int(m.get("star", -1))
	if star != -1 and (star < 1 or star >= count):
		out.append("star guest %d out of range" % star)
	if bool(m.daily) and star == -1:
		out.append("today's party has no star guest")
	if float(m.patience) < PATIENCE_MIN - 0.01 or float(m.patience) > PATIENCE_MAX + 0.01:
		out.append("patience %.1f" % float(m.patience))
	if float(m.interval) < INTERVAL_MIN * 0.95 - 0.01 or float(m.interval) > INTERVAL_MAX + 0.01:
		out.append("interval %.1f" % float(m.interval))
	if int(m.max_wait) < 1 or int(m.max_wait) > 4:
		out.append("max_wait %d" % int(m.max_wait))
	if String(m.get("gift", "")) != String(PARTIES[party]["gift"]):
		out.append("wrong gift")
	var word := String(m.get("word", ""))
	if not RegEx.create_from_string("^[A-Z][A-Z' ]{1,15}$").search(word):
		out.append("name %s isn't a short title" % word)
	var late := simulate(m)
	if not late.is_empty():
		out.append("orders %s can't be served in time" % [late])
	return out


static func _subset(a: Array, b: Array) -> bool:
	for k in a:
		if not b.has(k):
			return false
	return true


## After a round with `party`: what's new? {"teach": dish or "", "guests": party type now open or ""}.
static func news(before: Dictionary, after: Dictionary) -> Dictionary:
	var out := {"teach": "", "guests": ""}
	var tb := taught(before)
	for d in taught(after):
		if not tb.has(d):
			out["teach"] = d
	var ob := parties_open(before)
	for p in parties_open(after):
		if not ob.has(p):
			out["guests"] = p
	return out
