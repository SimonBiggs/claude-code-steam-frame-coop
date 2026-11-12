extends SceneTree
## OBSTACLE RUSH second pass validator (no game, no window): games/obstacle_rush/deep.gd.
##   godot-test --headless --path . -s res://tests/obstacle_rush_deep_test.gd      (SEEDS=200 for more; GEN_QUICK=1 samples)
## Proves, over many shows (every tier, every mode, every season, every course of a show):
##   - GENTLE <= BRAVE <= HARD: the mode table (deep.gd ordered()) AND what the courses really get (the tier, surprises
##     a course, warning seconds, band sizes, knock-backs, wading speed), and every moded course passes CourseGen.check;
##   - every course can be finished with every gift: the simulated jelly bean (coursegen.gd simulate) runs it to the
##     flag at CPU and full speed, jumping early and late, in SPRING SHOES, a GLIDE CAPE and ZOOM SHOES;
##   - Coach Jelly's surprises are fair (deep.gd problems(): none on the lessons or a show's first course, on solid
##     floor away from every obstacle, pad, the start and the flag, never on top of each other, told long enough for a
##     small kid standing in the middle to run out), the same every time and unchanged over the network (pack);
##   - TODAY'S COURSE in every mode over 400+ dates: finishable (CourseGen.check), with every gift, and its surprises fair;
##   - the gifts: three different unlocked ones, the newest among them, not the last again when there are others,
##     every picture drawn, short names; every gift helps;
##   - the seasons: each has a picture, a short line and both surprises; every date has a season;
##   - the medal hall only grows and every gift opens; the season props stand on the lawn clear of the table;
##   - the pick rows: the start orbs over solid start floor on every course, apart, above the runners' heads, the fence
##     and the orbs short of the first obstacle, nobody starts under one; the VR orbs an arm's reach in front of the
##     giant, small, apart; picks need a deliberate touch;
##   - the validator catches unfair surprises; every key colour stands out (palette.gd);
##   - fast: a course's surprises are made and checked well under 100 ms.
## Prints "SCRIPT ERROR: ..." for each failure and "RUSH DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/obstacle_rush/deep.gd")
const G := preload("res://games/obstacle_rush/coursegen.gd")
const Story := preload("res://games/obstacle_rush/story.gd")
const Season := preload("res://games/obstacle_rush/season.gd")
const Hall := preload("res://games/obstacle_rush/hall.gd")
const Runner := preload("res://games/obstacle_rush/runner.gd")
const RunnerLook := preload("res://games/obstacle_rush/runner_look.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Seeded := preload("res://core/seeded.gd")
const TestTime := preload("res://tests/test_time.gd")

const GIFT_PHYS: Array[String] = ["springs", "cape", "zoom"]

var fails := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	for w in Deep.ordered():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("obstacle_rush"):
		_fail("contrast: " + str(w))
	var Giant: GDScript = load("res://games/obstacle_rush/giant.gd")
	_expect(is_equal_approx(Deep.VR_S, float(Giant.S)), "deep.gd VR_S matches the giant's world scale")
	_expect(Deep.HIT_PAD <= RunnerLook.RADIUS, "a surprise catches a runner by their body, no further")
	# Shows over many seeds (Seeded.validate: today's sample in a quick run): every course of shows 1..6 in every mode.
	var worst_ms := [0.0]
	var sums := {}
	for m in PickOrbs.MODE_IDS:
		sums[m] = {"tier": 0, "n": 0, "haz": 0, "warn": 0.0, "w": 0.0, "hit": 0.0, "wade": 0.0}
	var seasons: Array = Deep.SEASONS.keys()
	var res := Seeded.validate(func(s: int) -> Array:
			var all: Array = []
			for shows in [1, 3, 6]:
				for i in Story.COURSES:
					all.append([shows, i])
			return [s, all],
		func(pack: Array) -> Array:
			var why: Array = []
			var world := int(pack[0])
			for si in pack[1]:
				var shows := int(si[0])
				var i := int(si[1])
				var season: String = seasons[(world + i) % 4]
				for m in PickOrbs.MODE_IDS:
					var d := Story.describe(Deep.moded(Story.recipe(shows, world, i, false), m))
					var c := G.make(d)
					var tag := "world %d show %d course %d %s" % [world, shows, i, m]
					for w in G.check(c):
						why.append("%s: %s" % [tag, w])
					for w in _gift_runs(c):
						why.append("%s: %s" % [tag, w])
					for w in _row_problems(c):
						why.append("%s: %s" % [tag, w])
					for first in [false, true]:
						var spec := {"mode": m, "season": season, "course": i, "first": first}
						var t1 := Time.get_ticks_usec()
						var list := Deep.hazards(c, spec)
						var probs := Deep.problems(c, list, spec)
						worst_ms[0] = TestTime.worst(worst_ms[0], (Time.get_ticks_usec() - t1) / 1000.0, func() -> Variant:
							return Deep.problems(c, Deep.hazards(c, spec), spec))
						for w in probs:
							why.append("%s (%s): %s" % [tag, str(spec), w])
						if var_to_str(list) != var_to_str(Deep.hazards(c, spec)):
							why.append("%s: surprises not the same every time" % tag)
						for e in list:
							if var_to_str(Deep.unpack(Deep.pack(e))) != var_to_str(e):
								why.append("a surprise changes over the network: %s" % str(e))
						if i == 0 and not first and not list.is_empty():
							why.append("%s: surprises on a show's first course" % tag)
						if not first and i >= 1:
							var sm: Dictionary = sums[m]
							sm.n += 1
							sm.tier += int(d.get("tier", 0))
							sm.haz += list.size()
							for e in list:
								if not is_equal_approx(float(e.w), float(Deep.mode_data(m)[String(e.kind) + "_w"])):
									why.append("%s: a %s band not its mode's size" % [tag, e.kind])
								sm.warn += float(e.warn)
								sm.w += float(e.w)
								sm.hit += float(Deep.mode_data(m).hit)
								sm.wade += float(Deep.mode_data(m).wade)
			return why,
		Seeded.test_count(24), 1, [], "RUSH DEEP")
	if not bool(res.ok):
		fails += 1
	# What the courses really get: GENTLE <= BRAVE <= HARD.
	var avg := func(m: String, k: String) -> float:
		var sm: Dictionary = sums[m]
		return float(sm[k]) / maxf(1.0, float(sm.n))
	var per := func(m: String, k: String) -> float:
		return float((sums[m] as Dictionary)[k]) / maxf(1.0, float((sums[m] as Dictionary).haz))
	for k in ["tier", "haz"]:
		_expect(avg.call("gentle", k) <= avg.call("brave", k) + 0.001 and avg.call("brave", k) <= avg.call("hard", k) + 0.001,
			"courses: %s gentle %.2f <= brave %.2f <= hard %.2f" % [k, avg.call("gentle", k), avg.call("brave", k), avg.call("hard", k)])
	for k in ["hit"]:  # (band sizes: each surprise has its mode's size, checked below, and ordered() orders the table)
		_expect(per.call("gentle", k) <= per.call("brave", k) + 0.001 and per.call("brave", k) <= per.call("hard", k) + 0.001,
			"surprises: %s gentle %.2f <= brave %.2f <= hard %.2f" % [k, per.call("gentle", k), per.call("brave", k), per.call("hard", k)])
	for k in ["warn", "wade"]:
		_expect(per.call("gentle", k) >= per.call("brave", k) - 0.001 and per.call("brave", k) >= per.call("hard", k) - 0.001,
			"surprises: %s most on gentle (%.2f, %.2f, %.2f)" % [k, per.call("gentle", k), per.call("brave", k), per.call("hard", k)])
	_expect(avg.call("gentle", "haz") < avg.call("hard", "haz"), "hard has more surprises than gentle")
	_expect(avg.call("gentle", "haz") >= 0.5, "even gentle courses have surprises (%.2f a course)" % avg.call("gentle", "haz"))
	_expect(avg.call("brave", "haz") >= 1.0, "brave courses have a surprise or more (%.2f a course)" % avg.call("brave", "haz"))
	_expect(avg.call("gentle", "tier") < avg.call("hard", "tier"), "hard courses are a harder tier than gentle ones")
	print("rush deep: surprises a course gentle %.2f brave %.2f hard %.2f; tiers %.2f %.2f %.2f" % [avg.call("gentle", "haz"),
		avg.call("brave", "haz"), avg.call("hard", "haz"), avg.call("gentle", "tier"), avg.call("brave", "tier"), avg.call("hard", "tier")])
	_expect(worst_ms[0] < 100.0, "a course's surprises are made and checked fast (%.1f ms)" % worst_ms[0])
	# The lessons: no surprises, no pick row needed (no picks on the lessons show), every gift still finishes them.
	for i in G.LESSONS.size():
		var c := G.lesson(i, 7)
		_expect(Deep.hazards(c, {"mode": "hard", "course": 2, "first": true}).is_empty(), "no surprises on lesson %d" % i)
		for w in _gift_runs(c):
			_fail("lesson %d: %s" % [i, w])
	# TODAY'S COURSE over 400+ dates, every mode (the mode never changes it).
	var days := Seeded.validate_days(func(date: String) -> Dictionary:
			var d := Story.describe(Story.recipe(3, 7, 0, true, date))
			var c := G.make(d)
			c["_d"] = d
			return c,
		func(c: Dictionary) -> Array:
			var why: Array = G.check(c)
			why.append_array(_gift_runs(c))
			why.append_array(_row_problems(c))
			if String(c._d.get("k", "")) != "daily":
				why.append("not the daily course")
			for m in PickOrbs.MODE_IDS:
				if var_to_str(Deep.moded(c._d, m)) != var_to_str(c._d):
					why.append("a mode changes TODAY'S COURSE")
				for first in [false, true]:
					var spec := {"mode": m, "season": "winter", "course": 0, "first": first}
					for w in Deep.problems(c, Deep.hazards(c, spec), spec):
						why.append("%s: %s" % [m, w])
			return why,
		400, "RUSH DAILY", ["2026-11-12", "2026-11-13"])
	if not bool(days.ok):
		fails += 1
	# The validator catches unfair surprises.
	var c0 := G.generate(42, 3)
	var spec0 := {"mode": "brave", "season": "spring", "course": 2}
	var spans := Deep.free_spans(c0)
	_expect(not spans.is_empty(), "a tier 3 course has plain floor for a surprise")
	var sx := (float(spans[0][0]) + float(spans[0][1])) * 0.5 if not spans.is_empty() else 0.0
	var sy := float(spans[0][2]) if not spans.is_empty() else 0.0
	_expect(not Deep.problems(c0, [{"kind": "log", "x": sx, "y": sy, "w": 0.6, "warn": 0.8}], spec0).is_empty(), "a surprise told too briefly is caught")
	var gap_x := 0.0
	for o in c0.obstacles:
		if String(o[2]) != "drop":
			gap_x = (float(o[0]) + float(o[1])) * 0.5
			break
	_expect(not Deep.problems(c0, [{"kind": "water", "x": gap_x, "y": 0.0, "w": 0.8, "warn": 2.8}], spec0).is_empty(), "a surprise in an obstacle is caught")
	_expect(not Deep.problems(c0, [{"kind": "log", "x": float(c0.start_x) + 1.0, "y": 0.0, "w": 0.6, "warn": 2.8}], spec0).is_empty(), "a surprise at the start is caught")
	_expect(not Deep.problems(c0, [{"kind": "log", "x": sx, "y": sy, "w": 0.6, "warn": 2.8}, {"kind": "water", "x": sx + 0.4, "y": sy, "w": 0.6, "warn": 2.8}], spec0).is_empty(), "two surprises on top of each other are caught")
	_expect(not Deep.problems(c0, [{"kind": "log", "x": sx, "y": sy, "w": 0.6, "warn": 2.8}], {"mode": "brave", "course": 0}).is_empty(), "a surprise on a show's first course is caught")
	_expect(not Deep.problems(c0, [{"kind": "log", "x": sx, "y": sy, "w": 3.0, "warn": 2.8}], spec0).is_empty(), "a band too wide is caught")
	_expect(not Deep.problems(G.lesson(0), [{"kind": "log", "x": 0.0, "y": 0.0, "w": 0.6, "warn": 3.0}], spec0).is_empty(), "a surprise on a lesson is caught")
	var e0 := {"kind": "log", "x": 0.0, "y": 0.0, "w": 0.6}
	_expect(Deep.inside(e0, Vector3(0.8, 0.0, 0.0)) and not Deep.inside(e0, Vector3(0.9, 0.0, 0.0)), "a runner's body counts at a band's edge")
	_expect(Deep.inside(e0, Vector3(0.0, 1.0, 0.0)) and not Deep.inside(e0, Vector3(0.0, 3.0, 0.0)), "a little hop is still caught, a big step above is not")
	_expect(Deep.wait_before(e0, Vector3(-1.6, 0.0, 0.0)) and not Deep.wait_before(e0, Vector3(0.0, 0.0, 0.0)) and not Deep.wait_before(e0, Vector3(-5.0, 0.0, 0.0)), "runners wait just before a told band")
	_expect(not Deep.inside(e0, Vector3(-0.6 - Deep.WAIT_NEAR + 0.3, 0.0, 0.0)), "a runner waiting before a band is not caught")
	# Gifts.
	for g in Deep.GIFTS:
		_expect(StoryCard.has_picture(String(g.pic)), "gift %s has a picture" % g.id)
		_expect(String(g.name).length() <= 14, "gift %s has a short name" % g.id)
		_expect(String(g.line).length() <= 28, "gift %s has a short line" % g.id)
	for medals in 6:
		var un := Deep.unlocked(medals)
		for last in [""] + un:
			for s in 12:
				var ch := Deep.gift_choices(medals, String(last), s * 977)
				_expect(ch.size() == 3, "three gifts offered (%d medals)" % medals)
				var seen := {}
				for id in ch:
					seen[id] = true
					_expect(un.has(id), "only unlocked gifts are offered")
				_expect(seen.size() == ch.size(), "three different gifts")
				if String(last) != un[un.size() - 1] or un.size() <= 3:
					_expect(ch.has(un[un.size() - 1]), "the newest gift is offered")
				if un.size() > 3:
					_expect(not ch.has(last) or String(last) == "", "not the last gift again")
	_expect(Deep.unlocked(0).size() == 3 and Deep.unlocked(4).size() == Deep.GIFTS.size(), "three gifts at first, all of them after four medals")
	_expect(float(Deep.phys("springs").jump) > 1.0, "SPRING SHOES jump higher")
	_expect(float(Deep.phys("cape").fall) < 1.0 and float(Deep.phys("cape").max_fall) < 30.0, "the GLIDE CAPE falls slowly")
	_expect(float(Deep.phys("zoom").speed) > 1.0, "ZOOM SHOES run faster")
	_expect(Deep.star_r("magnet") > Deep.star_r(""), "the STAR MAGNET grabs stars from further")
	_expect(Deep.phys("").is_empty() and Deep.phys("bubble").is_empty(), "no gift (and the bubble) keeps the runner's own physics")
	var spring_h := pow(Runner.JUMP_V * float(Deep.phys("springs").jump), 2.0) / (2.0 * Runner.GRAVITY)
	_expect(spring_h + RunnerLook.HEIGHT < 3.0 + 0.4, "SPRING SHOES never hop over a door wall (%.2f m)" % spring_h)
	_expect(spring_h < G.STEP, "SPRING SHOES never skip a bounce pad's big step (%.2f m)" % spring_h)
	var flat := _jump_len({})
	for g in GIFT_PHYS:
		var l := _jump_len(Deep.phys(g))
		_expect(l <= flat * 1.03, "%s never carries a jump further (%.2f m, plain %.2f m)" % [g, l, flat])
		_expect(l >= flat * 0.85, "%s still jumps a gap (%.2f m, plain %.2f m)" % [g, l, flat])
	# Seasons.
	for s in ["spring", "summer", "autumn", "winter"]:
		_expect(Deep.SEASONS.has(s), "season %s has a course" % s)
		var sd := Deep.season_data(s)
		_expect(StoryCard.has_picture(String(sd.pic)), "season %s has a picture" % s)
		_expect(String(sd.line).length() <= 24 and String(sd.name).length() <= 16, "season %s has a short line and name" % s)
		_expect((sd.weights as Array).size() == 2 and float(sd.weights[0]) > 0.0 and float(sd.weights[1]) > 0.0, "season %s has both surprises" % s)
	for date in Seeded.dates(370):
		_expect(Deep.SEASONS.has(Seeded.season(String(date))), "every date has a season (%s)" % date)
	for k in Deep.KINDS:
		_expect(StoryCard.has_picture(String(Deep.KIND_PICS[k])), "surprise %s has a picture" % k)
		_expect(String(Deep.KIND_NAMES[k]).length() <= 14, "surprise %s has a short banner" % k)
	for p in Season.SPOTS:
		var v: Vector2 = p
		_expect(absf(v.x) > 23.0 or v.y < -11.0, "season prop %s stands on the lawn off the table" % str(v))
		_expect(not (v.y > 5.0 and v.y < 10.5 and absf(v.x) < 22.0), "season prop %s is clear of the giant's walk" % str(v))
	# The medal hall.
	var prev := 0
	for n in 60:
		_expect(Deep.trophies(n) >= prev, "gold cups only grow")
		prev = Deep.trophies(n)
	_expect(Deep.HALL_SHOWN == Hall.PER_BOARD * Hall.BOARD_X.size(), "the hall's boards hold every medal shown")
	_expect(StoryCard.has_picture("medal") and StoryCard.has_picture("trophy"), "the medal hall has pictures")
	for m in PickOrbs.MODE_IDS:
		_expect(Deep.MEDAL_COLORS.has(m), "a %s medal has a colour" % m)
	_expect(Hall.BOARD_BOTTOM >= 2.9, "the hall stands over the grandstand's back rail")
	_expect(Story.save_defaults().has("medals") and Story.save_defaults().has("medal_total"), "the medals are saved")
	# The VR pick row: an arm's reach, small, apart.
	var head := Vector3(0.0, 4.5, 7.6)
	var vr := Deep.vr_spots(head)
	for i in vr.size():
		var d: float = (vr[i] as Vector3).distance_to(head) / Deep.VR_S
		_expect(d > 0.3 and d < 0.62, "VR orb %d is an arm's reach away (%.2f m)" % [i, d])
		_expect((vr[i] as Vector3).z < head.z, "VR orb %d is in front of the giant" % i)
		for j in range(i + 1, vr.size()):
			_expect((vr[i] as Vector3).distance_to(vr[j]) > 2.0 * (Deep.orb_r(true) + Deep.HAND_R), "VR orbs %d and %d are apart" % [i, j])
	_expect(Deep.orb_r(true) / Deep.VR_S > 0.05 and Deep.orb_r(true) / Deep.VR_S < 0.12, "VR orbs are a modest size (%.2f m)" % (Deep.orb_r(true) / Deep.VR_S))
	_expect((vr[0] as Vector3).x < (vr[2] as Vector3).x, "GENTLE is on the giant's left")
	_expect(Deep.DWELL >= 0.3 and Deep.TV_DWELL >= 0.8, "picks need a deliberate touch")
	for why in StoryCard.check():
		_fail(why)
	print("rush deep: %d ms" % (Time.get_ticks_msec() - t0))
	print("RUSH DEEP: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


## Every gift that changes how a runner moves still runs course c to the flag (CPU and full speed, early and late).
func _gift_runs(c: Dictionary) -> Array:
	var why: Array = []
	for g in GIFT_PHYS:
		for speed in [Runner.CPU_SPEED, 1.0]:
			for early in [true, false]:
				var sim := G.simulate(c, float(speed), bool(early), Deep.phys(g))
				if not bool(sim.ok):
					why.append("%s: %s" % [g, String(sim.why)])
	return why


## How far a running jump on flat ground carries a runner at full speed with phys (runner.gd's rules).
func _jump_len(phys: Dictionary) -> float:
	var dt := 1.0 / 60.0
	var sp := Runner.RUN_SPEED * float(phys.get("speed", 1.0))
	var vx := sp
	var vy := Runner.JUMP_V * float(phys.get("jump", 1.0))
	var x := 0.0
	var y := 0.0
	for k in 600:
		vx = minf(move_toward(vx, sp, Runner.AIR_ACCEL * dt), Runner.RUN_SPEED * float(phys.get("air", 99.0)))
		vy -= Runner.GRAVITY * dt * (float(phys.get("fall", 1.0)) if vy < 0.0 else 1.0)
		vy = maxf(vy, -float(phys.get("max_fall", 30.0)))
		x += vx * dt
		y += vy * dt
		if y <= 0.0:
			break
	return x


## The start pick row on course c: over solid start floor, apart, above heads, short of the first obstacle; the fence
## too; no runner starts under an orb.
func _row_problems(c: Dictionary) -> Array:
	var why: Array = []
	var row := Deep.row_spots(c)
	var first := Deep.first_obstacle(c)
	if Deep.FENCE + RunnerLook.RADIUS > first - 0.2:
		why.append("the pick fence (%.1f) runs into the first obstacle (%.1f)" % [Deep.FENCE, first])
	for i in row.size():
		var sp: Vector3 = row[i]
		var floor_y := G.support_y(c, sp.x, sp.z, 1.0)
		if absf(floor_y - (sp.y - Deep.ORB_Y)) > 0.01 or absf(sp.z) > float(c.half_w) - 0.5:
			why.append("start orb %d isn't over the start floor" % i)
		if sp.y - floor_y - Deep.orb_r(false) < RunnerLook.HEIGHT + 0.3:
			why.append("start orb %d hangs in the runners' faces" % i)
		if sp.x + Deep.TV_R - float(c.start_x) > first - 0.3:
			why.append("start orb %d is over the first obstacle" % i)
		if Deep.under(row, Vector3(sp.x, floor_y, sp.z)) != i:
			why.append("a runner can't stand under start orb %d" % i)
		for j in range(i + 1, row.size()):
			if Vector2(sp.x, sp.z).distance_to(Vector2((row[j] as Vector3).x, (row[j] as Vector3).z)) < Deep.TV_R * 2.0 + 0.3:
				why.append("start orbs %d and %d are too close" % [i, j])
	for n in 8:
		var st := G.start_spot(c, n, 8)
		if Deep.under(row, st) >= 0:
			why.append("runner %d starts under an orb" % n)
	return why


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: %s" % what)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)
