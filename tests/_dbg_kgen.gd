extends SceneTree
const TrackGen := preload("res://games/kart_race/trackgen.gd")
const Track := preload("res://games/kart_race/track.gd")
const Seeded := preload("res://core/seeded.gd")
func _init() -> void:
	var spec := {"palette": 0, "size": 0.5, "twist": 0.6, "hills": 3.5, "ramps": 0, "pads": 0, "rows": 0, "splits": 0}
	for sd in 6:
		var info := TrackGen._attempt(Seeded.rng(sd, "track0"), sd, spec)
		if info.is_empty():
			print(sd, " empty ", TrackGen.last_fail)
			continue
		var t := Track.new()
		t.prepare(info)
		var rad := TrackGen.radii(t)
		var out := []
		for i in range(0, t.n, 4):
			out.append("%d:%d" % [int(t.cum[i]), int(rad[i])])
		print(sd, " L=", int(t.length), " ", TrackGen.check(info))
		print("   ", " ".join(out))
		var cp := []
		for p in info.pts:
			cp.append("(%d,%d)" % [p[0], p[1]])
		print("   ", " ".join(cp))
	quit()
