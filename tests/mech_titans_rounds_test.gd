extends SceneTree
## MECH TITANS made rounds (SIMPLE_MODE, games/mech_titans/roundgen.gd): checks many seeds, no window.
##   godot-test --headless --path . -s res://tests/mech_titans_rounds_test.gd      (SEEDS=200 for more)
##  - every round (lessons and made rounds 4-40, with 0-20 kaiju friends) is fair: a known place that is
##    open with that many friends, a known sky, one or two different lost kaiju that suit SIMPLE_MODE
##    (no crab, no mega), helpers within limits, health / speed / calm within the kind limits, a name
##    of one or two capital words (no how-to text); round 4 is today's golden kaiju for every seed;
##  - the same seed makes the same rounds;
##  - the cities: for the lessons and a sample of made rounds, a rescue truck (2.5 m) can drive from the
##    Titan's start to within pick-up reach of every rescue spot and both shelters and where the lost kaiju walk in and go to
##    (0.75 m grid flood fill around the buildings), and the kaiju start in the open.
##  - DEEP (titans-deep): the same round checks at every difficulty (GENTLE / BRAVE / MEGA); every district's
##    hazard is fair at every difficulty and lap (districts.gd check: the Titan can always walk out of a warning,
##    gentle hazards never aim at the Titan or knock it over); every boss kaiju is fair (bigboss.gd check: long
##    readable tells, a gentle Titan can walk out, even a MEGA one can dash out, one hit never knocks it over) and
##    every place has one; boss rounds come every fifth made round; the difficulty RISES SMOOTHLY (each mode's
##    threat never drops and grows at most 15% a round, GENTLE < BRAVE < MEGA every round, MEGA ends at least
##    2.5x GENTLE's top); upgrade pods are fair for every seed / unlock level / upgrades taken (upgrades.gd
##    check_offer) and every upgrade, frame and BRAVE unlocks exactly once as the sanctuary grows; frames are
##    trades (frames.gd check). The pure-data checks must take < 100 ms (a Deck).
## Prints "SCRIPT ERROR: ..." for each failure.

const RoundGen := preload("res://games/mech_titans/roundgen.gd")
const Data := preload("res://games/mech_titans/data.gd")
const City := preload("res://games/mech_titans/city.gd")
const Seeded := preload("res://core/seeded.gd")
const Districts := preload("res://games/mech_titans/districts.gd")
const BigBoss := preload("res://games/mech_titans/bigboss.gd")
const Upgrades := preload("res://games/mech_titans/upgrades.gd")
const Frames := preload("res://games/mech_titans/frames.gd")
const Sanctuary := preload("res://games/mech_titans/sanctuary.gd")

const GRID := 0.75
const TRUCK_R := 2.5

var fails := 0
var cities := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 120
	var t0 := Time.get_ticks_msec()
	var total := 0
	var t_deep := Time.get_ticks_usec()
	_deep_checks()
	var deep_ms := (Time.get_ticks_usec() - t_deep) / 1000.0
	_expect(deep_ms < 100.0, "the deep data checks took %.1f ms (must be < 100 on a Deck)" % deep_ms)
	for mf in [["gentle", 0], ["gentle", 3], ["gentle", 7], ["brave", 13], ["mega", 20], ["mega", 3]]:
		var mode: String = mf[0]
		var friends: int = mf[1]
		var r := Seeded.validate(func(s: int) -> Array:
				var out: Array = []
				for i in 40:
					out.append(RoundGen.make(i, s, friends, mode))
				return out,
			func(rounds: Array) -> Array:
				var why: Array = []
				for m in rounds:
					for w in RoundGen.check(m, friends):
						why.append("round %d: %s" % [int(m.index) + 1, w])
				var d: Dictionary = rounds[3]
				if not bool(d.daily) or not bool((d.variant as Dictionary).get("golden", false)):
					why.append("round 4 is not today's golden kaiju")
				for m2 in rounds:
					var lap := int(m2.index) - RoundGen.LESSONS
					var big := lap >= 0 and lap % RoundGen.BOSS_EVERY == RoundGen.BOSS_EVERY - 1
					if big != (String(m2.get("bigboss", "")) != ""):
						why.append("round %d: a boss round should be every %dth made round" % [int(m2.index) + 1, RoundGen.BOSS_EVERY])
					if lap >= 0 and String(m2.get("mode", "")) != mode:
						why.append("round %d is %s, not %s" % [int(m2.index) + 1, m2.get("mode"), mode])
				return why,
			seeds, 3, [0, 1, 999999], "ROUNDS %s f%d" % [mode, friends])
		total += int(r.checked) * 40
		fails += (r.failures as Array).size()
	# Today's kaiju is the same whatever the session seed.
	_expect(var_to_str(RoundGen.make(3, 1, 5)) == var_to_str(RoundGen.make(3, 777, 5)), "today's kaiju is the same for every session")
	# Places open with friends; twins every fifth made round.
	_expect(RoundGen.places_open(0) == ["downtown"] and RoundGen.places_open(12).size() == 6, "places open with friends")
	_expect(RoundGen.place_opened(1, 2) == "harbour" and RoundGen.place_opened(2, 3) == "", "place_opened")
	_expect((RoundGen.make(RoundGen.LESSONS + RoundGen.TWIN_LAP, 5, 3).steps[0].boss as Array).size() == 2, "round 6 is TWIN TROUBLE")
	_expect(String(RoundGen.make(RoundGen.LESSONS + RoundGen.BOSS_EVERY - 1, 5, 3).get("bigboss", "")) != "", "round 8 is a BOSS KAIJU")
	# Cities: the lessons, then a sample of made rounds in every place.
	for i in RoundGen.LESSONS:
		_check_city(RoundGen.make(i, 1, 0))
	var city_seeds := maxi(4, seeds / 10)
	for s in city_seeds:
		for i in [3, 4, 6, 7, 9]:
			_check_city(RoundGen.make(i, 100 + s * 31, 20))
	print("ROUNDS: %d rounds and %d cities checked, %d failures (%d ms)" % [total, cities, fails, Time.get_ticks_msec() - t0])
	quit(1 if fails > 0 else 0)


