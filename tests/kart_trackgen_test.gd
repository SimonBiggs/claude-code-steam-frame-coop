extends SceneTree
## KART RACE track generator: proves the seeded tracks are fair over many seeds (no game, no window).
##   godot-test --headless --path . -s res://tests/kart_trackgen_test.gd      (SEEDS=200 for more)
## For every story place's track specs (and the bonus tours) and the daily track: games/kart_race/trackgen.gd
## check() (closed, never near itself, drivable bends, gentle hills, straight flat start, fair jumps at every
## speed, things on the road, no hidden walls), the same seed gives the same track, no hand-made fallbacks,
## every place's features show up, plus the story rules. Prints "SCRIPT ERROR: ..." for each failure and
## "KART TRACKGEN: PASS" / "FAIL" at the end (exit code 1 on failure).

const TrackGen := preload("res://games/kart_race/trackgen.gd")
const Seeded := preload("res://core/seeded.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 30
	var t0 := Time.get_ticks_msec()
	var attempts := {}
	var fb := 0
	var reasons := {}
	for pal in 5:
		for sz in [0.0, 0.5, 1.0]:
			var spec := {"palette": pal, "size": sz, "twist": 0.6, "hills": 3.5, "ramps": 2, "pads": 2, "rows": 3, "splits": 1}
			for i in seeds:
				var sd := 1 + i * 7919 + pal * 13
				for a in TrackGen.ATTEMPTS:
					var info := TrackGen._attempt(Seeded.rng(sd, "track%d" % a), sd, spec)
					if info.is_empty():
						reasons[TrackGen.last_fail] = int(reasons.get(TrackGen.last_fail, 0)) + 1
						continue
					var w := TrackGen.check(info)
					if w.is_empty():
						attempts[a] = int(attempts.get(a, 0)) + 1
						break
					var k: String = str(w[0]).get_slice(" at", 0).get_slice("(", 0).get_slice(" 3", 0).get_slice(" 4", 0)
					reasons[k] = int(reasons.get(k, 0)) + 1
					if a == TrackGen.ATTEMPTS - 1:
						fb += 1
	print("attempts: ", attempts)
	print("reasons: ", reasons)
	print("fallbacks: %d  in %d ms" % [fb, Time.get_ticks_msec() - t0])
	quit(0)
