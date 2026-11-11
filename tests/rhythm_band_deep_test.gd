extends SceneTree
## RHYTHM BAND second pass validator (no game, no window): games/rhythm_band/deep.gd.
##   godot-test --headless --path . -s res://tests/rhythm_band_deep_test.gd      (SEEDS=40 for more)
## Proves, for every mode, season, gift, band size and song over many show seeds:
##   - the warned changes are fair (deep.gd problems(): none in song 1 or a song's first note bars, never two at once,
##     each told for the mode's seconds while the song still plays plain, speeds within bounds, at most one solo and
##     always for someone who is there, and a small kid (songgen.gd's kid model, on the warped clock, with the game's
##     timing windows) still hits enough guitar notes and drums), the same every time and unchanged over the network;
##   - GENTLE <= BRAVE <= HARD: the mode table (deep.gd ordered()) AND what the songs really get (changes a song,
##     fast-part speed, warning seconds, timing windows, the kid model's share);
##   - Doodle's gifts: three different unlocked ones, the newest among them, not the last again when there are others,
##     every picture drawn, short names, every gift opens within a few weeks of play, gift windows only ever widen;
##   - the seasons: each has drifting things, a picture and a line;
##   - the pick row: three orbs apart (a hand never in two at once), at a small drummer's arm's reach;
##   - the festival only grows, every piece has a picture and its spot is clear of the stage, the crowd, the TV cameras'
##     view of the band and the other pieces;
##   - every key colour stands out (core/contrast.gd, games/rhythm_band/palette.gd);
##   - fast: well under 100 ms a song (a Deck works one out between songs).
## Prints "SCRIPT ERROR: ..." for each failure and "RHYTHM DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/rhythm_band/deep.gd")
const SongGen := preload("res://games/rhythm_band/songgen.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Seeded := preload("res://core/seeded.gd")
const Stage := preload("res://games/rhythm_band/stage.gd")

var fails := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 10
	for w in Deep.ordered():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("rhythm_band"):
		_fail("contrast: " + str(w))
	var per := {}
	var worst_ms := 0.0
	var checked := 0
	var gifts := ["", "bigdrum", "shaker", "goldmic", "snail", "confetti"]
	for mode in PickOrbs.MODE_IDS:
		var sum := {"songs": 0, "changes": 0, "fast": 0.0, "nfast": 0, "kid": 0.0}
		for season in Deep.SEASONS:
			for s in seeds:
				var session := 7300 + s * 7919
				for pos in range(0, 6):
					var code := SongGen.code_at(session, pos, s % 3 == 0)
					for gi in gifts.size():
						var g: String = gifts[(gi + s + pos) % gifts.size()] if gi > 1 else gifts[gi]
						var band: Array = [0]
						for k in (s + pos + gi) % 7:
							band.append(k + 1)
						var spec := {"mode": mode, "season": season, "gift": g, "band": band}
						var t1 := Time.get_ticks_usec()
						var list := Deep.changes(code, pos, spec)
						var why := Deep.problems(code, pos, list, spec)
						worst_ms = maxf(worst_ms, (Time.get_ticks_usec() - t1) / 1000.0)
						checked += 1
						var tag := "%s %s show %d song %d gift '%s' band %d" % [mode, season, session, pos + 1, g, band.size()]
						for x in why:
							_fail("%s: %s" % [tag, x])
						if gi == 0:
							if str(Deep.changes(code, pos, spec)) != str(list):
								_fail("%s: changes differ for the same seed" % tag)
							if str(Deep.unpack(Deep.pack(list))) != str(list):
								_fail("%s: changes differ over the network" % tag)
							# Bots turn changes on from song 1, bar 1: still fair.
							var bot := spec.duplicate()
							bot["from"] = 0
							bot["first"] = 1
							for x in Deep.problems(code, pos, Deep.changes(code, pos, bot), bot):
								_fail("%s (bot spec): %s" % [tag, x])
							if pos >= Deep.FIRST_POS:
								sum.songs += 1
								sum.changes += list.size()
								for e in list:
									if String(e.kind) == "fast":
										sum.fast += float(e.rate)
										sum.nfast += 1
		per[mode] = sum
	# GENTLE <= BRAVE <= HARD in what the songs really get.
	var cps := {}
	for m in per:
		cps[m] = float(per[m].changes) / maxf(1.0, float(per[m].songs))
		print("RHYTHM DEEP %s: %.2f changes a song, fast parts at %.2f, warned %.1f s, windows x%.2f" % [m, cps[m],
			float(per[m].fast) / maxf(1.0, float(per[m].nfast)), float(Deep.mode_data(m).warn), float(Deep.mode_data(m).win)])
	if not (cps.gentle <= cps.brave and cps.brave <= cps.hard):
		_fail("changes a song not gentle <= brave <= hard: %s" % str(cps))
	if cps.gentle <= 0.1:
		_fail("gentle songs almost never change (%.2f)" % cps.gentle)
	for g in ["", "bigdrum", "shaker"]:
		for d in [true, false]:
			var a := Deep.win_share("gentle", g, d)
			var b := Deep.win_share("brave", g, d)
			var c := Deep.win_share("hard", g, d)
			if not (a >= b and b >= c):
				_fail("windows not gentle >= brave >= hard (gift '%s')" % g)
			if g != "" and Deep.win_share("brave", g, d) < Deep.win_share("brave", "", d):
				_fail("gift %s makes the windows smaller" % g)
	# Gifts.
	for gd in Deep.GIFTS:
		if not StoryCard.has_picture(String(gd.pic)):
			_fail("gift %s: no picture %s" % [gd.id, gd.pic])
		if String(gd.name).length() > 10:
			_fail("gift %s: name too long" % gd.id)
		if int(gd.unlock) > Deep.FESTIVAL.size():
			_fail("gift %s never opens" % gd.id)
	for pieces in Deep.FESTIVAL.size() + 1:
		for last in ["", "bigdrum", "snail", "confetti"]:
			for sd in 20:
				var ch := Deep.gift_choices(pieces, last, 900 + sd)
				var un := Deep.unlocked(pieces)
				var uniq := {}
				for id in ch:
					uniq[id] = true
					if not un.has(id):
						_fail("gift %s offered with %d pieces" % [id, pieces])
				if ch.size() != 3 or uniq.size() != 3:
					_fail("gift choices %s (pieces %d)" % [str(ch), pieces])
				if not ch.has(un[un.size() - 1]) and un[un.size() - 1] != last:
					_fail("newest gift missing from %s" % str(ch))
				if un.size() > 3 and ch.has(last):
					_fail("last gift %s offered again" % last)
				if str(ch) != str(Deep.gift_choices(pieces, last, 900 + sd)):
					_fail("gift choices differ for the same seed")
	if Deep.FESTIVAL.size() * Deep.FEST_EVERY > 40:
		_fail("the festival takes over 40 songs to finish")
	# Seasons.
	for s in Deep.SEASONS:
		var sd: Dictionary = Deep.SEASONS[s]
		if not StoryCard.has_picture(String(sd.pic)) or String(sd.line).length() > 20 or (sd.weights as Array).size() != 3:
			_fail("season %s" % s)
	if not Deep.SEASONS.has(Seeded.season(Seeded.today())):
		_fail("today's season %s has no stage" % Seeded.season(Seeded.today()))
	# Pick row: apart and at arm's reach.
	var row := Deep.row_local()
	for i in row.size():
		var p: Vector3 = row[i]
		if Vector2(p.x, p.z).length() > 0.9 or p.y < -0.45 or p.y > 0.05:
			_fail("orb %d out of a small drummer's reach (%s)" % [i, str(p)])
		for j in range(i + 1, row.size()):
			if p.distance_to(row[j]) < 2.0 * Deep.reach_r() + 0.05:
				_fail("orbs %d and %d too close: a hand in both" % [i, j])
	# Festival.
	var prev := -1
	for n in 60:
		var f := Deep.festival(n)
		if f < prev:
			_fail("festival shrinks at %d songs" % n)
		prev = f
	if Deep.FEST_SPOTS.size() < Deep.FESTIVAL.size():
		_fail("festival pieces without a spot")
	for i in Deep.FESTIVAL.size():
		var id: String = Deep.FESTIVAL[i]
		if not StoryCard.has_picture(String(Deep.FEST_PICS.get(id, ""))):
			_fail("festival %s: no picture" % id)
		var p: Vector3 = Deep.FEST_SPOTS[i]
		if absf(p.x) < 6.2:
			_fail("festival %s on the stage or crowd (x %.1f)" % [id, p.x])
		for j in range(i + 1, Deep.FESTIVAL.size()):
			if p.distance_to(Deep.FEST_SPOTS[j]) < 2.6:
				_fail("festival %s and %s overlap" % [id, Deep.FESTIVAL[j]])
		for k in 6:  # the TV cameras look at the band: a piece never stands on that line
			var a := Vector2(Stage.AVATAR_X[k] * 0.5, -6.6)  # (== stage.gd tv_camera)
			var b := Vector2(Stage.AVATAR_X[k] * 0.35, 0.5)
			var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), a, b)
			if q.distance_to(Vector2(p.x, p.z)) < 2.0:
				_fail("festival %s blocks TV camera %d" % [id, k + 1])
	var ms := Time.get_ticks_msec() - t0
	print("RHYTHM DEEP: %d songs checked in %d ms, worst %.1f ms a song" % [checked, ms, worst_ms])
	if worst_ms > 100.0:
		_fail("a song takes %.0f ms to check" % worst_ms)
	print("RHYTHM DEEP: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func _fail(msg: String) -> void:
	fails += 1
	if fails <= 40:
		print("SCRIPT ERROR: " + msg)