## Districts, bosses, the difficulty curves, pods, frames, sanctuary unlocks (pure data, fast).
func _deep_checks() -> void:
	# Every district and boss is fair at every difficulty, every lap.
	for mode in RoundGen.MODE_ORDER:
		var gentle: bool = mode == "gentle"
		for lap in 41:
			var cv := RoundGen.curve(mode, lap)
			var hz_cv := {"haz_every": cv.haz_every, "tell": cv.haz_tell_mult, "haz_aim": cv.haz_aim, "haz_count": cv.haz_count, "dmg": cv.dmg}
			for place in Data.PLACES:
				for w in Districts.check(String(place), hz_cv, gentle):
					_expect(false, "DISTRICT %s %s lap %d: %s" % [place, mode, lap, w])
			var bcv := {"tell": cv.boss_tell, "dmg": cv.dmg, "calm": cv.calm}
			for b in BigBoss.ORDER:
				for w in BigBoss.check(b, bcv, gentle):
					_expect(false, "BOSS %s %s lap %d: %s" % [b, mode, lap, w])
	for place in Data.PLACES:
		_expect(not BigBoss.for_place(String(place)).is_empty(), "a boss kaiju lives in %s" % place)
		_expect(Districts.LIST.has(place), "%s is a district with a hazard" % place)
	for b in BigBoss.ORDER:
		_expect(Data.KAIJU.has(String(BigBoss.LIST[b]["base"])), "boss %s is a known kaiju" % b)
		_expect(RoundGen.BOSSES.values().any(func(l: Array) -> bool: return l.has(BigBoss.LIST[b]["base"])), "boss %s's kaiju is a simple-round kaiju" % b)
	# The difficulty rises smoothly, the modes are ordered, the top is a challenge.
	var tops := {}
	for mode in RoundGen.MODE_ORDER:
		var prev := -1.0
		for lap in 41:
			var th := RoundGen.threat(RoundGen.curve(mode, lap))
			if prev > 0.0:
				_expect(th >= prev - 0.0001, "DIFFICULTY %s drops at made round %d (%.3f -> %.3f)" % [mode, lap + 1, prev, th])
				_expect(th <= prev * 1.15 + 0.0001, "DIFFICULTY %s jumps %.0f%% at made round %d" % [mode, (th / prev - 1.0) * 100.0, lap + 1])
			prev = th
		tops[mode] = prev
	for lap in 41:
		var g := RoundGen.threat(RoundGen.curve("gentle", lap))
		var b2 := RoundGen.threat(RoundGen.curve("brave", lap))
		var m := RoundGen.threat(RoundGen.curve("mega", lap))
		_expect(g < b2 and b2 < m, "DIFFICULTY made round %d: gentle %.2f < brave %.2f < mega %.2f" % [lap + 1, g, b2, m])
	_expect(float(tops["mega"]) >= 2.5 * float(tops["gentle"]), "DIFFICULTY MEGA's top (%.2f) is a challenge next to GENTLE's (%.2f)" % [tops["mega"], tops["gentle"]])
	# Upgrade pods: every seed, unlock level and set already taken.
	for hearts in [0, 4, 9, 15, 22, 32, 99]:
		var unl := Upgrades.unlocked(hearts)
		for seed in 40:
			var have: Array = []
			for round_i in 3 + Upgrades.count() + 2:
				var o := Upgrades.offer(seed, round_i, unl, have)
				var why := Upgrades.check_offer(o, unl, have)
				_expect(why == "", "PODS hearts %d seed %d round %d: %s" % [hearts, seed, round_i, why])
				_expect(var_to_str(o) == var_to_str(Upgrades.offer(seed, round_i, unl, have)), "PODS are the same every time")
				if o.is_empty():
					_expect(have.size() == unl.size(), "PODS ran out with %d of %d taken" % [have.size(), unl.size()])
					break
				have.append(o[seed % o.size()])
	_expect(Upgrades.count() >= 8 and Upgrades.count() <= 10, "8-10 upgrades")
	for u in Upgrades.LIST:
		var nm := String(u["name"])
		_expect(nm.split(" ", false).size() <= 2 and nm == nm.to_upper(), "upgrade name %s is one or two capital words" % nm)
	# Frames are trades; everything unlocks exactly once as the sanctuary grows.
	for w in Frames.check(Data.PAINTS):
		_expect(false, "FRAMES %s" % w)
	var all := Sanctuary.unlocks_between(0, 100000)
	for id in Frames.ORDER:
		var want := 0 if int(Frames.INFO[id]["hearts"]) == 0 else 1
		_expect(all.filter(func(e: Dictionary) -> bool: return e.kind == "frame" and e.id == id).size() == want, "frame %s unlocks once" % id)
	for u2 in Upgrades.LIST:
		var want2 := 0 if int(u2["hearts"]) == 0 else 1
		_expect(all.filter(func(e: Dictionary) -> bool: return e.kind == "upgrade" and e.id == u2.id).size() == want2, "upgrade %s unlocks once" % u2.id)
	var by_steps: Array = []
	for h in 120:
		by_steps.append_array(Sanctuary.unlocks_between(h, h + 1))
	_expect(by_steps.size() == all.size(), "sanctuary unlocks step by step = all at once")
	_expect(Sanctuary.parade_size(0) <= Sanctuary.parade_size(1000) and Sanctuary.parade_size(1000) <= Sanctuary.PARADE_MAX, "the sanctuary parade grows within limits")


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: ROUNDS %s" % what)


