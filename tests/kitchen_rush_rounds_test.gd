extends SceneTree
## KITCHEN RUSH party rounds (SIMPLE_MODE, games/kitchen_rush/parties.gd): checks many seeds, no window.
##   godot-test --headless --path . -s res://tests/kitchen_rush_rounds_test.gd      (SEEDS=300 for more)
##  - every round 1-30 is fair for many progress states (0-40 gifts, 0-3 visits of each party): a known
##    party that is open (or today's party), a menu of known dishes where no dish is inside another (the
##    plate would DING too early), every ingredient has a crate / garden bed, the lesson dish first in
##    rounds 2-4, orders only from the menu, star guest in range (today's party always has one), pace
##    and patience in their limits, a short title name, and the kitchen model (one runner or the solo
##    helpers, one dish at a time) serves every order in time;
##  - both invitations are open, different party types; round 1 is Gran's friends; round 2 is today's
##    party for every seed and every choice;
##  - the same seed makes the same rounds; every party, gift and taught dish shows up over the seeds.
##  - second pass (games/kitchen_rush/nights.gd): every theme night, every mode; GENTLE <= BRAVE <= HARD in every
##    pressure number (patience, pace, waiting, events) for the same round; events start late enough to be warned,
##    are spaced out and never cover a crate, the pass, the window or the back door; gift picks offer different
##    gifts not taken yet; the café grows step by step.
## Prints "SCRIPT ERROR: ..." for each failure.

const Parties := preload("res://games/kitchen_rush/parties.gd")
const Seeded := preload("res://core/seeded.gd")
const Cafe := preload("res://games/kitchen_rush/cafe.gd")
const Nights := preload("res://games/kitchen_rush/nights.gd")

var fails := 0


