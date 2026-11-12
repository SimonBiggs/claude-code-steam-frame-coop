extends SceneTree
## DUO ARENA validator: proves every seeded arena, route, wave curve, boss tell, hazard and pick is fair and smooth
## (no game, no window).
##   godot-test --headless --path . -s res://tests/duo_arena_gen_test.gd      (SEEDS=500 for more)
## - arenagen.gd layout() for every zone over many seeds: check() (pillars and pads off the start spots and pick orbs,
##   nothing overlapping, inside the wall, every open spot reachable on foot); the same seed gives the same arena.
## - route(): NEON CITY first, every unlocked zone once, only unlocked zones; TODAY'S ARENA is the same all day.
## - plan(): check_curve() for every mode and party size 1..7 (every wave a little harder, never a cliff; gentle <=
##   brave <= hard; a tiny gentle solo start).
## - bosses.gd check() for every boss (tells long enough, gentle hits soft, a breather between attacks).
## - hazard numbers, pick lists (names fit, pictures exist, capped stats) and perk offers at every unlock level.
## - the validator really catches bad layouts / curves; progress.gd reads its sample; generation is fast.
## - Second pass (deep.gd): arena SHAPES + NOVA'S SPRING (reachable, off pillars and pads), every zone's TOLD
##   SURPRISES for every wave / mode (late enough, told long enough to step out, a rest between, inside the wall),
##   NOVA'S GIFT offers at every friends-saved level, friends and gifts data, today's surprises over 400+ days.
## Prints "SCRIPT ERROR: ..." per failure and "BOT RESULT: PASS|FAIL" + "DUO ARENA GEN: PASS|FAIL".

const Gen := preload("res://games/duo_arena/arenagen.gd")
const Bosses := preload("res://games/duo_arena/bosses.gd")
const Picks := preload("res://games/duo_arena/picks.gd")
const Prog := preload("res://games/duo_arena/progress.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")
const Deep := preload("res://games/duo_arena/deep.gd")
const TestTime := preload("res://tests/test_time.gd")

var fails := 0
var checks := 0


