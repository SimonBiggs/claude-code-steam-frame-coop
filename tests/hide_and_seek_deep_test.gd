extends SceneTree
## HIDE AND SEEK second pass (games/hide_and_seek/deep.gd): proves the new things fair over many seeds and days.
##   godot-test --headless --path . -s res://tests/hide_and_seek_deep_test.gd     (SEEDS / DAYS for more; GEN_QUICK=1 samples)
## - RUMBLE'S SURPRISES: never in round 1 or alone, at most the mode's count, every tell at least MIN_TELL long, none
##   before the seeker sets off or in the last seconds, never two close together; same seed same plan.
## - TODAY'S STREET: its surprises for the first rounds of the day and its pick orbs (Seeded.validate_days, 400+ days).
## - PICK ORBS: on every house (small and big, every twist) the three orbs stand on floor a hider AND the seeker can
##   walk to (housegen raster), clear of every spawn, the jail and the bell; the castle's and the spaceship's too.
## - PIP'S GIFTS: three different gifts for the side that picks, the same three for the same round, every gift
##   offered somewhere; Rumble's band never longer than his reach, never through a wall; the kennel grows in order;
##   every gift, surprise, season and kennel card has a story picture. A plan is made in well under a millisecond.

const Deep := preload("res://games/hide_and_seek/deep.gd")
const HouseGen := preload("res://games/hide_and_seek/housegen.gd")
const Street := preload("res://games/hide_and_seek/street.gd")
const Story := preload("res://games/hide_and_seek/story.gd")
const Castle := preload("res://games/hide_and_seek/map_castle.gd")
const Ship := preload("res://games/hide_and_seek/map_ship.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")
const TestTime := preload("res://tests/test_time.gd")

