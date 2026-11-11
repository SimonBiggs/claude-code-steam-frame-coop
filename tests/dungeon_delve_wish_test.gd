extends SceneTree
## DUNGEON DELVE: CINDER'S WISH validator (games/dungeon_delve/wishes.gd), no game, no window.
##   godot-test --headless --path . -s res://tests/dungeon_delve_wish_test.gd
## Over SEEDS seeds x every biome (and two endless depths) x every floor x BRAVE/HEROIC, plus the shop camps:
##  - every dungeon floor gets a wish, every shop camp none;
##  - the wish is possible on that floor (Wishes.problem: the hidden room / switch door / chests are really
##    there and reachable from the start, enough monsters to bop) and the same on every machine;
##  - boss floors always wish for "nobody knocked out"; every kind of wish turns up somewhere;
##  - fast: picking a wish for a floor takes well under a millisecond (it runs on a Deck at every floor).
## Prints "PASS" / "SCRIPT ERROR: WISH ..." (the bot runner greps for SCRIPT ERROR).

const FloorGen := preload("res://games/dungeon_delve/floorgen.gd")
const Wishes := preload("res://games/dungeon_delve/wishes.gd")
const SEEDS := 40

var fails := 0


func _fail(msg: String) -> void:
	fails += 1
	if fails <= 20:
		printerr("SCRIPT ERROR: WISH " + msg)


func _init() -> void:
	var seen := {}
	var floors := 0
	var pick_us := 0
	for s in SEEDS:
		var seed_v := 1000 + s * 7919
		for heroic in [false, true]:
			for z in FloorGen.ZONE_COUNT + 2:
				for fl in FloorGen.FLOORS_PER_ZONE:
					for k in ["floor", "shop"]:
						var f := FloorGen.generate(seed_v, z, fl, heroic, k)
						var t0 := Time.get_ticks_usec()
						var w := Wishes.pick(f)
						pick_us += Time.get_ticks_usec() - t0
						floors += 1
						var where := "seed %d zone %d floor %d %s%s" % [seed_v, z, fl, k, " heroic" if heroic else ""]
						var p := Wishes.problem(f, w)
						if p != "":
							_fail("%s: %s (%s)" % [where, p, str(w)])
						if k == "floor" and FloorGen.is_boss_floor(fl) and String(w.get("id", "")) != "safe":
							_fail("%s: a boss floor wishes %s, not nobody-knocked-out" % [where, str(w)])
						if not w.is_empty():
							seen[String(w["id"])] = int(seen.get(String(w["id"]), 0)) + 1
	for id in Wishes.KINDS:
		if int(seen.get(id, 0)) == 0:
			_fail("the %s wish never comes up" % id)
	var avg_ms := float(pick_us) / 1000.0 / maxf(1.0, float(floors))
	if avg_ms > 1.0:
		_fail("picking a wish takes %.2f ms a floor (want < 1 ms)" % avg_ms)
	print("WISH: %d floors, wishes %s, %.3f ms a pick" % [floors, str(seen), avg_ms])
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)
