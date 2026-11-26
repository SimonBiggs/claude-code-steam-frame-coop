extends SceneTree
## DUNGEON DELVE: Cinder's tools, gates, heart pieces, the shop's big item and rare mimics (no game, no window).
##   godot-test --headless --path . -s res://tests/dungeon_delve_tools_test.gd   (GEN_QUICK=1 = the landing sample)
## The validator (FloorGen.gate_problem) on every zone x floor x difficulty x seed, for EVERY set of tools a party might
## hold when a floor starts (a party that missed a tool, grabbed them all, or started deep):
##  - every gate opens with a tool held at the start or the one lying on that floor, which is never behind a gate;
##  - every gate leads into a dead-end vault with a heart piece; every room can be reached (FloorGen.solve with tools);
##  - the floor without its tools is the same floor (the gates have their own rng) and the same seed builds the same floor.
## A whole run, floor by floor, picking up each tool as it comes AND a run that never picks one up: every floor solvable.
## And: all three gates show up; a BRAVE run's first two biomes hide enough heart pieces for 2+ new hearts; the shop's
## heart piece costs more than a floor's chests hold (save up!) but not more than ~4 floors'; mimics are rare (5-20 %
## of chests from floor 3 on); both the bonk (_attack) and the VR knight's sword open gates; tips are short.
## Prints "SCRIPT ERROR: TOOLS ..." for each failure.

const FloorGen := preload("res://games/dungeon_delve/floorgen.gd")
const Loot := preload("res://games/dungeon_delve/loot.gd")
const Deep := preload("res://games/dungeon_delve/deep.gd")
const Seeded := preload("res://core/seeded.gd")

var fails := 0
var checks := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var seeds := Seeded.test_count(24, 4)
	var all_tools := (1 << FloorGen.TOOLS.size()) - 1
	var gates_seen := {}
	for heroic in [false, true]:
		for z in FloorGen.ZONE_COUNT + 2:
			for fl in FloorGen.FLOORS_PER_ZONE:
				for sd in seeds:
					var seed_v := 3000 + sd * 7177
					var base := FloorGen.generate(seed_v, z, fl, heroic, "floor", 0)
					for tools in all_tools + 1:
						var f := FloorGen.generate(seed_v, z, fl, heroic, "floor", tools)
						_check(f, "seed %d %d-%d %s tools %d" % [seed_v, z + 1, fl + 1, "heroic" if heroic else "brave", tools])
						for d in f["doors"]:
							if int((d as Dictionary)["type"]) == FloorGen.GATE:
								gates_seen[String(FloorGen.TOOLS[int((d as Dictionary)["tool"])]["gate"])] = true
						# The rest of the floor doesn't change with the tools (same rooms first, same monsters and chests).
						var nb := (base["rooms"] as Array).size() - (base["vaults"] as Array).size()
						for ri in nb:
							var a: Dictionary = (base["rooms"] as Array)[ri]
							var b: Dictionary = (f["rooms"] as Array)[ri]
							if a["cell"] != b["cell"] or var_to_str(a["foes"]) != var_to_str(b["foes"]) or var_to_str(a["chests"]) != var_to_str(b["chests"]):
								_fail("seed %d %d-%d tools %d: room %d changes with the tools held" % [seed_v, z + 1, fl + 1, tools, ri])
								break
					var again := FloorGen.generate(seed_v, z, fl, heroic, "floor", 5)
					if var_to_str(again) != var_to_str(FloorGen.generate(seed_v, z, fl, heroic, "floor", 5)):
						_fail("seed %d %d-%d: not deterministic" % [seed_v, z + 1, fl + 1])
	for gk in ["chasm", "block", "bramble"]:
		if not gates_seen.has(gk):
			_fail("no %s gate on any floor" % gk)
	_check_runs(seeds)
	_check_pieces(seeds)
	_check_shop()
	_check_mimics(seeds)
	_check_sources()
	print("TOOLS: %s - %d floors checked, %d failures (%d ms)" % ["PASS" if fails == 0 else "FAIL", checks, fails, Time.get_ticks_msec() - t0])
	quit(1 if fails > 0 else 0)


func _fail(msg: String) -> void:
	fails += 1
	if fails < 40:
		print("SCRIPT ERROR: TOOLS %s" % msg)


func _check(f: Dictionary, tag: String) -> void:
	checks += 1
	var why := FloorGen.gate_problem(f)
	if why != "":
		_fail("%s: %s" % [tag, why])
	var held := int(f["tools_in"])
	for d in f["doors"]:
		var dd: Dictionary = d
		if int(dd["type"]) == FloorGen.GATE and held & (1 << int(dd["tool"])) == 0 and int(dd["tool"]) != int(f["tool"]):
			_fail("%s: a gate for a tool the party can't have" % tag)
	if FloorGen.global_floor(int(f["zone"]), int(f["floor"])) == 0 and held == 0 and not (f["vaults"] as Array).is_empty():
		_fail("%s: a gate on the very first floor (no tool yet)" % tag)