func _check_city(m: Dictionary) -> void:
	cities += 1
	var c := City.new()
	root.add_child(c)
	c.build(String(m.place), int(m.seed), false, String(m.protect))
	var tag := "city %s seed %d (round %d)" % [m.place, int(m.seed), int(m.index) + 1]
	var reach := _flood(c, Data.MECH_START)
	var targets: Array = []
	for p in c.rescue_spots:
		targets.append(["rescue spot", p, 4.8])  # a truck picks people up within 8 m (support.gd PICKUP_R)
	for p in c.shelters:
		targets.append(["shelter", p, 4.8])
	var bosses: Array = m.steps[0].boss
	for k in bosses.size():
		var sx := 0.0 if bosses.size() <= 1 else (-6.5 if k == 0 else 6.5)
		var start := Vector3(sx, 0, -44.0 - 8.0 * k)
		var goal := Vector3(sx * 2.0, 0, 4.0)
		var kr := float(Data.KAIJU[String(bosses[k])]["height"]) * 0.3
		if c.push_out(start, kr).distance_to(start) > 0.01:
			_expect(false, "%s: lost kaiju %d starts inside a building" % [tag, k])
		targets.append(["kaiju start", start, 1.5])
		targets.append(["kaiju goal", goal, 1.5])
	for t in targets:
		if not _near(reach, t[1], t[2]):
			_expect(false, "%s: the %s at %s can't be reached from the start" % [tag, t[0], str(t[1])])
	if c.rescue_spots.size() < int(m.rescue):
		_expect(false, "%s: %d rescue spots for %d rescues" % [tag, c.rescue_spots.size(), int(m.rescue)])
	c.free()


## A reachable cell within `r` metres of p?
func _near(reach: Dictionary, p: Vector3, r: float) -> bool:
	var n := ceili(r / GRID)
	var c := _cell(p)
	for dx in range(-n, n + 1):
		for dz in range(-n, n + 1):
			if Vector2(dx, dz).length() * GRID <= r and reach.has(c + Vector2i(dx, dz)):
				return true
	return false


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x / GRID), roundi(p.z / GRID))


## Every grid cell a truck can drive to from `from` (cells whose centre is clear of every building).
func _flood(c: City, from: Vector3) -> Dictionary:
	var seen := {}
	var lim := roundi((Data.MAP + 6.0) / GRID)
	var start := _cell(from)
	var queue: Array[Vector2i] = [start]
	seen[start] = true
	var head := 0
	while head < queue.size():
		var q := queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = q + d
			if seen.has(n) or absi(n.x) > lim or absi(n.y) > lim:
				continue
			var p := Vector3(n.x * GRID, 0.0, n.y * GRID)
			if c.push_out(p, TRUCK_R).distance_to(p) > 0.01:
				continue
			seen[n] = true
			queue.append(n)
	return seen
