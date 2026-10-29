extends SceneTree
## RHYTHM BAND generator: proves every seeded song can be played by small kids (no game, no window).
##   godot-test --headless --path . -s res://tests/rhythm_band_gen_test.gd      (SEEDS=500 for more)
## For every show position (warm-up, song 2, 3, 4+ up to the top level) and TODAY'S SONG:
## games/rhythm_band/songgen.gd check() (tempo in range, kids' words in the name, notes inside the song,
## no gold notes, the warm-up has only the outer lanes, EASY guitar notes well apart and not too busy, a
## small kid model hits nearly all the EASY guitar and a small VR drummer model nearly all the drums at
## its level, songs never too long), the same seed gives the same song, the show gets gently harder,
## every style / name word shows up, TODAY'S SONG is the same all day and new each day, the song code
## round-trips, the fan club stands have room beside the stage, Doodle's pictures exist, the constants
## match the game's, and generation stays fast. Prints "SCRIPT ERROR: ..." per failure.

const G := preload("res://games/rhythm_band/songgen.gd")
const Song := preload("res://games/rhythm_band/song.gd")
const Main := preload("res://games/rhythm_band/main.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 100
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var seen := {}
	var avg_bpm := {}
	var avg_drums := {}
	var avg_kid := {}
	var avg_kd := {}
	var positions: Array[int] = [0, 1, 2, 3, 5, 7, 9]
	for pos in positions:
		var res := Seeded.validate(func(s: int) -> int: return G.code_at(s, pos, false),
			func(code: int) -> Array: return G.check(code, pos), seeds, 11 + pos, [0, 999999], "SONG %d" % (pos + 1))
		gens += int(res.checked)
		fails += (res.failures as Array).size()
		for k in 40:
			var code := G.code_at(k * 31 + 5, pos, false)
			var d := G.from_code(code)
			seen["style:" + str(d.style)] = true
			var parts := str(d.name).split(" ")
			seen["adj:" + parts[0]] = true
			seen["noun:" + parts[1]] = true
			avg_bpm[pos] = float(avg_bpm.get(pos, 0.0)) + float(d.bpm) / 40.0
			var s := G.build(code, pos)
			var n := 0
			for l in s.d_lvl:
				if int(l) <= G.drum_level_for(pos):
					n += 1
			avg_drums[pos] = float(avg_drums.get(pos, 0.0)) + n / (s.bars * 40.0)
			var et: Array[float] = []
			var el: Array[int] = []
			for i in s.g_t.size():
				if int(s.g_lvl[i]) == 0:
					et.append(s.g_t[i])
					el.append(int(s.g_lane[i]))
			avg_kid[pos] = float(avg_kid.get(pos, 0.0)) + G.kid_guitar(et, el, code) / 40.0
			var dt: Array[float] = []
			var dp: Array[int] = []
			for i in s.d_t.size():
				if int(s.d_lvl[i]) <= G.drum_level_for(pos):
					dt.append(s.d_t[i])
					dp.append(int(s.d_pad[i]))
			avg_kd[pos] = float(avg_kd.get(pos, 0.0)) + G.kid_drums(dt, dp, code) / 40.0
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens * 2.0)
	print("song gen: %.3f ms per song incl. check (%d songs)" % [per_ms, gens * 2])
	_expect(per_ms < 5.0, "a song generates + checks in under 5 ms here (%.2f ms; Decks are slower, aim < 100)" % per_ms)
	print("average BPM per show position: %s" % str(avg_bpm))
	print("drum notes per bar (at the drummer's level) per position: %s" % str(avg_drums))
	print("kid guitar hit share per position: %s" % str(avg_kid))
	print("kid VR drum hit share per position: %s" % str(avg_kd))
	for i in range(1, positions.size()):
		_expect(float(avg_bpm[positions[i]]) >= float(avg_bpm[positions[i - 1]]) - 0.5, "songs never get slower going on (%d)" % positions[i])
		_expect(G.level_for(positions[i]) >= G.level_for(positions[i - 1]), "levels never drop in a show")
	_expect(float(avg_bpm[positions[-1]]) > float(avg_bpm[0]) + 20.0, "late songs are clearly faster than the warm-up")
	_expect(float(avg_drums[2]) > float(avg_drums[0]), "drums get busier once the drummer is on NORMAL")
	_expect(G.level_for(0) == 1 and G.level_for(40) == G.MAX_LEVEL, "levels go from 1 to the top")
	for st in G.STYLES:
		_expect(seen.has("style:" + st), "style %s shows up" % st)
		_expect(StoryCard.has_picture(str(G.STYLE_PICS[st])), "style %s has a picture" % st)
	var words := 0
	for w in G.ADJ:
		words += 1 if seen.has("adj:" + w) else 0
	_expect(words >= G.ADJ.size() / 2, "song names use many words (%d)" % words)
	# The code packs seed, level and daily.
	for s in [0, 1, 4242, 999999]:
		for lv in range(1, G.MAX_LEVEL + 1):
			for dy in [false, true]:
				var c := G.code_of(s, lv, dy)
				_expect(G.seed_of(c) == s and G.level_of(c) == lv and G.daily_of(c) == dy, "song code round-trips (%d, %d, %s)" % [s, lv, dy])
	# The validator really catches songs a small kid can't play.
	var busy := G.build(G.code_at(7, 2, false), 2)
	_expect(G.kid_guitar([4.0, 4.3, 4.6, 4.9, 5.2], [0, 2, 0, 2, 0], 1) < G.KID_GUITAR_RATE, "a too-busy EASY part is caught")
	_expect(G.kid_drums([4.0, 4.1, 4.2, 4.3, 4.4, 4.5], [0, 1, 2, 3, 0, 1], 1) < G.KID_DRUM_RATE, "a drum roll too fast for small hands is caught")
	_expect(G.kid_guitar([4.0, 5.0, 6.0], [0, 2, 0], 1) == 1.0, "well spaced notes are easy")
	_expect(busy.g_t.size() > 0, "song 3 has notes")
	_expect(not G.check(G.code_of(5, 6, false), 0).is_empty(), "a top-level song as the warm-up is caught (too fast / too busy)")
	# TODAY'S SONG: valid, the same all day, different between days, at the second song.
	for date in ["2026-10-29", "2026-12-25", "2027-01-01"]:
		var dc := G.code_at(77, G.DAILY_POS, true, date)
		_expect(G.daily_of(dc) and G.level_of(dc) == G.DAILY_LEVEL, "TODAY'S SONG is marked daily at its level")
		for why in G.check(dc, G.DAILY_POS):
			_expect(false, "TODAY'S SONG %s: %s" % [date, why])
		_expect(dc == G.code_at(123456, G.DAILY_POS, true, date), "TODAY'S SONG is the same for every session all day")
		_expect(var_to_str(G.from_code(dc)) == var_to_str(G.from_code(G.code_at(9, G.DAILY_POS, true, date))), "TODAY'S SONG is the same song all day")
	_expect(G.daily_seed("2026-10-29") != G.daily_seed("2026-10-30"), "a new TODAY'S SONG each day")
	_expect(not G.daily_of(G.code_at(77, 0, true)) and not G.daily_of(G.code_at(77, 2, true)), "only one TODAY'S SONG per show")
	_expect(not G.daily_of(G.code_at(77, G.DAILY_POS, false)), "no TODAY'S SONG once it's done")
	# The fan club: room for every fan, beside the stage (never on it or in the crowd), facing in.
	var spots: Array = []
	for i in G.FAN_SLOTS:
		var at := G.fan_slot(i)
		_expect(absf(at.x) > 4.95, "fan spot %d stands beside the stage (%s)" % [i, str(at)])
		_expect(at.z > -2.7 and at.z < 0.5, "fan spot %d is level with the stage, not in the crowd (%s)" % [i, str(at)])
		for o in spots:
			_expect((o as Vector3).distance_to(at) > 0.55, "fan spot %d has room" % i)
		spots.append(at)
	_expect(G.fan_slot(G.FAN_SLOTS) == Vector3.INF, "no spot past the end")
	_expect(G.FAN_KEEP >= G.FAN_SLOTS, "the save keeps a full fan club")
	_expect(G.fan_stage(3, 3) == 0 and G.fan_stage(3, 4) == 1 and G.fan_stage(3, 9) == G.FAN_STAGES - 1, "fans grow a stage a day")
	var kinds := {}
	for n in 60:
		kinds[G.fan_kind(G.code_at(n, 1, false), n)] = true
	_expect(kinds.size() == G.FAN_KINDS.size(), "every kind of fan comes")
	# The game uses the same numbers.
	_expect(G.SIMPLE_BARS == Main.SIMPLE_BARS, "song lengths match main.gd")
	_expect(is_equal_approx(G.KID_WINDOW, Main.WINDOWS[0].y), "the EASY window matches main.gd")
	var pics: Array = ["frog", "goldrecord", "fanclub"]
	pics.append_array(G.FAN_KINDS)
	pics.append_array(G.STYLE_PICS.values())
	for pic in pics:
		_expect(StoryCard.has_picture(pic), "story picture %s exists" % pic)
	for why in StoryCard.check():
		_expect(false, why)
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: %s" % what)