var fails := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var seeds := Seeded.test_count(int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 300)
	# Surprise plans over seeds x modes x round lengths x rounds.
	var worst_ms := 0.0
	for mode in Deep.MODES:
		for seek in [90.0, 140.0, 160.0, 190.0, 25.0]:
			var r := Seeded.validate(func(s: int) -> Array:
					var out: Array = []
					for rn in range(1, 7):
						out.append([rn, Deep.plan(s, rn, mode, seek, false)])
					return out,
				func(all: Array) -> Array:
					var w: Array = []
					for e in all:
						w.append_array(Deep.check_plan(e[1], int(e[0]), mode, seek, false))
					return w, seeds, 1, [0, 999999], "SURPRISES %s %.0f" % [mode, seek])
			fails += (r.failures as Array).size()
		_expect(Deep.plan(5, 3, mode, 160.0, true).is_empty(), "no surprises alone (%s)" % mode)
		_expect(Deep.plan(5, 1, mode, 160.0, false).is_empty(), "no surprises in round 1 (%s)" % mode)
		_expect(float(Deep.MODES[mode].tell) >= Deep.MIN_TELL, "%s tells last long enough" % mode)
	var t1 := Time.get_ticks_usec()
	Deep.plan(123, 4, "hard", 190.0, false)
	worst_ms = TestTime.worst(worst_ms, (Time.get_ticks_usec() - t1) / 1000.0, func() -> Variant: return Deep.plan(123, 4, "hard", 190.0, false))
	_expect(worst_ms < 2.0, "a plan is quick (%.2f ms)" % worst_ms)
	var p2 := Deep.plan(77, 3, "brave", 160.0, false)
	_expect(not p2.is_empty() and var_to_str(p2) == var_to_str(Deep.plan(77, 3, "brave", 160.0, false)), "same seed, same surprises")
	var kinds := {}
	for s in 40:
		for e in Deep.plan(s, 3, "hard", 190.0, false):
			kinds[e.kind] = true
	_expect(kinds.size() == Deep.KINDS.size(), "both surprises turn up (%s)" % str(kinds.keys()))
	_expect(Deep.mode_data("gentle").surprises < Deep.mode_data("hard").surprises, "gentle has fewer surprises than hard")
	# The checks catch bad plans.
	_expect(not Deep.check_plan([{"t": 20.0, "kind": "pepper"}], 1, "brave", 160.0, false).is_empty(), "a round-1 surprise is caught")
	_expect(not Deep.check_plan([{"t": 20.0, "kind": "pepper"}, {"t": 25.0, "kind": "hoover"}], 3, "brave", 160.0, false).is_empty(), "two close surprises are caught")
	_expect(not Deep.check_plan([{"t": 150.0, "kind": "pepper"}], 3, "brave", 160.0, false).is_empty(), "a surprise at the end is caught")
	_expect(not Deep.check_plan([{"t": 5.0, "kind": "pepper"}], 3, "brave", 160.0, false).is_empty(), "a surprise at the very start is caught")
	# Pick orbs on houses (every size and twist) over many seeds: walkable for both, clear of spawns / jail / bell.
	for level in [0, 3, 6, 12]:
		var r2 := Seeded.validate(func(s: int) -> Dictionary:
				HouseGen.clear_cache()
				return HouseGen.generate(s, {"level": level, "theme": 0}),
			func(g: Dictionary) -> Array: return _house_picks(g), maxi(20, seeds / 6), 40 + level, [0, 1], "PICKS l%d" % level)
		fails += (r2.failures as Array).size()
	for m in [Castle, Ship]:
		for w in Deep.check_picks(m.data({})):
			_fail("%s: %s" % [m.TITLE, w])
	var bad := Castle.data({}).duplicate()
	bad["pick_spots"] = [Castle.SPAWNS[1], Vector3(0, 0, 0), Vector3(3, 0, 0)]
	_expect(not Deep.check_picks(bad).is_empty(), "a pick orb over a spawn is caught")
	# TODAY'S STREET: the day's house, its pick orbs and the surprises of its first rounds in every mode.
	var rs := Seeded.validate_days(func(date: String) -> Dictionary:
			var dd := Street.daily(date)
			HouseGen.clear_cache()
			var g := HouseGen.generate(int(dd.seed), dd)
			var plans := {}
			for mode in Deep.MODES:
				for rn in range(1, 5):
					plans["%s%d" % [mode, rn]] = Deep.plan(int(dd.seed), rn, mode, 150.0 + float(Deep.MODES[mode].seek_add), false)
			return {"g": g, "plans": plans},
		func(d: Dictionary) -> Array:
			var w := _house_picks(d.g)
			for k in d.plans:
				var mode := String(k).substr(0, String(k).length() - 1)
				w.append_array(Deep.check_plan(d.plans[k], int(String(k).right(1)), mode, 150.0 + float(Deep.MODES[mode].seek_add), false))
			return w, int(OS.get_environment("DAYS")) if OS.has_environment("DAYS") else 400, "TODAY'S SURPRISES", ["2026-11-12", "2026-11-13"])
	fails += (rs.failures as Array).size()
	# Gifts.
	var offered := {}
	for side in ["seeker", "hider"]:
		for s in 60:
			var c := Deep.gift_choices(s, 2 + s % 5, side)
			_expect(c.size() == Deep.GIFT_CHOICES, "three gifts")
			var uniq := {}
			for id in c:
				uniq[id] = true
				offered[id] = true
				_expect(Deep.gift_for(id, side), "%s is a %s gift" % [id, side])
			_expect(uniq.size() == c.size(), "three different gifts")
			_expect(c == Deep.gift_choices(s, 2 + s % 5, side), "same round, same gifts")
	_expect(offered.size() == Deep.GIFTS.size(), "every gift is offered somewhere (%d of %d)" % [offered.size(), Deep.GIFTS.size()])
	for g in Deep.GIFTS:
		_expect(StoryCard.has_picture(String(g.pic)), "the %s has a picture" % g.id)
	for k in Deep.KINDS:
		_expect(StoryCard.has_picture(String(Deep.KIND_PICS[k])), "the %s has a picture" % k)
	for s in Deep.SEASONS:
		_expect(StoryCard.has_picture(String(Deep.SEASONS[s].pic)), "%s has a picture" % s)
	_expect(StoryCard.has_picture("kennel"), "the kennel has a picture")
	for w in StoryCard.check():
		_fail(w)
	# Rumble's band.
	var hb := Deep.hoover_band(Vector3(1, 0, 1), Vector3.RIGHT, 9.0, 0.5)
	_expect(not hb.is_empty() and float(hb.len) <= Deep.HOOVER_REACH + 0.5 + 0.01 and (hb.from as Vector3).x >= 1.0 - Deep.HOOVER_REACH - 0.01, "the band stops at his reach and at the wall")
	_expect(Deep.hoover_band(Vector3.ZERO, Vector3.FORWARD, 0.8, 0.8).is_empty(), "no band in a cupboard-sized gap")
	# The kennel grows in order.
	var prev := 0
	for n in 40:
		var st := Deep.kennel_stage(n)
		_expect(st >= prev, "the kennel never shrinks")
		prev = st
	_expect(Deep.kennel_stage(0) == 0 and Deep.kennel_stage(1) == 1 and Deep.kennel_stage(100) == Deep.KENNEL_STEPS.size(), "kennel stages")
	for s in Deep.KENNEL_STEPS:
		_expect(Deep.KENNEL_NAMES.has(String(s[1])), "the %s has a name" % s[1])
	print("HIDE AND SEEK DEEP: %s (%d ms)" % ["PASS" if fails == 0 else "FAIL (%d)" % fails, Time.get_ticks_msec() - t0])
	quit(0 if fails == 0 else 1)


## The house's pick orbs: clear (deep.gd check_picks) and on floor a hider and the seeker reach.
func _house_picks(g: Dictionary) -> Array:
	var md := HouseGen.data(g)
	var w := Deep.check_picks(md)
	var hg := HouseGen.raster(g, HouseGen.HIDER[0], HouseGen.HIDER[1])
	var sg := HouseGen.raster(g, HouseGen.SEEKER[0], HouseGen.SEEKER[1])
	for i in Deep.pick_spots(md).size():
		var p: Vector3 = Deep.pick_spots(md)[i]
		if not HouseGen.near(hg, p, Deep.PICK_TOUCH * 0.6) or not HouseGen.near(sg, p, Deep.PICK_TOUCH * 0.6):
			w.append("pick orb %d over something (%.1f, %.1f)" % [i, p.x, p.z])
	return w


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: hide and seek deep: " + what)
