extends SceneTree
## DUO ARENA dinosaurs: "fewer dinosaurs" (Simon 2026-11-19; David found them in the way, Nathanael still wants them).
## Pins main.gd DINO_SHARE and what it does: the share of wave monsters that are dinos (counting raptor packs as bodies)
## is clearly lower than the old mix but never zero, raptor packs and the DINO STAMPEDE herd are smaller, dinos charge
## less often, and the KING REX boss is untouched.
##   godot-test --headless --path . -s res://tests/duo_arena_dino_test.gd
## Prints "SCRIPT ERROR: ..." per failure and "BOT RESULT: PASS|FAIL".

const Main := preload("res://games/duo_arena/main.gd")

var fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		push_error("SCRIPT ERROR: duo_arena_dino_test: " + what)


## Share of spawned bodies that are dinos at wave `w` over `n` picks.
func _dino_body_share(w: int, simple: bool, share: float, n: int) -> float:
	var bodies := 0
	var dinos := 0
	for i in n:
		var k := Main.pick_kind_for(w, simple, share)
		var count := Main.raptor_pack(share) if k == "raptor" else 1
		bodies += count
		if Main.is_small_dino(k):
			dinos += count
	return float(dinos) / float(bodies)


func _initialize() -> void:
	seed(1119)
	_check(is_equal_approx(Main.DINO_SHARE, 0.4), "DINO_SHARE is %.2f, pinned at 0.40 (Simon: fewer dinosaurs)" % Main.DINO_SHARE)
	_check(Main.is_small_dino("dino") and Main.is_small_dino("raptor") and Main.is_small_dino("ptero")
		and Main.is_small_dino("ankylo"), "dino, raptor, ptero, ankylo count as dinos")
	_check(not Main.is_small_dino("rex") and not Main.is_small_dino("grunt"), "rex (boss) and grunt are not wave dinos")
	for simple in [true, false]:
		for w in [3, 7, 11, 15]:
			var before := _dino_body_share(w, simple, 1.0, 20000)
			var after := _dino_body_share(w, simple, Main.DINO_SHARE, 20000)
			print("wave %d %s: dino bodies %.0f%% -> %.0f%%" % [w, "simple" if simple else "full", before * 100.0, after * 100.0])
			_check(after > 0.02, "wave %d: still some dinos for Nathanael (%.1f%%)" % [w, after * 100.0])
			_check(after <= before * 0.6 + 0.01, "wave %d: dinos clearly fewer (%.1f%% -> %.1f%%)" % [w, before * 100.0, after * 100.0])
			_check(after <= 0.25, "wave %d: dinos at most a quarter of the monsters (%.1f%%)" % [w, after * 100.0])
	_check(Main.raptor_pack(1.0) == 3 and Main.raptor_pack() == 2, "raptor pack 3 -> %d" % Main.raptor_pack())
	_check(Main.stampede_size(4) == 2 and Main.stampede_size(5) == 2, "stampede herd 4/5 -> %d/%d" % [Main.stampede_size(4), Main.stampede_size(5)])
	_check(Main.stampede_size(4, 1.0) == 4, "old mix keeps the full herd")
	_check(is_equal_approx(Main.dino_charge_gap(1.0), 5.0) and Main.dino_charge_gap() >= 7.5, "dino charge gap 5 s -> %.1f s" % Main.dino_charge_gap())
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(1 if fails else 0)
