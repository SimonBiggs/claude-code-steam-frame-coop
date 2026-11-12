extends SceneTree
## PARTY BOARD second pass validator (no game, no window): games/party_board/deep.gd + partygen.gd modes.
##   godot-test --headless --path . -s res://tests/party_board_deep_test.gd      (SEEDS=200 for more; GEN_QUICK=1 samples)
## Proves:
##   - GENTLE <= BRAVE <= HARD: the mode table (deep.gd ordered()) AND what the parties really get (red spaces on the
##     same seed, surprise rounds, how far things slide you back); every moded party passes partygen.gd check();
##   - TODAY'S PARTY over 400+ dates in every mode: fair (check()), every round's surprises fair, and a whole party
##     played out (simulated rolls, Mango's gifts to whoever is behind, the surprises going off) collects STARS;
##   - the surprises are fair on many boards and places (deep.gd problems(): only ordinary spaces on the way, never
##     START / the STAR / a chest / a present or special space / a junction / where somebody stands, the mode's number
##     and size, never in round 1, never too much of the board), the same every time;
##   - Mango's gifts never break the proof (deep.gd gift_problems(): a die never over 6, a turn never further than two
##     dice, a STAR worth at most two, a gift only for whoever has the fewest STARS), and check() still holds for a
##     party whatever gift anyone holds; three different unlocked gifts offered, the newest among them;
##   - every picture is drawable (StoryCard.has_picture), every word short and UPPERCASE (SIMPLE_MODE);
##   - the seasons: every date has one; the season props and Mango's party hall stand clear of every space on every
##     layout and of the festival pieces; the hall grows in order;
##   - the pick rows: VR orbs an arm's reach in front of the giant, small, apart, GENTLE on the left, above the board
##     standing and seated; board orbs over the island, apart; TV players' left-to-right order; a deliberate touch;
##   - every key colour stands out (palette.gd); fast: a round's surprises are found and checked well under 100 ms.
## Prints "SCRIPT ERROR: ..." for each failure and "PARTY DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/party_board/deep.gd")
const PartyGen := preload("res://games/party_board/partygen.gd")
const BD := preload("res://games/party_board/board_data.gd")
const Boards := preload("res://games/party_board/boards.gd")
const Festival := preload("res://games/party_board/festival.gd")
const Season := preload("res://games/party_board/season.gd")
const Hall := preload("res://games/party_board/hall.gd")
const TurnFlow := preload("res://games/party_board/turn_flow.gd")
const Main := preload("res://games/party_board/main.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Seeded := preload("res://core/seeded.gd")
const TestTime := preload("res://tests/test_time.gd")
const VrViewCheck := preload("res://core/vr_view_check.gd")

const MODES: Array[String] = ["gentle", "brave", "hard"]

var fails := 0
var worst_ms := 0.0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	for w in Deep.ordered(PartyGen.RED_MIN, PartyGen.RED_MAX):
		_fail("modes: " + str(w))
	for w in Contrast.check_game("party_board"):
		_fail("contrast: " + str(w))
	for why in StoryCard.check():
		_fail(why)
	_check_modes()
	_check_surprises()
	_check_daily()
	_check_gifts()
	_check_words_pictures()
	_check_seasons_hall()
	_check_rows()
	print("surprises: worst %.1f ms to find and check a round's" % worst_ms)
	_expect(worst_ms < 100.0, "a round's surprises are found and checked under 100 ms (%.1f)" % worst_ms)
	print("PARTY DEEP: %s (%d ms)" % ["PASS" if fails == 0 else "FAIL (%d)" % fails, Time.get_ticks_msec() - t0])
	quit(1 if fails > 0 else 0)


func _party(data, seed_value: int, mode: String, bid: String, level: int = 4, rounds: int = 4) -> Dictionary:
	var p := PartyGen.generate(data, seed_value, {"seed": seed_value, "level": level, "rounds": rounds, "board": bid, "mode": mode})
	data.set_types(p.types)
	return p


## Every mode's parties pass check(); on the same seed GENTLE has no more reds than BRAVE, BRAVE than HARD.
func _check_modes() -> void:
	var data := BD.new()
	data.make_simple()
	var n := Seeded.test_count(40, 10)
	for i in n:
		for bid in Boards.ids():
			for level in [0, 3, 9]:
				var reds := []
				for m in MODES:
					var p := _party(data, 5000 + i, m, bid, level)
					for w in PartyGen.check(data, p):
						_fail("%s %s seed %d level %d: %s" % [m, bid, 5000 + i, level, w])
					_expect(String(p.mode) == m, "the party carries its mode (%s)" % m)
					reds.append(int(p.reds))
				_expect(reds[0] <= reds[1] and reds[1] <= reds[2], "%s seed %d level %d reds %s not gentle <= brave <= hard" % [bid, 5000 + i, level, str(reds)])
	var p0 := PartyGen.generate(data, 77, {"level": 2, "rounds": 4, "board": "island"})
	_expect(String(p0.mode) == "brave", "an old desc without a mode reads as BRAVE")
	for r in range(2, 9):
		_expect(Deep.surprise_rounds(r, "gentle").size() <= Deep.surprise_rounds(r, "hard").size(), "surprise rounds rise with the mode")
		_expect(not Deep.surprise_rounds(r, "hard").has(1), "never a surprise in round 1")
	_expect(Deep.mode_data("gentle").back < TurnFlow.SIMPLE_BACK or Deep.mode_data("gentle").back == 1, "GENTLE slides back gently")
	_expect(int(Deep.mode_data("brave").back) == TurnFlow.SIMPLE_BACK, "BRAVE slides back like the old game")
	_expect(Deep.mode_of("mega") == "hard" and Deep.mode_of("nonsense") == "brave", "old mode ids map through PickOrbs.ALIASES")


## Somebody stands on a few spaces, the STAR on its route: the round's surprises are fair and the same every time.
func _round_zones(data, p: Dictionary, mode: String, round_n: int, r: RandomNumberGenerator) -> Array:
	var types: Array = data.types()
	var stands: Array = []
	for k in r.randi_range(1, 7):
		stands.append(r.randi_range(0, data.count() - 1))
	var star := int((p.route as Array)[r.randi_range(0, 5)])
	var chest := r.randi_range(0, data.count() - 1) if String(p.board) == "pirate" and r.randf() < 0.5 else -1
	var t := Time.get_ticks_usec()
	var zs := Deep.zones(data, types, int(p.seed), round_n, int(p.rounds), mode, star, chest, stands)
	var why := Deep.problems(zs, data, types, mode, star, chest, stands)
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	worst_ms = TestTime.worst(worst_ms, ms, func() -> Variant:
		return Deep.problems(Deep.zones(data, types, int(p.seed), round_n, int(p.rounds), mode, star, chest, stands), data, types, mode, star, chest, stands))
	for w in why:
		_fail("%s %s seed %d round %d: %s" % [mode, p.board, int(p.seed), round_n, w])
	var again := Deep.zones(data, types, int(p.seed), round_n, int(p.rounds), mode, star, chest, stands)
	_expect(str(again) == str(zs), "the same surprises every time (seed %d round %d)" % [int(p.seed), round_n])
	if round_n == 1:
		_expect(zs.is_empty(), "no surprise in round 1")
	return zs


func _check_surprises() -> void:
	var data := BD.new()
	data.make_simple()
	var r := Seeded.rng(4242, "places")
	var told := {}
	var n := Seeded.test_count(60, 12)
	for i in n:
		for bid in Boards.ids():
			for m in MODES:
				var p := _party(data, 9000 + i, m, bid, i % 10, 4)
				for rn in range(1, 5):
					var zs := _round_zones(data, p, m, rn, r)
					told[m] = int(told.get(m, 0)) + zs.size()
					for z in zs:
						told[String(z.kind)] = true
	print("surprises told: %s" % str(told))
	_expect(int(told.get("gentle", 0)) < int(told.get("brave", 0)) and int(told.get("brave", 0)) < int(told.get("hard", 0)), "more surprises in harder modes %s" % str(told))
	for k in Deep.KINDS:
		_expect(told.has(k), "the %s surprise comes" % k)


## A whole party played out with seeded rolls: everyone takes turns, Mango's gift goes to whoever is behind, the
## surprises go off; returns the STARS collected on the board (no minigames).
func _simulate(data, p: Dictionary, mode: String, players: int, seed_value: int) -> Dictionary:
	var r := Seeded.rng(seed_value, "sim")
	var md := Deep.mode_data(mode)
	var types: Array = data.types()
	var dist := PartyGen.dists(data)
	var at: Array = []
	var stars: Array = []
	var gift: Array = []
	for k in players:
		at.append(0)
		stars.append(0)
		gift.append("")
	var route_i := 0
	var star := int(p.route[0])
	var got := 0
	var hz_hits := 0
	var gifts := 0
	for rn in range(1, int(p.rounds) + 1):
		if rn >= 2:  # Mango's gift
			var recs: Array = []
			for k in players:
				recs.append({"pid": k, "stars": stars[k], "cpu": k > 0, "dist": dist[at[k]][star]})
			var who := Deep.gift_to(recs)
			var ch := Deep.gift_choices(r.randi_range(0, 25), r.randi())
			gift[who] = ch[r.randi_range(0, ch.size() - 1)]
			gifts += 1
		var zs := Deep.zones(data, types, int(p.seed), rn, int(p.rounds), mode, star, -1, at)
		for w in Deep.problems(zs, data, types, mode, star, -1, at):
			_fail("sim %s seed %d round %d: %s" % [mode, int(p.seed), rn, w])
		for k in players:
			var roll := Deep.die(r.randi_range(1, 6), gift[k])
			_expect(roll <= Deep.DIE_MAX, "a die never shows more than 6")
			var hops := roll
			if gift[k] in ["lucky", "shortcut"]:
				hops = Deep.hops(roll, gift[k])
				gift[k] = ""
			_expect(hops <= Deep.MAX_TURN_HOPS, "a turn never hops further than two dice (%d)" % hops)
			for h in hops:
				var nx: Array = data.next_of(at[k])
				var to := int(nx[0])
				if nx.size() > 1 and dist[int(nx[1])][star] < dist[to][star]:
					to = int(nx[1])
				at[k] = to
				if to == star:
					var worth := Deep.star_value(gift[k])
					if worth > 1:
						gift[k] = ""
					stars[k] += worth
					got += worth
					route_i += 1
					star = int(p.route[route_i % (p.route as Array).size()])
			if String(types[at[k]]) == "red":
				if gift[k] == "shield":
					gift[k] = ""
				else:
					for b in int(md.back):
						at[k] = int(data.prev_of(at[k])[0])
		for k in players:  # the round's surprises go off
			if Deep.hit(zs, at[k]):
				hz_hits += 1
				if gift[k] == "shield":
					gift[k] = ""
				else:
					for b in int(md.hz_back):
						at[k] = int(data.prev_of(at[k])[0])
	return {"stars": got, "hz_hits": hz_hits, "gifts": gifts, "per": stars}


## TODAY'S PARTY in every mode over 400+ dates: fair, its surprises fair, and a lone player with three CPUs (the
## family's SIMPLE party) collects STARS on the board.
func _check_daily() -> void:
	var data := BD.new()
	data.make_simple()
	var t := Time.get_ticks_msec()
	var rd := Seeded.validate_days(func(date: String) -> Array:
			var sv := Seeded.daily_seed("party_board", date)
			var bid: String = Boards.ids()[Seeded.rng(sv, "daily_board").randi() % Boards.BOARDS.size()]
			var out: Array = []
			for m in MODES:
				out.append([m, PartyGen.generate(data, sv, {"seed": sv, "level": 4, "rounds": TurnFlow.SIMPLE_ROUNDS, "daily": true, "board": bid, "mode": m})])
			return out,
		func(ps: Array) -> Array:
			var why: Array = []
			for mp in ps:
				var m: String = mp[0]
				var p: Dictionary = mp[1]
				var d2 := BD.new()
				d2.build_layout(p.layout)
				d2.make_simple()
				d2.set_types(p.types)
				for w in PartyGen.check(d2, p):
					why.append("%s %s: %s" % [m, p.board, w])
				var sim := _simulate(d2, p, m, 4, int(p.seed))
				if int(sim.stars) < 1:
					why.append("%s %s: nobody collected a STAR on the board in a simulated party %s" % [m, p.board, str(sim)])
			return why, 400, "TODAY'S PARTY (modes)", ["2026-11-12", "2026-12-25", "2027-02-29"])
	fails += (rd.failures as Array).size()
	print("TODAY'S PARTY in every mode: %d days (%d ms)" % [int(rd.checked), Time.get_ticks_msec() - t])


func _check_gifts() -> void:
	for s in Seeded.test_count(40, 8):
		for w in Deep.gift_problems(100 + s):
			_fail("gifts: " + w)
	_expect(Deep.gift_choices(0, 1).size() == 3, "three gifts on a fresh save")
	_expect(Deep.gift_choices(30, 1).has(Deep.unlocked(30)[-1]), "the newest gift is offered")
	var seen := {}
	for s in 60:
		for id in Deep.gift_choices(30, s):
			seen[id] = true
	_expect(seen.size() == Deep.GIFTS.size(), "every gift comes %s" % str(seen.keys()))
	# Gifts never touch the board: a party passes check() whatever anyone holds (they only change rolls, pushes and
	# what one STAR is worth, never the types, the route or anyone else).
	var data := BD.new()
	data.make_simple()
	for i in Seeded.test_count(20, 5):
		var p := _party(data, 700 + i, "hard", Boards.ids()[i % Boards.BOARDS.size()])
		var before := str(p.types) + str(p.route)
		for g in Deep.GIFTS:
			var sim := _simulate(data, p, "hard", 4, 31 * i + 1)
			_expect(int(sim.gifts) == int(p.rounds) - 1, "a gift every round from the second")
		_expect(str(p.types) + str(p.route) == before and PartyGen.check(data, p).is_empty(), "gifts leave the party fair")
	_expect(Deep.SHORTCUT_HOPS <= PartyGen.FIRST_STAR.x, "a SHORTCUT is a few hops, not a jump to the STAR")


func _short(w: String, what: String) -> void:
	_expect(w == w.to_upper() and w.split(" ").size() <= 2 and w.length() <= 12, "%s '%s' is one or two short UPPERCASE words" % [what, w])


func _check_words_pictures() -> void:
	for g in Deep.GIFTS:
		_short(String(g.name), "gift")
		_expect(StoryCard.has_picture(String(g.pic)), "gift picture %s is drawable" % g.pic)
	for k in Deep.KINDS:
		_short(String(Deep.KIND_NAMES[k]), "surprise")
		_expect(StoryCard.has_picture(String(Deep.KIND_PICS[k])), "surprise picture %s is drawable" % Deep.KIND_PICS[k])
	for s in Deep.SEASONS:
		_short(String(Deep.SEASONS[s].name), "season")
		_expect(StoryCard.has_picture(String(Deep.SEASONS[s].pic)), "season picture %s is drawable" % Deep.SEASONS[s].pic)
	for m in MODES:
		_short(PickOrbs.mode_name(m) + "!", "mode")
	for p in ["toucan", "partyhall", "boulder"]:
		_expect(StoryCard.has_picture(p), "picture %s is drawable" % p)
	_expect(Deep.ROCK_COLOR.h != Deep.WAVE_COLOR.h, "the two surprises have their own colours")


func _check_seasons_hall() -> void:
	for d in Seeded.dates(400):
		_expect(Deep.SEASONS.has(Seeded.season(String(d))), "%s has a season" % d)
	var data := BD.new()
	data.make_simple()
	var props: Array = Season.spots()
	var pieces: Array = [Festival.wall_spot()]
	for id in Festival.SPOTS:
		pieces.append(Festival.spot(String(id)))
	for q in props:
		_expect(BD.height((q as Vector3).x, (q as Vector3).z) > BD.WATER_Y, "a season prop stands on the beach %s" % str(q))
		for pc in pieces:
			_expect(Vector2(q.x - pc.x, q.z - pc.z).length() > 2.2, "a season prop is clear of a festival piece %s" % str(pc))
	# The hall's footprint (wall-local posts and presents) in board units.
	var w := Festival.wall_spot()
	var inward := Vector3(-w.x, 0, -w.z).normalized()
	var basis := Basis(Vector3.UP, atan2(inward.x, inward.z))
	var feet: Array = []
	for sx in [-Hall.POST_X, Hall.POST_X, -Hall.POST_X - 0.75, Hall.POST_X + 0.75]:
		for z in Hall.POST_Z:
			feet.append(w + basis * Vector3(sx, 0, z))
	for i in Seeded.test_count(200, 40):
		var lay := PartyGen.layout(20000 + i)
		data.build_layout(lay)
		for s in data.count():
			var sp: Vector3 = data.pos(s)
			for q in props:
				_expect(Vector2(sp.x - q.x, sp.z - q.z).length() > 1.6, "layout %d: space %d is clear of a season prop" % [20000 + i, s])
			for f in feet:
				_expect(Vector2(sp.x - f.x, sp.z - f.z).length() > 1.3, "layout %d: space %d is clear of the party hall" % [20000 + i, s])
	var prev := -1
	for n in 30:
		var st := Deep.hall_steps(n)
		_expect(st.size() >= prev, "the hall only grows")
		prev = st.size()
	_expect(Deep.hall_steps(0).is_empty() and Deep.hall_steps(30).size() == Deep.HALL_STEPS.size(), "the hall starts empty and gets everything")
	for n in [1, 5, 12, 30]:
		var m := Hall.build(n)
		_expect(m != null and m.get_surface_count() > 0, "the hall builds at %d parties" % n)
	for g in Deep.GIFTS:
		_expect(int(g.unlock) <= int(Deep.HALL_STEPS[2][0]), "gift %s opens within the first hall steps" % g.id)


func _check_rows() -> void:
	for eye in [1.6, 1.15]:  # standing and seated (VrRig fake eyes)
		var head := Transform3D(Basis(), Vector3(0.0, eye, Main.VR_FEET.z))
		var vr := Deep.vr_spots(head)
		var orb_m := PickOrbs.BALL_R * Deep.VR_SCALE
		for i in vr.size():
			var v: Vector3 = vr[i]
			var d: float = v.distance_to(head.origin)
			_expect(d > 0.3 and d < 0.62, "VR orb %d is an arm's reach away (%.2f m)" % [i, d])
			_expect(v.z < head.origin.z, "VR orb %d is in front of the giant" % i)
			var label := v + Vector3(0, 1.2 * Deep.VR_SCALE, 0)  # (picks.gd label_y 1.2 x the orb scale)
			_expect(label.distance_to(head.origin) > VrViewCheck.FACE_D + 0.02, "VR orb %d's name is not in the face (%.2f m)" % [i, label.distance_to(head.origin)])
			_expect(v.y - orb_m > Main.TABLE_Y + BD.GROUND_Y * Main.S_VR + 0.12, "VR orb %d floats above the island (eyes %.2f m)" % [i, eye])
			for j in range(i + 1, vr.size()):
				_expect(v.distance_to(vr[j]) > 2.0 * (orb_m + Deep.HAND_R), "VR orbs %d and %d are apart" % [i, j])
		_expect((vr[0] as Vector3).x < (vr[2] as Vector3).x, "GENTLE is on the VR giant's left")
		_expect(orb_m > 0.04 and orb_m < 0.12, "VR orbs are a modest size (%.2f m)" % orb_m)
	var bs := Deep.board_spots()
	for i in bs.size():
		var b: Vector3 = bs[i]
		_expect(Vector2(b.x, b.z).length() < BD.ISLAND_R and b.y - PickOrbs.BALL_R * Deep.BOARD_SCALE > 2.5, "board orb %d floats over the island" % i)
		for j in range(i + 1, bs.size()):
			_expect(b.distance_to(bs[j]) > 3.0 * PickOrbs.BALL_R * Deep.BOARD_SCALE, "board orbs %d and %d are apart" % [i, j])
	_expect(Deep.tv_order(bs) == [0, 1, 2], "board row: GENTLE on the TV's left")
	_expect(Deep.DWELL >= 0.3, "VR picks need a deliberate touch")


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: %s" % what)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)
