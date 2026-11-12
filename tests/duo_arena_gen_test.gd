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
## Prints "SCRIPT ERROR: ..." per failure and "BOT RESULT: PASS|FAIL".

const Gen := preload("res://games/duo_arena/arenagen.gd")
const Bosses := preload("res://games/duo_arena/bosses.gd")
const Picks := preload("res://games/duo_arena/picks.gd")
const Prog := preload("res://games/duo_arena/progress.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0
var checks := 0


func _initialize() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 120
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
			return all,
		func(all: Array) -> Array:
			var why: Array = []
			for x in all:
				if x.has("perk"):
					why.append_array(Picks.check_offer("perk", x.perk, x.open))
				elif x.has("route"):
					why.append_array(_check_route(x.route, x.open))
				else:
					why.append_array(Gen.check(x))
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
			return all,
		func(all: Array) -> Array:
			var why: Array = []
			for x in all:
				if x.has("perk"):
					why.append_array(Picks.check_offer("perk", x.perk, x.open))
				elif x.has("route"):
					why.append_array(_check_route(x.route, x.open))
				else:
					why.append_array(Gen.check(x))
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
	# Trophy Hall.
	var today := Seeded.today()
	var sm := Prog.progress_summary(Prog.sample(today), today)
	_expect(int(sm.grown) > 0 and bool(sm.daily), "progress.gd reads its sample (%s)" % sm)
	_expect(not bool(Prog.progress_summary({"daily": today}, today).daily), "a started daily isn't read as done")
	print("BOT RESULT: %s (%d checks, %d failures)" % ["PASS" if fails == 0 else "FAIL", checks, fails])
	quit(1 if fails > 0 else 0)


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
