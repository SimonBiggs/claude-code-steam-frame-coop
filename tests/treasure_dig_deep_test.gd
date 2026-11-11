extends SceneTree
## TREASURE DIG second pass validator (no game, no window): games/treasure_dig/deep.gd.
##   godot-test --headless --path . -s res://tests/treasure_dig_deep_test.gd      (SEEDS=40 for more)
## Proves, for every mode over every island kind, level, season and many seeds:
##   - every island is fair in every mode (islandgen.gd check(): spots on the sand, the relic reachable, the map
##     pieces in the pile, boots under the cap);
##   - its warned events are fair (deep.gd problems(): told >= 1.5 s early, spaced out, never on the chest or in the
##     sea, small enough to walk out of while told, tide coins on the sand) and the same on every machine;
##   - GENTLE <= BRAVE <= HARD: the mode table (deep.gd ordered()) AND what the islands really get (events a minute,
##     coconuts per drop, boots in the pile, how long a bonk sits you down; warnings longest on GENTLE);
##   - every key colour stands out on every sand (core/contrast.gd, games/treasure_dig/palette.gd);
##   - Peg's tools: three different unlocked ones, the newest unlock among them, not the last again when there are
##     others, every picture drawn, short lines; every tool unlocks within a few weeks of play;
##   - the seasons: every one dresses the island and has a picture; snowballs in winter, lava on the volcano;
##   - the pick orbs: on the sand, clear of the chest and each other, a lean from the giant wherever they wade;
##   - the museum only grows.
## Prints "SCRIPT ERROR: ..." for each failure and "TREASURE DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/treasure_dig/deep.gd")
const IslandGen := preload("res://games/treasure_dig/islandgen.gd")
const Story := preload("res://games/treasure_dig/story.gd")
const Picks := preload("res://games/treasure_dig/picks.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Seeded := preload("res://core/seeded.gd")
const TestTime := preload("res://tests/test_time.gd")

const S := 0.25  # main.gd S (beach scale)
const GIANT_R := 7.0 * S + 0.25  # main.gd: the giant wades from ISLAND * S + 0.15 out to + 2.0 (metres)

var fails := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 6
	for w in Deep.ordered():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("treasure_dig"):
		_fail("contrast: " + str(w))
	# Islands + events x modes.
	var per := {}
	var checked := 0
	var worst_ms := 0.0
	for mode in PickOrbs.MODE_IDS:
		var sum := {"events": 0.0, "mins": 0.0, "drops": 0, "drop_events": 0, "boots": 0.0, "decks": 0}
		for isl in Story.ISLANDS:
			for level in [0, 3, 9]:
				for season in Deep.SEASONS:
					for s in seeds:
						var seed_v: int = 9100 + s * 37 + level * 7
						var desc := Deep.island_spec({"seed": seed_v, "kind": String(isl.id), "level": level}, mode)
						var g := IslandGen.generate(seed_v, desc)
						for x in IslandGen.check(g):
							_fail("%s / %s L%d seed %d: island: %s" % [mode, isl.id, level, seed_v, x])
						var boots := 0
						for k in g.deck:
							boots += 1 if int(k) == Story.KIND_BOOT else 0
						sum.boots += float(boots) / (g.deck as Array).size()
						sum.decks += 1
						for time in [120.0, 60.0]:
							for gold in [0, Deep.PARROT_GOLD]:
								var spec := {"mode": mode, "time": time, "season": season, "kind": String(isl.id), "rocks": g.rocks, "extra_gold": gold}
								var e0 := Time.get_ticks_usec()
								var ev := Deep.events(seed_v, spec)
								worst_ms = TestTime.worst(worst_ms, (Time.get_ticks_usec() - e0) / 1000.0, func() -> Variant: return Deep.events(seed_v, spec))
								for x in Deep.problems(ev, spec):
									_fail("%s / %s %s %ds seed %d: events: %s" % [mode, isl.id, season, int(time), seed_v, x])
								if var_to_str(ev) != var_to_str(Deep.events(seed_v, spec.duplicate(true))):
									_fail("%s / %s: events differ between two makes" % [mode, isl.id])
								if gold == 0:
									sum.events += ev.size()
									sum.mins += time / 60.0
									for e in ev:
										if String(e[1]) == "drop":
											sum.drops += (e[2] as Array).size()
											sum.drop_events += 1
								checked += 1
		# Today's island.
		for d in seeds:
			var date := Time.get_date_string_from_unix_time(1790000000 + d * 86400 * 13)
			var dl := Story.daily(date)
			var g2 := IslandGen.generate(int(dl[0]), Deep.island_spec({"seed": int(dl[0]), "kind": String(dl[1]), "level": 3}, mode))
			for x in IslandGen.check(g2):
				_fail("%s daily %s: %s" % [mode, date, x])
			var sp2 := {"mode": mode, "time": 120.0, "season": Seeded.season(date), "kind": String(dl[1]), "rocks": g2.rocks}
			for x in Deep.problems(Deep.events(int(dl[0]), sp2), sp2):
				_fail("%s daily %s: events: %s" % [mode, date, x])
			checked += 1
		per[mode] = {"events_min": snappedf(sum.events / maxf(1.0, sum.mins), 0.01),
			"drops": snappedf(float(sum.drops) / maxf(1.0, sum.drop_events), 0.01),
			"boots": snappedf(sum.boots / maxf(1.0, sum.decks), 0.001), "stun": float(Deep.MODES[mode].stun),
			"warn": float(Deep.MODES[mode].warn)}
	print("TREASURE DEEP: per mode %s" % str(per))
	var gm: Dictionary = per.gentle
	var bm: Dictionary = per.brave
	var hm: Dictionary = per.hard
	for k in ["events_min", "drops", "boots", "stun"]:
		_expect(float(gm[k]) <= float(bm[k]) and float(bm[k]) <= float(hm[k]), "%s gentle %s <= brave %s <= hard %s" % [k, str(gm[k]), str(bm[k]), str(hm[k])])
	_expect(float(gm.warn) >= float(bm.warn) and float(bm.warn) >= float(hm.warn), "warnings longest on gentle")
	_expect(float(gm.events_min) < float(hm.events_min) * 0.7, "hard is clearly busier than gentle (%s vs %s)" % [str(hm.events_min), str(gm.events_min)])
	_expect(float(gm.boots) < float(hm.boots), "hard buries more boots (%s vs %s)" % [str(hm.boots), str(gm.boots)])
	_expect(worst_ms < 20.0, "events made fast (worst %.1f ms)" % worst_ms)
	# Unfair events are caught.
	var spec0 := {"mode": "hard", "time": 120.0}
	_expect(not Deep.problems([[20.0, "drop", [Vector3.ZERO]]], spec0).is_empty(), "a coconut on the chest is caught")
	_expect(not Deep.problems([[20.0, "drop", [Vector3(4, 0, 0), Vector3(4.5, 0, 0)]]], spec0).is_empty(), "overlapping drops are caught")
	_expect(not Deep.problems([[20.0, "gold", Vector3(6.5, 0, 0)]], spec0).is_empty(), "gold in the sea is caught")
	_expect(not Deep.problems([[20.0, "tide", 0.0], [21.0, "tide", 1.0]], spec0).is_empty(), "two events at once are caught")
	_expect(not Deep.problems([[0.5, "tide", 0.0]], spec0).is_empty(), "an event told before the round is caught")
	# Gifts (Peg's tools).
	for cases in [0, 1, 2, 4, 5, 12]:
		var un := Deep.unlocked(cases)
		_expect(un.size() >= 3, "three tools from the start (%d)" % un.size())
		for last in ["", "spade", "detector", "map", "parrot", "lucky"]:
			if last != "" and not un.has(last):
				continue
			for s in 20:
				var ch := Deep.gift_choices(cases, last, s)
				_expect(ch.size() == 3, "three tools (cases %d last %s: %s)" % [cases, last, str(ch)])
				var seen := {}
				for id in ch:
					_expect(un.has(id), "tool %s unlocked at %d cases" % [id, cases])
					_expect(not seen.has(id), "tools differ (%s)" % str(ch))
					seen[id] = true
				_expect(ch.has(un[un.size() - 1]) or un[un.size() - 1] == last, "the newest unlock offered (%d cases: %s)" % [cases, str(ch)])
				if un.size() > 3:
					_expect(not ch.has(last), "not the last tool again when there are others (%s, last %s)" % [str(ch), last])
	var last_unlock := 0
	for gd in Deep.GIFTS:
		_expect(StoryCard.has_picture(String(gd.pic)), "tool %s has a picture %s" % [gd.id, gd.pic])
		_expect(String(gd.line).length() <= 26 and String(gd.name).length() <= 12, "tool %s words are short" % gd.id)
		last_unlock = maxi(last_unlock, int(gd.unlock))
	# ~25 treasures an island, ~3 islands a day: every tool within about two weeks.
	_expect(last_unlock * Deep.CASE_EVERY <= 25 * 3 * 14, "every tool unlocks within ~2 weeks (%d cases)" % last_unlock)
	# Seasons.
	for season in ["winter", "spring", "summer", "autumn"]:
		_expect(Deep.SEASONS.has(season), "season %s exists" % season)
		_expect(StoryCard.has_picture(String(Deep.season_data(season).pic)), "season %s has a picture" % season)
		_expect((Deep.season_data(season).weights as Array).size() == Deep.KINDS.size(), "season %s weighs every event" % season)
	_expect(Seeded.season("2026-12-25") == "winter" and Seeded.season("2026-07-01") == "summer", "Seeded.season")
	_expect(Deep.drop_kind("volcano", "summer") == "lava" and Deep.drop_kind("sunny", "winter") == "snowball" and Deep.drop_kind("jungle", "autumn") == "coconut", "what falls")
	for pic in ["tidewave", "goldgem", "museum", "pirate"]:
		_expect(StoryCard.has_picture(pic), "picture %s" % pic)
	# Pick orbs: on the sand, clear of the chest and each other, reachable by the giant wherever they wade.
	var pk := Picks.new()
	for k in 16:
		var a := k * TAU / 16.0
		var giant := Vector3(cos(a), 0.0, sin(a)) * (GIANT_R / S)
		var row := pk.row_at(giant)
		for i in 3:
			var p := Picks.spot_of(row, i, 3)
			var flat := Vector2(p.x, p.z)
			_expect(flat.length() < IslandGen.R - 0.1 and flat.length() > IslandGen.CHEST_CLEAR, "pick orb %d on the sand (%.2f)" % [i, flat.length()])
			var reach := Vector2(giant.x, giant.z).distance_to(flat) * S
			_expect(reach < 1.15, "pick orb %d a lean from the giant (%.2f m)" % [i, reach])
		var p0 := Picks.spot_of(row, 0, 3)
		var p1 := Picks.spot_of(row, 1, 3)
		_expect(p0.distance_to(p1) > Picks.TV_R * 2.0, "a digger touches one orb at a time")
	# With diggers: behind the chest where the TV cameras look (from +z), the first orb on their left.
	var tv_row := pk.row_at(Vector3(0, 0, -9), Vector3(0, 0, 9))
	for i in 3:
		var p := Picks.spot_of(tv_row, i, 3)
		_expect(p.z < -IslandGen.CHEST_CLEAR and Vector2(p.x, p.z).length() < IslandGen.R - 0.1, "TV pick orb %d on the far sand (%s)" % [i, str(p)])
	_expect(Picks.spot_of(tv_row, 0, 3).x < Picks.spot_of(tv_row, 2, 3).x, "the first TV pick orb on the left")
	pk.free()
	_expect(Picks.Y * S + 0.8 > 0.9 and Picks.Y * S + 0.8 < 1.5, "pick orbs at a giant's hand height")
	# The museum only grows.
	var m := {}
	var prev := 0
	for n in 400:
		m[Deep.MUSEUM_KINDS[n % Deep.MUSEUM_KINDS.size()]] = int(m.get(Deep.MUSEUM_KINDS[n % Deep.MUSEUM_KINDS.size()], 0)) + 1
		var c := Deep.cases(m)
		_expect(c >= prev, "the museum never shrinks")
		prev = c
	_expect(prev >= 400 / Deep.CASE_EVERY - 1, "the museum grew (%d cases)" % prev)
	print("TREASURE DEEP: %d islands + events checked in %d ms" % [checked, Time.get_ticks_msec() - t0])
	print("TREASURE DEEP: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	if fails < 40:
		print("SCRIPT ERROR: TREASURE DEEP: " + what)