func _initialize() -> void:
	var seeds := Seeded.test_count(int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 120)
	var t0 := Time.get_ticks_usec()
	var res := Seeded.validate(func(s: int) -> Array:
			var all: Array = []
			for z in Gen.zone_ids():
				all.append(Gen.layout(Gen.leg_seed(s, 0), z))
				all.append(Gen.layout(Gen.leg_seed(s, 3), z))
			for lv in [0, 3, 8, 15, 25, 99]:
				var open := Picks.unlocked("perk", lv)
				for n in [1, 4, 9, 14]:
					all.append({"perk": Picks.offer("perk", s, n, open), "open": open})
				var zo := Gen.unlocked_zones(lv)
				all.append({"route": Gen.route(s, zo), "open": zo})
			for z in Gen.zone_ids():
				for mode in Gen.MODES:
					for w in [1, 2, 3, 4, 5, 7, 8, 9, 13, 21]:
						all.append({"surprises": Deep.plan(s, w, z, mode), "wave": w, "zone": z, "mode": mode})
			all.append_array(_gift_runs(s))
			return all,
		func(all: Array) -> Array:
			var why: Array = []
			for x in all:
				why.append_array(_check_any(x))
			return why,
		seeds, 1, [0, 999999, Gen.daily_seed("2026-11-11")], "ARENA")
	fails += (res.failures as Array).size()
	checks += int(res.checked)
	var arenas := seeds * Gen.ZONES.size() * 2
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, arenas)
	print("arena gen: %.3f ms per arena incl. checks (%d arenas)" % [per_ms, arenas])
	_expect(per_ms < 30.0, "an arena generates + checks in under 30 ms here (%.2f ms; Decks ~3x slower, aim < 100)" % per_ms)
	# Variety and determinism.
	var differ := 0
	for s in 20:
		if var_to_str(Gen.layout(s * 13 + 1, "jungle")) != var_to_str(Gen.layout(s * 13 + 2, "jungle")):
			differ += 1
	_expect(differ >= 18, "different seeds give different arenas (%d of 20)" % differ)
	_expect(Gen.daily_seed("2026-11-11") == Gen.daily_seed("2026-11-11"), "TODAY'S ARENA is the same all day")
	_expect(Gen.daily_seed("2026-11-11") != Gen.daily_seed("2026-11-12"), "TODAY'S ARENA changes each day")
	# TODAY'S ARENA over 400+ days (Seeded.validate_days, the shared daily validator), as main.gd _start_run() /
	# _enter_leg() play it: for a new, a mid and a long-time family (waves 0 / 15 / 99 unlock more zones and perks) the
	# day's route (NEON CITY first, only unlocked zones), every leg's arena on it (check()) and the perk offers of the
	# first legs (check_offer), the same all day.
	var rs := Seeded.validate_days(func(date: String) -> Array:
			var ds := Gen.daily_seed(date)
			var all: Array = []
			for lv in [0, 15, 99]:
				var zo := Gen.unlocked_zones(lv)
				var rt := Gen.route(ds, zo)
				all.append({"route": rt, "open": zo})
				for l in rt.size():
					all.append(Gen.layout(Gen.leg_seed(ds, l), Gen.zone_for_wave(rt, l * Gen.LEG + 1)))
				var open := Picks.unlocked("perk", lv)
				for n in [1, 3, 6, 9]:
					all.append({"perk": Picks.offer("perk", ds, n, open), "open": open})
				for w in range(1, 16):
					var z := Gen.zone_for_wave(rt, w)
					all.append({"surprises": Deep.plan(ds, w, z, ["gentle", "brave", "hard"][lv % 3]), "wave": w, "zone": z,
						"mode": ["gentle", "brave", "hard"][lv % 3]})
			all.append_array(_gift_runs(ds))
			return all,
		func(all: Array) -> Array:
			var why: Array = []
			for x in all:
				why.append_array(_check_any(x))
			return why, 400, "TODAY'S ARENA", ["2026-11-11", "2026-11-12"])
	fails += (rs.failures as Array).size()
	checks += int(rs.checked)
	# The wave curve.
	for mode in Gen.MODES:
		for players in range(1, 8):
			for why in Gen.check_curve(mode, players):
				_fail("curve: " + why)
			checks += 1
	var g1 := Gen.plan(1, "gentle", 1)
	print("curve: gentle solo wave 1 = %d monsters; brave duo wave 5 = %d (+ boss); hard x6 wave 12 = %d" % [int(g1.count),
		int(Gen.plan(5, "brave", 2).count), int(Gen.plan(12, "hard", 6).count)])
	# Bosses and hazards.
	for k in Bosses.KINDS:
		for why in Bosses.check(k):
			_fail("boss: " + why)
		checks += 1
		_expect(StoryCard.has_picture(String(Bosses.info(k).pic)), "%s has a picture" % k)
	for why in Gen.check_hazards():
		_fail("hazard: " + why)
	for z in Gen.ZONES:
		_expect(StoryCard.has_picture(String(z.pic)), "%s has a picture" % z.id)
		_expect(String(z.hazard) == "" or Gen.HAZARDS.has(String(z.hazard)), "%s's hazard exists" % z.id)
	# Picks.
	var ui_src := FileAccess.get_file_as_string("res://core/ui_kit.gd")
	for why in Picks.check_lists(func(n: String) -> bool: return StoryCard.has_picture(n) or (Picks.UI_ICONS.has(n) and ui_src.contains('"%s":' % n))):
		_fail("picks: " + why)
	for lv in [0, 2, 6, 12, 99]:
		for why in Picks.check_offer("hero", Picks.offer("hero", 1, 0, Picks.unlocked("hero", lv), "blaster"), Picks.unlocked("hero", lv)):
			_fail("heroes: " + why)
	# A player who took every perk 20 times stays inside the caps.
	var fake := {"fire_rate": 1.0, "damage": 1.0, "dash_cd": 1.0, "speed": 1.0, "max_hp": 0.0, "armor": 1.0}
	for i in 20:
		for d in Picks.PERKS:
			for fx in d.fx:
				fake[fx[0]] = float(fake[fx[0]]) * float(fx[2]) if fx[1] == "mul" else float(fake[fx[0]]) + float(fx[2])
			Picks.clamp_personal(fake)
	_expect(float(fake.fire_rate) >= 0.35 and float(fake.damage) <= 4.0 and float(fake.armor) >= 0.4, "stacked perks stay capped (%s)" % fake)
	# The validator catches bad things.
	var bad := Gen.layout(5, "lava")
	(bad.pillars as Array).append(Vector3(0, 0, -3.5))
	_expect(not Gen.check(bad).is_empty(), "the validator catches a pillar on the pick orbs")
	var walled := {"zone": "neon", "pads": [], "pillars": []}
	for a in 24:
		walled.pillars.append(Vector3(cos(a * TAU / 24.0) * 8.0, 0, sin(a * TAU / 24.0) * 8.0).snapped(Vector3(0.5, 1, 0.5)))
	var wwhy := Gen.check(walled)
	_expect(wwhy.any(func(w: String) -> bool: return w.contains("reached")), "the validator catches a walled-off ring (%s)" % [wwhy.slice(0, 2)])
	var pad_bad := Gen.layout(9, "jungle")
	if not (pad_bad.pads as Array).is_empty():
		pad_bad.pads[0].p = Vector3(0, 0, 0)
		_expect(not Gen.check(pad_bad).is_empty(), "the validator catches a pad on the start")
	# Second pass: shapes, springs, surprises, gifts, friends.
	var shapes := {}
	var springs := 0
	for s in 60:
		var lay := Gen.layout(Gen.leg_seed(s * 7 + 3, 0), "neon")
		shapes[String(lay.shape)] = true
		springs += 1 if lay.has("spring") else 0
	_expect(shapes.size() == Gen.SHAPES.size(), "every arena shape turns up (%s)" % [shapes.keys()])
	_expect(springs == 60, "every arena has Nova's spring (%d of 60)" % springs)
	var bad_spring := Gen.layout(11, "jungle")
	bad_spring.spring = (bad_spring.pillars[0] as Vector3)
	_expect(not Gen.check(bad_spring).is_empty(), "the validator catches a spring under a pillar")
	var sp_plan := Deep.plan(5, 4, "jungle", "brave")
	_expect(not sp_plan.is_empty(), "a brave wave 4 in the jungle has surprises")
	_expect(Deep.plan(5, 1, "jungle", "hard").is_empty() and Deep.plan(5, 5, "jungle", "hard").is_empty(), "no surprise in wave 1 or on a boss wave")
	var early := [{"t": 7.0, "id": "crate", "ang": 0.0, "off": 0.5, "who": 0}]
	_expect(not Deep.check_plan(early, 1, "neon", "brave").is_empty(), "the validator catches a surprise in wave 1")
	var close := [{"t": 7.0, "id": "crate", "ang": 0.0, "off": 0.5, "who": 0}, {"t": 9.0, "id": "crate", "ang": 1.0, "off": 0.5, "who": 0}]
	_expect(not Deep.check_plan(close, 4, "neon", "brave").is_empty(), "the validator catches two surprises too close")
	var wrong := [{"t": 7.0, "id": "snowball", "ang": 0.0, "off": 0.5, "who": 0}]
	_expect(not Deep.check_plan(wrong, 4, "lava", "brave").is_empty(), "the validator catches another zone's surprise")
	for z in Gen.zone_ids():
		_expect(Deep.ZONE_SURPRISES.has(z), "%s has a told surprise" % z)
	for id in Deep.SURPRISES:
		_expect(StoryCard.has_picture(String(Deep.SURPRISES[id].pic)), "surprise %s has a picture" % id)
		_expect(String(Deep.SURPRISES[id].name).length() <= 14, "surprise %s's banner is short" % id)
	for f in Deep.FRIENDS:
		_expect(StoryCard.has_picture(String(f.pic)), "friend %s has a picture" % f.id)
		_expect(Gen.zone_ids().has(String(f.zone)) and String(f.zone) != "neon", "friend %s waits in a far zone" % f.id)
		_expect(not Deep.gift(String(f.gift)).is_empty() and String(Deep.gift(String(f.gift)).friend) == String(f.id), "friend %s brings its gift" % f.id)
	_expect(Deep.open_gifts({}).size() >= Deep.GIFT_OFFER, "a new family has %d gifts to pick from" % Deep.GIFT_OFFER)
	_expect(Deep.open_gifts({"sprout": 1, "ember": 1, "flurry": 1, "comet": 1}).size() == Deep.GIFTS.size(), "every friend opens a gift")
	_expect(Deep.towers(0) == 0 and Deep.towers(30) == 10 and Deep.towers(100000) == Deep.TOWERS, "Nova's city grows with the waves (capped)")
	# Worst case time: one zone's arena + a wave's surprises (TestTime: a busy machine spike can't fail it).
	var worst := 0.0
	for k in 40:
		var one := func() -> Variant:
			var l := Gen.layout(98765 + k, "star")
			return [Gen.check(l), Deep.check_plan(Deep.plan(98765 + k, 9, "star", "hard"), 9, "star", "hard")]
		var t1 := Time.get_ticks_usec()
		one.call()
		worst = TestTime.worst(worst, (Time.get_ticks_usec() - t1) / 1000.0, one)
	_expect(worst < 30.0, "an arena + its surprises generate and check in < 30 ms (%.2f ms; Decks ~3x)" % worst)
	# Trophy Hall.
	var today := Seeded.today()
	var sm := Prog.progress_summary(Prog.sample(today), today)
	_expect(int(sm.grown) > 0 and bool(sm.daily), "progress.gd reads its sample (%s)" % sm)
	_expect(not bool(Prog.progress_summary({"daily": today}, today).daily), "a started daily isn't read as done")
	print("BOT RESULT: %s (%d checks, %d failures)" % ["PASS" if fails == 0 else "FAIL", checks, fails])
	print("DUO ARENA GEN: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(1 if fails > 0 else 0)


func _check_any(x: Dictionary) -> Array:
	if x.has("perk"):
		return Picks.check_offer("perk", x.perk, x.open)
	if x.has("route"):
		return _check_route(x.route, x.open)
	if x.has("surprises"):
		return Deep.check_plan(x.surprises, int(x.wave), String(x.zone), String(x.mode))
	if x.has("gift"):
		return Deep.check_gift_offer(x.gift, x.open, x.owned)
	return Gen.check(x)


## Nova's gift offers through a run (each leg's pick taken, the middle orb) for a new family, one with two friends and
## one with every friend saved.
func _gift_runs(s: int) -> Array:
	var out: Array = []
	for saved in [{}, {"sprout": 1, "ember": 1}, {"sprout": 1, "ember": 1, "flurry": 1, "comet": 1}]:
		var open := Deep.open_gifts(saved)
		var owned: Array = []
		for leg in range(1, 8):
			var ids := Deep.gift_offer(s, leg, open, owned)
			out.append({"gift": ids, "open": open, "owned": owned.duplicate()})
			if ids.size() >= 2:
				owned.append(ids[ids.size() / 2])
	return out


func _check_route(rt: Array, open: Array) -> Array:
	var why: Array = []
	if rt.is_empty() or String(rt[0]) != "neon":
		why.append("route doesn't start in NEON CITY: %s" % [rt])
	for z in rt:
		if not open.has(z):
			why.append("route visits %s before it is unlocked" % z)
	for z in open:
		if rt.count(z) != 1:
			why.append("route visits %s %d times" % [z, rt.count(z)])
	return why


func _expect(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: %s" % what)