func _progress(k: int) -> Dictionary:
	# A spread of saved progress: gifts and visits growing together.
	var visits := {}
	var i := 0
	for p in Parties.PARTY_ORDER:
		visits[p] = (k + i) % 4 if k > 0 else 0
		i += 1
	return {"gifts": [0, 1, 2, 3, 4, 6, 9, 15, 40][k % 9], "visits": visits, "theme": Nights.THEME_ORDER[k % 3]}


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 60
	var t0 := Time.get_ticks_msec()
	var seen := {}
	var total := 0
	for k in 9:
		var prog := _progress(k)
		var r := Seeded.validate(func(s: int) -> Array:
				var out: Array = []
				var last := ""
				var fresh_left: Array = Parties.taught(prog)
				for rn in range(1, 31):
					var offers := Parties.offers(rn, s, prog, last)
					# Alternate the choice so both invitations get played.
					var party: String = "" if offers.is_empty() else String(offers[rn % 2])
					var fresh := ""
					if rn >= Parties.MENU_FROM and not fresh_left.is_empty():
						fresh = fresh_left.pop_front()
					var m := Parties.make(rn, s, prog, party, fresh)
					m["offers"] = offers
					var pg := prog.duplicate()
					pg["mode"] = "gentle"
					m["gentle"] = Parties.make(rn, s, pg, party, fresh)
					pg["mode"] = "hard"
					m["hard"] = Parties.make(rn, s, pg, party, fresh)
					m["gift_offer"] = Nights.gift_offer(rn, s, Nights.GIFT_ORDER.slice(0, rn % 3))
					m["taken"] = Nights.GIFT_ORDER.slice(0, rn % 3)
					out.append(m)
					last = String(m.party)
				return out,
			func(rounds: Array) -> Array:
				var why: Array = []
				for m in rounds:
					for w in Parties.check(m, prog):
						why.append("round %d: %s" % [int(m.round), w])
					for md in ["gentle", "hard"]:
						var mm: Dictionary = m[md]
						if String(mm.mode) != md:
							why.append("round %d: %s round says mode %s" % [int(m.round), md, mm.mode])
						for w in Parties.check(mm, prog):
							why.append("round %d %s: %s" % [int(m.round), md, w])
						if mm.orders != m.orders or mm.menu != m.menu or mm.party != m.party:
							why.append("round %d: %s changes the orders" % [int(m.round), md])
					var pg: Array = Nights.pressure(m.gentle)
					var pb: Array = Nights.pressure(m)
					var ph: Array = Nights.pressure(m.hard)
					for i in pb.size():
						if float(pg[i]) > float(pb[i]) + 0.001 or float(pb[i]) > float(ph[i]) + 0.001:
							why.append("round %d: not gentle <= brave <= hard (%d: %.2f %.2f %.2f)" % [int(m.round), i, pg[i], pb[i], ph[i]])
					for e in m.hard.events:
						seen["event:" + String(e[1])] = true
					var go: Array = m.gift_offer
					if Nights.GIFT_BEFORE.has(int(m.round)):
						if go.size() != mini(3, Nights.GIFT_ORDER.size() - (m.taken as Array).size()):
							why.append("round %d: %d gifts offered" % [int(m.round), go.size()])
						for g in go:
							if (m.taken as Array).has(g) or go.count(g) > 1 or not Nights.GIFTS.has(g):
								why.append("round %d: gift %s offered twice or taken" % [int(m.round), g])
							seen["gift:" + String(g)] = true
					elif not go.is_empty():
						why.append("round %d: gifts offered off the gift rounds" % int(m.round))
					var offers: Array = m.offers
					if int(m.round) >= Parties.CHOICE_FROM:
						if offers.size() != 2 or offers[0] == offers[1]:
							why.append("round %d: offers %s" % [int(m.round), offers])
						for o in offers:
							if not Parties.parties_open(prog).has(o):
								why.append("round %d: offer %s not open" % [int(m.round), o])
						if not bool(m.daily) and not offers.has(m.party):
							why.append("round %d: party %s wasn't offered" % [int(m.round), m.party])
					if int(m.round) == Parties.DAILY_ROUND and (m.party != Parties.daily_party() or not bool(m.daily)):
						why.append("round 2 isn't today's party")
					var o: Array = m.orders
					for j in range(2, o.size()):
						if m.menu.size() > 1 and o[j] == o[j - 1] and o[j] == o[j - 2]:
							why.append("round %d: three %s in a row" % [int(m.round), o[j]])
					seen["party:" + String(m.party)] = true
					for d in m.menu:
						seen["dish:" + String(d)] = true
					if not Cafe.GIFTS.has(String(m.gift)):
						why.append("round %d: no shelf model for gift %s" % [int(m.round), m.gift])
				return why, seeds, 1, [], "KR_ROUNDS %d" % k)
		total += int(r.checked)
		fails += r.failures.size()
	for p in Parties.PARTY_ORDER:
		if not seen.has("party:" + p):
			print("SCRIPT ERROR: KR_ROUNDS party %s never came" % p)
			fails += 1
	for d in Parties.DISHES:
		if not seen.has("dish:" + d):
			print("SCRIPT ERROR: KR_ROUNDS dish %s never on a menu" % d)
			fails += 1
	for e in Nights.EVENT_KINDS:
		if not seen.has("event:" + String(e)):
			print("SCRIPT ERROR: KR_ROUNDS event %s never happened" % e)
			fails += 1
	for g in Nights.GIFT_ORDER:
		if not seen.has("gift:" + String(g)):
			print("SCRIPT ERROR: KR_ROUNDS gift %s never offered" % g)
			fails += 1
	if Nights.WARN_SECS < 2.5 or Nights.EVENT_FIRST < Nights.WARN_SECS + 5.0:
		print("SCRIPT ERROR: KR_ROUNDS events need a longer warning")
		fails += 1
	var lv := 0
	for n in 40:
		var l2 := Nights.cafe_level(n)
		if l2 < lv or l2 > lv + 1 or (l2 > 0 and Nights.cafe_step(l2) == ""):
			print("SCRIPT ERROR: KR_ROUNDS café level %d after %d parties" % [l2, n])
			fails += 1
		lv = l2
	var themes := {}
	for d in 60:
		themes[Nights.theme_for("2026-01-%02d" % (d % 28 + 1)) if d < 28 else Nights.theme_for("2026-02-%02d" % (d - 27))] = true
	if themes.size() != Nights.THEME_ORDER.size():
		print("SCRIPT ERROR: KR_ROUNDS theme nights seen %s" % [themes.keys()])
		fails += 1
	for th in Nights.THEMES:
		if not Parties.DISHES.has(Nights.theme_dish(th)):
			print("SCRIPT ERROR: KR_ROUNDS theme %s dish unknown" % th)
			fails += 1
	# A few sample rounds to read.
	var prog := {"gifts": 9, "visits": {"robot": 2, "alien": 2, "knight": 1}}
	for rn in [1, 2, 3, 5, 8, 12, 20]:
		prog["mode"] = ["gentle", "brave", "hard"][rn % 3]
		prog["theme"] = Nights.THEME_ORDER[rn % 3]
		var m := Parties.make(rn, 4242, prog, "")
		print("round %d %s menu=%s count=%d star=%d patience=%.0f interval=%.1f max_wait=%d raccoon=%s orders=%s %s %s events=%s" % [rn, m.party, m.menu,
			m.count, m.star, m.patience, m.interval, m.max_wait, m.raccoon, m.orders, m.mode, m.theme, m.events])
	for d in Parties.DISHES:
		print("dish %s time %s" % [d, Parties.dish_time(d)])
	print("KR_ROUNDS: %d round lists checked, %d failures (%d ms)" % [total, fails, Time.get_ticks_msec() - t0])
	quit(1 if fails > 0 else 0)