## A run, floor by floor: one party picks up every tool as soon as it lies there, one never does, one skips the
## first floor's tool and grabs the next. Every floor of each must pass gate_problem.
func _check_runs(seeds: int) -> void:
	for sd in seeds:
		for style in ["grab", "miss", "late"]:
			var tools := 0
			for g in (FloorGen.ZONE_COUNT + 1) * FloorGen.FLOORS_PER_ZONE:
				var f := FloorGen.generate(900 + sd * 31, g / FloorGen.FLOORS_PER_ZONE, g % FloorGen.FLOORS_PER_ZONE, sd % 2 == 1, "floor", tools)
				_check(f, "run %d (%s) depth %d" % [900 + sd * 31, style, g + 1])
				var t := int(f["tool"])
				if t >= 0 and (style == "grab" or (style == "late" and g > int(FloorGen.TOOLS[t]["floor"]))):
					tools |= 1 << t
			if style == "grab" and tools != (1 << FloorGen.TOOLS.size()) - 1:
				_fail("a run that grabs every tool doesn't hold them all by the endless depths")
	if FloorGen.tools_by(0) != 0 or FloorGen.tool_for_floor(0, 0) != -1:
		_fail("a tool on the very first floor")
	for i in FloorGen.TOOLS.size():
		var fl := int(FloorGen.TOOLS[i]["floor"])
		if FloorGen.tool_for_floor(fl, FloorGen.tools_by(fl)) != i:
			_fail("%s isn't on its floor" % String(FloorGen.TOOLS[i]["name"]))
		if Loot.tool_of_kind(Loot.tool_kind(i)) != i:
			_fail("Loot.TOOL_KINDS out of step with FloorGen.TOOLS")


## Heart pieces a BRAVE run can find in the first two biomes (behind gates, plus one per camp shop): enough for 2 hearts.
func _check_pieces(seeds: int) -> void:
	var total := 0.0
	for sd in seeds:
		var tools := 0
		for g in 2 * FloorGen.FLOORS_PER_ZONE:
			var f := FloorGen.generate(1200 + sd * 17, g / FloorGen.FLOORS_PER_ZONE, g % FloorGen.FLOORS_PER_ZONE, false, "floor", tools)
			total += (f["vaults"] as Array).size()
			if int(f["tool"]) >= 0:
				tools |= 1 << int(f["tool"])
	var per_run := total / float(seeds)
	print("TOOLS: %.1f heart pieces behind gates in the first two biomes (+ %d in the shops)" % [per_run, 2 * FloorGen.FLOORS_PER_ZONE])
	if per_run < 5.0:
		_fail("only %.1f heart pieces behind gates in two biomes" % per_run)


## The shop's big item: a heart piece at Loot.BIG_SPOT, dearer than a floor's chest gold, never more than ~4 floors'.
func _check_shop() -> void:
	if Deep.SHOP_SPOTS.size() != 5:
		_fail("the shop needs 5 spots (4 + the big one)")
	for z in FloorGen.ZONE_COUNT:
		for heroic in [false, true]:
			var rng := RandomNumberGenerator.new()
			rng.seed = 7 + z
			var stock := Loot.shop_stock(rng, z, heroic)
			if stock.size() != Deep.SHOP_SPOTS.size() or int((stock[Loot.BIG_SPOT] as Array)[0]) != Loot.PIECE:
				_fail("zone %d: the heart piece isn't on the big stand" % (z + 1))
				continue
			var price := int((stock[Loot.BIG_SPOT] as Array)[1])
			# A floor's reachable chest gold (what deep._open_chest pays: 2 piles of 5 + 1 more every 6 floors), averaged.
			var gold := 0.0
			for sd in 20:
				for fl in FloorGen.FLOORS_PER_ZONE - 1:
					var f := FloorGen.generate(500 + sd * 13, z, fl, heroic)
					gold += FloorGen.chest_list(f).size() * 5.0 * (2.0 + FloorGen.global_floor(z, fl) / 6)
			gold /= 20.0 * (FloorGen.FLOORS_PER_ZONE - 1)
			if float(price) <= gold:
				_fail("zone %d %s: the heart piece (%d) costs no more than a floor's chests (%.0f): nothing to save up for" % [z + 1, "heroic" if heroic else "brave", price, gold])
			if float(price) > gold * 4.0:
				_fail("zone %d %s: the heart piece (%d) costs more than 4 floors of chests (%.0f each)" % [z + 1, "heroic" if heroic else "brave", price, gold])


## Mimics are rare: 5-20 % of the chests from floor 3 down (they used to be 30 %+).
func _check_mimics(seeds: int) -> void:
	var chests := 0
	var mimics := 0
	for heroic in [false, true]:
		for g in range(2, 16):
			for sd in seeds * 2:
				var f := FloorGen.generate(77 + sd * 101, g / FloorGen.FLOORS_PER_ZONE, g % FloorGen.FLOORS_PER_ZONE, heroic)
				chests += FloorGen.chest_list(f).size()
				mimics += FloorGen.mimic_list(f).size()
	var rate := float(mimics) / maxf(1.0, float(chests + mimics))
	print("TOOLS: mimics %.1f %% of chests" % (rate * 100.0))
	if rate < 0.05 or rate > 0.2:
		_fail("mimics are %.1f %% of chests (5-20 %% wanted: rare, but there)" % (rate * 100.0))


## Every way of hitting things opens gates (a hero's bonk, the VR knight's sword), and the words are short and kind.
func _check_sources() -> void:
	var src := FileAccess.get_file_as_string("res://games/dungeon_delve/deep.gd")
	if src.count("_hit_gate(") < 3:
		_fail("deep.gd: the bonk and the VR sword must both call _hit_gate")
	if not src.contains("\"d_tools\""):
		_fail("deep.gd never shares the tools (d_tools)")
	for t in FloorGen.TOOLS:
		for k in ["verb", "tip"]:
			if String(t[k]).length() > 44:
				_fail("%s's %s is too long for the screen" % [String(t["name"]), k])
	for tip in Deep.TOP_TIPS:
		if String(tip).length() > 56:
			_fail("TOP TIP too long: %s" % tip)
