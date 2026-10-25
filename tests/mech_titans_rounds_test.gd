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
## Prints "SCRIPT ERROR: ..." for each failure.

const RoundGen := preload("res://games/mech_titans/roundgen.gd")
const Data := preload("res://games/mech_titans/data.gd")
const City := preload("res://games/mech_titans/city.gd")
const Seeded := preload("res://core/seeded.gd")

const GRID := 0.75
const TRUCK_R := 2.5

var fails := 0
var cities := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 120
	var t0 := Time.get_ticks_msec()
	var total := 0
	for friends in [0, 3, 7, 13, 20]:
		var r := Seeded.validate(func(s: int) -> Array:
				var out: Array = []
				for i in 40:
					out.append(RoundGen.make(i, s, friends))
				return out,
			func(rounds: Array) -> Array:
				var why: Array = []
				for m in rounds:
					for w in RoundGen.check(m, friends):
						why.append("round %d: %s" % [int(m.index) + 1, w])
				var d: Dictionary = rounds[3]
				if not bool(d.daily) or not bool((d.variant as Dictionary).get("golden", false)):
					why.append("round 4 is not today's golden kaiju")
				return why,
			seeds, 3, [0, 1, 999999], "ROUNDS f%d" % friends)
		total += int(r.checked) * 40
		fails += (r.failures as Array).size()
	# Today's kaiju is the same whatever the session seed.
	_expect(var_to_str(RoundGen.make(3, 1, 5)) == var_to_str(RoundGen.make(3, 777, 5)), "today's kaiju is the same for every session")
	# Places open with friends; twins every fifth made round.
	_expect(RoundGen.places_open(0) == ["downtown"] and RoundGen.places_open(12).size() == 6, "places open with friends")
	_expect(RoundGen.place_opened(1, 2) == "harbour" and RoundGen.place_opened(2, 3) == "", "place_opened")
	_expect((RoundGen.make(7, 5, 3).steps[0].boss as Array).size() == 2, "round 8 is TWIN TROUBLE")
	# Cities: the lessons, then a sample of made rounds in every place.
	for i in RoundGen.LESSONS:
		_check_city(RoundGen.make(i, 1, 0))
	var city_seeds := maxi(4, seeds / 10)
	for s in city_seeds:
		for i in [3, 4, 6, 7, 9]:
			_check_city(RoundGen.make(i, 100 + s * 31, 20))
	print("ROUNDS: %d rounds and %d cities checked, %d failures (%d ms)" % [total, cities, fails, Time.get_ticks_msec() - t0])
	quit(1 if fails > 0 else 0)


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
