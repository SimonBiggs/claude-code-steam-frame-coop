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
## Prints "SCRIPT ERROR: ..." for each failure.

const Parties := preload("res://games/kitchen_rush/parties.gd")
const Seeded := preload("res://core/seeded.gd")
const Cafe := preload("res://games/kitchen_rush/cafe.gd")

var fails := 0


func _progress(k: int) -> Dictionary:
	# A spread of saved progress: gifts and visits growing together.
	var visits := {}
	var i := 0
	for p in Parties.PARTY_ORDER:
		visits[p] = (k + i) % 4 if k > 0 else 0
		i += 1
	return {"gifts": [0, 1, 2, 3, 4, 6, 9, 15, 40][k % 9], "visits": visits}


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 120
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
					out.append(m)
					last = String(m.party)
				return out,
			func(rounds: Array) -> Array:
				var why: Array = []
				for m in rounds:
					for w in Parties.check(m, prog):
						why.append("round %d: %s" % [int(m.round), w])
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
	# A few sample rounds to read.
	var prog := {"gifts": 9, "visits": {"robot": 2, "alien": 2, "knight": 1}}
	for rn in [1, 2, 3, 5, 8, 12, 20]:
		var m := Parties.make(rn, 4242, prog, "")
		print("round %d %s menu=%s count=%d star=%d patience=%.0f interval=%.1f max_wait=%d raccoon=%s orders=%s" % [rn, m.party, m.menu,
			m.count, m.star, m.patience, m.interval, m.max_wait, m.raccoon, m.orders])
	for d in Parties.DISHES:
		print("dish %s time %s" % [d, Parties.dish_time(d)])
	print("KR_ROUNDS: %d round lists checked, %d failures (%d ms)" % [total, fails, Time.get_ticks_msec() - t0])
	quit(1 if fails > 0 else 0)
